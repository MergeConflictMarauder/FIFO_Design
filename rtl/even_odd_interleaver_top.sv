`timescale 1ns/1ps
`default_nettype none

// One parity FIFO as seen by the interleaver
interface parity_fifo_if #(
    parameter int WIDTH = 8             // data word width
);

    logic             wr_en;            // write strobe, from the parity routing
    logic             rd_en;            // read strobe, from the read controller
    logic [WIDTH-1:0] rd_data;          // valid the rd_clk cycle after rd_en
    logic             empty;

    // FIFO side: takes the strobes, returns read data and the empty flag.
    // The interleaver owns the interface instances and drives them directly.
    modport fifo (
        input  wr_en, rd_en,
        output rd_data, empty
    );

endinterface

// Asynchronous FIFO attached to a parity_fifo_if. The interleaver only needs
// the empty flag, so the full and almost flags are left unconnected.
module parity_fifo #(
    parameter int WIDTH = 8,            // data word width
    parameter int DEPTH = 64            // entries, must be a power of two
)(
    input  logic             wr_clk,
    input  logic             rd_clk,
    input  logic             rst_n,     // asynchronous, active low
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
        .*                              // wr_clk, rd_clk, rst_n, wr_data
    );

endmodule

// Alternates values from independent even and odd asynchronous FIFOs.
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

    // Reset release is synchronised independently for the write and read logic.
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

    // Even and odd FIFOs, each reached through its own interface
    parity_fifo_if #(.WIDTH(WIDTH)) even_if ();
    parity_fifo_if #(.WIDTH(WIDTH)) odd_if ();

    parity_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (FIFO_DEPTH)
    ) u_even_fifo (
        .fifo_if (even_if),
        .*                              // wr_clk, rd_clk, rst_n, wr_data
    );

    parity_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (FIFO_DEPTH)
    ) u_odd_fifo (
        .fifo_if (odd_if),
        .*                              // wr_clk, rd_clk, rst_n, wr_data
    );

    // A value is written to exactly one FIFO according to its least-significant bit.
    assign even_if.wr_en = rst_n_wr && wr_en && !wr_data[0];
    assign odd_if.wr_en  = rst_n_wr && wr_en &&  wr_data[0];

    // Strict round-robin control: do not skip the required parity.  If the
    // selected FIFO is empty, hold the state until that parity arrives.
    logic next_is_even;
    logic pending;
    logic pending_is_even;
    logic issue_read;

    assign issue_read    = rst_n_rd && rd_en &&
                           (next_is_even ? !even_if.empty : !odd_if.empty);
    assign even_if.rd_en = issue_read &&  next_is_even;
    assign odd_if.rd_en  = issue_read && !next_is_even;

    // Each FIFO has a synchronous read port.  Remember the selected FIFO for
    // one rd_clk cycle, then register its returned word and mark it valid.
    always_ff @(posedge rd_clk or negedge rst_n_rd) begin
        if (!rst_n_rd) begin
            next_is_even    <= FIRST_EVEN;
            pending         <= 1'b0;
            pending_is_even <= FIRST_EVEN;
            rd_data         <= '0;
            rd_valid        <= 1'b0;
        end
        else begin
            rd_valid <= pending;

            if (pending) begin
                if (pending_is_even)
                    rd_data <= even_if.rd_data;
                else
                    rd_data <= odd_if.rd_data;
            end

            pending <= issue_read;

            if (issue_read) begin
                pending_is_even <= next_is_even;
                next_is_even    <= !next_is_even;
            end
        end
    end

endmodule

`default_nettype wire
