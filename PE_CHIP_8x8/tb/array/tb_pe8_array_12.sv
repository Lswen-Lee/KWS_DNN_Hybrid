`timescale 1ns/1ps
module tb_pe8_array_12;
    logic clk=0;
    logic rst=0,clear=0,accumulate_en=0;
    logic [11:0] lane_mask=0;
    logic [7:0] activation_u8=0;
    logic signed [7:0] activation_s8;
    // Drive known weights with reset in step(); X startup exercises initialization.
    logic [95:0] weight_vector_i8='x;
    logic [383:0] result_vector_s32;
    integer weights[0:11], raw_expected[0:11], original_expected[0:11], weight_sum[0:11];
    integer checks=0,i,j,k,trial;
    integer pending_raw[0:11], pending_original[0:11], pending_w[0:11];
    bit pending_valid[0:11];
    always #5 clk=~clk;
    activation_u8_to_s8 converter (.*);
    pe8_array_12 dut (.*);
    task automatic step(input bit r,c,en,input logic [11:0] mask,input integer au);
        integer lane,actual;
        begin
            @(negedge clk);
            rst=r;clear=c;accumulate_en=en;lane_mask=mask;activation_u8=8'(au);
            for(lane=0;lane<12;lane=lane+1) begin
                weight_vector_i8[lane*8 +: 8]=8'(weights[lane]);
                if(r || c) begin
                    raw_expected[lane]=0; original_expected[lane]=0; weight_sum[lane]=0;
                end else if(pending_valid[lane]) begin
                    raw_expected[lane]=raw_expected[lane]+pending_raw[lane];
                    original_expected[lane]=original_expected[lane]+pending_original[lane];
                    weight_sum[lane]=weight_sum[lane]+pending_w[lane];
                end
                pending_valid[lane]=!r && !c && en && mask[lane];
                pending_raw[lane]=(au-128)*weights[lane];
                pending_original[lane]=(au-127)*weights[lane];
                pending_w[lane]=weights[lane];
            end
            @(posedge clk); #1;
            for(lane=0;lane<12;lane=lane+1) begin
                actual=$signed(result_vector_s32[lane*32 +: 32]);
                checks=checks+1;
                if(actual!==raw_expected[lane])
                    $fatal(1,"raw check=%0d lane=%0d actual=%0d expected=%0d",
                           checks,lane,actual,raw_expected[lane]);
                // Testbench correction only, independently referenced to original formula.
                if((actual+weight_sum[lane])!==original_expected[lane])
                    $fatal(1,"corrected check=%0d lane=%0d",checks,lane);
            end
        end
    endtask
    initial begin
        if(pe8_pkg::LANE_COUNT!=12 || pe8_pkg::ACT_U8_WIDTH!=8 ||
           pe8_pkg::ACT_ZERO_POINT!=127 || pe8_pkg::ACT_RECODE_OFFSET!=128 ||
           $bits(pe8_pkg::activation_t)!=8 || $bits(pe8_pkg::weight_t)!=8 ||
           $bits(pe8_pkg::product_t)!=16 || $bits(pe8_pkg::accumulator_t)!=32 ||
           pe8_pkg::WEIGHT_VECTOR_WIDTH!=96 || pe8_pkg::RESULT_VECTOR_WIDTH!=384)
            $fatal(1,"Package contract mismatch");
        for(j=0;j<12;j=j+1) begin
            weights[j]=j-6;raw_expected[j]=0;original_expected[j]=0;weight_sum[j]=0;
        end
        $display("TEST: reset, packing, mixed signed weights, enable hold");
        step(1,1,1,12'hfff,255);
        step(0,0,1,12'hfff,129);
        step(0,0,0,12'hfff,0);
        $display("TEST: FFF/0FF/AAA/555/000 and 12 one-hot masks");
        step(0,0,1,12'h0ff,131);
        step(0,0,1,12'haaa,123);
        step(0,0,1,12'h555,135);
        step(0,0,1,12'h000,255);
        for(j=0;j<12;j=j+1) step(0,0,1,12'b1 << j,130);
        $display("TEST: clear masked lanes; signed endpoint products");
        step(0,1,1,12'h000,255);
        for(j=0;j<12;j=j+1) weights[j]=-128;
        step(0,0,1,12'hfff,0);
        step(0,0,1,12'hfff,255);
        for(j=0;j<12;j=j+1) weights[j]=127;
        step(0,0,1,12'hfff,0);
        step(0,0,1,12'hfff,255);
        step(1,1,1,12'hfff,255);
        $display("TEST: A=127 produces zero after correction, A=128 has zero raw product");
        step(0,0,1,12'hfff,127);
        step(0,1,0,12'hfff,0);
        step(0,0,1,12'hfff,128);
        for(trial=0;trial<3;trial=trial+1) begin
            if(trial==0) k=9;
            else if(trial==1) k=32;
            else k=144;
            $display("TEST: K=%0d mixed data, stalls, restart and reference correction",k);
            step(0,1,0,12'hfff,0);
            for(i=0;i<k;i=i+1) begin
                for(j=0;j<12;j=j+1) weights[j]=(i*37+j*19+trial*11)%256-128;
                if(i%7==0) step(0,0,0,12'hfff,255);
                if(trial==1) step(0,0,1,12'h0ff,(i*73)%256);
                else step(0,0,1,12'hfff,(i*73)%256);
            end
            step(0,0,0,12'hfff,0);
        end
        $display("PASS pe8_array_12: %0d lane checks (raw + corrected), package contract",checks);
        $finish;
    end
endmodule
