# PYNQ-Z2 standalone 125 MHz PL clock, BTN0, four discrete LEDs.
# Ordinary top-level implementation only. Do not add the OOC XDC.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports sys_clk_125m]
create_clock -name board_clk -period 8.000 [get_ports sys_clk_125m]
set_clock_uncertainty 0.200 [get_clocks board_clk]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33 PULLDOWN true} [get_ports reset_button]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property DRIVE 8 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]
# Asynchronous human button: cut ONLY the first synchronizer D pin.
# Keep stage1 -> stage2 and all internal reset/data paths timed.
set button_first [get_pins -hier -filter {NAME =~ */clock_reset/button_meta_reg/D}]
# Object-count validation belongs in a Tcl hook, not in project XDC.
set_false_path -from [get_ports reset_button] -to $button_first
# LEDs are human indicators, not a clocked receiving interface.
set_false_path -to [get_ports {led[*]}]
