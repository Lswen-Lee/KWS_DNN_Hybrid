`timescale 1ns/1ps
module tb_pe_array_comparison;
    logic clk=0;
    logic rst=0,clear=0,accumulate_en=0;
    logic [11:0] lane_mask=0;
    logic [7:0] activation_u8=0;
    logic signed [8:0] activation_centered;
    logic signed [7:0] activation_s8;
    // Drive known weights with reset in step(); X startup exercises initialization.
    logic [95:0] weight_vector_i8='x;
    logic [383:0] result9,result8;
    integer w[0:11],gold9[0:11],gold8[0:11],sumw[0:11];
    integer checks=0,i,j,t,k,kind;
    integer pending9[0:11],pending8[0:11],pendingw[0:11];
    bit pending_valid[0:11];
    logic [31:0] random_state=32'h19a2b3c4;
    logic [11:0] random_mask;
    integer random_a;
    always #5 clk=~clk;
    activation_center_127 center (.activation_u8(activation_u8),.activation_centered(activation_centered));
    activation_u8_to_s8 recode (.activation_u8(activation_u8),.activation_s8(activation_s8));
    pe_array_12 original (
        .clk(clk),.rst(rst),.clear(clear),.accumulate_en(accumulate_en),
        .lane_mask(lane_mask),.activation_centered(activation_centered),
        .weight_vector_i8(weight_vector_i8),.result_vector_s32(result9));
    pe8_array_12 alternative (
        .clk(clk),.rst(rst),.clear(clear),.accumulate_en(accumulate_en),
        .lane_mask(lane_mask),.activation_s8(activation_s8),
        .weight_vector_i8(weight_vector_i8),.result_vector_s32(result8));
    // Explicit LCG seed, independent of simulator random implementation.
    task automatic next_random;
        random_state=random_state*32'd1664525+32'd1013904223;
    endtask
    task automatic step(input bit r,c,en,input logic [11:0] mask,input integer a);
        integer lane,actual9,actual8;
        begin
            @(negedge clk);
            rst=r;clear=c;accumulate_en=en;lane_mask=mask;activation_u8=8'(a);
            for(lane=0;lane<12;lane=lane+1) begin
                weight_vector_i8[lane*8 +: 8]=8'(w[lane]);
                if(r || c) begin gold9[lane]=0;gold8[lane]=0;sumw[lane]=0;end
                else if(pending_valid[lane]) begin
                    gold9[lane]=gold9[lane]+pending9[lane];
                    gold8[lane]=gold8[lane]+pending8[lane];
                    sumw[lane]=sumw[lane]+pendingw[lane];
                end
                pending_valid[lane]=!r && !c && en && mask[lane];
                pending9[lane]=(a-127)*w[lane];
                pending8[lane]=(a-128)*w[lane];
                pendingw[lane]=w[lane];
            end
            @(posedge clk); #1;
            for(lane=0;lane<12;lane=lane+1) begin
                actual9=$signed(result9[lane*32 +: 32]);
                actual8=$signed(result8[lane*32 +: 32]);
                checks=checks+1;
                if(actual9!==gold9[lane] || actual8!==gold8[lane] ||
                   actual9!==(actual8+sumw[lane]))
                    $fatal(1,"check=%0d lane=%0d pe9=%0d gold9=%0d pe8=%0d gold8=%0d sumw=%0d",
                           checks,lane,actual9,gold9[lane],actual8,gold8[lane],sumw[lane]);
            end
        end
    endtask
    initial begin
        for(j=0;j<12;j=j+1) begin w[j]=j-6;gold9[j]=0;gold8[j]=0;sumw[j]=0;end
        $display("TEST control, packing, masks, both raw references and corrected equivalence");
        step(1,1,1,12'hfff,255);
        step(0,0,1,12'hfff,200);
        step(0,0,0,12'hfff,0);
        step(0,0,1,12'h0ff,100);
        step(0,0,1,12'haaa,127);
        step(0,0,1,12'h555,128);
        step(0,0,1,12'h000,255);
        for(j=0;j<12;j=j+1) step(0,0,1,12'b1<<j,0);
        step(0,1,1,12'h000,255);
        for(j=0;j<12;j=j+1) w[j]=-128;
        step(0,0,1,12'hfff,0);
        step(0,0,1,12'hfff,255);
        for(j=0;j<12;j=j+1) w[j]=127;
        step(0,0,1,12'hfff,0);
        step(0,0,1,12'hfff,255);
        step(1,1,1,12'hfff,127);
        for(t=0;t<3;t=t+1) begin
            if(t==0) k=9;else if(t==1) k=32;else k=144;
            for(kind=0;kind<4;kind=kind+1) begin
                $display("TEST K=%0d pattern=%0d (positive/negative/zero/seeded mixed)",k,kind);
                step(0,1,0,12'hfff,0);
                for(i=0;i<k;i=i+1) begin
                    for(j=0;j<12;j=j+1) begin
                        next_random();
                        if(kind==0) w[j]=127;
                        else if(kind==1) w[j]=-128;
                        else if(kind==2) w[j]=0;
                        else w[j]=int'(random_state[31:24])-128;
                    end
                    next_random();random_a=int'(random_state[31:24]);
                    random_mask=12'hfff;
                    if(t==1) random_mask=12'h0ff;
                    if(kind==3) begin next_random();random_mask=random_state[31:20];end
                    if(i%7==0) step(0,0,0,random_mask,255);
                    step(0,0,1,random_mask,random_a);
                end
                step(0,0,0,12'hfff,0);
            end
        end
        $display("PASS comparison: %0d lane checks, three conditions each; seed=19a2b3c4",checks);
        $finish;
    end
endmodule
