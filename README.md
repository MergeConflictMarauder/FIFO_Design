# FIFO_Design
This lab focuses on design and verification of two components, an Asynchronous FIFO and a Data Interleaving circuit that uses this FIFO.

## Repository layout

```text
rtl/
  even_odd_interleaver_top.sv   Interleaver: parity_fifo_if, parity_fifo, even_odd_interleaver_top
  async_fifo_top.sv ...         Asynchronous FIFO reused for the even and odd FIFOs
tb/tb_even_odd_interleaver.sv   Self-checking interleaver testbench
Makefile                        Simulation with VCS and Verdi
```

## Design

`even_odd_interleaver_top` stores even and odd values in two asynchronous FIFOs
and outputs them alternately.

- **Write side (`wr_clk`):** each `wr_data` goes to the even or odd FIFO,
  selected by bit 0.
- **Read side (`rd_clk`):** each `rd_en` request reads the next FIFO in strict
  even, odd, even order, starting with even (`FIRST_EVEN`). If that FIFO is
  empty, the controller waits for that parity instead of skipping it.
- **Output:** `rd_data` is valid while `rd_valid` is high, one read-clock cycle
  after the FIFO read, and holds its value otherwise.

| Parameter | Default | Meaning |
|---|---|---|
| `WIDTH` | 8 | Data word width |
| `FIFO_DEPTH` | 64 | Entries in each FIFO, a power of two up to 128 |
| `FIRST_EVEN` | 1 | Parity of the first output |

**FIFO size.** In the worst case (Case 4 of the FIFO-depth calculation), one
parity receives 80 back-to-back writes while only 32 of them can be read, so a
FIFO must hold 48 words. Simulation measures 49, one more because of the
clock-domain synchroniser delay. `FIFO_DEPTH` is 64, the next power of two.

## Before you start

The flow uses Synopsys VCS and Verdi. Load the tool environment first, for
example by sourcing your course setup script (`env.cshrc` on Apporto).

## Simulation

Run these from the `FIFO_Design/` directory.

```sh
make                  # build the simulator (simv_part2); same as: make compile
make case1            # run one test
make case4
make case4_odd
make test             # run all three tests
```

A test target builds the simulator first if a source file has changed. Each
test prints `TEST PASSED` or `TEST FAILED` and the peak occupancy of both FIFOs.
A failing test makes `make` exit with an error.

| Test | Stimulus | What it shows |
|---|---|---|
| `case1` | Case 1: 80 writes at the start of each 100-cycle block | Normal operation with short bursts |
| `case4` | Case 4: 160 back-to-back writes, the long burst on the even FIFO | The FIFO-sizing case: peak of at least 48 words, no overflow |
| `case4_odd` | Case 4 timing with the long burst on the odd FIFO | The same worst case on the other FIFO |

Both clocks run at the same frequency with a phase offset. Every test writes 80
items per 100 write-clock cycles (40 even, 40 odd) and requests 8 outputs per
10 read-clock cycles; the testbench checks both rates. It also checks that
every value comes out in order, that parity alternates starting with even, and
that no write hits a full FIFO.

### Waveforms

Each test saves its waveform as `<test>.fsdb`, also when it fails.

```sh
make verdi_case1      # or verdi_case4, verdi_case4_odd
```

### Clean up

```sh
make clean            # remove the simulator, logs, waveforms and Verdi files
```

## Design notes

- A value whose parity is never matched stays in its FIFO, because the
  controller never skips a parity.
- The FIFOs' `full` flags are not brought out, so a write to a full FIFO is
  dropped without notice. At the required rates the FIFOs never fill.
- `FIFO_DEPTH` above 128 needs a wider `GRAY_W` in `rtl/gray_converter.sv`.
