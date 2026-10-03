# ============================================================
# RV32I v3 Superscalar - OpenSTA Timing Analysis
# Register-to-register datapath analysis
# ============================================================

read_liberty /data/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /data/core_riscv_superscalar_bimodal_synth.v
link_design core_riscv_superscalar
read_sdc /data/constraints.sdc


puts "\n========================================"
puts "TIMING SUMMARY"
puts "========================================"

report_wns
report_tns


# ------------------------------------------------------------
# Overall worst paths
# ------------------------------------------------------------

puts "\n========================================"
puts "WORST 5 SETUP PATHS - OVERALL"
puts "========================================"

report_checks \
    -path_delay max \
    -group_path_count 5 \
    -endpoint_path_count 1 \
    -fields {slew fanout} \
    -digits 3


# ------------------------------------------------------------
# Collect register Q and D pins
# ------------------------------------------------------------

set reg_q_pins [get_pins -hierarchical */Q]
set reg_d_pins [get_pins -hierarchical */D]

puts "\nRegister Q pins found: [llength $reg_q_pins]"
puts "Register D pins found: [llength $reg_d_pins]"


# ------------------------------------------------------------
# REGISTER -> REGISTER ONLY
#
# This excludes primary inputs such as cpu_enable and imem
# from being timing startpoints.
# ------------------------------------------------------------
puts "\n========================================"
puts "WORST 20 REGISTER-TO-REGISTER PATHS"
puts "========================================"

if {[llength $reg_q_pins] > 0 && [llength $reg_d_pins] > 0} {

    report_checks \
        -path_delay max \
        -from $reg_q_pins \
        -to $reg_d_pins \
        -group_path_count 20 \
        -endpoint_path_count 1 \
        -fields {slew fanout} \
        -digits 3

} else {

    puts "WARNING: Could not find register Q/D pins."

}

puts "\n========================================"
puts "END OF TIMING REPORT"
puts "========================================"