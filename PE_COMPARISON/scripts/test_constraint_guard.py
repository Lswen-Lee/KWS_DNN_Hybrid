"""Tcl control-flow tests only, not a substitute for Vivado timing checks."""
import ctypes
import ctypes.util
from pathlib import Path
import unittest


class ConstraintGuardTest(unittest.TestCase):
    def test_guard_cases(self):
        name = ctypes.util.find_library('tcl8.6')
        if not name:
            self.skipTest('Tcl 8.6 library unavailable')
        lib = ctypes.CDLL(name)
        lib.Tcl_CreateInterp.restype = ctypes.c_void_p
        lib.Tcl_Init.argtypes = [ctypes.c_void_p]
        lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
        lib.Tcl_GetStringResult.restype = ctypes.c_char_p
        lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
        script = Path(__file__).resolve().parents[1] / 'vivado/ensure_pe_equivalent_constraints.tcl'
        for case in ['missing', 'existing', 'wrong_period', 'no_design', 'other_clock']:
            with self.subTest(case=case):
                interp = lib.Tcl_CreateInterp()
                try:
                    self.assertEqual(lib.Tcl_Init(interp), 0)
                    def evaluate(code):
                        rc = lib.Tcl_Eval(interp, code.encode())
                        return rc, lib.Tcl_GetStringResult(interp).decode()
                    setup = '''
set clocks {}; set period 8.0; set design 1; set creates 0; set delays 0
proc get_designs {args} {if {$::design} {return netlist}; return {}}
proc get_ports {args} {return clk}
proc update_timing {} {}
proc get_clocks {args} {
    if {[lsearch $args -of_objects]>=0} {return $::clocks}
    if {[lsearch $::clocks pe_clk]>=0} {return pe_clk}; return {}
}
proc get_property {args} {return $::period}
proc create_clock {args} {incr ::creates; set ::clocks pe_clk}
proc set_clock_uncertainty {args} {incr ::delays}
proc set_input_delay {args} {incr ::delays}
proc set_output_delay {args} {incr ::delays}
'''
                    self.assertEqual(evaluate(setup)[0], 0)
                    if case in ['existing', 'wrong_period']:
                        evaluate('set clocks pe_clk')
                    if case == 'wrong_period':
                        evaluate('set period 10.0')
                    if case == 'no_design':
                        evaluate('set design 0')
                    if case == 'other_clock':
                        evaluate('set clocks another_clk')
                    rc, message = evaluate(f'source {{{script}}}')
                    if case in ['missing', 'existing']:
                        self.assertEqual(rc, 0, message)
                        self.assertEqual(evaluate('set creates')[1], '1' if case == 'missing' else '0')
                        self.assertEqual(evaluate('set delays')[1], '5' if case == 'missing' else '0')
                        self.assertEqual(evaluate(f'source {{{script}}}')[0], 0)
                        self.assertEqual(evaluate('set creates')[1], '1' if case == 'missing' else '0')
                    else:
                        self.assertNotEqual(rc, 0)
                        self.assertEqual(evaluate('set creates')[1], '0')
                finally:
                    lib.Tcl_DeleteInterp(interp)
