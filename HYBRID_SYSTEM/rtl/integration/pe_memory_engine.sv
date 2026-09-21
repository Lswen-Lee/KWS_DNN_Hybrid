`timescale 1ns/1ps
// One resident layer, one patch/vector per compute command. No bias/requant.
// PE8_MODE is an elaboration constant; only ONE array is instantiated.
// INPUT_ZERO_POINT=127 preserves the legacy PE8 sum-W correction.
// INPUT_ZERO_POINT=128 removes that entire path; both arrays compute (A-128)*W.
// RESULT_PIPELINED at zp128 selects an elastic raw output FF, not sum correction.
module pe_memory_engine #(
    parameter bit PE8_MODE = 1'b1,
    parameter bit RESULT_PIPELINED = 1'b0,
    parameter integer INPUT_ZERO_POINT = 127
) (
    input logic clk, rst,
    input logic load_valid,
    output logic load_ready,
    input logic [7:0] load_k,
    input logic [5:0] load_channels,
    output logic load_busy, load_done, load_error, layer_ready,
    input logic weight_valid,
    output logic weight_ready,
    input logic signed [7:0] weight_i8,
    input logic compute_valid,
    output logic compute_ready, compute_busy, compute_done, compute_error,
    output logic replay_valid,
    input logic replay_ready,
    output logic [7:0] replay_k,
    output logic [4:0] replay_channel_base,
    input logic activation_valid,
    output logic activation_ready,
    input logic [7:0] activation_u8,
    output logic out_valid,
    input logic out_ready,
    output logic signed [31:0] out_data,
    output logic [4:0] out_channel_id,
    output logic out_group_last, out_error
);
    // Reject unsupported configuration in simulation; build scripts must also
    // validate parameters before launching synthesis.
    generate if (!PE8_MODE && RESULT_PIPELINED) begin : g_invalid_configuration
        initial $fatal(1, "INVALID_PE_CONFIGURATION: pipeline requires PE8_MODE=1");
    end endgenerate
    localparam bit NEED_SUM = PE8_MODE && INPUT_ZERO_POINT == 127;
    generate if (INPUT_ZERO_POINT != 127 && INPUT_ZERO_POINT != 128) begin : g_invalid_zp
        initial $fatal(1, "INPUT_ZERO_POINT must be 127 or 128");
    end endgenerate
    logic [7:0] layer_k;
    logic [5:0] layer_channels;
    wire loader_ready, loader_layer_ready, group_ready, group_error;
    wire loader_cmd_valid, group_cmd_valid;
    wire load_fire = load_valid && load_ready;
    wire compute_fire = compute_valid && compute_ready;

    // Priority does not depend on the losing request's ready signal.
    // busy is owned by the existing loader/group FSMs, not duplicated here.
    assign loader_cmd_valid = !rst && !compute_busy && load_valid;
    assign load_ready = !rst && !compute_busy && loader_ready;
    assign layer_ready = !rst && loader_layer_ready;
    assign group_cmd_valid = !rst && !load_busy && !load_valid
                             && layer_ready && compute_valid;
    assign compute_ready = !rst && !load_busy && !load_valid
                           && layer_ready && group_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            layer_k <= 0;
            layer_channels <= 0;
            compute_error <= 0;
        end else begin
            // Invalid load also invalidates loader_layer_ready. These saved
            // fields are never used until the loader has succeeded.
            if (load_fire) begin
                layer_k <= load_k;
                layer_channels <= load_channels;
            end
            if (compute_fire) compute_error <= 0;
            else if (group_error || (out_valid && out_ready && out_error))
                compute_error <= 1;
        end
    end

    wire wr_valid, wr_ready;
    wire [3:0] wr_lane;
    wire [8:0] wr_addr;
    wire [7:0] wr_data;
    wire sum_valid, sum_ready;
    wire signed [31:0] weight_sum;
    wire [4:0] sum_channel_id;
    pe_layer_weight_loader #(.SUM_ENABLE(NEED_SUM)) loader (
        .clk(clk), .rst(rst), .cmd_valid(loader_cmd_valid), .cmd_ready(loader_ready),
        .cmd_k(load_k), .cmd_channels(load_channels),
        .weight_valid(weight_valid), .weight_ready(weight_ready), .weight_i8(weight_i8),
        .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_lane(wr_lane),
        .wr_addr(wr_addr), .wr_data(wr_data), .sum_valid(sum_valid),
        .sum_ready(sum_ready), .weight_sum(weight_sum), .sum_channel_id(sum_channel_id),
        .busy(load_busy), .layer_ready(loader_layer_ready), .done(load_done), .error(load_error)
    );

    wire ram_rd_valid, ram_rd_ready, ram_out_valid, ram_out_ready;
    wire [8:0] ram_rd_addr;
    wire [95:0] ram_data;
    pe_weight_buffer_12 #(.ADDR_WIDTH(9)) weights (
        .clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_ready(wr_ready),
        .wr_lane(wr_lane), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_valid(ram_rd_valid), .rd_ready(ram_rd_ready), .rd_addr(ram_rd_addr),
        .out_valid(ram_out_valid), .out_ready(ram_out_ready), .weights_flat(ram_data)
    );
    wire [3:0] active_lanes;
    wire [11:0] lane_mask;
    wire align_in_valid, align_in_ready, align_in_last;
    wire [8:0] align_weight_addr;
    wire align_out_valid, align_out_ready, align_out_last;
    wire pe_clear, pe_accumulate_en, result_start_valid, result_start_ready;
    wire group_result_done;
    wire unused_result_busy;
    pe_group_controller groups (
        .clk(clk), .rst(rst), .cmd_valid(group_cmd_valid), .cmd_ready(group_ready),
        .cmd_k(layer_k), .cmd_channels(layer_channels), .layer_ready(layer_ready),
        .busy(compute_busy), .done(compute_done), .error(group_error),
        .replay_valid(replay_valid), .replay_ready(replay_ready), .replay_k(replay_k),
        .channel_base(replay_channel_base), .active_lanes(active_lanes), .lane_mask(lane_mask),
        .activation_valid(activation_valid), .activation_ready(activation_ready),
        .align_in_valid(align_in_valid), .align_in_ready(align_in_ready),
        .align_weight_addr(align_weight_addr), .align_in_last(align_in_last),
        .align_out_valid(align_out_valid), .align_out_last(align_out_last),
        .align_out_ready(align_out_ready), .pe_clear(pe_clear), .pe_accumulate_en(pe_accumulate_en),
        .result_start_valid(result_start_valid), .result_start_ready(result_start_ready),
        .group_result_done(group_result_done)
    );
    wire [7:0] aligned_a;
    wire [95:0] aligned_w;
    wire read_align_valid, read_align_ready, read_align_last;
    wire [7:0] read_align_a;
    wire [95:0] read_align_w;
    logic operand_valid, operand_last;
    logic [7:0] operand_a;
    logic [95:0] operand_w;
    // One elastic operand stage, shared by all three comparison variants.
    // The controller observes CONSUMPTION here, not the earlier RAM response.
    // Keep payload unreset: only valid determines whether it can reach the MAC.
    assign read_align_ready = !rst && (!operand_valid || align_out_ready);
    assign align_out_valid = !rst && operand_valid;
    assign align_out_last = operand_last;
    assign aligned_a = operand_a;
    assign aligned_w = operand_w;
    always_ff @(posedge clk) begin
        if (rst) operand_valid <= 1'b0;
        else if (read_align_ready) begin
            operand_valid <= read_align_valid;
            if (read_align_valid) begin
                operand_a <= read_align_a;
                operand_w <= read_align_w;
                operand_last <= read_align_last;
            end
        end
    end
    wire [383:0] raw_results;
    pe_weight_read_align aligner (
        .clk(clk), .rst(rst), .in_valid(align_in_valid), .in_ready(align_in_ready),
        .in_activation_u8(activation_u8), .in_weight_addr(align_weight_addr), .in_last(align_in_last),
        .weight_rd_valid(ram_rd_valid), .weight_rd_ready(ram_rd_ready), .weight_rd_addr(ram_rd_addr),
        .weight_out_valid(ram_out_valid), .weight_out_ready(ram_out_ready), .weight_data(ram_data),
        .out_valid(read_align_valid), .out_ready(read_align_ready), .out_activation_u8(read_align_a),
        .out_weights(read_align_w), .out_last(read_align_last)
    );
    wire sum_rd_valid, sum_rd_ready, sum_out_valid, sum_out_ready, sum_error;
    wire [4:0] sum_rd_id, sum_out_id;
    wire signed [31:0] sum_data;
    generate if (PE8_MODE) begin : g_pe8
        wire signed [7:0] a8;
        activation_u8_to_s8 converter (.activation_u8(aligned_a), .activation_s8(a8));
        pe8_array_12 array_core (
            .clk(clk), .rst(rst), .clear(pe_clear), .accumulate_en(pe_accumulate_en),
            .lane_mask(lane_mask), .activation_s8(a8), .weight_vector_i8(aligned_w),
            .result_vector_s32(raw_results)
        );
    end else begin : g_pe9
        wire signed [8:0] a9;
        if (INPUT_ZERO_POINT == 127) begin : g_zp127
            activation_center_127 converter (.activation_u8(aligned_a), .activation_centered(a9));
        end else begin : g_zp128
            // Same mathematical value as PE8, sign-extended to the 9-bit lane.
            assign a9 = $signed({~aligned_a[7], ~aligned_a[7], aligned_a[6:0]});
        end
        pe_array_12 array_core (
            .clk(clk), .rst(rst), .clear(pe_clear), .accumulate_en(pe_accumulate_en),
            .lane_mask(lane_mask), .activation_centered(a9), .weight_vector_i8(aligned_w),
            .result_vector_s32(raw_results)
        );
    end endgenerate
    generate if (NEED_SUM) begin : g_sum_memory
        pe_channel_sum_memory sums (
            .clk(clk), .rst(rst), .layer_clear(load_fire),
            .wr_valid(sum_valid), .wr_ready(sum_ready), .wr_channel_id(sum_channel_id),
            .wr_weight_sum(weight_sum), .rd_valid(sum_rd_valid), .rd_ready(sum_rd_ready),
            .rd_channel_id(sum_rd_id), .out_valid(sum_out_valid), .out_ready(sum_out_ready),
            .out_channel_id(sum_out_id), .out_weight_sum(sum_data), .out_error(sum_error)
        );
    end else begin : g_no_sum_memory
        assign sum_ready = 1'b1;
        assign sum_rd_ready = 1'b0;
        assign sum_out_valid = 1'b0;
        assign sum_out_id = 5'd0;
        assign sum_data = 32'sd0;
        assign sum_error = 1'b0;
    end endgenerate
    generate if (NEED_SUM && RESULT_PIPELINED) begin : g_pipeline_result
    pe8_result_controller_pipeline results (
        .clk(clk), .rst(rst), .result_start_valid(result_start_valid), .result_start_ready(result_start_ready),
        .channel_base(replay_channel_base), .active_lanes(active_lanes), .raw_results(raw_results),
        .busy(unused_result_busy), .group_result_done(group_result_done),
        .sum_rd_valid(sum_rd_valid), .sum_rd_ready(sum_rd_ready), .sum_rd_channel_id(sum_rd_id),
        .sum_out_valid(sum_out_valid), .sum_out_ready(sum_out_ready), .sum_out_channel_id(sum_out_id),
        .sum_out_data(sum_data), .sum_out_error(sum_error),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
        .out_channel_id(out_channel_id), .out_last(out_group_last), .out_error(out_error)
    );
    end else begin : g_compact_result
    pe_result_controller #(.PE8_MODE(PE8_MODE), .APPLY_SUM_CORRECTION(NEED_SUM),
        .RAW_PIPELINED(!NEED_SUM && RESULT_PIPELINED)) results (
        .clk(clk), .rst(rst), .result_start_valid(result_start_valid), .result_start_ready(result_start_ready),
        .channel_base(replay_channel_base), .active_lanes(active_lanes), .raw_results(raw_results),
        .busy(unused_result_busy), .group_result_done(group_result_done),
        .sum_rd_valid(sum_rd_valid), .sum_rd_ready(sum_rd_ready), .sum_rd_channel_id(sum_rd_id),
        .sum_out_valid(sum_out_valid), .sum_out_ready(sum_out_ready), .sum_out_channel_id(sum_out_id),
        .sum_out_data(sum_data), .sum_out_error(sum_error),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
        .out_channel_id(out_channel_id), .out_last(out_group_last), .out_error(out_error)
    );
    end endgenerate
endmodule
