read_liberty /data/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /data/core_riscv_cacheless_synth.v
link_design core_riscv
read_sdc /data/constraints.sdc

report_wns
report_tns
report_checks -path_delay max -fields {slew cap input_pins} -digits 3