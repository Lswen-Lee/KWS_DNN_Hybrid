# Current RTL: lookup register + original RNE pipeline + output register.
# Normal checked board run, fixed PIPE=1 POST=1, unchanged 125/53MHz XDC.
set pip_dir [file normalize [file dirname [info script]]]
if {![info exists pot_input_root]} {
    set pot_input_root [file normalize [file join $pip_dir ../../build kws_pot_input_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]]
}
set order_root $pot_input_root
set order_variants {checked}
source [file join $pip_dir run_order_experiment.tcl]
