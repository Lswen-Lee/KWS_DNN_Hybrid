# Normal (not OOC) board-top frequency sweep, Vivado 2023.2.
# GUI: close_project; source /path/to/this_script.tcl
# Batch: vivado -mode batch -source this_script.tcl -tclargs C:/dcim_sweep/run1
# Optional GUI variables: dcim_sweep_root, dcim_sweep_frequencies, dcim_sweep_python.
# Never edits source RTL or overwrites an existing experiment directory.
set ds_script_dir [file dirname [file normalize [info script]]]
set ds_root [file dirname $ds_script_dir]
if {[llength [get_projects -quiet]]} {error "Close the current project before running the sweep."}
if {![info exists dcim_sweep_frequencies]} {set dcim_sweep_frequencies {45 50 51 52 53 54 55}}
# frequency -> {feedback multiplier output divider}; input divider is always 1.
set ds_settings [dict create 45 {9.000 25.000} 50 {8.000 20.000} \
    51 {6.375 15.625} 52 {6.500 15.625} 53 {6.625 15.625} \
    54 {6.750 15.625} 55 {5.500 12.500}]
if {![llength $dcim_sweep_frequencies]} {error "Empty frequency list"}
foreach mhz $dcim_sweep_frequencies {
    if {![dict exists $ds_settings $mhz]} {error "Unsupported MHz: $mhz; supported: [dict keys $ds_settings]"}
}
if {[llength [lsort -unique $dcim_sweep_frequencies]] != [llength $dcim_sweep_frequencies]} {error "Duplicate frequency"}
if {![info exists dcim_sweep_root]} {
    if {[info exists argc] && $argc > 0} {
        set dcim_sweep_root [lindex $argv 0]
    } else {
        set dcim_sweep_root [file join $ds_root build frequency_sweep [clock format [clock seconds] -format %Y%m%d_%H%M%S]]
    }
}
set dcim_sweep_root [file normalize $dcim_sweep_root]
if {[file exists $dcim_sweep_root]} {error "Output already exists; choose a NEW dcim_sweep_root: $dcim_sweep_root"}

proc ds_write {path content} {
    set f [open $path w]; puts $f $content; close $f
}
proc ds_patch_clock {source target multiplier divider} {
    set f [open $source r]; set content [read $f]; close $f
    foreach {name value} [list DIVCLK_DIVIDE 1 CLKFBOUT_MULT_F $multiplier CLKOUT0_DIVIDE_F $divider] {
        set pattern [format {\.%s\s*\(\s*[0-9.]+\s*\)} $name]
        if {[regsub -all $pattern $content [format {.%s (%s)} $name $value] content] != 1} {
            error "Expected exactly one literal $name in clock generator"
        }
    }
    ds_write $target "// GENERATED SWEEP COPY: original frequency comments/names below are historical.\n$content"
}
proc ds_check_clock {mhz} {
    set pin [get_pins -quiet u_clock_gen/u_output_buffer/O]
    if {[llength $pin] != 1} {error "Output BUFG pin not found"}
    set clocks [get_clocks -quiet -of_objects $pin]
    if {[llength $clocks] != 1} {error "Expected one generated core clock"}
    set period [get_property PERIOD $clocks]
    if {abs($period - 1000.0/$mhz) > 0.002} {error "Wrong core period $period for $mhz MHz"}
    return $period
}
proc ds_reports {directory stage mhz} {
    set out [file join $directory $stage]; file mkdir $out
    set period [ds_check_clock $mhz]
    report_clocks -file [file join $out clocks.rpt]
    report_utilization -file [file join $out top_utilization.rpt]
    report_utilization -hierarchical -file [file join $out hierarchy.rpt]
    foreach {name path} {chip u_chip macro u_chip/u_dcim_macro_core controller u_pin_master self_test u_self_test} {
        set cell [get_cells -quiet $path]
        if {[llength $cell] != 1} {error "Missing reporting hierarchy $path; do not silently report zero area"}
        report_utilization -cells $cell -file [file join $out ${name}_utilization.rpt]
    }
    report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
    report_timing -delay_type max -max_paths 10 -file [file join $out setup_paths.rpt]
    report_timing -delay_type min -max_paths 10 -file [file join $out hold_paths.rpt]
    check_timing -verbose -file [file join $out check_timing.rpt]
    set setup [get_timing_paths -quiet -delay_type max -max_paths 1]
    set hold [get_timing_paths -quiet -delay_type min -max_paths 1]
    if {![llength $setup] || ![llength $hold]} {error "Missing timing paths"}
    ds_write [file join $out metrics.tsv] "frequency_mhz\tperiod_ns\twns_ns\twhs_ns\n$mhz\t$period\t[get_property SLACK $setup]\t[get_property SLACK $hold]"
    if {$stage eq "post_route"} {
        report_route_status -file [file join $out route_status.rpt]
        report_drc -file [file join $out drc.rpt]
        report_methodology -file [file join $out methodology.rpt]
    }
}

