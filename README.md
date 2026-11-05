# FIFO_Design

Design and verification of an asynchronous FIFO (Part 1) and an even/odd
interleaver built from two of those FIFOs (Part 2).

## Repository layout

```text
rtl/                            Design
  async_fifo_top.sv ...           Part 1: asynchronous FIFO
  even_odd_interleaver_top.sv     Part 2: interleaver
tb/                             Verification
  tb_async_fifo.sv                Part 1 testbench (stimulus and tests)
  tb_even_odd_interleaver.sv      Part 2 testbench
  DPI_based/                      DPI-C checker
    checker.sv                      Compares the DUT with the C++ model
    model.cpp                       C++ reference model
  SV_based/                       SV class-based scoreboard
    fifo_if.sv                      Write-side and read-side interfaces
    transaction.sv                  One write, read or reset
    monitor.sv                      Turns pin activity into transactions
    scoreboard.sv                   Checks transactions against a queue model
synth/                          Synthesis with Design Compiler
Makefile                        Simulation with VCS and Verdi
```

## Setup

Load the Synopsys tools (VCS, Verdi, Design Compiler) first, for example by
sourcing `env.cshrc` on Apporto. Synthesis also needs `PDK_DIR` set to the
FreePDK45 installation. Run every `make` command from `FIFO_Design/`.

## Quick start

```sh
make                  # build both simulators (simv_part1, simv_part2)
make sim              # run all FIFO tests (Part 1), no bug: all must pass
make sim_bug          # run all FIFO tests with the injected bug: checkers must fail
make test_part2       # run all interleaver tests (Part 2)
make test             # run every test
make empty_full       # run one test (any test name works)
make verdi_empty_full # open that test's waveform in Verdi
make clean            # remove simulators, logs and waveforms
```

Each test prints `TEST PASSED` or `TEST FAILED`; a failure stops `make`
(use `make -k` to keep going).

## Part 1: Asynchronous FIFO

### Design

Independent write and read clocks. Pointers cross between the clock domains in
Gray code through 2-flop synchronisers. Writes while `full` and reads while
`empty` are ignored, and `rd_data` is valid one read-clock cycle after a read.

| Parameter | Default | Meaning |
|---|---|---|
| `WIDTH` | 8 | Data width |
| `DEPTH` | 16 | Entries, a power of two up to 128 |
| `AF_THRESH` | 12 | `almost_full` at this many words or more |
| `AE_THRESH` | 4 | `almost_empty` at this many words or fewer |

### Tests

| Test | What it does |
|---|---|
| `empty_full` | Fill to full, write while full, drain to empty, read while empty |
| `almost_flags` | `almost_full` and `almost_empty` set and clear at their thresholds |
| `simultaneous` | 64 words written and read at the same time (7 ns write clock, 13 ns read clock) |

### Checkers

Both checkers run in every Part 1 simulation, on the same stimulus. Their errors
make the test fail.

- **DPI-C checker** (`tb/DPI_based`): on each clock edge, copies accepted writes and
  reads into the C++ model, compares `rd_data`, and compares `full`/`empty` with
  the model. A flag may lag the model by up to 4 edges (synchroniser delay).
  Prints `CHECKER PASSED/FAILED`.
- **SV scoreboard** (`tb/SV_based`): the monitor posts a transaction for each
  accepted write, read and reset to a mailbox; the scoreboard checks it against
  a queue model `q[$]` (read data, overflow, underflow).
  Prints `SV SCOREBOARD PASSED/FAILED`.

### Monitor log

Set with `+LOG=<n>` when running the simulator directly:

| `+LOG` | Output |
|---|---|
| `0` (default) | Off |
| `1` | One line per transaction: kind and timestamp |
| `2` | Every field: kind, data and timestamp |

```sh
./simv_part1 +TEST=empty_full +LOG=2
```

### Bug injection

`+INJECT_BUG` makes the FIFO drop every Nth write (`+BUG_N=<n>`, default 5).
It is for simulation only; synthesis does not see it.

```sh
make sim_bug                                        # all tests, N = 5
make sim_bug BUG_N=3                                # all tests, N = 3
./simv_part1 +TEST=empty_full +INJECT_BUG +LOG=2    # one test, run directly
```

Expected: both checkers report `rd_data` mismatches, except in `almost_flags`,
where the dropped words are never read (the test's own flag checks fail instead).
`simultaneous` ends with a timeout. Logs and waveforms are kept as
`<test>_bug.log` and `<test>_bug.fsdb`.

### Waveforms

`make <test>` saves `<test>.fsdb`. A direct `./simv_part1` run writes `async_fifo.fsdb`.

```sh
make verdi_empty_full
verdi -dbdir simv_part1.daidir -ssf empty_full_bug.fsdb &   # a sim_bug run
verdi -dbdir simv_part1.daidir -ssf async_fifo.fsdb &       # a direct run
```

Useful signals: the pins in `tb_async_fifo.wr_if_inst` and `tb_async_fifo.rd_if_inst`,
and the DPI checker state in `tb_async_fifo.u_checker` (`exp_full`, `exp_empty`,
`rd_expect`, `errors`).

## Part 2: Even/odd interleaver

### Design

Writes go to an even or odd FIFO by bit 0 of `wr_data`. Reads alternate even,
odd, even, starting with even; if the next parity is empty, the reader waits
for it. `rd_data` is valid while `rd_valid` is high.

| Parameter | Default | Meaning |
|---|---|---|
| `WIDTH` | 8 | Data width |
| `FIFO_DEPTH` | 64 | Entries in each FIFO |
| `FIRST_EVEN` | 1 | Parity of the first output |

`FIFO_DEPTH` is 64 because the worst case (Case 4) needs 48 words (49 measured,
one extra for the synchroniser delay), rounded up to a power of two.

### Tests

| Test | Stimulus |
|---|---|
| `case1` | 80 writes at the start of each 100-cycle block |
| `case4` | 160 back-to-back writes, long burst on the even FIFO |
| `case4_odd` | Same as `case4`, long burst on the odd FIFO |

Each test checks the write and read rates, data order, even/odd alternation and
that no write hits a full FIFO, and prints the peak occupancy of both FIFOs.

## Synthesis

```sh
cd synth
make                  # dc_shell-t -f compile_dc.tcl, log in synth.log
make clean            # remove work files and logs
```

Reports are written to `synth/reports/` (timing, area, power, constraints).
Clock targets and I/O delays are set at the top of `compile_dc.tcl`.

## Design notes

- `DEPTH` and `FIFO_DEPTH` are limited to 128 because `GRAY_W` in
  `rtl/gray_converter.sv` is 8 bits.
- The SV scoreboard's interfaces and classes use 8-bit data (the default `WIDTH`).
- In the interleaver, a value whose parity is never requested stays in its FIFO.
