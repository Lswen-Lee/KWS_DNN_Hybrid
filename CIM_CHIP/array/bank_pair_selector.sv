`timescale 1ns/1ps

// Routes one selected 8-bit bank pair to either the CIM path or the SRAM
// read/write path.
//
// The 128 columns are implemented as thirty-two 32x4 segments.  Adjacent
// segments form one pair, so pair p controls physical segments 2*p (even)
// and 2*p+1 (odd).  bank_select is supplied by bank_decoder_4to16 and is
// expected to be active-high one-hot during a normal access.
//
// The presentation defines mode_sel=1 as CIM mode.  Its column-control
// schematic places a one-to-two demultiplexer after each of the sixteen
// decoder outputs.  The equations below implement those sixteen demuxes:
//
//   cim_pair_en[p]  = bank_select[p] &  mode_sel
//   sram_pair_en[p] = bank_select[p] & ~mode_sel
//
// This block only selects and routes a pair.  The even and odd 4-bit DCIM
// partial sums remain independent and are accumulated separately.  If the
// two segments are mapped as one 8-bit weight, downstream logic combines
// them as low_acc + (high_acc << 4).
module bank_pair_selector (
    input  logic [15:0] bank_select,
    input  logic        mode_sel,
    output logic [15:0] cim_pair_en,
    output logic [15:0] sram_pair_en
);

    assign cim_pair_en  = bank_select & {16{ mode_sel}};
    assign sram_pair_en = bank_select & {16{~mode_sel}};

endmodule
