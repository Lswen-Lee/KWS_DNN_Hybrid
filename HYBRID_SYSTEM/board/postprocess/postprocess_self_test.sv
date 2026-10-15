`timescale 1ns/1ps
module postprocess_self_test #(parameter bit POSTPROCESS_PIPELINED=0) (
    input logic clk, rst,
    output wire busy,
    output logic pass, fail
);
    // 608 quant tests + 1008 CHW pixels + 32 FC2 scores.
    localparam logic [10:0] LAST_INDEX = 11'd1647;
    typedef enum logic [2:0] {LOAD, SEND, WAIT_RESULT, CHECK_TAIL, FINISH} state_t;
    state_t state;
    logic [10:0] index;
    wire [106:0] vector_data;
    postprocess_vectors vectors (.index(index), .data(vector_data));
    logic signed [31:0] operand_q;
    logic [2:0] layer_q;
    logic [4:0] channel_q;
    logic relu_q, last_q, error_q;
    logic [7:0] expected_q;
    logic [1:0] mode_q;
    logic first_q, tail_valid_q, tail_done_q;
    logic [7:0] width_q, height_q, tail_data_q;
    logic [4:0] channels_q, tail_channel_q;
    logic [6:0] tail_y_q, tail_x_q;
    logic [2:0] class_q;
    wire pool_valid, pool_done, argmax_valid;
    wire [7:0] pool_data, maximum_value;
    wire [4:0] pool_channel;
    wire [6:0] pool_y, pool_x;
    wire [2:0] class_index;
    logic [15:0] watchdog;
    logic [3:0] phase;
    wire ready, valid, last_out, error_out;
    wire [7:0] data_out;
    wire [4:0] channel_out;
    wire out_ready = phase[3]; // Stall outputs for 8 of every 16 clocks.
    assign busy = !rst && state != FINISH;
    (* KEEP_HIERARCHY = "yes" *) pot_result_stream #(.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) dut (
        .clk(clk), .rst(rst), .in_valid(!rst && state==SEND), .in_ready(ready),
        .accumulator(operand_q), .layer_id(layer_q), .channel_id(channel_q),
        .relu_enable(relu_q), .in_last(last_q), .in_error(error_q),
        .out_valid(valid), .out_ready(out_ready), .output_uint8(data_out),
        .out_channel_id(channel_out), .out_last(last_out), .out_error(error_out), .empty());
    (* KEEP_HIERARCHY = "yes" *) postprocess_tail tail (
        .clk(clk),.rst(rst),.mode(mode_q),
        .accept(valid && out_ready),.frame_start(first_q),
        .argmax_clear(state==SEND && first_q && mode_q==2),
        .data_in(data_out),.width(width_q),.height(height_q),.channels(channels_q),
        .pool_valid(pool_valid),.pool_done(pool_done),.pool_data(pool_data),
        .pool_channel(pool_channel),.pool_y(pool_y),.pool_x(pool_x),
        .argmax_valid(argmax_valid),.class_index(class_index),.maximum_value(maximum_value));
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=LOAD; index<=0; pass<=0; fail<=0; watchdog<=0; phase<=0;
            operand_q<=0; layer_q<=0; channel_q<=0; relu_q<=0;
            last_q<=0; error_q<=0; expected_q<=0;
            mode_q<=0; first_q<=0; width_q<=0; height_q<=0; channels_q<=0;
            tail_valid_q<=0; tail_data_q<=0; tail_channel_q<=0;
            tail_y_q<=0; tail_x_q<=0; tail_done_q<=0; class_q<=0;
        end else begin
            phase<=phase+1'b1;
            if(state!=FINISH) watchdog<=watchdog+1'b1;
            case(state)
                LOAD: begin
                    {operand_q,layer_q,channel_q,relu_q,last_q,error_q,expected_q,
                     mode_q,first_q,width_q,height_q,channels_q,tail_valid_q,tail_data_q,
                     tail_channel_q,tail_y_q,tail_x_q,tail_done_q,class_q}
                        <=vector_data;
                    state<=SEND;
                end
                SEND: if(ready) state<=WAIT_RESULT;
                WAIT_RESULT: if(valid && out_ready) begin
                    if(data_out!=expected_q || channel_out!=channel_q ||
                       last_out!=last_q || error_out!=error_q) begin
                        fail<=1; state<=FINISH;
                    end else state<=CHECK_TAIL;
                end
                CHECK_TAIL: begin
                    if(pool_valid != (mode_q==1 && tail_valid_q) ||
                       argmax_valid != (mode_q==2 && tail_valid_q) ||
                       pool_done != (mode_q==1 && tail_done_q) ||
                       (pool_valid && {pool_data,pool_channel,pool_y,pool_x} !=
                                      {tail_data_q,tail_channel_q,tail_y_q,tail_x_q}) ||
                       (argmax_valid && {maximum_value,class_index} != {tail_data_q,class_q})) begin
                        fail<=1; state<=FINISH;
                    end else if(index==LAST_INDEX) begin pass<=1; state<=FINISH; end
                    else begin index<=index+1'b1; state<=LOAD; end
                end
                FINISH: ;
                default: begin fail<=1; state<=FINISH; end
            endcase
            if(state!=FINISH && (&watchdog)) begin
                pass<=0; fail<=1; state<=FINISH;
            end
        end
    end
endmodule
