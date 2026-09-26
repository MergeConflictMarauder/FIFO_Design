VCS       = vcs
VCS_FLAGS = -sverilog -full64 -kdb -debug_access+all
TOP       = tb_even_odd_interleaver
SIM       = simv_even_odd_interleaver
FSDB      = even_odd_interleaver.fsdb

# Add/remove RTL source files here as needed.
# gray_converter.sv must come first: the other RTL files import its package.
RTL       = rtl/gray_converter.sv \
            rtl/sync_reset.sv \
            rtl/sync_clock.sv \
            rtl/dual_port_memory.sv \
            rtl/write_handler.sv \
            rtl/read_handler.sv \
            rtl/async_fifo_top.sv \
            rtl/even_odd_interleaver_top.sv

TB        = tb/tb_even_odd_interleaver.sv

.PHONY: all compile sizing reverse alternating stall regress waves clean

# Default: compile the design
all: compile

# Compile once
compile:
	$(VCS) $(VCS_FLAGS) -top $(TOP) $(RTL) $(TB) -o $(SIM)

# Run each interleaver verification case.
sizing: compile
	./$(SIM) -exitstatus +TEST=sizing

reverse: compile
	./$(SIM) -exitstatus +TEST=reverse

alternating: compile
	./$(SIM) -exitstatus +TEST=alternating

stall: compile
	./$(SIM) -exitstatus +TEST=stall

regress: compile
	./$(SIM) -exitstatus +TEST=sizing
	./$(SIM) -exitstatus +TEST=reverse
	./$(SIM) -exitstatus +TEST=alternating
	./$(SIM) -exitstatus +TEST=stall

# Run tests and open their waveform in Verdi
waves:
	./$(SIM) +TEST=$(TEST)
	verdi -dbdir $(SIM).daidir -ssf $(FSDB)

clean:
	rm -rf $(SIM) $(SIM).daidir csrc ucli.key DVEfiles novas_dump.log \
	       *.fsdb *.log *.vpd
