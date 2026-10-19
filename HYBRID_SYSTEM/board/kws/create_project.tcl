# Windows Vivado 2023.2: import only, no launch_runs, no out_of_context.
if {[llength [get_projects -quiet]]} {error "Close the current project first"}
set kws_board_dir [file normalize [file dirname [info script]]]
set kws_hybrid [file normalize [file join $kws_board_dir ../..]]
if {![info exists kws_vectors]} {set kws_vectors [file join $kws_hybrid build kws_board_vectors]}
if {![info exists kws_destination]} {set kws_destination [file join $kws_hybrid build kws_board]}
if {![info exists kws_pipe]} {set kws_pipe 0}
if {![info exists kws_post]} {set kws_post 1}
if {![info exists kws_check_result_order]} {set kws_check_result_order 1}
if {$kws_check_result_order ni {0 1}} {error "kws_check_result_order must be 0 or 1"}
if {$kws_pipe ni {0 1} || $kws_post ni {0 1}} {error "kws_pipe/kws_post must be 0 or 1"}
if {[file exists $kws_destination]} {error "Destination exists: open its XPR or choose a new kws_destination"}
foreach filename {sources.txt manifest.json kws_demo.mem} {
    if {![file isfile [file join $kws_vectors $filename]]} {error "Run make generate-kws-board-vectors in Docker first; missing $filename"}
}
set f [open [file join $kws_vectors sources.txt] r]
set relative_sources [split [string trim [read $f]] \n]
close $f
set source_files {}
foreach relative $relative_sources {
    set path [file normalize [file join $kws_hybrid [string trim $relative]]]
    if {![file isfile $path]} {error "Missing RTL $path"}
    lappend source_files $path
}
create_project kws_board $kws_destination -part xc7z020clg400-1
add_files -norecurse $source_files
set_property file_type SystemVerilog [get_files *.sv]
set_property top kws_board_top [get_filesets sources_1]
set rom [file normalize [file join $kws_vectors kws_demo.mem]]
add_files -norecurse $rom
set_property generic "DEMO_FILE=\"$rom\" RESULT_PIPELINED=$kws_pipe POSTPROCESS_PIPELINED=$kws_post CHECK_RESULT_ORDER=$kws_check_result_order" [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $kws_board_dir kws_board_pynq_z2.xdc]
set_property strategy {Vivado Synthesis Defaults} [get_runs synth_1]
set_property strategy {Vivado Implementation Defaults} [get_runs impl_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
# Constraint hook is kept as a project utility; no OOC options or manual HD.CLK_SRC.
set hook [file join $kws_board_dir pre_opt.tcl]
add_files -fileset utils_1 -norecurse $hook
set_property STEPS.OPT_DESIGN.TCL.PRE $hook [get_runs impl_1]
puts "Imported kws_board. Run Synthesis/Implementation in GUI; read S6_BOARD_INTEGRATION.md before programming."
