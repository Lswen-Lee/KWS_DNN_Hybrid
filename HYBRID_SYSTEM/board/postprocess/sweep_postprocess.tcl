# Vivado 2023.2: normal board implementation, six independent projects.
# Optional: set pp_sweep_root {C:/fpga/postprocess/run01}; set pp_jobs 4
if {[llength [get_projects -quiet]]} {error "Close the current project before running the sweep"}
set sweep_script_dir [file normalize [file dirname [info script]]]
if {![info exists pp_jobs]} {set pp_jobs 4}
if {![string is integer -strict $pp_jobs] || $pp_jobs < 1} {error "pp_jobs must be positive"}
if {![info exists pp_sweep_root]} {
    set pp_sweep_root [file normalize [file join $sweep_script_dir ../../build/postprocess_sweep [clock format [clock seconds] -format run_%Y%m%d_%H%M%S]]]
}
if {[file exists $pp_sweep_root]} {error "Refusing to overwrite existing sweep: $pp_sweep_root"}
file mkdir $pp_sweep_root
set sweep_csv [file join $pp_sweep_root summary.csv]
set f [open $sweep_csv w]
puts $f "pipeline,target_mhz,status,actual_period_ns,LUT,FF,BRAM_tiles,DSP,BUFG,WNS_ns,WHS_ns,setup_hold_check"
close $f

proc pp_util_value {report labels} {
    foreach label $labels {
        set pattern [format {(?m)^\|\s*%s\s*\**\s*\|\s*([0-9,.]+)\s*\|} $label]
        if {[regexp $pattern $report -> value]} {return [string map {, {}} $value]}
    }
    return NA
}
proc pp_wait_complete {run} {
    wait_on_run $run
    set status [get_property STATUS [get_runs $run]]
    if {![string match -nocase {*Complete*} $status] || [string match -nocase {*error*} $status]} {
        error "$run did not complete: $status"
    }
}
set sweep_failed 0
set sweep_index 0
foreach pp_pipeline {0 1} {
    foreach pp_frequency {100 125 150} {
        incr sweep_index
        set pp_destination [file join $pp_sweep_root pp${pp_pipeline}_f${pp_frequency}]
        puts "SWEEP $sweep_index/6 START: pipeline=$pp_pipeline frequency=$pp_frequency MHz"
        set row [list $pp_pipeline $pp_frequency ERROR NA NA NA NA NA NA NA NA NOT_CHECKED]
        if {[catch {
            source [file join $sweep_script_dir create_project.tcl]
            launch_runs synth_1 -jobs $pp_jobs
            pp_wait_complete synth_1
            launch_runs impl_1 -to_step route_design -jobs $pp_jobs
            pp_wait_complete impl_1
            open_run impl_1
            source [file join $sweep_script_dir report.tcl]
            report_route_status -file [file join $pp_reports route_status.rpt]
            report_utilization -file [file join $pp_reports utilization_flat.rpt]
            set clock_pin [get_pins -hier -filter {NAME == output_buffer/O}]
            set test_clock [get_clocks -of_objects $clock_pin]
            if {[llength $test_clock] != 1} {error "Expected one MMCM output clock at output_buffer/O"}
            set actual_period [get_property PERIOD $test_clock]
            if {abs($actual_period - 1000.0/$pp_frequency) > 0.005} {
                error "Wrong generated clock period: $actual_period ns"
            }
            set setup_path [get_timing_paths -delay_type max -max_paths 1]
            set hold_path [get_timing_paths -delay_type min -max_paths 1]
            if {![llength $setup_path] || ![llength $hold_path]} {error "No setup/hold timing paths"}
            set wns [get_property SLACK $setup_path]
            set whs [get_property SLACK $hold_path]
            set util [report_utilization -return_string]
            set lut [pp_util_value $util {{Slice LUTs} {CLB LUTs}}]
            set ff [pp_util_value $util {{Slice Registers} {CLB Registers}}]
            set bram [pp_util_value $util {{Block RAM Tile}}]
            set dsp [pp_util_value $util {DSPs}]
            set bufg [pp_util_value $util {BUFGCTRL BUFG}]
            if {$lut eq "NA" || $ff eq "NA"} {error "Cannot parse LUT/FF: inspect utilization_flat.rpt"}
            set verdict [expr {$wns >= 0 && $whs >= 0 ? "PASS" : "FAIL"}]
            set row [list $pp_pipeline $pp_frequency COMPLETE $actual_period $lut $ff $bram $dsp $bufg $wns $whs $verdict]
        } message options]} {
            incr sweep_failed
            file mkdir $pp_destination
            set ef [open [file join $pp_destination sweep_error.log] w]
            puts $ef [dict get $options -errorinfo]
            close $ef
            puts "SWEEP ERROR: $message (continuing with next configuration)"
        }
        if {[llength [get_projects -quiet]]} {close_project}
        set f [open $sweep_csv a]
        puts $f [join $row ,]
        close $f
        puts "SWEEP $sweep_index/6 END: $row"
    }
}
puts "SWEEP FINISHED: 6 configurations, $sweep_failed execution errors. CSV: $sweep_csv"
puts "COMPLETE only means runs/reports finished. setup_hold_check excludes pulse width, DRC and unconstrained-path signoff. No bitstreams generated."
