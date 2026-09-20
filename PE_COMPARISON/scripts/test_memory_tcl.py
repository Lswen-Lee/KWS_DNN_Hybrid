"""Tcl runtime/mock checks, NOT execution inside Vivado. Standard library only."""
import ctypes
import ctypes.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TclMockTest(unittest.TestCase):
    def test_import_and_hooks(self):
        libname = ctypes.util.find_library("tcl8.6")
        if not libname:
            self.skipTest("libtcl8.6 unavailable")
        lib = ctypes.CDLL(libname)
        lib.Tcl_CreateInterp.restype = ctypes.c_void_p
        lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
        lib.Tcl_GetStringResult.restype = ctypes.c_char_p
        lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
        lib.Tcl_Init.argtypes = [ctypes.c_void_p]
        interp = lib.Tcl_CreateInterp()
        if lib.Tcl_Init(interp) != 0:
            # Core commands suffice for this mock; clock's script library may
            # not be installed alongside the shared library on headless hosts.
            lib.Tcl_Eval(interp, b'proc clock {sub args} {if {$sub eq "seconds"} {return 0}; return 19700101_000000}')

        def evaluate(code, fail=False):
            status = lib.Tcl_Eval(interp, code.encode())
            result = lib.Tcl_GetStringResult(interp).decode()
            if fail:
                self.assertNotEqual(status, 0, result)
            else:
                self.assertEqual(status, 0, result)
            return result

        try:
            with tempfile.TemporaryDirectory(prefix="pe_memory_tcl_") as tmp:
                parent = Path(tmp)
                root = parent / "PE_COMPARISON"
                # Minimal real inputs; no copying build trees or Vivado outputs.
                for folder in ("PE_CHIP/rtl", "PE_CHIP_8x8/rtl", "HYBRID_SYSTEM/rtl",
                               "PE_COMPARISON/rtl/memory_backed", "PE_COMPARISON/vivado",
                               "PE_COMPARISON/constraints"):
                    shutil.copytree(ROOT.parent / folder, parent / folder)
                evaluate('''
                    set project_open 0
                    set clock_exists 0
                    set actual_period 0
                    set imported_count 0
                    proc get_projects {args} {if {$::project_open} {return project}; return {}}
                    proc create_project {args} {set ::project_open 1}
                    proc get_runs {args} {return [lindex $args end]}
                    proc get_filesets {name} {return $name}
                    proc current_project {} {return project}
                    proc current_design {} {return design}
                    proc get_designs {args} {return design}
                    proc get_files {args} {return [lindex $args end]}
                    proc add_files {args} {incr ::imported_count}
                    proc update_compile_order {args} {}
                    proc set_property {args} {
                        if {[lindex $args 0] eq "-name"} {
                            if {[llength $args]!=6} {error "bad named set_property"}
                        } elseif {[llength $args]!=3} {error "bad set_property arity: $args"}
                    }
                    proc get_property {name obj} {
                        switch $name {
                            TOP {return $::mp_top}
                            PERIOD {return $::actual_period}
                            PART {return xc7z020clg400-1}
                            STRATEGY {return default}
                            default {error "Unexpected get_property $name"}
                        }
                    }
                    proc get_ports {args} {return clk}
                    proc get_clocks {args} {if {$::clock_exists} {return pe_clk}; return {}}
                    proc create_clock {args} {
                        set ::clock_exists 1
                        set ::actual_period [lindex $args [expr {[lsearch $args -period]+1}]]
                    }
                    proc set_clock_uncertainty {args} {}
                    proc set_input_delay {args} {}
                    proc set_output_delay {args} {}
                    proc update_timing {} {}
                    proc version {args} {return mocked-not-Vivado}
                    foreach name {report_utilization report_timing_summary report_timing report_clocks report_control_sets report_route_status report_drc report_methodology check_timing} {
                        proc $name {args} {}
                    }
                ''')
                script = root / "vivado/create_pe_memory_project.tcl"
                for variant, frequency in (("pe9", 50), ("pe8_compact", 100), ("pe8_pipeline", 125)):
                    evaluate(f'set project_open 0; set clock_exists 0; set pe_variant {variant}; set pe_frequency_mhz {frequency}; source {{{script}}}')
                    dest = root / "build/memory_backed" / variant / f"f{frequency:03d}"
                    self.assertEqual(len(list((dest / "inputs").glob("*.sv"))), 19)
                    self.assertNotIn("@PERIOD_NS@", (dest / "inputs/pe_memory_ooc.xdc").read_text())
                    for stage in ("post_synth", "pre_opt", "post_route"):
                        evaluate(f'source {{{dest / "scripts" / (stage + ".tcl")}}}')
                    manifest = next((dest / "reports/post_route").glob("*/comparison_config.txt"))
                    self.assertIn(f"variant={variant}", manifest.read_text())
                    evaluate('set actual_period 123')
                    self.assertIn("mismatch", evaluate(f'source {{{dest / "scripts/pre_opt.tcl"}}}', fail=True))
                    evaluate('set project_open 0')
                    self.assertIn("not overwritten", evaluate(f'source {{{script}}}', fail=True))
                # Separate operand-pipeline experiment keeps the baseline intact.
                evaluate(f'set project_open 0; set pe_variant pe9; set pe_frequency_mhz 125; set pe_build_root {{{root / "build/memory_operand"}}}; source {{{script}}}')
                self.assertTrue((root / "build/memory_operand/pe9/f125/inputs/pe_memory_engine.sv").is_file())
                evaluate('proc get_runs {args} {return {}}; set clock_exists 0')
                evaluate(f'source {{{root / "build/memory_operand/pe9/f125/scripts/post_synth.tcl"}}}')
                evaluate('set project_open 0; set pe_variant invalid')
                evaluate(f'source {{{script}}}', fail=True)
                evaluate('set pe_variant pe9; set pe_frequency_mhz 0')
                evaluate(f'source {{{script}}}', fail=True)
        finally:
            lib.Tcl_DeleteInterp(interp)


if __name__ == "__main__":
    unittest.main()
