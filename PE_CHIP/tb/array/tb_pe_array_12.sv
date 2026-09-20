`timescale 1ns/1ps

module tb_pe_array_12;
    logic clk=0;
    logic rst=0, clear=0, accumulate_en=0;
    logic [11:0] lane_mask=0;
    logic signed [8:0] activation_centered=0;
    // Drive known weights with reset in step(); X startup exercises initialization.
    logic [95:0] weight_vector_i8='x;
    logic [383:0] result_vector_s32;
    integer expected[0:11];
    integer pending[0:11];
    bit pending_valid[0:11];
    integer weights[0:11];
    integer checks=0, j, i, trial, k;
    always #5 clk=~clk;
    pe_array_12 dut (.*);

    // Drive on falling edge; observe after rising-edge nonblocking updates.
    // Reference deliberately uses literal interface dimensions, not DUT packing constants.
    task automatic step(input bit r,c,en, input logic [11:0] mask,
                        input integer activation);
        integer lane;
        integer actual;
        begin
            @(negedge clk);
            rst=r; clear=c; accumulate_en=en;
            lane_mask=mask; activation_centered=9'(activation);
            for(lane=0;lane<12;lane=lane+1) begin
                weight_vector_i8[lane*8 +: 8]=8'(weights[lane]);
                if(r || c) expected[lane]=0;
                else if(pending_valid[lane])
                    expected[lane]=expected[lane]+pending[lane];
                pending_valid[lane]=!r && !c && en && mask[lane];
                pending[lane]=activation*weights[lane];
            end
            @(posedge clk); #1;
            for(lane=0;lane<12;lane=lane+1) begin
                actual=$signed(result_vector_s32[lane*32 +: 32]);
                checks=checks+1;
                if(actual!==expected[lane])
                    $fatal(1,"check=%0d lane=%0d actual=%0d expected=%0d",
                           checks,lane,actual,expected[lane]);
            end
        end
    endtask

    initial begin
        if($bits(pe_pkg::activation_t)!=9 || $bits(pe_pkg::weight_t)!=8 ||
           $bits(pe_pkg::product_t)!=17 || $bits(pe_pkg::accumulator_t)!=32 ||
           pe_pkg::LANE_COUNT!=12 || pe_pkg::ACT_ZERO_POINT!=127 ||
           pe_pkg::ACT_U8_WIDTH!=8 || pe_pkg::WEIGHT_VECTOR_WIDTH!=96 ||
           pe_pkg::RESULT_VECTOR_WIDTH!=384)
            $fatal(1,"Package contract mismatch");
        for(j=0;j<12;j=j+1) begin expected[j]=0; weights[j]=j-6; end
        $display("TEST: reset, distinct signed weights, lane packing, hold");
        step(1,1,1,12'hfff,128);
        step(0,0,1,12'hfff,1);
        step(0,0,0,12'hfff,-127);
        $display("TEST: masks 0FF/AAA/555/000 and each one-hot lane");
        step(0,0,1,12'h0ff,3);
        step(0,0,1,12'haaa,-5);
        step(0,0,1,12'h555,7);
        step(0,0,1,12'h000,128);
        for(j=0;j<12;j=j+1) step(0,0,1,12'b1 << j,2);
        $display("TEST: clear overrides enable, even masked lanes clear; signed boundaries");
        step(0,1,1,12'h000,128);
        for(j=0;j<12;j=j+1) weights[j]=-128;
        step(0,0,1,12'hfff,-127);
        step(0,0,1,12'hfff,128);
        for(j=0;j<12;j=j+1) weights[j]=127;
        step(0,0,1,12'hfff,128);
        step(0,0,1,12'hfff,-127);
        step(1,1,1,12'hfff,128);
        for(trial=0;trial<3;trial=trial+1) begin
            if(trial==0) k=9;
            else if(trial==1) k=32;
            else k=144;
            $display("TEST: K=%0d deterministic mixed signs, stalls and restart",k);
            step(0,1,0,12'hfff,0);
            for(i=0;i<k;i=i+1) begin
                for(j=0;j<12;j=j+1) weights[j]=(i*37+j*19+trial*11)%256-128;
                if(i%7==0) step(0,0,0,12'hfff,128);
                if(trial==1) step(0,0,1,12'h0ff,(i*73)%256-127);
                else step(0,0,1,12'hfff,(i*73)%256-127);
            end
            step(0,0,0,12'hfff,0);
        end
        $display("PASS pe_array_12: %0d lane comparisons + package contract",checks);
        $finish;
    end
endmodule
