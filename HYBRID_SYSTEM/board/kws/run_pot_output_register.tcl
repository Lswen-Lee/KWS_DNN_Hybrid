# Separate checked-only normal board run, reuses tested reporting flow.
# Optional pot_output_root and order_jobs. No existing directory overwritten.
set por_dir [file normalize [file dirname [info script]]]
if {![info exists pot_output_root]} {
    set pot_output_root [file normalize [file join $por_dir ../../build kws_pot_output_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]]
}
set order_root $pot_output_root
set order_variants {checked}
source [file join $por_dir run_order_experiment.tcl]
