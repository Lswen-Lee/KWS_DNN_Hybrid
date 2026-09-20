`timescale 1ns/1ps
// PYNQ-Z2 self-test, one 125-MHz clock. Vivado inserts the input/global buffers.
// Simulation shortens heartbeat only; watchdog counts clocks, not wall time.
// Raw result golden values are independent offline integer calculations.
(* use_dsp = "no" *)
module pe8_standalone_top #(
    parameter integer HEARTBEAT_BITS = 26,
    parameter integer TIMEOUT_CYCLES = 4096,
    parameter bit INJECT_GOLDEN_ERROR = 1'b0
) (
    input logic clk,
    input logic reset_btn,
    output logic [3:0] led
);
    typedef enum logic [3:0] {
        RESET_WAIT, PREPARE, START, FEED, WAIT_RESULT,
        CHECK, ACK, NEXT_TEST, PASS, FAIL
    } state_t;
    state_t state;
    // FPGA INIT provides power-up reset; button asserts asynchronously.
    // Only synchronizer stages see the asynchronous button.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] reset_sync = 2'b11;
    wire rst = reset_sync[1];
    always_ff @(posedge clk or posedge reset_btn) begin
        if (reset_btn) reset_sync <= 2'b11;
        else reset_sync <= {reset_sync[0],1'b0};
    end

    logic [HEARTBEAT_BITS-1:0] heartbeat;
    localparam integer WATCH_BITS = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES);
    logic [WATCH_BITS-1:0] watchdog;
    (* MARK_DEBUG = "TRUE" *) logic [2:0] test_id;
    (* MARK_DEBUG = "TRUE" *) logic [7:0] sample_index;
    (* MARK_DEBUG = "TRUE" *) logic [3:0] check_lane;
    // Debug registers retained for optional ILA, not external pins.
    /* verilator lint_off UNUSEDSIGNAL */
    (* MARK_DEBUG = "TRUE" *) logic [1:0] fail_reason;
    (* MARK_DEBUG = "TRUE" *) logic signed [31:0] fail_actual,fail_expected;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [1:0] gap_count;
    logic [2:0] hold_count;
    logic start, busy, done, sample_valid, sample_ready, result_valid, result_ready;
    logic [7:0] k_length, activation_u8;
    logic [11:0] lane_mask;
    logic [95:0] weight_vector_i8;
    logic [383:0] result_vector_s32, golden_bus;
    logic signed [31:0] actual_word, expected_word;

    function automatic [7:0] case_k(input logic [2:0] tid);
        case(tid)
            0: case_k=1;
            1,4,6: case_k=9;
            2,5: case_k=32;
            3: case_k=144;
            default: case_k=1;
        endcase
    endfunction
    function automatic [7:0] make_activation(input logic [7:0] idx,input logic [2:0] tid);
        make_activation = idx*8'd73 + 8'(tid)*8'd29;
    endfunction
    function automatic [7:0] make_weight(input logic [7:0] idx,
                                        input logic [2:0] tid,input logic [3:0] lane);
        // XOR 128 encodes unsigned_pattern-128 as two's-complement INT8.
        make_weight = (idx*8'd37 + 8'(lane)*8'd19 + 8'(tid)*8'd11) ^ 8'h80;
    endfunction
    function automatic [383:0] golden_vector(input logic [2:0] tid);
        case(tid)
            3'd0: golden_vector = 384'hffffd780ffffe100ffffea80fffff400fffffd80000007000000108000001a000000238000002d000000368000004000;
            3'd1: golden_vector = 384'hffffbf7cffff8e91ffff92a6ffffc5bb000041d0000045e500000afa00000f0f00001d24000021390000784e00007c63;
            3'd2: golden_vector = 384'h0000000000000000000000000000000000016a6000002c50ffff5540fffecd30fffed320ffff6f10ffff7500000134f0;
            3'd3: golden_vector = 384'hfffd3530fffe27f8fffd64c0fffd80880000785000030a1800036de0000290a800000070ffff033800007700000172c8;
            3'd4: golden_vector = 384'hffffeb64ffffe15c00005d540000604cffffe944ffffec3cffffbe34ffffc12cffffdc24ffffdf1c000043140000460c;
            3'd5: golden_vector = 384'hffffe52000000570fffff4c00001391000017160ffff78b0ffff5b00fffecf50fffeb1a0ffff61f0ffff444000011890;
            3'd6: golden_vector = 384'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
            default: golden_vector=0;
        endcase
    endfunction

    assign start = (state == START);
    assign sample_valid = (state == FEED) && (gap_count == 0);
    assign result_ready = (state == ACK);
    assign golden_bus = golden_vector(test_id);
    assign actual_word = $signed(result_vector_s32[check_lane*32 +: 32]);
    assign expected_word = $signed(golden_bus[check_lane*32 +: 32])
                         ^ ((INJECT_GOLDEN_ERROR && test_id==0 && check_lane==0) ? 32'sd1 : 32'sd0);
    assign led[0] = heartbeat[HEARTBEAT_BITS-1];
    assign led[1] = !rst && state!=RESET_WAIT && state!=PASS && state!=FAIL;
    assign led[2] = !rst && state==PASS;
    assign led[3] = !rst && state==FAIL;

    (* KEEP_HIERARCHY = "yes" *) pe8_core_12 core (
        .clk(clk), .rst(rst), .start(start), .k_length(k_length), .lane_mask(lane_mask),
        .busy(busy), .done(done), .sample_valid(sample_valid), .sample_ready(sample_ready),
        .activation_u8(activation_u8), .weight_vector_i8(weight_vector_i8),
        .result_valid(result_valid), .result_ready(result_ready),
        .result_vector_s32(result_vector_s32)
    );

    always_ff @(posedge clk) begin
        if(rst) heartbeat <= 0;
        else heartbeat <= heartbeat + 1'b1;
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=RESET_WAIT;
            test_id<=0; sample_index<=0; check_lane<=0;
            watchdog<=0; gap_count<=0; hold_count<=0;
            fail_reason<=0; fail_actual<=0; fail_expected<=0;
            k_length<=0; lane_mask<=0;
            activation_u8<=0; weight_vector_i8<=0;
        end else begin
            if(state==RESET_WAIT || (state==PREPARE && !busy) || state==PASS || state==FAIL)
                watchdog<=0;
            else watchdog<=watchdog+1'b1;
            if(state!=RESET_WAIT && state!=PASS && state!=FAIL &&
               watchdog==WATCH_BITS'(TIMEOUT_CYCLES-1)) begin
                state<=FAIL;
                fail_reason<=2; // timeout over the complete test transaction
            end else begin
                case(state)
                    RESET_WAIT: state<=PREPARE;
                    PREPARE: begin
                        k_length<=case_k(test_id);
                        lane_mask<=(test_id==6)?12'h000:((test_id==2)?12'h0ff:12'hfff);
                        sample_index<=0; check_lane<=0; gap_count<=0; hold_count<=0;
                        activation_u8<=make_activation(0,test_id);
                        for(integer j=0;j<12;j=j+1)
                            weight_vector_i8[j*8+:8]<=make_weight(0,test_id,4'(j));
                        if(!busy) state<=START;
                    end
                    START: state<=FEED;
                    FEED: begin
                        if(gap_count!=0) gap_count<=gap_count-1'b1;
                        if(sample_valid && sample_ready) begin
                            if(sample_index==k_length-8'd1) state<=WAIT_RESULT;
                            else begin
                                sample_index<=sample_index+1'b1;
                                activation_u8<=make_activation(sample_index+8'd1,test_id);
                                for(integer j=0;j<12;j=j+1)
                                    weight_vector_i8[j*8+:8]<=make_weight(sample_index+8'd1,test_id,4'(j));
                                if(test_id==4) gap_count<=2;
                            end
                        end
                    end
                    WAIT_RESULT: begin
                        if(result_valid) begin
                            if(test_id==5 && hold_count!=7) hold_count<=hold_count+1'b1;
                            else state<=CHECK;
                        end
                    end
                    CHECK: begin
                        if(!result_valid) begin state<=FAIL; fail_reason<=3; end
                        else if(actual_word!=expected_word) begin
                            state<=FAIL; fail_reason<=1;
                            fail_actual<=actual_word; fail_expected<=expected_word;
                        end else if(check_lane==11) state<=ACK;
                        else check_lane<=check_lane+1'b1;
                    end
                    ACK: if(result_valid) state<=NEXT_TEST;
                    NEXT_TEST: begin
                        if(done && !busy) begin
                            if(test_id==6) state<=PASS;
                            else begin test_id<=test_id+1'b1; state<=PREPARE; end
                        end
                    end
                    PASS: state<=PASS;
                    FAIL: state<=FAIL;
                    default: begin state<=FAIL; fail_reason<=3; end
                endcase
            end
        end
    end
endmodule
