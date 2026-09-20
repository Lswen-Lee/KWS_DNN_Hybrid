# OOC core timing constraints; see PE_COMPARISON_GUIDE.md.
create_clock -name pe_clk \
    -period 8.000 \
    -waveform {0.000 4.000} \
    [get_ports clk]

# OOC core timing constraints; see PE_COMPARISON_GUIDE.md.
set_clock_uncertainty 0.200 [get_clocks pe_clk]

# OOC core timing constraints; see PE_COMPARISON_GUIDE.md.
# OOC core timing constraints; see PE_COMPARISON_GUIDE.md.
# OOC core timing constraints; see PE_COMPARISON_GUIDE.md.
set_input_delay -clock [get_clocks pe_clk] -max 2.000 \
    [get_ports -filter {DIRECTION == IN && NAME != clk}]

set_input_delay -clock [get_clocks pe_clk] -min 0.500 \
    [get_ports -filter {DIRECTION == IN && NAME != clk}]

# OOC core timing constraints; see PE_COMPARISON_GUIDE.md.
set_output_delay -clock [get_clocks pe_clk] -max 2.000 \
    [get_ports -filter {DIRECTION == OUT}]

set_output_delay -clock [get_clocks pe_clk] -min 0.500 \
    [get_ports -filter {DIRECTION == OUT}]
