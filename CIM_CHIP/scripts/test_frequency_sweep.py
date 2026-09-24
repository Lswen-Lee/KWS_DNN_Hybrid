"""Tcl/Vivado mock plus report parser/plot regression; NOT physical synthesis."""
import ctypes
import ctypes.util
import hashlib
from pathlib import Path
import tempfile

from summarize_dcim_sweep import collect, summarize, utilization

ROOT = Path(__file__).resolve().parents[1]
lib = ctypes.CDLL(ctypes.util.find_library("tcl8.6"))
lib.Tcl_CreateInterp.restype = ctypes.c_void_p
lib.Tcl_Init.argtypes = [ctypes.c_void_p]
lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
lib.Tcl_GetStringResult.restype = ctypes.c_char_p
lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
interp = lib.Tcl_CreateInterp()


def run(code, error=False):
    rc = lib.Tcl_Eval(interp, code.encode())
    result = lib.Tcl_GetStringResult(interp).decode()
    assert bool(rc) == error, result
    return result


try:
    if lib.Tcl_Init(interp):
        run('proc clock {args} {return mock_time}')
    run(r'''
        set opened 0
        set fault 0
        set bad_clock 0
        set synth_count 0
        set route_count 0
        set phys_count 0
        proc get_projects {args} {if {$::opened} {return project}; return {}}
        proc create_project {args} {set ::opened 1}
        proc close_project {} {set ::opened 0}
        proc version {args} {return MOCK_NOT_VIVADO}
        proc set_param {args} {}
        proc read_verilog {args} {
            if {![file exists [lindex $args end]]} {error "Missing RTL"}
        }
        proc read_xdc {args} {
            set f [open [lindex $args end]]; set x [read $f]; close $f
            if {![string match {*-period 8.000*} $x]} {error "Input clock changed"}
        }
        proc synth_design {args} {
            if {[string match *out_of_context* $args]} {error "OOC forbidden"}
            incr ::synth_count
            if {$::fault && $::mhz == 55} {error "Injected synthesis failure"}
        }
        foreach command {opt_design place_design} {proc $command {} {}}
        proc phys_opt_design {args} {
            if {$args ne {-directive AggressiveFanoutOpt}} {error "Wrong physical optimization directive"}
            incr ::phys_count
        }
        proc route_design {} {incr ::route_count}
        proc write_checkpoint {path} {ds_write $path "MOCK checkpoint"}
        proc get_pins {args} {return u_clock_gen/u_output_buffer/O}
        proc get_clocks {args} {return core_clock}
        proc get_cells {args} {return [lindex $args end]}
        proc get_timing_paths {args} {
            if {[lsearch -exact $args min] >= 0} {return hold}; return setup
        }
        proc get_property {name object} {
            if {$name eq "PERIOD"} {
                if {$::bad_clock && $::mhz == 54} {return 20.0}
                return [expr {1000.0/$::mhz}]
            }
            if {$name eq "SLACK"} {
                if {$object eq "hold"} {return 0.10}
                return [expr {$::mhz == 53 ? -0.25 : 0.50}]
            }
            error "Unexpected property $name"
        }
        proc mock_report {args} {
            set index [lsearch -exact $args -file]
            ds_write [lindex $args [expr {$index+1}]] "MOCK report"
        }
        foreach command {report_clocks report_timing_summary report_timing check_timing
            report_route_status report_drc report_methodology} {
            proc $command {args} {mock_report {*}$args}
        }
        proc report_utilization {args} {
            set index [lsearch -exact $args -file]
            ds_write [lindex $args [expr {$index+1}]] "| Slice LUTs* | 20,000 | 0 |\n| Slice Registers | 16,624 | 0 |"
        }
        set dcim_sweep_python python3
    ''')
    originals = {p: hashlib.sha256(p.read_bytes()).digest() for p in ROOT.glob("*/*.sv")}
    with tempfile.TemporaryDirectory(prefix="dcim sweep mock ") as temp:
        destination = Path(temp) / "all"
        script = ROOT / "vivado/sweep_dcim_frequency.tcl"
        run(f'set dcim_sweep_root {{{destination}}}; source {{{script}}}')
        assert run('set synth_count') == '7'
        assert run('set route_count') == '7'
        assert run('set phys_count') == '7'
        assert 'phys_opt_design -directive AggressiveFanoutOpt / route_design' in (destination / 'experiment.txt').read_text()
        rows = collect(destination)
        assert len(rows) == 14
        assert all(r['top_lut'] == 20000 and r['top_ff'] == 16624 for r in rows)
        assert all(r['setup_hold_status'] == ('FAIL' if r['frequency_mhz'] == 53 else 'PASS') for r in rows)
        expected = {45: (9, 25), 50: (8, 20), 51: (6.375, 15.625),
                    52: (6.5, 15.625), 53: (6.625, 15.625),
                    54: (6.75, 15.625), 55: (5.5, 12.5)}
        import re
        for mhz, (mult, divide) in expected.items():
            text = (destination / f'f{mhz}/dcim_clock_gen_125_to_50.sv').read_text()
            m = float(re.search(r'\.CLKFBOUT_MULT_F\s*\(([\d.]+)\)', text)[1])
            d = float(re.search(r'\.CLKOUT0_DIVIDE_F\s*\(([\d.]+)\)', text)[1])
            assert (m, d) == (mult, divide)
            assert abs(125*m/d - mhz) < 1e-9
            assert 600 <= 125*m <= 1200
            assert m*8 == int(m*8) and d*8 == int(d*8)
        # Plot with synthetic fixtures into a temporary directory only.
        summarize(destination)
        for name in ('summary.csv', 'SUMMARY.md', 'lut_vs_mhz.png', 'ff_vs_mhz.svg', 'frequency_overview.png', 'frequency_overview.svg'):
            assert (destination / name).stat().st_size > 100
        assert 'Output already exists' in run(f'source {{{script}}}', error=True)
        run('set opened 1')
        assert 'Close the current project' in run(f'source {{{script}}}', error=True)
        run('set opened 0; set dcim_sweep_frequencies {45 45}')
        assert 'Duplicate' in run(f'source {{{script}}}', error=True)
        run('set dcim_sweep_frequencies {75}')
        assert 'Unsupported' in run(f'source {{{script}}}', error=True)
        # Failure must not prevent later frequencies; bad generated clock must fail.
        failed = Path(temp) / 'failure'
        run(f'set dcim_sweep_root {{{failed}}}; set dcim_sweep_frequencies {{55 53 54}}; set fault 1; set bad_clock 1; source {{{script}}}')
        assert (failed / 'f55/status.txt').read_text().startswith('ERROR')
        assert (failed / 'f53/status.txt').read_text().startswith('COMPLETE')
        assert 'Wrong core period' in (failed / 'f54/status.txt').read_text()
        failed_rows = collect(failed)
        assert all(r['setup_hold_status'] == 'UNKNOWN' for r in failed_rows if r['frequency_mhz'] in (55, 54))
        assert all('top_lut' not in r for r in failed_rows if r['frequency_mhz'] in (55, 54))
        broken = Path(temp) / 'broken.rpt'
        broken.write_text('| LUT as Logic | 1 |\n')
        try:
            utilization(broken)
            raise AssertionError('Missing total should fail, not use LUT as Logic')
        except ValueError:
            pass
    assert all(hashlib.sha256(p.read_bytes()).digest() == digest for p, digest in originals.items())
    print('PASS: seven frequencies, real Tcl control flow/mock Vivado, snapshot isolation, no OOC/overwrite, clock guard, failure continuation, actual-format parser and synthetic plots. No Vivado synthesis performed.')
finally:
    lib.Tcl_DeleteInterp(interp)
