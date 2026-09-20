`timescale 1ns/1ps
// Channel-major stream W[channel][k]. Connect to a 12 x 512 byte buffer.
// SUM_ENABLE=0 removes the PE8-only sum builder for a PE9 implementation.
module pe_layer_weight_loader #(
    parameter bit SUM_ENABLE = 1'b1
) (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [7:0] cmd_k,
    input logic [5:0] cmd_channels,
    input logic weight_valid,
    output logic weight_ready,
    input logic signed [7:0] weight_i8,
    output logic wr_valid,
    input logic wr_ready,
    output logic [3:0] wr_lane,
    output logic [8:0] wr_addr,
    output logic [7:0] wr_data,
    output wire sum_valid,
    input logic sum_ready,
    output wire signed [31:0] weight_sum,
    output wire [4:0] sum_channel_id,
    output logic busy, layer_ready, done, error
);
    typedef enum logic [2:0] {IDLE, START_CHANNEL, LOAD_CHANNEL,
                             WAIT_SUM, NEXT_CHANNEL} state_t;
    state_t state;
    logic [7:0] k_reg, k_index;
    logic [5:0] channels_reg;
    logic [4:0] channel;
    logic [8:0] group_base;
    logic [9:0] required_depth;
    wire builder_cmd_ready, builder_weight_ready;
    wire builder_cmd_valid = !rst && state == START_CHANNEL;
    wire builder_weight_valid = !rst && state == LOAD_CHANNEL
                                && weight_valid && wr_ready;
    wire accepted = weight_valid && weight_ready;

    // Only three output groups are supported. Constant small additions,
    // no run-time division/modulo/multiplier on the address path.
    always_comb begin
        required_depth = {2'b0, cmd_k};
        if (cmd_channels > 12) required_depth = required_depth + {2'b0, cmd_k};
        if (cmd_channels > 24) required_depth = required_depth + {2'b0, cmd_k};
    end
    assign cmd_ready = !rst && state == IDLE;
    assign busy = state != IDLE;
    assign wr_valid = !rst && state == LOAD_CHANNEL && weight_valid
                      && builder_weight_ready;
    assign weight_ready = !rst && state == LOAD_CHANNEL && wr_ready
                          && builder_weight_ready;
    assign wr_addr = group_base + {1'b0, k_index};
    assign wr_data = weight_i8;

    generate if (SUM_ENABLE) begin : g_sum
        pe_weight_sum_builder builder (
            .clk(clk), .rst(rst), .cmd_valid(builder_cmd_valid),
            .cmd_ready(builder_cmd_ready), .cmd_k(k_reg),
            .cmd_channel_id(channel), .weight_valid(builder_weight_valid),
            .weight_ready(builder_weight_ready), .weight_i8(weight_i8),
            .sum_valid(sum_valid), .sum_ready(sum_ready),
            .weight_sum(weight_sum), .sum_channel_id(sum_channel_id)
        );
    end else begin : g_no_sum
        assign builder_cmd_ready = 1'b1;
        assign builder_weight_ready = 1'b1;
        assign sum_valid = 1'b0;
        assign weight_sum = 32'sd0;
        assign sum_channel_id = 5'd0;
    end endgenerate

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            k_reg <= 0; k_index <= 0; channels_reg <= 0;
            channel <= 0; wr_lane <= 0; group_base <= 0;
            layer_ready <= 0; done <= 0; error <= 0;
        end else begin
            done <= 0;
            error <= 0;
            case (state)
                IDLE: if (cmd_valid && cmd_ready) begin
                    layer_ready <= 0;
                    if (cmd_k == 0 || cmd_channels == 0 || cmd_channels > 32
                        || required_depth > 512) begin
                        error <= 1;
                    end else begin
                        k_reg <= cmd_k;
                        channels_reg <= cmd_channels;
                        channel <= 0; wr_lane <= 0; group_base <= 0;
                        k_index <= 0;
                        state <= START_CHANNEL;
                    end
                end
                START_CHANNEL: if (builder_cmd_ready) state <= LOAD_CHANNEL;
                LOAD_CHANNEL: if (accepted) begin
                    if (k_index == k_reg - 1'b1) begin
                        k_index <= 0;
                        if (SUM_ENABLE) state <= WAIT_SUM;
                        else state <= NEXT_CHANNEL;
                    end else k_index <= k_index + 1'b1;
                end
                WAIT_SUM: if (sum_valid && sum_ready) state <= NEXT_CHANNEL;
                NEXT_CHANNEL: begin
                    if ({1'b0, channel} + 6'd1 == channels_reg) begin
                        layer_ready <= 1;
                        done <= 1;
                        state <= IDLE;
                    end else begin
                        channel <= channel + 1'b1;
                        if (wr_lane == 11) begin
                            wr_lane <= 0;
                            group_base <= group_base + {1'b0, k_reg};
                        end else wr_lane <= wr_lane + 1'b1;
                        state <= START_CHANNEL;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
