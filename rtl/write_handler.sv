`timescale 1ns/1ps
`default_nettype none

// Write-side pointer, full flag and almost-full flag
module write_handler
    import gray_converter::bin2gray;
#(
    parameter int ADDR_WIDTH = 4,
    parameter int AF_THRESH  = 12    // almost_full asserts at >= this occupancy
)(
    input  logic                clk,
    input  logic                rst_n,
    input  logic                enable,         // write request from the producer
    input  logic [ADDR_WIDTH:0] read_ptr,       // read pointer, synchronised, binary

    output logic                  wr_en,        // gated write strobe to the memory
    output logic                  is_full,
    output logic                  is_almost,
    output logic [ADDR_WIDTH-1:0] wr_addr,
    output logic [ADDR_WIDTH:0]   wr_to_gray    // write pointer, Gray coded, to the CDC
);

    localparam int                  PTR_WIDTH = ADDR_WIDTH + 1;
    localparam logic [ADDR_WIDTH:0] AF_LEVEL  = PTR_WIDTH'(AF_THRESH);

    logic [ADDR_WIDTH:0] write_ptr, next_write;
    logic [ADDR_WIDTH:0] counter;
    logic                full, almost_full;

    // Gate the write with the registered flag
    assign wr_en = enable && !is_full;

    // The pointer advances only on an accepted write
    // i.e. 5’b0_0000 = (don’t advance), 5’b0_0001 = (advance) 
    assign next_write = write_ptr + {{ADDR_WIDTH{1'b0}}, wr_en};

    // Full when the lower bits match and the wrap bit differs
    assign full = (next_write[ADDR_WIDTH-1:0] == read_ptr[ADDR_WIDTH-1:0]) &&
                    (next_write[ADDR_WIDTH] != read_ptr[ADDR_WIDTH]);

    // Almost full after the pending write is more than or equal to the threshold
    assign counter = next_write - read_ptr;     // i.e 0_1100 - 0_0000 = 12, 1_0000 - 0_0100 = 12
    assign almost_full = (counter >= AF_LEVEL);

    // Assign the lower bits of the pointer to the memory address
    assign wr_addr = write_ptr[ADDR_WIDTH-1:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr  <= '0;
            is_full    <= 1'b0;
            is_almost  <= 1'b0;
            wr_to_gray <= '0;       // Gray code of zero is zero
        end
        else begin
            write_ptr  <= next_write;
            is_full    <= full;
            is_almost  <= almost_full;
            wr_to_gray <= bin2gray(next_write);
        end
    end

endmodule

`default_nettype wire
