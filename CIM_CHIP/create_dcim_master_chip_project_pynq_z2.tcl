# Create an import-only Vivado project for the PYNQ-Z2 DCIM design.
# This script adds RTL/XDC files and sets the top module.  It intentionally
# does not run synthesis, implementation, or bitstream generation.

set cim_root [file dirname [file normalize [info script]]]

# Optional first Tcl argument selects the project directory:
#   vivado -mode batch -source this_script.tcl -tclargs C:/vivado_build/dcim
if {[info exists dcim_project_dir]} {
    # GUI: set dcim_project_dir {C:/vivado_build/dcim_master_chip_50m}
    set project_dir [file normalize $dcim_project_dir]
} elseif {[info exists argc] && ($argc >= 1)} {
    set project_dir [file normalize [lindex $argv 0]]
} else {
    set project_dir [file join $cim_root build dcim_master_chip]
}

if {[llength [get_projects -quiet]] != 0} {
    error "Close the current project first. No project was modified."
}
if {[file exists $project_dir]} {
    error "Directory exists: $project_dir. Open its XPR or choose a NEW dcim_project_dir; no overwrite performed."
}

# Scan only synthesizable source directories.  Testbenches and old Vivado
# output directories are deliberately excluded.
set rtl_directories [list \
    [file join $cim_root cell] \
    [file join $cim_root segment] \
    [file join $cim_root peripheral] \
    [file join $cim_root array] \
    [file join $cim_root chip] \
    [file join $cim_root fpga] \
]

set rtl_sources [list]
foreach rtl_directory $rtl_directories {
    foreach rtl_file [lsort [glob -nocomplain -directory $rtl_directory *.sv]] {
        lappend rtl_sources [file normalize $rtl_file]
    }
}

if {[llength $rtl_sources] == 0} {
    error "No SystemVerilog source files were found below $cim_root"
}

set constraint_file [file join $cim_root constraints \
    dcim_master_chip_top_pynq_z2.xdc]
if {![file exists $constraint_file]} {
    error "Constraint file not found: $constraint_file"
}
create_project dcim_master_chip_pynq_z2 $project_dir \
    -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -norecurse $rtl_sources
set_property file_type SystemVerilog [get_files $rtl_sources]
add_files -fileset constrs_1 -norecurse $constraint_file

set_property top dcim_master_chip_top [get_filesets sources_1]
set_property STEPS.SYNTH_DESIGN.TCL.POST \
    [file join $cim_root vivado report_dcim_post_synth.tcl] [get_runs synth_1]
set_property STEPS.ROUTE_DESIGN.TCL.POST \
    [file join $cim_root vivado report_dcim_post_route.tcl] [get_runs impl_1]
update_compile_order -fileset sources_1

puts "================================================================"
puts "DCIM master/chip Vivado project created"
puts "Project : $project_dir"
puts "Top     : dcim_master_chip_top"
puts "RTL     : [llength $rtl_sources] SystemVerilog files"
puts "XDC     : $constraint_file"
puts "Reports : [file join $project_dir reports] (generated after synthesis/route)"
puts "No synthesis, implementation, or bitstream run was started."
puts "Open the .xpr project and run those steps manually in Vivado."
puts "================================================================"
