`timescale 1ns/1ps
`default_nettype none

// Interface between FIFO control logic and dual-port memory
interface dual_port_mem_if #(
    parameter int WIDTH      = 8,
    parameter int ADDR_WIDTH = 4
);

    logic                  wr_en;
    logic                  rd_en;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [WIDTH-1:0]      wr_data;
    logic [WIDTH-1:0]      rd_data;

    // FIFO side drives requests/data and receives read data
    modport fifo_side (
        output wr_en,
        output rd_en,
        output wr_addr,
        output rd_addr,
        output wr_data,
        input  rd_data
    );

    // Memory side receives requests/data and drives read data
    modport memory_side (
        input  wr_en,
        input  rd_en,
        input  wr_addr,
        input  rd_addr,
        input  wr_data,
        output rd_data
    );

endinterface


// One write port, one read port, independent clocks
module dual_port_memory #(
    parameter int WIDTH      = 8,
    parameter int ADDR_WIDTH = 4
)(
    input logic wr_clk,
    input logic rd_clk,

    dual_port_mem_if.memory_side mem_if
);

    // Number of memory entries
    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // Write port
    always_ff @(posedge wr_clk) begin
        if (mem_if.wr_en)
            mem[mem_if.wr_addr] <= mem_if.wr_data;
    end

    // Read port
    always_ff @(posedge rd_clk) begin
        if (mem_if.rd_en)
            mem_if.rd_data <= mem[mem_if.rd_addr];
    end

endmodule

`default_nettype wire
