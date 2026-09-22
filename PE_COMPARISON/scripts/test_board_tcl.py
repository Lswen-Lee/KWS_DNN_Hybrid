"""Execute import/hooks/XDC with mocked Vivado API; NOT a Vivado validation."""
import ctypes
import ctypes.util
from pathlib import Path
import tempfile
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
lib = ctypes.CDLL(ctypes.util.find_library("tcl8.6"))
lib.Tcl_CreateInterp.restype = ctypes.c_void_p
lib.Tcl_Init.argtypes = [ctypes.c_void_p]
lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
lib.Tcl_GetStringResult.restype = ctypes.c_char_p
lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
interp = lib.Tcl_CreateInterp()

def run(code, error=False):
    status = lib.Tcl_Eval(interp, code.encode())
    result = lib.Tcl_GetStringResult(interp).decode()
    assert bool(status) == error, result
    return result

try:
    if lib.Tcl_Init(interp):
        run('proc clock {sub args} {if {$sub eq "seconds"} {return 0}; return 19700101_000000}')
    run('''
        set open 0
        proc get_projects {args} {if {$::open} {return project}; return {}}
        proc create_project {args} {set ::open 1}
        proc current_project {} {return project}
        proc current_design {} {return design}
        proc get_designs {args} {return design}
        proc get_runs {args} {return [lindex $args end]}
        proc get_filesets {args} {return [lindex $args end]}
        proc get_files {args} {return [lindex $args end]}
        proc get_ports {args} {return [lindex $args end]}
        proc get_pins {args} {return board/clock_reset/button_meta_reg/D}
        set clock_exists 1
        set clock_period 8.0
        set pin_exists 1
        proc get_pins {args} {if {$::pin_exists} {return board/clock_reset/button_meta_reg/D}; return {}}
        proc get_clocks {args} {if {$::clock_exists} {return board_clk}; return {}}
        proc get_property {args} {return $::clock_period}
        proc create_clock {args} {set ::clock_exists 1; set ::clock_period 8.0}
        proc set_property {args} {
            if {[string match *out_of_context* $args]} {error "OOC forbidden"}
        }
        proc add_files {args} {
            if {[string match *sim_verilator* $args] || [string match *ooc* $args]} {error "Wrong input"}
        }
        foreach name {update_compile_order update_timing set_clock_uncertainty set_false_path
            report_utilization report_timing_summary report_timing check_timing report_clocks
            report_exceptions report_route_status report_drc report_methodology} {
            proc $name {args} {}
        }
    ''')
    with tempfile.TemporaryDirectory(prefix="pe_board_tcl_") as tmp:
        for variant in ("pe9", "pe8_compact", "pe8_pipeline", "pe9_pot", "pe8_compact_pot", "pe8_pipeline_pot", "pe8_compact_pot_comb", "pe8_pipeline_pot_comb"):
            run(f'set open 0; set pe_variant {variant}; set pe_board_build_root {{{tmp}}}; source {{{root / "vivado/create_pe_board_project.tcl"}}}')
            dest = Path(tmp) / variant
            assert len(list((dest / "inputs").glob("*.sv"))) == (29 if "_pot" in variant else 23)
            assert "operand_w" in (dest / "inputs/pe_memory_engine.sv").read_text()
            if "--lint-snapshots" in sys.argv:
                sources = [line.split("\t")[1] for line in (dest / "source_manifest.tsv").read_text().splitlines()[1:]]
                subprocess.run(["verilator", "--lint-only", "-Wall", "-Wno-UNUSEDSIGNAL", "-Wno-DECLFILENAME",
                    "--top-module", f"{variant}_board_top", *sources,
                    str(root / "sim_verilator/pe_board_clock_primitives.sv")], check=True)
            run(f'source {{{dest / "inputs/pe_board_pynq_z2.xdc"}}}')
            xdc = (dest / "inputs/pe_board_pynq_z2.xdc").read_text()
            for line in xdc.splitlines():
                # Conservative subset for this XDC, not a complete Vivado parser.
                if line.strip() and not line.lstrip().startswith("#"):
                    assert line.split()[0] in {"set", "set_property", "create_clock", "set_clock_uncertainty", "set_false_path"}, line
            for stage in ("post_synth", "pre_opt", "post_route"):
                run('set clock_exists 0')  # exercise full-XDC fallback
                run(f'source {{{dest / "scripts" / (stage + ".tcl")}}}')
            run('set clock_period 10.0')
            run(f'source {{{dest / "scripts/pre_opt.tcl"}}}', error=True)
            run('set clock_period 8.0; set pin_exists 0')
            run(f'source {{{dest / "scripts/pre_opt.tcl"}}}', error=True)
            run('set pin_exists 1')
            run('set open 0')
            run(f'source {{{root / "vivado/create_pe_board_project.tcl"}}}', error=True)
    print("PASS board Tcl: eight variants, snapshots, normal flow, XDC/hooks, no overwrite")
finally:
    lib.Tcl_DeleteInterp(interp)
