# Open Implemented Design before sourcing. Reports saved under project/reports.
if {[llength [get_designs -quiet]]==0} {error "Open Implemented Design first"}
set pp_reports [file join [get_property DIRECTORY [current_project]] reports]
file mkdir $pp_reports
report_clocks -file [file join $pp_reports clocks.rpt]
report_utilization -hierarchical -file [file join $pp_reports utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $pp_reports timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -file [file join $pp_reports setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -file [file join $pp_reports hold_paths.rpt]
report_methodology -file [file join $pp_reports methodology.rpt]
report_drc -file [file join $pp_reports drc.rpt]
check_timing -verbose -file [file join $pp_reports check_timing.rpt]
puts "Reports: $pp_reports; inspect generated clock period, setup, hold and unconstrained paths."
