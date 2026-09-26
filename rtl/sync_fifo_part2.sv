`timescale 1ns/1ps
`default_nettype none

// Single-clock FIFO used by Part II.
// The FIFO supports simultaneous read and write operations.
module sync_fifo_part2 #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 64
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         wr_en,
    input  logic                         rd_en,
    input  logic [WIDTH-1:0]             wr_data,

    output logic [WIDTH-1:0]             rd_data,
    output logic                         full,
    output logic                         empty,
    output logic [$clog2(DEPTH+1)-1:0]   count
);

    localparam int ADDR_WIDTH  = $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
    logic                  write_fire, read_fire;

    // Parameter check
    initial begin
        if (DEPTH < 2)
            $error("sync_fifo_part2: DEPTH (%0d) must be at least 2", DEPTH);
    end

    // FIFO status flags
    assign full  = (count == DEPTH);
    assign empty = (count == 0);

    // A read is accepted only when data is available.
    assign read_fire = rd_en && !empty;

    // A write is accepted when space is available.  If the FIFO is full,
    // a simultaneous read frees one location on the same clock edge.
    assign write_fire = wr_en && (!full || read_fire);

    // First-word view of the entry at the current read pointer.
    // The Part II controller captures this value only when read_fire is true.
    assign rd_data = mem[rd_ptr];

    // FIFO state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end
        else begin
            // Write port
            if (write_fire) begin
                mem[wr_ptr] <= wr_data;

                if (wr_ptr == DEPTH-1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            // Read pointer
            if (read_fire) begin
                if (rd_ptr == DEPTH-1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // Occupancy count
            case ({write_fire, read_fire})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule

`default_nettype wire
