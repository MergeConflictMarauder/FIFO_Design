`timescale 1ns/1ps
`default_nettype none

// Read-side pointer, empty flag and almost-empty flag
module read_handler
    import gray_converter::bin2gray, gray_converter::GRAY_W;
#(
    parameter int ADDR_WIDTH = 4,
    parameter int AE_THRESH  = 4     // almost_empty asserts at <= this occupancy
)(
    input  logic                clk,
    input  logic                rst_n,
    input  logic                enable,         // read request from the consumer
    input  logic [ADDR_WIDTH:0] write_ptr,      // write pointer, synchronised, binary

    output logic                  rd_en,        // gated read strobe to the memory
    output logic                  is_empty,
    output logic                  is_almost,
    output logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [ADDR_WIDTH:0]   num_content,  // occupancy seen by this domain
    output logic [ADDR_WIDTH:0]   rd_to_gray    // read pointer, Gray coded, to the CDC
);

    localparam int                  PTR_WIDTH = ADDR_WIDTH + 1;
    localparam logic [ADDR_WIDTH:0] AE_LEVEL  = PTR_WIDTH'(AE_THRESH);

    logic [ADDR_WIDTH:0] read_ptr, next_read;
    logic [ADDR_WIDTH:0] counter;
    logic                empty, almost_empty;

    // Gate the read with the registered flag
    assign rd_en = enable && !is_empty;

    // The pointer advances only on an accepted read
    // i.e. 5’b0_0000 = (don’t advance), 5’b0_0001 = (advance)
    assign next_read = read_ptr + {{ADDR_WIDTH{1'b0}}, rd_en};

    // Empty when both pointers match, wrap bit included
    assign empty = (next_read == write_ptr);

    // Almost empty when the occupancy after the pending read is <= the threshold
    assign counter = write_ptr - next_read;
    assign almost_empty = (counter <= AE_LEVEL);

    // Number of entries calculated from the current read pointer
    // i.e 0_1100 - 0_1000 = 4, 1_0000 - 0_1100 = 4
    assign num_content = write_ptr - read_ptr;

    // Assign the lower bits of the pointer to the memory address
    assign rd_addr = read_ptr[ADDR_WIDTH-1:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ptr   <= '0;
            is_empty   <= 1'b1;
            is_almost  <= 1'b1;
            rd_to_gray <= '0;       // Gray code of zero is zero
        end
        else begin
            read_ptr   <= next_read;
            is_empty   <= empty;
            is_almost  <= almost_empty;
            rd_to_gray <= PTR_WIDTH'(bin2gray(GRAY_W'(next_read)));
        end
    end

endmodule

`default_nettype wire
