# FIFO_Design
This lab focuses on design and verification of two components, an Asynchronous FIFO and a Data Interleaving circuit that uses this FIFO.

## Repository layout

```text
rtl/
  async_fifo_top.sv ...         Part 1: asynchronous FIFO (top level: async_fifo_top)
  even_odd_interleaver_top.sv   Part 2: interleaver built from two FIFOs
                                (parity_fifo_if, parity_fifo, even_odd_interleaver_top)
tb/
  tb_async_fifo.sv              Self-checking FIFO testbench
  tb_even_odd_interleaver.sv    Self-checking interleaver testbench
Makefile                        Simulation of both parts with VCS and Verdi
synth/                          Synthesis of the FIFO with Design Compiler
  compile_dc.tcl                Synthesis script: sources, clocks, constraints, reports
  Makefile                      Runs the synthesis script
  reports/                      Timing, area, power and constraint reports
```

## Before you start

The flow uses Synopsys VCS, Verdi and Design Compiler (`dc_shell-t`). Load the
tool environment first, for example by sourcing your course setup script
(`env.cshrc` on Apporto). Synthesis also needs the `PDK_DIR` environment
variable, which points to the FreePDK45 installation used by `compile_dc.tcl`.

## Part 1: Asynchronous FIFO

`async_fifo_top` has independent write and read clocks. Pointers cross between
the two domains in Gray code through two-stage synchronisers, and the reset is
released synchronously to each clock.

| Parameter | Default | Meaning |
|---|---|---|
| `WIDTH` | 8 | Data word width |
| `DEPTH` | 16 | Entries, a power of two up to 128 |
| `AF_THRESH` | 12 | `almost_full` is set at this many words or more |
| `AE_THRESH` | 4 | `almost_empty` is set at this many words or fewer |

`rd_data` is valid one read-clock cycle after an accepted read. Writes while
`full` and reads while `empty` are ignored.

## Part 2: Even/odd interleaver

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

## Simulation

Run these from the `FIFO_Design/` directory.

```sh
make                  # build both simulators (simv_part1, simv_part2); same as: make compile
make empty_full       # run one test
make test_part1       # run all FIFO tests
make test_part2       # run all interleaver tests
make test             # run every test
```

A test target builds its simulator first if a source file has changed. Each
test prints `TEST PASSED` or `TEST FAILED`, and a failing test makes `make` exit
with an error. `make test` stops at the first failure; use `make -k test` to
run the rest anyway.

### FIFO tests (`simv_part1`)

| Test | What it checks |
|---|---|
| `empty_full` | Empty after reset, full after 16 writes, empty again after 16 reads |
| `almost_flags` | `almost_full` sets and clears at 12 words, `almost_empty` at 4 words |
| `simultaneous` | A 64-word burst written and read at the same time, with a 7 ns write clock and a 13 ns read clock |

The scoreboard checks every word read against the data written.

### Interleaver tests (`simv_part2`)

| Test | Stimulus | What it shows |
|---|---|---|
| `case1` | Case 1: 80 writes at the start of each 100-cycle block | Normal operation with short bursts |
| `case4` | Case 4: 160 back-to-back writes, the long burst on the even FIFO | The FIFO-sizing case: peak of at least 48 words, no overflow |
| `case4_odd` | Case 4 timing with the long burst on the odd FIFO | The same worst case on the other FIFO |

Both clocks run at the same frequency with a phase offset. Every test writes 80
items per 100 write-clock cycles (40 even, 40 odd) and requests 8 outputs per
10 read-clock cycles; the testbench checks both rates. It also checks that
every value comes out in order, that parity alternates starting with even, and
that no write hits a full FIFO. Each test also prints the peak occupancy of
both FIFOs.

### Waveforms

Each test saves its waveform as `<test>.fsdb`, also when it fails.

```sh
make verdi_empty_full # or verdi_<any test name>
```

The simulators can also be run directly. The waveform is then written to
`async_fifo.fsdb` (part 1) or `even_odd_interleaver.fsdb` (part 2):

```sh
./simv_part1 +TEST=empty_full
verdi -dbdir simv_part1.daidir -ssf async_fifo.fsdb
```

### Clean up

```sh
make clean            # remove the simulators, logs, waveforms and Verdi files
```

## Synthesis

Synthesis covers the asynchronous FIFO (`async_fifo_top`). Run these from the
`synth/` directory.

```sh
cd synth
make                  # runs: dc_shell-t -f compile_dc.tcl, log in synth.log
```

Results:

| Output | Contents |
|---|---|
| `reports/write_timing.rep`, `reports/read_timing.rep` | Worst setup paths in each clock domain |
| `reports/clocks.rep` | Clock definitions |
| `reports/constraints.rep` | Constraint violations |
| `reports/check_timing.rep` | Timing setup checks |
| `reports/area.rep`, `reports/area_hierarchy.rep` | Cell area |
| `reports/power.rep` | Power estimate |
| `async_fifo_top.sdc` | Constraints as applied by Design Compiler |
| `async_fifo_top.ddc` | Synthesized design database |

The clock targets and I/O delays are set at the top of `compile_dc.tcl`
(`my_write_clk_freq_MHz`, `my_read_clk_freq_MHz`, `my_input_delay_ns`,
`my_output_delay_ns`). The write and read clocks are declared asynchronous, so
Design Compiler does not time paths between the two domains.

```sh
make clean_synth      # remove Design Compiler work files (WORK, *.syn, *.pvl, *.mr, *.svf)
make clean            # also remove logs
```

## Design notes

- `DEPTH` and `FIFO_DEPTH` are limited to 128 because the Gray-code functions in
  `rtl/gray_converter.sv` are 8 bits wide (`GRAY_W`). A deeper FIFO needs a
  wider `GRAY_W`; `async_fifo_top` reports an error if it is too narrow.
- In the interleaver, a value whose parity is never matched stays in its FIFO,
  because the controller never skips a parity.
- The interleaver's FIFO `full` flags are not brought out, so a write to a full
  FIFO is dropped without notice. At the required rates the FIFOs never fill.
