`timescale 1ns/1ps

//////////////////////
//Interfaces
/////////////////////
// The DUT is connected through these two interfaces (see tb/tb_async_fifo.sv),
// and the monitor watches the pins through them. Data is 8 bits, the DUT's WIDTH.

// Write side: signals in the wr_clk domain
interface fifo_wr_if(input logic wr_clk, input logic rst_n);

    logic       wr_en;
    logic [7:0] wr_data;
    logic       full;
    logic       almost_full;

endinterface

// Read side: signals in the rd_clk domain
interface fifo_rd_if(input logic rd_clk, input logic rst_n);

    logic       rd_en;
    logic [7:0] rd_data;
    logic       empty;
    logic       almost_empty;

endinterface
