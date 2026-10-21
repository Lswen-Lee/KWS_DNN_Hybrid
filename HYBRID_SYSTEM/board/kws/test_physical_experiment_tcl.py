"""Tcl control-flow/report-parser mock only; does not validate Vivado APIs/STA."""
import ctypes
import ctypes.util
import tempfile
from pathlib import Path

lib = ctypes.CDLL(ctypes.util.find_library("tcl8.6"))
lib.Tcl_CreateInterp.restype = ctypes.c_void_p
lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
lib.Tcl_GetStringResult.restype = ctypes.c_char_p
lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
script = Path(__file__).with_name("run_physical_experiment.tcl").resolve()
mock = r'''
proc get_projects {args} {return {}}
proc current_project {} {return project}
proc create_project {name dest args} {set ::dest $dest; file mkdir $dest}
proc get_files {args} {return files}
proc get_filesets {args} {return fileset}
proc get_runs {run} {return $run}
proc set_property {name value object} {set ::props($object,$name) $value}
proc get_property {name object} {
    switch $name {
        DIRECTORY {return $::dest}
        FLOW {return {Vivado Implementation 2023}}
        PROGRESS {return 100%}
        STATUS {
            if {$::inject && $object eq "impl_fanout"} {return {route_design ERROR}}
            if {$object eq "synth_1"} {return {synth_design Complete!}}
            return {route_design Complete, Failed Timing!}
        }
        default {error "Unexpected property $name"}
    }
}
proc version {args} {return MOCK}
proc launch_runs {run args} {lappend ::launched $run}
foreach cmd {add_files create_run wait_on_run open_run close_design report_clocks report_timing report_route_status report_cdc report_exceptions report_clock_interaction report_drc report_methodology write_checkpoint} {
    proc $cmd {args} {}
}
proc report_timing_summary {args} {
    set f [open [lindex $args end] w]
    puts $f { -0.169 -1.281 14 47161 0.070 0.000 0 46847 2.000 0.000 0 21704}
    close $f
}
proc report_utilization {args} {
    set f [open [lindex $args end] w]
    puts $f {| Slice LUTs | 27026 | 0 |}
    puts $f {| Slice Registers | 21606 | 0 |}
    close $f
}
'''
for inject in (0, 1):
    interp = lib.Tcl_CreateInterp()
    try:
        with tempfile.TemporaryDirectory(prefix="kws-physical-mock-") as tmp:
            root = Path(tmp) / "project"
            code = mock + f'''
set inject {inject}
set kws_destination {{{root}}}
set px_variants {{baseline fanout explore aggressive}}
set rc [catch {{source {{{script}}}}} msg]
if {{$rc != {inject}}} {{error "Unexpected result: $msg"}}
if {{[llength [lsearch -all -exact $launched synth_1]] != 1}} {{error "synthesis repeated"}}
if {{[lindex $launched end] ne "impl_aggressive"}} {{error "did not continue"}}
if {{$props(impl_aggressive,STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE) ne "AggressiveExplore"}} {{error "wrong directive"}}
if {{$props(impl_aggressive,STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE) ne "NoTimingRelaxation"}} {{error "wrong routing"}}
if {{$kws_check_result_order != 1}} {{error "checks disabled"}}
if {{![catch {{source {{{script}}}}} refused] || ![string match {{Destination exists:*}} $refused]}} {{error "overwrite not refused"}}
'''
            rc = lib.Tcl_Eval(interp, code.encode())
            assert rc == 0, lib.Tcl_GetStringResult(interp).decode()
            rows = (root / "reports/summary.csv").read_text().splitlines()
            assert len(rows) == 5, rows
            assert rows[-1] == "aggressive,COMPLETE,-0.169,-1.281,14,0.070,0.000,0,27026,21606,FAIL", rows
            assert ("fanout,ERROR," in rows[2]) == bool(inject), rows
            print(f"PASS physical Tcl mock: inject={inject}; single synthesis, four variants, CSV, no overwrite")
    finally:
        lib.Tcl_DeleteInterp(interp)
