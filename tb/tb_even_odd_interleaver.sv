`timescale 1ns/1ps
`default_nettype none

// Testbench for even_odd_interleaver_top.
// Run one Case-9 timing pattern per simulation:
//   +TEST=case1       Case 1: writes at the start of each 100-cycle block
//   +TEST=case4       Case 4: 160 back-to-back writes, the case used to size the FIFOs
//   +TEST=case4_odd   Case 4 timing with the long burst on the odd FIFO instead
//
// Case 9 has equal write and read frequencies, so both clocks share one period.
// The read clock is offset in phase to keep the two domains asynchronous.
module tb_even_odd_interleaver #(
    parameter WIDTH      = 8,
    parameter FIFO_DEPTH = 64
);

    localparam TOTAL_WRITES = 160;
    localparam real CLK_PERIOD = 10.0;      // ns, both clocks
    localparam real RD_PHASE   = 3.0;       // ns, read clock starts later

    // DUT ports; names match even_odd_interleaver_top, so it connects with .*
    reg              wr_clk  = 0;
    reg              rd_clk  = 0;
    reg              rst_n   = 0;
    reg              wr_en   = 0;
    reg              rd_en   = 0;
    reg  [WIDTH-1:0] wr_data = 0;
    wire [WIDTH-1:0] rd_data;
    wire             rd_valid;

    integer errors = 0;

    // Scoreboard: the two FIFOs preserve order independently.
    reg [WIDTH-1:0] expected_even [0:TOTAL_WRITES-1];
    reg [WIDTH-1:0] expected_odd  [0:TOTAL_WRITES-1];

    integer even_written = 0;               // writes accepted by each FIFO
    integer odd_written  = 0;
    integer even_issued  = 0;               // reads issued to each FIFO
    integer odd_issued   = 0;
    integer even_read    = 0;               // words checked at the output
    integer odd_read     = 0;
    integer total_read   = 0;

    integer peak_even = 0;                  // highest occupancy of each FIFO
    integer peak_odd  = 0;

    reg [WIDTH-1:0] last_rd_data      = 0;
    reg             last_parity_valid = 0;
    reg             last_parity       = 0;

    // Clocks: same frequency, read clock offset in phase
    always #(CLK_PERIOD/2.0) wr_clk = ~wr_clk;

    initial begin
        #(RD_PHASE);
        forever #(CLK_PERIOD/2.0) rd_clk = ~rd_clk;
    end

    even_odd_interleaver_top #(
        .WIDTH      (WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) dut (.*);

    // Write side: record each accepted input and track FIFO occupancy.
    // A write while the target FIFO is full would be dropped, so it is an error.
    always @(posedge wr_clk) begin
        if (!rst_n) begin
            even_written = 0;
            odd_written  = 0;
            peak_even    = 0;
            peak_odd     = 0;
        end
        else begin
            if (wr_en) begin
                if (!wr_data[0]) begin
                    if (dut.u_even_fifo.u_fifo.full) begin
                        errors = errors + 1;
                        $error("Even FIFO overflow at time %0t", $time);
                    end
                    else begin
                        expected_even[even_written] = wr_data;
                        even_written = even_written + 1;
                    end
                end
                else begin
                    if (dut.u_odd_fifo.u_fifo.full) begin
                        errors = errors + 1;
                        $error("Odd FIFO overflow at time %0t", $time);
                    end
                    else begin
                        expected_odd[odd_written] = wr_data;
                        odd_written = odd_written + 1;
                    end
                end
            end

            // Occupancy = accepted writes - issued reads
            if (even_written - even_issued > peak_even)
                peak_even = even_written - even_issued;
            if (odd_written - odd_issued > peak_odd)
                peak_odd = odd_written - odd_issued;
        end
    end

    // Read side: count issued reads and check every output word.
    // rd_data is a new word exactly when rd_valid is high.
    always @(posedge rd_clk) begin
        if (!rst_n) begin
            even_issued       = 0;
            odd_issued        = 0;
            even_read         = 0;
            odd_read          = 0;
            total_read        = 0;
            last_rd_data      = 0;
            last_parity_valid = 0;
            last_parity       = 0;
        end
        else begin
            // The DUT issues a read only when the selected FIFO is not empty
            if (dut.even_if.rd_en)
                even_issued = even_issued + 1;
            if (dut.odd_if.rd_en)
                odd_issued = odd_issued + 1;

            if (rd_valid) begin
                if (!rd_data[0]) begin
                    if (even_read >= even_written) begin
                        errors = errors + 1;
                        $error("Even output with no expected even data");
                    end
                    else if (rd_data !== expected_even[even_read]) begin
                        errors = errors + 1;
                        $error("Even data mismatch: got %0h expected %0h",
                               rd_data, expected_even[even_read]);
                    end
                    even_read = even_read + 1;
                end
                else begin
                    if (odd_read >= odd_written) begin
                        errors = errors + 1;
                        $error("Odd output with no expected odd data");
                    end
                    else if (rd_data !== expected_odd[odd_read]) begin
                        errors = errors + 1;
                        $error("Odd data mismatch: got %0h expected %0h",
                               rd_data, expected_odd[odd_read]);
                    end
                    odd_read = odd_read + 1;
                end

                // The generated input data never contains zero, so a zero
                // here would be an inserted/invalid output.
                if (rd_data === '0) begin
                    errors = errors + 1;
                    $error("Invalid zero output at time %0t", $time);
                end

                // The first output is even, and parity alternates after that.
                if (!last_parity_valid && rd_data[0] !== 1'b0) begin
                    errors = errors + 1;
                    $error("First output is not even at time %0t", $time);
                end
                if (last_parity_valid && rd_data[0] === last_parity) begin
                    errors = errors + 1;
                    $error("Output parity did not alternate at time %0t", $time);
                end

                last_parity       = rd_data[0];
                last_parity_valid = 1;
                last_rd_data      = rd_data;
                total_read        = total_read + 1;
            end
            else if (rd_data !== last_rd_data) begin
                // Without rd_valid the output must hold, including while the
                // controller waits for the required parity.
                errors = errors + 1;
                $error("rd_data changed without rd_valid at time %0t", $time);
            end
        end
    end

    // Compare two integers and count a mismatch
    task check_int(input string name, input integer actual, input integer expected);
        begin
            if (actual != expected) begin
                errors = errors + 1;
                $error("%s: expected %0d, got %0d", name, expected, actual);
            end
        end
    endtask

    // Hold reset for 4 cycles of each clock, release it on a falling write-clock
    // edge, and wait until both reset synchronisers in the DUT have released.
    task reset_dut;
        begin
            wr_en   = 0;
            rd_en   = 0;
            wr_data = 0;
            rst_n   = 0;
            repeat (4) @(posedge wr_clk);
            repeat (4) @(posedge rd_clk);
            @(negedge wr_clk);
            rst_n = 1;
            repeat (4) @(posedge wr_clk);
            repeat (4) @(posedge rd_clk);
        end
    endtask

    // Drive exactly one 200-cycle Case-9 write pattern on the write clock.
    // pattern = 1: Case 1 from the FIFO-depth document.
    // pattern = 4: Case 4, arranged to create 80 consecutive EVEN writes.
    // pattern = 5: Case 4 timing, arranged to create 80 consecutive ODD writes.
    task drive_writes(input integer pattern);
        integer cycle;
        integer writes_in_block;
        integer even_in_block;
        integer odd_in_block;
        integer value;
        integer do_write;
        begin
            writes_in_block = 0;
            even_in_block   = 0;
            odd_in_block    = 0;

            for (cycle = 0; cycle < 200; cycle = cycle + 1) begin
                @(negedge wr_clk);

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
                        value = cycle - 39;             // 120->81, 199->160
                    end
                end
                else if (pattern == 4) begin
                    // Case 4: IDLE 0..19, WRITE 20..179, IDLE 180..199.
                    // Parity ordering creates the worst-case EVEN burst:
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
                    // Symmetry test: same Case-4 write timing, but create
                    // 80 consecutive ODD writes across the block boundary.
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

                wr_en   = do_write;
                wr_data = value[WIDTH-1:0];

                if (do_write) begin
                    writes_in_block = writes_in_block + 1;
                    if (value[0])
                        odd_in_block = odd_in_block + 1;
                    else
                        even_in_block = even_in_block + 1;
                end

                // Verify the testbench itself meets the required write rate.
                if ((cycle % 100) == 99) begin
                    check_int("writes per 100 cycles", writes_in_block, 80);
                    check_int("even writes per 100 cycles", even_in_block, 40);
                    check_int("odd writes per 100 cycles", odd_in_block, 40);
                    writes_in_block = 0;
                    even_in_block   = 0;
                    odd_in_block    = 0;
                end
            end

            @(negedge wr_clk);
            wr_en   = 0;
            wr_data = 0;
        end
    endtask

    // Request reads 8 times per 10 read-clock cycles (two idle cycles, then
    // eight request cycles) until all 160 items have appeared at the output.
    task drive_reads;
        integer cycle;
        integer reads_in_ten;
        begin
            cycle        = 0;
            reads_in_ten = 0;

            while (total_read < TOTAL_WRITES && cycle < 600) begin
                @(negedge rd_clk);
                rd_en = ((cycle % 10) >= 2);
                if (rd_en)
                    reads_in_ten = reads_in_ten + 1;

                // Verify the testbench itself meets the required read rate.
                if ((cycle % 10) == 9) begin
                    check_int("read requests per 10 cycles", reads_in_ten, 8);
                    reads_in_ten = 0;
                end
                cycle = cycle + 1;
            end

            @(negedge rd_clk);
            rd_en = 0;

            if (total_read != TOTAL_WRITES) begin
                errors = errors + 1;
                $error("Drain timeout: only %0d/%0d outputs observed",
                       total_read, TOTAL_WRITES);
            end

            repeat (4) @(posedge rd_clk);
        end
    endtask

    // Reset, then run the write pattern and the read requests at the same time
    task run_case(input integer pattern);
        begin
            reset_dut;
            fork
                drive_writes(pattern);
                drive_reads;
            join
        end
    endtask

    // Every input must come out, in order, and both FIFOs must end empty
    task finish_checks;
        begin
            check_int("total even writes", even_written, 80);
            check_int("total odd writes",  odd_written,  80);
            check_int("total even reads",  even_read,    80);
            check_int("total odd reads",   odd_read,     80);
            check_int("total outputs",     total_read,   160);
            check_int("even words left in FIFO", even_written - even_issued, 0);
            check_int("odd words left in FIFO",  odd_written  - odd_issued,  0);
        end
    endtask

    task test_case1;
        begin
            run_case(1);
            finish_checks;
        end
    endtask

    // Case 4 is the sizing case: 80 even writes against 32 even reads, so the
    // even FIFO must reach at least 48 words without overflowing.
    task test_case4;
        begin
            run_case(4);
            finish_checks;
            if (peak_even < 48) begin
                errors = errors + 1;
                $error("Case 4 did not reach the sizing peak: even peak %0d < 48", peak_even);
            end
        end
    endtask

    // Symmetry stress: the odd FIFO now sees the 80-word burst.
    task test_case4_odd;
        begin
            run_case(5);
            finish_checks;
            if (peak_odd < 48) begin
                errors = errors + 1;
                $error("Case 4 odd burst did not reach the sizing peak: odd peak %0d < 48", peak_odd);
            end
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

        $display("Peak occupancy: even=%0d odd=%0d (FIFO depth %0d)",
                 peak_even, peak_odd, FIFO_DEPTH);
        $finish;
    end

    initial begin
        #100000;
        $error("TEST FAILED: timeout");
        $finish;
    end

endmodule

`default_nettype wire
