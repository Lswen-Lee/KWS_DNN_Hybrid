`timescale 1ns/1ps
// S3: one layer command, one writer command, one PE command per patch,
// one reader command per PE replay. Data bytes bypass this controller.
// All endpoints share clk/rst. Owner must prohibit weight reload/host/pool
// access while busy. Resident metadata describes SUCCESSFULLY loaded weights.
// pe_compute_done is RAW engine completion; pe_out_* is AFTER quantization.
// postprocess_empty includes all accepted in-flight and queued results.
module pe_layer_controller (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic cmd_is_fc,
    input logic [2:0] cmd_layer_id,
    input logic cmd_relu_enable,
    input logic [14:0] cmd_src_base, cmd_dst_base,
    input logic [7:0] cmd_width, cmd_height, cmd_vector_length,
    input logic [5:0] cmd_input_channels, cmd_output_channels,
    input logic resident_valid,
    input logic [2:0] resident_layer_id,
    input logic [7:0] resident_k,
    input logic [5:0] resident_channels,
    output logic busy, done, error, fault,

    output logic reader_cmd_valid,
    input logic reader_cmd_ready, reader_done, reader_error,
    output kws_system_pkg::activation_read_mode_t reader_mode,
    output logic [14:0] reader_base,
    output logic [15:0] reader_count,
    output logic [7:0] reader_width, reader_height, reader_x, reader_y,
    output logic [5:0] reader_channels,
    input logic reader_out_valid, reader_out_last,
    output logic reader_out_ready,

    output logic pe_compute_valid,
    input logic pe_compute_ready, pe_compute_done, pe_compute_error,
    input logic postprocess_empty,
    output logic [2:0] pe_layer_id,
    output logic pe_relu_enable,
    input logic pe_replay_valid,
    output logic pe_replay_ready,
    input logic [7:0] pe_replay_k,
    input logic [4:0] pe_replay_channel_base,
    output logic pe_activation_valid,
    input logic pe_activation_ready,
    input logic pe_out_valid, pe_out_group_last, pe_out_error,
    input logic [4:0] pe_out_channel_id,
    output logic pe_out_ready,

    output logic writer_cmd_valid,
    input logic writer_cmd_ready, writer_in_ready, writer_done, writer_error,
    output kws_system_pkg::activation_write_mode_t writer_mode,
    output logic [14:0] writer_base,
    output logic [15:0] writer_count,
    output logic [7:0] writer_width, writer_height,
    output logic [5:0] writer_channels,
    output logic writer_in_valid,
    output logic [5:0] writer_channel,
    output logic [7:0] writer_x, writer_y
);
    import kws_system_pkg::*;

    // 1. Frozen descriptor and CONFIG-only precomputation.
    typedef enum logic [3:0] {
        IDLE, CONFIG, START_WRITER, WAIT_WRITER_READY, START_PE,
        WAIT_REPLAY, RUN, NEXT_PATCH, DRAIN_LAYER, FAULT
    } state_t;
    state_t state;
    logic [1:0] config_phase;
    logic fc_q, relu_q;
    logic [2:0] layer_q;
    logic [14:0] src_q, dst_q;
    logic [7:0] width_q, height_q, vector_q, out_width, out_height;
    logic [5:0] in_channels_q, out_channels_q;
    logic [15:0] source_plane, output_plane, k_wide;
    logic [31:0] source_size, output_size, source_end, output_end;
    logic [9:0] weight_depth;
    logic [7:0] k_q, patch_x, patch_y;
    logic config_bad, resident_matches;

    // 2. Per-patch/per-replay progress, not copies of the PE's group FSM.
    logic reader_active, pe_done_seen, writer_done_seen;
    logic [7:0] activation_count;
    logic [5:0] next_group_base, result_count;
    logic compute_phase, operation_phase, runtime_bad, replay_bad, result_bad;
    logic expected_group_last;
    wire replay_fire = reader_cmd_valid && reader_cmd_ready;
    wire activation_fire = pe_activation_valid && pe_activation_ready;
    wire result_fire = pe_out_valid && pe_out_ready;

    assign cmd_ready = !rst && state == IDLE;
    assign busy = state != IDLE;
    assign fault = state == FAULT;
    assign compute_phase = state == WAIT_REPLAY || state == RUN;
    assign operation_phase = state != IDLE && state != CONFIG && state != FAULT;
    assign source_end = 32'(src_q) + source_size;
    assign output_end = 32'(dst_q) + output_size;
    assign resident_matches = resident_valid && resident_layer_id == layer_q &&
                              {8'd0,resident_k} == k_wide && resident_channels == out_channels_q;
    always_comb begin
        weight_depth = 10'(k_wide);
        if (out_channels_q > 12) weight_depth = weight_depth + 10'(k_wide);
        if (out_channels_q > 24) weight_depth = weight_depth + 10'(k_wide);
        config_bad = !resident_matches || k_wide == 0 || k_wide > 255 ||
                     out_channels_q == 0 || out_channels_q > 32 || weight_depth > 512 ||
                     source_size == 0 || output_size == 0 ||
                     source_end > 32768 || output_end > 32768 ||
                     (32'(src_q) < output_end && 32'(dst_q) < source_end);
        // ROM IDs: 0/1/2 convolution (<=12 channels), 3 FC1, 4 FC2.
        if (fc_q)
            config_bad = config_bad || (layer_q != 3 && layer_q != 4) ||
                         (layer_q == 4 && out_channels_q > 8);
        else
            config_bad = config_bad || layer_q > 2 || out_channels_q > 12 ||
                         width_q < 3 || height_q < 3 || in_channels_q == 0;
    end

    // Bad tags are rejected before entering Writer. Error signals from a
    // previous PE command can be sticky, so inspect them only after launch.
    assign expected_group_last = result_count == 11 || result_count == 23 ||
                                 result_count + 6'd1 == out_channels_q;
    assign result_bad = compute_phase && pe_out_valid &&
        (pe_out_error || result_count >= out_channels_q ||
         {1'b0,pe_out_channel_id} != result_count || pe_out_group_last != expected_group_last);
    assign replay_bad = state == WAIT_REPLAY && pe_replay_valid &&
        (pe_replay_k != k_q || next_group_base >= out_channels_q ||
         {1'b0,pe_replay_channel_base} != next_group_base);
    assign runtime_bad = operation_phase &&
        (reader_error || writer_error || !resident_matches ||
         (compute_phase && pe_compute_error) || result_bad || replay_bad ||
         (!compute_phase && pe_out_valid));

    // 3. Command/data control routing. Actual 8-bit payloads bypass the FSM.
    assign reader_mode = fc_q ? READ_LINEAR : READ_PATCH;
    assign reader_base = src_q;
    assign reader_count = {8'd0,k_q};
    assign reader_width = width_q;
    assign reader_height = height_q;
    assign reader_channels = in_channels_q;
    assign reader_x = patch_x;
    assign reader_y = patch_y;
    assign reader_cmd_valid = !rst && !runtime_bad && state == WAIT_REPLAY &&
                              !reader_active && pe_replay_valid;
    assign pe_replay_ready = !rst && !runtime_bad && state == WAIT_REPLAY &&
                             !reader_active && reader_cmd_ready;
    assign pe_compute_valid = !rst && !runtime_bad && postprocess_empty && state == START_PE;
    assign pe_layer_id = layer_q;
    assign pe_relu_enable = relu_q;
    assign pe_activation_valid = !rst && !runtime_bad && compute_phase &&
                                 reader_active && reader_out_valid;
    assign reader_out_ready = !rst && !runtime_bad && compute_phase &&
                              reader_active && pe_activation_ready;

    assign writer_mode = WRITE_CHW; // FC is C x 1 x 1.
    assign writer_base = dst_q;
    assign writer_count = 16'(output_size);
    assign writer_width = out_width;
    assign writer_height = out_height;
    assign writer_channels = out_channels_q;
    assign writer_x = patch_x;
    assign writer_y = patch_y;
    assign writer_channel = {1'b0,pe_out_channel_id};
    assign writer_cmd_valid = !rst && !runtime_bad && state == START_WRITER;
    // Keep the result path open across replay boundaries; FIFO can still drain.
    assign writer_in_valid = !rst && !runtime_bad && compute_phase && pe_out_valid;
    assign pe_out_ready = !rst && !runtime_bad && compute_phase && writer_in_ready;

    // 4. Sequencer. Pulses are remembered; they need not arrive together.
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; config_phase <= 0;
            fc_q <= 0; relu_q <= 0; layer_q <= 0; src_q <= 0; dst_q <= 0;
            width_q <= 0; height_q <= 0; vector_q <= 0;
            in_channels_q <= 0; out_channels_q <= 0;
            out_width <= 0; out_height <= 0; source_plane <= 0; output_plane <= 0;
            k_wide <= 0; k_q <= 0; source_size <= 0; output_size <= 0;
            patch_x <= 0; patch_y <= 0; reader_active <= 0;
            activation_count <= 0; next_group_base <= 0; result_count <= 0;
            pe_done_seen <= 0; writer_done_seen <= 0; done <= 0; error <= 0;
        end else begin
            done <= 0; error <= 0;
            if (operation_phase && writer_done) writer_done_seen <= 1;
            if (compute_phase && pe_compute_done) pe_done_seen <= 1;
            if (reader_active && reader_done) reader_active <= 0;
            if (activation_fire) activation_count <= activation_count + 8'd1;
            if (result_fire) result_count <= result_count + 6'd1;

            if (runtime_bad || (activation_fire &&
                (activation_count >= k_q || reader_out_last != (activation_count == k_q-8'd1))) ||
                (reader_active && reader_done && activation_count != k_q)) begin
                state <= FAULT; error <= 1;
            end else case (state)
                IDLE: if (cmd_valid && cmd_ready) begin
                    fc_q <= cmd_is_fc; layer_q <= cmd_layer_id; relu_q <= cmd_relu_enable;
                    src_q <= cmd_src_base; dst_q <= cmd_dst_base;
                    width_q <= cmd_width; height_q <= cmd_height; vector_q <= cmd_vector_length;
                    in_channels_q <= cmd_input_channels; out_channels_q <= cmd_output_channels;
                    patch_x <= 0; patch_y <= 0; config_phase <= 0;
                    writer_done_seen <= 0; state <= CONFIG;
                end
                CONFIG: case (config_phase)
                    0: begin
                        source_plane <= 16'(width_q) * 16'(height_q);
                        out_width <= fc_q ? 8'd1 : width_q - 8'd2;
                        out_height <= fc_q ? 8'd1 : height_q - 8'd2;
                        k_wide <= fc_q ? 16'(vector_q) : 16'(in_channels_q) * 16'd9;
                        config_phase <= 1;
                    end
                    1: begin
                        source_size <= fc_q ? 32'(vector_q) : 32'(source_plane)*32'(in_channels_q);
                        output_plane <= 16'(out_width)*16'(out_height);
                        config_phase <= 2;
                    end
                    2: begin
                        output_size <= 32'(output_plane)*32'(out_channels_q);
                        config_phase <= 3;
                    end
                    default: begin
                        if (config_bad) begin error <= 1; state <= IDLE; end
                        else begin k_q <= 8'(k_wide); state <= START_WRITER; end
                    end
                endcase
                START_WRITER: if (writer_cmd_valid && writer_cmd_ready) state <= WAIT_WRITER_READY;
                WAIT_WRITER_READY: if (writer_in_ready) state <= START_PE;
                START_PE: if (pe_compute_valid && pe_compute_ready) begin
                    result_count <= 0; next_group_base <= 0; activation_count <= 0;
                    reader_active <= 0; pe_done_seen <= 0; state <= WAIT_REPLAY;
                end
                WAIT_REPLAY: if (replay_fire) begin
                    reader_active <= 1; activation_count <= 0;
                    next_group_base <= next_group_base + 6'd12; state <= RUN;
                end
                RUN: begin
                    if (pe_done_seen || pe_compute_done) begin
                        if ((reader_active && !reader_done) ||
                            next_group_base < out_channels_q) begin
                            error <= 1; state <= FAULT;
                        end else if (postprocess_empty) begin
                            // Raw done may precede quantized output acceptance.
                            // Once empty, a short result stream is a real error.
                            if (result_count != out_channels_q) begin
                                error <= 1; state <= FAULT;
                            end else if (patch_x == out_width-8'd1 && patch_y == out_height-8'd1)
                                state <= DRAIN_LAYER;
                            else state <= NEXT_PATCH;
                        end
                    end else if (!reader_active && pe_replay_valid) state <= WAIT_REPLAY;
                end
                NEXT_PATCH: begin
                    if (patch_x == out_width-8'd1) begin patch_x <= 0; patch_y <= patch_y+8'd1; end
                    else patch_x <= patch_x+8'd1;
                    state <= START_PE;
                end
                DRAIN_LAYER: if (writer_done_seen || writer_done) begin done <= 1; state <= IDLE; end
                FAULT: ; // Shared reset only; no rollback of committed RAM writes.
                default: begin error <= 1; state <= FAULT; end
            endcase
        end
    end
endmodule
