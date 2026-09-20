`timescale 1ns/1ps
module tb_pe_layer_weight_loader;
    parameter bit SUM_ENABLE=1;
    parameter bit STORE_SUM=0;
    logic clk=0, rst=1;
    always #4 clk=~clk;
    logic cmd_valid=0, cmd_ready;
    logic [7:0] cmd_k=0;
    logic [5:0] cmd_channels=0;
    logic weight_valid=0, weight_ready;
    logic signed [7:0] weight_i8=0;
    logic wr_valid, wr_ready, ram_ready, allow_write=1;
    logic [3:0] wr_lane;
    logic [8:0] wr_addr;
    logic [7:0] wr_data;
    wire sum_valid;
    wire sum_ready;
    logic allow_sum=0;
    wire sum_mem_ready;
    logic sum_rd_valid=0, sum_rd_ready, sum_out_valid, sum_out_ready=0;
    logic [4:0] sum_rd_id=0, sum_out_id;
    logic signed [31:0] sum_out_data;
    logic sum_out_error;
    integer sum_read_checks=0;
    wire signed [31:0] weight_sum;
    wire [4:0] sum_channel_id;
    logic busy, layer_ready, done, error;
    logic rd_valid=0, rd_ready, out_valid, out_ready=0;
    logic [8:0] rd_addr=0;
    wire [95:0] weights_flat;
    integer ticks=0, writes=0, sums=0, checks=0;
    integer accepted_index=0, ref_k=1, expected_sum=0, expected_channel=0;
    pe_layer_weight_loader #(.SUM_ENABLE(SUM_ENABLE)) dut (.*);
    assign sum_ready=allow_sum && (!STORE_SUM || sum_mem_ready);
    pe_channel_sum_memory sum_memory (
        .clk(clk), .rst(rst), .layer_clear(cmd_valid && cmd_ready),
        .wr_valid(STORE_SUM && sum_valid && allow_sum), .wr_ready(sum_mem_ready),
        .wr_channel_id(sum_channel_id), .wr_weight_sum(weight_sum),
        .rd_valid(sum_rd_valid), .rd_ready(sum_rd_ready), .rd_channel_id(sum_rd_id),
        .out_valid(sum_out_valid), .out_ready(sum_out_ready),
        .out_channel_id(sum_out_id), .out_weight_sum(sum_out_data), .out_error(sum_out_error)
    );
    assign wr_ready=ram_ready && allow_write;
    pe_weight_buffer_12 #(.ADDR_WIDTH(9)) ram (
        .clk(clk), .rst(rst), .wr_valid(wr_valid && allow_write),
        .wr_ready(ram_ready), .wr_lane(wr_lane), .wr_addr(wr_addr),
        .wr_data(wr_data), .rd_valid(rd_valid), .rd_ready(rd_ready),
        .rd_addr(rd_addr), .out_valid(out_valid), .out_ready(out_ready),
        .weights_flat(weights_flat)
    );
    function automatic logic [7:0] value(input integer c,k);
        value=8'(c*73+k*29+128);
    endfunction
    always @(negedge clk) begin
        ticks=ticks+1;
        allow_write=(ticks%5 != 0);
        allow_sum=(ticks%7 < 3);
    end
    always @(posedge clk) if (!rst) begin
        if ((wr_valid && wr_ready) != (weight_valid && weight_ready))
            $fatal(1,"RAM/stream handshake mismatch");
        if (weight_valid && weight_ready) begin
            if (wr_lane != 4'((accepted_index/ref_k)%12) ||
                wr_addr != 9'(((accepted_index/ref_k)/12)*ref_k+accepted_index%ref_k))
                $fatal(1,"Mapping error at weight %0d",accepted_index);
            expected_sum=expected_sum+integer'($signed(weight_i8));
            accepted_index=accepted_index+1;
            writes=writes+1;
        end
        if (sum_valid && sum_ready) begin
            if (weight_sum != expected_sum || sum_channel_id != 5'(expected_channel))
                $fatal(1,"Sum error channel %0d",expected_channel);
            expected_sum=0; expected_channel=expected_channel+1; sums=sums+1;
        end
    end
    task automatic command(input integer k,c);
        if(k<0 || k>255 || c<0 || c>63) $fatal(1,"TB command out of range");
        @(negedge clk);
        cmd_k=8'(k); cmd_channels=6'(c); cmd_valid=1;
        do @(posedge clk); while (!cmd_ready);
        @(negedge clk); cmd_valid=0;
    endtask
    task automatic send_weight(input logic [7:0] data);
        @(negedge clk); weight_i8=data; weight_valid=1;
        do @(posedge clk); while (!weight_ready);
        @(negedge clk); weight_valid=0;
    endtask
    task automatic run_layer(input integer k,c);
        integer ch,ki,g,l,reference_sum;
        ref_k=k; accepted_index=0; expected_sum=0; expected_channel=0;
        command(k,c);
        for(ch=0;ch<c;ch=ch+1)
            for(ki=0;ki<k;ki=ki+1) send_weight(value(ch,ki));
        wait(done); @(negedge clk);
        if (!layer_ready || busy || accepted_index != k*c) $fatal(1,"Completion error");
        if(SUM_ENABLE && expected_channel != c) $fatal(1,"Missing sums");
        if(STORE_SUM) begin
            // Read every channel, including those not present in this layer.
            // FC1 -> FC2 specifically checks that channels 8..31 were invalidated.
            for(ch=0;ch<32;ch=ch+1) begin
                reference_sum=0;
                if(ch<c) for(ki=0;ki<k;ki=ki+1)
                    reference_sum=reference_sum+integer'($signed(value(ch,ki)));
                @(negedge clk); sum_rd_valid=1; sum_rd_id=5'(ch);
                do @(posedge clk); while(!sum_rd_ready);
                @(negedge clk); sum_rd_valid=0;
                repeat(3) begin
                    if(!sum_out_valid || sum_out_id != 5'(ch) ||
                       sum_out_error != (ch>=c) || sum_out_data != reference_sum)
                        $fatal(1,"Stored sum mismatch channel=%0d",ch);
                    sum_read_checks=sum_read_checks+1;
                    @(negedge clk);
                end
                sum_out_ready=1;
                @(negedge clk); sum_out_ready=0;
            end
        end
        for(g=0;g<(c+11)/12;g=g+1) begin
            for(ki=0;ki<k;ki=ki+1) begin
                @(negedge clk); rd_addr=9'(g*k+ki); rd_valid=1;
                do @(posedge clk); while(!rd_ready);
                @(negedge clk); rd_valid=0;
                if(!out_valid) $fatal(1,"Missing RAM response");
                repeat(2) begin
                    for(l=0;l<12;l=l+1) if(g*12+l<c) begin
                        if(weights_flat[l*8+:8] !== value(g*12+l,ki))
                            $fatal(1,"Read error group=%0d k=%0d lane=%0d",g,ki,l);
                        checks=checks+1;
                    end
                    @(negedge clk);
                end
                out_ready=1;
                @(negedge clk); out_ready=0;
            end
        end
        $display("PASS layer K=%0d C=%0d",k,c);
    endtask
    task automatic bad_command(input integer k,c);
        command(k,c);
        if(!error || busy || layer_ready || wr_valid) $fatal(1,"Invalid command accepted");
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=0;
        bad_command(0,12); bad_command(9,0); bad_command(9,33); bad_command(171,32);
        run_layer(9,12); run_layer(144,32); run_layer(32,8);
        run_layer(170,32); run_layer(255,24); run_layer(1,1);
        ref_k=9; accepted_index=0; expected_channel=0; expected_sum=0;
        command(9,12); send_weight(8'h80);
        @(negedge clk); rst=1;
        @(negedge clk); rst=0;
        if(busy || layer_ready || sum_valid) $fatal(1,"Reset abort failed");
        run_layer(9,12);
        $display("PASS loader SUM_ENABLE=%0d writes=%0d sums=%0d read_checks=%0d",SUM_ENABLE,writes,sums,checks);
        $display("Stored sum checks=%0d",sum_read_checks);
        $finish;
    end
    initial begin #5000000; $fatal(1,"Timeout"); end
endmodule
