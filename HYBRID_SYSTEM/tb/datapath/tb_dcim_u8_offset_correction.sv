`timescale 1ns/1ps
module tb_dcim_u8_offset_correction;
    logic clk=0,rst=1,in_valid=0; always #4 clk=~clk;
    logic [31:0] unsigned_mac=0,activation_sum=0,offset_weight_sum=0;
    logic [15:0] term_count=0;
    wire out_valid,overflow; wire signed [31:0] accumulator;
    dcim_u8_offset_correction dut (.*);
    integer checks=0;
    task automatic check(input longint signed golden,input logic ov);
        @(posedge clk); #1;
        if(!out_valid || accumulator!==32'(golden) || overflow!==ov)
            $fatal(1,"DCIM correction actual=%0d expected=%0d overflow=%0d",accumulator,golden,overflow);
        checks++;
    endtask
    initial begin : run
        integer a,w,wu,kk;
        longint signed golden;
        repeat(3) @(negedge clk); rst=0;
        for(integer t=0;t<300;t++) begin
            @(negedge clk); in_valid=1;
            kk=1+(t*13)%144; term_count=16'(kk);
            unsigned_mac=0; activation_sum=0; offset_weight_sum=0; golden=0;
            for(integer k=0;k<kk;k++) begin
                a=(k*43+t*71)%256; w=(k*29+t*17)%256-128; wu=w+128;
                unsigned_mac+=32'(a*wu); activation_sum+=32'(a); offset_weight_sum+=32'(wu);
                golden+=(longint'(a)-128)*longint'(w);
            end
            check(golden,0);
        end
        // Inconsistent input statistics deliberately test both overflow guards.
        @(negedge clk); unsigned_mac=32'hffffffff; activation_sum=0; offset_weight_sum=0; term_count=0;
        check(2147483647,1);
        @(negedge clk); unsigned_mac=0; activation_sum=32'hffffffff;
        check(-64'sd2147483648,1);
        @(negedge clk); in_valid=0;
        @(posedge clk); #1; if(out_valid) $fatal(1,"bubble failed");
        @(negedge clk); rst=1; in_valid=1;
        @(posedge clk); #1; if(out_valid) $fatal(1,"reset failed");
        $display("PASS DCIM offset correction %0d outputs and reset/bubble",checks);
        $finish;
    end
endmodule
