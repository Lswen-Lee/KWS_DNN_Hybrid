# Runs only on an OPEN netlist. Reload the full reference XDC if the
# checkpoint/run has lost pe_clk. Never overwrite an existing wrong clock.
if {[llength [get_designs -quiet]] == 0} {
    error "PE constraints: no open design. Open the synthesized design first."
}
if {[llength [get_ports -quiet clk]] != 1} {
    error "PE constraints: expected one top-level clk port."
}
set pe_constraint_file [file normalize [file join [file dirname [info script]] .. constraints pe_equivalent_ooc.xdc]]
if {![file isfile $pe_constraint_file]} {error "Missing XDC: $pe_constraint_file"}
update_timing
set pe_constraint_reloaded 0
set pe_constraint_clocks [get_clocks -quiet pe_clk]
if {[llength $pe_constraint_clocks] == 0} {
    if {[llength [get_clocks -quiet -of_objects [get_ports clk]]] != 0} {
        error "PE constraints: clk already has a differently named clock; inspect constraints before replacing it."
    }
    puts "PE constraints: pe_clk missing; sourcing full XDC: $pe_constraint_file"
    source $pe_constraint_file
    update_timing
    set pe_constraint_reloaded 1
    set pe_constraint_clocks [get_clocks -quiet pe_clk]
}
if {[llength $pe_constraint_clocks] != 1} {
    error "PE constraints: expected exactly one pe_clk after loading XDC."
}
set pe_constraint_period [get_property PERIOD $pe_constraint_clocks]
if {![string is double -strict $pe_constraint_period] || abs($pe_constraint_period - 8.0) > 0.000001} {
    error "PE constraints: expected 8 ns, got $pe_constraint_period; not overwritten."
}
if {[lsearch -exact [get_clocks -quiet -of_objects [get_ports clk]] [lindex $pe_constraint_clocks 0]] < 0} {
    error "PE constraints: pe_clk is not associated with the top clk port."
}
puts "PE constraints ready: pe_clk=$pe_constraint_period ns; full_xdc_reloaded=$pe_constraint_reloaded"
