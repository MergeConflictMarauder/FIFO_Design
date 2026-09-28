VCS       = vcs
VCS_FLAGS = -full64 -sverilog -debug_access+all -kdb -lca
TOP       = tb_even_odd_interleaver
SIMV      = simv_part2
FSDB      = even_odd_interleaver.fsdb

# gray_converter.sv must come first: the other FIFO files import its package.
SRCS      = rtl/gray_converter.sv \
            rtl/sync_reset.sv \
            rtl/sync_clock.sv \
            rtl/dual_port_memory.sv \
            rtl/write_handler.sv \
            rtl/read_handler.sv \
            rtl/async_fifo_top.sv \
            rtl/even_odd_interleaver_top.sv \
            tb/tb_even_odd_interleaver.sv

CASES     = case1 case4 case4_odd

.PHONY: all compile test $(CASES) $(addprefix verdi_,$(CASES)) clean

# Default: build the simulator
all: compile

compile: $(SIMV)

# Rebuild only when a source file changes
$(SIMV): $(SRCS)
	$(VCS) $(VCS_FLAGS) $(SRCS) -top $(TOP) -o $(SIMV)

# Run one test and keep its waveform as <test>.fsdb.
# The waveform is kept even if the test fails; make still reports the failure.
$(CASES): $(SIMV)
	./$(SIMV) -exitstatus +TEST=$@; status=$$?; \
	mv -f $(FSDB) $@.fsdb; exit $$status

# Run every test
test: $(CASES)

# Open a test's waveform in Verdi, e.g. make verdi_case4
$(addprefix verdi_,$(CASES)):
	verdi -dbdir $(SIMV).daidir -ssf $(@:verdi_%=%).fsdb -nologo &

clean:
	rm -rf $(SIMV) $(SIMV).daidir csrc \
	       ucli.key *.log *.fsdb *.vpd \
	       novas.conf novas.rc verdiLog
