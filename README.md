# FIFO_Design
This lab focuses on design and verification of two components, an Asynchronous FIFO and a Data Interleaving circuit that uses this FIFO.

## Repository layout

```text
rtl/                  Asynchronous FIFO RTL (top level: async_fifo_top)
tb/tb_async_fifo.sv   Self-checking testbench (top level: tb_async_fifo)
Makefile              Simulation with VCS and Verdi
synth/                Synthesis with Design Compiler
  compile_dc.tcl      Synthesis script: sources, clocks, constraints, reports
  Makefile            Runs the synthesis script
  reports/            Timing, area, power and constraint reports
```

## Before you start

The flow uses Synopsys VCS, Verdi and Design Compiler (`dc_shell-t`). Load the
tool environment first, for example by sourcing your course setup script
(`env.cshrc` on Apporto). Synthesis also needs the `PDK_DIR` environment
variable, which points to the FreePDK45 installation used by `compile_dc.tcl`.

## Simulation

Run these from the `FIFO_Design/` directory.

```sh
make compile          # build the simulator (simv); same as: make
make empty_full       # run a test on the existing build
make almost_flags
make simultaneous
```

Compile once, then run any test. Recompile after changing the RTL or the
testbench. Each test prints `TEST PASSED` or `TEST FAILED`, and a failing test
makes `make` exit with an error.

| Test | What it checks |
|---|---|
| `empty_full` | Empty after reset, full after 16 writes, empty again after 16 reads |
| `almost_flags` | `almost_full` sets and clears at 12 words, `almost_empty` at 4 words |
| `simultaneous` | A 64-word burst written and read at the same time, with a 7 ns write clock and a 13 ns read clock |

The scoreboard in the testbench checks every word read against the data written.

### Waveforms

```sh
make waves TEST=empty_full      # or almost_flags, simultaneous
```

This runs the named test and opens its waveform (`async_fifo.fsdb`) in Verdi.
Each run overwrites the waveform file. The simulator can also be run directly:

```sh
./simv +TEST=empty_full
verdi -dbdir simv.daidir -ssf async_fifo.fsdb
```

### Clean up

```sh
make clean            # remove simv, simulation logs and waveforms
```

## Synthesis

Run these from the `synth/` directory.

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

- Default configuration: 8-bit data, 16 entries, `almost_full` at 12 words,
  `almost_empty` at 4 words (parameters of `async_fifo_top`).
- `DEPTH` must be a power of two and at most 16, because the Gray-code
  functions in `rtl/gray_converter.sv` are 5 bits wide. A deeper FIFO needs a
  wider `GRAY_W`.
