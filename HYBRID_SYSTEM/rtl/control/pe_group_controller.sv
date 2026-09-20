`timescale 1ns/1ps
// One activation vector/patch per command, all output channels in groups of 12.
// Contract: input adapter (optionally with elastic operand FF) -> conversion -> PE.
// align_out_* MUST describe the final adapter output consumed by the PE.
// Each PE accepts a product at N and commits it at N+1 (no extra input FF).
module pe_group_controller (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [7:0] cmd_k,
    input logic [5:0] cmd_channels,
    input logic layer_ready,
    output logic busy, done, error,

    output logic replay_valid,
    input logic replay_ready,
    output logic [7:0] replay_k,
    output logic [4:0] channel_base,
    output logic [3:0] active_lanes,
    output logic [11:0] lane_mask,

    // Activation DATA bypasses this controller, directly into read-align.
    input logic activation_valid,
    output logic activation_ready,
    output logic align_in_valid,
    input logic align_in_ready,
    output logic [8:0] align_weight_addr,
    output logic align_in_last,
    input logic align_out_valid, align_out_last,
    output logic align_out_ready,
    output logic pe_clear, pe_accumulate_en,

    output logic result_start_valid,
    input logic result_start_ready,
    // Pulse AFTER start handshake, when the final external result is consumed.
    input logic group_result_done
);
    typedef enum logic [3:0] {
        IDLE, CLEAR, REPLAY, RUN, WAIT_LAST, DRAIN_MAC,
        START_RESULT, WAIT_RESULT, NEXT_GROUP
    } state_t;
    state_t state;
    logic [7:0] k_reg, issue_count;
    logic [5:0] remaining_channels;
    logic [8:0] group_weight_base;
    logic [9:0] required_depth;
    wire issue_fire = align_in_valid && align_in_ready;
    wire last_mac_fire = pe_accumulate_en && align_out_last;

    always_comb begin
        required_depth = {2'b0, cmd_k};
        if (cmd_channels > 12) required_depth = required_depth + {2'b0, cmd_k};
        if (cmd_channels > 24) required_depth = required_depth + {2'b0, cmd_k};
    end
    assign cmd_ready = !rst && state == IDLE && layer_ready;
    assign busy = state != IDLE;
    assign replay_valid = !rst && state == REPLAY;
    assign replay_k = k_reg;
    assign active_lanes = remaining_channels >= 12 ? 4'd12 : remaining_channels[3:0];
    assign lane_mask = 12'hfff >> (4'd12 - active_lanes);
    assign activation_ready = !rst && state == RUN && align_in_ready;
    assign align_in_valid = !rst && state == RUN && activation_valid;
    assign align_weight_addr = group_weight_base + {1'b0, issue_count};
    assign align_in_last = issue_count == k_reg - 8'd1;
    assign align_out_ready = !rst && (state == RUN || state == WAIT_LAST);
    assign pe_clear = !rst && state == CLEAR;
    assign pe_accumulate_en = align_out_valid && align_out_ready;
    assign result_start_valid = !rst && state == START_RESULT;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            k_reg <= 0; issue_count <= 0; remaining_channels <= 0;
            channel_base <= 0; group_weight_base <= 0;
            done <= 0; error <= 0;
        end else begin
            done <= 0;
            error <= 0;
            case (state)
                IDLE: if (cmd_valid && cmd_ready) begin
                    if (cmd_k == 0 || cmd_channels == 0 || cmd_channels > 32 ||
                        required_depth > 512) error <= 1;
                    else begin
                        k_reg <= cmd_k;
                        remaining_channels <= cmd_channels;
                        channel_base <= 0;
                        group_weight_base <= 0;
                        state <= CLEAR;
                    end
                end
                CLEAR: begin
                    issue_count <= 0;
                    state <= REPLAY;
                end
                REPLAY: if (replay_valid && replay_ready) state <= RUN;
                RUN: if (issue_fire) begin
                    if (issue_count == k_reg - 8'd1) state <= WAIT_LAST;
                    else issue_count <= issue_count + 8'd1;
                end
                WAIT_LAST: if (last_mac_fire) state <= DRAIN_MAC;
                // Last product commits on this edge. Results valid AFTER it.
                DRAIN_MAC: state <= START_RESULT;
                START_RESULT: if (result_start_valid && result_start_ready)
                    state <= WAIT_RESULT;
                WAIT_RESULT: if (group_result_done) begin
                    if (remaining_channels <= 12) begin
                        done <= 1;
                        state <= IDLE;
                    end else state <= NEXT_GROUP;
                end
                NEXT_GROUP: begin
                    remaining_channels <= remaining_channels - 6'd12;
                    channel_base <= channel_base + 5'd12;
                    group_weight_base <= group_weight_base + {1'b0, k_reg};
                    state <= CLEAR;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
