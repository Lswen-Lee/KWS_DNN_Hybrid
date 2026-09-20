# Classify the OPEN netlist by its interface, not the design object's NAME.
# NAME can be synth_1/impl_1 or another arbitrary open_run alias.
proc pe_open_array_top {} {
    current_design
    foreach port {clk rst clear accumulate_en} {
        if {[llength [get_ports -quiet $port]] != 1} {error "Not a PE array: missing $port"}
    }
    foreach {pattern count} {lane_mask* 12 weight_vector_i8* 96 result_vector_s32* 384} {
        if {[llength [get_ports -quiet $pattern]] != $count} {
            error "Not a raw PE array: unexpected width for $pattern"
        }
    }
    set a9 [llength [get_ports -quiet activation_centered*]]
    set a8 [llength [get_ports -quiet activation_s8*]]
    if {$a9 == 9 && $a8 == 0} {return pe_array_12}
    if {$a8 == 8 && $a9 == 0} {return pe8_array_12}
    error "Cannot identify raw PE variant from open netlist ports."
}
proc pe_require_routed {} {
    set status [report_route_status -return_string]
    foreach {key expression} {
        total {# of routable nets[. ]*:[ ]*([0-9]+)}
        done {# of fully routed nets[. ]*:[ ]*([0-9]+)}
        errors {# of nets with routing errors[. ]*:[ ]*([0-9]+)}
    } {
        if {![regexp $expression $status match value]} {
            error "Cannot confirm routed state from report_route_status. Inspect report manually; optimization not started."
        }
        set counts($key) $value
    }
    if {$counts(total) == 0 || $counts(done) != $counts(total) || $counts(errors) != 0} {
        error "Open a completed routed design: routable=$counts(total), routed=$counts(done), errors=$counts(errors). Use Open Implemented Design, not Open Synthesized Design."
    }
}
