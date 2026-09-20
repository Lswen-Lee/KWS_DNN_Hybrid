if {![info exists pb_stage] || $pb_stage ni {post_synth post_route}} {error "Invalid board report stage"}
if {![llength [get_designs -quiet]]} {error "Open a design before reporting"}
source [file join [file dirname [info script]] ensure_pe_board_constraints.tcl]
set base [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $base reports $pb_stage [clock format [clock seconds] -format %Y%m%d_%H%M%S]]
set original $report_dir
set index 0
while {[file exists $report_dir]} {incr index; set report_dir ${original}_$index}
file mkdir $report_dir
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir hierarchy.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $report_dir setup_paths.rpt]
report_timing -delay_type min -max_paths 20 -file [file join $report_dir hold_paths.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
report_clocks -file [file join $report_dir clocks.rpt]
report_exceptions -file [file join $report_dir exceptions.rpt]
if {$pb_stage eq "post_route"} {
    report_route_status -file [file join $report_dir route_status.rpt]
    report_drc -file [file join $report_dir drc.rpt]
    report_methodology -file [file join $report_dir methodology.rpt]
}
puts "Board reports: $report_dir (hierarchy separates engine and self-test overhead)"
