`timescale 1ns/1ps
module tb_feature_map_writer;
    import kws_system_pkg::*;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst=1, cmd_valid=0, cmd_ready, in_valid=0, in_ready;
    activation_write_mode_t cmd_mode=WRITE_LINEAR;
    activation_addr_t cmd_base=0;
    logic [7:0] cmd_width=0, cmd_height=0;
    logic [5:0] cmd_channels=0;
    activation_count_t cmd_count=0;
    activation_t in_data=0;
    logic [5:0] in_channel=0;
    logic [7:0] in_y=0, in_x=0;
    logic wr_en, busy, done, error;
    activation_addr_t wr_addr;
    activation_t wr_data;
    logic rd_en=0, rd_valid;
    activation_addr_t rd_addr=0;
    activation_t rd_data;
    integer expected_addr [0:131071];
    activation_t expected_data [0:131071];
    activation_t golden [0:ACT_DEPTH-1];
    integer head=0, tail=0, commits=0, read_checks=0, successes=0, errors=0;
    logic [31:0] rng=32'h5052026;
    feature_map_writer dut (.*);
    activation_buffer ram (.clk(clk),.rst(rst),.wr_en(wr_en),.wr_addr(wr_addr),
        .wr_data(wr_data),.rd_en(rd_en),.rd_addr(rd_addr),.rd_valid(rd_valid),.rd_data(rd_data));

    // Independent expected-write queue: test stimulus supplies mathematical
    // addresses; DUT writes cannot define the expected RAM contents.
    always @(posedge clk) begin
        if (!rst && wr_en) begin
            if (head == tail) $fatal(1,"Unexpected write");
            if (int'(wr_addr) != expected_addr[head] || wr_data !== expected_data[head])
                $fatal(1,"Write mismatch queue=%0d addr=%0d expected=%0d",head,wr_addr,expected_addr[head]);
            golden[expected_addr[head]] = expected_data[head];
            head++; commits++;
        end
        #1;
        if (done) begin
            if (head != tail || busy || error) $fatal(1,"Early/invalid done");
            successes++;
        end
        if (error) begin
            if (head != tail || busy || done) $fatal(1,"Error before drain");
            errors++;
        end
    end
    task automatic launch(input activation_write_mode_t m, input integer base,
                          input integer w,h,c,n);
        if(base<0 || base>=32768 || w<0 || w>255 || h<0 || h>255 || c<0 || c>63 || n<0 || n>65535)
            $fatal(1,"TB command exceeds port widths");
        @(negedge clk);
        if (!cmd_ready) $fatal(1,"Command not ready");
        cmd_mode=m; cmd_base=activation_addr_t'(base);
        cmd_width=8'(w); cmd_height=8'(h); cmd_channels=6'(c); cmd_count=16'(n);
        cmd_valid=1;
        @(negedge clk); cmd_valid=0;
        // Change external configuration after acceptance to test saved config.
        cmd_base=0; cmd_width=0; cmd_height=0; cmd_channels=0; cmd_count=0;
    endtask
    task automatic wait_ready;
        while (!in_ready && !error) @(negedge clk);
        if (error) $fatal(1,"Valid command rejected");
    endtask
    task automatic send(input integer addr,c,y,x, input activation_t d, input bit legal);
        if(c<0 || c>63 || y<0 || y>255 || x<0 || x>255)
            $fatal(1,"TB coordinate exceeds port widths");
        @(negedge clk);
        if (!in_ready) $fatal(1,"Data sent while not ready");
        in_valid=1; in_data=d; in_channel=6'(c); in_y=8'(y); in_x=8'(x);
        if (legal) begin
            expected_addr[tail]=addr; expected_data[tail]=d; tail++;
        end
    endtask
    task automatic finish_transaction(input bit expect_error);
        @(negedge clk); in_valid=0;
        while (!done && !error) @(negedge clk);
        if (error != expect_error || done == expect_error) $fatal(1,"Wrong terminal status");
        @(negedge clk);
        if (done || error) $fatal(1,"Terminal status must pulse");
    endtask
    task automatic scan;
        for (integer a=0; a<ACT_DEPTH; a++) begin
            @(negedge clk); rd_en=1; rd_addr=activation_addr_t'(a);
            @(posedge clk); #2;
            if (!rd_valid || rd_data !== golden[a]) $fatal(1,"RAM readback mismatch at %0d",a);
            read_checks++;
        end
        @(negedge clk); rd_en=0;
    endtask
    initial begin
        repeat(2) @(negedge clk); rst=0;
        $display("[1] Full-depth LINEAR fill, count=32768, continuous input");
        launch(WRITE_LINEAR,0,0,0,0,32768); wait_ready();
        for(integer a=0;a<ACT_DEPTH;a++) send(a,0,0,0,8'(a ^ (a>>8)),1);
        finish_transaction(0); scan();
        $display("[2] CHW interleaved channels, nonzero base, deterministic bubbles");
        launch(WRITE_CHW,100,5,3,12,0); wait_ready();
        for(integer y=0;y<3;y++) for(integer x=0;x<5;x++) for(integer c=0;c<12;c++) begin
            rng=rng^(rng<<13); rng=rng^(rng>>17); rng=rng^(rng<<5);
            if(rng[0]) begin @(negedge clk); in_valid=0; end
            send(100+c*15+y*5+x,c,y,x,8'(c*17+y*5+x),1);
        end
        finish_transaction(0); scan();
        $display("[3] Last address, single-byte write");
        launch(WRITE_LINEAR,32767,0,0,0,1); wait_ready();
        send(32767,63,255,255,8'hff,1); finish_transaction(0);
        $display("[4] Invalid counts/shapes/ranges, no writes");
        launch(WRITE_LINEAR,0,0,0,0,0); finish_transaction(1);
        launch(WRITE_LINEAR,32767,0,0,0,2); finish_transaction(1);
        launch(WRITE_LINEAR,0,0,0,0,65535); finish_transaction(1);
        launch(WRITE_CHW,0,0,3,12,1); finish_transaction(1);
        launch(WRITE_CHW,0,5,0,12,1); finish_transaction(1);
        launch(WRITE_CHW,0,5,3,0,1); finish_transaction(1);
        launch(WRITE_CHW,0,255,255,63,1); finish_transaction(1);
        $display("[5] Invalid c/y/x after one accepted write; no rollback");
        for(integer t=0;t<3;t++) begin
            launch(WRITE_CHW,400,3,2,2,0); wait_ready();
            send(400,0,0,0,8'(20+t),1);
            send(0,t==0?2:0,t==1?2:0,t==2?3:0,8'h99,0);
            finish_transaction(1);
        end
        $display("[6] Reset cancels pending write, no false completion; recovery");
        launch(WRITE_LINEAR,500,0,0,0,3); wait_ready();
        send(500,0,0,0,8'h11,1);
        @(negedge clk); in_valid=0; rst=1;
        // Accepted but not committed payload is intentionally discarded.
        tail=head;
        @(negedge clk);
        if(wr_en || done || error || busy) $fatal(1,"Reset failed");
        rst=0;
        launch(WRITE_LINEAR,510,0,0,0,2); wait_ready();
        send(510,0,0,0,8'h7f,1); send(511,0,0,0,8'h80,1);
        finish_transaction(0); scan();
        $display("[7] Actual Conv1 shape 12x30x61 at base 10080; busy command ignored");
        launch(WRITE_CHW,10080,61,30,12,0); wait_ready();
        cmd_valid=1; // cmd_ready remains low while processing this command.
        for(integer y=0;y<30;y++) for(integer x=0;x<61;x++) for(integer c=0;c<12;c++)
            send(10080+c*1830+y*61+x,c,y,x,8'(c+y+x),1);
        cmd_valid=0;
        finish_transaction(0); scan();
        $display("[8] CHW 32 channels, reverse channel arrival order");
        launch(WRITE_CHW,32040,1,1,32,0); wait_ready();
        for(integer c=31;c>=0;c--) send(32040+c,c,0,0,8'(c),1);
        finish_transaction(0); scan();
        if(successes!=6 || errors!=10 || head!=tail) $fatal(1,"Coverage mismatch");
        $display("PASS feature_map_writer commits=%0d read_checks=%0d success=%0d error=%0d",commits,read_checks,successes,errors);
        $finish;
    end
    initial begin #3000000; $fatal(1,"Watchdog timeout"); end
endmodule
