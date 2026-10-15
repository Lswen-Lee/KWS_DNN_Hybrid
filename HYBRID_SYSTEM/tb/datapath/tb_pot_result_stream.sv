`timescale 1ns/1ps
module tb_pot_result_stream;
    parameter bit POSTPROCESS_PIPELINED=1;
    logic clk=0,rst=1; always #4 clk=~clk;
    logic in_valid=0; wire in_ready;
    logic signed [31:0] accumulator=0;
    logic [2:0] layer_id=0; logic [4:0] channel_id=0;
    logic in_last=0,in_error=0,relu_enable=0;
    wire out_valid; logic out_ready=0;
    wire [7:0] output_uint8; wire [4:0] out_channel_id;
    wire out_last,out_error,empty;
    pot_result_stream #(.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) dut (.*);
    logic [14:0] expected[0:2047],held_payload;
    integer sent=0,received=0,checks=0,cycles=0,full_cycles=0;
    logic held=0,drain=0;
    logic force_stall=1;
    integer simultaneous=0,max_pending=0,full_pop=0;
    function automatic integer model_k(input integer l,c);
        case(l)
            0: return c<12 ? ((c==0 || c==4 || c==10) ? 8 : 9) : -1;
            1: return c<12 ? (c==0 ? 9 : ((c==4 || c==6) ? 7 : 8)) : -1;
            2: return c<12 ? (c==7 ? 10 : (c==8 ? 9 : 8)) : -1;
            3: return (c==10 || c==13 || c==23 || c==27 || c==28) ? 8 : 7;
            4: return c<8 ? 6 : -1;
            default: return -1;
        endcase
    endfunction
    function automatic logic [7:0] quant(input integer acc,k,input logic relu_on);
        longint signed mag,d,q,r;
        mag=acc<0 ? -longint'(acc) : longint'(acc); d=64'sd1<<k;
        q=mag/d; r=mag%d;
        if(2*r>d || (2*r==d && q%2==1)) q++;
        if(acc<0) q=-q;
        q+=128;
        if(q<0) q=0;
        if(q>255) q=255;
        if(relu_on && q<128) q=128;
        return 8'(q);
    endfunction
    always @(negedge clk) begin
        #1; out_ready=!force_stall && (drain || cycles%43>=24);
    end
    always @(posedge clk) begin : scoreboard
        integer k;
        cycles++;
        if(rst) begin sent=0; received=0; held=0; end
        else begin
            if(empty !== (sent==received)) $fatal(1,"empty misses FIFO/in-flight data");
            if(in_ready !== (sent-received<8)) $fatal(1,"capacity/ready policy mismatch");
            if(sent-received==8 && out_valid && out_ready) full_pop++;
            if(held && (!out_valid || held_payload!=={out_error,out_last,out_channel_id,output_uint8}))
                $fatal(1,"FIFO payload changed while stalled");
            held=out_valid && !out_ready;
            held_payload={out_error,out_last,out_channel_id,output_uint8};
            if(in_valid && !in_ready) full_cycles++;
            if(in_valid && in_ready) begin
                k=model_k(int'(layer_id),int'(channel_id));
                expected[sent]={in_error || k<0,in_last,channel_id,quant(accumulator,k<0 ? 0 : k,relu_enable)};
                sent++;
            end
            if(out_valid && out_ready) begin
                if(received>=sent || {out_error,out_last,out_channel_id,output_uint8}!==expected[received])
                    $fatal(1,"stream mismatch received=%0d",received);
                received++; checks++;
            end
            if(in_valid && in_ready && out_valid && out_ready) simultaneous++;
            if(sent-received>max_pending) max_pending=sent-received;
            if(sent-received>8) $fatal(1,"more than eight outstanding transactions");
        end
        if(cycles>15000) $fatal(1,"timeout");
    end
    task automatic send(input integer index);
        @(negedge clk);
        in_valid=1; layer_id=3'(index/32); channel_id=5'(index);
        accumulator=index%2==0 ? (index*113-28000) : (28000-index*173);
        relu_enable=(index%3==0); in_last=(index%12==11); in_error=(index%19==0);
        do @(posedge clk); while(!in_ready);
    endtask
    initial begin
        repeat(4) @(negedge clk); rst=0;
        // E0 accepts first input. Comb captures directly into FIFO at E0;
        // original pipeline must not yet expose an output at this edge.
        send(0); #1;
        if(out_valid !== !POSTPROCESS_PIPELINED) $fatal(1,"first output latency mismatch");
        for(integer i=1;i<8;i++) send(i);
        @(negedge clk); in_valid=0;
        repeat(8) @(negedge clk);
        if(in_ready || !out_valid || sent!=8 || received!=0) $fatal(1,"full FIFO test failed");
        // Reset full FIFO: no accepted pre-reset result may leak out.
        rst=1;
        repeat(3) @(negedge clk); rst=0;
        repeat(3) @(negedge clk);
        if(out_valid || !in_ready) $fatal(1,"full FIFO reset failed");
        // Leave accepted items in-flight and reset: no stale outputs may survive.
        send(0); send(1);
        @(negedge clk); rst=1; in_valid=0;
        repeat(3) @(negedge clk); rst=0;
        repeat(8) @(negedge clk);
        if(out_valid) $fatal(1,"stale output after reset");
        force_stall=0;
        for(integer i=0;i<768;i++) send(i%256);
        @(negedge clk); in_valid=0; drain=1;
        wait(received==sent); repeat(6) @(negedge clk);
        if(sent!=768 || full_cycles==0 || out_valid || simultaneous==0 || max_pending!=8 || full_pop==0)
            $fatal(1,"coverage/drain failed");
        $display("PASS PoT stream POST_PIPE=%0d 768 outputs, all 256 ROM addresses, errors, mixed tags, full/reset/latency; checked=%0d simultaneous=%0d full_pop=%0d",POSTPROCESS_PIPELINED,checks,simultaneous,full_pop);
        $finish;
    end
endmodule
