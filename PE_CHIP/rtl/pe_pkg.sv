`timescale 1ns/1ps

// Fixed 12-lane original PE contract. Compile before pe_array_12.sv.
// Changing these constants alone does not resize existing arithmetic modules.
package pe_pkg;
    localparam int LANE_COUNT = 12;
    // Public input contract for the future core; array takes centered data.
    // These two constants are intentionally unused when linting array alone.
    /* verilator lint_off UNUSEDPARAM */
    localparam int ACT_U8_WIDTH = 8;
    localparam int ACT_ZERO_POINT = 127;
    /* verilator lint_on UNUSEDPARAM */
    localparam int ACT_CENTERED_WIDTH = 9;
    localparam int WEIGHT_WIDTH = 8;
    localparam int PRODUCT_WIDTH = 17;
    localparam int ACC_WIDTH = 32;
    localparam int WEIGHT_VECTOR_WIDTH = LANE_COUNT * WEIGHT_WIDTH;
    localparam int RESULT_VECTOR_WIDTH = LANE_COUNT * ACC_WIDTH;

    typedef logic signed [ACT_CENTERED_WIDTH-1:0] activation_t;
    typedef logic signed [WEIGHT_WIDTH-1:0] weight_t;
    typedef logic signed [PRODUCT_WIDTH-1:0] product_t;
    typedef logic signed [ACC_WIDTH-1:0] accumulator_t;
endpackage
