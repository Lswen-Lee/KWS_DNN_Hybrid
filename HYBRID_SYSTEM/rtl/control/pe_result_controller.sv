`timescale 1ns/1ps
// One lane at a time; raw_results, channel_base and active_lanes MUST remain
// stable from start handshake through group_result_done. No result copy RAM.
// PE8_MODE is elaboration-time selection, NOT a run-time mode input.
module pe_result_controller #(
    parameter bit PE8_MODE = 1'b1
) (
    input logic clk, rst,
    input logic result_start_valid,
    output logic result_start_ready,
    input logic [4:0] channel_base,
    input logic [3:0] active_lanes,
    input logic [383:0] raw_results,
    output logic busy, group_result_done,
    output logic sum_rd_valid,
    input logic sum_rd_ready,
    output logic [4:0] sum_rd_channel_id,
    input logic sum_out_valid,
    output logic sum_out_ready,
    input logic [4:0] sum_out_channel_id,
    input logic signed [31:0] sum_out_data,
    input logic sum_out_error,
    output logic out_valid,
    input logic out_ready,
    output logic signed [31:0] out_data,
    output logic [4:0] out_channel_id,
    output logic out_last, out_error
);
    typedef enum logic [1:0] {IDLE, READ_SUM, FEED_CORRECTION, EMIT} state_t;
    state_t state;
    logic [3:0] lane_index;
    wire signed [31:0] selected_raw = $signed(raw_results[int'(lane_index)*32 +: 32]);
    wire [5:0] channel_end = {1'b0, channel_base} + {2'b0, active_lanes};
    wire descriptor_ok = active_lanes >= 1 && active_lanes <= 12 && channel_end <= 32;
    wire [4:0] selected_channel = channel_base + {1'b0, lane_index};
    wire output_fire = out_valid && out_ready;
    assign result_start_ready = !rst && state == IDLE && descriptor_ok;
    assign busy = state != IDLE;
    assign out_channel_id = selected_channel;
    assign out_last = lane_index == active_lanes - 4'd1;

    generate if (PE8_MODE) begin : g_pe8
        logic error_pending;
        logic correction_ready, correction_valid, correction_overflow;
        logic signed [31:0] correction_data;
        // Channel derives from stable group metadata; no duplicate tag FF needed.
        wire [4:0] unused_corrected_channel;
        wire response_error = sum_out_error || sum_out_channel_id != selected_channel;
        wire correction_input_valid = !rst && state == FEED_CORRECTION &&
                                      sum_out_valid && !response_error;
        assign sum_rd_valid = !rst && state == READ_SUM;
        assign sum_rd_channel_id = selected_channel;
        assign sum_out_ready = !rst && state == FEED_CORRECTION &&
                               (response_error || correction_ready);
        pe8_result_correction correction (
            .clk(clk), .rst(rst), .in_valid(correction_input_valid), .in_ready(correction_ready),
            .raw_accumulator(selected_raw), .weight_sum(sum_out_data), .in_channel_id(selected_channel),
            .out_valid(correction_valid),
            .out_ready(!rst && state == EMIT && !error_pending && out_ready),
            .corrected_accumulator(correction_data), .out_channel_id(unused_corrected_channel), .out_overflow(correction_overflow)
        );
        assign out_valid = !rst && state == EMIT && (error_pending || correction_valid);
        assign out_data = error_pending ? 32'sd0 : correction_data;
        assign out_error = error_pending || correction_overflow;
        always_ff @(posedge clk) begin
            if (rst) begin
                state <= IDLE; lane_index <= 0; error_pending <= 0; group_result_done <= 0;
            end else begin
                group_result_done <= 0;
                case (state)
                    IDLE: if (result_start_valid && result_start_ready) begin
                        lane_index <= 0; error_pending <= 0; state <= READ_SUM;
                    end
                    READ_SUM: if (sum_rd_valid && sum_rd_ready) state <= FEED_CORRECTION;
                    FEED_CORRECTION: if (sum_out_valid && sum_out_ready) begin
                        error_pending <= response_error;
                        state <= EMIT;
                    end
                    EMIT: if (output_fire) begin
                        error_pending <= 0;
                        if (out_last) begin state <= IDLE; group_result_done <= 1; end
                        else begin lane_index <= lane_index + 4'd1; state <= READ_SUM; end
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end else begin : g_pe9
        // No sum reads, correction instance, arithmetic adder, or data FF here.
        assign sum_rd_valid = 1'b0;
        assign sum_rd_channel_id = 5'd0;
        assign sum_out_ready = 1'b0;
        assign out_valid = !rst && state == EMIT;
        assign out_data = selected_raw;
        assign out_error = 1'b0;
        always_ff @(posedge clk) begin
            if (rst) begin state <= IDLE; lane_index <= 0; group_result_done <= 0; end
            else begin
                group_result_done <= 0;
                case (state)
                    IDLE: if (result_start_valid && result_start_ready) begin
                        lane_index <= 0; state <= EMIT;
                    end
                    EMIT: if (output_fire) begin
                        if (out_last) begin state <= IDLE; group_result_done <= 1; end
                        else lane_index <= lane_index + 4'd1;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end endgenerate
endmodule
