`timescale 1ns/1ps
`default_nettype none

// Asynchronous FIFO with independent write and read clocks
module async_fifo_top #(
    parameter int WIDTH     = 8,
    parameter int DEPTH     = 16,
    parameter int AF_THRESH = 12,
    parameter int AE_THRESH = 4
)(
    input  logic              wr_clk,
    input  logic              rd_clk,
    input  logic              rst_n,
    input  logic              wr_en,
    input  logic              rd_en,
    input  logic [WIDTH-1:0]  wr_data,

    output logic [WIDTH-1:0]  rd_data,
    output logic              almost_full,
    output logic              full,
    output logic              almost_empty,
    output logic              empty
);

    localparam int ADDR_WIDTH = $clog2(DEPTH);
    localparam int PTR_WIDTH  = ADDR_WIDTH + 1;

    // Parameter checks
    initial begin
        if (DEPTH < 2 || DEPTH != (1 << ADDR_WIDTH))
            $error("async_fifo_top: DEPTH (%0d) must be a power of two, >= 2", DEPTH);
        if (AF_THRESH < 1 || AF_THRESH > DEPTH)
            $error("async_fifo_top: AF_THRESH (%0d) must be in 1..DEPTH", AF_THRESH);
        if (AE_THRESH < 0 || AE_THRESH >= DEPTH)
            $error("async_fifo_top: AE_THRESH (%0d) must be in 0..DEPTH-1", AE_THRESH);
    end

    // Reset synchronization
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

    // Write and read pointers
    logic [PTR_WIDTH-1:0] wr_to_gray, wr_from_gray;
    logic [PTR_WIDTH-1:0] rd_to_gray, rd_from_gray;

    logic [ADDR_WIDTH-1:0] wr_addr, rd_addr;
    logic                  wr_en_gate, rd_en_gate;

    // Write-side control
    write_handler #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .AF_THRESH  (AF_THRESH)
    ) u_wr (
        .clk        (wr_clk),
        .rst_n      (rst_n_wr),
        .enable     (wr_en),
        .read_ptr   (rd_from_gray),
        .wr_en      (wr_en_gate),
        .is_full    (full),
        .is_almost  (almost_full),
        .*
    );

    // Read-side control
    read_handler #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .AE_THRESH  (AE_THRESH)
    ) u_rd (
        .clk        (rd_clk),
        .rst_n      (rst_n_rd),
        .enable     (rd_en),
        .write_ptr  (wr_from_gray),
        .rd_en      (rd_en_gate),
        .is_empty   (empty),
        .is_almost  (almost_empty),
        .*
    );

    // Write pointer into read domain
    sync_clock #(
        .PTR_WIDTH (PTR_WIDTH)
    ) u_sync_wr2rd (
        .clk         (rd_clk),
        .rst_n       (rst_n_rd),
        .ptr_gray_in (wr_to_gray),
        .ptr_bin_out (wr_from_gray)
    );

    // Read pointer into write domain
    sync_clock #(
        .PTR_WIDTH (PTR_WIDTH)
    ) u_sync_rd2wr (
        .clk         (wr_clk),
        .rst_n       (rst_n_wr),
        .ptr_gray_in (rd_to_gray),
        .ptr_bin_out (rd_from_gray)
    );

    // Interface between FIFO control logic and memory
    dual_port_mem_if #(
        .WIDTH      (WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) mem_if();

    assign mem_if.wr_en   = wr_en_gate;
    assign mem_if.rd_en   = rd_en_gate;
    assign mem_if.wr_addr = wr_addr;
    assign mem_if.rd_addr = rd_addr;
    assign mem_if.wr_data = wr_data;

    assign rd_data = mem_if.rd_data;

    // Dual-port memory
    dual_port_memory #(
        .WIDTH      (WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_mem (
        .mem_if (mem_if),
        .*
    );

endmodule

`default_nettype wire
