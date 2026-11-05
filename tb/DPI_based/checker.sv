// Import the C functions using DPI (C++ reference model in model.cpp)
import "DPI-C" function void fifo_init(int fifo_depth, int fifo_width);
import "DPI-C" function void fifo_push(int data);
import "DPI-C" function int  fifo_pop();
import "DPI-C" function int  fifo_is_empty();
import "DPI-C" function int  fifo_is_full();

`timescale 1ns/1ps

/////////////////////
// Checks async_fifo_top against the C++ model. Accepted operations update the
// model on their clock edges; read data is checked one rd_clk edge later.
// Full and empty are checked on every wr_clk and rd_clk edge, respectively.
//////////////////////
module fifo_checker #(parameter int WIDTH = 8, parameter int DEPTH = 16)
                     (input wr_clk, input rd_clk, input rst_n,
                      input wr_en, input logic [WIDTH-1:0] wr_data, input full,
                      input rd_en, input logic [WIDTH-1:0] rd_data, input empty);

    // Allow four clock edges for synchronized flags to update. Ignore temporary
    // pessimistic mismatches; fail immediately on optimistic mismatches that could
    // permit overflow or underflow.
    localparam int FLAG_LAG = 4;

    // Checker state, visible in the waveform under u_checker
    int               errors    = 0;    // mismatches found, also used by the testbench
    int               writes    = 0;    // writes the DUT accepted (pushed into the model)
    int               reads     = 0;    // read data words compared with the model
    bit               exp_full;         // model full flag on the last wr_clk edge
    bit               exp_empty;        // model empty flag on the last rd_clk edge
    int               full_lag  = 0;    // wr_clk edges in a row on which full  disagrees with the model
    int               empty_lag = 0;    // rd_clk edges in a row on which empty disagrees with the model
    bit               rd_check  = 0;    // a read was accepted on the previous rd_clk edge
    logic [WIDTH-1:0] rd_expect;        // the word the model returned for that read

    // Check if a flag mismatch is an error, depending on how long it has lasted.
    function automatic bit flag_error(input logic actual, input bit expected, input int lag);
        if (actual === 1'b1 && expected == 1'b0)
            return lag == FLAG_LAG + 1;     // pessimistic: an error once it lasts too long
        else
            return lag == 1;                // optimistic, or X: an error at once
    endfunction

    // Write side
    always begin
        @(posedge wr_clk);
        if (!rst_n) begin
            fifo_init(DEPTH, WIDTH);    // empty the model while the DUT is in reset
            full_lag = 0;
        end else begin
            // 1. Compare full with the model, before this edge's write is added
            exp_full = fifo_is_full();
            full_lag = (full === exp_full) ? 0 : full_lag + 1;
            if (flag_error(full, exp_full, full_lag)) begin
                errors = errors + 1;
                $error("[%.1f ns] full mismatch: expected %0d, actual %b, for %0d wr_clk edges",
                       $realtime, exp_full, full, full_lag);
            end

            // 2. Copy every write the DUT accepts into the model
            if (wr_en && !full) begin
                fifo_push(wr_data);
                writes = writes + 1;
            end
        end
    end

    // Read side
    always begin
        @(posedge rd_clk);
        if (!rst_n) begin
            rd_check  = 0;
            empty_lag = 0;
        end else begin
            // 1. Check data from the read accepted on the previous rd_clk edge.
            if (rd_check) begin
                reads = reads + 1;
                if (rd_data !== rd_expect) begin
                    errors = errors + 1;
                    $error("[%.1f ns] rd_data mismatch: expected 0x%0h, actual 0x%0h",
                           $realtime, rd_expect, rd_data);
                end
            end

            // 2. Compare empty with the model, before this edge's read is removed
            exp_empty = fifo_is_empty();
            empty_lag = (empty === exp_empty) ? 0 : empty_lag + 1;
            if (flag_error(empty, exp_empty, empty_lag)) begin
                errors = errors + 1;
                $error("[%.1f ns] empty mismatch: expected %0d, actual %b, for %0d rd_clk edges",
                       $realtime, exp_empty, empty, empty_lag);
            end

            // 3. Take a word from the model for every read the DUT accepts
            rd_check = rd_en && !empty;
            if (rd_check)
                rd_expect = fifo_pop();
        end
    end

    final begin     // Pass/fail summary at the end of the simulation
        if (errors == 0)
            $display("CHECKER PASSED: %0d writes, %0d reads checked, 0 errors", writes, reads);
        else
            $display("CHECKER FAILED: %0d writes, %0d reads checked, %0d errors", writes, reads, errors);
    end

endmodule
