# Resume configuration after Common 17-170 interrupted project creation.
# Does not reset runs, overwrite source files, or start synthesis.
if {[llength [get_projects -quiet]] != 1} {error "Open the PE equivalent XPR first."}
set repair_top [get_property TOP [get_filesets sources_1]]
if {$repair_top ni {pe8_equivalent_top pe9_equivalent_top}} {error "Unexpected top: $repair_top"}
set repair_dir [file dirname [file normalize [info script]]]
set repair_xdc [file normalize [file join $repair_dir .. constraints pe_equivalent_ooc.xdc]]
if {![file isfile $repair_xdc]} {error "Missing XDC: $repair_xdc"}
if {[llength [get_files -quiet $repair_xdc]] == 0} {
    add_files -fileset constrs_1 -norecurse $repair_xdc
}
set_property IS_ENABLED true [get_files $repair_xdc]
set_property USED_IN {synthesis implementation out_of_context} [get_files $repair_xdc]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP 0 [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.TCL.POST [file join $repair_dir report_equivalent_post_synth.tcl] [get_runs synth_1]
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $repair_dir prepare_pe_equivalent_impl.tcl] [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.TCL.POST [file join $repair_dir report_equivalent_post_route.tcl] [get_runs impl_1]
update_compile_order -fileset sources_1
puts "OOC: [get_property {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} [get_runs synth_1]]"
puts "XDC USED_IN: [get_property USED_IN [get_files $repair_xdc]]"
puts "Configuration repaired. Run synthesis/implementation manually; no run was reset or launched."
