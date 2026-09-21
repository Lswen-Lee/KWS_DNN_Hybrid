`timescale 1ns/1ps
// ONLY public engine ports: real loader/RAM/controllers/MAC/correction.
module tb_pe_memory_engine;
    parameter bit PE8_MODE=1;
    parameter bit RESULT_PIPELINED=0;
    parameter integer INPUT_ZERO_POINT=127;
    logic clk=0, rst=1;
    always #4 clk=~clk;
    logic load_valid=0, load_ready;
    logic [7:0] load_k=0;
    logic [5:0] load_channels=0;
    logic load_busy, load_done, load_error, layer_ready;
    logic weight_valid=0, weight_ready;
    logic signed [7:0] weight_i8=0;
    logic compute_valid=0, compute_ready, compute_busy, compute_done, compute_error;
    logic replay_valid, replay_ready=0;
    logic [7:0] replay_k;
    logic [4:0] replay_channel_base;
    logic activation_valid=0, activation_ready;
    logic [7:0] activation_u8=0;
    logic out_valid, out_ready=0;
    logic signed [31:0] out_data;
    logic [4:0] out_channel_id;
    logic out_group_last, out_error;
    pe_memory_engine #(.PE8_MODE(PE8_MODE), .RESULT_PIPELINED(RESULT_PIPELINED), .INPUT_ZERO_POINT(INPUT_ZERO_POINT)) dut (.*);

    // Passive one-cycle reference for the elastic operand stage. No force,
    // no bypass: all stimulus still enters through public engine interfaces.
    logic expected_operand_valid=0;
    logic [104:0] expected_operand_payload;
    integer operand_transfers=0;
    always @(posedge clk) begin
        if (rst) expected_operand_valid=0;
        else if (dut.read_align_ready) begin
            expected_operand_valid=dut.read_align_valid;
            if (dut.read_align_valid) begin
                expected_operand_payload={dut.read_align_last,dut.read_align_a,dut.read_align_w};
                operand_transfers=operand_transfers+1;
            end
        end
        #1;
        if (dut.align_out_valid !== expected_operand_valid)
            $fatal(1,"operand valid/reset/latency mismatch");
        if (expected_operand_valid &&
            {dut.align_out_last,dut.aligned_a,dut.aligned_w} !== expected_operand_payload)
            $fatal(1,"operand activation/weights/last alignment or hold mismatch");
    end

    integer ref_k=1, ref_c=1, pattern=0, activation_pattern=0;
    integer cycle=0, jobs=0, loads=0, outputs=0, received=0;
    integer rejected=0, aborts=0, stall_checks=0;
    logic checking=0, sink_enable=0, sink_stalls=0, held=0;
    logic performance=0;
    integer stall_target=-1, directed_stalls=0;
    integer compute_start_cycle=0, first_output_cycle=0, last_output_cycle=0;
    integer load_start_cycle=0, load_cycles=0;
    logic raw_held=0, error_due=0;
    logic [383:0] saved_raw;
    logic [4:0] saved_base;
    logic [3:0] saved_lanes;
    logic signed [31:0] held_data;
    logic [4:0] held_channel;
    logic held_last, held_error;
    function automatic logic signed [7:0] wvalue(input integer c,k);
        case(pattern)
            1: wvalue=-128;
            2: wvalue=127;
            3: wvalue=0;
            default: wvalue=8'(c*71+k*29+128);
        endcase
    endfunction
    function automatic logic [7:0] avalue(input integer k);
        case(activation_pattern)
            1: avalue=0;
            2: avalue=255;
            3: avalue=127;
            4: avalue=128;
            default: avalue=8'(k*43+17);
        endcase
    endfunction
    function automatic longint signed golden(input integer c);
        longint signed total;
        total=0;
        for(integer k=0;k<ref_k;k=k+1)
            total=total+(longint'(avalue(k))-longint'(INPUT_ZERO_POINT))*longint'($signed(wvalue(c,k)));
        return total;
    endfunction
    // Sink is independent of the activation source; deterministic stalls.
    always @(negedge clk) begin
        // Avoid races with task drivers which also change on the falling edge.
        #1;
        out_ready = !rst && sink_enable && (!sink_stalls || cycle%7>=3);
        if(!rst && sink_enable && out_valid && integer'(out_channel_id)==stall_target && directed_stalls<24) begin
            out_ready=0;
            directed_stalls=directed_stalls+1;
        end
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if(rst) begin held=0; raw_held=0; error_due=0; end
        else begin
            if(load_valid && load_ready) load_start_cycle=cycle;
            if(load_done) load_cycles=cycle-load_start_cycle;
            if(compute_valid && compute_ready) begin
                compute_start_cycle=cycle; first_output_cycle=0;
            end
            // Read-only contract monitors: never drive internal DUT signals.
            if(raw_held && (dut.raw_results!==saved_raw || dut.replay_channel_base!==saved_base || dut.active_lanes!==saved_lanes))
                $fatal(1,"ACC/group descriptor changed before result completion");
            if(dut.group_result_done) raw_held=0;
            if(dut.result_start_valid && dut.result_start_ready) begin
                raw_held=1; saved_raw=dut.raw_results;
                saved_base=dut.replay_channel_base; saved_lanes=dut.active_lanes;
            end
            if(error_due && !compute_error) $fatal(1,"accepted output error was lost");
            error_due=out_valid && out_ready && out_error;
            if(load_busy && compute_busy) $fatal(1,"load/compute overlap");
            if(load_valid && load_ready && compute_valid && compute_ready)
                $fatal(1,"two commands accepted together");
            if(compute_busy && (load_ready || compute_ready)) $fatal(1,"busy accepted command");
            if(load_busy && compute_ready) $fatal(1,"compute during load");
            if(held) begin
                if(!out_valid || out_data!==held_data || out_channel_id!==held_channel ||
                   out_group_last!==held_last || out_error!==held_error)
                    $fatal(1,"output changed while stalled");
                stall_checks=stall_checks+1;
            end
            held=out_valid && !out_ready;
            held_data=out_data; held_channel=out_channel_id;
            held_last=out_group_last; held_error=out_error;
            if(out_valid && out_ready) begin
                if(first_output_cycle==0) first_output_cycle=cycle;
                last_output_cycle=cycle;
                if(!checking || received>=ref_c || integer'(out_channel_id)!=received ||
                   longint'($signed(out_data))!==golden(received) || out_error)
                    $fatal(1,"output mismatch c=%0d got=%0d expected=%0d",received,out_data,golden(received));
                if(out_group_last !== (received%12==11 || received==ref_c-1))
                    $fatal(1,"group last mismatch");
                received=received+1; outputs=outputs+1;
            end
            if(compute_done && (!checking || received!=ref_c || compute_error))
                $fatal(1,"early/incorrect compute_done");
        end
    end

    task automatic reset_engine;
        @(negedge clk);
        rst=1; load_valid=0; weight_valid=0; compute_valid=0;
        replay_ready=0; activation_valid=0; sink_enable=0;
        checking=0;
        repeat(3) @(negedge clk);
        if(load_ready || compute_ready || weight_ready || activation_ready || out_valid ||
           layer_ready || load_busy || compute_busy || load_done || compute_done || compute_error)
            $fatal(1,"reset did not clear transaction state");
        rst=0;
        @(negedge clk);
        if(!load_ready || compute_ready || layer_ready) $fatal(1,"bad empty state");
    endtask
    task automatic command_load(input integer k,c, input bit simultaneous);
        @(negedge clk);
        load_k=8'(k); load_channels=6'(c); load_valid=1;
        compute_valid=simultaneous;
        #1;
        if(simultaneous && compute_ready) $fatal(1,"load priority failed");
        do @(posedge clk); while(!load_ready);
        @(negedge clk);
        load_valid=0; compute_valid=0;
        // Poison external descriptors immediately after acceptance.
        load_k=0; load_channels=63;
        if(layer_ready) $fatal(1,"new load retained old valid layer");
    endtask
    task automatic send_weight(input integer c,k);
        @(negedge clk);
        weight_valid=1; weight_i8=wvalue(c,k);
        do @(posedge clk); while(!weight_ready);
        @(negedge clk); weight_valid=0;
    endtask
    task automatic load_layer(input integer k,c,p, input bit simultaneous);
        ref_k=k; ref_c=c; pattern=p;
        command_load(k,c,simultaneous);
        if(load_error) $fatal(1,"valid descriptor rejected");
        for(integer ch=0;ch<c;ch=ch+1)
            for(integer n=0;n<k;n=n+1) begin
                if(!performance && n%13==0) repeat(2) @(negedge clk);
                send_weight(ch,n);
            end
        while(!load_done) @(negedge clk);
        if(!layer_ready || load_busy || load_error) $fatal(1,"bad load completion");
        loads=loads+1;
        @(negedge clk);
        if(load_done) $fatal(1,"load_done not pulse");
    endtask
    task automatic invalid_load(input integer k,c);
        command_load(k,c,1);
        if(!load_error || load_busy || layer_ready || compute_ready || weight_ready)
            $fatal(1,"bad invalid load response K=%0d C=%0d",k,c);
        @(negedge clk);
        if(load_error) $fatal(1,"load_error not pulse");
        rejected=rejected+1;
    endtask
    task automatic start_compute;
        @(negedge clk);
        received=0; checking=1; compute_valid=1;
        do @(posedge clk); while(!compute_ready);
        @(negedge clk); compute_valid=0;
    endtask
    task automatic send_activations;
        for(integer base=0;base<ref_c;base=base+12) begin
            while(!replay_valid) @(negedge clk);
            if(!performance) repeat(2) @(negedge clk);
            if(integer'(replay_channel_base)!=base || integer'(replay_k)!=ref_k)
                $fatal(1,"saved descriptor/replay mismatch");
            replay_ready=1;
            @(posedge clk);
            @(negedge clk); replay_ready=0;
            for(integer n=0;n<ref_k;n=n+1) begin
                if(!performance && n%11==0) repeat(2) @(negedge clk);
                activation_valid=1; activation_u8=avalue(n);
                do @(posedge clk); while(!activation_ready);
                @(negedge clk); activation_valid=0;
            end
        end
    endtask
    task automatic run_job(input integer ap, input bit stalls);
        activation_pattern=ap; sink_stalls=stalls; sink_enable=1;
        start_compute();
        // Busy requests are not accepted and must not disturb the resident layer.
        load_valid=1; compute_valid=1; load_k=1; load_channels=1;
        repeat(2) @(negedge clk);
        if(load_ready || compute_ready) $fatal(1,"busy request accepted");
        load_valid=0; compute_valid=0;
        send_activations();
        while(!compute_done) @(negedge clk);
        if(received!=ref_c || compute_error || !layer_ready) $fatal(1,"incomplete job");
        if(performance)
            $display("METRIC pe8=%0d pipe=%0d K=%0d C=%0d load_observed=%0d compute_to_done_edge=%0d first_output=%0d last_output=%0d",
                PE8_MODE,RESULT_PIPELINED,ref_k,ref_c,load_cycles,cycle+1-compute_start_cycle,
                first_output_cycle-compute_start_cycle,last_output_cycle-compute_start_cycle);
        @(negedge clk);
        if(compute_done) $fatal(1,"compute_done not pulse");
        checking=0; sink_enable=0; jobs=jobs+1;
    endtask
    initial begin
        reset_engine();
        compute_valid=1;
        repeat(4) @(negedge clk);
        if(compute_ready || compute_busy || replay_valid) $fatal(1,"compute on empty layer");
        compute_valid=0;
        load_layer(9,12,0,1); run_job(0,0); run_job(3,1); run_job(2,1);
        invalid_load(0,12); invalid_load(9,0); invalid_load(9,33); invalid_load(171,32);
        load_layer(144,32,0,0); run_job(0,1); run_job(4,0);
        load_layer(32,8,1,0); run_job(1,1); run_job(2,0);
        load_layer(170,32,2,0); run_job(2,1);
        load_layer(255,24,0,0); run_job(0,1);
        for(integer c=1;c<=32;c=c+1) begin
            load_layer(1,c,0,0); run_job(0,1);
        end
        // Abort partially written layer; stale RAM must not become usable.
        ref_k=9; ref_c=12; pattern=0;
        command_load(9,12,0); send_weight(0,0);
        reset_engine(); aborts=aborts+1;
        load_layer(9,12,3,0); run_job(2,0);
        // Abort while waiting for replay.
        start_compute(); wait(replay_valid);
        reset_engine(); aborts=aborts+1;
        load_layer(1,12,0,0); run_job(0,0);
        // Abort while a completed result is blocked at the external port.
        sink_enable=0; start_compute(); send_activations(); wait(out_valid);
        repeat(4) @(negedge clk);
        if(compute_done) $fatal(1,"done before final output acceptance");
        reset_engine(); aborts=aborts+1;
        load_layer(9,12,0,0); run_job(0,1);
        // Directed long holds at first, middle and last output across groups.
        load_layer(9,25,0,0);
        for(integer t=0;t<3;t=t+1) begin
            stall_target=(t==0) ? 0 : ((t==1) ? 12 : 24);
            directed_stalls=0; run_job(0,0);
            if(directed_stalls!=24) $fatal(1,"directed stall coverage missing");
        end
        stall_target=-1;
        // Abort with a populated operand stage, before that product is accepted.
        start_compute(); wait(replay_valid); @(negedge clk); replay_ready=1;
        @(negedge clk); replay_ready=0; activation_valid=1; activation_u8=avalue(0);
        do @(posedge clk); while(!activation_ready);
        @(negedge clk); activation_valid=0;
        wait(dut.operand_valid);
        reset_engine(); aborts=aborts+1;
        // Controlled source schedule, no activation bubbles or sink stalls.
        // Weight driver retains its documented per-word turnaround cycle.
        performance=1;
        load_layer(9,12,0,0); run_job(0,0);
        load_layer(144,32,0,0); run_job(0,0);
        load_layer(32,8,0,0); run_job(0,0);
        if(operand_transfers==0) $fatal(1,"operand pipeline coverage missing");
        $display("PASS operand transfers=%0d (payload/valid/last/reset checked)",operand_transfers);
        $display("PASS memory_engine PE8_MODE=%0d RESULT_PIPELINED=%0d loads=%0d jobs=%0d outputs=%0d invalid=%0d aborts=%0d stall_checks=%0d",
                 PE8_MODE,RESULT_PIPELINED,loads,jobs,outputs,rejected,aborts,stall_checks);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"watchdog timeout");
    end
endmodule
