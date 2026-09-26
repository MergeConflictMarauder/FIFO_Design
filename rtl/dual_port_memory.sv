`timescale 1ns/1ps
`default_nettype none

// Signals between the FIFO control logic and the dual-port memory
interface dual_port_mem_if #(
    parameter int WIDTH      = 8,   // data word width
    parameter int ADDR_WIDTH = 4    // address width, 2**ADDR_WIDTH entries
);

    // Write port
    logic                  wr_en;       // gated write strobe
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [WIDTH-1:0]      wr_data;

    // Read port
    logic                  rd_en;       // gated read strobe
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [WIDTH-1:0]      rd_data;     // valid the cycle after rd_en

    // Memory side: receives the requests and write data, drives read data.
    modport memory_side (
        input  wr_en, wr_addr, wr_data,
        input  rd_en, rd_addr,
        output rd_data
    );

endinterface

// One write port, one read port, independent clocks
module dual_port_memory #(
    parameter int WIDTH      = 8,   // data word width
    parameter int ADDR_WIDTH = 4    // address width, 2**ADDR_WIDTH entries
)(
    input  logic                 wr_clk,
    input  logic                 rd_clk,
    dual_port_mem_if.memory_side mem_if
);

    // Left bit-shift operator: 1 << 4 = 2^4 = 16
    localparam int DEPTH = 1 << ADDR_WIDTH;

    // [DEPTH] declares DEPTH entries, addresses 0 to DEPTH-1
    logic [WIDTH-1:0] mem [DEPTH];

    // Write port
    always_ff @(posedge wr_clk) begin
        if (mem_if.wr_en)
            mem[mem_if.wr_addr] <= mem_if.wr_data;
    end

    // Read port: synchronous read, data available the next cycle
    always_ff @(posedge rd_clk) begin
        if (mem_if.rd_en)
            mem_if.rd_data <= mem[mem_if.rd_addr];
    end

endmodule

`default_nettype wire
