# Caller sources per-project config.tcl first. No dependence on GUI pwd.
if {[llength [get_designs -quiet]] == 0} {error "No open design; open synthesized/implemented design first."}
if {[get_property TOP [get_filesets sources_1]] ne $mp_top} {error "Unexpected project top"}
if {[llength [get_ports -quiet clk]] != 1} {error "Expected one clk port"}
set mp_clock [get_clocks -quiet pe_clk]
if {![llength $mp_clock]} {
    if {[llength [get_clocks -quiet -of_objects [get_ports clk]]]} {error "clk has a differently named clock"}
    # Recover the full generated XDC, not only create_clock.
    source $mp_xdc
    set mp_clock [get_clocks -quiet pe_clk]
}
if {[llength $mp_clock] != 1} {error "Expected one pe_clk"}
if {abs([get_property PERIOD $mp_clock] - $mp_period) > 0.00001} {
    error "Clock period mismatch; existing clock is NOT overwritten"
}
if {[lsearch -exact [get_clocks -quiet -of_objects [get_ports clk]] [lindex $mp_clock 0]] < 0} {
    error "pe_clk is not associated with clk"
}
update_timing
# Timing coverage is reported explicitly; existence of a clock alone is not signoff.
puts "PE memory constraints: $mp_top, period=$mp_period ns. Inspect check_timing/unconstrained reports."
