create_clock -name clk -period 17.000 [get_ports clk]
set_clock_uncertainty 0.250 [get_clocks clk]

set data_inputs [list]

foreach port [get_ports *] {
    if {[get_property $port direction] eq "input" &&
        [get_property $port full_name] ne "clk"} {
        lappend data_inputs $port
    }
}

set_input_delay -clock clk 2.000 $data_inputs
set_output_delay -clock clk 2.000 [all_outputs]


set_driving_cell \
    -lib_cell sky130_fd_sc_hd__buf_2 \
    $data_inputs

set_load 0.030 [all_outputs]
set_max_transition 1.500 [current_design]
set_max_fanout 20 [current_design]