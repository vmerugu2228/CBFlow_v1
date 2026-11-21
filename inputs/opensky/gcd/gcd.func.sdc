# gcd functional constraints (sky130hd) — 20 ns clock
create_clock -name core_clock -period 20.0 [get_ports clk]
set_clock_uncertainty 0.25 [get_clocks core_clock]
set_input_delay  2.0 -clock core_clock [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 2.0 -clock core_clock [all_outputs]
set_load 0.033 [all_outputs]
