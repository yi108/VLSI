# Design Compiler synthesis script template for VSD HW2.
# Run on the course server (library setup comes from the course .synopsys_dc.setup):
#   dc_shell -f script/synthesis.tcl
set top_name top

# read RTL
set search_path [concat $search_path ./src]
analyze -format sverilog [glob ./src/*.sv]
elaborate $top_name
current_design $top_name
link

# constraints
source ./script/DC.sdc
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

# compile
compile_ultra -no_autoungroup

# reports / outputs expected by the submission hierarchy
file mkdir ./syn
report_area  -hierarchy          > ./syn/area_rpt.txt
report_timing -delay_type max    > ./syn/timing_max_rpt.txt
write -format verilog -hierarchy -output ./syn/top_syn.v
write_sdf ./syn/top_syn.sdf
write -format ddc -hierarchy -output ./syn/top_syn.ddc
exit
