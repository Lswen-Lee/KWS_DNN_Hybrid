"""Run actual sweep/import/report Tcl with mocked Vivado; no physical timing claims."""
import csv
import ctypes
import ctypes.util
from pathlib import Path
import tempfile

lib = ctypes.CDLL(ctypes.util.find_library('tcl8.6'))
lib.Tcl_CreateInterp.restype = ctypes.c_void_p
lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
lib.Tcl_GetStringResult.restype = ctypes.c_char_p
lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
script = Path(__file__).with_name('sweep_postprocess.tcl').as_posix()
mock = r'''
set project_open 0
set launches {}
proc get_projects {args} {if {$::project_open} {return project}; return {}}
proc create_project {name destination args} {
    set ::project_open 1
    set ::project_path $destination
    file mkdir $destination
}
proc close_project {} {set ::project_open 0}
proc current_project {} {return project}
proc get_designs {args} {return design}
proc add_files {args} {}
proc get_files {args} {return svfiles}
proc get_filesets {args} {return sources_1}
proc get_runs {run} {return $run}
proc set_property {args} {
    if {[string match *out_of_context* $args]} {error "OOC is forbidden"}
}
proc launch_runs {args} {lappend ::launches [list $::pp_pipeline $::pp_frequency {*}$args]}
proc wait_on_run {args} {}
proc open_run {args} {}
proc get_pins {args} {return output_buffer/O}
proc get_clocks {args} {return generated_clk}
proc get_timing_paths {args} {return [lindex $args 1]}
proc get_property {property object} {
    switch -- $property {
        STATUS {
            if {$::scenario eq "failed_run" && $::pp_pipeline == 0 && $::pp_frequency == 125 && $object eq "synth_1"} {return "synth_design ERROR"}
            return "route_design Complete!"
        }
        PERIOD {
            if {$::scenario eq "wrong_clock" && $::pp_pipeline == 0 && $::pp_frequency == 125} {return 8.8}
            return [expr {1000.0/$::pp_frequency}]
        }
        SLACK {if {$object eq "max" && $::pp_frequency == 150} {return -0.1}; return 0.2}
        DIRECTORY {return $::project_path}
        default {error "Unexpected property $property"}
    }
}
proc report_utilization {args} {
    return "| Slice LUTs* | 1,234 |\n| Slice Registers | 567 |\n| Block RAM Tile | 0.5 |\n| DSPs | 0 |\n| BUFGCTRL | 2 |"
}
foreach command {report_clocks report_timing_summary report_timing report_methodology report_drc check_timing report_route_status} {
    proc $command {args} {}
}
'''
for scenario in ['normal', 'failed_run', 'wrong_clock']:
    with tempfile.TemporaryDirectory(prefix='pp_sweep_test_') as temporary:
        root = Path(temporary) / 'run01'
        interp = lib.Tcl_CreateInterp()
        def evaluate(text):
            code = lib.Tcl_Eval(interp, text.encode())
            result = lib.Tcl_GetStringResult(interp).decode()
            return code, result
        code, result = evaluate(mock + f'\nset scenario {scenario}\nset pp_sweep_root {{{root.as_posix()}}}\nsource {{{script}}}')
        assert code == 0, result
        with (root / 'summary.csv').open() as f:
            rows = list(csv.DictReader(f))
        assert [(r['pipeline'], r['target_mhz']) for r in rows] == [(str(p), str(m)) for p in [0, 1] for m in [100, 125, 150]]
        for row in rows:
            if scenario != 'normal' and row['pipeline'] == '0' and row['target_mhz'] == '125':
                assert row['status'] == 'ERROR'
                assert (root / 'pp0_f125/sweep_error.log').exists()
            else:
                assert row['status'] == 'COMPLETE'
                assert row['LUT'] == '1234' and row['FF'] == '567'
                assert row['BRAM_tiles'] == '0.5' and row['BUFG'] == '2'
                assert row['setup_hold_check'] == ('FAIL' if row['target_mhz'] == '150' else 'PASS')
        code, result = evaluate(f'source {{{script}}}')
        assert code != 0 and 'Refusing to overwrite' in result
        lib.Tcl_DeleteInterp(interp)
print('PASS sweep Tcl mock: six combinations, resource parsing, timing FAIL vs run ERROR, wrong-clock guard, continue-on-error, no overwrite')
