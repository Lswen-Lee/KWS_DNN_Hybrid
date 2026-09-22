`timescale 1ns/1ps
// Registered source, channel-major weights. Same workload for all variants.
// Golden ROM is independent of the engine implementation.
module pe_board_self_test #(
    parameter bit PE8_MODE=0,
    parameter bit RESULT_PIPELINED=0,
    parameter bit POT_MODEL=0,
    parameter integer TIMEOUT_CYCLES=1000000,
    // Intentionally unused when the legacy (non-PoT) branch is elaborated.
    /* verilator lint_off UNUSEDPARAM */
    parameter bit POSTPROCESS_PIPELINED=1'b1
    /* verilator lint_on UNUSEDPARAM */
) (
    input logic clk, rst,
    output wire busy,
    output logic pass, fail,
    output logic [3:0] failure_code,
    output logic [1:0] test_id,
    output logic [6:0] checked_outputs
);
    typedef enum logic [3:0] {LOAD, W_PREP, W_SEND, LOAD_WAIT,
        COMPUTE, REPLAY, A_PREP, A_SEND, FINISH, NEXT, PASSED, FAILED} state_t;
    state_t state;
    logic [7:0] load_k;
    logic [5:0] load_channels;
    logic [7:0] k_index;
    logic [5:0] channel_index, received;
    logic [5:0] next_base;
    logic [7:0] activation_u8;
    logic signed [7:0] weight_i8;
    logic [31:0] watchdog;
    wire load_ready, load_busy, load_done, load_error, layer_ready;
    wire weight_ready, compute_ready, compute_busy, compute_done, compute_error;
    wire replay_valid, activation_ready, out_valid, out_group_last, out_error;
    wire [7:0] replay_k;
    wire [4:0] replay_channel_base, out_channel_id;
    wire signed [31:0] out_data, expected_data;
    wire load_valid = !rst && state==LOAD;
    wire weight_valid = !rst && state==W_SEND;
    wire compute_valid = !rst && state==COMPUTE;
    wire replay_ready = !rst && state==REPLAY;
    wire activation_valid = !rst && state==A_SEND;
    // Deliberately exercise downstream backpressure, including last outputs.
    wire out_ready = !rst && !pass && !fail && watchdog[2:0]!=0;
    assign busy = !rst && !pass && !fail;
    generate if(!POT_MODEL) begin : g_legacy
    pe_memory_engine #(.PE8_MODE(PE8_MODE),.RESULT_PIPELINED(RESULT_PIPELINED)) engine (
        .clk(clk),.rst(rst),.load_valid(load_valid),.load_ready(load_ready),
        .load_k(load_k),.load_channels(load_channels),.load_busy(load_busy),
        .load_done(load_done),.load_error(load_error),.layer_ready(layer_ready),
        .weight_valid(weight_valid),.weight_ready(weight_ready),.weight_i8(weight_i8),
        .compute_valid(compute_valid),.compute_ready(compute_ready),.compute_busy(compute_busy),
        .compute_done(compute_done),.compute_error(compute_error),
        .replay_valid(replay_valid),.replay_ready(replay_ready),.replay_k(replay_k),
        .replay_channel_base(replay_channel_base),.activation_valid(activation_valid),
        .activation_ready(activation_ready),.activation_u8(activation_u8),
        .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),
        .out_channel_id(out_channel_id),.out_group_last(out_group_last),.out_error(out_error)
    );
    pe_board_golden golden (.test_id(test_id),.channel_id(out_channel_id),.value(expected_data));
    end else begin : g_pot
        wire [7:0] out_uint8;
        pe_pot_engine #(.PE8_MODE(PE8_MODE),.RESULT_PIPELINED(RESULT_PIPELINED),
            .POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) engine (
            .compute_layer_id(test_id==0 ? 3'd0 : (test_id==1 ? 3'd3 : 3'd4)),
            .relu_enable(test_id!=2), .out_data(out_uint8), .*
        );
        assign out_data=$signed({24'd0,out_uint8});
        pe_board_golden_pot golden (.test_id(test_id),.channel_id(out_channel_id),.value(expected_data));
    end endgenerate
    function automatic [7:0] weight_value(input [5:0] c, input [7:0] k, input [1:0] t);
        weight_value = 8'(32'(c)*71 + 32'(k)*29 + 128 + 32'(t)*17);
    endfunction
    function automatic [7:0] activation_value(input [7:0] k, input [1:0] t);
        activation_value = 8'(32'(k)*43 + 17 + 32'(t)*61);
    endfunction
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=LOAD; test_id<=0; load_k<=9; load_channels<=12;
            k_index<=0; channel_index<=0; received<=0; next_base<=0;
            activation_u8<=0; weight_i8<=0; watchdog<=0;
            pass<=0; fail<=0; failure_code<=0; checked_outputs<=0;
        end else if(!pass && !fail) begin
            watchdog<=watchdog+1;
            if(out_valid && out_ready) begin
                received<=received+1;
                checked_outputs<=checked_outputs+1;
            end
            case(state)
                LOAD: if(load_ready) begin k_index<=0; channel_index<=0; state<=W_PREP; end
                W_PREP: begin weight_i8<=weight_value(channel_index,k_index,test_id); state<=W_SEND; end
                W_SEND: if(weight_ready) begin
                    if(k_index==load_k-1'b1) begin
                        k_index<=0;
                        if(channel_index==load_channels-1'b1) state<=LOAD_WAIT;
                        else begin channel_index<=channel_index+1'b1; state<=W_PREP; end
                    end else begin k_index<=k_index+1'b1; state<=W_PREP; end
                end
                LOAD_WAIT: if(load_done && layer_ready) state<=COMPUTE;
                COMPUTE: if(compute_ready) begin received<=0; next_base<=0; state<=REPLAY; end
                REPLAY: if(replay_valid) begin
                    if(replay_k!=load_k || {1'b0,replay_channel_base}!=next_base) begin
                        fail<=1; failure_code<=4; state<=FAILED;
                    end else begin
                        next_base<=next_base+12; k_index<=0; state<=A_PREP;
                    end
                end
                A_PREP: begin activation_u8<=activation_value(k_index,test_id); state<=A_SEND; end
                A_SEND: if(activation_ready) begin
                    if(k_index==load_k-1'b1) begin
                        if(next_base>=load_channels) state<=FINISH;
                        else state<=REPLAY;
                    end else begin k_index<=k_index+1'b1; state<=A_PREP; end
                end
                FINISH: if(compute_done) begin
                    if(received!=load_channels) begin fail<=1; failure_code<=5; state<=FAILED; end
                    else state<=NEXT;
                end
                NEXT: begin
                    if(test_id==2) begin pass<=1; state<=PASSED; end
                    else begin
                        test_id<=test_id+1'b1;
                        load_k <= test_id==0 ? 8'd144 : 8'd32;
                        load_channels <= test_id==0 ? 6'd32 : 6'd8;
                        state<=LOAD;
                    end
                end
                default: begin fail<=1; failure_code<=6; state<=FAILED; end
            endcase
            // Overrides above transitions on any error; sticky until reset.
            if(out_valid && out_ready && (out_error || received>=load_channels ||
               {1'b0,out_channel_id}!=received || out_data!==expected_data ||
               out_group_last!=(out_channel_id==11 || out_channel_id==23 ||
                                 {1'b0,out_channel_id}==load_channels-1'b1))) begin
                pass<=0; fail<=1; failure_code<=1; state<=FAILED;
            end
            if(load_error || compute_error) begin pass<=0; fail<=1; failure_code<=2; state<=FAILED; end
            if(watchdog>=32'(TIMEOUT_CYCLES-1)) begin pass<=0; fail<=1; failure_code<=3; state<=FAILED; end
        end
    end
endmodule
