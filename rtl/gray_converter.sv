`timescale 1ns/1ps
`default_nettype none

// Gray code conversion functions, used for pointer synchronisation across clock domains
package gray_converter;

    localparam int GRAY_W = 5;  // Must be at least the pointer width

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
