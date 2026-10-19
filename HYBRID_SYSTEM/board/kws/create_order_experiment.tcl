# Import only. Two NEW independent normal (non-OOC) projects, same strategies.
# Set order_variant to checked or unchecked before sourcing. Run GUI synth/impl.
if {![info exists order_variant] || $order_variant ni {checked unchecked}} {
    error "Set order_variant checked or unchecked first"
}
set order_dir [file normalize [file dirname [info script]]]
if {![info exists order_root]} {
    set order_root [file normalize [file join $order_dir ../../build/kws_order_run01]]
}
set kws_destination [file join $order_root $order_variant]
set kws_pipe 1
set kws_post 1
set kws_check_result_order [expr {$order_variant eq "checked" ? 1 : 0}]
source [file join $order_dir create_project.tcl]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
puts "ORDER EXPERIMENT $order_variant: CHECK_RESULT_ORDER=$kws_check_result_order"
puts "125/53MHz, PIPE=1 POST=1, identical Default physical strategies; no timing exceptions added."
puts "Run Synthesis and Implementation in GUI. Do not edit live sources between variants."
