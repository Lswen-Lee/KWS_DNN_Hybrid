`timescale 1ns/1ps
// S4 internal streaming top, not a physical FPGA pin top.
// Supports FRONTEND and FC_TAIL; FULL/DCIM/Argmax are not implemented yet.
module kws_inference_top #(
    parameter bit RESULT_PIPELINED = 1'b0,
    parameter bit POSTPROCESS_PIPELINED = 1'b1
) (
    input logic clk, rst,
    input logic start_valid,
    output logic start_ready,
    input kws_system_pkg::inference_mode_t run_mode,
    output logic busy, done, error,
    output kws_system_pkg::layer_error_t error_code,
    output logic [3:0] current_op,
    output logic op_done,
    output logic input_request_valid,
    input logic input_request_ready,
    output logic input_is_flatten,
    output logic [15:0] input_count,
    input logic input_valid,
    output logic input_ready,
    input logic [7:0] input_data,
    output logic weight_request_valid,
    input logic weight_request_ready,
    output logic [2:0] weight_layer_id,
    output logic [7:0] weight_k,
    output logic [5:0] weight_channels,
    input logic weight_valid,
    output logic weight_ready,
    input logic signed [7:0] weight_i8,
    input logic source_error,
    // Debug/result readback: only between runs. Start has priority over read.
    input logic read_valid,
    output logic read_ready,
    input logic [14:0] read_base,
    input logic [15:0] read_count,
    output logic read_out_valid,
    input logic read_out_ready,
    output logic [7:0] read_data,
    output logic read_last, read_done, read_error
);
    import kws_system_pkg::*;
    layer_descriptor_t cfg;
    logic controller_busy, controller_ready, path_busy, path_fault;
    logic load_valid, load_ready, load_done, load_error;
    logic weight_load_valid, weight_load_ready, weight_load_done, weight_load_error;
    logic pe_cmd_valid, pe_cmd_ready, pe_done, pe_error;
    logic pool_valid, pool_ready, pool_done, pool_error;
    logic input_enable, weight_enable, path_input_ready, path_weight_ready;
    logic host_read_valid, host_read_ready;
    assign start_ready = controller_ready;
    assign busy = controller_busy || path_busy;
    assign host_read_valid = read_valid && !controller_busy && !start_valid && !rst;
    assign read_ready = host_read_ready && !controller_busy && !start_valid && !rst;
    assign input_ready = input_enable && path_input_ready;
    assign weight_ready = weight_enable && path_weight_ready;
    assign weight_layer_id = cfg.layer_id;
    assign weight_k = cfg.k;
    assign weight_channels = cfg.output_channels;

    layer_controller controller (
        .clk(clk), .rst(rst), .start_valid(start_valid), .start_ready(controller_ready), .run_mode(run_mode),
        .busy(controller_busy), .done(done), .error(error), .error_code(error_code),
        .current_op(current_op), .op_done(op_done),
        .input_request_valid(input_request_valid), .input_request_ready(input_request_ready),
        .input_is_flatten(input_is_flatten), .input_count(input_count),
        .weight_request_valid(weight_request_valid), .weight_request_ready(weight_request_ready),
        .source_error(source_error), .active_descriptor(cfg),
        .input_stream_enable(input_enable), .weight_stream_enable(weight_enable),
        .load_valid(load_valid), .load_ready(load_ready), .load_done(load_done), .load_error(load_error),
        .weight_load_valid(weight_load_valid), .weight_load_ready(weight_load_ready),
        .weight_load_done(weight_load_done), .weight_load_error(weight_load_error),
        .pe_cmd_valid(pe_cmd_valid), .pe_cmd_ready(pe_cmd_ready), .pe_done(pe_done), .pe_error(pe_error),
        .pool_valid(pool_valid), .pool_ready(pool_ready), .pool_done(pool_done), .pool_error(pool_error),
        .path_busy(path_busy), .path_fault(path_fault)
    );
    kws_activation_path #(.RESULT_PIPELINED(RESULT_PIPELINED), .POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) path (
        // S4 scheduler remains PE/Pool-only until the full-sequence milestone.
        .clk_cim(clk),.rst_cim(rst),.weight_backend(1'b0),
        .dcim_cmd_valid(1'b0),.dcim_cmd_ready(),.dcim_layer_id(3'd0),.dcim_relu_enable(1'b0),
        .dcim_src_base(15'd0),.dcim_dst_base(15'd0),.dcim_width(8'd0),.dcim_height(8'd0),
        .dcim_done(),.dcim_error(),.dcim_resident_valid(),
        .clk(clk), .rst(rst),
        .load_valid(load_valid), .load_ready(load_ready), .load_mode(WRITE_LINEAR),
        .load_base(15'd0), .load_count(input_count), .load_width(8'd0), .load_height(8'd0), .load_channels(6'd0),
        .load_data_valid(input_enable && input_valid), .load_data_ready(path_input_ready),
        .load_data(input_data), .load_x(8'd0), .load_y(8'd0), .load_channel(6'd0),
        .load_done(load_done), .load_error(load_error),
        .read_valid(host_read_valid), .read_ready(host_read_ready), .read_base(read_base), .read_count(read_count),
        .read_out_valid(read_out_valid), .read_out_ready(read_out_ready), .read_data(read_data),
        .read_last(read_last), .read_done(read_done), .read_error(read_error),
        .pool_valid(pool_valid), .pool_ready(pool_ready), .pool_src_base(cfg.src_base), .pool_dst_base(cfg.dst_base),
        .pool_width(cfg.input_width), .pool_height(cfg.input_height), .pool_channels(cfg.input_channels),
        .pool_done(pool_done), .pool_error(pool_error), .fault(path_fault), .busy(path_busy),
        .weight_load_valid(weight_load_valid), .weight_load_ready(weight_load_ready),
        .weight_layer_id(cfg.layer_id), .weight_k(cfg.k), .weight_channels(cfg.output_channels),
        .weight_valid(weight_enable && weight_valid), .weight_ready(path_weight_ready), .weight_i8(weight_i8),
        .weight_load_done(weight_load_done), .weight_load_error(weight_load_error), .resident_valid(),
        .pe_cmd_valid(pe_cmd_valid), .pe_cmd_ready(pe_cmd_ready), .pe_is_fc(cfg.op_kind == OP_FC),
        .pe_relu_enable(cfg.relu_enable), .pe_layer_id(cfg.layer_id), .pe_src_base(cfg.src_base), .pe_dst_base(cfg.dst_base),
        .pe_width(cfg.input_width), .pe_height(cfg.input_height), .pe_vector_length(cfg.k),
        .pe_input_channels(cfg.input_channels), .pe_output_channels(cfg.output_channels), .pe_done(pe_done), .pe_error(pe_error)
    );
endmodule
