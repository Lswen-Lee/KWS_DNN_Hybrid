# Vivado XSim GUI: launch tb_dcim_pin_master before sourcing this file.
create_wave_config DCIM_GROUPED
restart

set tb /tb_dcim_pin_master

# 01: Command, clock and Master state
set g_cmd [add_wave_group "01_COMMAND_STATE"]
foreach sig {
    clk rst start operation busy done result_valid error activation_is_a8
    dut/state dut/stage_count dut/plane_count
} {
    add_wave -into $g_cmd ${tb}/${sig}
    log_wave ${tb}/${sig}
}

# 02: Actual Chip input ports
set g_in [add_wave_group "02_CHIP_INPUT_PINS"]
foreach sig {
    clk model_rst_n reset1 reset2 mode_sel wl_en write_en sense_en pre_en
    clk_en sel_next output_en nv_store nv_recall pd_en
} {
    add_wave -into $g_in ${tb}/chip/${sig}
    log_wave ${tb}/chip/${sig}
}
foreach sig {row_addr bank_addr} {
    add_wave -into $g_in -radix unsigned ${tb}/chip/${sig}
    log_wave ${tb}/chip/${sig}
}
add_wave -into $g_in -radix hex ${tb}/chip/din
log_wave ${tb}/chip/din

# 03: Actual serial output ports
set g_out [add_wave_group "03_CHIP_OUTPUT_PINS"]
foreach sig {clk sume sumo} {
    add_wave -into $g_out ${tb}/chip/${sig}
    log_wave ${tb}/chip/${sig}
}

# 04: Received results and testbench golden values (not Chip ports)
set g_result [add_wave_group "04_RECEIVED_RESULTS"]
foreach sig {done result_valid error} {
    add_wave -into $g_result ${tb}/${sig}
    log_wave ${tb}/${sig}
}
add_wave -into $g_result -radix hex ${tb}/sram_read_data
log_wave ${tb}/sram_read_data
foreach sig {
    even_raw_result odd_raw_result expected_even expected_odd actual_w8 expected_w8
} {
    add_wave -into $g_result -radix unsigned ${tb}/${sig}
    log_wave ${tb}/${sig}
}

run all

