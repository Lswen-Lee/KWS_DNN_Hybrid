`timescale 1ns/1ps
module tb_pe_weight_sum_builder;
    logic clk=0;
    always #4 clk=~clk;
    logic rst=1,cmd_valid=0,cmd_ready,weight_valid=0,weight_ready;
    logic [7:0] cmd_k=0;
    logic [4:0] cmd_channel_id=0,sum_channel_id;
    logic signed [7:0] weight_i8=0;
    logic sum_valid,sum_ready=1;
    logic signed [31:0] weight_sum;
    pe_weight_sum_builder dut(.*);

    integer accepted=0, received=0, aborted=0, ref_remaining=0, ref_sum=0;
    integer weight_count=0, stall_checks=0;
    logic [4:0] ref_channel;
    bit working=0, pending=0;
    // Expected state tracks external handshakes only, never DUT state/count.
    always @(posedge clk) begin
        if (rst) begin
            if (working || pending) aborted=aborted+1;
            working=0; pending=0;
            #1;
            if (cmd_ready || weight_ready || sum_valid || weight_sum!=0 || sum_channel_id!=0)
                $fatal(1,"Reset mismatch");
        end else begin
            if (sum_valid !== pending || weight_ready !== working)
                $fatal(1,"Protocol state mismatch");
            if (cmd_ready !== (!working && !pending && cmd_k!=0))
                $fatal(1,"Command ready mismatch");
            if (sum_valid) begin
                if (weight_sum !== ref_sum || sum_channel_id !== ref_channel)
                    $fatal(1,"Sum mismatch got=%0d expected=%0d",weight_sum,ref_sum);
                if (!sum_ready) stall_checks=stall_checks+1;
            end
            if (sum_valid && sum_ready) begin pending=0; received=received+1; end
            if (weight_valid && weight_ready) begin
                weight_count=weight_count+1;
                ref_sum=ref_sum+int'(weight_i8);
                ref_remaining=ref_remaining-1;
                if (ref_remaining==0) begin working=0; pending=1; end
            end
            if (cmd_valid && cmd_ready) begin
                accepted=accepted+1;
                working=1; ref_remaining=int'(cmd_k); ref_sum=0;
                ref_channel=cmd_channel_id;
            end
        end
    end
    function automatic integer value_for(input integer index, mode);
        case(mode)
            0:return 0;
            1:return 127;
            2:return -128;
            3:return (index%2==0)?-128:127;
            default:return ((index*73+19)%256)-128;
        endcase
    endfunction
    task automatic command(input integer k,channel);
        if(k<0 || k>255 || channel<0 || channel>31) $fatal(1,"Bad TB parameter");
        cmd_k=8'(k); cmd_channel_id=5'(channel); cmd_valid=1;
        @(posedge clk); while(!cmd_ready) @(posedge clk);
        @(negedge clk); cmd_valid=0;
    endtask
    task automatic send_weight(input integer w);
        if(w < -128 || w > 127) $fatal(1,"Bad TB weight");
        weight_i8=8'(w); weight_valid=1;
        @(posedge clk); while(!weight_ready) @(posedge clk);
        @(negedge clk); weight_valid=0;
    endtask
    task automatic job(input integer k,mode,channel);
        integer expected;
        expected=0;
        command(k,channel);
        // Changing command payload / asserting valid while busy must not
        // replace the accepted K or channel.
        cmd_valid=1; cmd_k=1; cmd_channel_id=31;
        for(integer i=0;i<k;i=i+1) begin
            expected=expected+value_for(i,mode);
            if(i==k-1) sum_ready=0;
            send_weight(value_for(i,mode));
            if(mode==4 && i%7==0 && i!=k-1) repeat(2) @(negedge clk);
        end
        if(!sum_valid || weight_sum!==expected || sum_channel_id!==5'(channel))
            $fatal(1,"Final weight missing / incorrect latency");
        // Surplus weight must not be accepted while holding result.
        weight_valid=1; weight_i8=99;
        repeat(3) @(negedge clk);
        cmd_valid=0; weight_valid=0; sum_ready=1;
        @(negedge clk);
        if(sum_valid) $fatal(1,"Result not consumed");
    endtask
    initial begin #100000; $fatal(1,"Watchdog timeout"); end
    initial begin
        repeat(2) @(negedge clk); rst=0;
        $display("TEST K=0 ignored, no accidental weight acceptance in IDLE");
        cmd_valid=1; cmd_k=0; weight_valid=1; weight_i8=127;
        repeat(3) @(negedge clk);
        if(cmd_ready || weight_ready || sum_valid) $fatal(1,"K0 accepted");
        cmd_valid=0; weight_valid=0;
        $display("TEST K=1/9/32/144/255, zero/positive/negative/alternating/mixed; bubbles and stalls");
        for(integer mode=0;mode<5;mode=mode+1) begin
            job(1,mode,mode);
            job(9,mode,mode+5);
            job(32,mode,mode+10);
            job(144,mode,mode+15);
            job(255,mode,mode+20);
        end
        $display("TEST command and weight simultaneous: weight accepted only next edge");
        weight_valid=1; weight_i8=55;
        command(1,31);
        @(negedge clk); weight_valid=0;
        @(negedge clk);
        $display("TEST reset in ACCUMULATE and RESULT; restart without stale sum");
        command(9,3); send_weight(-128);
        rst=1; repeat(2) @(negedge clk); rst=0;
        command(1,4); sum_ready=0; send_weight(127);
        rst=1; repeat(2) @(negedge clk); rst=0; sum_ready=1;
        job(9,4,30);
        repeat(2) @(negedge clk);
        if(working || pending || accepted!=29 || received!=27 || aborted!=2)
            $fatal(1,"Count mismatch accepted=%0d received=%0d aborted=%0d",accepted,received,aborted);
        $display("PASS sum builder: commands=%0d results=%0d aborted=%0d weights=%0d stall_checks=%0d",
                 accepted,received,aborted,weight_count,stall_checks);
        $finish;
    end
endmodule
