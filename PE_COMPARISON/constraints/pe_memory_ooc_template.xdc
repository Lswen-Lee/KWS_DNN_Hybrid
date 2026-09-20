# Abstract synchronous environment, NOT board pin timing. Generated per project.
create_clock -name pe_clk -period @PERIOD_NS@ [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks pe_clk]
set_input_delay -clock pe_clk -max 2.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay -clock pe_clk -min 0.500 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock pe_clk -max 2.000 [get_ports -filter {DIRECTION == OUT}]
set_output_delay -clock pe_clk -min 0.500 [get_ports -filter {DIRECTION == OUT}]
# Do not invent HD.CLK_SRC / HD.PARTPIN_LOCS or false-path functional ports.
