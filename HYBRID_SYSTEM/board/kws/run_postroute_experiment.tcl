# Vivado 2023.2. Open an existing routed DCP, never re-read RTL/XDC.
# Refuse open projects/designs and existing output directories.
set pr_dir [file normalize [file dirname [info script]]]
if {[llength [get_projects -quiet]]} {
    error "Close the current project/design first"
}
# get_designs can throw 'No open project' even with -quiet in an empty GUI.
# Probe the current design defensively; open_checkpoint below creates context.
set pr_active_design {}
if {![catch {current_design -quiet} pr_active_design] && $pr_active_design ne ""} {
    error "Close the current project/design first"
}
if {![info exists pr_input]} {
    set pr_input [file normalize [file join $pr_dir ../../build/kws_strategy_run01/reports/aggressive/routed.dcp]]
}
if {![info exists pr_output]} {
    set pr_output [file normalize [file join $pr_dir ../../build kws_postroute_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]]
}
set pr_input [file normalize $pr_input]
set pr_output [file normalize $pr_output]
if {![file isfile $pr_input]} {error "Missing routed checkpoint: $pr_input"}
if {[file exists $pr_output]} {error "Refusing existing output directory: $pr_output"}
file mkdir $pr_output

proc pr_reports {directory stage csv} {
    file mkdir $directory
    report_timing_summary -report_unconstrained -file [file join $directory timing_summary.rpt]
    report_timing -delay_type max -max_paths 100 -nworst 1 -file [file join $directory setup_paths.rpt]
    report_timing -delay_type min -max_paths 20 -file [file join $directory hold_paths.rpt]
    report_utilization -file [file join $directory utilization.rpt]
    report_utilization -hierarchical -file [file join $directory utilization_hier.rpt]
    report_clocks -file [file join $directory clocks.rpt]
    report_route_status -file [file join $directory route_status.rpt]
    report_cdc -details -file [file join $directory cdc.rpt]
    report_exceptions -file [file join $directory exceptions.rpt]
    report_drc -file [file join $directory drc.rpt]
    report_methodology -file [file join $directory methodology.rpt]
    set f [open [file join $directory timing_summary.rpt] r]
    set text [read $f]; close $f
    set metrics {NA NA NA NA NA NA}
    set status UNKNOWN
    if {[regexp -line {^\s*(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+[0-9]+\s+(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+[0-9]+\s+} $text match wns tns setup_count whs ths hold_count]} {
        set metrics [list $wns $tns $setup_count $whs $ths $hold_count]
        set status [expr {$wns >= 0 && $whs >= 0 && $setup_count == 0 && $hold_count == 0 ? "PASS" : "FAIL"}]
    }
    set f [open [file join $directory utilization.rpt] r]
    set text [read $f]; close $f
    set lut NA; set ff NA
    regexp {\| Slice LUTs\s*\|\s*([0-9]+)} $text match lut
    regexp {\| Slice Registers\s*\|\s*([0-9]+)} $text match ff
    puts $csv "$stage,[join $metrics ,],$lut,$ff,$status"
    flush $csv
    puts "POSTROUTE $stage: metrics=$metrics setup/hold=$status"
}

set pr_csv [open [file join $pr_output summary.csv] w]
puts $pr_csv "stage,wns_ns,tns_ns,setup_failing_endpoints,whs_ns,ths_ns,hold_failing_endpoints,lut,ff,setup_hold_status"
set pr_rc [catch {
    open_checkpoint $pr_input
    # Verify board ports and route completeness, not a run label such as synth_1.
    if {[llength [get_ports -quiet sys_clk_125m]] != 1 ||
        [llength [get_ports -quiet reset_button]] != 1 ||
        [llength [get_ports -quiet {led[*]}]] != 4} {error "Unexpected checkpoint board interface"}
    report_route_status -file [file join $pr_output input_route_status.rpt]
    set f [open [file join $pr_output input_route_status.rpt] r]
    set text [read $f]; close $f
    if {![regexp {# of routable nets\.+\s*:\s*([0-9]+)} $text match routable] ||
        ![regexp {# of fully routed nets\.+\s*:\s*([0-9]+)} $text match routed] ||
        ![regexp {# of nets with routing errors\.+\s*:\s*([0-9]+)} $text match route_errors]} {error "Cannot verify checkpoint route status"}
    if {$routable == 0 || $routable != $routed || $route_errors != 0} {error "Checkpoint is not fully routed without route errors"}
    set pr_sys [get_clocks -quiet sys_clk_125m]
    set pr_cim [get_clocks -quiet cim_unbuffered]
    if {[llength $pr_sys] != 1 || [llength $pr_cim] != 1} {error "Missing expected clocks"}
    if {abs([get_property PERIOD $pr_sys] - 8.0) > 0.001 ||
        abs([get_property PERIOD $pr_cim] - 1000.0/53.0) > 0.002} {error "Expected 125/53MHz checkpoint"}
    set f [open [file join $pr_output experiment.txt] w]
    puts $f "Vivado: [version -short]\nSource DCP: $pr_input\nSource bytes: [file size $pr_input]\nSource mtime: [file mtime $pr_input]"
    puts $f "phys_opt_design -directive Explore; route_design -directive NoTimingRelaxation"
    puts $f "Checkpoint constraints retained. No synthesis, RTL edits, new exceptions or bitstream."
    close $f
    pr_reports [file join $pr_output before] before $pr_csv
    phys_opt_design -directive Explore
    # Complete/repair routing after physical changes before judging final STA.
    route_design -directive NoTimingRelaxation
    pr_reports [file join $pr_output after] after $pr_csv
    write_checkpoint [file join $pr_output after routed.dcp]
} pr_message pr_options]
close $pr_csv
if {$pr_rc} {
    set f [open [file join $pr_output error.txt] w]
    puts $f [dict get $pr_options -errorinfo]; close $f
    catch {close_design}
    return -options $pr_options $pr_message
}
close_design
puts "POSTROUTE COMPLETE: $pr_output/summary.csv"
puts "Negative slack is still FAIL. Review route status, pulse width, CDC, reset and DRC before signoff."
