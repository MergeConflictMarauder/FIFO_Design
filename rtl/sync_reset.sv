`timescale 1ns/1ps
`default_nettype none

// Reset synchroniser, asynchronous assert, synchronous de-assert
module sync_reset (
    input  logic clk,
    input  logic rst_n_in,    // asynchronous, active low
    output logic rst_n_out    // released synchronously to clk
);

    logic [1:0] sync;

    always_ff @(posedge clk or negedge rst_n_in) begin
        if (!rst_n_in)
            sync <= 2'b00;
        else
            sync <= {sync[0], 1'b1};
    end

    assign rst_n_out = sync[1];

endmodule

`default_nettype wire
