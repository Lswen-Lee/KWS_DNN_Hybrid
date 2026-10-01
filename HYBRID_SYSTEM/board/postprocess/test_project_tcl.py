"""Execute import Tcl in a mocked Tcl interpreter; NOT Vivado validation."""
import ctypes
import ctypes.util
from pathlib import Path

lib = ctypes.CDLL(ctypes.util.find_library('tcl8.6'))
lib.Tcl_CreateInterp.restype = ctypes.c_void_p
lib.Tcl_Eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.Tcl_GetStringResult.argtypes = [ctypes.c_void_p]
lib.Tcl_GetStringResult.restype = ctypes.c_char_p
lib.Tcl_DeleteInterp.argtypes = [ctypes.c_void_p]
script = Path(__file__).with_name('create_project.tcl').as_posix()
for mode in [0, 1]:
    interp = lib.Tcl_CreateInterp()
    text = f'''
        set pp_pipeline {mode}
        set pp_frequency 150
        set pp_destination /tmp/pp_mock_nonexistent_destination_{mode}
        proc get_projects {{args}} {{return {{}}}}
        proc create_project {{args}} {{set ::created $args}}
        proc add_files {{args}} {{lappend ::sources $args}}
        proc get_files {{args}} {{return svfiles}}
        proc get_filesets {{args}} {{return sources_1}}
        proc get_runs {{args}} {{return [lindex $args 0]}}
        proc set_property {{args}} {{lappend ::properties $args}}
        source {{{script}}}
        if {{[lsearch -exact $properties {{generic {{POSTPROCESS_PIPELINED={mode} OUTPUT_DIVIDE=5.0}} sources_1}}] < 0}} {{error "Wrong clock/mode generics"}}
        if {{[string match *out_of_context* $properties]}} {{error "Unexpected OOC"}}
        if {{[lsearch -exact $created xc7z020clg400-1] < 0}} {{error "Wrong part"}}
    '''
    status = lib.Tcl_Eval(interp, text.encode())
    result = lib.Tcl_GetStringResult(interp).decode()
    lib.Tcl_DeleteInterp(interp)
    assert status == 0, result
print('PASS Tcl import mock: comb/pipeline, 150 MHz generics, normal flow, PYNQ-Z2 part')
