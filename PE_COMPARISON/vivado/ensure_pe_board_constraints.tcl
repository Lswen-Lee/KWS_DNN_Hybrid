# Called in an open synthesized/implemented design or the pre-opt hook.
# Ordinary Tcl supports validation logic; project XDC intentionally does not.
if {![llength [get_designs -quiet]]} {error "No open design; open synth/impl first"}
set pb_check_root [file normalize [file join [file dirname [info script]] ..]]
set pb_check_xdc [file join $pb_check_root inputs pe_board_pynq_z2.xdc]
if {![file isfile $pb_check_xdc]} {error "Missing frozen board XDC: $pb_check_xdc"}
if {[llength [get_ports -quiet sys_clk_125m]]!=1} {error "Expected one sys_clk_125m input"}
# Materialize deferred constraints before concluding that the clock is absent.
update_timing
set bc [get_clocks -quiet board_clk]
if {![llength $bc]} {
    if {[llength [get_clocks -quiet -of_objects [get_ports sys_clk_125m]]]} {
        error "Input already has a differently named clock; not overwritten"
    }
    puts "Recovering complete board constraints from $pb_check_xdc"
    source $pb_check_xdc
    update_timing
    set bc [get_clocks -quiet board_clk]
}
if {[llength $bc]!=1} {error "Expected exactly one board_clk after loading board XDC"}
if {abs([get_property PERIOD $bc]-8.0)>0.00001} {error "Expected real 125 MHz clock; not overwritten"}
if {[lsearch -exact [get_clocks -quiet -of_objects [get_ports sys_clk_125m]] [lindex $bc 0]]<0} {
    error "board_clk is not associated with sys_clk_125m"
}
set pb_button_first [get_pins -hier -filter {NAME =~ */clock_reset/button_meta_reg/D}]
if {[llength $pb_button_first]!=1} {error "Expected exactly one first-stage button synchronizer D pin"}
puts "Board constraints checked: real 125 MHz clock and button synchronizer found."
