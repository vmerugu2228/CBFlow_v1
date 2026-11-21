# opensky_chip functional constraints (sky130hd) — 20 ns clock (50 MHz)
create_clock -name core_clock -period 20.0 [get_ports clk]
set_clock_uncertainty 0.5 [get_clocks core_clock]
set_input_delay  4.0 -clock core_clock [delete_from_list [all_inputs] [get_ports {clk rst_n}]]
set_output_delay 4.0 -clock core_clock [all_outputs]
set_false_path -from [get_ports rst_n]
set_load 0.033 [all_outputs]
