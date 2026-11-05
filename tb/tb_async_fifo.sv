`timescale 1ns/1ps
`default_nettype none

// SV-class scoreboard classes, in tb/SV_based (the interfaces are in fifo_if.sv)
`include "transaction.sv"
`include "monitor.sv"
`include "scoreboard.sv"

// Run one test per simulation: +TEST=empty_full, +TEST=almost_flags or +TEST=simultaneous.
// Add +INJECT_BUG to make the DUT drop every Nth write.
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

    integer errors = 0;                         // errors from the flag checks in the tests

    // Free-running clocks
    always #(wr_period/2.0) wr_clk = ~wr_clk;
    always #(rd_period/2.0) rd_clk = ~rd_clk;

    // Write-side and read-side interfaces
    fifo_wr_if wr_if_inst(wr_clk, rst_n);
    fifo_rd_if rd_if_inst(rd_clk, rst_n);

    // The DUT is connected through the interfaces
    async_fifo_top #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .AF_THRESH(AF_THRESH),
        .AE_THRESH(AE_THRESH)
    ) dut (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk),
        .rst_n(rst_n),
        .wr_en(wr_if_inst.wr_en),
        .wr_data(wr_if_inst.wr_data),
        .full(wr_if_inst.full),
        .almost_full(wr_if_inst.almost_full),
        .rd_en(rd_if_inst.rd_en),
        .rd_data(rd_if_inst.rd_data),
        .empty(rd_if_inst.empty),
        .almost_empty(rd_if_inst.almost_empty)
    );

    // The stimulus drives these testbench signals into the interfaces...
    assign wr_if_inst.wr_en   = wr_en;
    assign wr_if_inst.wr_data = wr_data;
    assign rd_if_inst.rd_en   = rd_en;

    // ...and the tests and the DPI checker read the DUT outputs from them
    assign full         = wr_if_inst.full;
    assign almost_full  = wr_if_inst.almost_full;
    assign rd_data      = rd_if_inst.rd_data;
    assign empty        = rd_if_inst.empty;
    assign almost_empty = rd_if_inst.almost_empty;

    // SV-class scoreboard: the monitor posts transactions to the mailbox,
    // the scoreboard checks them against its queue model (tb/SV_based)
    mailbox #(transaction) txn_mail;
    monitor mon;
    scoreboard sb;

    initial begin
        mon = new(wr_if_inst, rd_if_inst);
        sb = new(DEPTH);
        txn_mail = new();
        mon.txn_mail = txn_mail;
        sb.txn_mail = txn_mail;
        fork
            mon.run();
            sb.run();
        join
    end

    // Print the scoreboard's pass/fail summary at the end of the simulation
    final if (sb != null) sb.report();

    // Scoreboard: checks every accepted write and read, and the full and empty flags,
    // against the C++ reference model (tb/DPI_based/checker.sv, tb/DPI_based/model.cpp)
    fifo_checker #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) u_checker (.*);

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

            // Overflow attempt: the FIFO must ignore this write
            write_one(8'hEE);

            drain_fifo;
            check("empty after drain", empty, 1);

            // Underflow attempt: the FIFO must ignore this read
            read_one;

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

        if (errors + u_checker.errors + sb.errors == 0)
            $display("TEST PASSED: %s", test);
        else
            $error("TEST FAILED: %s (%0d errors)", test, errors + u_checker.errors + sb.errors);

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
