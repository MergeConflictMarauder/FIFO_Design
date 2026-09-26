`timescale 1ns/1ps
`default_nettype none

// Gray code conversion functions, used for pointer synchronisation across clock domains
package gray_converter;

    // DEPTH=64 uses six address bits plus one wrap bit.
    // This width also preserves the existing DEPTH=16 FIFO behavior.
    localparam int GRAY_W = 7;

    // Binary to Gray:  g = b ^ (b >> 1)
    function automatic logic [GRAY_W-1:0] bin2gray(input logic [GRAY_W-1:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    // Gray to binary:  b[i] = ^g[GRAY_W-1:i]
    function automatic logic [GRAY_W-1:0] gray2bin(input logic [GRAY_W-1:0] gray);
        logic [GRAY_W-1:0] bin;
        bin = gray;
        for (int i = 1; i < GRAY_W; i <<= 1) begin
            bin = bin ^ (bin >> i);
        end
        return bin;
    endfunction

endpackage

`default_nettype wire
