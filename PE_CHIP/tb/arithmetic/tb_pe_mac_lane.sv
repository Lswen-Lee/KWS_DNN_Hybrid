`timescale 1ns/1ps
module tb_pe_mac_lane;
    logic clk=0;
    logic rst=0,clear=0,accumulate_en=0;
    logic signed [8:0] activation_centered=0;
    logic signed [7:0] weight_i8=0;
    logic signed [31:0] accumulator;
    integer expected=0, pending_product=0;
    bit pending_valid=0;
    integer checks=0,i,k,trial;
    always #5 clk=~clk;
    pe_mac_lane dut (.*);

    // Independent reference queue: consume the PREVIOUS accepted transaction.
    // integer is signed 32-bit, so overflow wraps just like the public output.
    task automatic step(input bit r,c,en,input integer a,w);
        begin
            @(negedge clk);
            rst=r; clear=c; accumulate_en=en;
            activation_centered=9'(a); weight_i8=8'(w);
            if(r || c) expected=0;
            else if(pending_valid) expected=expected+pending_product;
            pending_valid=!r && !c && en;
            pending_product=a*w;
            @(posedge clk); #1;
            checks=checks+1;
            if(accumulator!==expected)
                $fatal(1,"check=%0d actual=%0d expected=%0d",checks,accumulator,expected);
        end
    endtask

    initial begin
        $display("TEST reset, first latency, streaming, drain and repeated idle");
        step(1,0,0,0,0);
        step(0,0,1,10,3);
        if(accumulator!==0) $fatal(1,"First product committed too early");
        step(0,0,1,5,-4);
        if(accumulator!==30) $fatal(1,"First product not committed");
        step(0,0,0,127,127);
        if(accumulator!==10) $fatal(1,"Drain failed");
        step(0,0,0,127,127);
        $display("TEST clear/reset discard pending work, including concurrent enable");
        step(0,0,1,7,8);
        step(0,1,1,100,100);
        step(0,0,0,0,0);
        step(0,0,1,-7,-8);
        step(1,0,1,100,100);
        step(0,0,0,0,0);
        $display("TEST signed endpoints");
        step(0,0,1,128,-128);
        step(0,0,1,-127,-128);
        step(0,0,1,-1,127);
        step(0,0,0,0,0);
        for(trial=0;trial<3;trial=trial+1) begin
            if(trial==0) k=9; else if(trial==1) k=32; else k=144;
            $display("TEST K=%0d signed dot product, bubbles, final drain",k);
            step(0,1,0,0,0);
            for(i=0;i<k;i=i+1) begin
                if(i%7==0) step(0,0,0,0,0);
                step(0,0,1,(i*73)%256-127,(i*37)%256-128);
            end
            step(0,0,0,0,0);
            step(0,0,0,0,0);
        end
        $display("TEST positive and negative INT32 wrap, without forcing internal state");
        step(0,1,0,0,0);
        for(i=0;i<140000;i=i+1) step(0,0,1,128,127);
        step(0,0,0,0,0);
        if(accumulator>=0) $fatal(1,"Positive overflow not exercised");
        step(0,1,0,0,0);
        for(i=0;i<140000;i=i+1) step(0,0,1,128,-128);
        step(0,0,0,0,0);
        if(accumulator<=0) $fatal(1,"Negative overflow not exercised");
        $display("PASS pe_mac_lane: %0d pipeline/control/wrap checks",checks);
        $finish;
    end
endmodule
