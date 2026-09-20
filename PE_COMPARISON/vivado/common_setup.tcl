# Paths are relative to this script, allowing Windows/Linux relocation.
set pe_compare_root [file normalize [file join [file dirname [info script]] ..]]
proc pe_compare_create {variant} {
    global pe_compare_root
    if {[llength [get_projects -quiet]] != 0} {
        error "Close the current project first. This script will not close or overwrite it."
    }
    set parent [file dirname $pe_compare_root]
    if {$variant eq "pe9"} {
        set dir [file join $parent PE_CHIP]
        set sources [list rtl/pe_pkg.sv rtl/arithmetic/pe_multiplier_s9xs8.sv rtl/arithmetic/pe_accumulator_s32.sv rtl/arithmetic/pe_mac_lane.sv rtl/array/pe_array_12.sv]
        set top pe_array_12
    } elseif {$variant eq "pe8"} {
        set dir [file join $parent PE_CHIP_8x8]
        set sources [list rtl/pe8_pkg.sv rtl/arithmetic/pe8_multiplier_s8xs8.sv rtl/arithmetic/pe8_accumulator_s32.sv rtl/arithmetic/pe8_mac_lane.sv rtl/array/pe8_array_12.sv]
        set top pe8_array_12
    } else { error "Unknown variant $variant" }
    set paths {}
    foreach src $sources {
        set path [file join $dir $src]
        if {![file isfile $path]} { error "Missing RTL: $path" }
        lappend paths $path
    }
    set xdc [file join $pe_compare_root constraints pe_array_ooc.xdc]
    if {![file isfile $xdc]} { error "Missing XDC: $xdc" }
    set output [file join $pe_compare_root build $variant]
    if {[file exists $output]} { error "Project directory exists: $output. Open its XPR or choose a new directory; no overwrite performed." }
    create_project pe_compare_$variant $output -part xc7z020clg400-1
    set_property target_language Verilog [current_project]
    add_files -norecurse $paths
    set_property file_type SystemVerilog [get_files $paths]
    set_property top $top [get_filesets sources_1]
    add_files -fileset constrs_1 -norecurse $xdc
    set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
    # 2026-09-14: compare both arrays using LUT/FF, not DSP resources.
    set_property -name STEPS.SYNTH_DESIGN.ARGS.MAX_DSP -value 0 -objects [get_runs synth_1]
    set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
    update_compile_order -fileset sources_1
    puts "Created $variant: top=$top, part=xc7z020clg400-1, OOC synthesis."
    puts "No synthesis or implementation launched. See docs/PE_COMPARISON_GUIDE.md."
}
