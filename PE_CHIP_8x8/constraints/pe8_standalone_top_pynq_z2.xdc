# PYNQ-Z2 / xc7z020clg400-1, normal top-level implementation (NOT OOC).
# Pin reference:
# https://github.com/Xilinx/xup_fpga_vivado_flow/blob/main/source/pynq-z2/lab5/uart_led_pins_pynq.xdc
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name board_clk_125m -period 8.000 -waveform {0.000 4.000} [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks board_clk_125m]

# BTN0 only feeds the asynchronous preset of the reset synchronizer.
# Do not false-path the downstream synchronous core reset/control signals.
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33 PULLDOWN true} [get_ports reset_btn]
set_false_path -from [get_ports reset_btn]

set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property DRIVE 8 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]
# Human-visible indicators are not sampled by an external synchronous receiver.
# All INTERNAL register-to-register paths remain timed.
set_false_path -to [get_ports {led[*]}]
