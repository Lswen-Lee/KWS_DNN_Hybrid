# Vivado route_design post hook, before any later manual optimization.
source [file join [file dirname [file normalize [info script]]] report_dcim_common.tcl]
dcim_export_reports post_route
