# Source after opening synthesized or implemented design.
# Report folders are timestamped; previous reports are not overwritten.
set root [file normalize [file join [file dirname [info script]] ..]]
set design [current_design]
source [file join [file dirname [info script]] design_checks.tcl]
set top [pe_open_array_top]
if {$top eq "pe_array_12"} {set variant pe9} elseif {$top eq "pe8_array_12"} {set variant pe8} else {
    error "Unexpected design $top: open pe_array_12 or pe8_array_12."
}
set out [file join $root reports $variant [clock format [clock seconds] -format %Y%m%d_%H%M%S]]
if {[file exists $out]} {error "Report directory already exists; retry in a second."}
file mkdir $out
report_utilization -file [file join $out utilization.rpt]
report_utilization -hierarchical -file [file join $out utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -path_type full_clock_expanded -file [file join $out setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -path_type full_clock_expanded -file [file join $out hold_paths.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]
report_methodology -file [file join $out methodology.rpt]
set f [open [file join $out metadata.txt] w]
puts $f "top=$top"
puts $f "vivado=[version -short]"
puts $f "part=[get_property PART $design]"
puts $f "scope=raw_array_excludes_input_conversion_and_correction"
puts $f "routing_stage=verify_route_status.rpt_manually"
close $f
puts "Reports saved to $out"
puts "Check route_status and unconstrained paths before calling this a post-route timing comparison."
