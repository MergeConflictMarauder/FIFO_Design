###################################################################

# Created by write_sdc on Thu Sep 24 18:05:40 2026

###################################################################
set sdc_version 2.1

set_units -time ns -resistance kOhm -capacitance pF -voltage V -current uA
set_driving_cell -lib_cell INVX1 [get_ports wr_clk]
set_driving_cell -lib_cell INVX1 [get_ports rd_clk]
set_driving_cell -lib_cell INVX1 [get_ports rst_n]
set_driving_cell -lib_cell INVX1 [get_ports wr_en]
set_driving_cell -lib_cell INVX1 [get_ports rd_en]
set_driving_cell -lib_cell INVX1 [get_ports {wr_data[7]}]
set_driving_cell -lib_cell INVX1 [get_ports {wr_data[6]}]
set_driving_cell -lib_cell INVX1 [get_ports {wr_data[5]}]
set_driving_cell -lib_cell INVX1 [get_ports {wr_data[4]}]
set_driving_cell -lib_cell INVX1 [get_ports {wr_data[3]}]
set_driving_cell -lib_cell INVX1 [get_ports {wr_data[2]}]
set_driving_cell -lib_cell INVX1 [get_ports {wr_data[1]}]
set_driving_cell -lib_cell INVX1 [get_ports {wr_data[0]}]
create_clock [get_ports wr_clk]  -name WR_CLK  -period 10  -waveform {0 5}
create_clock [get_ports rd_clk]  -name RD_CLK  -period 10  -waveform {0 5}
set_input_delay -clock RD_CLK  0.1  [get_ports rst_n]
set_input_delay -clock RD_CLK  0.1  [get_ports wr_en]
set_input_delay -clock RD_CLK  0.1  [get_ports rd_en]
set_input_delay -clock RD_CLK  0.1  [get_ports {wr_data[7]}]
set_input_delay -clock RD_CLK  0.1  [get_ports {wr_data[6]}]
set_input_delay -clock RD_CLK  0.1  [get_ports {wr_data[5]}]
set_input_delay -clock RD_CLK  0.1  [get_ports {wr_data[4]}]
set_input_delay -clock RD_CLK  0.1  [get_ports {wr_data[3]}]
set_input_delay -clock RD_CLK  0.1  [get_ports {wr_data[2]}]
set_input_delay -clock RD_CLK  0.1  [get_ports {wr_data[1]}]
set_input_delay -clock RD_CLK  0.1  [get_ports {wr_data[0]}]
set_output_delay -clock RD_CLK  0.1  [get_ports {rd_data[7]}]
set_output_delay -clock RD_CLK  0.1  [get_ports {rd_data[6]}]
set_output_delay -clock RD_CLK  0.1  [get_ports {rd_data[5]}]
set_output_delay -clock RD_CLK  0.1  [get_ports {rd_data[4]}]
set_output_delay -clock RD_CLK  0.1  [get_ports {rd_data[3]}]
set_output_delay -clock RD_CLK  0.1  [get_ports {rd_data[2]}]
set_output_delay -clock RD_CLK  0.1  [get_ports {rd_data[1]}]
set_output_delay -clock RD_CLK  0.1  [get_ports {rd_data[0]}]
set_output_delay -clock RD_CLK  0.1  [get_ports almost_full]
set_output_delay -clock RD_CLK  0.1  [get_ports full]
set_output_delay -clock RD_CLK  0.1  [get_ports almost_empty]
set_output_delay -clock RD_CLK  0.1  [get_ports empty]
set_clock_groups  -asynchronous -name WR_CLK_1  -group [get_clocks WR_CLK]     \
-group [get_clocks RD_CLK]
