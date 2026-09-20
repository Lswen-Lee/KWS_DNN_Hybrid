`timescale 1ns/1ps
// No TB driver for cfg_weight_sum: only the real builder drives configuration.
// Weights are replayed by the TB for MAC; no weight RAM is claimed here.
module tb_pe8_weight_sum_integration;
    logic clk=0;
    always #4 clk=~clk;
    logic rst=1,cmd_valid=0,cmd_ready,in_valid=0,in_ready;
    logic [7:0] cmd_k=0,activation_u8=0;
    logic [11:0] cmd_lane_mask=0;
    logic [95:0] weights_flat=0;
    logic cfg_valid,cfg_ready;
    logic [3:0] cfg_lane;
    logic signed [31:0] cfg_weight_sum;
    logic out_valid,out_ready=1,out_last,out_overflow,busy,done;
    logic signed [31:0] result;
    logic [3:0] lane_id;
    pe8_equivalent_top pe (.*);

    logic build_valid=0,build_ready,weight_valid=0,weight_ready;
    logic [7:0] build_k=0;
    logic [3:0] build_lane=0;
    logic signed [7:0] weight_i8=0;
    pe_weight_sum_builder #(.CHANNEL_ID_WIDTH(4)) builder (
        .clk(clk),.rst(rst),.cmd_valid(build_valid),.cmd_ready(build_ready),
        .cmd_k(build_k),.cmd_channel_id(build_lane),
        .weight_valid(weight_valid),.weight_ready(weight_ready),.weight_i8(weight_i8),
        .sum_valid(cfg_valid),.sum_ready(cfg_ready),
        .weight_sum(cfg_weight_sum),.sum_channel_id(cfg_lane)
    );
    integer golden[0:11];
    integer results=0,configs=0,weights=0,jobs=0,cycles=0;
    integer cfg_stalls=0,result_stalls=0,reference_sum=0;
    logic [3:0] reference_lane;
    logic [11:0] seen=0;
    bit cfg_held=0,result_held=0;
    logic [35:0] old_cfg;
    logic [37:0] old_result;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(rst) begin cfg_held=0; result_held=0; reference_sum=0; end
        else begin
            if(cfg_held && (!cfg_valid || {cfg_weight_sum,cfg_lane} !== old_cfg))
                $fatal(1,"Builder configuration changed during backpressure");
            if(result_held && (!out_valid || {result,lane_id,out_last,out_overflow} !== old_result))
                $fatal(1,"PE result changed during backpressure");
            cfg_held=cfg_valid && !cfg_ready;
            result_held=out_valid && !out_ready;
            old_cfg={cfg_weight_sum,cfg_lane};
            old_result={result,lane_id,out_last,out_overflow};
            if(cfg_held) cfg_stalls=cfg_stalls+1;
            if(result_held) result_stalls=result_stalls+1;
            if(build_valid && build_ready) begin reference_sum=0; reference_lane=build_lane; end
            if(weight_valid && weight_ready) begin
                reference_sum=reference_sum+int'(weight_i8); weights=weights+1;
            end
            if(cfg_valid && cfg_ready) begin
                if(cfg_weight_sum!==reference_sum || cfg_lane!==reference_lane || cfg_lane>=12)
                    $fatal(1,"Builder sum/channel mismatch");
                configs=configs+1;
            end
            if(out_valid && out_ready) begin
                if(lane_id>=12 || !cmd_lane_mask[lane_id] || seen[lane_id]) $fatal(1,"Wrong/duplicate lane");
                if(result!==golden[lane_id] || out_overflow) $fatal(1,"Golden mismatch lane%0d got%0d expected%0d",lane_id,result,golden[lane_id]);
                if(out_last !== ((cmd_lane_mask >> (int'(lane_id)+1))==0)) $fatal(1,"Last mismatch");
                seen[lane_id]=1; results=results+1;
            end
        end
    end
    function automatic integer a(input integer i,mode);
        case(mode)
            0:return 127;
            1:return 128;
            2:return (i%2==0)?0:255;
            default:return (i*73+mode*29)%256;
        endcase
    endfunction
    function automatic integer w(input integer i,j,mode);
        if(mode==2) return ((i+j)%2==0)?-128:127;
        return (i*37+j*19+mode*11)%256-128;
    endfunction
    task automatic start_builder(input integer k,j);
        if(k<1 || k>255 || j<0 || j>11) $fatal(1,"Invalid TB builder command");
        build_k=8'(k); build_lane=4'(j); build_valid=1;
        @(posedge clk); while(!build_ready) @(posedge clk);
        @(negedge clk); build_valid=0;
    endtask
    task automatic send_weight(input integer value);
        if(value < -128 || value > 127) $fatal(1,"Invalid weight");
        weight_valid=1; weight_i8=8'(value);
        @(posedge clk); while(!weight_ready) @(posedge clk);
        @(negedge clk); weight_valid=0;
    endtask
    task automatic configure(input integer k,mode,input logic[11:0] mask);
        // Reverse order proves channel addressing is not a FIFO/order shortcut.
        for(integer j=11;j>=0;j=j-1) if(mask[j]) begin
            start_builder(k,j);
            for(integer i=0;i<k;i=i+1) begin
                send_weight(w(i,j,mode));
                if(i!=k-1 && i%7==0) repeat(2) @(negedge clk);
            end
            @(posedge clk);
            if(!cfg_valid || !cfg_ready) $fatal(1,"Configuration not delivered in idle");
            @(negedge clk);
        end
    endtask
    task automatic start_pe(input integer k,input logic[11:0] mask);
        if(k<1 || k>255) $fatal(1,"Invalid PE K");
        cmd_k=8'(k); cmd_lane_mask=mask; cmd_valid=1;
        @(posedge clk); while(!cmd_ready) @(posedge clk);
        @(negedge clk); cmd_valid=0;
    endtask
    task automatic run_job(input integer k,mode,input logic[11:0] mask);
        integer config_before;
        seen=0; config_before=configs;
        for(integer j=0;j<12;j=j+1) begin
            golden[j]=0;
            for(integer i=0;i<k;i=i+1) golden[j]=golden[j]+(a(i,mode)-127)*w(i,j,mode);
        end
        configure(k,mode,mask);
        if(configs-config_before!=$countones(mask)) $fatal(1,"Configuration count mismatch");
        start_pe(k,mask);
        for(integer i=0;i<k;i=i+1) begin
            activation_u8=8'(a(i,mode));
            for(integer j=0;j<12;j=j+1) weights_flat[j*8+:8]=8'(w(i,j,mode));
            in_valid=1;
            @(posedge clk); while(!in_ready) @(posedge clk);
            @(negedge clk); in_valid=0;
            if(i%7==0 && i!=k-1) repeat(2) @(negedge clk);
        end
        while(!done) begin out_ready=cycles%4==0; @(negedge clk); end
        out_ready=1;
        if(seen!==mask) $fatal(1,"Missing outputs");
        jobs=jobs+1;
        $display("PASS integrated job K=%0d mode=%0d mask=%h",k,mode,mask);
        @(negedge clk);
    endtask
    task automatic reset_both;
        rst=1; cmd_valid=0; build_valid=0; in_valid=0; weight_valid=0;
        repeat(2) @(negedge clk);
        if(busy || cfg_valid || out_valid || done) $fatal(1,"Reset did not flush both modules");
        rst=0; out_ready=1;
    endtask
    initial begin #1000000; $fatal(1,"Watchdog"); end
    initial begin
        repeat(2) @(negedge clk); rst=0;
        cmd_valid=1; cmd_k=9; cmd_lane_mask=12'hfff;
        repeat(3) begin @(negedge clk); if(cmd_ready || busy) $fatal(1,"PE accepted missing configuration"); end
        cmd_valid=0;
        run_job(1,2,12'hfff);
        run_job(9,0,12'hfff);
        run_job(32,1,12'h0ff);
        run_job(144,2,12'hfff);
        run_job(9,3,12'ha55);
        run_job(32,4,12'h800);
        run_job(255,5,12'hfff);
        run_job(9,6,12'h000);
        $display("TEST reset during partial weight accumulation");
        start_builder(9,0); send_weight(-128); reset_both();
        // Hold PE in RUN with no inputs. Builder computes next config and
        // must wait because PE forbids writes while busy. No artificial gate.
        configure(1,0,12'h001); start_pe(1,12'h001);
        start_builder(1,11); send_weight(127);
        repeat(5) begin @(negedge clk); if(!cfg_valid || cfg_ready) $fatal(1,"Expected native cfg backpressure"); end
        reset_both();
        run_job(9,7,12'hfff);
        // Reset while actual PE output is stalled; old result must disappear.
        configure(1,0,12'h001); start_pe(1,12'h001);
        out_ready=0; activation_u8=127; weights_flat=0; in_valid=1;
        @(posedge clk); while(!in_ready) @(posedge clk);
        @(negedge clk); in_valid=0;
        while(!out_valid) @(negedge clk);
        repeat(3) @(negedge clk);
        reset_both();
        run_job(9,8,12'h0ff);
        if(jobs!=10 || results!=83 || cfg_stalls<5 || result_stalls<3) $fatal(1,"Coverage/count failure");
        $display("PASS builder->PE8: jobs=%0d outputs=%0d configs=%0d weights=%0d cfg_stalls=%0d result_stalls=%0d",
                 jobs,results,configs,weights,cfg_stalls,result_stalls);
        $finish;
    end
endmodule
