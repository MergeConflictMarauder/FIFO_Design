// Golden reference model of the asynchronous FIFO, called from SystemVerilog through DPI-C.
//
// The model has no clocks: a write or read takes effect as soon as the checker
// calls fifo_push() or fifo_pop(). The checker (checker.sv) calls them on
// the clock edges where the DUT accepts a write or a read.
//
// Data is passed as a 32-bit int, so WIDTH can be at most 32.

#include <cstdio>

static const int MAX_DEPTH = 128;   // the DUT supports DEPTH up to 128
static const int MAX_WIDTH = 32;    // data is passed as a 32-bit int

// FIFO storage: mem[entry][bit], one row per FIFO entry and one column per data bit,
// like the DUT's memory "logic [WIDTH-1:0] mem [DEPTH]"
static int mem[MAX_DEPTH][MAX_WIDTH];

static int depth = 0;       // entries in use, set by fifo_init() to the DUT's DEPTH
static int width = 0;       // data bits, set by fifo_init() to the DUT's WIDTH
static int wr_ptr = 0;      // next entry to write
static int rd_ptr = 0;      // next entry to read
static int count = 0;       // words currently stored

extern "C" {

// Set the size to match the DUT and empty the FIFO. Call it again to reset.
void fifo_init(int fifo_depth, int fifo_width) {
    if (fifo_depth < 1 || fifo_depth > MAX_DEPTH || fifo_width < 1 || fifo_width > MAX_WIDTH) {
        printf("fifo_model: DEPTH %d / WIDTH %d not supported (DEPTH 1..%d, WIDTH 1..%d)\n",
               fifo_depth, fifo_width, MAX_DEPTH, MAX_WIDTH);
        return;
    }
    depth  = fifo_depth;
    width  = fifo_width;
    wr_ptr = 0;
    rd_ptr = 0;
    count  = 0;
}

int fifo_is_empty() {
    return count == 0;
}

int fifo_is_full() {
    return count == depth;
}

// Store one word at the write pointer. A write while full is ignored, like the DUT.
void fifo_push(int data) {
    if (fifo_is_full())
        return;
    for (int b = 0; b < width; b++)
        mem[wr_ptr][b] = (data >> b) & 1;
    wr_ptr = (wr_ptr + 1) % depth;   // wrap around at the end of the storage
    count++;
}

// Return the oldest word. A read while empty returns 0 and changes nothing.
int fifo_pop() {
    if (fifo_is_empty())
        return 0;
    int data = 0;
    for (int b = 0; b < width; b++)
        data |= mem[rd_ptr][b] << b;
    rd_ptr = (rd_ptr + 1) % depth;
    count--;
    return data;
}

} // extern "C"
