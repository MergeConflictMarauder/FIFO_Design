`timescale 1ns/1ps
`default_nettype none

// Part II: Even/Odd alternating circuit.
// Incoming even and odd values are stored in separate FIFOs.  The read-side
// controller alternates between the two FIFOs and stalls if the required FIFO
// is empty.  data_out changes only after a successful read.
module even_odd_interleaver #(
    parameter int WIDTH      = 8,
    parameter int FIFO_DEPTH = 64
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] data_in,
    input  logic             write_en,
    output logic [WIDTH-1:0] data_out,
    input  logic             read_en
);

    localparam int COUNT_WIDTH = $clog2(FIFO_DEPTH + 1);

    // Even FIFO signals
    logic                  even_wr_en, even_rd_en;
    logic [WIDTH-1:0]      even_rd_data;
    logic                  even_full, even_empty;
    logic [COUNT_WIDTH-1:0] even_count;

    // Odd FIFO signals
    logic                  odd_wr_en, odd_rd_en;
    logic [WIDTH-1:0]      odd_rd_data;
    logic                  odd_full, odd_empty;
    logic [COUNT_WIDTH-1:0] odd_count;

    // Read controller: the first successful output after reset is even.
    typedef enum logic {
        READ_EVEN,
        READ_ODD
    } read_state_t;

    read_state_t read_state;

    // These internal signals are intentionally named and kept simple so the
    // testbench/Verdi can show when an output transaction actually occurs.
    logic read_fire;

    // ---------------------------------------------------------------------
    // Write-side routing
    // data_in[0] = 0 -> even FIFO
    // data_in[0] = 1 -> odd FIFO
    // ---------------------------------------------------------------------
    assign even_wr_en = write_en && !data_in[0];
    assign odd_wr_en  = write_en &&  data_in[0];

    // ---------------------------------------------------------------------
    // Read-side alternating control
    // The state changes only after a successful read.  If the FIFO required
    // by the current state is empty, the controller stalls and data_out holds
    // its previous value.
    // ---------------------------------------------------------------------
    assign even_rd_en = read_en && (read_state == READ_EVEN) && !even_empty;
    assign odd_rd_en  = read_en && (read_state == READ_ODD)  && !odd_empty;
    assign read_fire  = even_rd_en || odd_rd_en;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_state <= READ_EVEN;
            data_out    <= '0;
        end
        else begin
            if (even_rd_en) begin
                data_out    <= even_rd_data;
                read_state  <= READ_ODD;
            end
            else if (odd_rd_en) begin
                data_out    <= odd_rd_data;
                read_state  <= READ_EVEN;
            end
            // else: stall and hold data_out/read_state
        end
    end

    // ---------------------------------------------------------------------
    // Even FIFO
    // ---------------------------------------------------------------------
    sync_fifo_part2 #(
        .WIDTH (WIDTH),
        .DEPTH (FIFO_DEPTH)
    ) u_even_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (even_wr_en),
        .rd_en   (even_rd_en),
        .wr_data (data_in),
        .rd_data (even_rd_data),
        .full    (even_full),
        .empty   (even_empty),
        .count   (even_count)
    );

    // ---------------------------------------------------------------------
    // Odd FIFO
    // ---------------------------------------------------------------------
    sync_fifo_part2 #(
        .WIDTH (WIDTH),
        .DEPTH (FIFO_DEPTH)
    ) u_odd_fifo (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (odd_wr_en),
        .rd_en   (odd_rd_en),
        .wr_data (data_in),
        .rd_data (odd_rd_data),
        .full    (odd_full),
        .empty   (odd_empty),
        .count   (odd_count)
    );

endmodule

`default_nettype wire
