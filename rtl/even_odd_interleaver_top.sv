`timescale 1ns/1ps
`default_nettype none

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

    // A value is written to exactly one FIFO according to its least-significant bit.
    logic even_wr_en, odd_wr_en;
    logic even_rd_en, odd_rd_en;
    logic [WIDTH-1:0] even_rd_data, odd_rd_data;
    logic even_empty, odd_empty;

    assign even_wr_en = rst_n_wr && wr_en && !wr_data[0];
    assign odd_wr_en  = rst_n_wr && wr_en &&  wr_data[0];

    async_fifo_top #(
        .WIDTH     (WIDTH),
        .DEPTH     (FIFO_DEPTH),
        .AF_THRESH (FIFO_DEPTH),
        .AE_THRESH (0)
    ) u_even_fifo (
        .wr_clk       (wr_clk),
        .rd_clk       (rd_clk),
        .rst_n        (rst_n),
        .wr_en        (even_wr_en),
        .rd_en        (even_rd_en),
        .wr_data      (wr_data),
        .rd_data      (even_rd_data),
        .almost_full  (),
        .full         (),
        .almost_empty (),
        .empty        (even_empty)
    );

    async_fifo_top #(
        .WIDTH     (WIDTH),
        .DEPTH     (FIFO_DEPTH),
        .AF_THRESH (FIFO_DEPTH),
        .AE_THRESH (0)
    ) u_odd_fifo (
        .wr_clk       (wr_clk),
        .rd_clk       (rd_clk),
        .rst_n        (rst_n),
        .wr_en        (odd_wr_en),
        .rd_en        (odd_rd_en),
        .wr_data      (wr_data),
        .rd_data      (odd_rd_data),
        .almost_full  (),
        .full         (),
        .almost_empty (),
        .empty        (odd_empty)
    );

    // Strict round-robin control: do not skip the required parity.  If the
    // selected FIFO is empty, hold the state until that parity arrives.
    logic next_is_even;
    logic pending;
    logic pending_is_even;
    logic issue_read;

    assign issue_read = rst_n_rd && rd_en &&
                        (next_is_even ? !even_empty : !odd_empty);
    assign even_rd_en = issue_read &&  next_is_even;
    assign odd_rd_en  = issue_read && !next_is_even;

    // Each FIFO has a synchronous read port.  Remember the selected FIFO for
    // one rd_clk cycle, then register its returned word and mark it valid.
    always_ff @(posedge rd_clk or negedge rst_n_rd) begin
        if (!rst_n_rd) begin
            next_is_even  <= FIRST_EVEN;
            pending       <= 1'b0;
            pending_is_even <= FIRST_EVEN;
            rd_data       <= '0;
            rd_valid      <= 1'b0;
        end
        else begin
            rd_valid <= pending;

            if (pending) begin
                if (pending_is_even)
                    rd_data <= even_rd_data;
                else
                    rd_data <= odd_rd_data;
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
