//////////////////////
//Transaction
/////////////////////
// The kinds of FIFO operation the monitor reports
typedef enum {WRITE, READ, RESET} txn_kind_e;

// One FIFO operation: an accepted write, an accepted read, or a reset
class transaction;

    txn_kind_e  kind;       // WRITE, READ or RESET
    logic [7:0] data;       // word written (wr_data) or read (rd_data); not used for RESET
    realtime    timestamp;  // time of the clock edge where the operation happened, in ns

    function new();
    endfunction

endclass
