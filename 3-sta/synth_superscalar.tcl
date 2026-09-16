read_liberty /data/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /data/core_riscv_superscalar_gshare_synth.v
link_design core_riscv_superscalar_FINAL
read_sdc /data/constraints.sdc

puts "\n========================================"
puts "DESIGN RULE VIOLATIONS"
puts "========================================"

report_check_types \
    -max_slew \
    -max_capacitance \
    -max_fanout \
    -violators

puts "\n========================================"
puts "WORST SETUP PATHS"
puts "========================================"

report_checks \
    -path_delay max \
    -group_path_count 10 \
    -endpoint_path_count 1 \
    -fields {slew cap input_pins fanout} \
    -digits 4

report_wns
report_tns
report_checks -path_delay max -fields {slew cap input_pins} -digits 3