# Freeze all input files once so every frequency compares the same RTL/XDC.
set ds_snapshot [file join $dcim_sweep_root snapshot]; file mkdir $ds_snapshot
set ds_sources {}
foreach folder {cell segment peripheral array chip fpga} {
    foreach source [lsort [glob -directory [file join $ds_root $folder] *.sv]] {
        set target [file join $ds_snapshot $folder [file tail $source]]
        file mkdir [file dirname $target]; file copy $source $target
        lappend ds_sources $target
    }
}
set ds_xdc [file join $ds_snapshot board.xdc]
file copy [file join $ds_root constraints dcim_master_chip_top_pynq_z2.xdc] $ds_xdc
ds_write [file join $dcim_sweep_root source_manifest.txt] [join $ds_sources \n]
ds_write [file join $dcim_sweep_root experiment.txt] "Vivado: [version -short]\nPart: xc7z020clg400-1\nTop: dcim_master_chip_top\nFrequencies: $dcim_sweep_frequencies\nFlow: normal synth_design / opt_design / place_design / phys_opt_design -directive AggressiveFanoutOpt / route_design\nFlatten: rebuilt; threads: 4; input clock: 125 MHz\nXDC: frozen existing board constraints; no added timing exceptions\nRTL attributes including DONT_TOUCH: inherited unchanged from snapshot; inspect snapshot/fpga/dcim_master_chip_top.sv\n"
file copy [info script] [file join $dcim_sweep_root sweep_script.tcl]
file copy [file join $ds_root scripts summarize_dcim_sweep.py] [file join $dcim_sweep_root summarize_dcim_sweep.py]
set_param general.maxThreads 4
foreach mhz $dcim_sweep_frequencies {
    set run_dir [file join $dcim_sweep_root f${mhz}]; file mkdir $run_dir
    lassign [dict get $ds_settings $mhz] mult divide
    puts "DCIM SWEEP: $mhz MHz -> $run_dir"
    set result [catch {
        set clock_copy [file join $run_dir dcim_clock_gen_125_to_50.sv]
        ds_patch_clock [file join $ds_snapshot fpga dcim_clock_gen_125_to_50.sv] $clock_copy $mult $divide
        ds_write [file join $run_dir configuration.txt] "MHz=$mhz\nDIVCLK_DIVIDE=1\nCLKFBOUT_MULT_F=$mult\nCLKOUT0_DIVIDE_F=$divide"
        create_project -in_memory -part xc7z020clg400-1
        foreach source $ds_sources {
            if {[file tail $source] eq "dcim_clock_gen_125_to_50.sv"} {read_verilog -sv $clock_copy} else {read_verilog -sv $source}
        }
        read_xdc $ds_xdc
        synth_design -top dcim_master_chip_top -part xc7z020clg400-1 -flatten_hierarchy rebuilt
        write_checkpoint [file join $run_dir synthesized.dcp]
        ds_reports $run_dir post_synth $mhz
        opt_design
        place_design
        phys_opt_design -directive AggressiveFanoutOpt
        route_design
        write_checkpoint [file join $run_dir routed.dcp]
        ds_reports $run_dir post_route $mhz
    } message options]
    if {$result} {
        ds_write [file join $run_dir status.txt] "ERROR\n$message\n[dict get $options -errorinfo]"
        puts "WARNING: $mhz MHz failed: $message; continuing other frequencies."
    } else {
        ds_write [file join $run_dir status.txt] "COMPLETE"
    }
    if {[llength [get_projects -quiet]]} {close_project}
}
if {![info exists dcim_sweep_python]} {set dcim_sweep_python python}
if {[catch {exec {*}$dcim_sweep_python [file join $dcim_sweep_root summarize_dcim_sweep.py] $dcim_sweep_root 2>@1} summary]} {
    puts "WARNING: Automatic summary/plot failed: $summary"
    puts "Run Python manually: summarize_dcim_sweep.py $dcim_sweep_root"
} else {puts $summary}
puts "Sweep finished. Inspect status.txt AND timing/DRC reports for every frequency: $dcim_sweep_root"
