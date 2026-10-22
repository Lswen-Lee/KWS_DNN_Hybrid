"""Exercise pre_opt Tcl guards using mocks, not a Vivado netlist/STA test."""
import ctypes
import ctypes.util
from pathlib import Path

lib = ctypes.CDLL(ctypes.util.find_library("tcl8.6"))
lib.Tcl_CreateInterp.restype = ctypes.c_void_p
lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
lib.Tcl_GetStringResult.restype = ctypes.c_char_p
lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
script = Path(__file__).with_name("pre_opt.tcl").resolve()
mock = r'''
proc get_clocks {args} {return clock}
proc get_cells {args} {
    set pattern [lindex $args end]
    if {[string first release_ready $pattern] >= 0} {
        if {$::case eq "missing"} {return {}}
        if {$::case eq "duplicate"} {return {src src2}}
        return src
    }
    if {[string first cim_reset_sync $pattern] >= 0} {return dst}
    return generic
}
proc get_pins {args} {
    if {[lsearch -exact $args src] >= 0} {return clocks/release_ready_reg/Q}
    if {[lsearch -exact $args dst] >= 0} {return {clocks/cim_reset_sync_reg[0]/D}}
    return pin
}
proc get_property {prop obj} {
    if {$prop eq "ASYNC_REG"} {return [expr {$::case eq "no_async" ? "FALSE" : "TRUE"}]}
    return $obj
}
proc all_fanin {args} {
    if {$::case eq "disconnected"} {return other/Q}
    return clocks/release_ready_reg/Q
}
proc set_false_path {args} {lappend ::exceptions $args}
proc set_max_delay {args} {}
'''
for case in ("normal", "missing", "duplicate", "no_async", "disconnected"):
    interp = lib.Tcl_CreateInterp()
    try:
        code = mock + f'\nset case {case}\nset exceptions {{}}\nsource {{{script}}}\n'
        rc = lib.Tcl_Eval(interp, code.encode())
        message = lib.Tcl_GetStringResult(interp).decode()
        if case == "normal":
            assert rc == 0, message
            check = r'''
if {[lindex $exceptions end] ne {-from clocks/release_ready_reg/Q -to {clocks/cim_reset_sync_reg[0]/D}}} {
    error "exception scope mismatch"
}
'''
            assert lib.Tcl_Eval(interp, check.encode()) == 0, lib.Tcl_GetStringResult(interp).decode()
        else:
            assert rc != 0 and "KWS" in message, (case, message)
        print(f"PASS reset constraint mock: {case}")
    finally:
        lib.Tcl_DeleteInterp(interp)
