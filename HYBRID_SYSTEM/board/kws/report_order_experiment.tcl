# Open Implemented Design before sourcing. Does not change constraints or RTL.
if {[llength [get_designs -quiet]] == 0} {error "Open Implemented Design first"}
if {![string match *route* [string tolower [get_property STATUS [get_runs impl_1]]]]} {
    error "impl_1 must have completed routing; inspect its status first"
}
set order_reports [file join [get_property DIRECTORY [current_project]] reports order]
file mkdir $order_reports
report_timing_summary -report_unconstrained -file [file join $order_reports timing_summary.rpt]
report_timing -delay_type max -max_paths 100 -nworst 1 -file [file join $order_reports setup_paths.rpt]
report_utilization -hierarchical -file [file join $order_reports utilization_hier.rpt]
report_cdc -details -file [file join $order_reports cdc.rpt]
set order_info [open [file join $order_reports configuration.txt] w]
puts $order_info "Vivado [version -short]"
puts $order_info "Generics: [get_property GENERIC [get_filesets sources_1]]"
puts $order_info "Implementation: [get_property STATUS [get_runs impl_1]]"
close $order_info
puts "Reports: $order_reports (check setup AND hold; completion is not timing pass)"
