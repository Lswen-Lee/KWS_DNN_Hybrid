`timescale 1ns/1ps
module tb_pe8_accumulator_s32;
    logic clk=0;
    logic rst=0,clear=0,accumulate_en=0;
    logic signed [15:0] product=0;
    logic signed [31:0] accumulator;
    logic signed [31:0] expected=0;
    integer i,checks=0;
    always #5 clk=~clk;
    pe8_accumulator_s32 dut (.*);
    task automatic step(input bit r,c,en,input integer p);
        begin
            @(negedge clk);
            rst=r; clear=c; accumulate_en=en; product=16'(p);
            if(r || c) expected=0;
            else if(en) expected=expected+p;
            @(posedge clk); #1;
            checks=checks+1;
            if(accumulator!==expected)
                $fatal(1,"check=%0d actual=%0d expected=%0d",checks,accumulator,expected);
        end
    endtask
    initial begin
        $display("TEST: reset/clear priority, signed extension, hold");
        step(1,1,1,32767);
        step(0,0,1,-32768);
        step(0,0,1,32767);
        step(0,0,0,123);
        step(0,1,1,99);
        step(0,0,1,31);
        // Reset asserted between edges must not change the accumulator early.
        @(negedge clk); rst=1; #1;
        if(accumulator!==32'sd31) $fatal(1,"Reset is not synchronous");
        @(posedge clk); #1;
        if(accumulator!==32'sd0) $fatal(1,"Reset failed");
        expected=0;
        $display("TEST: positive INT32 overflow using legal 16-bit products");
        step(0,1,0,0);
        for(i=0;i<65539;i=i+1) step(0,0,1,32767);
        if(accumulator>=0) $fatal(1,"Positive wrap not reached");
        $display("TEST: negative INT32 overflow using legal 16-bit products");
        step(0,1,0,0);
        for(i=0;i<65537;i=i+1) step(0,0,1,-32768);
        if(accumulator<=0) $fatal(1,"Negative wrap not reached");
        $display("PASS accumulator: %0d clocked checks + synchronous-reset check",checks);
        $finish;
    end
endmodule

