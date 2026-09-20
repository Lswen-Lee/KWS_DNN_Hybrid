`timescale 1ns/1ps
// Common scheduler: input register -> product register -> accumulator.
module pe_compare_stream_controller (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [7:0] cmd_k,
    input logic [11:0] cmd_lane_mask,
    input logic config_ready,
    input logic in_valid,
    output logic in_ready,
    input logic output_finished,
    output logic clear, output_active, busy, done,
    output logic [11:0] lane_mask
);
    typedef enum logic [2:0] {IDLE, CLEAR, RUN, DRAIN_INPUT,
                             DRAIN_PRODUCT, OUTPUT} state_t;
    state_t state;
    logic [7:0] remaining;
    assign cmd_ready = !rst && state == IDLE && cmd_k != 0 && config_ready;
    assign in_ready = !rst && state == RUN;
    assign clear = state == CLEAR;
    assign output_active = !rst && state == OUTPUT;
    assign busy = state != IDLE;
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            remaining <= 0;
            lane_mask <= 0;
            done <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (cmd_valid && cmd_ready) begin
                    remaining <= cmd_k;
                    lane_mask <= cmd_lane_mask;
                    state <= CLEAR;
                end
                CLEAR: state <= RUN;
                RUN: if (in_valid && in_ready) begin
                    remaining <= remaining - 1'b1;
                    if (remaining == 1) state <= DRAIN_INPUT;
                end
                DRAIN_INPUT: state <= DRAIN_PRODUCT;
                DRAIN_PRODUCT: state <= OUTPUT;
                OUTPUT: if (output_finished) begin
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
