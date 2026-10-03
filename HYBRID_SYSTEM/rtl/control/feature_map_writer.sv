`timescale 1ns/1ps
// Exclusive writer for activation_buffer's always-accepting local RAM port.
// Valid/ready accepts input; the pending register commits on the NEXT edge.
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
    logic [31:0] total_wide, end_exclusive, address_wide;
    logic pending_valid, failed;
    logic coordinate_ok;

    assign cmd_ready = !rst && state == IDLE;
    assign busy = state != IDLE;
    assign in_ready = !rst && state == RECEIVE;
    assign wr_en = !rst && pending_valid;
    // All arithmetic remains wide until configuration/coordinate validation.
    assign end_exclusive = {17'd0, base_q} + total_wide;
    always_comb begin
        coordinate_ok = 1'b1;
        address_wide = {17'd0, base_q} + {16'd0, accepted_count};
        if (mode_q == WRITE_CHW) begin
            coordinate_ok = in_channel < channels_q && in_y < height_q && in_x < width_q;
            address_wide = {17'd0, base_q}
                         + (32'(in_channel) * 32'(plane_stride))
                         + (32'(in_y) * 32'(width_q)) + 32'(in_x);
        end
    end

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
            done <= 0; error <= 0;
            // Payload registers need no reset: wr_en qualifies them.
        end else begin
            done <= 0;
            error <= 0;
            pending_valid <= 0;
            if (wr_en) committed_count <= committed_count + 1'b1;
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
                RECEIVE: if (in_valid) begin
                    if (!coordinate_ok || address_wide >= 32'(ACT_DEPTH)) begin
                        // Reject this payload. Previously accepted pending data
                        // may commit on this edge; there is no rollback.
                        failed <= 1;
                        state <= DRAIN;
                    end else begin
                        pending_valid <= 1;
                        wr_addr <= activation_addr_t'(address_wide);
                        wr_data <= in_data;
                        accepted_count <= accepted_count + 1'b1;
                        if (accepted_count + 16'd1 == expected_count)
                            state <= DRAIN;
                    end
                end
                DRAIN: begin
                    // Account for a commit occurring on this very edge.
                    if (failed) begin
                        error <= 1;
                        state <= IDLE;
                    end else if (committed_count + 16'(wr_en) == expected_count) begin
                        done <= 1;
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
