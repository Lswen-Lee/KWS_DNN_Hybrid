# Compatibility entry point.
# The build script now creates/imports the Vivado project only.  Synthesis,
# implementation, and bitstream generation are left for manual GUI use.

set wrapper_dir [file dirname [file normalize [info script]]]
source [file join $wrapper_dir create_dcim_master_chip_project_pynq_z2.tcl]
