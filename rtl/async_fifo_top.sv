`timescale 1ns/1ps
`default_nettype none

// Asynchronous FIFO with independent write and read clocks
module async_fifo_top #(
    parameter int WIDTH     = 8,    // data word width
    parameter int DEPTH     = 16,   // entries, must be a power of two
    parameter int AF_THRESH = 12,   // almost_full  asserts at >= this occupancy
    parameter int AE_THRESH = 4     // almost_empty asserts at <= this occupancy
)(
    input  logic              wr_clk,
    input  logic              rd_clk,
    input  logic              rst_n,            // asynchronous, active low
    input  logic              wr_en,
    input  logic              rd_en,
    input  logic [WIDTH-1:0]  wr_data,

    output logic [WIDTH-1:0]  rd_data,
    output logic              almost_full,
    output logic              full,
    output logic              almost_empty,
    output logic              empty
);

    localparam int ADDR_WIDTH = $clog2(DEPTH);      // ceiling of log2(DEPTH), address width
    localparam int PTR_WIDTH  = ADDR_WIDTH + 1;     // pointer width, to distinguish full from empty

    // Elaboration-time parameter checks
    initial begin
        if (DEPTH < 2 || DEPTH != (1 << ADDR_WIDTH))
            $error("async_fifo_top: DEPTH (%0d) must be a power of two, >= 2", DEPTH);
        if (AF_THRESH < 1 || AF_THRESH > DEPTH)
            $error("async_fifo_top: AF_THRESH (%0d) must be in 1..DEPTH", AF_THRESH);
        if (AE_THRESH < 0 || AE_THRESH >= DEPTH)
            $error("async_fifo_top: AE_THRESH (%0d) must be in 0..DEPTH-1", AE_THRESH);
    end

    // Reset synchronisers for the two clock domains
    // The FIFO is reset when rst_n is low, and comes out of reset synchronously to each clock
    logic rst_n_wr, rst_n_rd;

    sync_reset u_rst_wr (.clk(wr_clk), .rst_n_in(rst_n), .rst_n_out(rst_n_wr));
    sync_reset u_rst_rd (.clk(rd_clk), .rst_n_in(rst_n), .rst_n_out(rst_n_rd));

    // Write and read pointers, Gray-coded for the CDC
    // The write pointer is synchronised into the read domain and vice versa
    logic [PTR_WIDTH-1:0] wr_to_gray,  wr_ptr_sync;
    logic [PTR_WIDTH-1:0] rd_to_gray,  rd_ptr_sync;

    // The read and write addresses are the lower bits of the pointers,
    // which are one bit wider than the address to distinguish full from empty
    logic [ADDR_WIDTH-1:0] wr_addr, rd_addr;
    logic                  wr_en_gate, rd_en_gate;
    logic [PTR_WIDTH-1:0]  num_content_w, num_content_r;

    write_handler #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .AF_THRESH  (AF_THRESH)
    ) u_wr (
        .clk         (wr_clk),
        .rst_n       (rst_n_wr),
        .enable      (wr_en),
        .read_ptr    (rd_ptr_sync),     // from the read domain
        .wr_en       (wr_en_gate),
        .is_full     (full),
        .is_almost   (almost_full),
        .wr_addr     (wr_addr),
        .num_content (num_content_w),
        .wr_to_gray  (wr_to_gray)       // to the read domain
    );

    read_handler #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .AE_THRESH  (AE_THRESH)
    ) u_rd (
        .clk         (rd_clk),
        .rst_n       (rst_n_rd),
        .enable      (rd_en),
        .write_ptr   (wr_ptr_sync),     // from the write domain
        .rd_en       (rd_en_gate),
        .is_empty    (empty),
        .is_almost   (almost_empty),
        .rd_addr     (rd_addr),
        .num_content (num_content_r),
        .rd_to_gray  (rd_to_gray)       // to the write domain
    );

    // Write pointer into the read domain.
    sync_clock #(
        .PTR_WIDTH  (PTR_WIDTH)
    ) u_sync_wr2rd (
        .clk         (rd_clk),
        .rst_n       (rst_n_rd),
        .ptr_gray_in (wr_to_gray),
        .ptr_bin_out (wr_ptr_sync)
    );

    // Read pointer into the write domain.
    sync_clock #(
        .PTR_WIDTH  (PTR_WIDTH)
    ) u_sync_rd2wr (
        .clk         (wr_clk),
        .rst_n       (rst_n_wr),
        .ptr_gray_in (rd_to_gray),
        .ptr_bin_out (rd_ptr_sync)
    );

    dual_port_memory #(
        .WIDTH      (WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_mem (
        .wr_clk  (wr_clk),
        .rd_clk  (rd_clk),
        .wr_en   (wr_en_gate),
        .rd_en   (rd_en_gate),
        .wr_addr (wr_addr),
        .rd_addr (rd_addr),
        .wr_data (wr_data),
        .rd_data (rd_data)
    );

endmodule

`default_nettype wire
