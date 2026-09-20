# Import only. Does NOT launch/reset runs or overwrite existing projects.
# set pe_variant pe9|pe8_compact|pe8_pipeline
# set pe_frequency_mhz 125
if {![info exists pe_variant] || $pe_variant ni {pe9 pe8_compact pe8_pipeline}} {
    error "Set pe_variant to pe9, pe8_compact, or pe8_pipeline."
}
if {![info exists pe_frequency_mhz]} {set pe_frequency_mhz 125}
if {![string is integer -strict $pe_frequency_mhz] || $pe_frequency_mhz < 1 || $pe_frequency_mhz > 500} {
    error "pe_frequency_mhz must be an integer from 1 to 500 (not a timing guarantee)."
}
if {[llength [get_projects -quiet]]} {error "Close the current project first."}
set mp_root [file normalize [file join [file dirname [info script]] ..]]
set mp_parent [file dirname $mp_root]
set mp_variant $pe_variant
set mp_frequency $pe_frequency_mhz
set mp_period [format %.9f [expr {1000.0 / $mp_frequency}]]
set mp_top ${mp_variant}_memory_top
# Compact/pipeline wrapper names already contain the required suffix.
set mp_top [dict get [dict create pe9 pe9_memory_top pe8_compact pe8_compact_memory_top pe8_pipeline pe8_pipeline_memory_top] $mp_variant]
set mp_destination [file join $mp_root build memory_backed $mp_variant [format f%03d $mp_frequency]]
# Optional separate experiment directory; never overwrite the baseline snapshot.
if {[info exists pe_build_root]} {
    set mp_destination [file normalize [file join $pe_build_root $mp_variant [format f%03d $mp_frequency]]]
}
if {[file exists $mp_destination]} {
    error "Directory exists; not overwritten: $mp_destination. Open its XPR, or move the old project before rebuilding."
}
set mp_sources {}
foreach spec {
    PE_CHIP/rtl/pe_pkg.sv
    PE_CHIP/rtl/arithmetic/activation_center_127.sv
    PE_CHIP/rtl/arithmetic/pe_mac_lane.sv
    PE_CHIP/rtl/array/pe_array_12.sv
    PE_CHIP_8x8/rtl/pe8_pkg.sv
    PE_CHIP_8x8/rtl/arithmetic/activation_u8_to_s8.sv
    PE_CHIP_8x8/rtl/arithmetic/pe8_mac_lane.sv
    PE_CHIP_8x8/rtl/array/pe8_array_12.sv
    HYBRID_SYSTEM/rtl/datapath/pe_weight_buffer_12.sv
    HYBRID_SYSTEM/rtl/datapath/pe_layer_weight_loader.sv
    HYBRID_SYSTEM/rtl/datapath/pe_weight_sum_builder.sv
    HYBRID_SYSTEM/rtl/datapath/pe_channel_sum_memory.sv
    HYBRID_SYSTEM/rtl/datapath/pe_weight_read_align.sv
    HYBRID_SYSTEM/rtl/datapath/pe8_result_correction.sv
    HYBRID_SYSTEM/rtl/control/pe_group_controller.sv
    HYBRID_SYSTEM/rtl/control/pe_result_controller.sv
    HYBRID_SYSTEM/rtl/control/pe8_result_controller_pipeline.sv
    HYBRID_SYSTEM/rtl/integration/pe_memory_engine.sv
} {lappend mp_sources [file join $mp_parent $spec]}
lappend mp_sources [file join $mp_root rtl memory_backed ${mp_top}.sv]
foreach p $mp_sources {if {![file isfile $p]} {error "Missing RTL: $p"}}
set mp_template [file join $mp_root constraints pe_memory_ooc_template.xdc]
if {![file isfile $mp_template]} {error "Missing XDC template: $mp_template"}
foreach name {ensure_pe_memory_constraints.tcl report_pe_memory.tcl} {
    if {![file isfile [file join $mp_root vivado $name]]} {error "Missing helper: $name"}
}
file mkdir [file join $mp_destination inputs]
file mkdir [file join $mp_destination scripts]
# Freeze exact source contents. No TB, board self-test or sim model is imported.
set mp_frozen {}
set mp_manifest [open [file join $mp_destination source_manifest.tsv] w]
puts $mp_manifest "original_path\tsnapshot_path\tbytes"
foreach p $mp_sources {
    set q [file join $mp_destination inputs [file tail $p]]
    if {[file exists $q]} {error "Duplicate source basename: $q"}
    file copy $p $q
    lappend mp_frozen $q
    puts $mp_manifest "$p\t$q\t[file size $q]"
}
close $mp_manifest
foreach name {ensure_pe_memory_constraints.tcl report_pe_memory.tcl} {
    file copy [file join $mp_root vivado $name] [file join $mp_destination scripts $name]
}
set f [open $mp_template r]; set template_text [read $f]; close $f
set mp_xdc [file join $mp_destination inputs pe_memory_ooc.xdc]
set f [open $mp_xdc w]
puts $f [string map [list @PERIOD_NS@ $mp_period] $template_text]
close $f
set mp_config [file join $mp_destination scripts config.tcl]
set f [open $mp_config w]
foreach key {mp_variant mp_frequency mp_period mp_top mp_destination mp_xdc} {
    puts $f [list set $key [set $key]]
}
close $f
foreach stage {post_synth pre_opt post_route} {
    set f [open [file join $mp_destination scripts ${stage}.tcl] w]
    puts $f [list source $mp_config]
    puts $f [list set mp_stage $stage]
    if {$stage eq "pre_opt"} {set helper ensure_pe_memory_constraints.tcl} else {set helper report_pe_memory.tcl}
    puts $f [list source [file join $mp_destination scripts $helper]]
    close $f
}
create_project ${mp_variant}_f${mp_frequency} $mp_destination -part xc7z020clg400-1
add_files -norecurse $mp_frozen
set_property file_type SystemVerilog [get_files $mp_frozen]
set_property target_language Verilog [current_project]
set_property top $mp_top [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse $mp_xdc
set_property USED_IN {synthesis implementation out_of_context} [get_files $mp_xdc]
set_property strategy {Vivado Synthesis Defaults} [get_runs synth_1]
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
set_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP 0 [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
add_files -fileset utils_1 -norecurse [glob [file join $mp_destination scripts *.tcl]]
set_property STEPS.SYNTH_DESIGN.TCL.POST [file join $mp_destination scripts post_synth.tcl] [get_runs synth_1]
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $mp_destination scripts pre_opt.tcl] [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.TCL.POST [file join $mp_destination scripts post_route.tcl] [get_runs impl_1]
update_compile_order -fileset sources_1
puts "Created $mp_destination; GUI: Run Synthesis, then Run Implementation. OOC: no bitstream."
