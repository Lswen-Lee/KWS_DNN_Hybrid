# Vivado synthesis post hook; no synthesis/implementation launched here.
source [file join [file dirname [file normalize [info script]]] report_dcim_common.tcl]
dcim_export_reports post_synth
