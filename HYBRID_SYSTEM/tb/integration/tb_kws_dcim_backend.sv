`timescale 1ns/1ps
// Real pin master and full 16384-cell chip. No backdoor weight preload.
module tb_kws_dcim_backend;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    logic load_valid=0, load_ready, load_done, weight_valid=0, weight_ready;
    logic signed [7:0] weight_data=0;
    logic patch_valid=0, patch_ready, patch_done, activation_valid=0, activation_ready;
    logic [7:0] activation_data=0;
    logic result_valid, result_ready=0, result_last, busy, weights_ready, error;
    logic [3:0] filter_id;
    logic signed [31:0] result_data;
    logic source_error=0;
    logic cmd_valid, cmd_ready, cmd_activation_is_a8;
    logic [1:0] cmd_operation;
    logic [6:0] cmd_row_addr;
    logic [3:0] cmd_bank_addr;
    logic [7:0] cmd_weight;
    logic [255:0] cmd_activation_flat;
    logic rsp_valid=0, rsp_ready, rsp_data_valid=0, rsp_error=0;
    logic [17:0] rsp_even_raw_result=0, rsp_odd_raw_result=0;
    kws_dcim_backend dut (.*);

    // Test-only one-outstanding transport. It delays commands/responses but
    // obtains every successful result from the real pin master, never a model.
    logic gate=1, in_flight=0, pending=0;
    bit no_stalls=0;
    integer delay_left=0, cycles=0;
    logic inject_error=0, inject_missing_data=0;
    logic debug_mode=0, debug_start=0;
    logic [6:0] debug_row=0;
    logic [3:0] debug_pair=0;
    logic master_start, master_busy, master_done, master_result_valid, master_error;
    logic [7:0] master_read;
    logic [17:0] master_even, master_odd;
    logic chip_model_rst_n, chip_reset1, chip_reset2;
    logic [6:0] chip_row_addr;
    logic [3:0] chip_bank_addr, chip_din;
    logic chip_mode_sel,chip_wl_en,chip_write_en,chip_sense_en,chip_pre_en;
    logic chip_clk_en,chip_sel_next,chip_output_en,chip_nv_store,chip_nv_recall,chip_pd_en;
    logic chip_sume,chip_sumo;
    assign cmd_ready=!rst && !debug_mode && gate && !in_flight && !pending &&
                     !rsp_valid && !master_busy && !master_done;
    assign master_start=debug_mode ? debug_start : cmd_valid && cmd_ready;
    dcim_pin_master master (
        .clk(clk),.rst(rst),.start(master_start),
        .operation(debug_mode ? 2'd1 : cmd_operation),
        .command_row_addr(debug_mode ? debug_row : cmd_row_addr),
        .command_bank_addr(debug_mode ? debug_pair : cmd_bank_addr),
        .command_weight(cmd_weight),.activation_flat(cmd_activation_flat),
        .activation_is_a8(cmd_activation_is_a8),
        .command_burst_length(12'd0),.burst_weight_valid(1'b0),.burst_weight_data(8'd0),
        .burst_weight_ready(),.burst_weight_row_addr(),.burst_weight_bank_addr(),
        .busy(master_busy),.done(master_done),.result_valid(master_result_valid),
        .error(master_error),.sram_read_data(master_read),
        .even_raw_result(master_even),.odd_raw_result(master_odd),
        .chip_model_rst_n(chip_model_rst_n),.chip_reset1(chip_reset1),.chip_reset2(chip_reset2),
        .chip_row_addr(chip_row_addr),.chip_bank_addr(chip_bank_addr),
        .chip_mode_sel(chip_mode_sel),.chip_wl_en(chip_wl_en),.chip_write_en(chip_write_en),
        .chip_sense_en(chip_sense_en),.chip_pre_en(chip_pre_en),.chip_clk_en(chip_clk_en),
        .chip_sel_next(chip_sel_next),.chip_din(chip_din),.chip_output_en(chip_output_en),
        .chip_nv_store(chip_nv_store),.chip_nv_recall(chip_nv_recall),.chip_pd_en(chip_pd_en),
        .chip_sume(chip_sume),.chip_sumo(chip_sumo)
    );
    dcim_chip_pin_top chip (
        .clk(clk),.model_rst_n(chip_model_rst_n),.reset1(chip_reset1),.reset2(chip_reset2),
        .row_addr(chip_row_addr),.bank_addr(chip_bank_addr),.mode_sel(chip_mode_sel),
        .wl_en(chip_wl_en),.write_en(chip_write_en),.sense_en(chip_sense_en),
        .pre_en(chip_pre_en),.clk_en(chip_clk_en),.sel_next(chip_sel_next),.din(chip_din),
        .output_en(chip_output_en),.nv_store(chip_nv_store),.nv_recall(chip_nv_recall),
        .pd_en(chip_pd_en),.sume(chip_sume),.sumo(chip_sumo)
    );

    integer weights [0:11][0:107];
    integer acts [0:107];
    integer expected [0:11];
    integer write_count=0, cim_count=0, result_count=0, input_count=0, activation_count=0;
    integer write_responses=0, patch_start_cycle=0;
    integer exp_even=0, exp_odd=0;
    logic check_enabled=1, check_raw=0, stalled_result=0, stalled_cmd=0;
    logic [36:0] held_result;
    logic [276:0] held_cmd;
    integer seed=505;
    integer random_dummy;
    always @(negedge clk) gate=no_stalls || ($urandom_range(0,3)!=0);
    always @(posedge clk) begin : monitor
        integer f,r,g,a,w;
        cycles=cycles+1;
        if (!rst && check_enabled) begin
            if (stalled_result && {result_valid,result_last,filter_id,result_data} !==
                {1'b1,held_result}) $fatal(1,"result changed while stalled");
            stalled_result=result_valid && !result_ready;
            held_result={result_last,filter_id,result_data};
            if (stalled_cmd && (!cmd_valid ||
                {cmd_operation,cmd_row_addr,cmd_bank_addr,cmd_weight,cmd_activation_flat} !== held_cmd))
                $fatal(1,"command changed while stalled");
            stalled_cmd=cmd_valid && !cmd_ready;
            held_cmd={cmd_operation,cmd_row_addr,cmd_bank_addr,cmd_weight,cmd_activation_flat};
            if (weight_valid && weight_ready) input_count=input_count+1;
            if (activation_valid && activation_ready) activation_count=activation_count+1;
            if (cmd_valid && cmd_ready) begin
                if (cmd_operation==0) begin
                    f=write_count/128; r=write_count%128;
                    w=(r<108) ? weights[f][r]+128 : 128;
                    if (int'(cmd_row_addr)!=r || int'(cmd_bank_addr)!=f || int'(cmd_weight)!=w)
                        $fatal(1,"write mapping mismatch index=%0d",write_count);
                    write_count=write_count+1;
                end else if (cmd_operation==2) begin
                    g=cim_count/12; f=cim_count%12;
                    if (int'(cmd_row_addr)!=g*32 || int'(cmd_bank_addr)!=f || !cmd_activation_is_a8)
                        $fatal(1,"CIM schedule mismatch index=%0d",cim_count);
                    exp_even=0; exp_odd=0;
                    for(r=0;r<32;r=r+1) begin
                        a=(g*32+r<108) ? acts[g*32+r] : 128;
                        w=(g*32+r<108) ? weights[f][g*32+r]+128 : 128;
                        if(int'(cmd_activation_flat[r*8 +: 8])!=a) $fatal(1,"activation mapping mismatch");
                        exp_even=exp_even+a*(w/16);
                        exp_odd=exp_odd+a*(w%16);
                    end
                    check_raw=1; cim_count=cim_count+1;
                end else $fatal(1,"unexpected operation");
            end
            if (master_done && !debug_mode && check_raw) begin
                if (int'(master_even)!=exp_even || int'(master_odd)!=exp_odd)
                    $fatal(1,"raw even/odd mismatch");
                check_raw=0;
            end
            if (rsp_valid && rsp_ready && !rsp_data_valid && !rsp_error)
                write_responses=write_responses+1;
            if (load_done && (write_count!=1536 || write_responses!=1536 || input_count!=1296))
                $fatal(1,"load_done too early");
            if (result_valid && result_ready) begin
                if (int'(filter_id)!=result_count || result_data!==expected[result_count] ||
                    result_last!=(result_count==11))
                    $fatal(1,"result mismatch f=%0d got=%0d expected=%0d",filter_id,result_data,expected[result_count]);
                result_count=result_count+1;
            end
            if(patch_done && (result_count!=12 || cim_count!=48 || activation_count!=108)) $fatal(1,"patch_done too early");
        end
        if(rst) begin stalled_result=0; stalled_cmd=0; check_raw=0; end
    end

    always @(posedge clk) begin
        if(rst) begin
            in_flight<=0; pending<=0; rsp_valid<=0; delay_left<=0;
            rsp_error<=0; rsp_data_valid<=0;
        end else begin
            if(cmd_valid && cmd_ready) in_flight<=1;
            if(in_flight && master_done) begin
                in_flight<=0; pending<=1;
                delay_left<=no_stalls ? 0 : $urandom_range(0,4);
                rsp_error<=master_error || inject_error;
                rsp_data_valid<=master_result_valid && !inject_missing_data;
                rsp_even_raw_result<=master_even; rsp_odd_raw_result<=master_odd;
            end
            if(pending) begin
                if(delay_left==0) begin pending<=0; rsp_valid<=1; end
                else delay_left<=delay_left-1;
            end
            if(rsp_valid && rsp_ready) rsp_valid<=0;
        end
    end

    task automatic reset_all(input bit already_at_negedge=0);
        if(!already_at_negedge) @(negedge clk);
        rst=1; load_valid=0; patch_valid=0; weight_valid=0; activation_valid=0;
        result_ready=0; source_error=0; debug_mode=0; debug_start=0;
        inject_error=0; inject_missing_data=0;
        repeat(4) @(negedge clk);
        rst=0;
        @(negedge clk);
        if(weights_ready || patch_ready || busy || error) $fatal(1,"reset state incorrect");
    endtask

    task automatic load_layer(input integer pattern);
        integer f,k,start_cycle;
        for(f=0;f<12;f=f+1)
            for(k=0;k<108;k=k+1) begin
                if(pattern==0) weights[f][k]=((f*37+k*53)%256)-128;
                else if(f==0) weights[f][k]=-128;
                else if(f==1) weights[f][k]=127;
                else if(f==2) weights[f][k]=0;
                else weights[f][k]=int'($urandom_range(0,255))-128;
            end
        @(negedge clk);
        write_count=0; write_responses=0; input_count=0; start_cycle=cycles;
        load_valid=1;
        // Also request a patch: load must win without accepting the patch.
        patch_valid=1;
        #1;
        if(patch_ready) $fatal(1,"load/patch arbitration failed");
        do @(posedge clk); while(!load_ready);
        @(negedge clk); load_valid=0; patch_valid=0;
        for(f=0;f<12;f=f+1)
            for(k=0;k<108;k=k+1) begin
                if(!no_stalls) repeat($urandom_range(0,2)) @(negedge clk);
                weight_valid=1; weight_data=8'(weights[f][k]);
                do @(posedge clk); while(!weight_ready);
                @(negedge clk); weight_valid=0;
            end
        wait(load_done);
        @(negedge clk);
        if(!weights_ready || write_count!=1536) $fatal(1,"load failed");
        $display("PASS load pattern=%0d writes=%0d cycles=%0d",pattern,write_count,cycles-start_cycle);
    endtask

    task automatic readback_all;
        integer f,r,w;
        @(negedge clk); debug_mode=1;
        for(f=0;f<12;f=f+1)
            for(r=0;r<128;r=r+1) begin
                while(master_busy || master_done) @(negedge clk);
                debug_row=7'(r); debug_pair=4'(f); debug_start=1;
                @(negedge clk); debug_start=0;
                wait(master_done); #1;
                w=(r<108) ? weights[f][r]+128 : 128;
                if(!master_result_valid || master_error || int'(master_read)!=w)
                    $fatal(1,"SRAM readback mismatch pair=%0d row=%0d",f,r);
                @(negedge clk);
            end
        while(master_busy || master_done) @(negedge clk);
        debug_mode=0;
        $display("PASS SRAM readback: 1536 bytes including padding");
    endtask

    task automatic run_patch(input integer pattern);
        integer k,f;
        for(k=0;k<108;k=k+1) begin
            case(pattern)
                0: acts[k]=(k*71+3)%256;
                1: acts[k]=128;
                2: acts[k]=0;
                3: acts[k]=255;
                default: acts[k]=int'($urandom_range(0,255));
            endcase
        end
        for(f=0;f<12;f=f+1) begin
            expected[f]=0;
            for(k=0;k<108;k=k+1) expected[f]=expected[f]+(acts[k]-128)*weights[f][k];
        end
        if($test$plusargs("CORRUPT_GOLDEN")) expected[0]=expected[0]+1;
        @(negedge clk);
        cim_count=0; result_count=0; activation_count=0; patch_start_cycle=cycles; patch_valid=1;
        result_ready=no_stalls;
        do @(posedge clk); while(!patch_ready);
        @(negedge clk); patch_valid=0;
        for(k=0;k<108;k=k+1) begin
            if(!no_stalls) repeat($urandom_range(0,3)) @(negedge clk);
            activation_data=8'(acts[k]); activation_valid=1;
            do @(posedge clk); while(!activation_ready);
            @(negedge clk); activation_valid=0;
        end
        wait(result_valid);
        if(!no_stalls) repeat(8) @(negedge clk); // Deliberate backpressure on first result.
        while(!patch_done) begin
            result_ready=no_stalls || ($urandom_range(0,2)!=0);
            @(negedge clk);
        end
        result_ready=0;
        if(result_count!=12 || cim_count!=48 || error) $fatal(1,"patch counts wrong");
        $display("PASS patch pattern=%0d no_stalls=%0d CIM=%0d outputs=%0d cycles=%0d",pattern,no_stalls,cim_count,result_count,cycles-patch_start_cycle);
    endtask

    // Observe real activity to select the reset edge; never force DUT state.
    // 0: LOAD in flight, 1: SAMPLE about to latch, 2: correction valid pending
    // consumption, 3: EMIT with valid result held under backpressure.
    task automatic reset_during_patch(input integer phase);
        integer k,f,count;
        for(k=0;k<108;k=k+1) acts[k]=(k*19+7)%256;
        for(f=0;f<12;f=f+1) begin
            expected[f]=0;
            for(k=0;k<108;k=k+1) expected[f]+=(acts[k]-128)*weights[f][k];
        end
        @(negedge clk);
        cim_count=0; result_count=0; activation_count=0;
        patch_valid=1; result_ready=0;
        do @(posedge clk); while(!patch_ready);
        @(negedge clk); patch_valid=0;
        count=(phase==3) ? 108 : 32;
        for(k=0;k<count;k=k+1) begin
            activation_valid=1; activation_data=8'(acts[k]);
            do @(posedge clk); while(!activation_ready);
            @(negedge clk); activation_valid=0;
        end
        case(phase)
            0: begin
                while(!(master_busy && chip_mode_sel && chip_clk_en)) @(negedge clk);
            end
            1: begin
                while(!(master_busy && chip_output_en)) @(negedge clk);
            end
            2: begin
                while(!(dut.correction_pending && dut.correction_valid)) @(negedge clk);
            end
            3: begin
                while(!result_valid) @(negedge clk);
                repeat(20) begin
                    @(negedge clk);
                    if(!result_valid || result_ready || patch_done || result_count!=0)
                        $fatal(1,"EMIT reset precondition violated");
                end
            end
            default: $fatal(1,"invalid reset phase");
        endcase
        if(!busy || result_count!=0) $fatal(1,"reset target not active");
        reset_all(1); // Assert now, before the next sampling edge.
        // Longer than a normal master operation: no late completion may leak.
        repeat(120) begin
            @(negedge clk);
            if(cmd_valid || rsp_valid || master_done || result_valid || patch_done ||
               load_done || weights_ready || patch_ready || busy || error)
                $fatal(1,"stale activity after reset phase=%0d",phase);
        end
        $display("PASS reset phase=%0d reached; 120 clocks without stale result/done",phase);
    endtask

    initial begin
        if($value$plusargs("SEED=%d",seed)) begin end
        random_dummy=$urandom(seed);
        $display("S5-A seed=%0d (also set +verilator+seed+N for all process streams)",seed);
        reset_all();
        load_layer(0); readback_all(); run_patch(0); run_patch(1);
        load_layer(1); readback_all(); run_patch(2); run_patch(3); run_patch(4);
        // Source abort during active work is sticky and suppresses new traffic.
        check_enabled=0;
        @(negedge clk); patch_valid=1;
        @(negedge clk); patch_valid=0; source_error=1;
        @(negedge clk); source_error=0;
        repeat(3) @(negedge clk);
        if(!error || weights_ready || cmd_valid || result_valid || load_ready) $fatal(1,"source fault not sticky");
        reset_all();
        // Inject a transport error after a REAL write has finished.
        load_valid=1;
        @(negedge clk); load_valid=0; weight_valid=1; weight_data=-8'sd3;
        do @(posedge clk); while(!weight_ready);
        @(negedge clk); weight_valid=0; inject_error=1;
        wait(error);
        @(negedge clk);
        if(load_done || weights_ready || cmd_valid) $fatal(1,"write error accepted");
        reset_all();
        // Shared reset while a real write transaction is outstanding.
        load_valid=1;
        @(negedge clk); load_valid=0; weight_valid=1;
        do @(posedge clk); while(!weight_ready);
        @(negedge clk); weight_valid=0;
        wait(master_busy);
        reset_all();
        check_enabled=1;
        load_layer(0); run_patch(4);
        // Invalid CIM response must not be converted into a successful result.
        check_enabled=0;
        @(negedge clk); patch_valid=1; inject_missing_data=1;
        @(negedge clk); patch_valid=0;
        repeat(32) begin
            activation_valid=1; activation_data=8'd128;
            do @(posedge clk); while(!activation_ready);
            @(negedge clk);
        end
        activation_valid=0;
        wait(error);
        @(negedge clk);
        if(result_valid || patch_done || weights_ready) $fatal(1,"missing CIM data accepted");
        reset_all();
        $display("PASS S5-A real chip integration: 3 loads, 3072 readbacks, 6 patches, 288 CIM commands, 72 INT32 results; faults/reset recovery");
        check_enabled=1;
        no_stalls=1;
        $display("BEGIN no-extra-stall and targeted reset extension");
        load_layer(0);
        run_patch(0); run_patch(3);
        for(integer phase=0;phase<4;phase=phase+1) begin
            reset_during_patch(phase);
            load_layer(phase%2);
            run_patch(phase); // Full independent golden check after each reset.
        end
        $display("PASS extension: 5 loads, 6 successful patches/72 results, 4 targeted resets with reload/recompute recovery");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"S5-A watchdog timeout");
    end
endmodule
