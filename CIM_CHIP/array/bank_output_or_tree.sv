`timescale 1ns/1ps

// Selects the active even/odd 32x4 segment results with two parallel,
// two-stage OR trees.
//
// Each pair slot p contains two physical segments:
//   even_bank_sum[p] comes from segment 2*p
//   odd_bank_sum[p]  comes from segment 2*p+1
//
// Normal operation enables only one pair, so all unselected segment sums are
// zero.  The presentation therefore uses OR gates instead of data muxes and
// states that only the chosen bank affects the output.  Sixteen pair slots
// are reduced as four OR4 groups followed by one final OR4.  Every operation
// below is a bitwise OR on a complete unsigned nine-bit partial sum.
module bank_output_or_tree (
    // Explicit net kinds keep unpacked-array inputs compatible with
    // Vivado 2023.2.
    input  wire logic [8:0] even_bank_sum [0:15],
    input  wire logic [8:0] odd_bank_sum  [0:15],
    output logic [8:0] selected_even_sum,
    output logic [8:0] selected_odd_sum
);

    logic [8:0] even_stage1 [0:3];
    logic [8:0] odd_stage1  [0:3];

    // Stage 1: four groups of four even-segment outputs.
    assign even_stage1[0] = even_bank_sum[0]  | even_bank_sum[1]  |
                            even_bank_sum[2]  | even_bank_sum[3];
    assign even_stage1[1] = even_bank_sum[4]  | even_bank_sum[5]  |
                            even_bank_sum[6]  | even_bank_sum[7];
    assign even_stage1[2] = even_bank_sum[8]  | even_bank_sum[9]  |
                            even_bank_sum[10] | even_bank_sum[11];
    assign even_stage1[3] = even_bank_sum[12] | even_bank_sum[13] |
                            even_bank_sum[14] | even_bank_sum[15];

    // Stage 1: the matching four groups of odd-segment outputs.
    assign odd_stage1[0] = odd_bank_sum[0]  | odd_bank_sum[1]  |
                           odd_bank_sum[2]  | odd_bank_sum[3];
    assign odd_stage1[1] = odd_bank_sum[4]  | odd_bank_sum[5]  |
                           odd_bank_sum[6]  | odd_bank_sum[7];
    assign odd_stage1[2] = odd_bank_sum[8]  | odd_bank_sum[9]  |
                           odd_bank_sum[10] | odd_bank_sum[11];
    assign odd_stage1[3] = odd_bank_sum[12] | odd_bank_sum[13] |
                           odd_bank_sum[14] | odd_bank_sum[15];

    // Stage 2: one final OR4 for each independent accumulator path.
    assign selected_even_sum = even_stage1[0] | even_stage1[1] |
                               even_stage1[2] | even_stage1[3];
    assign selected_odd_sum  = odd_stage1[0] | odd_stage1[1] |
                               odd_stage1[2] | odd_stage1[3];

endmodule
