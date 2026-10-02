read_liberty /data/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /data/core_riscv_superscalar_gshare_synth.v
link_design core_riscv_superscalar_FINAL
read_sdc /data/constraints.sdc

puts "\n========================================"
puts "TIMING SUMMARY"
puts "========================================"

report_wns
report_tns

puts "\n========================================"
puts "WORST 5 SETUP PATHS"
puts "========================================"

report_checks \
    -path_delay max \
    -group_path_count 5 \
    -endpoint_path_count 1 \
    -fields {slew fanout} \
    -digits 3