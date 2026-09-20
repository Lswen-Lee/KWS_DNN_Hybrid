# Abstract identical synchronous environment, not physical PYNQ pin timing.
create_clock -name pe_clk -period 8.000 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks pe_clk]
set_input_delay -clock pe_clk -max 2.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay -clock pe_clk -min 0.500 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock pe_clk -max 2.000 [get_ports -filter {DIRECTION == OUT}]
set_output_delay -clock pe_clk -min 0.500 [get_ports -filter {DIRECTION == OUT}]
# Do not fake HD.CLK_SRC/PARTPIN placements or hide reset timing. The OOC
# boundary route/skew limitations must accompany any timing interpretation.
