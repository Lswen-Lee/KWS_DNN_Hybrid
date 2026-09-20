# Import only. GUI: set pe_variant pe8 (or pe9), then source this file.
if {![info exists pe_variant] || $pe_variant ni {pe8 pe9}} {
    error "Set pe_variant to pe8 or pe9 before sourcing this script."
}
if {[llength [get_projects -quiet]]} {error "Close the current project first."}
set equivalent_root [file normalize [file join [file dirname [info script]] ..]]
set parent [file dirname $equivalent_root]
set destination [file join $equivalent_root build ${pe_variant}_equivalent]
if {[file exists $destination]} {error "Directory already exists: $destination. Open the XPR; no overwrite."}
if {$pe_variant eq "pe8"} {
    set array_dir [file join $parent PE_CHIP_8x8 rtl]
    set sources [list [file join $array_dir pe8_pkg.sv] \
        [file join $array_dir arithmetic pe8_mac_lane.sv] \
        [file join $array_dir array pe8_array_12.sv] \
        [file join $parent HYBRID_SYSTEM rtl datapath pe8_result_correction.sv]]
} else {
    set array_dir [file join $parent PE_CHIP rtl]
    set sources [list [file join $array_dir pe_pkg.sv] \
        [file join $array_dir arithmetic pe_mac_lane.sv] \
        [file join $array_dir array pe_array_12.sv]]
}
foreach name {pe_compare_stream_controller pe_compare_result_drain pe_compare_engine} {
    lappend sources [file join $equivalent_root rtl equivalent ${name}.sv]
}
lappend sources [file join $equivalent_root rtl equivalent ${pe_variant}_equivalent_top.sv]
foreach path $sources {if {![file isfile $path]} {error "Missing RTL $path"}}
create_project ${pe_variant}_equivalent $destination -part xc7z020clg400-1
add_files -norecurse $sources
set_property file_type SystemVerilog [get_files $sources]
set_property top ${pe_variant}_equivalent_top [get_filesets sources_1]
set_property target_language Verilog [current_project]
add_files -fileset constrs_1 -norecurse [file join $equivalent_root constraints pe_equivalent_ooc.xdc]
set_property USED_IN {synthesis implementation out_of_context} [get_files [file join $equivalent_root constraints pe_equivalent_ooc.xdc]]
set_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP 0 [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.TCL.POST [file join $equivalent_root vivado report_equivalent_post_synth.tcl] [get_runs synth_1]
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $equivalent_root vivado prepare_pe_equivalent_impl.tcl] [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.TCL.POST [file join $equivalent_root vivado report_equivalent_post_route.tcl] [get_runs impl_1]
update_compile_order -fileset sources_1
puts "Created $destination; GUI Run Synthesis then Run Implementation. OOC: no bitstream."
