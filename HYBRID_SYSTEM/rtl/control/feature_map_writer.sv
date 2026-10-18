`timescale 1ns/1ps
// Exclusive writer for activation_buffer's always-accepting local RAM port.
// Five-stage pipeline: input -> products -> partial sums -> address -> pending.
// An input accepted at E0 commits at E5. RAM must always accept writes.
module feature_map_writer (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input kws_system_pkg::activation_write_mode_t cmd_mode,
    input kws_system_pkg::activation_addr_t cmd_base,
    input logic [7:0] cmd_width, cmd_height,
    input logic [5:0] cmd_channels,
    input kws_system_pkg::activation_count_t cmd_count,
    input logic in_valid,
    output logic in_ready,
    input kws_system_pkg::activation_t in_data,
    input logic [5:0] in_channel,
    input logic [7:0] in_y, in_x,
    output logic wr_en,
    output kws_system_pkg::activation_addr_t wr_addr,
    output kws_system_pkg::activation_t wr_data,
    output logic busy, done, error
);
    import kws_system_pkg::*;
    typedef enum logic [1:0] {IDLE, CONFIG, RECEIVE, DRAIN} state_t;
    state_t state;
    logic [1:0] config_phase;
    activation_write_mode_t mode_q;
    activation_addr_t base_q;
    logic [7:0] width_q, height_q;
    logic [5:0] channels_q;
    activation_count_t count_q, expected_count, accepted_count, committed_count;
    logic [15:0] plane_stride;
    logic [31:0] total_wide, end_exclusive;
    logic pending_valid, failed;
    logic [3:0] pipe_valid;
    activation_t data_s0, data_s1, data_s2, data_s3;
    logic [5:0] channel_s0;
    logic [7:0] y_s0, x_s0;
    activation_count_t index_s0;
    logic [31:0] channel_offset_s1, row_offset_s1, x_s1;
    logic [31:0] sum_a_s2, sum_b_s2, address_s3;
    logic coordinate_ok_s1, coordinate_ok_s2, coordinate_ok_s3;
    wire input_fire = in_valid && in_ready;
    wire pipeline_empty = !(|pipe_valid) && !pending_valid;
    wire payload_bad = pipe_valid[3] &&
                       (!coordinate_ok_s3 || address_s3 >= 32'(ACT_DEPTH));

    assign cmd_ready = !rst && state == IDLE;
    assign busy = state != IDLE;
    assign in_ready = !rst && state == RECEIVE;
    assign wr_en = !rst && pending_valid;
    // All arithmetic remains wide until configuration/coordinate validation.
    assign end_exclusive = {17'd0, base_q} + total_wide;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            config_phase <= 0;
            mode_q <= WRITE_LINEAR;
            base_q <= 0; width_q <= 0; height_q <= 0; channels_q <= 0;
            count_q <= 0; expected_count <= 0;
            accepted_count <= 0; committed_count <= 0;
            plane_stride <= 0; total_wide <= 0;
            pending_valid <= 0; failed <= 0;
            pipe_valid <= 0;
            done <= 0; error <= 0;
            // Payload registers need no reset: wr_en qualifies them.
        end else begin
            done <= 0;
            error <= 0;
            pending_valid <= 0;
            pipe_valid <= {pipe_valid[2:0], input_fire};
            if (wr_en) committed_count <= committed_count + 1'b1;

            // S0 separates upstream owner/coordinate muxes from arithmetic.
            if (input_fire) begin
                data_s0 <= in_data;
                channel_s0 <= in_channel; y_s0 <= in_y; x_s0 <= in_x;
                index_s0 <= accepted_count;
            end
            // S1: independent products; LINEAR follows the same latency.
            if (pipe_valid[0]) begin
                data_s1 <= data_s0;
                channel_offset_s1 <= mode_q == WRITE_CHW
                    ? 32'(channel_s0) * 32'(plane_stride) : 32'(index_s0);
                row_offset_s1 <= mode_q == WRITE_CHW
                    ? 32'(y_s0) * 32'(width_q) : 32'd0;
                x_s1 <= mode_q == WRITE_CHW ? 32'(x_s0) : 32'd0;
                coordinate_ok_s1 <= mode_q != WRITE_CHW ||
                    (channel_s0 < channels_q && y_s0 < height_q && x_s0 < width_q);
            end
            // S2/S3: balanced registered additions; never truncate before check.
            if (pipe_valid[1]) begin
                data_s2 <= data_s1; coordinate_ok_s2 <= coordinate_ok_s1;
                sum_a_s2 <= 32'(base_q) + channel_offset_s1;
                sum_b_s2 <= row_offset_s1 + x_s1;
            end
            if (pipe_valid[2]) begin
                data_s3 <= data_s2; coordinate_ok_s3 <= coordinate_ok_s2;
                address_s3 <= sum_a_s2 + sum_b_s2;
            end
            // S4: older pending data may commit on this edge. A bad payload
            // and ALL younger payloads are cancelled, including this edge's input.
            if (pipe_valid[3] && !failed && !payload_bad) begin
                pending_valid <= 1;
                wr_addr <= activation_addr_t'(address_s3);
                wr_data <= data_s3;
            end
            case (state)
                IDLE: if (cmd_valid) begin
                    mode_q <= cmd_mode;
                    base_q <= cmd_base;
                    width_q <= cmd_width; height_q <= cmd_height;
                    channels_q <= cmd_channels; count_q <= cmd_count;
                    accepted_count <= 0; committed_count <= 0;
                    failed <= 0; config_phase <= 0;
                    state <= CONFIG;
                end
                CONFIG: case (config_phase)
                    0: begin
                        plane_stride <= 16'(width_q) * 16'(height_q);
                        config_phase <= 1;
                    end
                    1: begin
                        total_wide <= mode_q == WRITE_CHW
                                    ? 32'(plane_stride) * 32'(channels_q) : 32'(count_q);
                        config_phase <= 2;
                    end
                    default: begin
                        if (total_wide == 0 || end_exclusive > 32'(ACT_DEPTH) ||
                            (mode_q == WRITE_CHW && (width_q == 0 || height_q == 0 || channels_q == 0))) begin
                            error <= 1;
                            state <= IDLE;
                        end else begin
                            expected_count <= activation_count_t'(total_wide);
                            state <= RECEIVE;
                        end
                    end
                endcase
                RECEIVE: if (input_fire) begin
                    // Counts issued transactions, including subsequently cancelled ones.
                    accepted_count <= accepted_count + 1'b1;
                    if (accepted_count + 16'd1 == expected_count) state <= DRAIN;
                end
                DRAIN: begin
                    // Completion is one edge AFTER the final commit, with all
                    // valids empty. Commands cannot overwrite in-flight metadata.
                    if (pipeline_empty && failed) begin
                        error <= 1;
                        state <= IDLE;
                    end else if (pipeline_empty && committed_count == expected_count) begin
                        done <= 1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
            // Highest priority: flush younger stages and wait for terminal error.
            // No combinational address arithmetic is fed back into in_ready.
            if (payload_bad && !failed) begin
                pipe_valid <= 0;
                pending_valid <= 0;
                failed <= 1;
                state <= DRAIN;
            end
        end
    end
endmodule
