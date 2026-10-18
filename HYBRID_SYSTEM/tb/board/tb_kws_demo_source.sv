`timescale 1ns/1ps
module tb_kws_demo_source;
    logic clk=0,rst=1,enable=1;
    always #4 clk=~clk;
    logic input_request_valid=0,input_is_flatten=0,input_request_ready,input_valid,input_ready=0;
    logic [15:0] input_count=8064;
    logic [7:0] input_data;
    logic weight_request_valid=0,weight_request_ready,weight_valid,weight_ready=0;
    logic [2:0] weight_layer_id=0;
    logic [7:0] weight_k=0;
    logic [5:0] weight_channels=0;
    logic signed [7:0] weight_i8;
    logic fault,busy;
    kws_demo_source #(.DEMO_FILE("build/kws_board_vectors/kws_demo.mem")) dut (.*);
    logic [7:0] expected[0:15627];
    string vectors;
    integer count=0,base=0,total=0,checks=0,cycles=0;
    bit checking=0,kind=0,held=0;
    logic [7:0] held_data;
    always @(posedge clk) begin
        cycles++;
        if(cycles>200000) $fatal(1,"source watchdog");
        if(!rst && checking) begin
            if(fault || (input_valid && weight_valid)) $fatal(1,"source invalid output");
            if(held && (!(kind ? weight_valid : input_valid) || (kind ? weight_i8 : input_data)!==held_data))
                $fatal(1,"source changed stalled byte");
            held=(kind ? weight_valid && !weight_ready : input_valid && !input_ready);
            held_data=kind ? weight_i8 : input_data;
            if((input_valid && input_ready) || (weight_valid && weight_ready)) begin
                if(count>=total || (kind ? weight_i8 : input_data)!==expected[base+count])
                    $fatal(1,"source byte mismatch base=%0d n=%0d",base,count);
                count++;checks++;
            end
        end
    end
    task automatic reset_source;
        @(negedge clk);checking=0;held=0;rst=1;input_request_valid=0;weight_request_valid=0;input_ready=0;weight_ready=0;
        repeat(3) @(negedge clk);rst=0;@(negedge clk);
        if(fault || busy || input_valid || weight_valid) $fatal(1,"source reset residue");
    endtask
    task automatic transfer(input bit is_weight,input integer id,n,b);
        kind=is_weight;base=b;total=n;count=0;held=0;checking=1;
        input_count=8064;input_is_flatten=0;
        weight_layer_id=3'(id);weight_k=8'(id==0 ? 9 : id==3 ? 144 : id==4 ? 32 : 108);
        weight_channels=6'(id==3 ? 32 : id==4 ? 8 : 12);
        input_request_valid=!is_weight;weight_request_valid=is_weight;
        do @(posedge clk);while(!(is_weight ? weight_request_ready : input_request_ready));
        @(negedge clk);input_request_valid=0;weight_request_valid=0;
        // Live metadata is deliberately poisoned after acceptance.
        input_count=0;weight_layer_id=7;weight_k=0;weight_channels=0;
        while(count<n) begin
            input_ready=!is_weight && cycles%5!=0;
            weight_ready=is_weight && cycles%7!=0;
            @(negedge clk);
        end
        input_ready=0;weight_ready=0;checking=0;held=0;
        if(busy || fault) $fatal(1,"source final byte not retired");
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"Missing VECTORS");
        $readmemh({vectors,"/quant_input.mem"},expected,0,8063);
        $readmemh({vectors,"/conv1_weights.mem"},expected,8064,8171);
        $readmemh({vectors,"/conv2_weights.mem"},expected,8172,9467);
        $readmemh({vectors,"/conv3_weights.mem"},expected,9468,10763);
        $readmemh({vectors,"/fc1_weights.mem"},expected,10764,15371);
        $readmemh({vectors,"/fc2_weights.mem"},expected,15372,15627);
        if($test$plusargs("CORRUPT_EXPECTED")) expected[8172]^=1;
        reset_source();transfer(0,0,8064,0);
        transfer(1,0,108,8064);transfer(1,1,1296,8172);transfer(1,2,1296,9468);
        transfer(1,3,4608,10764);transfer(1,4,256,15372);
        if(checks!=15628) $fatal(1,"source coverage");
        // Duplicate input is rejected after a completed run.
        input_count=8064;input_request_valid=1;@(negedge clk);input_request_valid=0;
        if(!fault) $fatal(1,"source duplicate not rejected");
        reset_source();input_count=0;input_request_valid=1;@(negedge clk);input_request_valid=0;
        if(!fault) $fatal(1,"source zero count not rejected");
        reset_source();weight_request_valid=1;@(negedge clk);weight_request_valid=0;
        if(!fault) $fatal(1,"source weight before input not rejected");
        // Reset while ROM byte is waiting for downstream ready.
        reset_source();input_count=8064;input_request_valid=1;@(negedge clk);input_request_valid=0;
        while(!input_valid) @(negedge clk);
        repeat(5) @(negedge clk);
        reset_source();transfer(0,0,8064,0);
        weight_layer_id=0;weight_k=8;weight_channels=12;weight_request_valid=1;
        @(negedge clk);weight_request_valid=0;
        if(!fault) $fatal(1,"source malformed weight not rejected");
        $display("PASS board source bytes=%0d original=15628 reset_recovery=8064 rejects=4",checks);
        $finish;
    end
endmodule
