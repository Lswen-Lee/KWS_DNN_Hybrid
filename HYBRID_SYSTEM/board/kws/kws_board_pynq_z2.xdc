# Normal board flow; PYNQ-Z2 XC7Z020-1CLG400C. Same pins as existing DCIM board.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports sys_clk_125m]
create_clock -name sys_clk_125m -period 8.000 [get_ports sys_clk_125m]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33 PULLDOWN true} [get_ports reset_button]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property DRIVE 8 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]
# Button is asynchronous; LEDs are human-readable status, not timed interfaces.
set_false_path -from [get_ports reset_button]
set_false_path -to [get_ports {led[*]}]
# MMCM generates 53MHz. Do NOT globally false-path/group the two clock domains:
# bundled mailbox data must remain physically bounded (see pre_opt.tcl).
