`timescale 1ns/1ps
module tb_activation_reader;
    import kws_system_pkg::*;
    logic clk=0;
    always #5 clk=~clk;
    logic rst=1, cmd_valid=0, cmd_ready;
    activation_read_mode_t cmd_mode=READ_LINEAR;
    activation_addr_t cmd_base=0;
    activation_count_t cmd_count=0;
    logic [7:0] cmd_width=0, cmd_height=0, cmd_x=0, cmd_y=0;
    logic [5:0] cmd_channels=0;
    logic ram_rd_en, ram_rd_valid;
    activation_addr_t ram_rd_addr;
    activation_t ram_rd_data;
    logic out_valid, out_ready=0, out_last, busy, done, error;
    activation_t out_data;
    logic wr_en=0;
    activation_addr_t wr_addr=0;
    activation_t wr_data=0;
    integer expected_address [0:32767];
    integer length, issued, received;
    integer total_requests=0, total_outputs=0, successes=0, rejected=0, stall_checks=0;
    integer tick=0, previous_output_tick;
    bit stalled=0, no_bubbles=0;
    logic [8:0] held_payload;
    logic [31:0] rng=32'h5052026;

    activation_reader dut (.*);
    activation_buffer ram (.clk(clk),.rst(rst),.wr_en(wr_en),.wr_addr(wr_addr),
        .wr_data(wr_data),.rd_en(ram_rd_en),.rd_addr(ram_rd_addr),
        .rd_valid(ram_rd_valid),.rd_data(ram_rd_data));

    function automatic activation_t pattern(input integer address);
        return 8'((address * 37) ^ (address >> 8) ^ (address >> 3));
    endfunction

    // Public-port scoreboard: expected addresses come from the math formula,
    // not from the DUT's incremental address generator.
    always @(posedge clk) begin
        tick++;
        if (rst) stalled=0;
        else begin
            if (stalled) begin
                if (!out_valid || {out_last,out_data} !== held_payload)
                    $fatal(1,"Payload changed while stalled");
                stall_checks++;
            end
            stalled=out_valid && !out_ready;
            held_payload={out_last,out_data};
            if (ram_rd_en) begin
                if (issued>=length || int'(ram_rd_addr)!=expected_address[issued])
                    $fatal(1,"Read address mismatch at index %0d",issued);
                issued++; total_requests++;
            end
            if (out_valid && out_ready) begin
                if(received>=length || out_data !== pattern(expected_address[received]) ||
                   out_last !== (received==length-1)) $fatal(1,"Output mismatch index=%0d",received);
                if(no_bubbles && received>0 && tick!=previous_output_tick+1)
                    $fatal(1,"Unexpected throughput bubble");
                previous_output_tick=tick;
                received++; total_outputs++;
            end
        end
        #1;
        if(done && (received!=length || issued!=length || busy || out_valid || error))
            $fatal(1,"Early/invalid completion");
        if(error && (issued!=0 || received!=0 || busy || done))
            $fatal(1,"Invalid command generated traffic");
    end

    task automatic launch(input activation_read_mode_t mode, input integer base,n,w,h,c,x,y,
                          input bit legal);
        if(base<0 || base>32767 || n<0 || n>65535 || w<0 || w>255 || h<0 || h>255 ||
           c<0 || c>63 || x<0 || x>255 || y<0 || y>255) $fatal(1,"Bad TB port value");
        @(negedge clk);
        if(!cmd_ready) $fatal(1,"Reader not idle");
        issued=0; received=0; length=0; no_bubbles=0;
        if(legal) begin
            if(mode==READ_LINEAR) begin
                length=n;
                for(integer i=0;i<n;i++) expected_address[i]=base+i;
            end else begin
                length=9*c;
                for(integer ch=0;ch<c;ch++) for(integer u=0;u<3;u++) for(integer v=0;v<3;v++)
                    expected_address[ch*9+u*3+v]=base+ch*h*w+(y+u)*w+x+v;
            end
        end
        cmd_mode=mode; cmd_base=15'(base); cmd_count=16'(n);
        cmd_width=8'(w); cmd_height=8'(h); cmd_channels=6'(c); cmd_x=8'(x); cmd_y=8'(y);
        cmd_valid=1; out_ready=0;
        @(negedge clk); cmd_valid=0;
        cmd_base=0; cmd_count=0; cmd_width=0; cmd_height=0; cmd_channels=0; cmd_x=0; cmd_y=0;
    endtask

    // policy: 0=continuous; 1=random stalls; 2=block start and final payload.
    task automatic complete(input integer policy, input bit legal);
        integer elapsed, last_wait;
        elapsed=0; last_wait=0; no_bubbles=(policy==0 && legal);
        while(!done && !error) begin
            if(elapsed>200000) $fatal(1,"Command timeout");
            case(policy)
                0: out_ready=1;
                1: begin
                    rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
                    out_ready=rng[0];
                end
                default: begin
                    out_ready=elapsed>=25;
                    if(received==length-1 && last_wait<20) begin
                        out_ready=0;
                        if(out_valid) last_wait++;
                    end
                end
            endcase
            @(negedge clk); elapsed++;
        end
        if(error==legal || done!=legal) $fatal(1,"Wrong terminal result");
        if(legal) successes++; else rejected++;
        if(policy==2 && last_wait!=20) $fatal(1,"Final-stall coverage missing");
        out_ready=0; no_bubbles=0;
        @(negedge clk);
        if(done || error) $fatal(1,"Status not a pulse");
    endtask

    initial begin
        length=0; issued=0; received=0; previous_output_tick=0;
        repeat(2) @(negedge clk); rst=0;
        $display("[1] Initialize real RAM through write port");
        for(integer a=0;a<ACT_DEPTH;a++) begin
            @(negedge clk); wr_en=1; wr_addr=15'(a); wr_data=pattern(a);
        end
        @(negedge clk); wr_en=0;
        $display("[2] LINEAR: full capacity, boundary, FC vector replay, stalls");
        launch(READ_LINEAR,0,32768,0,0,0,0,0,1); complete(0,1);
        launch(READ_LINEAR,32767,1,0,0,0,0,0,1); complete(2,1);
        repeat(3) begin launch(READ_LINEAR,100,144,0,0,0,0,0,1); complete(1,1); end
        $display("[3] PATCH math examples and actual Conv1/2/3 corner patches");
        launch(READ_PATCH,100,0,6,5,2,2,1,1); complete(0,1);
        launch(READ_PATCH,8064,0,63,32,1,0,0,1); complete(1,1);
        launch(READ_PATCH,8064,0,63,32,1,60,29,1); complete(2,1);
        launch(READ_PATCH,0,0,30,15,12,0,0,1); complete(0,1);
        launch(READ_PATCH,0,0,30,15,12,27,12,1); complete(1,1);
        launch(READ_PATCH,0,0,14,6,12,11,3,1); complete(2,1);
        launch(READ_PATCH,0,0,3,3,32,0,0,1); complete(1,1);
        $display("[4] Reject invalid counts, dimensions, full-map range and patch bounds");
        launch(READ_LINEAR,0,0,0,0,0,0,0,0); complete(0,0);
        launch(READ_LINEAR,32767,2,0,0,0,0,0,0); complete(0,0);
        launch(READ_LINEAR,0,65535,0,0,0,0,0,0); complete(0,0);
        launch(READ_PATCH,0,0,2,5,1,0,0,0); complete(0,0);
        launch(READ_PATCH,0,0,5,2,1,0,0,0); complete(0,0);
        launch(READ_PATCH,0,0,5,5,0,0,0,0); complete(0,0);
        launch(READ_PATCH,0,0,255,255,63,0,0,0); complete(0,0);
        launch(READ_PATCH,0,0,5,5,1,3,0,0); complete(0,0);
        launch(READ_PATCH,0,0,5,5,1,0,3,0); complete(0,0);
        launch(READ_PATCH,0,0,5,5,1,255,255,0); complete(0,0);
        $display("[5] Reset with in-flight request, buffered responses, and during CONFIG");
        for(integer phase=0;phase<3;phase++) begin
            launch(READ_LINEAR,200,144,0,0,0,0,0,1);
            if(phase<2) begin
                while(issued==0) @(negedge clk);
                if(phase==1) repeat(5) @(negedge clk);
            end
            rst=1;
            @(negedge clk);
            if(busy || out_valid || ram_rd_en || done || error) $fatal(1,"Reset failed");
            rst=0;
            launch(READ_LINEAR,200,144,0,0,0,0,0,1); complete(0,1);
        end
        if(successes!=15 || rejected!=10 || stall_checks==0 || total_requests-total_outputs!=3)
            $fatal(1,"Coverage/reset cancellation mismatch");
        $display("PASS activation_reader commands=%0d rejected=%0d requests=%0d outputs=%0d stalled_checks=%0d",successes,rejected,total_requests,total_outputs,stall_checks);
        $finish;
    end
    initial begin #5000000; $fatal(1,"Watchdog timeout"); end
endmodule
