`timescale 1ns/1ps
module tb_pe_channel_sum_memory;
    logic clk=0, rst=1, layer_clear=0;
    always #4 clk=~clk;
    logic wr_valid=0, wr_ready, rd_valid=0, rd_ready;
    logic [4:0] wr_channel_id=0, rd_channel_id=0, out_channel_id;
    logic signed [31:0] wr_weight_sum=0, out_weight_sum;
    logic out_valid, out_ready=0, out_error;
    logic signed [31:0] reference [0:31];
    logic [31:0] valid_reference=0;
    logic pending=0, expected_error=0;
    logic [4:0] expected_id=0;
    logic signed [31:0] expected_data=0;
    integer reads=0, writes=0, responses=0, stalls=0, aborted=0;
    pe_channel_sum_memory dut (.*);
    // Check output before advancing independent handshake-based scoreboard.
    always @(posedge clk) begin
        if (rst || layer_clear) begin
            if(pending) aborted=aborted+1;
            pending=0; valid_reference=0;
            if(wr_ready || rd_ready) $fatal(1,"Accept during clear/reset");
        end else begin
            if(out_valid !== pending) $fatal(1,"Response valid mismatch");
            if(pending) begin
                if(out_channel_id !== expected_id || out_error !== expected_error ||
                   out_weight_sum !== expected_data) $fatal(1,"Response mismatch");
                if(out_ready) begin pending=0; responses=responses+1; end
                else stalls=stalls+1;
            end
            if(wr_valid && wr_ready) begin
                if(rd_ready) $fatal(1,"Write priority failed");
                reference[wr_channel_id]=wr_weight_sum;
                valid_reference[wr_channel_id]=1;
                writes=writes+1;
            end
            if(rd_valid && rd_ready) begin
                pending=1; expected_id=rd_channel_id;
                expected_error=!valid_reference[rd_channel_id];
                expected_data=valid_reference[rd_channel_id] ? reference[rd_channel_id] : 0;
                reads=reads+1;
            end
        end
    end
    task automatic write_value(input logic [4:0] id, input logic signed [31:0] data);
        @(negedge clk); wr_valid=1; wr_channel_id=id; wr_weight_sum=data;
        @(negedge clk); wr_valid=0;
    endtask
    task automatic read_value(input logic [4:0] id);
        @(negedge clk); rd_valid=1; rd_channel_id=id;
        do @(posedge clk); while(!rd_ready);
        @(negedge clk); rd_valid=0;
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0; out_ready=1;
        for(integer i=0;i<32;i=i+1) read_value(5'(i));
        for(integer i=0;i<32;i=i+1) write_value(5'(i), (i-16)*1234);
        write_value(0,32'sh80000000); write_value(31,32'sh7fffffff);
        // Continuous reads: consume old response and replace each clock.
        @(negedge clk); rd_valid=1;
        for(integer i=0;i<32;i=i+1) begin
            rd_channel_id=5'(i);
            @(posedge clk); if(!rd_ready) $fatal(1,"Throughput failed");
            @(negedge clk);
        end
        rd_valid=0;
        repeat(2) @(negedge clk);
        out_ready=0; read_value(0);
        write_value(0,32'sd42); // Must not alter previously captured response.
        repeat(4) @(negedge clk);
        out_ready=1;
        read_value(0);
        // Retry read unchanged after simultaneous write takes priority.
        @(negedge clk); wr_valid=1; wr_channel_id=2; wr_weight_sum=-9;
        rd_valid=1; rd_channel_id=2;
        @(negedge clk); wr_valid=0;
        @(negedge clk); rd_valid=0;
        repeat(2) @(negedge clk);
        out_ready=0; read_value(2);
        @(negedge clk); layer_clear=1; wr_valid=1; rd_valid=1;
        @(negedge clk); layer_clear=0; wr_valid=0; rd_valid=0; out_ready=1;
        for(integer i=0;i<32;i=i+1) read_value(5'(i));
        write_value(7,0); read_value(7); // Valid zero differs from invalid zero.
        repeat(2) @(negedge clk);
        out_ready=0; read_value(7);
        @(negedge clk); rst=1;
        @(negedge clk); rst=0; out_ready=1;
        read_value(7);
        repeat(3) @(negedge clk);
        if(pending || responses+aborted != reads) $fatal(1,"Undrained responses");
        $display("PASS sum memory writes=%0d reads=%0d responses=%0d stalls=%0d aborted=%0d",writes,reads,responses,stalls,aborted);
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout"); end
endmodule
