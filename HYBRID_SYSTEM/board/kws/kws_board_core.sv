`timescale 1ns/1ps
// Technology-independent board harness, also the real dual-clock simulation DUT.
module kws_board_core #(
    parameter DEMO_FILE="kws_demo.mem",
    parameter bit RESULT_PIPELINED=0, POSTPROCESS_PIPELINED=1,
    parameter bit CHECK_RESULT_ORDER=1'b1,
    parameter integer TIMEOUT_CYCLES=125000000,
    parameter logic [2:0] EXPECTED_CLASS=6,
    parameter logic [7:0] EXPECTED_SCORE=183
) (
    input logic clk, rst, clk_cim, rst_cim,
    output logic busy, pass, fail,
    output logic [2:0] result_index,
    output logic [7:0] result_score,
    output logic [3:0] failure_code,
    output logic [31:0] run_cycles
);
    import kws_system_pkg::*;
    logic start_valid,start_ready,engine_done,engine_error,class_valid;
    logic [2:0] class_index;
    logic [7:0] class_score;
    logic source_enable,source_fault;
    logic input_request_valid,input_request_ready,input_is_flatten,input_valid,input_ready;
    logic [15:0] input_count;
    logic [7:0] input_data;
    logic weight_request_valid,weight_request_ready,weight_valid,weight_ready;
    logic [2:0] weight_layer_id;
    logic [7:0] weight_k;
    logic [5:0] weight_channels;
    logic signed [7:0] weight_i8;
    kws_demo_source #(.DEMO_FILE(DEMO_FILE)) source (
        .clk(clk),.rst(rst),.enable(source_enable),
        .input_request_valid(input_request_valid),.input_request_ready(input_request_ready),
        .input_is_flatten(input_is_flatten),.input_count(input_count),
        .input_valid(input_valid),.input_ready(input_ready),.input_data(input_data),
        .weight_request_valid(weight_request_valid),.weight_request_ready(weight_request_ready),
        .weight_layer_id(weight_layer_id),.weight_k(weight_k),.weight_channels(weight_channels),
        .weight_valid(weight_valid),.weight_ready(weight_ready),.weight_i8(weight_i8),.fault(source_fault),.busy()
    );
    kws_board_self_test #(.EXPECTED_CLASS(EXPECTED_CLASS),.EXPECTED_SCORE(EXPECTED_SCORE),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) supervisor (
        .clk(clk),.rst(rst),.engine_start_ready(start_ready),.engine_start_valid(start_valid),
        .engine_done(engine_done),.engine_error(engine_error),.source_fault(source_fault),
        .class_valid(class_valid),.class_index(class_index),.class_score(class_score),
        .source_enable(source_enable),.busy(busy),.pass(pass),.fail(fail),
        .result_index(result_index),.result_score(result_score),.failure_code(failure_code),.run_cycles(run_cycles)
    );
    kws_inference_top #(.RESULT_PIPELINED(RESULT_PIPELINED),.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED),
        .CHECK_RESULT_ORDER(CHECK_RESULT_ORDER)) engine (
        .clk(clk),.rst(rst),.clk_cim(clk_cim),.rst_cim(rst_cim),
        .start_valid(start_valid),.start_ready(start_ready),.run_mode(RUN_FULL),
        .busy(),.done(engine_done),.error(engine_error),.error_code(),.current_op(),.op_done(),
        .class_valid(class_valid),.class_index(class_index),.class_score(class_score),
        .input_request_valid(input_request_valid),.input_request_ready(input_request_ready),
        .input_is_flatten(input_is_flatten),.input_count(input_count),
        .input_valid(input_valid),.input_ready(input_ready),.input_data(input_data),
        .weight_request_valid(weight_request_valid),.weight_request_ready(weight_request_ready),
        .weight_layer_id(weight_layer_id),.weight_k(weight_k),.weight_channels(weight_channels),
        .weight_valid(weight_valid),.weight_ready(weight_ready),.weight_i8(weight_i8),.source_error(source_fault),
        .read_valid(1'b0),.read_ready(),.read_base(15'd0),.read_count(16'd0),
        .read_out_valid(),.read_out_ready(1'b0),.read_data(),.read_last(),.read_done(),.read_error()
    );
endmodule
