VCS       = vcs
VCS_FLAGS = -full64 -sverilog -debug_access+all -kdb -lca

# Asynchronous FIFO RTL, shared by both parts.
# gray_converter.sv must come first: the other FIFO files import its package.
FIFO_RTL  = rtl/gray_converter.sv \
            rtl/sync_reset.sv \
            rtl/sync_clock.sv \
            rtl/dual_port_memory.sv \
            rtl/write_handler.sv \
            rtl/read_handler.sv \
            rtl/async_fifo_top.sv

# Part 1: asynchronous FIFO
P1_TOP    = tb_async_fifo
P1_SIMV   = simv_part1
P1_FSDB   = async_fifo.fsdb
# tb/DPI_based/model.cpp is the C++ reference model, compiled by VCS and called through DPI-C
P1_SRCS   = $(FIFO_RTL) tb/DPI_based/model.cpp tb/DPI_based/checker.sv tb/SV_based/fifo_if.sv tb/tb_async_fifo.sv
# SV-class scoreboard classes: `included by tb_async_fifo.sv, listed here so an edit triggers a rebuild
P1_INCS   = tb/SV_based/transaction.sv tb/SV_based/monitor.sv tb/SV_based/scoreboard.sv
P1_TESTS  = empty_full almost_flags simultaneous

# Part 2: even/odd interleaver
P2_TOP    = tb_even_odd_interleaver
P2_SIMV   = simv_part2
P2_FSDB   = even_odd_interleaver.fsdb
P2_SRCS   = $(FIFO_RTL) rtl/even_odd_interleaver_top.sv tb/tb_even_odd_interleaver.sv
P2_TESTS  = case1 case4 case4_odd

TESTS     = $(P1_TESTS) $(P2_TESTS)

.PHONY: all compile test test_part1 test_part2 sim sim_bug $(TESTS) $(addprefix verdi_,$(TESTS)) clean

# Each testbench writes a fixed waveform file name, so tests must not run in parallel
.NOTPARALLEL:

# Default: build both simulators
all: compile

compile: $(P1_SIMV) $(P2_SIMV)

# Rebuild a simulator only when one of its source files changes.
# Each build keeps its own VCS work directory, so the two do not overwrite each other.
$(P1_SIMV): $(P1_SRCS) $(P1_INCS)
	$(VCS) $(VCS_FLAGS) +incdir+tb/SV_based -Mdir=csrc_part1 $(P1_SRCS) -top $(P1_TOP) -o $@

$(P2_SIMV): $(P2_SRCS)
	$(VCS) $(VCS_FLAGS) -Mdir=csrc_part2 $(P2_SRCS) -top $(P2_TOP) -o $@

# Select the simulator and waveform file for each test and its Verdi target
$(P1_TESTS) $(addprefix verdi_,$(P1_TESTS)): SIMV = $(P1_SIMV)
$(P1_TESTS): FSDB = $(P1_FSDB)
$(P1_TESTS): $(P1_SIMV)

$(P2_TESTS) $(addprefix verdi_,$(P2_TESTS)): SIMV = $(P2_SIMV)
$(P2_TESTS): FSDB = $(P2_FSDB)
$(P2_TESTS): $(P2_SIMV)

# Run one test and keep its waveform as <test>.fsdb.
# The waveform is kept even if the test fails; make still reports the failure.
$(TESTS):
	./$(SIMV) -exitstatus +TEST=$@; status=$$?; \
	mv -f $(FSDB) $@.fsdb; exit $$status

# Run groups of tests
test_part1: $(P1_TESTS)
test_part2: $(P2_TESTS)
test: test_part1 test_part2

# FIFO tests with the DPI-C checker, clean design: every test must pass
sim: test_part1

# Run the tests with the injected dropped-write bug; failures are expected.
# Save each run's log and waveform as <test>_bug.log and <test>_bug.fsdb.
BUG_N = 5
sim_bug: $(P1_SIMV)
	for t in $(P1_TESTS); do \
	    ./$(P1_SIMV) +TEST=$$t +INJECT_BUG +BUG_N=$(BUG_N) | tee $${t}_bug.log; \
	    mv -f $(P1_FSDB) $${t}_bug.fsdb; \
	done

# Open a test's waveform in Verdi, e.g. make verdi_case4
$(addprefix verdi_,$(TESTS)):
	verdi -dbdir $(SIMV).daidir -ssf $(@:verdi_%=%).fsdb -nologo &

clean:
	rm -rf $(P1_SIMV) $(P1_SIMV).daidir $(P2_SIMV) $(P2_SIMV).daidir \
	       csrc csrc_part1 csrc_part2 ucli.key vc_hdrs.h DVEfiles \
	       *.log *.fsdb *.vpd novas.conf novas.rc verdiLog
