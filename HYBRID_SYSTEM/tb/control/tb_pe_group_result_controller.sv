`timescale 1ns/1ps
// Public-port, self-checking integration test. No force, hierarchical writes,
// mocked MAC sums, or hand-driven PE enables/addresses/last/lane masks.
module tb_pe_group_result_controller;
    parameter bit PE8_MODE=1;
    logic clk=0, rst=1;
    always #4 clk=~clk;
    logic cmd_valid=0, cmd_ready, layer_ready, busy, done, error;
    logic [7:0] cmd_k=0;
    logic [5:0] cmd_channels=0;
    logic replay_valid, replay_ready=0;
    logic [7:0] replay_k;
    logic [4:0] channel_base;
    logic [3:0] active_lanes;
    logic [11:0] lane_mask;
    logic activation_valid=0, activation_ready;
    logic [7:0] activation_data=0;
    logic align_in_valid, align_in_ready, align_in_last;
    logic [8:0] align_weight_addr;
    logic align_out_valid, align_out_last, align_out_ready;
    logic [7:0] aligned_a;
    logic [95:0] aligned_w;
    logic pe_clear, pe_accumulate_en;
    logic result_start_valid, result_start_ready, group_result_done;
    logic result_busy, result_valid, result_ready=0, result_last, result_error;
    logic signed [31:0] result_data;
    logic [4:0] result_channel;
    logic ram_rd_valid, ram_rd_ready, ram_out_valid, ram_out_ready;
    logic [8:0] ram_rd_addr;
    wire [95:0] ram_data;
    logic load_cmd=0, load_ready, load_weight_valid=0, load_weight_ready;
    logic signed [7:0] load_weight=0;
    logic wr_valid, wr_ready;
    logic [3:0] wr_lane;
    logic [8:0] wr_addr;
    logic [7:0] wr_data;
    wire sum_valid, sum_ready;
    wire signed [31:0] weight_sum;
    wire [4:0] sum_channel_id;
    logic load_busy, load_done, load_error;
    logic sum_rd_valid, sum_rd_ready, sum_out_valid, sum_out_ready, sum_error;
    logic [4:0] sum_rd_id, sum_out_id;
    logic signed [31:0] sum_data;
    logic signed [7:0] a8;
    logic signed [8:0] a9;
    logic [383:0] results8, results9;
    integer ref_k=1, ref_c=1, pattern=0;
    integer cycle=0, issues=0, macs=0, expected_base=0, last_mac_cycle=-100;
    integer model_acc8[0:11], model_acc9[0:11], model_product8[0:11], model_product9[0:11];
    logic [11:0] model_pending=0;
    logic checking_job=0, holding_results=0;
    logic [383:0] held8, held9;
    integer jobs=0, groups=0, outputs=0, invalids=0, resets=0, mac_total=0;
    integer replay_waits=0, input_bubbles=0, result_waits=0, cycle_checks=0;
    integer rejected_busy_commands=0;
    logic [31:0] channel_coverage=0;
    logic [31:0] random_state=32'h1626_0916;

    pe_group_controller controller (.*);
    pe_layer_weight_loader loader (
        .clk(clk), .rst(rst), .cmd_valid(load_cmd), .cmd_ready(load_ready),
        .cmd_k(cmd_k), .cmd_channels(cmd_channels), .weight_valid(load_weight_valid),
        .weight_ready(load_weight_ready), .weight_i8(load_weight),
        .wr_valid(wr_valid), .wr_ready(wr_ready), .wr_lane(wr_lane), .wr_addr(wr_addr), .wr_data(wr_data),
        .sum_valid(sum_valid), .sum_ready(sum_ready), .weight_sum(weight_sum), .sum_channel_id(sum_channel_id),
        .busy(load_busy), .layer_ready(layer_ready), .done(load_done), .error(load_error)
    );
    pe_weight_buffer_12 #(.ADDR_WIDTH(9)) weights (
        .clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_ready(wr_ready),
        .wr_lane(wr_lane), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_valid(ram_rd_valid), .rd_ready(ram_rd_ready), .rd_addr(ram_rd_addr),
        .out_valid(ram_out_valid), .out_ready(ram_out_ready), .weights_flat(ram_data)
    );
    pe_weight_read_align aligner (
        .clk(clk), .rst(rst), .in_valid(align_in_valid), .in_ready(align_in_ready),
        .in_activation_u8(activation_data), .in_weight_addr(align_weight_addr), .in_last(align_in_last),
        .weight_rd_valid(ram_rd_valid), .weight_rd_ready(ram_rd_ready), .weight_rd_addr(ram_rd_addr),
        .weight_out_valid(ram_out_valid), .weight_out_ready(ram_out_ready), .weight_data(ram_data),
        .out_valid(align_out_valid), .out_ready(align_out_ready), .out_activation_u8(aligned_a),
        .out_weights(aligned_w), .out_last(align_out_last)
    );
    activation_u8_to_s8 cv8 (.activation_u8(aligned_a), .activation_s8(a8));
    activation_center_127 cv9 (.activation_u8(aligned_a), .activation_centered(a9));
    pe8_array_12 array8 (.clk(clk), .rst(rst), .clear(pe_clear), .accumulate_en(pe_accumulate_en),
        .lane_mask(lane_mask), .activation_s8(a8), .weight_vector_i8(aligned_w), .result_vector_s32(results8));
    pe_array_12 array9 (.clk(clk), .rst(rst), .clear(pe_clear), .accumulate_en(pe_accumulate_en),
        .lane_mask(lane_mask), .activation_centered(a9), .weight_vector_i8(aligned_w), .result_vector_s32(results9));
    pe_channel_sum_memory sums (
        .clk(clk), .rst(rst), .layer_clear(load_cmd && load_ready),
        .wr_valid(sum_valid), .wr_ready(sum_ready), .wr_channel_id(sum_channel_id), .wr_weight_sum(weight_sum),
        .rd_valid(sum_rd_valid), .rd_ready(sum_rd_ready), .rd_channel_id(sum_rd_id),
        .out_valid(sum_out_valid), .out_ready(sum_out_ready), .out_channel_id(sum_out_id),
        .out_weight_sum(sum_data), .out_error(sum_error)
    );
    pe_result_controller #(.PE8_MODE(PE8_MODE)) result_controller (
        .clk(clk), .rst(rst), .result_start_valid(result_start_valid), .result_start_ready(result_start_ready),
        .channel_base(channel_base), .active_lanes(active_lanes), .raw_results(PE8_MODE ? results8 : results9),
        .busy(result_busy), .group_result_done(group_result_done),
        .sum_rd_valid(sum_rd_valid), .sum_rd_ready(sum_rd_ready), .sum_rd_channel_id(sum_rd_id),
        .sum_out_valid(sum_out_valid), .sum_out_ready(sum_out_ready), .sum_out_channel_id(sum_out_id),
        .sum_out_data(sum_data), .sum_out_error(sum_error),
        .out_valid(result_valid), .out_ready(result_ready), .out_data(result_data),
        .out_channel_id(result_channel), .out_last(result_last), .out_error(result_error)
    );

    function automatic logic [7:0] avalue(input integer k);
        case(pattern)
            1: avalue=0;
            2: avalue=255;
            3: avalue=127;
            4: avalue=128;
            5: avalue=128;
            default: avalue=8'(k*43+17);
        endcase
    endfunction
    function automatic logic signed [7:0] wvalue(input integer c,k);
        case(pattern)
            1: wvalue=-128;
            2: wvalue=127;
            3: wvalue=(k%2==0) ? -128 : 127;
            4: wvalue=0;
            default: wvalue=8'(c*71+k*29+128);
        endcase
    endfunction
    function automatic integer golden(input integer c,zero_point);
        integer total;
        total=0;
        for(integer k=0;k<ref_k;k=k+1)
            total=total+(integer'(avalue(k))-zero_point)*integer'(wvalue(c,k));
        return total;
    endfunction
    function automatic integer pause_length;
        random_state=random_state ^ (random_state << 13);
        random_state=random_state ^ (random_state >> 17);
        random_state=random_state ^ (random_state << 5);
        return integer'(random_state & 32'd3);
    endfunction

    // Independent cycle-level MAC pipeline model AND transaction monitors.
    // Sample before NBA; model_acc contains all commits from earlier edges.
    always @(posedge clk) begin
        cycle=cycle+1;
        if(rst) begin
            model_pending=0; checking_job=0; holding_results=0;
            issues=0; macs=0; expected_base=0;
            for(integer l=0;l<12;l=l+1) begin
                model_acc8[l]=0; model_acc9[l]=0; model_product8[l]=0; model_product9[l]=0;
            end
            if(cmd_ready || align_in_valid || pe_accumulate_en || result_start_valid || replay_valid)
                $fatal(1,"Handshake during reset");
        end else begin
            for(integer l=0;l<12;l=l+1) begin
                if($signed(results8[l*32+:32]) !== model_acc8[l] ||
                   $signed(results9[l*32+:32]) !== model_acc9[l])
                    $fatal(1,"Cycle MAC mismatch cycle=%0d lane=%0d",cycle,l);
                cycle_checks=cycle_checks+1;
            end
            if(load_error) $fatal(1,"Unexpected loader error");
            if(cmd_valid && cmd_ready && cmd_k!=0 && cmd_channels!=0 && cmd_channels<=32 &&
               ((integer'(cmd_channels)+11)/12)*integer'(cmd_k)<=512) begin
                checking_job=1; expected_base=0;
            end
            if(pe_clear) begin
                if(!checking_job || holding_results || pe_accumulate_en || model_pending!=0)
                    $fatal(1,"Unsafe clear");
                issues=0; macs=0;
            end
            if(busy && cmd_ready) $fatal(1,"Busy controller accepted a new command");
            if(replay_valid && replay_ready) begin
                if(channel_base != 5'(expected_base) || replay_k != 8'(ref_k) ||
                   active_lanes != 4'((ref_c-expected_base>=12) ? 12 : ref_c-expected_base) ||
                   lane_mask != (12'hfff >> (12-integer'(active_lanes))))
                    $fatal(1,"Group descriptor mismatch");
            end
            if((activation_valid && activation_ready) != (align_in_valid && align_in_ready))
                $fatal(1,"Activation/align handshake mismatch");
            if(align_in_valid && align_in_ready) begin
                if(issues>=ref_k || align_weight_addr != 9'((expected_base/12)*ref_k+issues) ||
                   activation_data !== avalue(issues) || align_in_last != (issues==ref_k-1))
                    $fatal(1,"Issue count/address/last mismatch");
                issues=issues+1;
            end
            if(pe_accumulate_en) begin
                if(!checking_job || macs>=ref_k || aligned_a !== avalue(macs) ||
                   align_out_last != (macs==ref_k-1)) $fatal(1,"MAC order/last mismatch");
                for(integer l=0;l<12;l=l+1)
                    if(l<integer'(active_lanes) && $signed(aligned_w[l*8+:8]) !== wvalue(expected_base+l,macs))
                        $fatal(1,"Wrong mapped weight");
                if(align_out_last) last_mac_cycle=cycle;
            end
            if(holding_results && (results8 !== held8 || results9 !== held9))
                $fatal(1,"Results overwritten while receiver waiting");
            if(result_start_valid) begin
                if(issues!=ref_k || macs!=ref_k || cycle<last_mac_cycle+2 || model_pending!=0)
                    $fatal(1,"Premature result start");
                for(integer l=0;l<12;l=l+1) begin
                    if(l<integer'(active_lanes)) begin
                        if($signed(results8[l*32+:32]) != golden(expected_base+l,128) ||
                           $signed(results9[l*32+:32]) != golden(expected_base+l,127))
                            $fatal(1,"Golden raw MAC mismatch");
                    end else if(results8[l*32+:32] !== 0 || results9[l*32+:32] !== 0)
                        $fatal(1,"Inactive lane accumulated");
                end
                held8=results8; held9=results9; holding_results=1;
                if(result_start_ready) groups=groups+1;
            end
            if(group_result_done && holding_results) begin
                holding_results=0; expected_base=expected_base+integer'(active_lanes);
            end
            if(done) begin
                if(expected_base!=ref_c || holding_results) $fatal(1,"Early done");
                checking_job=0;
            end
            for(integer l=0;l<12;l=l+1) begin
                if(pe_clear) begin model_acc8[l]=0; model_acc9[l]=0; end
                else if(model_pending[l]) begin
                    model_acc8[l]=model_acc8[l]+model_product8[l];
                    model_acc9[l]=model_acc9[l]+model_product9[l];
                end
                model_pending[l]=pe_accumulate_en && lane_mask[l];
                if(model_pending[l]) begin
                    model_product8[l]=(integer'(avalue(macs))-128)*integer'(wvalue(expected_base+l,macs));
                    model_product9[l]=(integer'(avalue(macs))-127)*integer'(wvalue(expected_base+l,macs));
                end
            end
            if(pe_accumulate_en) begin macs=macs+1; mac_total=mac_total+1; end
        end
    end

    task automatic reset_all;
        rst=1; cmd_valid=0; load_cmd=0; load_weight_valid=0;
        activation_valid=0; replay_ready=0; result_ready=0;
        repeat(2) @(negedge clk);
        rst=0; resets=resets+1;
    endtask
    task automatic load_layer(input integer k,c,p);
        if(k<1 || k>255 || c<1 || c>32) $fatal(1,"Bad TB layer");
        ref_k=k; ref_c=c; pattern=p; cmd_k=8'(k); cmd_channels=6'(c);
        @(negedge clk); load_cmd=1;
        do @(posedge clk); while(!load_ready);
        @(negedge clk); load_cmd=0;
        for(integer ch=0;ch<c;ch=ch+1)
            for(integer ki=0;ki<k;ki=ki+1) begin
                load_weight_valid=1; load_weight=wvalue(ch,ki);
                do @(posedge clk); while(!load_weight_ready);
                @(negedge clk); load_weight_valid=0;
            end
        wait(load_done); @(negedge clk);
        if(!layer_ready || load_busy) $fatal(1,"Loader completion");
    endtask
    task automatic start_job;
        @(negedge clk); cmd_valid=1;
        do @(posedge clk); while(!cmd_ready);
        @(negedge clk); cmd_valid=0;
    endtask
    task automatic start_replay;
        wait(replay_valid); @(negedge clk);
        // Adversarial new command while busy must not replace latched K/C.
        cmd_valid=1; cmd_k=255; cmd_channels=63;
        repeat(2+pause_length()) begin
            if(!replay_valid || activation_ready || cmd_ready) $fatal(1,"Replay wait violated");
            replay_waits=replay_waits+1; @(negedge clk);
        end
        cmd_valid=0; cmd_k=8'(ref_k); cmd_channels=6'(ref_c);
        rejected_busy_commands=rejected_busy_commands+1;
        replay_ready=1;
        @(negedge clk); replay_ready=0;
    endtask
    task automatic send_activation(input integer k, input logic bubbles);
        if(bubbles) repeat(pause_length()) begin input_bubbles=input_bubbles+1; @(negedge clk); end
        activation_valid=1; activation_data=avalue(k);
        do @(posedge clk); while(!activation_ready);
        @(negedge clk); activation_valid=0;
    endtask
    // Only an external consumer remains in the TB. RTL now selects raw lane,
    // requests sums, feeds correction, and generates group completion.
    task automatic receive_group;
        integer ch;
        for(integer l=0;l<integer'(active_lanes);l=l+1) begin
            ch=integer'(channel_base)+l;
            wait(result_valid); @(negedge clk);
            repeat(1+pause_length()) begin
                if(!result_valid || result_error || result_channel!=5'(ch) ||
                   result_last!=(l==integer'(active_lanes)-1) ||
                   result_data!=golden(ch,127) || result_data!=$signed(results9[l*32+:32]))
                    $fatal(1,"RTL result mismatch PE8_MODE=%0d channel=%0d",PE8_MODE,ch);
                if(!result_busy || pe_clear || pe_accumulate_en || done)
                    $fatal(1,"Controller advanced before output acceptance");
                result_waits=result_waits+1; @(negedge clk);
            end
            result_ready=1;
            @(negedge clk); result_ready=0; outputs=outputs+1;
        end
        wait(group_result_done); @(negedge clk);
    endtask
    task automatic run_job(input logic bubbles);
        start_job();
        for(integer g=0;g<(ref_c+11)/12;g=g+1) begin
            start_replay();
            for(integer k=0;k<ref_k;k=k+1) send_activation(k,bubbles);
            receive_group();
        end
        if(!done || busy) $fatal(1,"Missing final done");
        @(negedge clk);
        if(done || !cmd_ready) $fatal(1,"Done not one-cycle or no next command");
        jobs=jobs+1;
        channel_coverage[ref_c-1]=1;
        $display("PASS job K=%0d C=%0d pattern=%0d bubbles=%0d",ref_k,ref_c,pattern,bubbles);
    endtask
    task automatic invalid_command(input logic [7:0] k, input logic [5:0] c);
        cmd_k=k; cmd_channels=c; start_job();
        if(!error || busy || pe_clear || replay_valid) $fatal(1,"Invalid command accepted");
        @(negedge clk); if(error) $fatal(1,"Error not pulse");
        invalids=invalids+1;
    endtask
    initial begin
        reset_all();
        // Not loaded: command must not be accepted.
        cmd_valid=1; cmd_k=1; cmd_channels=1;
        repeat(3) begin @(negedge clk); if(cmd_ready || busy) $fatal(1,"Accepted unloaded layer"); end
        cmd_valid=0;
        load_layer(1,1,0);
        invalid_command(0,12); invalid_command(9,0); invalid_command(9,33); invalid_command(171,32);
        cmd_k=1; cmd_channels=1; run_job(0);
        load_layer(9,12,0); run_job(0); run_job(1); // reuse layer without reload
        load_layer(144,32,0); run_job(1);
        load_layer(32,8,3); run_job(1);
        load_layer(3,13,1); run_job(1);
        load_layer(5,24,2); run_job(0);
        load_layer(7,25,4); run_job(1);
        load_layer(170,32,1); run_job(1);
        load_layer(255,24,2); run_job(0);
        load_layer(9,12,5); run_job(1); // A=128, nonzero weights: raw PE8=0, corrected=SigmaW
        // Exhaust every channel count, not only the model's three layers.
        for(integer c=1;c<=32;c=c+1) begin
            load_layer(1+c%7,c,0); run_job(1);
        end
        // Abort at CLEAR, REPLAY, active MAC, final-product drain, result wait.
        for(integer phase=0;phase<5;phase=phase+1) begin
            load_layer(9,13,0); start_job();
            if(phase>=1) begin wait(replay_valid); @(negedge clk); end
            if(phase>=2) begin
                start_replay();
                for(integer k=0;k<((phase==2)?2:9);k=k+1) send_activation(k,0);
            end
            if(phase==3) begin
                // Edge immediately following last issue accepts final MAC.
                @(negedge clk);
            end
            if(phase==4) begin
                wait(result_start_valid); @(negedge clk);
                repeat(4) @(negedge clk);
            end
            reset_all();
            load_layer(1,1,0); run_job(0);
        end
        if(jobs!=48 || invalids!=4 || replay_waits==0 || input_bubbles==0 || result_waits==0 ||
           channel_coverage!=32'hffffffff || rejected_busy_commands==0)
            $fatal(1,"Coverage target missing");
        $display("PASS group+result controller jobs=%0d groups=%0d outputs=%0d invalid=%0d resets=%0d MACs=%0d cycle_lane_checks=%0d",jobs,groups,outputs,invalids,resets,mac_total,cycle_checks);
        $display("PE8_MODE=%0d", PE8_MODE);
        $display("COVER replay_wait=%0d input_bubbles=%0d result_wait=%0d",replay_waits,input_bubbles,result_waits);
        $display("COVER channel_counts=%h ignored_busy_commands=%0d",channel_coverage,rejected_busy_commands);
        $finish;
    end
    initial begin #10000000; $fatal(1,"Watchdog timeout"); end
endmodule
