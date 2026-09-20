`timescale 1ns/1ps
module pe8_core_controller (
    input logic clk, rst,
    input logic start,
    input logic [7:0] k_length,
    input logic [11:0] lane_mask,
    input logic sample_valid, result_ready,
    output logic busy, done, sample_ready, result_valid,
    output logic array_clear, sample_accept, input_valid,
    output logic [11:0] lane_mask_reg
);
    typedef enum logic [2:0] {IDLE, CLEAR, RUN, DRAIN, RESULT} state_t;
    state_t state;
    logic [7:0] k_reg, accepted_count;
    logic product_pending;

    assign busy = (state != IDLE);
    assign array_clear = (state == CLEAR);
    assign sample_ready = !rst && (state == RUN);
    assign sample_accept = sample_valid && sample_ready;
    assign result_valid = !rst && (state == RESULT);

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            k_reg <= 0;
            accepted_count <= 0;
            lane_mask_reg <= 0;
            input_valid <= 0;
            product_pending <= 0;
            done <= 0;
        end else begin
            done <= 0;
            // Track the exact core input register -> lane product register path.
            input_valid <= sample_accept;
            product_pending <= input_valid;
            case (state)
                IDLE: begin
                    if (start && k_length != 0) begin
                        k_reg <= k_length;
                        lane_mask_reg <= lane_mask;
                        state <= CLEAR;
                    end
                end
                CLEAR: begin
                    accepted_count <= 0;
                    input_valid <= 0;
                    product_pending <= 0;
                    state <= RUN;
                end
                RUN: begin
                    if (sample_accept) begin
                        accepted_count <= accepted_count + 1'b1;
                        if (accepted_count == k_reg - 8'd1) state <= DRAIN;
                    end
                end
                DRAIN: begin
                    // On this edge, each enabled lane commits its last product.
                    if (product_pending && !input_valid) state <= RESULT;
                end
                RESULT: begin
                    if (result_ready) begin
                        done <= 1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
