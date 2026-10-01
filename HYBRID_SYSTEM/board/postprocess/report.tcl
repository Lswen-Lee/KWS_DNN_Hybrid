# Open Implemented Design before sourcing. Reports saved under project/reports.
if {[llength [get_designs -quiet]]==0} {error "Open Implemented Design first"}
set pp_reports [file join [get_property DIRECTORY [current_project]] reports]
file mkdir $pp_reports
report_clocks -file [file join $pp_reports clocks.rpt]
report_utilization -hierarchical -file [file join $pp_reports utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $pp_reports timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -file [file join $pp_reports setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -file [file join $pp_reports hold_paths.rpt]
# Preserve separate datapath hierarchy (KEEP_HIERARCHY, not DONT_TOUCH).
# Internal: both endpoints in DUT/tail. Inbound: any source -> DUT/tail FF.
set pp_regs [get_cells -hier -filter {IS_SEQUENTIAL == 1 && (NAME =~ test/dut/* || NAME =~ test/tail/*)}]
if {[llength $pp_regs]} {
    report_timing -delay_type max -from $pp_regs -to $pp_regs -max_paths 10 -file [file join $pp_reports postprocess_internal_setup.rpt]
    report_timing -delay_type max -to $pp_regs -max_paths 10 -file [file join $pp_reports postprocess_inbound_setup.rpt]
    report_timing -delay_type min -from $pp_regs -to $pp_regs -max_paths 10 -file [file join $pp_reports postprocess_internal_hold.rpt]
} else {
    puts "WARNING: No postprocess registers matched; inspect synthesized hierarchy. Do not infer timing PASS from missing paths."
}
report_methodology -file [file join $pp_reports methodology.rpt]
report_drc -file [file join $pp_reports drc.rpt]
check_timing -verbose -file [file join $pp_reports check_timing.rpt]
puts "Reports: $pp_reports; inspect generated clock period, setup, hold and unconstrained paths."
