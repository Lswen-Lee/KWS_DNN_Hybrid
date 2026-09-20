`timescale 1ns/1ps
module tb_pe8_core_12;
    logic clk=0,rst=1,start=0,sample_valid=0,result_ready=0;
    logic [7:0] k_length=0,activation_u8=0;
    logic [11:0] lane_mask=0;
    logic [95:0] weight_vector_i8=0;
    wire busy,done,sample_ready,result_valid;
    wire [383:0] result_vector_s32;
    integer gold[0:11];
    integer checks=0,transactions=0,cycle=0,last_accept=-100;
    integer i,j,t,kk,aa,ww;
    logic [11:0] mask;
    pe8_core_12 dut (.*);
    always #5 clk=~clk;
    always @(posedge clk) begin
        cycle=cycle+1;
        if(sample_valid && sample_ready) last_accept=cycle;
    end
    task automatic tick;
        @(posedge clk); #1; @(negedge clk);
    endtask
    task automatic begin_work(input integer k,input logic [11:0] m);
        if(k<1 || k>255) $fatal(1,"Invalid test K");
        start=1; k_length=8'(k); lane_mask=m;
        tick();
        if(!busy) $fatal(1,"Command not accepted");
        start=0;
        // Change command pins while busy: latched configuration must be used.
        k_length=0; lane_mask=~m;
        tick();
        if(!sample_ready) $fatal(1,"RUN not ready");
        for(integer n=0;n<12;n=n+1) gold[n]=0;
    endtask
    task automatic finish_work;
        sample_valid=0;
        tick();
        if(result_valid) $fatal(1,"Premature result");
        tick();
        if(!result_valid || cycle-last_accept!=2)
            $fatal(1,"Expected exactly two drain clocks");
        for(integer hold_cycle=0;hold_cycle<4;hold_cycle=hold_cycle+1) begin
            for(integer n=0;n<12;n=n+1) begin
                checks=checks+1;
                if($signed(result_vector_s32[n*32+:32])!==gold[n])
                    $fatal(1,"lane %0d actual %0d gold %0d",n,
                        $signed(result_vector_s32[n*32+:32]),gold[n]);
            end
            // Unaccepted inputs and commands cannot alter the held result.
            start=1; sample_valid=1; activation_u8=255; weight_vector_i8='1;
            tick();
            if(!result_valid || sample_ready || done) $fatal(1,"Result hold");
        end
        start=0; sample_valid=0; result_ready=1; tick();
        if(!done || busy) $fatal(1,"Done handshake");
        result_ready=0; tick();
        if(done) $fatal(1,"Done pulse");
        transactions=transactions+1;
    endtask
    initial begin
        tick(); rst=0;
        start=1; k_length=0; tick();
        if(busy || done || result_valid || sample_ready) $fatal(1,"K0 ignored");
        start=0;
        for(t=0;t<6;t=t+1) begin
            case(t)
                0: begin kk=1; mask=12'hfff; end
                1: begin kk=9; mask=12'haaa; end
                2: begin kk=32; mask=12'h0ff; end
                3: begin kk=144; mask=12'hfff; end
                5: begin kk=9; mask=12'h000; end
                default: begin kk=255; mask=12'hfff; end
            endcase
            begin_work(kk,mask);
            for(i=0;i<kk;i=i+1) begin
                if(i%5==0) begin
                    sample_valid=0; tick(); tick();
                    if(!sample_ready || result_valid) $fatal(1,"Input stall");
                end
                aa=(i*73+t*29)%256;
                activation_u8=8'(aa);
                for(j=0;j<12;j=j+1) begin
                    ww=(i*37+j*19)%256-128;
                    weight_vector_i8[j*8+:8]=8'(ww);
                    if(mask[j]) gold[j]=gold[j]+(aa-128)*ww;
                end
                sample_valid=1;
                if(!sample_ready) $fatal(1,"Unexpected backpressure");
                tick();
            end
            finish_work();
        end
        // Reset each active state including a pending last product and held result.
        for(t=0;t<4;t=t+1) begin
            if(t==0) begin start=1; k_length=1; lane_mask='1; tick(); start=0; end
            else begin
                begin_work(1,12'hfff);
                if(t>=2) begin sample_valid=1; tick(); sample_valid=0; end
                if(t==3) begin tick(); tick(); end
            end
            rst=1; tick(); rst=0; sample_valid=0; start=0;
            if(busy || done || result_valid || result_vector_s32!==0)
                $fatal(1,"Reset active state %0d",t);
            tick();
        end
        $display("PASS core: %0d result checks, %0d jobs, K0/stalls/drain/backpressure/reset",
                 checks,transactions);
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout"); end
endmodule
