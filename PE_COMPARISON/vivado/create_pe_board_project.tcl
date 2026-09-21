# Import-only, normal top-level flow: no OOC options or abstract I/O delays.
# Legacy: pe9|pe8_compact|pe8_pipeline; PoT zp128: add _pot to the variant.
# set pe_variant pe8_compact_pot ; source this_file.tcl
if {![info exists pe_variant] || $pe_variant ni {pe9 pe8_compact pe8_pipeline pe9_pot pe8_compact_pot pe8_pipeline_pot}} {
    error "Set pe_variant to pe9/pe8_compact/pe8_pipeline (legacy) or add _pot (zp128 with quantization)"
}
if {[llength [get_projects -quiet]]} {error "Close the current project first"}
set pb_root [file normalize [file join [file dirname [info script]] ..]]
set pb_parent [file dirname $pb_root]
if {![info exists pe_board_build_root]} {set pe_board_build_root [file join $pb_root build board]}
set pb_dest [file normalize [file join $pe_board_build_root $pe_variant]]
if {[file exists $pb_dest]} {error "Not overwritten: $pb_dest. Open its XPR or choose a new pe_board_build_root."}
set pb_sources {}
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
} {lappend pb_sources [file join $pb_parent $spec]}
foreach name {pe_board_clock_reset pe_board_self_test pe_board_golden pe_board_top} {
    lappend pb_sources [file join $pb_root rtl board ${name}.sv]
}
if {[string match *_pot $pe_variant]} {
    foreach spec {
        HYBRID_SYSTEM/rtl/integration/pe_pot_engine.sv
        HYBRID_SYSTEM/rtl/datapath/requantizer_int32_to_uint8_pot.sv
        HYBRID_SYSTEM/rtl/datapath/kws_pot_shift_rom.sv
        HYBRID_SYSTEM/rtl/datapath/pe_pot_result_stream.sv
        PE_COMPARISON/rtl/board/pe_board_golden_pot.sv
    } {lappend pb_sources [file join $pb_parent $spec]}
}
set pb_top ${pe_variant}_board_top
lappend pb_sources [file join $pb_root rtl board ${pb_top}.sv]
foreach p $pb_sources {if {![file isfile $p]} {error "Missing source $p"}}
file mkdir [file join $pb_dest inputs]
file mkdir [file join $pb_dest scripts]
set pb_frozen {}
set f [open [file join $pb_dest source_manifest.tsv] w]
puts $f "original_path\tsnapshot_path"
foreach p $pb_sources {
    set q [file join $pb_dest inputs [file tail $p]]
    if {[file exists $q]} {error "Duplicate basename $q"}
    file copy $p $q
    lappend pb_frozen $q
    puts $f "$p\t$q"
}
close $f
set pb_xdc [file join $pb_dest inputs pe_board_pynq_z2.xdc]
file copy [file join $pb_root constraints pe_board_pynq_z2.xdc] $pb_xdc
file copy [file join $pb_root vivado report_pe_board.tcl] [file join $pb_dest scripts report_pe_board.tcl]
file copy [file join $pb_root vivado ensure_pe_board_constraints.tcl] [file join $pb_dest scripts ensure_pe_board_constraints.tcl]
foreach stage {post_synth pre_opt post_route} {
    set f [open [file join $pb_dest scripts ${stage}.tcl] w]
    puts $f [list set pb_stage $stage]
    if {$stage eq "pre_opt"} {
        puts $f {source [file join [file dirname [info script]] ensure_pe_board_constraints.tcl]}
    } else {
        puts $f {source [file join [file dirname [info script]] report_pe_board.tcl]}
    }
    close $f
}
create_project ${pe_variant}_board $pb_dest -part xc7z020clg400-1
add_files -norecurse $pb_frozen
set_property file_type SystemVerilog [get_files $pb_frozen]
set_property target_language Verilog [current_project]
set_property top $pb_top [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse $pb_xdc
set_property USED_IN {synthesis implementation} [get_files $pb_xdc]
add_files -fileset utils_1 -norecurse [glob [file join $pb_dest scripts *.tcl]]
set_property strategy {Vivado Synthesis Defaults} [get_runs synth_1]
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
set_property STEPS.SYNTH_DESIGN.ARGS.MAX_DSP 0 [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.TCL.POST [file join $pb_dest scripts post_synth.tcl] [get_runs synth_1]
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $pb_dest scripts pre_opt.tcl] [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.TCL.POST [file join $pb_dest scripts post_route.tcl] [get_runs impl_1]
update_compile_order -fileset sources_1
puts "Created normal board project: $pb_dest. GUI: Synthesis -> Implementation -> inspect timing -> Bitstream."
