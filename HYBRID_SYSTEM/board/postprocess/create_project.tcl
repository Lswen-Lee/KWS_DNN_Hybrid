# Source in Windows Vivado 2023.2. Import only; run synth/implementation in GUI.
if {![info exists pp_pipeline]} {set pp_pipeline 0}
if {![info exists pp_frequency]} {set pp_frequency 150}
if {$pp_pipeline ni {0 1}} {error "pp_pipeline must be 0 or 1"}
if {$pp_frequency ni {50 75 100 125 150 200 250}} {error "Supported MHz: 50 75 100 125 150 200 250"}
if {[llength [get_projects -quiet]]} {error "Close the current project first"}
set pp_dir [file normalize [file dirname [info script]]]
set pp_hybrid [file normalize [file join $pp_dir ../..]]
set pp_name pp${pp_pipeline}_f${pp_frequency}
if {![info exists pp_destination]} {set pp_destination [file join $pp_hybrid build postprocess $pp_name]}
if {[file exists $pp_destination]} {error "Destination exists; open its XPR or select a new pp_destination: $pp_destination"}
set pp_sources [glob -directory $pp_dir *.sv]
foreach f {pe_pot_result_stream kws_pot_shift_rom requantizer_int32_to_uint8_pot requantizer_int32_to_uint8_pot_comb} {
    lappend pp_sources [file join $pp_hybrid rtl datapath ${f}.sv]
}
foreach f $pp_sources {if {![file exists $f]} {error "Missing source $f"}}
create_project $pp_name $pp_destination -part xc7z020clg400-1
add_files -norecurse $pp_sources
set_property file_type SystemVerilog [get_files *.sv]
set_property top postprocess_board_top [get_filesets sources_1]
set_property generic "POSTPROCESS_PIPELINED=$pp_pipeline OUTPUT_DIVIDE=[expr {750.0/$pp_frequency}]" [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $pp_dir postprocess_pynq_z2.xdc]
set_property strategy {Vivado Synthesis Defaults} [get_runs synth_1]
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
puts "Imported normal board top: $pp_name. Run Synthesis, Implementation, then source report.tcl. No OOC options."
