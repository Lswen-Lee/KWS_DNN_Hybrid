# Shared read-only design reporting. Report files are kept in the project tree.
proc dcim_export_reports {stage} {
    if {$stage ni {post_synth post_route}} {error "Unknown DCIM report stage: $stage"}
    set project_root [get_property DIRECTORY [current_project]]
    set report_base [file join $project_root reports $stage]
    set stamp [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]
    set output_dir [file join $report_base $stamp]
    set suffix 0
    while {[file exists $output_dir]} {
        incr suffix
        set output_dir [file join $report_base ${stamp}_$suffix]
    }
    file mkdir $output_dir
    report_utilization -file [file join $output_dir total_utilization.rpt]
    report_utilization -hierarchical -file [file join $output_dir hierarchy.rpt]
    foreach {name path} {macro u_chip/u_dcim_macro_core controller u_pin_master} {
        set cells [get_cells -quiet $path]
        if {[llength $cells] == 1} {
            report_utilization -cells $cells -file [file join $output_dir ${name}_utilization.rpt]
        } else {
            puts "WARNING: DCIM report skipped $name: hierarchy $path not found. Check top/flattening."
        }
    }
    report_timing_summary -report_unconstrained -file [file join $output_dir timing_summary.rpt]
    report_control_sets -verbose -file [file join $output_dir control_sets.rpt]
    if {$stage eq "post_route"} {
        report_route_status -file [file join $output_dir route_status.rpt]
        report_drc -file [file join $output_dir drc.rpt]
        report_methodology -file [file join $output_dir methodology.rpt]
    }
    puts "DCIM $stage reports: $output_dir"
}
