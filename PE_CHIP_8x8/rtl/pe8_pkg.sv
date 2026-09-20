`timescale 1ns/1ps
// Fixed 12-lane contract, not a promise of arbitrary arithmetic resizing.
package pe8_pkg;
    localparam int LANE_COUNT=12;
    // Model zero-point and MAC re-encoding offset are different concepts.
    // Public core-side metadata, intentionally unused by the raw array.
    /* verilator lint_off UNUSEDPARAM */
    localparam int ACT_U8_WIDTH=8;
    localparam int ACT_ZERO_POINT=127;
    localparam int ACT_RECODE_OFFSET=128;
    /* verilator lint_on UNUSEDPARAM */
    localparam int ACT_WIDTH=8;
    localparam int WEIGHT_WIDTH=8;
    localparam int PRODUCT_WIDTH=16;
    localparam int ACC_WIDTH=32;
    localparam int WEIGHT_VECTOR_WIDTH=LANE_COUNT*WEIGHT_WIDTH;
    localparam int RESULT_VECTOR_WIDTH=LANE_COUNT*ACC_WIDTH;
    typedef logic signed [ACT_WIDTH-1:0] activation_t;
    typedef logic signed [WEIGHT_WIDTH-1:0] weight_t;
    typedef logic signed [PRODUCT_WIDTH-1:0] product_t;
    typedef logic signed [ACC_WIDTH-1:0] accumulator_t;
endpackage

