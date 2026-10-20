# Live RTL experiment: remove backend cross-group sum overflow check only.
# Keep correction_overflow, order checks, PIPE=1 POST=1 and 125/53 MHz.
# No project may be open. Existing output directories are never overwritten.
set bso_dir [file normalize [file dirname [info script]]]
if {![info exists backend_no_sum_root]} {
    set backend_no_sum_root [file normalize [file join $bso_dir ../../build kws_backend_no_sum_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]]
}
set order_root $backend_no_sum_root
set order_variants {checked}
source [file join $bso_dir run_order_experiment.tcl]
