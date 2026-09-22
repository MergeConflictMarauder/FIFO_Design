`timescale 1ns/1ps
`default_nettype none

// Pointer synchroniser, instantiated once per direction
module sync_clock
    import gray_converter::gray2bin, gray_converter::GRAY_W;
#(
    parameter int PTR_WIDTH = 5
)(
    input  logic                 clk,           // destination clock
    input  logic                 rst_n,         // destination-domain reset
    input  logic [PTR_WIDTH-1:0] ptr_gray_in,   // from the source domain
    output logic [PTR_WIDTH-1:0] ptr_bin_out    // binary, destination domain
);

    // Two-stage synchroniser, with ASYNC_REG attribute to avoid optimisations
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] ff1, ff2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ff1 <= '0;
            ff2 <= '0;
        end
        else begin
            ff1 <= ptr_gray_in;
            ff2 <= ff1;
        end
    end

    assign ptr_bin_out = PTR_WIDTH'(gray2bin(GRAY_W'(ff2)));

endmodule

`default_nettype wire
