# Physical CDC constraints after synthesis, before opt_design. Fail closed if
# names disappear; inspect the netlist rather than silently dropping constraints.
proc kws_require {objects label} {
    if {![llength $objects]} {error "KWS missing netlist objects: $label"}
    return $objects
}
set sys_clock [kws_require [get_clocks -quiet sys_clk_125m] system_clock]
set cim_pin [kws_require [get_pins -quiet -hier -filter {NAME =~ */clocks/mmcm/CLKOUT0 || NAME == clocks/mmcm/CLKOUT0}] mmcm_output]
set cim_clock [kws_require [get_clocks -quiet -of_objects $cim_pin] cim_clock]
# Only the first synchronizer D is exempted. Stage1->stage2 remains timed.
set meta [kws_require [get_cells -quiet -hier -regexp {.*u_cdc/(request_sync_meta_50|response_sync_meta_125)_reg}] toggle_meta]
set_false_path -to [get_pins -of_objects $meta -filter {REF_PIN_NAME == D}]
# Fixed and conservative 6ns mailbox propagation budget, below both periods.
# Data is held until the round trip completes. No broad clock-group exceptions.
set cmd [kws_require [get_cells -quiet -hier -regexp {.*u_cdc/command_.*_125_reg(\[[0-9]+\])?}] command_mailbox]
set rsp [kws_require [get_cells -quiet -hier -regexp {.*u_cdc/response_(data_valid|error|sram_read_data|even_raw_result|odd_raw_result)_50_reg(\[[0-9]+\])?}] response_mailbox]
set_max_delay 6.000 -datapath_only -from $cmd -to $cim_clock
set_max_delay 6.000 -datapath_only -from $rsp -to $sys_clock
# Internal asynchronous reset sources only: target reset/clear pins, not D paths.
set reset_pins [get_pins -quiet -hier -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}]
if {[llength $reset_pins]} {set_false_path -to $reset_pins}
# MMCM LOCKED is asynchronous to system logic; synchronize its first stage.
set lock_meta [kws_require [get_cells -quiet -hier -regexp {.*clocks/lock_sync_reg\[0\]}] lock_meta]
set_false_path -to [get_pins -of_objects $lock_meta -filter {REF_PIN_NAME == D}]
puts "KWS CDC constraints applied: command regs=[llength $cmd], response regs=[llength $rsp]. Review report_cdc and exceptions."
