//////////////////////
//Scoreboard
/////////////////////
// Pulls transactions from the mailbox and checks them against a reference model.
// The model is a queue q[$] holding the words the FIFO should contain, oldest first,
// like the C++ model in tb/DPI_based/model.cpp.
class scoreboard;

    mailbox #(transaction) txn_mail;
    transaction txn;
    logic [7:0] q[$];       // reference model
    int depth;              // FIFO depth: the model is full when q holds this many words
    int errors = 0;         // mismatches found, also used by the testbench
    int writes = 0;         // write transactions received
    int reads  = 0;         // read transactions checked

    function new(int depth);
        this.depth = depth;
    endfunction

    task run();
        logic [7:0] expected;
        forever begin
            txn_mail.get(txn);
            case (txn.kind)
                // Reset: the FIFO is empty again
                RESET: q.delete();

                // Write: add the word to the model. The DUT must not accept a write when full.
                WRITE: begin
                    writes = writes + 1;
                    if (q.size() == depth) begin
                        errors = errors + 1;
                        $error("[%.1f ns] SV scoreboard: write of 0x%h accepted while the model is full (overflow)",
                               txn.timestamp, txn.data);
                    end else
                        q.push_back(txn.data);
                end

                // Read: the DUT must return the oldest word in the model. It must not read when empty.
                READ: begin
                    reads = reads + 1;
                    if (q.size() == 0) begin
                        errors = errors + 1;
                        $error("[%.1f ns] SV scoreboard: read of 0x%h accepted while the model is empty (underflow)",
                               txn.timestamp, txn.data);
                    end else begin
                        expected = q.pop_front();
                        if (txn.data !== expected) begin
                            errors = errors + 1;
                            $error("[%.1f ns] SV scoreboard: read data mismatch: expected 0x%h, observed 0x%h",
                                   txn.timestamp, expected, txn.data);
                        end
                    end
                end
            endcase
        end
    endtask

    // Pass/fail summary, printed at the end of the simulation
    function void report();
        if (errors == 0)
            $display("SV SCOREBOARD PASSED: %0d writes, %0d reads checked, 0 errors", writes, reads);
        else
            $display("SV SCOREBOARD FAILED: %0d writes, %0d reads checked, %0d errors", writes, reads, errors);
    endfunction

endclass
