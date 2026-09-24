# /**************************************************/
# /* Design Compiler synthesis script               */
# /* Asynchronous FIFO                              */
# /*                                                */
# /* Run with:                                      */
# /*   dc_shell-t -f compile_dc.tcl                */
# /*                                                */
# /* OSU FreePDK 45nm                               */
# /**************************************************/


# User/project-specific settings

# RTL source files.
# gray_converter.sv must come first because other files
# import its package.
set my_verilog_files [list \
    ../rtl/gray_converter.sv \
    ../rtl/sync_reset.sv \
    ../rtl/sync_clock.sv \
    ../rtl/dual_port_memory.sv \
    ../rtl/write_handler.sv \
    ../rtl/read_handler.sv \
    ../rtl/async_fifo_top.sv \
]

# RTL top-level module
set my_toplevel async_fifo_top

# Clock port names
set my_write_clock_pin wr_clk
set my_read_clock_pin  rd_clk

# Starting target frequencies.
# These are synthesis targets, not necessarily the final Fmax.
# Start here and adjust upward when checking timing.
set my_write_clk_freq_MHz 100
set my_read_clk_freq_MHz  100

# Optional external input/output delay assumptions
set my_input_delay_ns  0.1
set my_output_delay_ns 0.1


#/**************************************************/
#/* No modifications needed below                  */
#/**************************************************/

# OSU FreePDK 45nm library
set OSU_FREEPDK [format "%s%s" \
    [getenv "PDK_DIR"] \
    "/osu_soc/lib/files"]

set search_path [concat $search_path $OSU_FREEPDK]
set alib_library_analysis_path $OSU_FREEPDK

set link_library [concat \
    [list gscl45nm.db] \
    [list dw_foundation.sldb]]

set target_library "gscl45nm.db"

define_design_lib WORK -path ./WORK

set verilogout_show_unconnected_pins true

set_ultra_optimization true
set_ultra_optimization -force


# Read RTL

analyze -format sverilog $my_verilog_files

elaborate $my_toplevel

current_design $my_toplevel

link
uniquify


# Clock definitions

set my_write_period [expr 1000.0 / $my_write_clk_freq_MHz]
set my_read_period  [expr 1000.0 / $my_read_clk_freq_MHz]

create_clock \
    -name WR_CLK \
    -period $my_write_period \
    [get_ports $my_write_clock_pin]

create_clock \
    -name RD_CLK \
    -period $my_read_period \
    [get_ports $my_read_clock_pin]


# Asynchronous clock-domain crossing constraint

# Write and read clocks are asynchronous.
set_clock_groups -asynchronous \
    -group [get_clocks WR_CLK] \
    -group [get_clocks RD_CLK]


# Driving cell
set_driving_cell -lib_cell INVX1 [all_inputs]


# Input/output timing assumptions

# Write-clock domain ports
set my_write_inputs  [get_ports "wr_en wr_data*"]
set my_write_outputs [get_ports "full almost_full"]

# Read-clock domain ports
set my_read_inputs   [get_ports "rd_en"]
set my_read_outputs  [get_ports "rd_data* empty almost_empty"]

set_input_delay \
    $my_input_delay_ns \
    -clock WR_CLK \
    $my_write_inputs

set_input_delay \
    $my_input_delay_ns \
    -clock RD_CLK \
    $my_read_inputs

set_output_delay \
    $my_output_delay_ns \
    -clock WR_CLK \
    $my_write_outputs

set_output_delay \
    $my_output_delay_ns \
    -clock RD_CLK \
    $my_read_outputs

# rst_n is asynchronous and only drives the two reset synchronisers.
set_false_path -from [get_ports rst_n]


# Synthesis

compile -ungroup_all -map_effort medium

compile -incremental_mapping -map_effort medium


# Checks

check_design

check_timing

report_constraint -all_violators


# Create report directory
file mkdir reports


# Timing reports

# Write-clock domain
redirect reports/write_timing.rep {
    report_timing \
        -group WR_CLK \
        -delay_type max \
        -max_paths 10
}

# Read-clock domain
redirect reports/read_timing.rep {
    report_timing \
        -group RD_CLK \
        -delay_type max \
        -max_paths 10
}

# Clock information
redirect reports/clocks.rep {
    report_clocks
}

# Constraint information
redirect reports/constraints.rep {
    report_constraint -all_violators
}

# Timing sanity check
redirect reports/check_timing.rep {
    check_timing
}


# Area

redirect reports/area.rep {
    report_area
}

redirect reports/area_hierarchy.rep {
    report_area -hierarchy
}


# Power
redirect reports/power.rep {
    report_power
}


# Save synthesized design
set filename [format "%s%s" $my_toplevel ".ddc"]
write -format ddc -hierarchy -output $filename

set filename [format "%s%s" $my_toplevel ".sdc"]
write_sdc $filename


# Finish
quit