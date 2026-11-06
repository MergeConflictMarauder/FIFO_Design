
`timescale 1ns/1ps
`default_nettype none

// One parity FIFO as seen by the interleaver.
interface parity_fifo_if #(
    parameter int WIDTH = 8
);

    logic             wr_en;
    logic             rd_en;
    logic [WIDTH-1:0] rd_data;
    logic             empty;

    modport fifo (
        input  wr_en, rd_en,
        output rd_data, empty
    );

endinterface


// Asynchronous FIFO attached to a parity_fifo_if.
module parity_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 64
)(
    input  logic             wr_clk,
    input  logic             rd_clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] wr_data,
    parity_fifo_if.fifo      fifo_if
);

    async_fifo_top #(
        .WIDTH     (WIDTH),
        .DEPTH     (DEPTH),
        .AF_THRESH (DEPTH),
        .AE_THRESH (0)
    ) u_fifo (
        .wr_en        (fifo_if.wr_en),
        .rd_en        (fifo_if.rd_en),
        .rd_data      (fifo_if.rd_data),
        .empty        (fifo_if.empty),
        .full         (),
        .almost_full  (),
        .almost_empty (),
        .*
    );

endmodule


// Even/odd FIFO interleaver.
module even_odd_interleaver_top #(
    parameter int WIDTH      = 8,
    parameter int FIFO_DEPTH = 64,
    parameter bit FIRST_EVEN = 1'b1
)(
    input  logic             wr_clk,
    input  logic             rd_clk,
    input  logic             rst_n,
    input  logic             wr_en,
    input  logic             rd_en,
    input  logic [WIDTH-1:0] wr_data,

    output logic [WIDTH-1:0] rd_data,
    output logic             rd_valid
);

    // Independently synchronize reset release.
    logic rst_n_wr, rst_n_rd;

    sync_reset u_rst_wr (
        .clk       (wr_clk),
        .rst_n_in  (rst_n),
        .rst_n_out (rst_n_wr)
    );

    sync_reset u_rst_rd (
        .clk       (rd_clk),
        .rst_n_in  (rst_n),
        .rst_n_out (rst_n_rd)
    );

    // Even and odd FIFO interfaces.
    parity_fifo_if #(.WIDTH(WIDTH)) even_if ();
    parity_fifo_if #(.WIDTH(WIDTH)) odd_if ();

    parity_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (FIFO_DEPTH)
    ) u_even_fifo (
        .fifo_if (even_if),
        .*
    );

    parity_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (FIFO_DEPTH)
    ) u_odd_fifo (
        .fifo_if (odd_if),
        .*
    );

    // Write data to the appropriate parity FIFO.
    assign even_if.wr_en = rst_n_wr && wr_en && !wr_data[0];
    assign odd_if.wr_en  = rst_n_wr && wr_en &&  wr_data[0];

    // Read controller state.
    logic next_is_even;
    logic pending;
    logic pending_is_even;
    logic issue_read;


    // ============================================
    // LAB 4 PART 4 - SIMULATION FAULT INJECTION
    // ============================================

`ifndef SYNTHESIS

    bit inject_sva_bug;

    initial begin
        inject_sva_bug = $test$plusargs("INJECT_SVA_BUG");

        if (inject_sva_bug)
            $display("SVA INJECTED BUG: corrupting rd_valid");
    end

`endif

    // ============================================
    // READ SELECTION
    // ============================================

    // Do not skip parity if the selected FIFO is empty.
    assign issue_read = rst_n_rd && rd_en &&
                        (next_is_even ?
                         !even_if.empty :
                         !odd_if.empty);

    assign even_if.rd_en = issue_read &&  next_is_even;
    assign odd_if.rd_en  = issue_read && !next_is_even;


    // ============================================
    // SEQUENTIAL READ CONTROL
    // ============================================

    always_ff @(posedge rd_clk or negedge rst_n_rd) begin

        if (!rst_n_rd) begin

            next_is_even    <= FIRST_EVEN;
            pending         <= 1'b0;
            pending_is_even <= FIRST_EVEN;

            rd_data         <= '0;
            rd_valid        <= 1'b0;

        end
        else begin

            // Normal operation:
            // rd_valid follows pending.
            //
            // Fault injection:
            // Invert rd_valid to trigger assertion A7.

`ifdef SYNTHESIS

            rd_valid <= pending;

`else

            rd_valid <= inject_sva_bug ? !pending : pending;

`endif

            // Register the data from the selected FIFO.
            if (pending) begin

                if (pending_is_even)
                    rd_data <= even_if.rd_data;
                else
                    rd_data <= odd_if.rd_data;

            end

            // Track accepted read operations.
            pending <= issue_read;

            // Alternate parity after accepted reads.
            if (issue_read) begin

                pending_is_even <= next_is_even;
                next_is_even    <= !next_is_even;

            end

        end

    end

endmodule

`default_nettype wire

