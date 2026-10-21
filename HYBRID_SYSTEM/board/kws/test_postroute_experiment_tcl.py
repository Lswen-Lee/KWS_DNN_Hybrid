"""Tcl mock only: no Vivado API/implementation validation."""
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
script = Path(__file__).with_name("run_postroute_experiment.tcl").resolve()
mock = r'''
proc get_projects {args} {return {}}
proc get_designs {args} {return {}}
proc get_ports {args} {if {[lindex $args end] eq {led[*]}} {return {l0 l1 l2 l3}}; return port}
proc get_clocks {args} {return [lindex $args end]}
proc get_property {prop obj} {if {$obj eq "sys_clk_125m"} {return 8.0}; return 18.868}
proc version {args} {return MOCK}
proc open_checkpoint {p} {lappend ::calls open}
proc close_design {} {}
proc phys_opt_design {args} {lappend ::calls phys; if {$::inject} {error "injected phys failure"}}
proc route_design {args} {lappend ::calls route}
proc write_checkpoint {p} {lappend ::calls write; set f [open $p w]; puts $f mock; close $f}
foreach cmd {report_timing report_clocks report_cdc report_exceptions report_drc report_methodology} {proc $cmd {args} {}}
proc report_route_status {args} {
 set f [open [lindex $args end] w]
 puts $f {# of routable nets.......... : 100 :}
 puts $f {# of fully routed nets.......... : 100 :}
 puts $f {# of nets with routing errors.......... : 0 :}
 close $f
}
proc report_timing_summary {args} {
 set f [open [lindex $args end] w]
 puts $f { -0.010 -0.010 1 47161 0.070 0.000 0 46847 2.000 0.000 0 21704}
 close $f
}
proc report_utilization {args} {
 set f [open [lindex $args end] w]
 puts $f {| Slice LUTs | 27064 | 0 |}
 puts $f {| Slice Registers | 21611 | 0 |}
 close $f
}
'''
for inject in (0, 1):
    interp = lib.Tcl_CreateInterp()
    try:
        with tempfile.TemporaryDirectory(prefix="postroute-mock-") as tmp:
            root = Path(tmp)
            # The mock input is created by Tcl; production script only reads it.
            code = mock + f'''
set inject {inject}
set calls {{}}
set pr_input {{{root / 'input.dcp'}}}
set pr_output {{{root / 'result'}}}
set f [open $pr_input w]; puts $f original; close $f
set rc [catch {{source {{{script}}}}} msg]
if {{$rc != {inject}}} {{error "unexpected result $msg"}}
if {{!$inject && $calls ne {{open phys route write}}}} {{error "wrong sequence $calls"}}
if {{![catch {{source {{{script}}}}} refused] || ![string match {{Refusing existing*}} $refused]}} {{error "overwrite not refused"}}
'''
            rc = lib.Tcl_Eval(interp, code.encode())
            assert rc == 0, lib.Tcl_GetStringResult(interp).decode()
            assert (root / "input.dcp").read_text() == "original\n"
            rows = (root / "result/summary.csv").read_text().splitlines()
            assert len(rows) == (2 if inject else 3)
            if not inject:
                assert rows[-1] == "after,-0.010,-0.010,1,0.070,0.000,0,27064,21611,FAIL"
            else:
                assert (root / "result/error.txt").is_file()
            print(f"PASS postroute mock inject={inject}: CSV, sequencing, source preserved, no overwrite")
    finally:
        lib.Tcl_DeleteInterp(interp)
