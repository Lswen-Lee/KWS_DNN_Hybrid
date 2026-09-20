###############################################################################
# PYNQ-Z2 standalone constraints for dcim_master_chip_top
# Device : XC7Z020-1CLG400C
# Input  : 125-MHz oscillator on H16
# Output : four onboard LEDs
###############################################################################

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} \
    [get_ports {sys_clk_125m}]
create_clock -add -name sys_clk_125m -period 8.000 \
    -waveform {0.000 4.000} [get_ports {sys_clk_125m}]

# BTN0: active-high reset/rerun button.
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} \
    [get_ports {reset_button}]
set_property PULLDOWN true [get_ports {reset_button}]

# LED0=clock locked, LED1=busy, LED2=pass, LED3=fail.
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

set_property DRIVE 8 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]

# The MMCM primitive defines the generated 50-MHz clock.  Confirm it after
# synthesis with report_clocks; do not create a fictitious 20-ns clock on H16.
