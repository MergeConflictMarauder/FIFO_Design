VCS      = vcs
VCS_FLAGS = -sverilog -full64 -kdb -debug_access+all
TOP      = tb_async_fifo
SIM      = simv
FSDB     = async_fifo.fsdb

# Add/remove RTL source files here as needed.
# gray_converter.sv must come first: the other RTL files import its package.
RTL      = rtl/gray_converter.sv \
           rtl/sync_reset.sv \
           rtl/sync_clock.sv \
           rtl/dual_port_memory.sv \
           rtl/write_handler.sv \
           rtl/read_handler.sv \
           rtl/async_fifo_top.sv
TB       = tb/tb_async_fifo.sv

.PHONY: all compile empty_full almost_flags simultaneous waves clean

all: compile

compile:
	$(VCS) $(VCS_FLAGS) -top $(TOP) $(RTL) $(TB) -o $(SIM)

# -exitstatus makes simv exit nonzero on a test error, so make stops
empty_full: compile
	./$(SIM) -exitstatus +TEST=empty_full

almost_flags: compile
	./$(SIM) -exitstatus +TEST=almost_flags

simultaneous: compile
	./$(SIM) -exitstatus +TEST=simultaneous

# No -exitstatus here, so Verdi still opens when the test fails
waves: compile
	./$(SIM) +TEST=simultaneous
	verdi -dbdir $(SIM).daidir -ssf $(FSDB)

clean:
	rm -rf $(SIM) $(SIM).daidir csrc ucli.key DVEfiles novas_dump.log \
	       *.fsdb *.log *.vpd
