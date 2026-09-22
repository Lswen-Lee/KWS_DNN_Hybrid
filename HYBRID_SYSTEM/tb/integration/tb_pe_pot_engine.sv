`timescale 1ns/1ps
// Public-port integration: actual BRAM/loader/aligner/PE/result/FIFO path.
module tb_pe_pot_engine;
    parameter bit PE8_MODE=1, RESULT_PIPELINED=0;
    parameter bit POSTPROCESS_PIPELINED=1;
    logic clk=0,rst=1;
    always #4 clk=~clk;
    logic load_valid=0; wire load_ready;
    logic [7:0] load_k=0; logic [5:0] load_channels=0;
    wire load_busy,load_done,load_error,layer_ready;
    logic weight_valid=0; wire weight_ready; logic signed [7:0] weight_i8=0;
    logic compute_valid=0; wire compute_ready,compute_busy,compute_done,compute_error;
    logic [2:0] compute_layer_id=0; logic relu_enable=0;
    wire replay_valid; logic replay_ready=0;
    wire [7:0] replay_k; wire [4:0] replay_channel_base;
    logic activation_valid=0; wire activation_ready; logic [7:0] activation_u8=0;
    wire out_valid; logic out_ready=0; wire [7:0] out_data;
    wire [4:0] out_channel_id; wire out_group_last,out_error;
    pe_pot_engine #(.PE8_MODE(PE8_MODE),.RESULT_PIPELINED(RESULT_PIPELINED),
        .POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) dut (.*);
    integer layer=0,k_count=0,c_count=0,received=0,checked=0,cycles=0;
    integer final_stalls=0,stall_checks=0,jobs=0;
    logic check_enable=0,do_relu=0,held=0;
    logic [14:0] held_output;
    function automatic integer w(input integer c,k);
        integer v; v=(71*c+29*k+128+17*layer)%256;
        return v>=128 ? v-256 : v;
    endfunction
    function automatic integer a(input integer k);
        return (43*k+17+61*layer)%256;
    endfunction
    // Independent model constants, NOT a read of the DUT ROM.
    function automatic integer shift_for(input integer l,c);
        case(l)
            0: return c==0 || c==4 || c==10 ? 8 : 9;
            1: begin
                if(c==0) return 9;
                if(c==4 || c==6) return 7;
                return 8;
            end
            2: return c==7 ? 10 : (c==8 ? 9 : 8);
            3: return c==10 || c==13 || c==23 || c==27 || c==28 ? 8 : 7;
            4: return 6;
            default: return 0;
        endcase
    endfunction
    function automatic integer golden(input integer c);
        longint signed acc,mag,q,remn,divisor;
        acc=0;
        for(integer k=0;k<k_count;k++) acc+=(longint'(a(k))-128)*longint'(w(c,k));
        // Absolute-value division and remainder: different implementation than RTL floor shift.
        divisor=64'sd1<<shift_for(layer,c); mag=acc<0 ? -acc : acc;
        q=mag/divisor; remn=mag%divisor;
        if(2*remn>divisor || (2*remn==divisor && q%2==1)) q++;
        if(acc<0) q=-q;
        q+=128;
        if(q<0) q=0;
        if(q>255) q=255;
        if(do_relu && q<128) q=128;
        return int'(q);
    endfunction
    always @(negedge clk) begin
        #1;
        out_ready=check_enable && cycles%7!=0;
        if(check_enable && received==c_count-1 && out_valid && final_stalls<20) begin
            out_ready=0; final_stalls++;
        end
    end
    always @(posedge clk) begin
        cycles++;
        if(rst) held=0;
        else begin
            if(held) begin
                if(!out_valid || {out_error,out_group_last,out_channel_id,out_data}!==held_output)
                    $fatal(1,"Output changed under backpressure");
                stall_checks++;
            end
            held=out_valid && !out_ready;
            held_output={out_error,out_group_last,out_channel_id,out_data};
            if(check_enable && out_valid && out_ready) begin
                if(int'(out_channel_id)!=received || int'(out_data)!=golden(received) || out_error!==(layer>4))
                    $fatal(1,"layer=%0d channel=%0d actual=%0d expected=%0d",layer,received,out_data,golden(received));
                if(out_group_last !== (received%12==11 || received==c_count-1))
                    $fatal(1,"group last mismatch");
                received++; checked++;
            end
            if(compute_busy && (load_ready || compute_ready)) $fatal(1,"command exclusion failed");
            if(compute_done && received!=c_count) $fatal(1,"done before last output accepted");
        end
        if(cycles>150000) $fatal(1,"timeout");
    end
    task automatic run_layer(input integer l,kk,cc,input logic relu_on);
        layer=l; k_count=kk; c_count=cc; do_relu=relu_on;
        received=0; final_stalls=0;
        @(negedge clk); load_k=8'(kk); load_channels=6'(cc); load_valid=1;
        do @(posedge clk); while(!load_ready);
        @(negedge clk); load_valid=0;
        for(integer c=0;c<cc;c++) begin
            for(integer k=0;k<kk;k++) begin
                @(negedge clk); weight_valid=1; weight_i8=8'(w(c,k));
                do @(posedge clk); while(!weight_ready);
                @(negedge clk); weight_valid=0;
            end
        end
        wait(load_done); #1;
        if(load_error || !layer_ready) $fatal(1,"load failed");
        @(negedge clk); compute_layer_id=3'(l); relu_enable=relu_on; compute_valid=1;
        do @(posedge clk); while(!compute_ready);
        @(negedge clk); compute_valid=0; check_enable=1;
        // Inputs may change after handshake; frozen descriptor must still be used.
        compute_layer_id=7; relu_enable=!relu_on;
        for(integer base=0;base<cc;base+=12) begin
            @(negedge clk); replay_ready=1;
            do @(posedge clk); while(!replay_valid);
            if(int'(replay_k)!=kk || int'(replay_channel_base)!=base) $fatal(1,"replay descriptor mismatch");
            @(negedge clk); replay_ready=0;
            for(integer k=0;k<kk;k++) begin
                @(negedge clk); activation_valid=1; activation_u8=8'(a(k));
                do @(posedge clk); while(!activation_ready);
                @(negedge clk); activation_valid=0;
            end
        end
        wait(compute_done); #1;
        if(compute_error!==(l>4) || received!=cc || final_stalls!=20) $fatal(1,"job completion mismatch");
        jobs++;
        @(negedge clk); check_enable=0;
        repeat(4) @(negedge clk);
    endtask
    initial begin
        repeat(4) @(negedge clk); rst=0;
        run_layer(0,9,12,1);
        run_layer(1,108,12,1);
        run_layer(2,108,12,1);
        run_layer(3,144,32,1);
        run_layer(4,32,8,0);
        run_layer(3,144,32,0);
        run_layer(5,1,1,0); // Unsupported ROM layer must propagate error and still drain.
        if(stall_checks<120) $fatal(1,"stall coverage missing");
        $display("PASS pe_pot_engine PE8=%0d PIPE=%0d POST_PIPE=%0d jobs=%0d outputs=%0d stalls=%0d",PE8_MODE,RESULT_PIPELINED,POSTPROCESS_PIPELINED,jobs,checked,stall_checks);
        $finish;
    end
endmodule
