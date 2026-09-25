`timescale 1ns/1ps
`default_nettype none

// Part II testbench.
// Run one Case-9 timing pattern per simulation:
//   +TEST=case1
//   +TEST=case4
// Optional symmetry stress test:
//   +TEST=case4_odd
//
// Every 100-cycle input block contains exactly 80 writes:
// 40 even and 40 odd.  read_en is asserted exactly 8 times per 10 cycles.
module tb_even_odd_interleaver #(
    parameter WIDTH      = 8,
    parameter FIFO_DEPTH = 64
);

    localparam TOTAL_WRITES = 160;

    reg clk = 0;
    reg rst_n = 0;
    reg [WIDTH-1:0] data_in = 0;
    reg write_en = 0;
    reg read_en = 0;

    wire [WIDTH-1:0] data_out;

    integer errors = 0;

    // Scoreboard: the two FIFOs preserve order independently.
    reg [WIDTH-1:0] expected_even [0:TOTAL_WRITES-1];
    reg [WIDTH-1:0] expected_odd  [0:TOTAL_WRITES-1];

    integer even_written = 0;
    integer odd_written  = 0;
    integer even_read    = 0;
    integer odd_read     = 0;
    integer total_read   = 0;

    integer peak_even = 0;
    integer peak_odd  = 0;

    reg [WIDTH-1:0] last_data_out = 0;
    reg             last_parity_valid = 0;
    reg             last_parity = 0;

    // Sample pre-edge transaction controls, then check data after NBA updates.
    reg fire_sample;
    reg even_sample;
    reg odd_sample;
    reg stall_sample;

    always #5 clk = ~clk;

    even_odd_interleaver #(
        .WIDTH      (WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .data_in  (data_in),
        .write_en (write_en),
        .data_out (data_out),
        .read_en  (read_en)
    );

    // ---------------------------------------------------------------------
    // Scoreboard and protocol checks
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            even_written      = 0;
            odd_written       = 0;
            even_read         = 0;
            odd_read          = 0;
            total_read        = 0;
            peak_even         = 0;
            peak_odd          = 0;
            last_data_out     = '0;
            last_parity_valid = 0;
            last_parity       = 0;
        end
        else begin
            fire_sample = dut.read_fire;
            even_sample = dut.even_rd_en;
            odd_sample  = dut.odd_rd_en;
            stall_sample = read_en && !dut.read_fire;

            // Record each accepted input.  FIFO overflow is a test failure.
            if (write_en) begin
                if (!data_in[0]) begin
                    if (dut.even_full && !dut.even_rd_en) begin
                        errors = errors + 1;
                        $error("Even FIFO overflow attempt at time %0t", $time);
                    end
                    else begin
                        expected_even[even_written] = data_in;
                        even_written = even_written + 1;
                    end
                end
                else begin
                    if (dut.odd_full && !dut.odd_rd_en) begin
                        errors = errors + 1;
                        $error("Odd FIFO overflow attempt at time %0t", $time);
                    end
                    else begin
                        expected_odd[odd_written] = data_in;
                        odd_written = odd_written + 1;
                    end
                end
            end

            // Wait until the DUT's nonblocking assignments update data_out
            // and the FIFO occupancy counters.
            #1;

            if (dut.even_count > peak_even)
                peak_even = dut.even_count;
            if (dut.odd_count > peak_odd)
                peak_odd = dut.odd_count;

            // Check every successful output transaction.
            if (fire_sample) begin
                if (even_sample) begin
                    if (even_read >= even_written) begin
                        errors = errors + 1;
                        $error("Even read occurred with no expected even data");
                    end
                    else if (data_out !== expected_even[even_read]) begin
                        errors = errors + 1;
                        $error("Even data mismatch: got %0h expected %0h",
                               data_out, expected_even[even_read]);
                    end
                    even_read = even_read + 1;
                end
                else if (odd_sample) begin
                    if (odd_read >= odd_written) begin
                        errors = errors + 1;
                        $error("Odd read occurred with no expected odd data");
                    end
                    else if (data_out !== expected_odd[odd_read]) begin
                        errors = errors + 1;
                        $error("Odd data mismatch: got %0h expected %0h",
                               data_out, expected_odd[odd_read]);
                    end
                    odd_read = odd_read + 1;
                end
                else begin
                    errors = errors + 1;
                    $error("read_fire asserted without an even/odd source");
                end

                // The generated input data intentionally never contains zero.
                // Therefore a zero here would be an inserted/invalid output.
                if (data_out === '0) begin
                    errors = errors + 1;
                    $error("Invalid zero output at time %0t", $time);
                end

                // Output parity must alternate on every successful transfer.
                if (last_parity_valid && data_out[0] === last_parity) begin
                    errors = errors + 1;
                    $error("Output parity did not alternate at time %0t", $time);
                end

                last_parity       = data_out[0];
                last_parity_valid = 1;
                total_read        = total_read + 1;
            end
            else if (stall_sample) begin
                // When the required FIFO is empty, the circuit must pause.
                // data_out therefore holds its previous value instead of
                // producing a new zero/invalid transaction.
                if (data_out !== last_data_out) begin
                    errors = errors + 1;
                    $error("data_out changed while the controller was stalled");
                end
            end

            last_data_out = data_out;
        end
    end

    task check_int(input string name, input integer actual, input integer expected);
        begin
            if (actual != expected) begin
                errors = errors + 1;
                $error("%s: expected %0d, got %0d", name, expected, actual);
            end
        end
    endtask

    // Hold reset low and release on a falling clock edge.
    task reset_dut;
        begin
            write_en = 0;
            read_en  = 0;
            data_in  = 0;
            rst_n    = 0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1;
        end
    endtask

    // Drive exactly one 200-cycle Case-9 pattern.
    // pattern = 1: Case 1 from the FIFO-depth document.
    // pattern = 4: Case 4, arranged to create 80 consecutive EVEN writes.
    // pattern = 5: Case 4 timing, arranged to create 80 consecutive ODD writes.
    task drive_case(input integer pattern);
        integer cycle;
        integer writes_in_block;
        integer even_in_block;
        integer odd_in_block;
        integer reads_in_ten;
        integer value;
        integer do_write;
        begin
            writes_in_block = 0;
            even_in_block   = 0;
            odd_in_block    = 0;
            reads_in_ten    = 0;

            for (cycle = 0; cycle < 200; cycle = cycle + 1) begin
                @(negedge clk);

                // Exactly 8 read requests in every 10 cycles:
                // two idle cycles followed by eight request cycles.
                read_en = ((cycle % 10) >= 2);
                if (read_en)
                    reads_in_ten = reads_in_ten + 1;

                do_write = 0;
                value    = 1;

                if (pattern == 1) begin
                    // Case 1: WRITE 0..79, IDLE 80..119, WRITE 120..199.
                    // Values 1..80 and 81..160 contain 40 even + 40 odd
                    // in each 100-cycle block.
                    if (cycle < 80) begin
                        do_write = 1;
                        value = cycle + 1;
                    end
                    else if (cycle >= 120) begin
                        do_write = 1;
                        value = cycle - 39;       // 120->81, 199->160
                    end
                end
                else if (pattern == 4) begin
                    // Case 4: IDLE 0..19, WRITE 20..179, IDLE 180..199.
                    // Parity ordering creates the legal worst-case EVEN burst:
                    // 40 odd, 40 even | 40 even, 40 odd.
                    if (cycle >= 20 && cycle < 60) begin
                        do_write = 1;
                        value = 2*(cycle-20) + 1;       // odd 1..79
                    end
                    else if (cycle >= 60 && cycle < 100) begin
                        do_write = 1;
                        value = 2*(cycle-60) + 2;       // even 2..80
                    end
                    else if (cycle >= 100 && cycle < 140) begin
                        do_write = 1;
                        value = 2*(cycle-100) + 82;     // even 82..160
                    end
                    else if (cycle >= 140 && cycle < 180) begin
                        do_write = 1;
                        value = 2*(cycle-140) + 81;     // odd 81..159
                    end
                end
                else begin
                    // Optional symmetry test: same Case-4 write timing, but
                    // create 80 consecutive ODD writes across the boundary.
                    if (cycle >= 20 && cycle < 60) begin
                        do_write = 1;
                        value = 2*(cycle-20) + 2;       // even 2..80
                    end
                    else if (cycle >= 60 && cycle < 100) begin
                        do_write = 1;
                        value = 2*(cycle-60) + 1;       // odd 1..79
                    end
                    else if (cycle >= 100 && cycle < 140) begin
                        do_write = 1;
                        value = 2*(cycle-100) + 81;     // odd 81..159
                    end
                    else if (cycle >= 140 && cycle < 180) begin
                        do_write = 1;
                        value = 2*(cycle-140) + 82;     // even 82..160
                    end
                end

                write_en = do_write;
                data_in  = value[WIDTH-1:0];

                if (do_write) begin
                    writes_in_block = writes_in_block + 1;
                    if (value[0])
                        odd_in_block = odd_in_block + 1;
                    else
                        even_in_block = even_in_block + 1;
                end

                // Verify the testbench itself satisfies the required rates.
                if ((cycle % 10) == 9) begin
                    check_int("read requests per 10 cycles", reads_in_ten, 8);
                    reads_in_ten = 0;
                end

                if ((cycle % 100) == 99) begin
                    check_int("writes per 100 cycles", writes_in_block, 80);
                    check_int("even writes per 100 cycles", even_in_block, 40);
                    check_int("odd writes per 100 cycles", odd_in_block, 40);
                    writes_in_block = 0;
                    even_in_block   = 0;
                    odd_in_block    = 0;
                end
            end

            @(negedge clk);
            write_en = 0;
            data_in  = 0;
        end
    endtask

    // Continue requesting reads at the required 8/10 rate until all 160
    // input items have appeared at the output.
    task drain_output;
        integer cycle;
        begin
            cycle = 200;
            while (total_read < TOTAL_WRITES && cycle < 600) begin
                @(negedge clk);
                read_en = ((cycle % 10) >= 2);
                cycle = cycle + 1;
            end

            @(negedge clk);
            read_en = 0;

            if (total_read != TOTAL_WRITES) begin
                errors = errors + 1;
                $error("Drain timeout: only %0d/%0d outputs observed",
                       total_read, TOTAL_WRITES);
            end

            repeat (2) @(posedge clk);
        end
    endtask

    task finish_checks;
        begin
            check_int("total even writes", even_written, 80);
            check_int("total odd writes",  odd_written,  80);
            check_int("total even reads",  even_read,     80);
            check_int("total odd reads",   odd_read,      80);
            check_int("total outputs",     total_read,   160);
            check_int("final even FIFO occupancy", dut.even_count, 0);
            check_int("final odd FIFO occupancy",  dut.odd_count,  0);
        end
    endtask

    task test_case1;
        begin
            reset_dut;
            drive_case(1);
            drain_output;
            finish_checks;

            // Exact peak for this deterministic Case-1 stimulus/read phase.
            check_int("Case 1 peak even occupancy", peak_even, 8);
            check_int("Case 1 peak odd occupancy",  peak_odd,  8);
        end
    endtask

    task test_case4;
        begin
            reset_dut;
            drive_case(4);
            drain_output;
            finish_checks;

            // Exact result for the worst-case same-parity burst used for
            // sizing: 80 even writes - 32 even reads = 48 entries.
            check_int("Case 4 peak even occupancy", peak_even, 48);
            check_int("Case 4 peak odd occupancy",  peak_odd,  40);
        end
    endtask

    task test_case4_odd;
        begin
            reset_dut;
            drive_case(5);
            drain_output;
            finish_checks;

            // Symmetry stress: the odd FIFO now sees the 80-word burst.
            check_int("Case 4 odd-burst peak occupancy", peak_odd, 48);
        end
    endtask

    initial begin : main
        string test;

        if (!$value$plusargs("TEST=%s", test)) begin
            $display("Usage: ./simv_part2 +TEST=case1|case4|case4_odd");
            $finish;
        end

        $fsdbDumpfile("even_odd_interleaver.fsdb");
        $fsdbDumpvars(0, tb_even_odd_interleaver);

        case (test)
            "case1":     test_case1;
            "case4":     test_case4;
            "case4_odd": test_case4_odd;
            default: begin
                $error("Unknown TEST=%s", test);
                $finish;
            end
        endcase

        if (errors == 0)
            $display("TEST PASSED: %s", test);
        else
            $error("TEST FAILED: %s (%0d errors)", test, errors);

        $display("Peak occupancy: even=%0d odd=%0d", peak_even, peak_odd);
        $finish;
    end

    initial begin
        #100000;
        $error("TEST FAILED: timeout");
        $finish;
    end

endmodule

`default_nettype wire
