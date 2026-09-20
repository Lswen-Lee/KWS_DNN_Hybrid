`timescale 1ns/1ps
// Elaborated separately for PE8 and PE9. Constant generate removes the unused
// variant, including all PE8 parameter storage from the PE9 netlist.
(* use_dsp = "no" *)
module pe_compare_engine #(parameter bit PE8 = 0) (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [7:0] cmd_k,
    input logic [11:0] cmd_lane_mask,
    input logic in_valid,
    output logic in_ready,
    input logic [7:0] activation_u8,
    input logic [95:0] weights_flat,
    input logic cfg_valid,
    output logic cfg_ready,
    input logic [3:0] cfg_lane,
    input logic signed [31:0] cfg_weight_sum,
    output logic out_valid,
    input logic out_ready,
    output logic signed [31:0] result,
    output logic [3:0] lane_id,
    output logic out_last, out_overflow, busy, done
);
    logic clear, active, finished, config_ready;
    logic [11:0] mask;
    logic input_pending;
    logic [7:0] activation_q;
    logic [95:0] weights_q;
    logic [383:0] results;
    logic drain_valid, drain_ready, drain_last, drain_empty;
    logic signed [31:0] drain_data;
    logic [3:0] drain_lane;

    pe_compare_stream_controller control (
        .clk(clk), .rst(rst), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_k(cmd_k), .cmd_lane_mask(cmd_lane_mask), .config_ready(config_ready),
        .in_valid(in_valid), .in_ready(in_ready), .output_finished(finished),
        .clear(clear), .output_active(active), .busy(busy), .done(done), .lane_mask(mask)
    );
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            input_pending <= 0;
            activation_q <= 0;
            weights_q <= 0;
        end else begin
            input_pending <= in_valid && in_ready;
            if (in_valid && in_ready) begin
                activation_q <= activation_u8;
                weights_q <= weights_flat;
            end
        end
    end
    pe_compare_result_drain drain (
        .clk(clk), .rst(rst), .clear(clear), .active(active), .lane_mask(mask),
        .results(results), .valid(drain_valid), .ready(drain_ready),
        .data(drain_data), .lane(drain_lane), .last(drain_last), .empty(drain_empty)
    );
    assign finished = active && (drain_empty || (out_valid && out_ready && out_last));
    generate
        if (PE8) begin : g_pe8
            logic signed [7:0] a8;
            logic signed [31:0] weight_sums [0:11];
            logic [11:0] configured;
            logic last_q;
            assign a8 = $signed({~activation_q[7], activation_q[6:0]});
            assign config_ready = !cfg_valid && (configured & cmd_lane_mask) == cmd_lane_mask;
            // Configuration takes priority over command acceptance while idle.
            assign cfg_ready = !rst && !busy && cfg_lane < 12;
            always_ff @(posedge clk) begin
                if (rst) begin
                    configured <= 0;
                    for (integer i=0; i<12; i=i+1) weight_sums[i] <= 0;
                    last_q <= 0;
                end else begin
                    if (cfg_valid && cfg_ready) begin
                        weight_sums[cfg_lane] <= cfg_weight_sum;
                        configured[cfg_lane] <= 1;
                    end
                    if (cmd_valid && cmd_ready) configured <= 0;
                    if (drain_valid && drain_ready) last_q <= drain_last;
                end
            end
            pe8_array_12 array_core (
                .clk(clk), .rst(rst), .clear(clear), .accumulate_en(input_pending),
                .lane_mask(mask), .activation_s8(a8), .weight_vector_i8(weights_q),
                .result_vector_s32(results)
            );
            pe8_result_correction #(.CHANNEL_ID_WIDTH(4)) correction (
                .clk(clk), .rst(rst), .in_valid(drain_valid), .in_ready(drain_ready),
                .raw_accumulator(drain_data), .weight_sum(weight_sums[drain_lane]),
                .in_channel_id(drain_lane), .out_valid(out_valid), .out_ready(out_ready),
                .corrected_accumulator(result), .out_channel_id(lane_id), .out_overflow(out_overflow)
            );
            assign out_last = last_q;
        end else begin : g_pe9
            logic signed [8:0] a9;
            assign a9 = $signed({1'b0, activation_q}) - 9'sd127;
            assign config_ready = 1;
            assign cfg_ready = 0;
            pe_array_12 array_core (
                .clk(clk), .rst(rst), .clear(clear), .accumulate_en(input_pending),
                .lane_mask(mask), .activation_centered(a9), .weight_vector_i8(weights_q),
                .result_vector_s32(results)
            );
            assign out_valid = drain_valid;
            assign drain_ready = out_ready;
            assign result = drain_data;
            assign lane_id = drain_lane;
            assign out_last = drain_last;
            // K<=255 with these operand widths cannot overflow INT32.
            assign out_overflow = 0;
        end
    endgenerate
endmodule
