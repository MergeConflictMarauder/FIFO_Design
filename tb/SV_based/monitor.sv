//////////////////////
//Monitor
/////////////////////
// Watches the FIFO pins through the two interfaces. For every accepted write, accepted
// read and reset it creates a transaction and posts it to the mailbox.
//
// Logging is set with the plusarg +LOG=<n>:
//   0 (default) = off, 1 = one brief line per transaction, 2 = every field of the transaction
class monitor;

    virtual fifo_wr_if wr_vif;
    virtual fifo_rd_if rd_vif;
    mailbox #(transaction) txn_mail;
    int log_level;

    function new(virtual fifo_wr_if wr_vif, virtual fifo_rd_if rd_vif);
        this.wr_vif = wr_vif;
        this.rd_vif = rd_vif;
        if (!$value$plusargs("LOG=%d", log_level))
            log_level = 0;
    endfunction

    // Watch the write side, the read side and the reset at the same time
    task run();
        fork
            watch_writes();
            watch_reads();
            watch_reset();
        join
    endtask

    // The DUT accepts a write on a rising wr_clk edge with wr_en = 1 and full = 0
    task watch_writes();
        transaction txn;
        forever begin
            @(posedge wr_vif.wr_clk);
            if (wr_vif.rst_n && wr_vif.wr_en && !wr_vif.full) begin
                txn = new();
                txn.kind      = WRITE;
                txn.data      = wr_vif.wr_data;
                txn.timestamp = $realtime;
                post(txn);
            end
        end
    endtask

    // The DUT accepts a read on a rising rd_clk edge with rd_en = 1 and empty = 0.
    // It puts the word on rd_data at that edge, so rd_data is captured on the falling edge after.
    task watch_reads();
        transaction txn;
        forever begin
            @(posedge rd_vif.rd_clk);
            if (rd_vif.rst_n && rd_vif.rd_en && !rd_vif.empty) begin
                txn = new();
                txn.kind      = READ;
                txn.timestamp = $realtime;
                @(negedge rd_vif.rd_clk);
                txn.data      = rd_vif.rd_data;
                post(txn);
            end
        end
    endtask

    // A reset empties the FIFO; the scoreboard must empty its model too
    task watch_reset();
        transaction txn;
        forever begin
            @(negedge wr_vif.rst_n);
            txn = new();
            txn.kind      = RESET;
            txn.timestamp = $realtime;
            post(txn);
        end
    endtask

    // Post a complete transaction to the mailbox, then log it
    task post(transaction txn);
        txn_mail.put(txn);
        if (log_level == 1)
            $display("[%.1f ns] monitor: %s transaction", txn.timestamp, txn.kind.name());
        else if (log_level == 2)
            $display("[%.1f ns] monitor: kind = %s, data = 0x%h, timestamp = %.1f ns",
                     $realtime, txn.kind.name(), txn.data, txn.timestamp);
    endtask

endclass
