# Open implemented design first; reports belong to this project's reports dir.
if {![llength [get_designs -quiet]]} {error "Open synthesized or implemented design first"}
set out [file join [get_property DIRECTORY [current_project]] reports]
file mkdir $out
report_clocks -file [file join $out clocks.rpt]
report_utilization -hierarchical -file [file join $out utilization_hier.rpt]
report_timing_summary -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 20 -file [file join $out setup_paths.rpt]
report_timing -delay_type min -max_paths 20 -file [file join $out hold_paths.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_clock_interaction -file [file join $out clock_interaction.rpt]
report_exceptions -file [file join $out exceptions.rpt]
report_drc -file [file join $out drc.rpt]
report_methodology -file [file join $out methodology.rpt]
puts "Reports: $out. No automatic timing/CDC signoff is implied."
