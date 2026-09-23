`timescale 1ns/1ps
`default_nettype none

// Run one test per simulation: +TEST=empty_full, +TEST=almost_flags or +TEST=simultaneous.
// Stimulus changes on falling clock edges, so the FIFO samples stable inputs on rising edges.
module tb_async_fifo #(
    parameter WIDTH     = 8,
    parameter DEPTH     = 16,
    parameter AF_THRESH = 12,
    parameter AE_THRESH = 4
);

    // Clocks, reset and DUT ports; reset is asserted from time 0
    reg wr_clk = 0, rd_clk = 0;
    reg rst_n = 0;
    reg wr_en = 0, rd_en = 0;
    reg [WIDTH-1:0] wr_data = 0;
    wire [WIDTH-1:0] rd_data;
    wire full, empty, almost_full, almost_empty;

    // Clock periods in ns; test_simultaneous changes them
    real wr_period = 10.0;
    real rd_period = 17.0;

    // Scoreboard state
    integer errors = 0;                         // errors from every check
    integer write_count = 0;                    // writes accepted since reset
    integer read_count = 0;                     // reads checked since reset
    reg [WIDTH-1:0] expected [0:2*DEPTH-1];     // accepted write data, used as a circular buffer
    reg read_pending = 0;                       // a read was accepted on the previous rd_clk edge

    // Free-running clocks
    always #(wr_period/2.0) wr_clk = ~wr_clk;
    always #(rd_period/2.0) rd_clk = ~rd_clk;

    async_fifo_top #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .AF_THRESH(AF_THRESH),
        .AE_THRESH(AE_THRESH)
    ) dut (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .wr_data(wr_data),
        .rd_data(rd_data),
        .almost_full(almost_full),
        .full(full),
        .almost_empty(almost_empty),
        .empty(empty)
    );

    // Record accepted writes and check returned data.

    // Write side: store the data of every write the FIFO accepts
    always @(posedge wr_clk) begin
        if (!rst_n)
            write_count <= 0;
        else if (wr_en && !full) begin
            expected[write_count % (2*DEPTH)] <= wr_data;
            write_count <= write_count + 1;
        end
    end

    // Read side: rd_data is valid one rd_clk edge after an accepted read,
    // so compare it with the oldest stored word on the following edge
    always @(posedge rd_clk) begin
        if (!rst_n) begin
            read_count  <= 0;
            read_pending <= 0;
        end else begin
            if (read_pending) begin
                if (read_count >= write_count) begin    // nothing was written for this read
                    errors = errors + 1;
                    $error("Read occurred with no expected data");
                end else if (rd_data !== expected[read_count % (2*DEPTH)]) begin
                    errors = errors + 1;
                    $error("Read data mismatch: got %0h expected %0h",
                           rd_data, expected[read_count % (2*DEPTH)]);
                end
                read_count <= read_count + 1;
            end
            read_pending <= rd_en && !empty;            // read accepted on this edge
        end
    end

    // Compare a value with its expected value and count a mismatch
    task check(input string name, input logic actual, input logic expected_value);
        if (actual !== expected_value) begin
            errors = errors + 1;
            $error("%s: expected %b, got %b", name, expected_value, actual);
        end
    endtask

    // Wait for pointers to cross both clock domains so the flags are current.
    // The flags lag by three edges; four is the minimum that works.
    task settle;
        fork
            repeat (4) @(posedge wr_clk);
            repeat (4) @(posedge rd_clk);
        join
    endtask

    // Hold reset for 4 cycles of each clock, release it on a falling wr_clk edge, then settle
    task reset_fifo;
        begin
            wr_en = 0;
            rd_en = 0;
            rst_n = 0;
            repeat (4) @(posedge wr_clk);
            repeat (4) @(posedge rd_clk);
            @(negedge wr_clk);
            rst_n = 1;
            settle;
        end
    endtask

    // Request one write for one wr_clk cycle; the FIFO ignores it if full
    task write_one(input [WIDTH-1:0] data);
        begin
            @(negedge wr_clk);
            wr_data = data;
            wr_en = 1;
            @(negedge wr_clk);
            wr_en = 0;
        end
    endtask

    // Request one read for one rd_clk cycle; the FIFO ignores it if empty
    task read_one;
        begin
            @(negedge rd_clk);
            rd_en = 1;
            @(negedge rd_clk);
            rd_en = 0;
        end
    endtask

    // Write DEPTH words, one at a time
    task fill_fifo;
        integer i;
        begin
            for (i = 0; i < DEPTH; i = i + 1)
                write_one(i);
            settle;
        end
    endtask

    // Read DEPTH words, one at a time
    task drain_fifo;
        integer i;
        begin
            for (i = 0; i < DEPTH; i = i + 1)
                read_one;
            settle;
        end
    endtask

    // 1. Empty -> filled and full -> empty.
    task test_empty_full;
        begin
            reset_fifo;

            check("empty after reset", empty, 1);
            fill_fifo;
            check("full after fill", full, 1);

            drain_fifo;
            check("empty after drain", empty, 1);

            // One more word: empty must clear, then return after it is read
            write_one(8'hA5);
            settle;
            check("empty clears after write", empty, 0);

            read_one;
            settle;
            check("empty returns after read", empty, 1);
        end
    endtask

    // 2. Check almost-full and almost-empty boundaries.
    task test_almost_flags;
        integer i;
        begin
            reset_fifo;

            // almost_full: one word below, at, then back below AF_THRESH
            for (i = 0; i < AF_THRESH - 1; i = i + 1)
                write_one(i);
            settle;
            check("almost_full below threshold", almost_full, 0);

            write_one(AF_THRESH);
            settle;
            check("almost_full at threshold", almost_full, 1);

            read_one;
            settle;
            check("almost_full clears", almost_full, 0);

            reset_fifo;

            // almost_empty: one word above, at, then back above AE_THRESH
            for (i = 0; i <= AE_THRESH; i = i + 1)
                write_one(i);
            settle;
            check("almost_empty above threshold", almost_empty, 0);

            read_one;
            settle;
            check("almost_empty at threshold", almost_empty, 1);

            write_one(8'h5A);
            settle;
            check("almost_empty clears", almost_empty, 0);
        end
    endtask

    // Write n words back to back, holding each word until the FIFO accepts it
    task write_burst(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge wr_clk);
                wr_data = i;
                wr_en = 1;
                @(posedge wr_clk);
                while (full) @(posedge wr_clk);     // blocked by full: retry on the next edge
            end
            @(negedge wr_clk);
            wr_en = 0;
        end
    endtask

    // Read n words back to back, retrying while the FIFO is empty
    task read_burst(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge rd_clk);
                rd_en = 1;
                @(posedge rd_clk);
                while (empty) @(posedge rd_clk);    // blocked by empty: retry on the next edge
            end
            @(negedge rd_clk);
            rd_en = 0;
        end
    endtask

    // 3. Simultaneous traffic with different clock frequencies.
    task test_simultaneous;
        begin
            reset_fifo;
            wr_period = 7.0;                // unrelated periods, write clock faster
            rd_period = 13.0;

            fork
                write_burst(64);
                read_burst(64);
            join

            settle;
            check("empty after simultaneous read/write", empty, 1);
        end
    endtask

    // Read +TEST, dump waves, run the test, then report the result
    initial begin : main
        string test;

        if (!$value$plusargs("TEST=%s", test)) begin
            $display("Usage: ./simv +TEST=empty_full|almost_flags|simultaneous");
            $finish;
        end

        $fsdbDumpfile("async_fifo.fsdb");
        $fsdbDumpvars(0, tb_async_fifo);

        case (test)
            "empty_full":  test_empty_full;
            "almost_flags": test_almost_flags;
            "simultaneous": test_simultaneous;
            default: begin
                $error("Unknown TEST=%s", test);
                $finish;
            end
        endcase

        settle;                             // let the last read's data check finish

        if (errors == 0)
            $display("TEST PASSED: %s", test);
        else
            $error("TEST FAILED: %s (%0d errors)", test, errors);

        $finish;
    end

    // Fail the run if a test hangs for 100 us
    initial begin
        #100000;
        $error("TEST FAILED: timeout");
        $finish;
    end

endmodule

`default_nettype wire
