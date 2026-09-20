`timescale 1ns/1ps

// Two-to-four decoder for selecting one 32-row DCIM group.
//
// The presentation connects address pins A6/A5 to this decoder.  Therefore
// group_addr is ordered as {A6, A5}, and the four outputs map the complete
// 128-row array as follows:
//   2'b00 -> cim_row[0] -> global rows   0..31
//   2'b01 -> cim_row[1] -> global rows  32..63
//   2'b10 -> cim_row[2] -> global rows  64..95
//   2'b11 -> cim_row[3] -> global rows 96..127
//
// cim_en is intentionally not part of this address decoder.  The downstream
// input-control equation gates computation with cim_en, cim_row and the
// activation bit, matching the separate blocks shown in the presentation.
module cim_group_decoder_2to4 (
    input  logic [1:0] group_addr,
    output logic [3:0] cim_row
);

    // Explicit equations make the active-high one-hot mapping visible.
    assign cim_row[0] = ~group_addr[1] & ~group_addr[0];
    assign cim_row[1] = ~group_addr[1] &  group_addr[0];
    assign cim_row[2] =  group_addr[1] & ~group_addr[0];
    assign cim_row[3] =  group_addr[1] &  group_addr[0];

endmodule
