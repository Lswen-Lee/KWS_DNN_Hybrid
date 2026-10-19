# Vivado 2023.2 GUI: source this file with no project open.
# Batch: vivado -mode batch -source <this file>
# Optional variables: order_root, order_variants, order_jobs, kws_vectors.
# Independent normal (not OOC) synthesis and implementation for each variant.
set oe_dir [file normalize [file dirname [info script]]]
if {[llength [get_projects -quiet]]} {error "Close the current project first"}
if {![info exists order_root]} {
    set order_root [file normalize [file join $oe_dir ../../build kws_order_auto_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]]
}
set order_root [file normalize $order_root]
if {![info exists order_variants]} {set order_variants {checked unchecked}}
if {![info exists order_jobs]} {set order_jobs 4}
if {![string is integer -strict $order_jobs] || $order_jobs < 1} {error "order_jobs must be positive"}
if {![llength $order_variants] || [llength [lsort -unique $order_variants]] != [llength $order_variants]} {
    error "Select a nonempty unique list of variants"
}
foreach oe_variant $order_variants {
    if {$oe_variant ni {checked unchecked}} {error "Unknown variant: $oe_variant"}
}
if {[file exists $order_root]} {error "Refusing existing directory: $order_root; choose a new order_root"}
file mkdir $order_root

proc oe_wait {run_name} {
    wait_on_run $run_name
    set status [get_property STATUS [get_runs $run_name]]
    puts "ORDER RUN $run_name: $status"
    # Vivado reports successful routing with negative slack as
    # "route_design Complete, Failed Timing!". This is NOT a run failure.
    # Strip only this known suffix; retain all other failure/error checks.
    set flow_status [string tolower $status]
    regsub {, failed timing!$} $flow_status {} flow_status
    if {![string match -nocase {*complete*} $status] ||
        [string match {*error*} $flow_status] ||
        [string match {*fail*} $flow_status] ||
        [get_property PROGRESS [get_runs $run_name]] ne "100%"} {
        error "$run_name did not complete: $status (inspect runme.log)"
    }
}
proc oe_slack {delay_type} {
    set paths [get_timing_paths -quiet -delay_type $delay_type -max_paths 1 -nworst 1]
    if {![llength $paths]} {return NA}
    return [get_property SLACK [lindex $paths 0]]
}

set oe_csv [open [file join $order_root summary.csv] w]
puts $oe_csv "variant,check_result_order,flow_status,wns_ns,whs_ns,setup_hold_status"
flush $oe_csv
set oe_failed {}
foreach order_variant $order_variants {
    puts "===== START $order_variant ====="
    set oe_code [catch {
        source [file join $oe_dir create_order_experiment.tcl]
        set oe_reports [file join $kws_destination reports order]
        file mkdir $oe_reports
        launch_runs synth_1 -jobs $order_jobs
        oe_wait synth_1
        open_run synth_1
        report_utilization -hierarchical -file [file join $oe_reports utilization_synth.rpt]
        close_design
        launch_runs impl_1 -to_step route_design -jobs $order_jobs
        oe_wait impl_1
        open_run impl_1
        source [file join $oe_dir report_order_experiment.tcl]
        report_utilization -file [file join $oe_reports utilization.rpt]
        report_timing -delay_type min -max_paths 20 -file [file join $oe_reports hold_paths.rpt]
        report_clocks -file [file join $oe_reports clocks.rpt]
        report_exceptions -file [file join $oe_reports exceptions.rpt]
        report_route_status -file [file join $oe_reports route_status.rpt]
        report_drc -file [file join $oe_reports drc.rpt]
        report_methodology -file [file join $oe_reports methodology.rpt]
        write_checkpoint [file join $oe_reports routed.dcp]
        set oe_wns [oe_slack max]
        set oe_whs [oe_slack min]
        set oe_timing UNKNOWN
        if {$oe_wns ne "NA" && $oe_whs ne "NA"} {
            set oe_timing [expr {$oe_wns >= 0 && $oe_whs >= 0 ? "PASS" : "FAIL"}]
        }
        puts $oe_csv "$order_variant,$kws_check_result_order,COMPLETE,$oe_wns,$oe_whs,$oe_timing"
        flush $oe_csv
        puts "ORDER RESULT $order_variant: routed; setup/hold=$oe_timing WNS=$oe_wns WHS=$oe_whs"
    } oe_message oe_options]
    if {$oe_code} {
        set oe_error [open [file join $order_root ${order_variant}_error.txt] w]
        puts $oe_error $oe_message
        puts $oe_error [dict get $oe_options -errorinfo]
        close $oe_error
        puts $oe_csv "$order_variant,[expr {$order_variant eq "checked" ? 1 : 0}],ERROR,NA,NA,UNKNOWN"
        flush $oe_csv
        lappend oe_failed $order_variant
        puts "ERROR $order_variant: $oe_message"
    }
    if {[llength [get_projects -quiet]]} {close_project}
}
close $oe_csv
puts "ORDER EXPERIMENT FINISHED: $order_root/summary.csv"
puts "Setup/hold PASS is not signoff: inspect pulse width, unconstrained paths, CDC, DRC and methodology. No bitstream generated."
if {[llength $oe_failed]} {error "Failed variants: $oe_failed; see *_error.txt and runme.log"}
