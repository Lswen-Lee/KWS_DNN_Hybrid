`timescale 1ns/1ps

// SRAM-side output of the shared slide-3 Input Path.
//
// This block deliberately contains no additional flip-flop.  The first two
// DFF stages already shown in the presentation are the eight storage bits:
//
//   first load clock  -> stage 0
//   second load clock -> new nibble in stage 0, old nibble moves to stage 1
//
// Consequently, after high-nibble-first loading, stage 1 is write_data[7:4]
// and stage 0 is write_data[3:0].  This also reproduces the slide-12 example
// in which input nibbles 9 then 1 form SRAM write word 8'h91.
//
// sram_path_en represents the two cascaded demultiplexer decisions:
// sel_next selects the stored tap, and mode_sel=0 selects the SRAM branch.
module sram_write_buffer_8bit (
    input  logic       sram_path_en,
    input  logic [3:0] stage0_bits,
    input  logic [3:0] stage1_bits,
    output logic [7:0] write_data
);

    // Zero while unselected models the inactive demultiplexer output and lets
    // downstream write_en remain the sole command that changes an SRAM cell.
    assign write_data = sram_path_en ?
                        {stage1_bits, stage0_bits} : 8'b0000_0000;

endmodule
