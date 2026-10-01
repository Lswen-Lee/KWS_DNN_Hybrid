`timescale 1ns/1ps
module postprocess_self_test #(parameter bit POSTPROCESS_PIPELINED=0) (
    input logic clk, rst,
    output wire busy,
    output logic pass, fail
);
    // 76 valid model channels x 8 numerical patterns = 608 transactions.
    localparam logic [9:0] LAST_INDEX = 10'd607;
    typedef enum logic [1:0] {LOAD, SEND, WAIT_RESULT, FINISH} state_t;
    state_t state;
    logic [9:0] index;
    wire [50:0] vector_data;
    postprocess_vectors vectors (.index(index), .data(vector_data));
    logic signed [31:0] operand_q;
    logic [2:0] layer_q;
    logic [4:0] channel_q;
    logic relu_q, last_q, error_q;
    logic [7:0] expected_q;
    logic [15:0] watchdog;
    logic [3:0] phase;
    wire ready, valid, last_out, error_out;
    wire [7:0] data_out;
    wire [4:0] channel_out;
    wire out_ready = phase[3]; // Stall outputs for 8 of every 16 clocks.
    assign busy = !rst && state != FINISH;
    pe_pot_result_stream #(.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) dut (
        .clk(clk), .rst(rst), .in_valid(!rst && state==SEND), .in_ready(ready),
        .accumulator(operand_q), .layer_id(layer_q), .channel_id(channel_q),
        .relu_enable(relu_q), .in_last(last_q), .in_error(error_q),
        .out_valid(valid), .out_ready(out_ready), .output_uint8(data_out),
        .out_channel_id(channel_out), .out_last(last_out), .out_error(error_out));
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=LOAD; index<=0; pass<=0; fail<=0; watchdog<=0; phase<=0;
            operand_q<=0; layer_q<=0; channel_q<=0; relu_q<=0;
            last_q<=0; error_q<=0; expected_q<=0;
        end else begin
            phase<=phase+1'b1;
            if(state!=FINISH) watchdog<=watchdog+1'b1;
            case(state)
                LOAD: begin
                    {operand_q,layer_q,channel_q,relu_q,last_q,error_q,expected_q}
                        <=vector_data;
                    state<=SEND;
                end
                SEND: if(ready) state<=WAIT_RESULT;
                WAIT_RESULT: if(valid && out_ready) begin
                    if(data_out!=expected_q || channel_out!=channel_q ||
                       last_out!=last_q || error_out!=error_q) begin
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
