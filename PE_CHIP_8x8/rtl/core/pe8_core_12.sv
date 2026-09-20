`timescale 1ns/1ps
// Raw dot product core: sum((UINT8_A-128)*signed8_W), NOT zp127-corrected.
// One input register plus one product register; final accept needs two drain edges.
// start must pulse only when idle. K=0 is ignored (no done/error transaction).
(* use_dsp = "no" *)
module pe8_core_12 (
    input logic clk, rst, start,
    input logic [7:0] k_length,
    input logic [11:0] lane_mask,
    output logic busy, done,
    input logic sample_valid,
    output logic sample_ready,
    input logic [7:0] activation_u8,
    input logic [95:0] weight_vector_i8,
    output logic result_valid,
    input logic result_ready,
    output logic [383:0] result_vector_s32
);
    logic array_clear, sample_accept, input_valid;
    logic [11:0] lane_mask_reg;
    logic signed [7:0] activation_s8, activation_reg;
    logic [95:0] weights_reg;

    pe8_core_controller controller (
        .clk(clk), .rst(rst), .start(start), .k_length(k_length),
        .lane_mask(lane_mask), .sample_valid(sample_valid),
        .result_ready(result_ready), .busy(busy), .done(done),
        .sample_ready(sample_ready), .result_valid(result_valid),
        .array_clear(array_clear), .sample_accept(sample_accept),
        .input_valid(input_valid), .lane_mask_reg(lane_mask_reg)
    );
    activation_u8_to_s8 recode (
        .activation_u8(activation_u8), .activation_s8(activation_s8)
    );
    always_ff @(posedge clk) begin
        if (rst || array_clear) begin
            activation_reg <= 0;
            weights_reg <= 0;
        end else if (sample_accept) begin
            activation_reg <= activation_s8;
            weights_reg <= weight_vector_i8;
        end
    end
    pe8_array_12 array_unit (
        .clk(clk), .rst(rst), .clear(array_clear),
        .accumulate_en(input_valid), .lane_mask(lane_mask_reg),
        .activation_s8(activation_reg), .weight_vector_i8(weights_reg),
        .result_vector_s32(result_vector_s32)
    );
endmodule
