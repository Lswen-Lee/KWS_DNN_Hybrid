`timescale 1ns/1ps
// One channel per command. Only accepted weights count; no weight RAM here.
module pe_weight_sum_builder #(
    parameter integer CHANNEL_ID_WIDTH = 5
) (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [7:0] cmd_k,
    input logic [CHANNEL_ID_WIDTH-1:0] cmd_channel_id,
    input logic weight_valid,
    output logic weight_ready,
    input logic signed [7:0] weight_i8,
    output logic sum_valid,
    input logic sum_ready,
    output logic signed [31:0] weight_sum,
    output logic [CHANNEL_ID_WIDTH-1:0] sum_channel_id
);
    typedef enum logic [1:0] {IDLE, ACCUMULATE, RESULT} state_t;
    state_t state;
    logic [7:0] remaining;
    logic signed [31:0] sum_next;
    assign cmd_ready = !rst && state == IDLE && cmd_k != 0;
    assign weight_ready = !rst && state == ACCUMULATE;
    assign sum_valid = !rst && state == RESULT;
    assign sum_next = weight_sum + {{24{weight_i8[7]}}, weight_i8};
    // K<=255, INT8 weights: [-32640,32385], well within signed INT32.
    // weight_sum doubles as the work register; meaningful output only if valid.
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            remaining <= 0;
            weight_sum <= 0;
            sum_channel_id <= 0;
        end else begin
            case (state)
                IDLE: if (cmd_valid && cmd_ready) begin
                    remaining <= cmd_k;
                    sum_channel_id <= cmd_channel_id;
                    weight_sum <= 0;
                    state <= ACCUMULATE;
                end
                ACCUMULATE: if (weight_valid && weight_ready) begin
                    weight_sum <= sum_next;
                    remaining <= remaining - 1'b1;
                    if (remaining == 1) state <= RESULT;
                end
                RESULT: if (sum_valid && sum_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
