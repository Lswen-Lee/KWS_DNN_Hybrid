# Explicitly invoked experiment, unlike project-creation scripts.
# Open the routed design first. Saves baseline before changing in-memory design.
set trial_root [file normalize [file join [file dirname [info script]] ..]]
source [file join [file dirname [info script]] design_checks.tcl]
set trial_top [pe_open_array_top]
pe_require_routed
set trial_out [file join $trial_root reports postroute_trial $trial_top [clock format [clock seconds] -format %Y%m%d_%H%M%S]]
if {[file exists $trial_out]} {error "Trial path exists; retry later."}
file mkdir $trial_out
write_checkpoint [file join $trial_out before.dcp]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $trial_out before_timing.rpt]
report_route_status -file [file join $trial_out before_route.rpt]
phys_opt_design -directive Explore
route_design
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $trial_out after_timing.rpt]
report_route_status -file [file join $trial_out after_route.rpt]
report_utilization -file [file join $trial_out after_utilization.rpt]
report_drc -file [file join $trial_out after_drc.rpt]
write_checkpoint [file join $trial_out after.dcp]
puts "Trial saved to $trial_out. Original run DCP is not overwritten."
puts "Compare setup AND hold and route status; improvement is not guaranteed."
puts "OOC clock/boundary limitations remain; this does not certify board timing."
