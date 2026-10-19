"""Tcl 8.6 mock control-flow test; NOT Vivado syntax or hardware signoff."""
import ctypes
import ctypes.util
from pathlib import Path
import tempfile

lib = ctypes.CDLL(ctypes.util.find_library("tcl8.6"))
lib.Tcl_CreateInterp.restype = ctypes.c_void_p
lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
lib.Tcl_GetStringResult.restype = ctypes.c_char_p
lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
script = Path(__file__).with_name("run_order_experiment.tcl").resolve()
mock = r'''
set opened 0
set generics {}
proc get_projects {args} {if {$::opened} {return project}; return {}}
proc current_project {} {return project}
proc create_project {name dest args} {set ::opened 1; set ::dest $dest}
proc close_project {} {set ::opened 0}
proc get_designs {args} {return design}
proc get_files {args} {return files}
proc get_filesets {args} {return fileset}
proc get_runs {run} {return $run}
proc set_property {name value args} {
    if {$name eq "generic"} {set ::generic $value; lappend ::generics $value}
}
proc get_property {name object} {
    switch $name {
        DIRECTORY {return $::dest}
        GENERIC {return $::generic}
        PROGRESS {return 100%}
        STATUS {
            if {$::inject && $::order_variant eq "checked" && $object eq "synth_1"} {return "synth_design ERROR"}
            if {$object eq "synth_1"} {return "synth_design Complete!"}
            return $::route_status
        }
        SLACK {if {$object eq "max"} {return -0.5}; return 0.02}
        default {error "Unexpected property $name"}
    }
}
proc get_timing_paths {args} {return [lindex $args [expr {[lsearch $args -delay_type]+1}]]}
proc version {args} {return MOCK}
foreach cmd {add_files launch_runs wait_on_run open_run close_design report_utilization report_timing_summary report_timing report_cdc report_clocks report_exceptions report_route_status report_drc report_methodology write_checkpoint} {
    proc $cmd {args} {}
}
'''
for inject, route_status in ((0, "route_design Complete!"),
                             (0, "route_design Complete, Failed Timing!"),
                             (1, "route_design Complete, Failed Timing!")):
    interp = lib.Tcl_CreateInterp()
    try:
        with tempfile.TemporaryDirectory(prefix="kws-order-tcl-") as temp:
            root = Path(temp) / "experiment"
            code = mock + f'\nset inject {inject}\nset route_status {{{route_status}}}\nset order_root {{{root}}}\nsource {{{script}}}\n'
            rc = lib.Tcl_Eval(interp, code.encode())
            result = lib.Tcl_GetStringResult(interp).decode()
            assert (rc != 0) == bool(inject), result
            csv = (root / "summary.csv").read_text()
            assert "unchecked,0,COMPLETE,-0.5,0.02,FAIL" in csv, csv
            expected = "checked,1,ERROR,NA,NA,UNKNOWN" if inject else "checked,1,COMPLETE,-0.5,0.02,FAIL"
            assert expected in csv, csv
            # A repeat must refuse an existing root, not overwrite reports.
            rc = lib.Tcl_Eval(interp, f'source {{{script}}}'.encode())
            assert rc != 0 and b"Refusing existing" in lib.Tcl_GetStringResult(interp)
            assert (root / "summary.csv").read_text() == csv
            print(f"PASS Tcl mock inject_synth_failure={inject}; status={route_status}; no overwrite")
    finally:
        lib.Tcl_DeleteInterp(interp)
