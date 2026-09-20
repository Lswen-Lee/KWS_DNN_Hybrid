`timescale 1ns/1ps
module tb_pe_weight_read_align;
    logic clk=0, rst=1;
    always #4 clk=~clk;
    logic in_valid=0, in_ready, in_last=0;
    logic [7:0] in_activation_u8=0;
    logic [8:0] in_weight_addr=0;
    logic weight_rd_valid, weight_rd_ready, weight_out_valid, weight_out_ready;
    logic [8:0] weight_rd_addr;
    wire [95:0] weight_data;
    logic out_valid, out_ready=0, out_last;
    logic [7:0] out_activation_u8;
    logic [95:0] out_weights;
    logic wr_valid=0, wr_ready;
    logic [3:0] wr_lane=0;
    logic [8:0] wr_addr=0;
    logic [7:0] wr_data=0;
    integer accepted=0, received=0, cancelled=0, stalls=0, overlap=0, checks=0;
    integer head=0, tail=0;
    logic [7:0] expected_a[0:4095];
    logic [8:0] expected_addr[0:4095];
    logic expected_last[0:4095];
    logic was_stalled=0;
    logic [104:0] held;
    logic [7:0] reference_mem[0:11][0:511];
    pe_weight_read_align dut (.*);
    pe_weight_buffer_12 #(.ADDR_WIDTH(9)) ram (
        .clk(clk), .rst(rst), .wr_valid(wr_valid), .wr_ready(wr_ready),
        .wr_lane(wr_lane), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_valid(weight_rd_valid), .rd_ready(weight_rd_ready), .rd_addr(weight_rd_addr),
        .out_valid(weight_out_valid), .out_ready(weight_out_ready), .weights_flat(weight_data)
    );
    // Scoreboard uses public handshakes and an independent RAM image.
    always @(posedge clk) begin
        if(rst) begin
            cancelled=cancelled+tail-head; head=tail; was_stalled=0;
            if(in_ready || out_valid || weight_rd_valid || weight_out_ready)
                $fatal(1,"Reset handshake not suppressed");
        end else begin
            if((in_valid && in_ready) != (weight_rd_valid && weight_rd_ready))
                $fatal(1,"Request/activation acceptance mismatch");
            if(was_stalled && (!out_valid || {out_activation_u8,out_weights,out_last} !== held))
                $fatal(1,"Output changed while stalled");
            was_stalled=out_valid && !out_ready;
            held={out_activation_u8,out_weights,out_last};
            if(out_valid) begin
                if(head==tail) $fatal(1,"Unexpected or zero-latency response");
                if(out_activation_u8 !== expected_a[head] || out_last !== expected_last[head])
                    $fatal(1,"Metadata mismatch");
                for(integer l=0;l<12;l=l+1) begin
                    if(out_weights[l*8+:8] !== reference_mem[l][expected_addr[head]])
                        $fatal(1,"Weight mismatch lane=%0d",l);
                    checks=checks+1;
                end
                if(out_ready) begin head=head+1; received=received+1; end
                else stalls=stalls+1;
            end
            if(in_valid && in_ready) begin
                if(tail>=4096) $fatal(1,"Scoreboard capacity");
                expected_a[tail]=in_activation_u8;
                expected_addr[tail]=in_weight_addr;
                expected_last[tail]=in_last;
                tail=tail+1; accepted=accepted+1;
                if(out_valid && out_ready) overlap=overlap+1;
            end
            if(wr_valid && wr_ready) reference_mem[wr_lane][wr_addr]=wr_data;
        end
    end
    // Called on a falling edge; hold source unchanged until accepted.
    task automatic send(input integer address, input integer a, input logic last_bit);
        if(address<0 || address>511 || a<0 || a>255) $fatal(1,"TB value range");
        in_valid=1; in_weight_addr=9'(address); in_activation_u8=8'(a); in_last=last_bit;
        do @(posedge clk); while(!in_ready);
        @(negedge clk); in_valid=0;
    endtask
    task automatic drain;
        out_ready=1;
        repeat(3) @(negedge clk);
        if(head != tail || out_valid) $fatal(1,"Drain failed");
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        // Populate every physical address including signed byte patterns.
        for(integer l=0;l<12;l=l+1)
            for(integer a=0;a<512;a=a+1) begin
                wr_valid=1; wr_lane=4'(l); wr_addr=9'(a); wr_data=8'(l*71+a*29);
                @(negedge clk);
            end
        wr_valid=0; out_ready=1;
        send(511,255,1); drain(); // K=1
        // FC1: three groups, each replays 144 activations. No input bubbles.
        for(integer g=0;g<3;g=g+1) begin
            for(integer k=0;k<144;k=k+1) begin
                send(g*144+k,k,k==143);
                if(!out_valid) $fatal(1,"Continuous-read throughput bubble");
            end
            drain();
        end
        // Deterministic jumps, source bubbles, and long output stalls.
        for(integer i=0;i<80;i=i+1) begin
            if(i%3==0) repeat(2) @(negedge clk);
            send((i*137)%512,(i*43)%256,i%9==0);
            if(i%4==0) begin
                out_ready=0;
                repeat(5) @(negedge clk);
                out_ready=1;
            end
        end
        drain();
        // Real buffer write priority blocks a read; source must be retained.
        wr_valid=1; wr_lane=0; wr_addr=500; wr_data=8'h80;
        in_valid=1; in_weight_addr=0; in_activation_u8=127; in_last=1;
        repeat(3) begin
            @(posedge clk); if(in_ready) $fatal(1,"Ignored RAM backpressure");
            @(negedge clk);
        end
        wr_valid=0;
        @(posedge clk); if(!in_ready) $fatal(1,"Retry failed");
        @(negedge clk); in_valid=0; drain();
        // Cancel a captured final item and a blocked following request.
        out_ready=0; send(500,128,1);
        in_valid=1; in_weight_addr=17; in_activation_u8=0; in_last=0;
        repeat(4) @(negedge clk);
        rst=1;
        @(negedge clk); rst=0; in_valid=0; out_ready=1;
        send(500,0,1); drain();
        if(accepted != received+cancelled || cancelled!=1 || overlap<429 || stalls==0)
            $fatal(1,"Coverage/accounting failed");
        $display("PASS read align accepted=%0d received=%0d cancelled=%0d overlap=%0d stalls=%0d weight_checks=%0d",accepted,received,cancelled,overlap,stalls,checks);
        $finish;
    end
    initial begin #1000000; $fatal(1,"Timeout"); end
endmodule
