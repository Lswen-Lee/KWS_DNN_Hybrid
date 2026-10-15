`timescale 1ns/1ps
// S5-C sequencer: fixed K=108, Cin=Cout=12, valid 3x3 convolution.
// Payload bypasses this module. All ports are synchronous to clk_sys (clk).
// Owner locks resident weights/RAM ownership while busy. Reset ALL endpoints
// together on fault; already committed RAM data cannot be rolled back.
module dcim_layer_controller (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [2:0] cmd_layer_id,
    input logic cmd_relu_enable,
    input logic [14:0] cmd_src_base, cmd_dst_base,
    input logic [7:0] cmd_width, cmd_height,
    input logic resident_valid,
    input logic [2:0] resident_layer_id,
    output logic busy, done, error, fault,

    output logic reader_cmd_valid,
    input logic reader_cmd_ready, reader_done, reader_error,
    output logic [14:0] reader_base,
    output logic [7:0] reader_width, reader_height, reader_x, reader_y,
    input logic reader_out_valid, reader_out_last,
    output logic reader_out_ready,
    output logic dcim_activation_valid,
    input logic dcim_activation_ready,
    output logic dcim_patch_valid,
    input logic dcim_patch_ready, dcim_patch_done, dcim_error,

    // Raw DCIM -> PoT valid/ready must BOTH be gated with raw_path_enable.
    output logic raw_path_enable,
    output logic dcim_source_error,
    output logic [2:0] post_layer_id,
    output logic post_relu_enable,
    input logic post_valid, post_last, post_error,
    input logic [4:0] post_channel,
    output logic post_ready,

    output logic writer_cmd_valid,
    input logic writer_cmd_ready, writer_in_ready, writer_done, writer_error,
    output logic [14:0] writer_base,
    output logic [7:0] writer_width, writer_height, writer_x, writer_y,
    output logic [5:0] writer_channel,
    output logic writer_in_valid
);
    typedef enum logic [2:0] {
        IDLE, CONFIG, START_WRITER, START_PATCH,
        START_READER, RUN_PATCH, DRAIN_LAYER, FAULT
    } state_t;
    state_t state;
    logic [1:0] config_phase;
    logic [2:0] layer_q;
    logic relu_q;
    logic [14:0] src_q, dst_q;
    logic [7:0] width_q, height_q, out_width, out_height, patch_x, patch_y;
    logic [15:0] source_plane, output_plane;
    logic [31:0] source_size, output_size, source_end, output_end;
    logic [6:0] activation_count;
    logic [3:0] result_count;
    logic reader_done_seen, dcim_done_seen, writer_done_seen;
    logic active, resident_matches, config_bad, runtime_bad, final_patch;
    logic activation_bad, result_bad, completion_bad;
    logic activation_candidate, result_candidate;
    logic [7:0] activation_after;
    logic [4:0] result_after;
    wire activation_fire = dcim_activation_valid && dcim_activation_ready;
    wire result_fire = writer_in_valid && writer_in_ready;

    assign cmd_ready = !rst && state == IDLE;
    assign busy = state != IDLE;
    assign fault = state == FAULT;
    assign active = state != IDLE && state != CONFIG && state != FAULT;
    assign resident_matches = resident_valid && resident_layer_id == layer_q;
    assign source_end = {17'd0,src_q} + source_size;
    assign output_end = {17'd0,dst_q} + output_size;
    assign config_bad = !resident_matches || dcim_error ||
        (layer_q != 1 && layer_q != 2) || width_q < 3 || height_q < 3 ||
        source_end > 32768 || output_end > 32768 ||
        (32'(src_q) < output_end && 32'(dst_q) < source_end);
    assign final_patch = patch_x == out_width-8'd1 && patch_y == out_height-8'd1;

    // Candidates do NOT depend on runtime_bad: no combinational feedback from
    // output gating into count validation. Illegal payload never handshakes.
    assign activation_candidate = state == RUN_PATCH && reader_out_valid && dcim_activation_ready;
    assign result_candidate = state == RUN_PATCH && post_valid && writer_in_ready;
    assign activation_after = {1'b0,activation_count} + {7'd0,activation_candidate};
    assign result_after = {1'b0,result_count} + {4'd0,result_candidate};
    assign activation_bad = state == RUN_PATCH && reader_out_valid &&
        (activation_count >= 108 || reader_out_last != (activation_count == 107) || reader_done_seen);
    assign result_bad = active && post_valid &&
        (state != RUN_PATCH || post_error || result_count >= 12 ||
         post_channel != {1'b0,result_count} || post_last != (result_count == 11));
    assign completion_bad = active && (
        (reader_done && (state != RUN_PATCH || reader_done_seen || activation_after != 108)) ||
        (dcim_patch_done && (state != RUN_PATCH || dcim_done_seen || activation_after != 108)) ||
        (writer_done && (writer_done_seen || !final_patch || result_after != 12 ||
                        (state != RUN_PATCH && state != DRAIN_LAYER))));
    assign runtime_bad = active && (!resident_matches || reader_error ||
        writer_error || dcim_error || activation_bad || result_bad || completion_bad);
    // Registered-state abort avoids feedback through backend activation_ready.
    // Local gates stop immediately; backend observes abort after the FAULT edge.
    assign dcim_source_error = !rst && fault;

    assign reader_base = src_q;
    assign reader_width = width_q;
    assign reader_height = height_q;
    assign reader_x = patch_x;
    assign reader_y = patch_y;
    assign writer_base = dst_q;
    assign writer_width = out_width;
    assign writer_height = out_height;
    assign writer_x = patch_x;
    assign writer_y = patch_y;
    assign writer_channel = {1'b0,post_channel};
    assign post_layer_id = layer_q;
    assign post_relu_enable = relu_q;
    assign reader_cmd_valid = !rst && !runtime_bad && state == START_READER;
    assign dcim_patch_valid = !rst && !runtime_bad && state == START_PATCH;
    assign writer_cmd_valid = !rst && !runtime_bad && state == START_WRITER;
    assign raw_path_enable = !rst && !runtime_bad && state == RUN_PATCH;
    assign dcim_activation_valid = raw_path_enable && !reader_done_seen && reader_out_valid;
    assign reader_out_ready = raw_path_enable && !reader_done_seen && dcim_activation_ready;
    assign writer_in_valid = raw_path_enable && post_valid;
    assign post_ready = raw_path_enable && writer_in_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; config_phase <= 0;
            layer_q <= 0; relu_q <= 0; src_q <= 0; dst_q <= 0;
            width_q <= 0; height_q <= 0; out_width <= 0; out_height <= 0;
            source_plane <= 0; output_plane <= 0; source_size <= 0; output_size <= 0;
            patch_x <= 0; patch_y <= 0; activation_count <= 0; result_count <= 0;
            reader_done_seen <= 0; dcim_done_seen <= 0; writer_done_seen <= 0;
            done <= 0; error <= 0;
        end else begin
            done <= 0; error <= 0;
            if (activation_fire) activation_count <= activation_count + 7'd1;
            if (result_fire) result_count <= result_count + 4'd1;
            if (active && writer_done) writer_done_seen <= 1;
            if (state == RUN_PATCH && reader_done) reader_done_seen <= 1;
            if (state == RUN_PATCH && dcim_patch_done) dcim_done_seen <= 1;
            if (runtime_bad) begin state <= FAULT; error <= 1; end
            else case (state)
                IDLE: if (cmd_valid && cmd_ready) begin
                    layer_q <= cmd_layer_id; relu_q <= cmd_relu_enable;
                    src_q <= cmd_src_base; dst_q <= cmd_dst_base;
                    width_q <= cmd_width; height_q <= cmd_height;
                    patch_x <= 0; patch_y <= 0; config_phase <= 0;
                    writer_done_seen <= 0; state <= CONFIG;
                end
                CONFIG: case (config_phase)
                    0: begin
                        source_plane <= 16'(width_q)*16'(height_q);
                        out_width <= width_q-8'd2; out_height <= height_q-8'd2;
                        config_phase <= 1;
                    end
                    1: begin
                        source_size <= 32'(source_plane)*32'd12;
                        output_plane <= 16'(out_width)*16'(out_height);
                        config_phase <= 2;
                    end
                    2: begin output_size <= 32'(output_plane)*32'd12; config_phase <= 3; end
                    default: if (config_bad) begin error <= 1; state <= IDLE; end
                             else state <= START_WRITER;
                endcase
                START_WRITER: if (writer_cmd_valid && writer_cmd_ready) state <= START_PATCH;
                START_PATCH: if (dcim_patch_valid && dcim_patch_ready) begin
                    activation_count <= 0; result_count <= 0;
                    reader_done_seen <= 0; dcim_done_seen <= 0; state <= START_READER;
                end
                START_READER: if (reader_cmd_valid && reader_cmd_ready) state <= RUN_PATCH;
                RUN_PATCH: if ((reader_done_seen || reader_done) &&
                              (dcim_done_seen || dcim_patch_done) && result_after == 12) begin
                    if (final_patch) state <= DRAIN_LAYER;
                    else begin
                        if (patch_x == out_width-8'd1) begin patch_x <= 0; patch_y <= patch_y+8'd1; end
                        else patch_x <= patch_x+8'd1;
                        state <= START_PATCH;
                    end
                end
                DRAIN_LAYER: if (writer_done_seen || writer_done) begin done <= 1; state <= IDLE; end
                FAULT: ; // No retry or local reset: owner resets the whole path.
                default: begin error <= 1; state <= FAULT; end
            endcase
        end
    end
endmodule
