# Design constraints for VSD HW2 (max allowed clock period: 2.0 ns).
# Keep clk_period identical to `define CYCLE in sim/top_tb.sv.
set clk_period 2.0

create_clock -name clk -period $clk_period [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks clk]
set_fix_hold [get_clocks clk]

set input_max  [expr double(round(1000*$clk_period * 0.6))/1000]
set input_min  [expr double(round(1000*$clk_period * 0.0))/1000]
set output_max [expr double(round(1000*$clk_period * 0.1))/1000]
set output_min [expr double(round(1000*$clk_period * 0.0))/1000]

set_input_delay  -max $input_max  -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay  -min $input_min  -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -max $output_max -clock clk [all_outputs]
set_output_delay -min $output_min -clock clk [all_outputs]
