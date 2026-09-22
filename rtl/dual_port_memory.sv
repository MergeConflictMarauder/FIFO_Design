`timescale 1ns/1ps
`default_nettype none

// One write port, one read port, independent clocks
module dual_port_memory #(
    parameter int WIDTH = 8,            // data word width
    parameter int ADDR_WIDTH = 4        // address width, 2**4 = 16 entries
)(
    input  logic                  wr_clk,
    input  logic                  rd_clk,

    input  logic                  wr_en,
    input  logic                  rd_en,

    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [ADDR_WIDTH-1:0] rd_addr,

    input  logic [WIDTH-1:0]      wr_data,
    output logic [WIDTH-1:0]      rd_data
);

    // Left bit-shift operator: 1 << 4 = 2^4 = 16
    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [WIDTH-1:0] mem [DEPTH];

    // Write port
    always_ff @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    // Read port
    always_ff @(posedge rd_clk) begin   // synchronous read, data available next cycle
        if (rd_en)
            rd_data <= mem[rd_addr];
    end

endmodule

`default_nettype wire
