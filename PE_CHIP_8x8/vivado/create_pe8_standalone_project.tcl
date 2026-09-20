# Create/import only. User runs synthesis/implementation/bitstream in GUI.
set pe8_root [file normalize [file join [file dirname [info script]] ..]]
if {[llength [get_projects -quiet]] != 0} {
    error "Close the current project first; this script will not close or overwrite it."
}
set pe8_project_dir [file join $pe8_root build vivado_standalone]
if {[file exists $pe8_project_dir]} {
    error "Project directory exists: $pe8_project_dir. Open its XPR; no overwrite performed."
}
set pe8_paths {}
foreach relative_path {
    rtl/pe8_pkg.sv
    rtl/arithmetic/activation_u8_to_s8.sv
    rtl/arithmetic/pe8_multiplier_s8xs8.sv
    rtl/arithmetic/pe8_accumulator_s32.sv
    rtl/arithmetic/pe8_mac_lane.sv
    rtl/array/pe8_array_12.sv
    rtl/control/pe8_core_controller.sv
    rtl/core/pe8_core_12.sv
    rtl/core/pe8_standalone_top.sv
} {
    set path [file join $pe8_root $relative_path]
    if {![file isfile $path]} {error "Missing RTL: $path"}
    lappend pe8_paths $path
}
create_project pe8_standalone $pe8_project_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]
add_files -norecurse $pe8_paths
set_property file_type SystemVerilog [get_files $pe8_paths]
set_property top pe8_standalone_top [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $pe8_root constraints pe8_standalone_top_pynq_z2.xdc]
set_property -name STEPS.SYNTH_DESIGN.ARGS.MAX_DSP -value 0 -objects [get_runs synth_1]
update_compile_order -fileset sources_1
puts "Created normal board top (not OOC). No synthesis or implementation launched."
puts "Use Run Synthesis, Run Implementation, then Generate Bitstream after timing/DRC checks."
