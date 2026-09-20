`timescale 1ns/1ps
module tb_pe_weight_buffer_12;
    logic clk=0;
    always #4 clk=~clk;
    logic rst=1,wr_valid=0,wr_ready,rd_valid=0,rd_ready,out_valid,out_ready=1;
    logic [3:0] wr_lane=0;
    logic [7:0] wr_addr=0,wr_data=0,rd_addr=0;
    wire [95:0] weights_flat;
    pe_weight_buffer_12 dut(.*);
    logic [7:0] model [0:11][0:255];
    bit initialized [0:11][0:255];
    logic [95:0] expected;
    bit pending=0;
    integer writes=0,reads=0,responses=0,checks=0,aborted=0;
    integer stalled_checks=0,arbitrations=0,invalids=0;
    // Scoreboard models accepted transactions; no access to internal RAM.
    always @(posedge clk) begin
        if(rst) begin
            if(pending) aborted=aborted+1;
            pending=0;
            #1;
            if(out_valid || wr_ready || rd_ready) $fatal(1,"Reset protocol failure");
        end else begin
            if(wr_ready !== (wr_lane<12)) $fatal(1,"Write ready mismatch");
            if(rd_ready !== (!(wr_valid && wr_lane<12) && (!pending || out_ready)))
                $fatal(1,"Read arbitration/ready mismatch");
            if(out_valid !== pending) $fatal(1,"Valid mismatch");
            if(pending) begin
                if(weights_flat !== expected) $fatal(1,"Read response mismatch");
                checks=checks+12;
                if(!out_ready) stalled_checks=stalled_checks+1;
            end
            if(out_valid && out_ready) begin pending=0; responses=responses+1; end
            if(wr_valid && wr_lane>=12) invalids=invalids+1;
            if(wr_valid && wr_ready) begin
                model[wr_lane][wr_addr]=wr_data;
                initialized[wr_lane][wr_addr]=1;
                writes=writes+1;
                if(rd_valid) arbitrations=arbitrations+1;
            end
            if(rd_valid && rd_ready) begin
                for(integer j=0;j<12;j=j+1) begin
                    if(!initialized[j][rd_addr]) $fatal(1,"TB read of unwritten memory");
                    expected[j*8+:8]=model[j][rd_addr];
                end
                reads=reads+1; pending=1;
            end
            #1;
            if(out_valid !== pending) $fatal(1,"Response not visible after read edge");
            if(pending && weights_flat !== expected) $fatal(1,"Synchronous read latency/data wrong");
        end
    end
    function automatic logic [7:0] pattern(input integer j,k);
        case(k%8)
            0:return 8'h00;
            1:return 8'h7f;
            2:return 8'h80;
            3:return 8'hff;
            default:return 8'(j*37+k*73);
        endcase
    endfunction
    task automatic write_byte(input integer lane,address,input logic[7:0] data);
        if(lane<0 || lane>11 || address<0 || address>255) $fatal(1,"Bad test address");
        wr_lane=4'(lane); wr_addr=8'(address); wr_data=data; wr_valid=1;
        @(posedge clk); while(!wr_ready) @(posedge clk);
        @(negedge clk); wr_valid=0;
    endtask
    task automatic read_word(input integer address);
        if(address<0 || address>255) $fatal(1,"Bad read address");
        rd_addr=8'(address); rd_valid=1;
        @(posedge clk); while(!rd_ready) @(posedge clk);
        @(negedge clk); rd_valid=0;
    endtask
    initial begin #200000; $fatal(1,"Watchdog"); end
    initial begin
        repeat(2) @(negedge clk); rst=0;
        $display("TEST write all 12 x 256 bytes, then continuous parallel reads");
        for(integer j=0;j<12;j=j+1)
            for(integer k=0;k<256;k=k+1) write_byte(j,k,pattern(j,k));
        for(integer k=0;k<256;k=k+1) read_word(k);
        repeat(2) @(negedge clk);
        $display("TEST stalled response survives writes to same address");
        out_ready=0; read_word(17);
        rd_addr=18; rd_valid=1;
        for(integer j=0;j<12;j=j+1) write_byte(j,17,8'(j+90));
        repeat(3) @(negedge clk);
        out_ready=1;
        @(negedge clk); rd_valid=0;
        read_word(17);
        repeat(2) @(negedge clk);
        $display("TEST write priority; rejected read is retried unchanged");
        wr_valid=1; wr_lane=5; wr_addr=255; wr_data=8'h81;
        rd_valid=1; rd_addr=255;
        @(negedge clk); wr_valid=0;
        @(negedge clk); rd_valid=0;
        repeat(2) @(negedge clk);
        $display("TEST invalid write lanes 12..15 do not starve reads");
        for(integer j=12;j<16;j=j+1) begin
            wr_valid=1; wr_lane=4'(j); wr_addr=0; wr_data=8'h99;
            read_word(0);
        end
        wr_valid=0;
        repeat(2) @(negedge clk);
        $display("TEST reset drops pending result but preserves memory");
        out_ready=0; read_word(255);
        rst=1; wr_valid=1; wr_lane=5; wr_addr=255; wr_data=0;
        rd_valid=1; rd_addr=17;
        repeat(2) @(negedge clk);
        rst=0; wr_valid=0; rd_valid=0; out_ready=1;
        // Read every stored byte again after reset, including overwritten data.
        for(integer k=255;k>=0;k=k-1) begin
            read_word(k);
            if(k%17==0) repeat(2) @(negedge clk);
        end
        repeat(3) @(negedge clk);
        if(pending || reads!=responses+aborted || aborted!=1 || writes!=3085 || invalids!=4 || arbitrations<1 || stalled_checks<15)
            $fatal(1,"Transaction coverage mismatch");
        $display("PASS weight buffer: writes=%0d reads=%0d responses=%0d aborted=%0d lane_checks=%0d stalls=%0d arbitration=%0d invalid=%0d",
                 writes,reads,responses,aborted,checks,stalled_checks,arbitrations,invalids);
        $finish;
    end
endmodule
