`timescale 1ns/1ps
module tb_pe8_result_controller_pipeline;
    localparam bit PE8_MODE=1;
    logic clk=0, rst=1;
    always #4 clk=~clk;
    logic result_start_valid=0, result_start_ready;
    logic [4:0] channel_base=0;
    logic [3:0] active_lanes=1;
    logic [383:0] raw_results=0;
    logic busy, group_result_done;
    logic sum_rd_valid, sum_rd_ready, sum_out_valid, sum_out_ready, sum_out_error;
    logic [4:0] sum_rd_channel_id, sum_out_channel_id;
    logic signed [31:0] sum_out_data;
    logic out_valid, out_ready=0, out_last, out_error;
    logic [4:0] out_channel_id;
    logic signed [31:0] out_data;
    logic wr_valid=0, wr_ready, layer_clear=0;
    logic [4:0] wr_id=0;
    logic signed [31:0] wr_sum=0;
    logic mem_rd_ready, mem_out_valid, mem_out_error;
    logic [4:0] mem_out_id;
    logic signed [31:0] mem_out_data;
    logic allow_request=1, allow_response=1, corrupt_id=0;
    logic [31:0] loaded=0;
    logic signed [31:0] reference_sum[0:31];
    integer request_lane=0, last_output_cycle=0;
    logic measure_ii=0;
    integer lane=0, responses=0, groups=0, aborted=0, starts=0, requests=0;
    integer stalls=0, faults=0, cycle=0, start_cycle=0;
    logic pending=0, previous_last=0, was_stalled=0;
    logic extremes=0, mixed_stalls=0;
    logic [38:0] held;
    logic request_stalled=0;
    logic [4:0] held_request;
    pe8_result_controller_pipeline dut (.*);
    pe_channel_sum_memory memory (
        .clk(clk), .rst(rst), .layer_clear(layer_clear), .wr_valid(wr_valid), .wr_ready(wr_ready),
        .wr_channel_id(wr_id), .wr_weight_sum(wr_sum),
        .rd_valid(sum_rd_valid && allow_request), .rd_ready(mem_rd_ready),
        .rd_channel_id(sum_rd_channel_id), .out_valid(mem_out_valid),
        .out_ready(sum_out_ready && allow_response), .out_channel_id(mem_out_id),
        .out_weight_sum(mem_out_data), .out_error(mem_out_error)
    );
    assign sum_rd_ready=mem_rd_ready && allow_request;
    assign sum_out_valid=mem_out_valid && allow_response;
    assign sum_out_data=mem_out_data;
    assign sum_out_error=mem_out_error;
    // Deliberate bus fault injection, not a hierarchical DUT override.
    assign sum_out_channel_id=corrupt_id ? (mem_out_id ^ 5'd1) : mem_out_id;
    always @(posedge clk) begin : scoreboard
        integer channel;
        longint signed total;
        logic signed [31:0] expected;
        logic expected_error;
        cycle=cycle+1;
        if(rst) begin
            if(pending) aborted=aborted+1;
            pending=0; lane=0; loaded=0; previous_last=0; was_stalled=0; request_stalled=0;
            if(result_start_ready || sum_rd_valid || sum_out_ready || out_valid)
                $fatal(1,"Handshake during reset");
        end else begin
            if(request_stalled && (!sum_rd_valid || sum_rd_channel_id!==held_request))
                $fatal(1,"Request changed before acceptance");
            request_stalled=sum_rd_valid && !sum_rd_ready;
            held_request=sum_rd_channel_id;
            if(group_result_done !== previous_last) $fatal(1,"Done must follow final output acceptance");
            previous_last=0;
            if(layer_clear) loaded=0;
            if(wr_valid && wr_ready) begin loaded[wr_id]=1; reference_sum[wr_id]=wr_sum; end
            if(was_stalled && (!out_valid || {out_data,out_channel_id,out_last,out_error} !== held))
                $fatal(1,"Stalled output changed");
            held={out_data,out_channel_id,out_last,out_error};
            was_stalled=out_valid && !out_ready;
            if(result_start_valid && result_start_ready) begin
                if(pending) $fatal(1,"Accepted overlapping group");
                pending=1; lane=0; request_lane=0; starts=starts+1; start_cycle=cycle;
            end
            if(sum_rd_valid && sum_rd_ready) begin
                if(request_lane>=integer'(active_lanes)) $fatal(1,"Too many sum requests");
                if(!PE8_MODE || !pending || sum_rd_channel_id != 5'(integer'(channel_base)+request_lane))
                    $fatal(1,"Wrong sum request");
                requests=requests+1; request_lane=request_lane+1;
            end
            if(!PE8_MODE && (sum_rd_valid || sum_out_ready)) $fatal(1,"PE9 used sum interface");
            if(out_valid) begin
                if(!pending || lane>=integer'(active_lanes)) $fatal(1,"Extra output");
                channel=integer'(channel_base)+lane;
                total=longint'($signed(raw_results[lane*32+:32]));
                expected_error=0;
                if(PE8_MODE) begin
                    if(!loaded[channel] || corrupt_id) begin total=0; expected_error=1; end
                    else total=total+longint'(reference_sum[channel]);
                end
                if(total>2147483647) begin expected=32'sh7fffffff; expected_error=1; end
                else if(total < -64'sd2147483648) begin expected=32'sh80000000; expected_error=1; end
                else expected=32'(total);
                if(out_channel_id != 5'(channel) || out_last != (lane==integer'(active_lanes)-1) ||
                   out_data !== expected || out_error !== expected_error)
                    $fatal(1,"Response mismatch channel=%0d expected=%0d actual=%0d",channel,expected,out_data);
                if(out_ready) begin
                    if(measure_ii && lane>0 && cycle-last_output_cycle!=1)
                        $fatal(1,"Pipeline did not sustain II=1");
                    last_output_cycle=cycle;
                    responses=responses+1;
                    if(out_error) faults=faults+1;
                    lane=lane+1;
                    if(out_last) begin
                        if(request_lane!=integer'(active_lanes)) $fatal(1,"Request count mismatch at completion");
                        pending=0; previous_last=1; groups=groups+1;
                    end
                end else stalls=stalls+1;
            end
        end
    end
    task automatic reset_all;
        rst=1; result_start_valid=0; out_ready=0; wr_valid=0;
        allow_request=1; allow_response=1; corrupt_id=0;
        repeat(2) @(negedge clk); rst=0;
    endtask
    task automatic write_sum(input integer c, input logic signed [31:0] value);
        if(c<0 || c>31) $fatal(1,"TB channel");
        wr_valid=1; wr_id=5'(c); wr_sum=value;
        @(negedge clk); wr_valid=0;
    endtask
    task automatic start_group(input integer base,count);
        if(base<0 || base>31 || count<1 || count>12) $fatal(1,"TB descriptor");
        channel_base=5'(base); active_lanes=4'(count);
        for(integer l=0;l<12;l=l+1) raw_results[l*32+:32]=32'((base+l)*-17+23);
        if(extremes) begin raw_results[31:0]=32'h7fffffff; raw_results[63:32]=32'h80000000; end
        result_start_valid=1;
        do @(posedge clk); while(!result_start_ready);
        @(negedge clk); result_start_valid=0;
    endtask
    task automatic finish_group(input logic backpressure);
        integer tick;
        tick=0;
        while(!group_result_done) begin
            out_ready=!backpressure || (tick%5==4);
            if(mixed_stalls) begin
                allow_request=(tick%3!=0);
                allow_response=(tick%4>=2);
            end
            tick=tick+1;
            @(negedge clk);
        end
        out_ready=0;
        allow_request=1; allow_response=1;
        @(negedge clk);
    endtask
    initial begin
        reset_all();
        // Invalid descriptors are not accepted; group controller guarantees validity.
        result_start_valid=1; active_lanes=0;
        @(negedge clk); if(result_start_ready || busy) $fatal(1,"Accepted zero lanes");
        active_lanes=13;
        @(negedge clk); if(result_start_ready || busy) $fatal(1,"Accepted >12 lanes");
        active_lanes=2; channel_base=31;
        @(negedge clk); if(result_start_ready || busy) $fatal(1,"Accepted channel overflow");
        result_start_valid=0;
        for(integer c=0;c<32;c=c+1) write_sum(c,(c-16)*13);
        measure_ii=1;
        for(integer n=1;n<=12;n=n+1) begin
            start_group(32-n,n); out_ready=1;
            wait(group_result_done); @(negedge clk);
            if(cycle-start_cycle != (n+2)) $fatal(1,"No-stall latency mismatch");
            out_ready=0; @(negedge clk);
        end
        measure_ii=0;
        start_group(0,12); finish_group(1);
        // Block requests and then responses through public ready/valid interfaces.
        allow_request=0; start_group(4,8);
        repeat(4) @(negedge clk);
        allow_response=0; allow_request=1;
        repeat(4) @(negedge clk);
        allow_response=1; finish_group(1);
        // Missing sums, including an error on the final lane.
        layer_clear=1; @(negedge clk); layer_clear=0;
        write_sum(0,9); start_group(0,3); finish_group(1);
        write_sum(1,-9); corrupt_id=1; start_group(0,2); finish_group(1); corrupt_id=0;
        // Alternating missing/good sums, independent interface stalls.
        for(integer c=5;c<12;c=c+2) write_sum(c,c*19);
        mixed_stalls=1; start_group(4,8); finish_group(1); mixed_stalls=0;
        // Exercise correction overflow with full INT32 unit-level operands.
        extremes=1; start_group(0,2); finish_group(1); extremes=0;
        // Cancel in request wait, response wait, and output wait; reset RAM too.
        for(integer p=0;p<3;p=p+1) begin
            allow_request=(p!=0); allow_response=(p!=1);
            start_group(0,(p==2) ? 12 : 1);
            repeat(4) @(negedge clk);
            reset_all();
            write_sum(0,7); start_group(0,1); finish_group(1);
        end
        if(starts!=groups+aborted || aborted!=3 || stalls==0 || (PE8_MODE && faults==0))
            $fatal(1,"Coverage/accounting failed");
        $display("PASS pipeline result PE8_MODE=%0d groups=%0d outputs=%0d aborted=%0d sum_requests=%0d faults=%0d stalls=%0d",PE8_MODE,groups,responses,aborted,requests,faults,stalls);
        $finish;
    end
    initial begin #1000000; $fatal(1,"Timeout"); end
endmodule
