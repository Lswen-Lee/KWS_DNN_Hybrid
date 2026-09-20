if {![info exists mp_stage] || $mp_stage ni {post_synth post_route}} {error "Invalid report stage"}
source [file join [file dirname [info script]] ensure_pe_memory_constraints.tcl]
set report_dir [file join $mp_destination reports $mp_stage [clock format [clock seconds] -format %Y%m%d_%H%M%S]]
set original_dir $report_dir
set suffix 0
while {[file exists $report_dir]} {incr suffix; set report_dir ${original_dir}_$suffix}
file mkdir $report_dir
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir hierarchy.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -file [file join $report_dir setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -file [file join $report_dir hold_paths.rpt]
report_clocks -file [file join $report_dir clocks.rpt]
report_control_sets -verbose -file [file join $report_dir control_sets.rpt]
check_timing -verbose -file [file join $report_dir check_timing.rpt]
if {$mp_stage eq "post_route"} {
    report_route_status -file [file join $report_dir route_status.rpt]
    report_drc -file [file join $report_dir drc.rpt]
    report_methodology -file [file join $report_dir methodology.rpt]
}
set f [open [file join $report_dir comparison_config.txt] w]
# A run hook may execute in a non-project process without get_runs objects.
set mp_synth_strategy unavailable_in_hook
set mp_impl_strategy unavailable_in_hook
if {[llength [get_runs -quiet synth_1]]} {set mp_synth_strategy [get_property STRATEGY [get_runs synth_1]]}
if {[llength [get_runs -quiet impl_1]]} {set mp_impl_strategy [get_property STRATEGY [get_runs impl_1]]}
foreach {key value} [list scope memory_backed_pe_operand_v2 variant $mp_variant top $mp_top stage $mp_stage \
    frequency_mhz $mp_frequency period_ns [get_property PERIOD $mp_clock] \
    tool [version -short] part [get_property PART [current_design]] \
    synthesis_strategy $mp_synth_strategy \
    implementation_strategy $mp_impl_strategy \
    boundary_model abstract_OOC_not_board_signoff] {puts $f "$key=$value"}
close $f
puts "Memory-backed comparison reports: $report_dir"
