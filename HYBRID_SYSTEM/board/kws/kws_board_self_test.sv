`timescale 1ns/1ps
// One run per reset. Captures unbuffered class_valid on its active edge.
module kws_board_self_test #(
    parameter logic [2:0] EXPECTED_CLASS=3'd6,
    parameter logic [7:0] EXPECTED_SCORE=8'd183,
    parameter integer TIMEOUT_CYCLES=125000000
) (
    input logic clk, rst, engine_start_ready, engine_done, engine_error,
    input logic source_fault, class_valid,
    input logic [2:0] class_index,
    input logic [7:0] class_score,
    output logic engine_start_valid, source_enable, busy, pass, fail,
    output logic [2:0] result_index,
    output logic [7:0] result_score,
    output logic [3:0] failure_code,
    output logic [31:0] run_cycles
);
    typedef enum logic [1:0] {START, RUN, PASS, FAIL} state_t;
    state_t state;
    assign engine_start_valid = !rst && state==START;
    assign source_enable = !rst && (state==START || state==RUN);
    assign busy = source_enable;
    assign pass = !rst && state==PASS;
    assign fail = !rst && state==FAIL;
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=START; run_cycles<=0; result_index<=0; result_score<=0; failure_code<=0;
        end else if(state==START || state==RUN) begin
            run_cycles<=run_cycles+1'b1;
            if(class_valid) begin result_index<=class_index; result_score<=class_score; end
            if(engine_error || source_fault) begin
                state<=FAIL; failure_code<=source_fault ? 4'd2 : 4'd1;
            end else if(state==START && (engine_done || class_valid)) begin
                state<=FAIL; failure_code<=4;
            end else if(state==RUN && (engine_done || class_valid)) begin
                if(!(engine_done && class_valid)) begin state<=FAIL; failure_code<=4; end
                else if(class_index!=EXPECTED_CLASS || class_score!=EXPECTED_SCORE) begin state<=FAIL; failure_code<=5; end
                else state<=PASS;
            end else if(run_cycles>=32'(TIMEOUT_CYCLES-1)) begin state<=FAIL; failure_code<=3; end
            else if(state==START && engine_start_ready) state<=RUN;
        end
    end
endmodule
