`timescale 1ns/1ps
/* verilator lint_off DECLFILENAME */
// Each top has an independent driver/checker so neither timing nor ready of
// one implementation is assumed to match the other implementation.
module pe_equivalence_case #(parameter bit PE8=0) (output logic finished=0);
    logic clk=0;
    always #4 clk=~clk;
    logic rst=1, cmd_valid=0, cmd_ready, in_valid=0, in_ready;
    logic [7:0] cmd_k=0, activation_u8=0;
    logic [11:0] cmd_lane_mask=0;
    logic [95:0] weights_flat=0;
    logic cfg_valid=0, cfg_ready;
    logic [3:0] cfg_lane=0;
    logic signed [31:0] cfg_weight_sum=0;
    logic out_valid, out_ready=1, out_last, out_overflow, busy, done;
    logic signed [31:0] result;
    logic [3:0] lane_id;
    generate
        if (PE8) begin : g8
            pe8_equivalent_top dut (.*);
        end else begin : g9
            pe9_equivalent_top dut (
                .clk(clk), .rst(rst), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
                .cmd_k(cmd_k), .cmd_lane_mask(cmd_lane_mask), .in_valid(in_valid),
                .in_ready(in_ready), .activation_u8(activation_u8), .weights_flat(weights_flat),
                .out_valid(out_valid), .out_ready(out_ready), .out_last(out_last),
                .out_overflow(out_overflow), .busy(busy), .done(done), .result(result), .lane_id(lane_id)
            );
            assign cfg_ready=0;
        end
    endgenerate
    integer golden[0:11], sums[0:11];
    integer got=0, total=0, cycles=0, job_start=0;
    logic [11:0] seen=0;
    logic stalled=0;
    logic [37:0] held;
    logic [37:0] payload;
    assign payload={result,lane_id,out_last,out_overflow};
    always @(posedge clk) begin
        cycles=cycles+1;
        if (rst) stalled=0;
        else begin
            if (stalled && (!out_valid || payload !== held)) $fatal(1,"Stall violation PE%0d",PE8?8:9);
            stalled=out_valid && !out_ready;
            held=payload;
            if (out_valid && out_ready) begin
                if (lane_id>=12 || !cmd_lane_mask[lane_id] || seen[lane_id]) $fatal(1,"Unexpected lane");
                if (result !== golden[lane_id] || out_overflow) $fatal(1,"PE%0d lane%0d got%0d expected%0d",PE8?8:9,lane_id,result,golden[lane_id]);
                if (out_last !== ((cmd_lane_mask >> (int'(lane_id)+1))==0)) $fatal(1,"last mismatch");
                seen[lane_id]=1;
                got=got+1;
                total=total+1;
            end
        end
    end
    function automatic integer aval(input integer i, mode);
        case(mode)
            0: return 127;
            1: return 128;
            2: return (i%2==0)?0:255;
            default: return (i*73+mode*29)%256;
        endcase
    endfunction
    function automatic integer wval(input integer i,j,mode);
        if(mode==2) return ((i+j)%2==0)?-128:127;
        return (i*37+j*19+mode*11)%256-128;
    endfunction
    task automatic configure;
        if(PE8) begin
            for(integer j=0;j<12;j=j+1) begin
                cfg_valid=1; cfg_lane=4'(j); cfg_weight_sum=sums[j];
                @(posedge clk);
                if(!cfg_ready) $fatal(1,"Configuration rejected");
                @(negedge clk);
            end
            cfg_valid=0;
        end
    endtask
    task automatic run_job(input integer k,mode,input logic[11:0] mask,input bit bubbles);
        got=0; seen=0;
        for(integer j=0;j<12;j=j+1) begin
            golden[j]=0; sums[j]=0;
            for(integer i=0;i<k;i=i+1) begin
                golden[j]=golden[j]+(aval(i,mode)-127)*wval(i,j,mode);
                sums[j]=sums[j]+wval(i,j,mode);
            end
        end
        configure();
        cmd_k=8'(k); cmd_lane_mask=mask; cmd_valid=1;
        @(posedge clk);
        while(!cmd_ready) @(posedge clk);
        #1; // Read cycle counter after its posedge monitor; avoid TB race.
        job_start=cycles;
        @(negedge clk); cmd_valid=0;
        for(integer i=0;i<k;i=i+1) begin
            activation_u8=8'(aval(i,mode));
            for(integer j=0;j<12;j=j+1) weights_flat[j*8+:8]=8'(wval(i,j,mode));
            in_valid=1;
            @(posedge clk);
            while(!in_ready) @(posedge clk);
            @(negedge clk); in_valid=0;
            if(bubbles && i%7==0) repeat(2) @(negedge clk);
        end
        // Backpressure varies during output; data and last must remain stable.
        while(!done) begin
            out_ready=!bubbles || cycles%4==0;
            @(negedge clk);
        end
        out_ready=1;
        if(seen !== mask || got!=$countones(mask)) $fatal(1,"Missing output");
        $display("PE%0d K=%0d mask=%h bubbles=%0d job_cycles=%0d outputs=%0d",PE8?8:9,k,mask,bubbles,cycles-job_start,got);
        @(negedge clk);
    endtask
    initial begin
        repeat(2) @(negedge clk); rst=0;
        // k=0 cannot be accepted and never enters an error state.
        cmd_valid=1;
        repeat(3) begin @(negedge clk); if(cmd_ready || busy || done) $fatal(1,"K0 accepted"); end
        cmd_valid=0;
        if(PE8) begin
            cmd_k=9; cmd_lane_mask=12'hfff; cmd_valid=1;
            repeat(2) begin @(negedge clk); if(cmd_ready) $fatal(1,"Missing parameters accepted"); end
            cmd_valid=0;
            cfg_lane=15; cfg_valid=1;
            @(negedge clk); if(cfg_ready) $fatal(1,"Bad config lane accepted");
            cfg_valid=0;
        end
        run_job(1,2,12'hfff,0);
        run_job(9,0,12'hfff,0);
        run_job(32,1,12'h0ff,0);
        run_job(144,2,12'hfff,1);
        run_job(9,3,12'ha55,1);
        run_job(32,4,12'h800,1);
        run_job(255,5,12'hfff,0);
        run_job(9,6,12'h000,0);
        // Abort a job in RUN with a product pending, then restart.
        for(integer j=0;j<12;j=j+1) sums[j]=0;
        configure();
        cmd_k=9; cmd_lane_mask=12'hfff; cmd_valid=1;
        @(posedge clk); while(!cmd_ready) @(posedge clk);
        @(negedge clk); cmd_valid=0;
        while(!in_ready) @(negedge clk);
        in_valid=1;
        @(negedge clk); rst=1; in_valid=0;
        repeat(2) @(negedge clk);
        if(busy || out_valid || done) $fatal(1,"Reset failed");
        rst=0;
        run_job(9,7,12'hfff,0);
        $display("PASS PE%0d equivalent top: %0d outputs",PE8?8:9,total);
        finished=1;
    end
endmodule
module tb_pe_equivalence;
    logic done8,done9;
    pe_equivalence_case #(.PE8(0)) pe9(.finished(done9));
    pe_equivalence_case #(.PE8(1)) pe8(.finished(done8));
    initial begin wait(done8 && done9); $display("PASS both equivalent tops"); $finish; end
    initial begin #1000000; $fatal(1,"Watchdog"); end
endmodule
