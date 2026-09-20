# Source after Open Synthesized Design or Open Implemented Design.
# Read-only diagnostic for the explicit 12-lane DSP48E1 array.
set mac_dsps [get_cells -hierarchical -filter {REF_NAME == DSP48E1}]
puts "DSP48E1 count: [llength $mac_dsps]"
if {[llength $mac_dsps] != 12} {
    error "Expected 12 DSP48E1 cells. Check top, source copies and synthesis log."
}
foreach mac_dsp $mac_dsps {
    puts "DSP: $mac_dsp"
    foreach mac_property {AREG BREG MREG PREG USE_MULT USE_SIMD} {
        puts "  $mac_property = [get_property $mac_property $mac_dsp]"
    }
    if {[get_property MREG $mac_dsp] != 1 || [get_property PREG $mac_dsp] != 1} {
        error "Unexpected MREG/PREG on $mac_dsp"
    }
}
report_utilization
# Also inspect synthesis DSP Final Report and schematic:
# expect A*B+P with MREG=1/PREG=1, not just A*B followed by fabric carry chains.
# PREG alone does not prove feedback accumulation; inspect the mapped operation.
