`timescale 1ns/1ps

// Balanced adder tree for one 32-row x 4-column DCIM segment.
//
// Each input is the unsigned 4-bit product from one dcim_row_4bit.  The tree
// adds all 32 rows in five combinational levels.  The maximum result is
// 32 * 15 = 480, so the final output is nine bits wide.
module adder_tree_32x4 (
    // The explicit net kind keeps the unpacked-array input compatible with
    // Vivado 2023.2 while preserving the four-state SystemVerilog data type.
    input  wire logic [3:0] row_product [0:31],
    output logic [8:0] bank_sum
);

    // Level 1: 32 four-bit values become 16 five-bit sums.
    logic [4:0] level1_sum [0:15];

    assign level1_sum[0]  = {1'b0, row_product[0]}  + {1'b0, row_product[1]};
    assign level1_sum[1]  = {1'b0, row_product[2]}  + {1'b0, row_product[3]};
    assign level1_sum[2]  = {1'b0, row_product[4]}  + {1'b0, row_product[5]};
    assign level1_sum[3]  = {1'b0, row_product[6]}  + {1'b0, row_product[7]};
    assign level1_sum[4]  = {1'b0, row_product[8]}  + {1'b0, row_product[9]};
    assign level1_sum[5]  = {1'b0, row_product[10]} + {1'b0, row_product[11]};
    assign level1_sum[6]  = {1'b0, row_product[12]} + {1'b0, row_product[13]};
    assign level1_sum[7]  = {1'b0, row_product[14]} + {1'b0, row_product[15]};
    assign level1_sum[8]  = {1'b0, row_product[16]} + {1'b0, row_product[17]};
    assign level1_sum[9]  = {1'b0, row_product[18]} + {1'b0, row_product[19]};
    assign level1_sum[10] = {1'b0, row_product[20]} + {1'b0, row_product[21]};
    assign level1_sum[11] = {1'b0, row_product[22]} + {1'b0, row_product[23]};
    assign level1_sum[12] = {1'b0, row_product[24]} + {1'b0, row_product[25]};
    assign level1_sum[13] = {1'b0, row_product[26]} + {1'b0, row_product[27]};
    assign level1_sum[14] = {1'b0, row_product[28]} + {1'b0, row_product[29]};
    assign level1_sum[15] = {1'b0, row_product[30]} + {1'b0, row_product[31]};

    // Level 2: 16 five-bit values become eight six-bit sums.
    logic [5:0] level2_sum [0:7];

    assign level2_sum[0] = {1'b0, level1_sum[0]}  + {1'b0, level1_sum[1]};
    assign level2_sum[1] = {1'b0, level1_sum[2]}  + {1'b0, level1_sum[3]};
    assign level2_sum[2] = {1'b0, level1_sum[4]}  + {1'b0, level1_sum[5]};
    assign level2_sum[3] = {1'b0, level1_sum[6]}  + {1'b0, level1_sum[7]};
    assign level2_sum[4] = {1'b0, level1_sum[8]}  + {1'b0, level1_sum[9]};
    assign level2_sum[5] = {1'b0, level1_sum[10]} + {1'b0, level1_sum[11]};
    assign level2_sum[6] = {1'b0, level1_sum[12]} + {1'b0, level1_sum[13]};
    assign level2_sum[7] = {1'b0, level1_sum[14]} + {1'b0, level1_sum[15]};

    // Level 3: eight six-bit values become four seven-bit sums.
    logic [6:0] level3_sum [0:3];

    assign level3_sum[0] = {1'b0, level2_sum[0]} + {1'b0, level2_sum[1]};
    assign level3_sum[1] = {1'b0, level2_sum[2]} + {1'b0, level2_sum[3]};
    assign level3_sum[2] = {1'b0, level2_sum[4]} + {1'b0, level2_sum[5]};
    assign level3_sum[3] = {1'b0, level2_sum[6]} + {1'b0, level2_sum[7]};

    // Level 4: four seven-bit values become two eight-bit sums.
    logic [7:0] level4_sum [0:1];

    assign level4_sum[0] = {1'b0, level3_sum[0]} + {1'b0, level3_sum[1]};
    assign level4_sum[1] = {1'b0, level3_sum[2]} + {1'b0, level3_sum[3]};

    // Level 5: the final two values become the nine-bit bank result.
    assign bank_sum = {1'b0, level4_sum[0]} + {1'b0, level4_sum[1]};

endmodule
