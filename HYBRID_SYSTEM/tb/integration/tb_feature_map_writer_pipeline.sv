`timescale 1ns/1ps
module tb_feature_map_writer_pipeline;
    import kws_system_pkg::*;
    logic clk=0; always #4 clk=~clk;
    logic rst=1,cmd_valid=0,cmd_ready,in_valid=0,in_ready;
    activation_write_mode_t cmd_mode=WRITE_LINEAR;
    activation_addr_t cmd_base=100,wr_addr;
    logic [7:0] cmd_width=8,cmd_height=2;
    logic [5:0] cmd_channels=2;
    activation_count_t cmd_count=32;
    activation_t in_data=0,wr_data;
    logic [5:0] in_channel=0;
    logic [7:0] in_y=0,in_x=0;
    logic wr_en,busy,done,error;
    integer cycle=0,head=0,tail=0,commits=0,issued=0,successes=0,failures=0;
    integer addresses[0:255],due[0:255];
    logic [7:0] values[0:255];
    bit poisoned=0,corrupt=0;
    integer bad_index=-1,last_commit=-1;
    feature_map_writer dut(.*);
    // Real RAM is attached; the original TB also performs full RAM readback.
    logic rd_valid; activation_t rd_data;
    activation_buffer ram(.clk(clk),.rst(rst),.wr_en(wr_en),.wr_addr(wr_addr),
        .wr_data(wr_data),.rd_en(1'b0),.rd_addr(15'd0),.rd_valid(rd_valid),.rd_data(rd_data));
    always @(posedge clk) begin
        cycle++;
        if(!rst) begin
            if(in_valid && in_ready) begin
                if(issued==bad_index) poisoned=1;
                if(!poisoned) begin
                    addresses[tail]=cmd_mode==WRITE_LINEAR ? 100+issued :
                        100+int'(in_channel)*16+int'(in_y)*8+int'(in_x);
                    values[tail]=in_data ^ ((corrupt && issued==0) ? 8'd1 : 8'd0);
                    due[tail]=cycle+5;tail++;
                end
                issued++;
            end
            if(wr_en) begin
                if(head==tail || int'(wr_addr)!=addresses[head] || wr_data!==values[head])
                    $fatal(1,"PIPELINE_SCOREBOARD mismatch");
                if(cycle!=due[head]) $fatal(1,"pipeline latency expected five edges");
                head++;commits++;last_commit=cycle;
            end
        end
        #1;
        if(done) begin
            if(head!=tail || busy || error || cycle!=last_commit+1)
                $fatal(1,"pipeline terminal before drain");
            successes++;
        end
        if(error) begin
            if(head!=tail || busy || done || !poisoned) $fatal(1,"pipeline error flush");
            failures++;
        end
    end
    task automatic launch(input bit chw,input integer bad);
        @(negedge clk);
        head=0;tail=0;issued=0;poisoned=0;bad_index=bad;
        cmd_mode=chw ? WRITE_CHW : WRITE_LINEAR;cmd_valid=1;
        if(!cmd_ready) $fatal(1,"pipeline command not ready");
        @(negedge clk);cmd_valid=0;
        while(!in_ready) @(negedge clk);
    endtask
    task automatic stream(input bit bubbles,input bit expect_error);
        integer n;
        n=0;
        while(n<32 && in_ready) begin
            in_valid=1;in_data=8'(n*7+3);
            in_channel=6'(n%2);in_y=8'((n/2)/8);in_x=8'((n/2)%8);
            if(n==bad_index) in_channel=2;
            @(negedge clk);n++;
            if(bubbles && n%3==0 && in_ready) begin
                in_valid=0;@(negedge clk);
            end
        end
        in_valid=0;
        while(!done && !error) @(negedge clk);
        if(error!=expect_error) $fatal(1,"pipeline unexpected status");
        repeat(3) @(negedge clk);
    endtask
    initial begin
        corrupt=$test$plusargs("CORRUPT_EXPECTED");
        repeat(3) @(negedge clk);rst=0;
        launch(0,-1);stream(0,0);
        launch(1,-1);stream(0,0);
        launch(1,-1);stream(1,0);
        // First/middle/last malformed payload, younger inputs stay continuous.
        launch(1,0);stream(0,1);
        launch(1,7);stream(0,1);
        launch(1,31);stream(0,1);
        // Reset at each occupancy age S0..S4, including pending before RAM edge.
        for(integer age=0;age<5;age++) begin
            launch(0,-1);
            in_valid=1;in_data=8'ha5;
            @(negedge clk);in_valid=0;
            repeat(age) @(negedge clk);
            rst=1;head=0;tail=0;
            repeat(2) @(negedge clk);
            if(wr_en || done || error || busy) $fatal(1,"pipeline reset residue");
            rst=0;
            repeat(7) begin @(negedge clk);if(wr_en || done || error) $fatal(1,"late reset residue");end
            launch(0,-1);stream(0,0);
        end
        if(successes!=8 || failures!=3) $fatal(1,"pipeline coverage missing");
        $display("PASS writer pipeline success=%0d error=%0d commits=%0d",successes,failures,commits);
        $finish;
    end
    initial begin #100000; $fatal(1,"pipeline watchdog");end
endmodule
