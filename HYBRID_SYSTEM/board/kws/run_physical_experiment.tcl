# Vivado 2023.2 GUI or batch. New project, one synthesis, independent impl runs.
# Never resets the user's original project/runs. RTL and constraints unchanged.
# Override kws_destination before source; an existing directory is refused.
set px_script_dir [file normalize [file dirname [info script]]]
if {[llength [get_projects -quiet]]} {error "Close the current project before this experiment"}
if {![info exists kws_destination]} {
    set kws_destination [file normalize [file join $px_script_dir ../../build/kws_phys_run01]]
}
if {![info exists px_jobs]} {set px_jobs 4}
if {![string is integer -strict $px_jobs] || $px_jobs < 1} {error "px_jobs must be positive"}
if {![info exists px_variants]} {set px_variants {baseline fanout}}
if {![llength $px_variants]} {error "No experiment variants selected"}
foreach px_variant $px_variants {
    if {$px_variant ni {baseline fanout explore aggressive}} {error "Unknown variant $px_variant"}
}
if {[llength [lsort -unique $px_variants]] != [llength $px_variants]} {error "Duplicate variants"}
set kws_pipe 1
set kws_post 1
set kws_check_result_order 1
source [file join $px_script_dir create_project.tcl]
set px_destination [get_property DIRECTORY [current_project]]
set px_flow [get_property FLOW [get_runs impl_1]]
set px_hook [file join $px_script_dir pre_opt.tcl]

proc px_wait_complete {run_name} {
    wait_on_run $run_name
    set status [get_property STATUS [get_runs $run_name]]
    puts "EXPERIMENT RUN $run_name : $status"
    set flow_status [string tolower $status]
    regsub {, failed timing!$} $flow_status {} flow_status
    if {![string match -nocase {*complete*} $status] ||
        [string match {*error*} $flow_status] ||
        [string match {*fail*} $flow_status] ||
        [get_property PROGRESS [get_runs $run_name]] ne "100%"} {
        error "$run_name did not complete. Inspect its runme.log; status=$status"
    }
}
proc px_reports {destination} {
    file mkdir $destination
    report_clocks -file [file join $destination clocks.rpt]
    report_utilization -file [file join $destination utilization.rpt]
    report_utilization -hierarchical -file [file join $destination utilization_hier.rpt]
    report_timing_summary -report_unconstrained -file [file join $destination timing_summary.rpt]
    report_timing -delay_type max -max_paths 100 -nworst 1 -file [file join $destination setup_paths.rpt]
    report_timing -delay_type min -max_paths 20 -file [file join $destination hold_paths.rpt]
    report_route_status -file [file join $destination route_status.rpt]
    report_cdc -details -file [file join $destination cdc.rpt]
    report_exceptions -file [file join $destination exceptions.rpt]
    report_clock_interaction -file [file join $destination clock_interaction.rpt]
    report_drc -file [file join $destination drc.rpt]
    report_methodology -file [file join $destination methodology.rpt]
    write_checkpoint [file join $destination routed.dcp]
}

# All variants have the same synthesis parent, so physical changes are not
# confounded with a different synthesis netlist. No OOC or incremental reference.
foreach px_variant $px_variants {
    set px_run impl_$px_variant
    create_run $px_run -parent_run synth_1 -flow $px_flow -constrset constrs_1
    set px_obj [get_runs $px_run]
    set_property strategy {Vivado Implementation Defaults} $px_obj
    set_property STEPS.OPT_DESIGN.TCL.PRE $px_hook $px_obj
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $px_obj
    set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default $px_obj
    set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Default $px_obj
    set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Default $px_obj
    set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Default $px_obj
    if {$px_variant eq "fanout"} {
        set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveFanoutOpt $px_obj
    }
    if {$px_variant in {explore aggressive}} {
        set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Explore $px_obj
        set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore $px_obj
        set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore $px_obj
        set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore $px_obj
    }
    if {$px_variant eq "aggressive"} {
        set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $px_obj
        set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE NoTimingRelaxation $px_obj
    }
}
file mkdir [file join $px_destination reports]
set px_info [open [file join $px_destination reports experiment.txt] w]
puts $px_info "Vivado: [version -short]"
puts $px_info "PIPE=1 POST=1 CHECK_RESULT_ORDER=1; system=125MHz CIM=53MHz; no RTL/constraint edits"
puts $px_info "Variants: $px_variants; shared synthesis=synth_1"
puts $px_info "baseline: all Default, post-place phys enabled"
puts $px_info "fanout: baseline except post-place phys AggressiveFanoutOpt"
puts $px_info "explore: opt/place/phys/route Explore (multi-variable experiment)"
puts $px_info "aggressive: opt/place Explore, phys AggressiveExplore, route NoTimingRelaxation"
puts $px_info "Sources are live; do not edit RTL, ROM, XDC or hooks during this run."
close $px_info
launch_runs synth_1 -jobs $px_jobs
px_wait_complete synth_1
set px_csv [open [file join $px_destination reports summary.csv] w]
puts $px_csv "variant,flow_status,wns_ns,tns_ns,setup_failing_endpoints,whs_ns,ths_ns,hold_failing_endpoints,lut,ff,setup_hold_status"
flush $px_csv
set px_failed {}
foreach px_variant $px_variants {
    set px_run impl_$px_variant
    set px_code [catch {
    launch_runs $px_run -to_step route_design -jobs $px_jobs
    px_wait_complete $px_run
    open_run $px_run
    px_reports [file join $px_destination reports $px_variant]
    # Parse the generated summary rather than summing a truncated path list.
    set px_f [open [file join $px_destination reports $px_variant timing_summary.rpt] r]
    set px_text [read $px_f]; close $px_f
    set px_metrics {NA NA NA NA NA NA}
    if {[regexp -line {^\s*(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+[0-9]+\s+(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+[0-9]+\s+} $px_text px_match wns tns setup_count whs ths hold_count]} {
        set px_metrics [list $wns $tns $setup_count $whs $ths $hold_count]
    }
    set px_f [open [file join $px_destination reports $px_variant utilization.rpt] r]
    set px_text [read $px_f]; close $px_f
    set px_lut NA; set px_ff NA
    regexp {\| Slice LUTs\s*\|\s*([0-9]+)} $px_text px_match px_lut
    regexp {\| Slice Registers\s*\|\s*([0-9]+)} $px_text px_match px_ff
    set px_pass UNKNOWN
    if {[lindex $px_metrics 0] ne "NA"} {
        set px_pass [expr {$wns >= 0 && $whs >= 0 && $setup_count == 0 && $hold_count == 0 ? "PASS" : "FAIL"}]
    }
    puts $px_csv "$px_variant,COMPLETE,[join $px_metrics ,],$px_lut,$px_ff,$px_pass"
    flush $px_csv
    close_design
    } px_message px_options]
    if {$px_code} {
        set px_f [open [file join $px_destination reports ${px_variant}_error.txt] w]
        puts $px_f [dict get $px_options -errorinfo]; close $px_f
        puts $px_csv "$px_variant,ERROR,NA,NA,NA,NA,NA,NA,NA,NA,UNKNOWN"
        flush $px_csv
        lappend px_failed $px_variant
        puts "EXPERIMENT ERROR $px_variant: $px_message"
        catch {close_design}
    }
}
close $px_csv
puts "EXPERIMENT COMPLETE: $px_destination/reports"
puts "Run complete is NOT timing/CDC signoff. Compare setup, hold, resources and exceptions."
if {[llength $px_failed]} {error "Failed strategies: $px_failed; inspect reports/*_error.txt and runme.log"}
