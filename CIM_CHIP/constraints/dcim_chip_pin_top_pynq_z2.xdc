###############################################################################
# PYNQ-Z2 constraints for dcim_chip_pin_top
#
# Target device : XC7Z020-1CLG400C
# PL clock      : 125 MHz on package pin H16 (8.000 ns period)
# I/O voltage   : 3.3 V LVCMOS
# Top module    : dcim_chip_pin_top
#
# This constraint set is intended for standalone synthesis/implementation of
# the current CIM_CHIP digital pin top.  It does not create a 50-MHz clock.
# To operate the DCIM at 50 MHz from the 125-MHz board oscillator, instantiate
# an MMCM/Clocking Wizard in a board wrapper and constrain its generated clock.
#
# Expansion-pin allocation used by this file:
#   Arduino D0-D13 and A0-A5 : input/control signals
#   PMODB 1-4 and 7-10       : input/control signals
#   PMODA 1                  : pd_en
#   PMODA 2                  : sume
#   PMODA 3                  : sumo
#
# PMODA is shared with part of the Raspberry Pi header on PYNQ-Z2. Do not use
# those two connectors for different functions at the same time. Verify every
# external connection is 3.3-V compatible before programming the FPGA.
###############################################################################

# FPGA configuration bank voltage.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

###############################################################################
# 125-MHz board clock
###############################################################################

set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports {clk}]
create_clock -add -name sys_clk_pin -period 8.000 \
    -waveform {0.000 4.000} [get_ports {clk}]

# Do not change the period above to 20 ns merely to request 50 MHz.  XDC only
# describes timing; it cannot divide the physical 125-MHz clock on H16.
###############################################################################
# Arduino header: D0-D13
###############################################################################

# Arduino D0-D2
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {model_rst_n}]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports {reset1}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {reset2}]

# Arduino D3-D9: row_addr[0] through row_addr[6]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {row_addr[0]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {row_addr[1]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {row_addr[2]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {row_addr[3]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {row_addr[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {row_addr[5]}]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports {row_addr[6]}]

# Arduino D10-D13: bank_addr[0] through bank_addr[3]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {bank_addr[0]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {bank_addr[1]}]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {bank_addr[2]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {bank_addr[3]}]

###############################################################################
# Arduino header: A0-A5 used as digital GPIO
###############################################################################

set_property -dict {PACKAGE_PIN Y11 IOSTANDARD LVCMOS33} [get_ports {mode_sel}]
set_property -dict {PACKAGE_PIN Y12 IOSTANDARD LVCMOS33} [get_ports {wl_en}]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports {write_en}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {sense_en}]
set_property -dict {PACKAGE_PIN T5  IOSTANDARD LVCMOS33} [get_ports {pre_en}]
set_property -dict {PACKAGE_PIN U10 IOSTANDARD LVCMOS33} [get_ports {clk_en}]

###############################################################################
# PMODB header
#
# Logical index to physical header pin:
#   [0]=JB1, [1]=JB2, [2]=JB3, [3]=JB4
#   [4]=JB7, [5]=JB8, [6]=JB9, [7]=JB10
###############################################################################

set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {sel_next}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {din[0]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {din[1]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {din[2]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {din[3]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {output_en}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {nv_store}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports {nv_recall}]

###############################################################################
# PMODA header
#
# PMODA is shared with Raspberry Pi GPIO[7:0] on this board.
###############################################################################

set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {pd_en}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {sume}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {sumo}]

###############################################################################
# Electrical defaults
###############################################################################

# Keep the active-low storage-model reset deasserted if its header pin floats.
set_property PULLUP true [get_ports {model_rst_n}]

# Keep active-high resets and functional controls inactive on floating headers.
set_property PULLDOWN true [get_ports {
    reset1 reset2 row_addr[*] bank_addr[*] mode_sel wl_en write_en sense_en
    pre_en clk_en sel_next din[*] output_en nv_store nv_recall pd_en
}]

# Conservative output drive strength for direct header connections.
set_property DRIVE 8 [get_ports {sume sumo}]
set_property SLEW SLOW [get_ports {sume sumo}]

###############################################################################
# External-interface timing
###############################################################################

# The internal sequential logic is constrained by sys_clk_pin above. Input and
# output delays are intentionally not guessed: they depend on the external
# controller, cable and setup/hold requirements. If all header signals are
# driven and sampled synchronously by another 125-MHz device, characterize that
# interface and then add constraints such as the following with verified values:
#
# set_input_delay  -clock sys_clk_pin -max <ns> [get_ports {row_addr[*] ...}]
# set_input_delay  -clock sys_clk_pin -min <ns> [get_ports {row_addr[*] ...}]
# set_output_delay -clock sys_clk_pin -max <ns> [get_ports {sume sumo}]
# set_output_delay -clock sys_clk_pin -min <ns> [get_ports {sume sumo}]

# model_rst_n is an asynchronous reset input. Recovery/removal inside the design
# still needs a proper reset-deassertion strategy; do not hide functional clock
# paths with broad false-path constraints.
