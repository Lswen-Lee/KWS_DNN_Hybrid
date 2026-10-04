`timescale 1ns/1ps
// Protocol-only unit test. End-to-end numeric verification is a separate TB
// using the real RAM/PE/Pool, not these controlled completion signals.
module tb_layer_controller;
    import kws_system_pkg::*;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic start_valid=0,start_ready,busy,done,error,op_done;
    inference_mode_t run_mode=RUN_FRONTEND;
    layer_error_t error_code;
    logic [3:0] current_op;
    logic input_request_valid,input_request_ready=0,input_is_flatten;
    logic [15:0] input_count;
    logic weight_request_valid,weight_request_ready=0,source_error=0;
    layer_descriptor_t active_descriptor;
    logic input_stream_enable,weight_stream_enable;
    logic load_valid,load_ready=0,load_done=0,load_error=0;
    logic weight_load_valid,weight_load_ready=0,weight_load_done=0,weight_load_error=0;
    logic pe_cmd_valid,pe_cmd_ready=0,pe_done=0,pe_error=0;
    logic pool_valid,pool_ready=0,pool_done=0,pool_error=0;
    logic path_busy=0,path_fault=0;
    integer cycles=0,successes=0,failures=0,operations=0;
    layer_controller dut (.*);
    always @(posedge clk) begin
        cycles++;
        if(cycles>10000) $fatal(1,"Controller watchdog");
        if(!rst) begin
            if(done && error) $fatal(1,"Two terminal statuses");
            if(busy && start_ready) $fatal(1,"Start ready while busy");
            if(int'(load_valid)+int'(weight_load_valid)+int'(pe_cmd_valid)+int'(pool_valid)>1)
                $fatal(1,"Multiple path commands");
            if(op_done) operations++;
        end
    end
    task automatic reset_all;
        @(negedge clk);rst=1; start_valid=0;
        input_request_ready=0;weight_request_ready=0;source_error=0;
        load_ready=0;load_done=0;load_error=0;weight_load_ready=0;weight_load_done=0;weight_load_error=0;
        pe_cmd_ready=0;pe_done=0;pe_error=0;pool_ready=0;pool_done=0;pool_error=0;path_busy=0;path_fault=0;
        repeat(2) @(negedge clk);rst=0;@(negedge clk);
        if(!start_ready || busy || error_code!=LERR_NONE) $fatal(1,"Reset failed");
    endtask
    task automatic launch(input inference_mode_t mode);
        @(negedge clk);run_mode=mode;start_valid=1;
        @(negedge clk);start_valid=0;run_mode=RUN_FULL; // Must have been saved.
    endtask
    // Wait and deliberately hold a command with ready=0 before accepting it.
    task automatic accept_command(input integer kind);
        bit valid_now;
        layer_descriptor_t saved;
        valid_now=0;
        while(!valid_now) begin
            @(negedge clk);
            case(kind)
                0: valid_now=input_request_valid;
                1: valid_now=load_valid;
                2: valid_now=weight_request_valid;
                3: valid_now=weight_load_valid;
                4: valid_now=pe_cmd_valid;
                5: valid_now=pool_valid;
            endcase
        end
        saved=active_descriptor;
        repeat(4) begin
            @(negedge clk);
            case(kind)
                0: valid_now=input_request_valid;
                1: valid_now=load_valid;
                2: valid_now=weight_request_valid;
                3: valid_now=weight_load_valid;
                4: valid_now=pe_cmd_valid;
                5: valid_now=pool_valid;
            endcase
            if(!valid_now || active_descriptor!==saved) $fatal(1,"Command not stable kind=%0d",kind);
        end
        case(kind)
            0: input_request_ready=1;
            1: load_ready=1;
            2: weight_request_ready=1;
            3: weight_load_ready=1;
            4: pe_cmd_ready=1;
            5: pool_ready=1;
        endcase
        @(negedge clk);
        input_request_ready=0;load_ready=0;weight_request_ready=0;
        weight_load_ready=0;pe_cmd_ready=0;pool_ready=0;
    endtask
    task automatic input_stage;
        accept_command(0);
        if(input_is_flatten!=(current_op==7) || input_count!=(current_op==7 ? 16'd144 : 16'd8064))
            $fatal(1,"Frozen input mode/count incorrect");
        accept_command(1);
        repeat(5) begin
            @(negedge clk);
            if(!input_stream_enable || weight_request_valid || pe_cmd_valid || pool_valid)
                $fatal(1,"Input advanced before completion");
        end
        load_done=1;@(negedge clk);load_done=0;
    endtask
    task automatic weights;
        accept_command(2);accept_command(3);
        repeat(5) begin
            @(negedge clk);
            if(!weight_stream_enable || pe_cmd_valid) $fatal(1,"Weight advanced early");
        end
        weight_load_done=1;@(negedge clk);weight_load_done=0;
    endtask
    task automatic operation(input bit is_pool,input integer index);
        accept_command(is_pool ? 5 : 4);
        // Wrong backend's completion must not advance this operation.
        pe_done=is_pool;pool_done=!is_pool;
        repeat(5) begin
            @(negedge clk);
            if(int'(current_op)!=index || op_done || done) $fatal(1,"Wrong done advanced operation");
        end
        pe_done=!is_pool;pool_done=is_pool;
        @(negedge clk);pe_done=0;pool_done=0;
        if(!op_done || int'(current_op)!=index) $fatal(1,"Missing operation completion");
    endtask
    task automatic check_failure(input layer_error_t expected);
        while(!error) @(negedge clk);
        if(error_code!=expected || done || !busy) $fatal(1,"Wrong failure code");
        @(negedge clk);
        repeat(4) begin
            if(error || start_ready || load_valid || weight_load_valid || pe_cmd_valid || pool_valid ||
               input_stream_enable || weight_stream_enable) $fatal(1,"Failure did not lock/pulse");
            @(negedge clk);
        end
        failures++;
    endtask
    initial begin
        reset_all();path_busy=1;#1;if(start_ready) $fatal(1,"Busy path accepted start");path_busy=0;
        launch(RUN_FRONTEND);input_stage();operation(1,0);weights();operation(0,1);operation(1,2);
        while(!done) @(negedge clk);if(busy) $fatal(1,"Done still busy");successes++;
        @(negedge clk);if(done) $fatal(1,"Done not pulse");
        launch(RUN_FC_TAIL);input_stage();weights();operation(0,7);weights();operation(0,8);
        while(!done) @(negedge clk);successes++;
        reset_all();launch(RUN_FULL);check_failure(LERR_MODE);
        reset_all();launch(inference_mode_t'(3));check_failure(LERR_MODE);
        reset_all();launch(RUN_FRONTEND);accept_command(0);source_error=1;check_failure(LERR_SOURCE);
        reset_all();launch(RUN_FRONTEND);accept_command(0);accept_command(1);
        load_error=1;load_done=1;check_failure(LERR_INPUT); // Error wins over done.
        reset_all();launch(RUN_FC_TAIL);input_stage();accept_command(2);accept_command(3);
        weight_load_error=1;weight_load_done=1;check_failure(LERR_WEIGHT);
        reset_all();launch(RUN_FRONTEND);input_stage();accept_command(5);
        pool_error=1;pool_done=1;check_failure(LERR_OPERATION);
        reset_all();launch(RUN_FC_TAIL);input_stage();weights();accept_command(4);
        pe_error=1;pe_done=1;check_failure(LERR_OPERATION);
        reset_all();launch(RUN_FRONTEND);accept_command(0);path_fault=1;check_failure(LERR_PATH);
        // Descriptor corruption is fault injection only, never a numeric bypass.
        reset_all();launch(RUN_FRONTEND);
        force dut.rom_valid=1'b0;
        input_stage();check_failure(LERR_DESCRIPTOR);release dut.rom_valid;
        // Reset cancels an outstanding input stream; no stale done may survive.
        reset_all();launch(RUN_FRONTEND);accept_command(0);accept_command(1);reset_all();
        if(operations!=5 || successes!=2 || failures!=9) $fatal(1,"Unit coverage missing");
        $display("PASS layer_controller successes=%0d operations=%0d failures=%0d",successes,operations,failures);
        $finish;
    end
endmodule
