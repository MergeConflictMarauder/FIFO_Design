```make
VCS       = vcs
VCS_FLAGS = -sverilog -full64 -kdb -debug_access+all
TOP       = tb_async_fifo
SIM       = simv

# Add/remove RTL source files here as needed.
# gray_converter.sv must come first: the other RTL files import its package.
RTL       = rtl/gray_converter.sv \
            rtl/sync_reset.sv \
            rtl/sync_clock.sv \
            rtl/dual_port_memory.sv \
            rtl/write_handler.sv \
            rtl/read_handler.sv \
            rtl/async_fifo_top.sv

TB        = tb/tb_async_fifo.sv

.PHONY: all compile empty_full almost_flags simultaneous \
        waves_empty_full waves_almost_flags waves_simultaneous clean

# Default: compile the design
all: compile

# Compile once
compile:
	$(VCS) $(VCS_FLAGS) -top $(TOP) $(RTL) $(TB) -o $(SIM)

# Run tests using the existing compiled simulation
empty_full:
	./$(SIM) -exitstatus +TEST=empty_full

almost_flags:
	./$(SIM) -exitstatus +TEST=almost_flags

simultaneous:
	./$(SIM) -exitstatus +TEST=simultaneous

# Run tests and open their waveform in Verdi
waves_empty_full:
	./$(SIM) +TEST=empty_full
	verdi -dbdir $(SIM).daidir -ssf empty_full.fsdb

waves_almost_flags:
	./$(SIM) +TEST=almost_flags
	verdi -dbdir $(SIM).daidir -ssf almost_flags.fsdb

waves_simultaneous:
	./$(SIM) +TEST=simultaneous
	verdi -dbdir $(SIM).daidir -ssf simultaneous.fsdb

clean:
	rm -rf $(SIM) $(SIM).daidir csrc ucli.key DVEfiles \
	       novas_dump.log *.fsdb *.log *.vpd
```
