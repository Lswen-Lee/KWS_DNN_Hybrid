# Explicit source-relative project base; does not use run-local DIRECTORY.
if {![info exists equivalent_stage] || $equivalent_stage ni {post_synth post_route}} {
    error "Set equivalent_stage post_synth or post_route first."
}
set root [file normalize [file join [file dirname [info script]] ..]]
set top [get_property TOP [get_filesets sources_1]]
if {$top ni {pe8_equivalent_top pe9_equivalent_top}} {error "Unexpected top: $top"}
set variant [string range $top 0 2]
source [file join [file dirname [info script]] ensure_pe_equivalent_constraints.tcl]
set equivalent_clock $pe_constraint_clocks
set stamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
set base [file join $root build ${variant}_equivalent reports $equivalent_stage]
set destination [file join $base $stamp]
set suffix 0
while {[file exists $destination]} {incr suffix; set destination [file join $base ${stamp}_$suffix]}
file mkdir $destination
report_utilization -file [file join $destination total_utilization.rpt]
report_utilization -hierarchical -file [file join $destination hierarchy.rpt]
report_timing_summary -report_unconstrained -file [file join $destination timing_summary.rpt]
report_control_sets -verbose -file [file join $destination control_sets.rpt]
report_clocks -file [file join $destination clocks.rpt]
if {$equivalent_stage eq "post_route"} {
    report_route_status -file [file join $destination route_status.rpt]
    report_drc -file [file join $destination drc.rpt]
    report_methodology -file [file join $destination methodology.rpt]
}
set manifest [open [file join $destination comparison_config.txt] w]
puts $manifest "scope=stream_compute_with_pe8_sum_parameters_v1"
puts $manifest "variant=$variant"
puts $manifest "stage=$equivalent_stage"
puts $manifest "full_xdc_reloaded_for_report=$pe_constraint_reloaded"
puts $manifest "period_ns=[get_property PERIOD $equivalent_clock]"
puts $manifest "part=[get_property PART [current_design]]"
puts $manifest "tool=[version -short]"
close $manifest
puts "Equivalent comparison reports: $destination"
