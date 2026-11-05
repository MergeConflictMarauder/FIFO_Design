`timescale 1ns/1ps

// Lab 4 Part 4: assertion monitor attached to the Lab 1 even/odd interleaver.
// This interface is passive: no signal is driven into the DUT. Internal DUT
// controls are observed via explicit hierarchical connections in the testbench.
//
// Clock-domain rule: write routing is checked on wr_clk; read controller,
// valid/data timing and turn state are checked on rd_clk.
interface even_odd_sva_if (
    input logic       wr_clk,
    input logic       rd_clk,
    input logic       rst_n_wr,
    input logic       rst_n_rd,
    input logic       wr_en,
    input logic       wr_data_lsb,
    input logic       even_wr_en,
    input logic       odd_wr_en,
    input logic       rd_en,
    input logic       even_empty,
    input logic       odd_empty,
    input logic       even_rd_en,
    input logic       odd_rd_en,
    input logic       issue_read,
    input logic       next_is_even,
    input logic       pending,
    input logic       pending_is_even,
    input logic [7:0] rd_data,
    input logic       rd_valid
);
    wire selected_empty = next_is_even ? even_empty : odd_empty;
    integer witness[1:9] = '{default:0};

    // A1: Every enabled write is routed to exactly one parity FIFO.
    a1_write_routes: assert property (@(posedge wr_clk)
        disable iff (!rst_n_wr)
        wr_en |-> (even_wr_en ^ odd_wr_en) &&
                 (even_wr_en == !wr_data_lsb))
        else $error("SVA_ASSERT A1: even/odd write routing incorrect");
    c1_write_routes: cover property (@(posedge wr_clk)
        disable iff (!rst_n_wr) wr_en && (even_wr_en ^ odd_wr_en))
        begin witness[1]++; if (witness[1] == 1) $display("SVA_COVER A1: write routed to one parity FIFO"); end

    // A2: A read request cannot target both FIFOs simultaneously.
    a2_one_read: assert property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        issue_read |-> (even_rd_en ^ odd_rd_en))
        else $error("SVA_ASSERT A2: overlapping or missing parity read strobes");
    c2_one_read: cover property (@(posedge rd_clk)
        disable iff (!rst_n_rd) issue_read && (even_rd_en ^ odd_rd_en))
        begin witness[2]++; if (witness[2] == 1) $display("SVA_COVER A2: exclusive parity read"); end

    // A3: An accepted read must target the current turn and a nonempty FIFO.
    a3_read_select: assert property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        issue_read |-> (!selected_empty &&
                        (next_is_even ? even_rd_en : odd_rd_en)))
        else $error("SVA_ASSERT A3: read did not respect current nonempty parity");
    c3_read_select: cover property (@(posedge rd_clk)
        disable iff (!rst_n_rd) issue_read && !selected_empty)
        begin witness[3]++; if (witness[3] == 1) $display("SVA_COVER A3: read selected current turn"); end

    // A4: The interleaver must wait, not skip a parity, if its FIFO is empty.
    a4_stall_empty: assert property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        (rd_en && selected_empty) |->
            (!issue_read && !even_rd_en && !odd_rd_en))
        else $error("SVA_ASSERT A4: read attempted when chosen parity was empty");
    c4_stall_empty: cover property (@(posedge rd_clk)
        disable iff (!rst_n_rd) rd_en && selected_empty)
        begin witness[4]++; if (witness[4] == 1) $display("SVA_COVER A4: read stalled waiting for parity"); end

    // A5: After a read is actually accepted, the controller alternates turns.
    a5_advance_turn: assert property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        issue_read |=> (next_is_even != $past(next_is_even)))
        else $error("SVA_ASSERT A5: turn failed to alternate after an accepted read");
    c5_advance_turn: cover property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        issue_read ##1 (next_is_even != $past(next_is_even)))
        begin witness[5]++; if (witness[5] == 1) $display("SVA_COVER A5: parity turn advanced"); end

    // A6: Without an accepted read, the controller must keep its turn.
    a6_hold_turn: assert property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        !issue_read |=> (next_is_even == $past(next_is_even)))
        else $error("SVA_ASSERT A6: parity turn advanced without a read");
    c6_hold_turn: cover property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        !issue_read ##1 (next_is_even == $past(next_is_even)))
        begin witness[6]++; if (witness[6] == 1) $display("SVA_COVER A6: parity turn held"); end

    // A7: 'pending' is the one-cycle source of 'rd_valid' (including bubbles).
    // A pipeline error is detected in either direction, including spurious valid.
    a7_valid_after_pending: assert property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        pending |=> rd_valid)
        else $error("SVA_ASSERT A7: accepted read did not produce rd_valid");
    a7_no_spurious_valid: assert property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        !pending |=> !rd_valid)
        else $error("SVA_ASSERT A7: rd_valid rose with no pending read");
    c7_valid_after_pending: cover property (@(posedge rd_clk)
        disable iff (!rst_n_rd) pending ##1 rd_valid)
        begin witness[7]++; if (witness[7] == 1) $display("SVA_COVER A7: valid output arrived after pending"); end
    c7_no_spurious_valid: cover property (@(posedge rd_clk)
        disable iff (!rst_n_rd) !pending ##1 !rd_valid)
        begin witness[9]++; if (witness[9] == 1) $display("SVA_COVER A7b: idle cycle correctly kept rd_valid low"); end

    // A8: When valid, the output data parity matches the preceding selected FIFO.
    // Read data and rd_valid are both registered after the pending operation;
    // $past samples pending_is_even on the clock that produced this output.
    a8_output_parity: assert property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        rd_valid |-> (rd_data[0] != $past(pending_is_even)))
        else $error("SVA_ASSERT A8: output parity mismatched pending FIFO");
    c8_output_parity: cover property (@(posedge rd_clk)
        disable iff (!rst_n_rd)
        rd_valid && (rd_data[0] != $past(pending_is_even)))
        begin witness[8]++; if (witness[8] == 1) $display("SVA_COVER A8: output parity validated"); end

    final begin
        $display("SVA witness counts A1..A8: %0d %0d %0d %0d %0d %0d %0d %0d",
                 witness[1], witness[2], witness[3], witness[4],
                 witness[5], witness[6], witness[7], witness[8]);
        $display("SVA witness A7b (no spurious valid) count: %0d", witness[9]);
        $display("SVA witness counts are *per simulation*. Review combined test cases for closure.");
    end
endinterface
