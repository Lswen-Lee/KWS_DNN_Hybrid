`timescale 1ns/1ps
// PE8 result pipeline: synchronous sum response -> elastic correction -> out.
// Hold raw_results/channel_base/active_lanes through group_result_done.
// Exclusive, ordered sum-memory read port; reset controller and memory together.
module pe8_result_controller_pipeline (
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
    typedef enum logic [1:0] {IDLE, STREAM, DRAIN} state_t;
    state_t state;
    logic [3:0] issue_lane, response_lane;
    logic response_pending, output_fault;
    wire [5:0] channel_end = {1'b0, channel_base} + {2'b0, active_lanes};
    wire descriptor_ok = active_lanes >= 1 && active_lanes <= 12 && channel_end <= 32;
    wire running = state == STREAM || state == DRAIN;
    wire [4:0] expected_channel = channel_base + {1'b0, response_lane};
    wire response_fault = sum_out_error || sum_out_channel_id != expected_channel;
    wire signed [31:0] selected_raw = $signed(raw_results[int'(response_lane)*32 +: 32]);
    wire correction_ready, correction_valid, correction_overflow;
    wire correction_input_valid = !rst && running && response_pending && sum_out_valid;
    wire request_fire = sum_rd_valid && sum_rd_ready;
    wire response_fire = correction_input_valid && correction_ready;
    wire output_fire = out_valid && out_ready;

    assign result_start_ready = !rst && state == IDLE && descriptor_ok;
    assign busy = state != IDLE;
    // At most one sum response is outstanding. The consumed response tag can
    // be replaced on the SAME edge as the next memory request is accepted.
    assign sum_rd_valid = !rst && state == STREAM && (!response_pending || response_fire);
    assign sum_rd_channel_id = channel_base + {1'b0, issue_lane};
    assign sum_out_ready = !rst && running && response_pending && correction_ready;
    assign out_valid = !rst && running && correction_valid;
    assign out_last = {1'b0, out_channel_id} == channel_end - 6'd1;
    assign out_error = output_fault || correction_overflow;

    // Faults pass through the SAME stage as good results (zero data + flag),
    // so an error cannot bypass or overtake an older stalled result.
    pe8_result_correction correction (
        .clk(clk), .rst(rst), .in_valid(correction_input_valid), .in_ready(correction_ready),
        .raw_accumulator(response_fault ? 32'sd0 : selected_raw),
        .weight_sum(response_fault ? 32'sd0 : sum_out_data),
        .in_channel_id(expected_channel), .out_valid(correction_valid),
        .out_ready(!rst && running && out_ready), .corrected_accumulator(out_data),
        .out_channel_id(out_channel_id), .out_overflow(correction_overflow)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            issue_lane <= 0;
            response_lane <= 0;
            response_pending <= 0;
            output_fault <= 0;
            group_result_done <= 0;
        end else begin
            group_result_done <= 0;
            // Same enable as correction's output register replacement.
            if (correction_ready)
                output_fault <= correction_input_valid && response_fault;
            if (request_fire) begin
                response_pending <= 1;
                response_lane <= issue_lane;
            end else if (response_fire) response_pending <= 0;
            case (state)
                IDLE: if (result_start_valid && result_start_ready) begin
                    issue_lane <= 0;
                    response_pending <= 0;
                    state <= STREAM;
                end
                STREAM: if (request_fire) begin
                    if (issue_lane == active_lanes - 4'd1) state <= DRAIN;
                    else issue_lane <= issue_lane + 4'd1;
                end
                DRAIN: if (output_fire && out_last) begin
                    state <= IDLE;
                    group_result_done <= 1;
                end
                default: begin state <= IDLE; response_pending <= 0; end
            endcase
        end
    end
endmodule
