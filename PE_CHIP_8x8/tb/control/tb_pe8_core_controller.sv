`timescale 1ns/1ps
module tb_pe8_core_controller;
    logic clk=0,rst=1,start=0,sample_valid=0,result_ready=0;
    logic [7:0] k_length=0;
    logic [11:0] lane_mask=0;
    wire busy,done,sample_ready,result_valid,array_clear,sample_accept,input_valid;
    wire [11:0] lane_mask_reg;
    integer checks=0;
    always #5 clk=~clk;
    pe8_core_controller dut (.*);
    task automatic tick;
        @(posedge clk); #1; checks=checks+1;
        @(negedge clk);
    endtask
    initial begin
        tick(); rst=0;
        start=1; tick(); // K=0 ignored.
        if(busy || done || array_clear) $fatal(1,"K0 must stay idle");
        k_length=1; lane_mask=12'h0ff; tick();
        if(!busy || !array_clear || lane_mask_reg!=12'h0ff) $fatal(1,"Command latch");
        start=0; k_length=255; lane_mask=0; tick();
        if(!sample_ready || array_clear) $fatal(1,"CLEAR -> RUN");
        tick(); tick(); // bubbles do not advance count.
        if(!sample_ready || sample_accept) $fatal(1,"Stall changed count/accept");
        sample_valid=1; tick();
        if(sample_ready || !input_valid || result_valid) $fatal(1,"Last accept");
        sample_valid=0; tick();
        if(result_valid) $fatal(1,"Only one drain edge");
        tick();
        if(!result_valid || !busy || done) $fatal(1,"Two drain edges required");
        tick(); tick();
        if(!result_valid) $fatal(1,"Backpressure");
        result_ready=1; tick();
        if(!done || busy || result_valid) $fatal(1,"Result handshake");
        result_ready=0; tick();
        if(done) $fatal(1,"Done must pulse");
        rst=1; tick(); rst=0;
        if(busy || input_valid || done) $fatal(1,"Reset");
        $display("PASS controller: %0d timing checkpoints",checks);
        $finish;
    end
    initial begin #10000; $fatal(1,"Timeout"); end
endmodule
