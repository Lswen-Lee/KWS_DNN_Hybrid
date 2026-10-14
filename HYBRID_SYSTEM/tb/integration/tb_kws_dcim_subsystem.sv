`timescale 1ns/1ps
// Real backend -> real mailbox CDC -> real master -> full chip.
// Stimulus uses ONLY public ports. Hierarchical accesses below are observers,
// never a backdoor preload, forced response, or replacement arithmetic model.
module tb_kws_dcim_subsystem;
    logic clk_sys=0, clk_cim=0;
    integer cim_half_ps=9434, phase_ps=1300, seed=505;
    always #4 clk_sys=~clk_sys;
    initial begin
        if ($value$plusargs("CIM_HALF_PS=%d",cim_half_ps)) begin end
        if ($value$plusargs("PHASE_PS=%d",phase_ps)) begin end
        if (cim_half_ps<1 || phase_ps<0) $fatal(1,"invalid clock settings");
        #(phase_ps * 1ps);
        forever #(cim_half_ps * 1ps) clk_cim=~clk_cim;
    end

    // Testbench model of the OUTER reset owner. One common asynchronous
    // cause, local two-edge release. Holding one domain tests release skew.
    logic reset_request=1, hold_sys=1, hold_cim=1;
    logic [1:0] reset_sys_ff=2'b11, reset_cim_ff=2'b11;
    wire rst_sys=reset_sys_ff[1];
    wire rst_cim=reset_cim_ff[1];
    always @(posedge clk_sys or posedge reset_request)
        if(reset_request) reset_sys_ff<=2'b11;
        else if(hold_sys) reset_sys_ff<=2'b11;
        else reset_sys_ff<={reset_sys_ff[0],1'b0};
    always @(posedge clk_cim or posedge reset_request)
        if(reset_request) reset_cim_ff<=2'b11;
        else if(hold_cim) reset_cim_ff<=2'b11;
        else reset_cim_ff<={reset_cim_ff[0],1'b0};

    logic load_valid=0, load_ready, load_done, weight_valid=0, weight_ready;
    logic signed [7:0] weight_data=0;
    logic patch_valid=0, patch_ready, patch_done, activation_valid=0, activation_ready;
    logic [7:0] activation_data=0;
    logic result_valid, result_ready=0, result_last, busy, weights_ready, error;
    logic [3:0] filter_id;
    logic signed [31:0] result_data;
    logic source_error=0;
    kws_dcim_subsystem dut (.*);

    integer weights[0:11][0:107], acts[0:107], expected[0:11];
    integer accepted=0, starts=0, completions=0, responses=0;
    integer writes=0, physical_writes=0, write_responses=0, weight_inputs=0;
    integer cims=0, result_count=0, activation_inputs=0;
    integer expected_even=0, expected_odd=0;
    integer load_cases=0, patch_cases=0, reset_cases=0, fault_cases=0;
    integer sys_cycles=0, cim_cycles=0;
    bit random_stalls=0, pending_is_cim=0;
    logic [277:0] expected_command;
    wire [277:0] command_payload={dut.cmd_operation,dut.cmd_row_addr,
        dut.cmd_bank_addr,dut.cmd_weight,dut.cmd_activation_flat,dut.cmd_activation_is_a8};
    wire [277:0] master_payload={dut.master_operation,dut.master_row_addr,
        dut.master_bank_addr,dut.master_weight,dut.master_activation_flat,dut.master_activation_is_a8};
    wire [277:0] mailbox_payload={dut.u_cdc.command_operation_125,dut.u_cdc.command_row_addr_125,
        dut.u_cdc.command_bank_addr_125,dut.u_cdc.command_weight_125,
        dut.u_cdc.command_activation_125,dut.u_cdc.command_activation_is_a8_125};
    wire [45:0] response_payload={dut.rsp_data_valid,dut.rsp_error,
        dut.unused_rsp_sram_read_data,dut.rsp_even_raw_result,dut.rsp_odd_raw_result};
    logic [277:0] held_mailbox, held_command;
    logic [45:0] held_response;
    logic [36:0] held_result;
    bit previous_accept=0, mailbox_seen=0, command_stalled=0;
    bit response_stalled=0, result_stalled=0;
    logic [7:0] write_shift=0;

    // Fast-domain scoreboard: independent mapping and signed dot-product.
    always @(posedge clk_sys) begin : check_sys
        integer f,r,g,a,w;
        sys_cycles=sys_cycles+1;
        if(rst_sys) begin
            accepted=0; responses=0;
            previous_accept=0; mailbox_seen=0;
            command_stalled=0; response_stalled=0; result_stalled=0;
        end else begin
            // A mailbox update is allowed on the edge AFTER the monitor
            // observed acceptance (NBA update), not arbitrary non-IDLE edges.
            if(mailbox_seen && !previous_accept && mailbox_payload!==held_mailbox)
                $fatal(1,"mailbox changed without accepted command");
            held_mailbox=mailbox_payload; mailbox_seen=1;
            previous_accept=dut.cmd_valid && dut.cmd_ready;
            if(response_stalled && (!dut.rsp_valid || response_payload!==held_response))
                $fatal(1,"CDC response changed under backpressure");
            response_stalled=dut.rsp_valid && !dut.rsp_ready;
            held_response=response_payload;
            // source_error explicitly aborts the ready/valid contract.
            if(!source_error && !error) begin
                if(command_stalled && (!dut.cmd_valid || command_payload!==held_command))
                    $fatal(1,"backend command changed under backpressure");
                if(result_stalled && (!result_valid ||
                    {result_last,filter_id,result_data}!==held_result))
                    $fatal(1,"result changed under backpressure");
            end
            command_stalled=dut.cmd_valid && !dut.cmd_ready;
            held_command=command_payload;
            result_stalled=result_valid && !result_ready;
            held_result={result_last,filter_id,result_data};
            if(weight_valid && weight_ready) weight_inputs++;
            if(activation_valid && activation_ready) activation_inputs++;
            if(dut.cmd_valid && dut.cmd_ready) begin
                if(accepted!=responses) $fatal(1,"more than one outstanding command");
                expected_command=command_payload;
                accepted++;
                if(dut.cmd_operation==0) begin
                    if(writes>=1536) $fatal(1,"extra write command");
                    f=writes/128; r=writes%128;
                    w=r<108 ? weights[f][r]+128 : 128;
                    if(int'(dut.cmd_row_addr)!=r || int'(dut.cmd_bank_addr)!=f ||
                       int'(dut.cmd_weight)!=w) $fatal(1,"write mapping mismatch");
                    writes++; pending_is_cim=0;
                end else if(dut.cmd_operation==2) begin
                    if(cims>=48) $fatal(1,"extra CIM command");
                    g=cims/12; f=cims%12;
                    if(int'(dut.cmd_row_addr)!=g*32 || int'(dut.cmd_bank_addr)!=f ||
                       !dut.cmd_activation_is_a8) $fatal(1,"CIM scheduling mismatch");
                    expected_even=0; expected_odd=0;
                    for(r=0;r<32;r++) begin
                        a=g*32+r<108 ? acts[g*32+r] : 128;
                        w=g*32+r<108 ? weights[f][g*32+r]+128 : 128;
                        if(int'(dut.cmd_activation_flat[r*8 +: 8])!=a)
                            $fatal(1,"activation tile/padding mismatch");
                        expected_even+=a*(w/16); expected_odd+=a*(w%16);
                    end
                    cims++; pending_is_cim=1;
                end else $fatal(1,"unsupported backend operation");
            end
            if(dut.rsp_valid && dut.rsp_ready) begin
                if(responses>=accepted || completions!=accepted || dut.rsp_error)
                    $fatal(1,"unexpected/missing CDC completion");
                if(dut.rsp_data_valid!=pending_is_cim) $fatal(1,"response type mismatch");
                if(pending_is_cim) begin
                    if(int'(dut.rsp_even_raw_result)!=expected_even ||
                       int'(dut.rsp_odd_raw_result)!=expected_odd)
                        $fatal(1,"CDC raw data mismatch");
                end else write_responses++;
                responses++;
            end
            if(result_valid && result_ready) begin
                if(result_count>=12) $fatal(1,"extra result");
                if(int'(filter_id)!=result_count || result_data!==expected[result_count] ||
                   result_last!=(result_count==11))
                    $fatal(1,"result mismatch f=%0d got=%0d expected=%0d",
                           filter_id,result_data,expected[result_count]);
                result_count++;
            end
            if(load_done && (writes!=1536 || physical_writes!=1536 ||
                write_responses!=1536 || weight_inputs!=1296 || !weights_ready))
                $fatal(1,"load_done early");
            if(patch_done && (cims!=48 || activation_inputs!=108 || result_count!=12))
                $fatal(1,"patch_done early");
        end
    end

    // Slow-domain observer checks commands at their REAL acceptance edge,
    // and reconstructs the chip input nibbles without reading model memory.
    always @(posedge clk_cim) begin : check_cim
        integer f,r,w;
        cim_cycles++;
        if(rst_cim) begin starts=0; completions=0; write_shift=0; end
        else begin
            if(dut.master_start) begin
                if(starts>=accepted || starts!=completions || dut.master_busy || dut.master_done)
                    $fatal(1,"extra/overlapping master start");
                if(master_payload!==expected_command) $fatal(1,"CDC command payload mismatch");
                starts++;
            end
            if(dut.chip_clk_en && !dut.chip_mode_sel)
                write_shift={write_shift[3:0],dut.chip_din};
            if(dut.chip_write_en) begin
                if(physical_writes>=1536 || !dut.chip_wl_en || !dut.chip_sel_next || dut.chip_mode_sel)
                    $fatal(1,"invalid chip write control");
                f=physical_writes/128; r=physical_writes%128;
                w=r<108 ? weights[f][r]+128 : 128;
                if(int'(dut.chip_row_addr)!=r || int'(dut.chip_bank_addr)!=f || int'(write_shift)!=w)
                    $fatal(1,"physical write mismatch");
                physical_writes++;
            end
            if(dut.master_done) begin
                if(completions>=starts || dut.master_error) $fatal(1,"extra/error master completion");
                if(dut.master_result_valid!=pending_is_cim) $fatal(1,"master result type mismatch");
                if(pending_is_cim && (int'(dut.master_even_raw_result)!=expected_even ||
                    int'(dut.master_odd_raw_result)!=expected_odd)) $fatal(1,"chip raw result mismatch");
                completions++;
            end
        end
    end

    // order=0: fast releases first, order=1: slow releases first.
    // Can be called at a deliberately selected point inside an operation.
    task automatic reset_all(input integer order);
        reset_request=1; hold_sys=1; hold_cim=1;
        load_valid=0; weight_valid=0; patch_valid=0; activation_valid=0;
        result_ready=0; source_error=0;
        repeat(4) @(negedge clk_sys);
        reset_request=0;
        if(order==0) begin
            hold_sys=0;
            repeat(12) @(negedge clk_cim);
            hold_cim=0;
        end else begin
            hold_cim=0;
            repeat(12) @(negedge clk_sys);
            hold_sys=0;
        end
        wait(!rst_sys && !rst_cim);
        @(negedge clk_sys);
    endtask

    task automatic check_quiet;
        // At least 120 edges in BOTH domains, even when CIM is slower.
        fork
            begin
                repeat(120) begin
                    @(negedge clk_sys);
                    if(dut.cmd_valid || dut.rsp_valid || result_valid || patch_done ||
                       load_done || weights_ready || patch_ready || busy || error || accepted!=0)
                        $fatal(1,"stale sys activity after reset");
                end
            end
            begin
                repeat(120) begin
                    @(negedge clk_cim);
                    if(dut.master_start || dut.master_done || dut.master_busy || starts!=0 ||
                       dut.chip_write_en || dut.chip_output_en) $fatal(1,"stale CIM activity after reset");
                end
            end
        join
    endtask

    task automatic load_layer(input integer pattern);
        integer f,k,start_cycle;
        time start_time;
        for(f=0;f<12;f++) for(k=0;k<108;k++) begin
            if(pattern==0) weights[f][k]=((f*37+k*53)%256)-128;
            else if(f==0) weights[f][k]=-128;
            else if(f==1) weights[f][k]=127;
            else if(f==2) weights[f][k]=0;
            else weights[f][k]=int'($urandom_range(0,255))-128;
        end
        @(negedge clk_sys);
        writes=0; physical_writes=0; write_responses=0; weight_inputs=0;
        start_cycle=sys_cycles; start_time=$time;
        load_valid=1; patch_valid=1;
        #0.001;
        if(patch_ready) $fatal(1,"load priority not honored");
        do @(posedge clk_sys); while(!load_ready);
        @(negedge clk_sys); load_valid=0; patch_valid=0;
        for(f=0;f<12;f++) for(k=0;k<108;k++) begin
            if(random_stalls) repeat($urandom_range(0,2)) @(negedge clk_sys);
            weight_valid=1; weight_data=8'(weights[f][k]);
            do @(posedge clk_sys); while(!weight_ready);
            @(negedge clk_sys); weight_valid=0;
        end
        wait(load_done);
        @(negedge clk_sys);
        if(!weights_ready || error || accepted!=responses || starts!=accepted || completions!=starts)
            $fatal(1,"load not drained");
        load_cases++;
        $display("PASS load %0d: inputs=1296 chip_writes=1536 sys_cycles=%0d elapsed_ns=%0d",
                 load_cases,sys_cycles-start_cycle,$time-start_time);
    endtask

    task automatic prepare_patch(input integer pattern);
        for(integer k=0;k<108;k++) begin
            case(pattern)
                0: acts[k]=(k*71+3)%256;
                1: acts[k]=128;
                2: acts[k]=0;
                3: acts[k]=255;
                default: acts[k]=int'($urandom_range(0,255));
            endcase
        end
        for(integer f=0;f<12;f++) begin
            expected[f]=0;
            for(integer k=0;k<108;k++) expected[f]+=(acts[k]-128)*weights[f][k];
        end
        if($test$plusargs("CORRUPT_GOLDEN")) expected[0]++;
        @(negedge clk_sys);
        cims=0; result_count=0; activation_inputs=0;
        patch_valid=1; result_ready=0;
        do @(posedge clk_sys); while(!patch_ready);
        @(negedge clk_sys); patch_valid=0;
    endtask

    task automatic send_activations(input integer count);
        for(integer k=0;k<count;k++) begin
            if(random_stalls) repeat($urandom_range(0,3)) @(negedge clk_sys);
            activation_data=8'(acts[k]); activation_valid=1;
            do @(posedge clk_sys); while(!activation_ready);
            @(negedge clk_sys); activation_valid=0;
        end
    endtask

    task automatic run_patch(input integer pattern);
        integer start_cycle;
        time start_time;
        start_cycle=sys_cycles; start_time=$time;
        prepare_patch(pattern);
        result_ready=!random_stalls;
        send_activations(108);
        if(random_stalls) begin
            wait(result_valid);
            repeat(12) @(negedge clk_sys);
        end
        while(!patch_done) begin
            result_ready=!random_stalls || ($urandom_range(0,2)!=0);
            @(negedge clk_sys);
        end
        result_ready=0;
        if(result_count!=12 || cims!=48 || error || accepted!=responses || starts!=accepted)
            $fatal(1,"patch not complete/drained");
        patch_cases++;
        $display("PASS patch %0d: pattern=%0d stalls=%0d CIM=48 results=12 sys_cycles=%0d elapsed_ns=%0d",
                 patch_cases,pattern,random_stalls,sys_cycles-start_cycle,$time-start_time);
    endtask

    // Select real observed events, never force DUT state. Phase 4 source
    // error deliberately leaves 3 accepted results, demonstrating no rollback.
    task automatic interrupt_patch(input integer phase, input bit fault);
        integer starts_at_fault, accepted_at_fault;
        prepare_patch(0);
        send_activations(phase==4 ? 108 : 32);
        case(phase)
            0: while(!dut.u_cdc.new_request_50) @(negedge clk_cim);
            1: while(!dut.chip_output_en) @(negedge clk_cim);
            2: begin
                while(!dut.master_done) @(negedge clk_cim);
                @(posedge clk_cim); #0.001; // response written, not synchronized yet
            end
            3: while(!dut.rsp_valid) @(negedge clk_sys);
            4: begin
                wait(result_valid);
                repeat(8) @(negedge clk_sys);
                if(fault) begin
                    result_ready=1;
                    while(result_count<3) @(negedge clk_sys);
                    result_ready=0;
                end
            end
            default: $fatal(1,"invalid phase");
        endcase
        if(fault) begin
            // Align source_error to sys domain. For phase 2/3 inject right
            // now while still before the next sys sampling edge.
            source_error=1;
            starts_at_fault=starts; accepted_at_fault=accepted;
            repeat(3) @(negedge clk_sys);
            source_error=0;
            repeat(150) @(negedge clk_cim);
            if(!error || weights_ready || dut.cmd_valid || result_valid || patch_done || load_done ||
               accepted!=accepted_at_fault || starts>accepted_at_fault || starts<starts_at_fault)
                $fatal(1,"fault not contained");
            if(phase==4 && result_count!=3) $fatal(1,"partial output accounting wrong");
            fault_cases++;
            $display("PASS source_error phase=%0d accepted_results=%0d; sticky until reset",phase,result_count);
        end else begin
            reset_cases++;
            $display("REACHED reset phase=%0d",phase);
        end
        reset_all(phase%2);
        check_quiet();
        load_layer(phase%2);
        run_patch(phase);
        $display("PASS recovery phase=%0d fault=%0d",phase,fault);
    endtask

    initial begin : test_sequence
        integer random_dummy;
        if($value$plusargs("SEED=%d",seed)) begin end
        random_dummy=$urandom(seed);
        $display("S5-B sys=125MHz CIM_half_ps=%0d phase_ps=%0d seed=%0d",cim_half_ps,phase_ps,seed);
        // Offer a real load as soon as sys reset releases, WHILE slow reset
        // is still asserted. The command must wait safely in the mailbox.
        fork
            reset_all(0);
            begin wait(!rst_sys); load_layer(0); end
        join
        run_patch(0); run_patch(1);
        random_stalls=1;
        load_layer(1);
        run_patch(2); run_patch(3); run_patch(4);
        random_stalls=0;
        for(integer p=0;p<5;p++) interrupt_patch(p,0);
        for(integer p=0;p<5;p++) interrupt_patch(p,1);
        // Exercise the opposite release order with an immediate real load.
        fork
            reset_all(1);
            begin wait(rst_sys); wait(!rst_sys); load_layer(0); end
        join
        run_patch(4);
        $display("PASS S5-B SUMMARY loads=%0d patches=%0d results=%0d targeted_resets=%0d source_faults=%0d",
                 load_cases,patch_cases,patch_cases*12,reset_cases,fault_cases);
        $finish;
    end
    initial begin
        #50000000;
        $fatal(1,"S5-B watchdog timeout");
    end
endmodule
