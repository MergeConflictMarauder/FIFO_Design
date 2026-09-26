`timescale 1ns/1ps
`default_nettype none

// End-to-end verification for the even/odd interleaver.
//
// The testbench defines four 100-write-clock-cycle traffic frames.  Every
// frame has exactly 80 writes: 40 even values and 40 odd values.  The first
// two frames form the clustered traffic pattern used for the FIFO-depth
// calculation:
//
//   frame 1: 20 idle, 40 even, 40 odd
//   frame 2: 40 odd,  40 even, 20 idle
//
// Frames 3 and 4 reverse the parity order to exercise the same buildup in the
// even FIFO.  The consumer requests reads for eight of every ten rd_clk
// cycles.  A request is not necessarily an output: rd_valid identifies an
// actual output transfer.
module tb_even_odd_interleaver #(
    parameter int WIDTH      = 8,
    parameter int FIFO_DEPTH = 64
);

    localparam int FRAME_CYCLES = 100;
    localparam int MAX_EXPECTED = 1024;

    // Same-frequency clocks, intentionally phase-shifted to exercise the
    // asynchronous FIFO clock-domain crossing.
    logic wr_clk = 1'b0;
    logic rd_clk = 1'b0;
    logic rst_n  = 1'b0;

    logic             wr_en   = 1'b0;
    logic             rd_en   = 1'b0;
    logic [WIDTH-1:0] wr_data = '0;
    logic [WIDTH-1:0] rd_data;
    logic             rd_valid;

    // Source-side expected queues.  They intentionally model the two FIFO
    // streams separately, because global input order is not preserved by an
    // even/odd interleaver; order within each parity stream must be preserved.
    logic [WIDTH-1:0] expected_even [0:MAX_EXPECTED-1];
    logic [WIDTH-1:0] expected_odd  [0:MAX_EXPECTED-1];
    integer even_head;
    integer even_tail;
    integer odd_head;
    integer odd_tail;

    integer total_writes_seen;
    integer even_writes_seen;
    integer odd_writes_seen;
    integer output_count;
    integer errors;
    integer expected_total_writes;
    integer expected_frames;
    logic   expect_even_next;

    // Write-rate monitor state.  frame_active is asserted by the stimulus at
    // the same falling edge that drives the first value of a 100-cycle frame.
    logic   frame_active = 1'b0;
    integer frame_cycles_seen;
    integer frame_writes_seen;
    integer frame_even_seen;
    integer frame_odd_seen;
    integer completed_frames;

    // Read-rate monitor state.
    logic   start_reads = 1'b0;
    logic   stop_reads  = 1'b0;
    logic   read_driver_active = 1'b0;
    integer read_cycles_seen;
    integer read_requests_seen;

    logic scoreboard_active = 1'b0;
    // Keep every generated payload nonzero.  That makes a zero on a valid
    // output unequivocally erroneous in addition to being a data mismatch.
    logic [WIDTH-1:0] next_even_data = WIDTH'(2);
    logic [WIDTH-1:0] next_odd_data  = {{(WIDTH-1){1'b0}}, 1'b1};

    // 10 ns periods; rd_clk is offset by 2.5 ns from wr_clk.
    always #5 wr_clk = ~wr_clk;
    initial begin
        #2.5;
        forever #5 rd_clk = ~rd_clk;
    end

    even_odd_interleaver_top #(
        .WIDTH      (WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) dut (
        .wr_clk   (wr_clk),
        .rd_clk   (rd_clk),
        .rst_n    (rst_n),
        .wr_en    (wr_en),
        .rd_en    (rd_en),
        .wr_data  (wr_data),
        .rd_data  (rd_data),
        .rd_valid (rd_valid)
    );

    // Continuously generate the required read-request rate after reset.
    // A complete 10-cycle group is checked independently below.
    initial begin : read_request_driver
        integer cycle_in_group;

        rd_en = 1'b0;
        cycle_in_group = 0;
        wait (start_reads);

        while (!stop_reads) begin
            @(negedge rd_clk);
            if (!stop_reads) begin
                rd_en = (cycle_in_group < 8);
                read_driver_active = 1'b1;
                cycle_in_group = cycle_in_group + 1;
                if (cycle_in_group == 10)
                    cycle_in_group = 0;
            end
        end

        rd_en = 1'b0;
        read_driver_active = 1'b0;
    end

    // Record all producer requests in their respective expected queues.
    // The chosen depth and traffic are intended to avoid FIFO overflow, so
    // every wr_en request must eventually appear at the interleaver output.
    always @(posedge wr_clk) begin
        if (!rst_n) begin
            even_tail         = 0;
            odd_tail          = 0;
            total_writes_seen = 0;
            even_writes_seen  = 0;
            odd_writes_seen   = 0;
        end
        else if (wr_en) begin
            if (wr_data[0]) begin
                expected_odd[odd_tail % MAX_EXPECTED] = wr_data;
                odd_tail = odd_tail + 1;
                odd_writes_seen = odd_writes_seen + 1;
            end
            else begin
                expected_even[even_tail % MAX_EXPECTED] = wr_data;
                even_tail = even_tail + 1;
                even_writes_seen = even_writes_seen + 1;
            end
            total_writes_seen = total_writes_seen + 1;
        end
    end

    // Check that each active producer frame has exactly the required traffic.
    always @(posedge wr_clk) begin
        integer writes_after_edge;
        integer evens_after_edge;
        integer odds_after_edge;

        if (!rst_n) begin
            frame_cycles_seen = 0;
            frame_writes_seen = 0;
            frame_even_seen   = 0;
            frame_odd_seen    = 0;
            completed_frames  = 0;
        end
        else if (frame_active) begin
            writes_after_edge = frame_writes_seen + (wr_en ? 1 : 0);
            evens_after_edge  = frame_even_seen + ((wr_en && !wr_data[0]) ? 1 : 0);
            odds_after_edge   = frame_odd_seen + ((wr_en &&  wr_data[0]) ? 1 : 0);

            if (frame_cycles_seen == FRAME_CYCLES - 1) begin
                if (writes_after_edge != 80) begin
                    errors = errors + 1;
                    $error("Write-rate violation: frame %0d has %0d writes, expected 80",
                           completed_frames + 1, writes_after_edge);
                end
                if (evens_after_edge != 40 || odds_after_edge != 40) begin
                    errors = errors + 1;
                    $error("Parity-rate violation: frame %0d has %0d evens and %0d odds, expected 40/40",
                           completed_frames + 1, evens_after_edge, odds_after_edge);
                end

                completed_frames  = completed_frames + 1;
                frame_active      = 1'b0;
                frame_cycles_seen = 0;
                frame_writes_seen = 0;
                frame_even_seen   = 0;
                frame_odd_seen    = 0;
            end
            else begin
                frame_cycles_seen = frame_cycles_seen + 1;
                frame_writes_seen = writes_after_edge;
                frame_even_seen   = evens_after_edge;
                frame_odd_seen    = odds_after_edge;
            end
        end
    end

    // Verify that the consumer asks for exactly eight reads in every complete
    // ten-cycle group while the read driver is enabled.
    always @(posedge rd_clk) begin
        integer requests_after_edge;

        if (!rst_n) begin
            read_cycles_seen   = 0;
            read_requests_seen = 0;
        end
        else if (read_driver_active) begin
            requests_after_edge = read_requests_seen + (rd_en ? 1 : 0);

            if (read_cycles_seen == 9) begin
                if (requests_after_edge != 8) begin
                    errors = errors + 1;
                    $error("Read-rate violation: 10-cycle group has %0d requests, expected 8",
                           requests_after_edge);
                end
                read_cycles_seen   = 0;
                read_requests_seen = 0;
            end
            else begin
                read_cycles_seen   = read_cycles_seen + 1;
                read_requests_seen = requests_after_edge;
            end
        end
    end

    // rd_data is meaningful only when rd_valid is asserted.  Sample one ns
    // after the read edge so nonblocking assignments in the DUT have updated.
    always @(posedge rd_clk) begin
        if (rst_n && scoreboard_active) begin
            #1;
            if (rd_valid !== 1'b0 && rd_valid !== 1'b1) begin
                errors = errors + 1;
                $error("rd_valid is unknown");
            end
            else if (rd_valid) begin
                if (rd_data === '0) begin
                    errors = errors + 1;
                    $error("Valid output is zero, but zero was never written");
                end

                // Strict round-robin may read only the selected FIFO.  It
                // must pause when that next required parity is empty rather
                // than skipping it and emitting the other parity again.
                if (expect_even_next) begin
                    if (even_head == even_tail) begin
                        errors = errors + 1;
                        $error("Expected an even output but the expected even queue is empty");
                    end
                    else begin
                        if (rd_data !== expected_even[even_head % MAX_EXPECTED]) begin
                            errors = errors + 1;
                            $error("Even output mismatch: got %0h expected %0h",
                                   rd_data, expected_even[even_head % MAX_EXPECTED]);
                        end
                        even_head = even_head + 1;
                    end
                end
                else begin
                    if (odd_head == odd_tail) begin
                        errors = errors + 1;
                        $error("Expected an odd output but the expected odd queue is empty");
                    end
                    else begin
                        if (rd_data !== expected_odd[odd_head % MAX_EXPECTED]) begin
                            errors = errors + 1;
                            $error("Odd output mismatch: got %0h expected %0h",
                                   rd_data, expected_odd[odd_head % MAX_EXPECTED]);
                        end
                        odd_head = odd_head + 1;
                    end
                end

                expect_even_next = ~expect_even_next;
                output_count = output_count + 1;
            end
        end
        else if (!rst_n) begin
            even_head        = 0;
            odd_head         = 0;
            output_count     = 0;
            expect_even_next = 1'b1;      // specified first output parity
        end
    end

    // Drive one 100-cycle clustered input frame.  No deassertion is performed
    // here, allowing the next frame to begin on the immediately following
    // write cycle with no unintended gap between frames.
    task drive_clustered_frame(input integer pattern);
        integer cycle;
        logic   write_this_cycle;
        logic   even_this_cycle;
        begin
            for (cycle = 0; cycle < FRAME_CYCLES; cycle = cycle + 1) begin
                @(negedge wr_clk);

                write_this_cycle = 1'b0;
                even_this_cycle  = 1'b0;
                case (pattern)
                    // 20 idle, 40 even, 40 odd
                    1: begin
                        write_this_cycle = (cycle >= 20);
                        even_this_cycle  = (cycle >= 20 && cycle < 60);
                    end
                    // 40 odd, 40 even, 20 idle
                    2: begin
                        write_this_cycle = (cycle < 80);
                        even_this_cycle  = (cycle >= 40 && cycle < 80);
                    end
                    // 20 idle, 40 odd, 40 even
                    3: begin
                        write_this_cycle = (cycle >= 20);
                        even_this_cycle  = (cycle >= 60);
                    end
                    // 40 even, 40 odd, 20 idle
                    4: begin
                        write_this_cycle = (cycle < 80);
                        even_this_cycle  = (cycle < 40);
                    end
                    default: begin
                        errors = errors + 1;
                        $error("Unknown clustered pattern %0d", pattern);
                    end
                endcase

                if (cycle == 0)
                    frame_active = 1'b1;

                wr_en = write_this_cycle;
                if (write_this_cycle) begin
                    if (even_this_cycle) begin
                        wr_data = next_even_data;
                        next_even_data = next_even_data + 2;
                    end
                    else begin
                        wr_data = next_odd_data;
                        next_odd_data = next_odd_data + 2;
                    end
                end
            end
        end
    endtask

    // Drive one 100-cycle frame with 80 already-alternating writes.  The
    // start offset selects whether the 20 idle cycles appear at the end or
    // the beginning of the frame; first_even selects the first written parity.
    task drive_alternating_frame(
        input integer write_start_cycle,
        input logic   first_even
    );
        integer cycle;
        integer write_index;
        logic   write_this_cycle;
        logic   even_this_cycle;
        begin
            for (cycle = 0; cycle < FRAME_CYCLES; cycle = cycle + 1) begin
                @(negedge wr_clk);

                write_this_cycle = (cycle >= write_start_cycle &&
                                    cycle < write_start_cycle + 80);
                write_index = cycle - write_start_cycle;
                even_this_cycle = first_even ? !write_index[0] : write_index[0];

                if (cycle == 0)
                    frame_active = 1'b1;

                wr_en = write_this_cycle;
                if (write_this_cycle) begin
                    if (even_this_cycle) begin
                        wr_data = next_even_data;
                        next_even_data = next_even_data + 2;
                    end
                    else begin
                        wr_data = next_odd_data;
                        next_odd_data = next_odd_data + 2;
                    end
                end
            end
        end
    endtask

    task reset_dut;
        begin
            wr_en = 1'b0;
            rd_en = 1'b0;
            rst_n = 1'b0;

            // Reset is synchronized internally to both clock domains.
            fork
                repeat (4) @(posedge wr_clk);
                repeat (4) @(posedge rd_clk);
            join

            @(negedge wr_clk);
            rst_n = 1'b1;

            // Allow reset synchronizers and FIFO pointer synchronizers to
            // settle before traffic begins.
            fork
                repeat (8) @(posedge wr_clk);
                repeat (8) @(posedge rd_clk);
            join
        end
    endtask

    task wait_for_drain(input integer expected_words);
        integer cycles_waited;
        begin
            cycles_waited = 0;
            while (output_count < expected_words && cycles_waited < 3000) begin
                @(posedge rd_clk);
                cycles_waited = cycles_waited + 1;
            end

            if (output_count != expected_words) begin
                errors = errors + 1;
                $error("Drain timeout: observed %0d outputs, expected %0d",
                       output_count, expected_words);
            end

            // Keep requesting reads briefly after the expected drain.  Any
            // unexpected rd_valid is caught by the scoreboard above.
            repeat (10) @(posedge rd_clk);
        end
    endtask

    initial begin : main
        string test;

        errors = 0;
        even_head = 0;
        even_tail = 0;
        odd_head = 0;
        odd_tail = 0;
        total_writes_seen = 0;
        even_writes_seen = 0;
        odd_writes_seen = 0;
        output_count = 0;
        expect_even_next = 1'b1;

        if (!$value$plusargs("TEST=%s", test))
            test = "sizing";

        if (test != "sizing" && test != "reverse" &&
            test != "alternating" && test != "stall") begin
            $error("Unknown TEST=%s; use +TEST=sizing|reverse|alternating|stall", test);
            $finish;
        end

`ifndef VERILATOR
        $fsdbDumpfile("even_odd_interleaver.fsdb");
        $fsdbDumpvars(0, tb_even_odd_interleaver);
`endif

        reset_dut;
        scoreboard_active = 1'b1;
        start_reads = 1'b1;

        case (test)
            "sizing": begin
                expected_total_writes = 160;
                expected_frames = 2;
                $display("CASE 1: 20 idle, 40 even, 40 odd");
                drive_clustered_frame(1);
                $display("CASE 2: 40 odd, 40 even, 20 idle (FIFO-depth sizing continuation)");
                drive_clustered_frame(2);
            end
            "reverse": begin
                expected_total_writes = 160;
                expected_frames = 2;
                $display("CASE 3: 20 idle, 40 odd, 40 even");
                drive_clustered_frame(3);
                $display("CASE 4: 40 even, 40 odd, 20 idle (parity-reversed continuation)");
                drive_clustered_frame(4);
            end
            "alternating": begin
                expected_total_writes = 160;
                expected_frames = 2;
                $display("ALTERNATING CASE 1: 80 alternating writes, even first");
                drive_alternating_frame(0, 1'b1);
                $display("ALTERNATING CASE 2: 80 alternating writes, odd first");
                drive_alternating_frame(20, 1'b0);
            end
            "stall": begin
                expected_total_writes = 80;
                expected_frames = 1;
                $display("STALL CASE: 20 idle, then 40 even before the first odd");
                drive_clustered_frame(1);
            end
        endcase

        // The last frame's final write is sampled on the next rising edge.
        @(negedge wr_clk);
        wr_en = 1'b0;

        if (completed_frames != expected_frames) begin
            errors = errors + 1;
            $error("Only %0d of %0d input frames completed", completed_frames, expected_frames);
        end
        if (total_writes_seen != expected_total_writes ||
            even_writes_seen != expected_total_writes / 2 ||
            odd_writes_seen != expected_total_writes / 2) begin
            errors = errors + 1;
            $error("Input count mismatch: total=%0d even=%0d odd=%0d; expected %0d/%0d/%0d",
                   total_writes_seen, even_writes_seen, odd_writes_seen,
                   expected_total_writes, expected_total_writes / 2, expected_total_writes / 2);
        end

        wait_for_drain(expected_total_writes);
        stop_reads = 1'b1;
        @(negedge rd_clk);
        repeat (4) @(posedge rd_clk);

        if (even_head != even_tail || odd_head != odd_tail) begin
            errors = errors + 1;
            $error("Expected queues did not drain: even %0d/%0d, odd %0d/%0d",
                   even_head, even_tail, odd_head, odd_tail);
        end
        if (output_count != expected_total_writes) begin
            errors = errors + 1;
            $error("Output count mismatch: got %0d expected %0d",
                   output_count, expected_total_writes);
        end

        if (errors == 0)
            $display("TEST PASSED: %s", test);
        else
            $error("TEST FAILED: %s (%0d errors)", test, errors);

        $finish;
    end

    // Prevent an undetected deadlock from leaving a simulation running.
    initial begin
        #100000;
        $error("TEST FAILED: timeout");
        $finish;
    end

endmodule

`default_nettype wire
