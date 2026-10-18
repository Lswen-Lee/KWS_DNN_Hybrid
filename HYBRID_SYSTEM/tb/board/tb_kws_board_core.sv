`timescale 1ns/1ps
// Real autonomous ROM/source + real inference, no TB request servicing.
module tb_kws_board_core;
    parameter bit RESULT_PIPELINED=0,POSTPROCESS_PIPELINED=1;
    logic clk=0,clk_cim=0,reset_request=1;
    always #4 clk=~clk;
    initial begin #2.7;forever #9.434 clk_cim=~clk_cim;end
    logic [1:0] sr=3,cr=3;
    always @(posedge clk or posedge reset_request) if(reset_request) sr<=3;else sr<={sr[0],1'b0};
    always @(posedge clk_cim or posedge reset_request) if(reset_request) cr<=3;else cr<={cr[0],1'b0};
    wire rst=sr[1],rst_cim=cr[1];
    wire busy,pass,fail;
    wire [2:0] result_index;
    wire [7:0] result_score;
    wire [3:0] failure_code;
    wire [31:0] run_cycles;
    kws_board_core #(.DEMO_FILE("build/kws_board_vectors/kws_demo.mem"),
        .RESULT_PIPELINED(RESULT_PIPELINED),.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) dut (.*);
    logic [7:0] quant_input[0:8063],pool1[0:2015],relu1[0:21959],pool2[0:5399];
    logic [7:0] relu2[0:4367],pool3[0:1007],relu3[0:575],pool4[0:143],relu4[0:31],fc2[0:7];
    integer counts[0:8]='{2016,21960,5400,4368,1008,576,144,32,8};
    integer bases[0:8]='{8064,10080,0,5400,0,1008,0,144,0};
    integer phase=-1,writes=0,ops=0,cycles=0,inputs=0,weights=0,requests=0,class_reads=0;
    string vectors;
    function automatic logic [7:0] golden(input integer op,n);
        case(op)
            0:return pool1[n];1:return relu1[n];2:return pool2[n];3:return relu2[n];
            4:return pool3[n];5:return relu3[n];6:return pool4[n];7:return relu4[n];8:return fc2[n];
            default:return 0;
        endcase
    endfunction
    always @(posedge clk) begin : monitor
        integer idx,addr;
        logic [7:0] value;
        cycles++;
        if(cycles>20000000) $fatal(1,"board FULL watchdog");
        if(!rst) begin
            if(fail) $fatal(1,"board FAIL code=%0d op=%0d",failure_code,dut.engine.current_op);
            if(dut.input_valid && dut.input_ready) inputs++;
            if(dut.weight_valid && dut.weight_ready) weights++;
            if(dut.weight_request_valid && dut.weight_request_ready) requests++;
            if(dut.engine.load_valid && dut.engine.load_ready) begin phase=-2;writes=0;end
            if((dut.engine.pe_cmd_valid && dut.engine.pe_cmd_ready) ||
               (dut.engine.dcim_cmd_valid && dut.engine.dcim_cmd_ready) ||
               (dut.engine.pool_valid && dut.engine.pool_ready)) begin
                if(int'(dut.engine.current_op)!=ops) $fatal(1,"board operation order");
                phase=ops;writes=0;
            end
            if(dut.engine.path.w_en) begin
                if(phase==-2) begin
                    if(writes>=8064) $fatal(1,"board excess input commit");
                    addr=writes;value=quant_input[writes];
                end else begin
                    if(phase<0 || phase>8) $fatal(1,"board unscheduled commit");
                    if(writes>=counts[phase]) $fatal(1,"board excess layer commit");
                    idx=(phase==1 || phase==3 || phase==5) ? (writes%12)*(counts[phase]/12)+writes/12 : writes;
                    addr=bases[phase]+idx;value=golden(phase,idx);
                end
                if(int'(dut.engine.path.w_addr)!=addr || dut.engine.path.w_data!==value)
                    $fatal(1,"board commit mismatch op=%0d n=%0d",phase,writes);
                writes++;
            end
            if(dut.engine.load_done && writes!=8064) $fatal(1,"board early input done");
            if(dut.engine.op_done) begin
                if(phase!=ops || writes!=counts[phase]) $fatal(1,"board early op_done");
                $display("PASS S6 op=%0d commits=%0d",phase,writes);ops++;phase=-1;
            end
            if(dut.engine.classify_active && dut.engine.path.r_en) begin
                if(ops!=9 || int'(dut.engine.path.r_addr)!=class_reads || class_reads>=8)
                    $fatal(1,"board classification read mismatch");
                class_reads++;
            end
        end
    end
    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"Missing VECTORS");
        $readmemh({vectors,"/quant_input.mem"},quant_input);$readmemh({vectors,"/pool1.mem"},pool1);
        $readmemh({vectors,"/relu1.mem"},relu1);$readmemh({vectors,"/pool2.mem"},pool2);
        $readmemh({vectors,"/relu2.mem"},relu2);$readmemh({vectors,"/pool3.mem"},pool3);
        $readmemh({vectors,"/relu3.mem"},relu3);$readmemh({vectors,"/pool4.mem"},pool4);
        $readmemh({vectors,"/relu4.mem"},relu4);$readmemh({vectors,"/fc2.mem"},fc2);
        if($test$plusargs("CORRUPT_GOLDEN")) relu2[0]^=1;
        repeat(5) @(negedge clk);reset_request=0;
        wait(pass);@(negedge clk);
        if(result_index!=6 || result_score!==fc2[6] || ops!=9 || inputs!=8064 || weights!=7564 || requests!=5 || class_reads!=8)
            $fatal(1,"board coverage/result mismatch");
        repeat(100) begin
            @(negedge clk);
            if(!pass || fail || busy || dut.start_valid || dut.engine.path.w_en || dut.engine.path.r_en)
                $fatal(1,"board status not sticky or extra transaction");
        end
        $display("PASS S6 FULL PIPE=%0d POST=%0d inputs=%0d weights=%0d requests=%0d ops=%0d class_reads=%0d result=%0d/%0d cycles=%0d",
            RESULT_PIPELINED,POSTPROCESS_PIPELINED,inputs,weights,requests,ops,class_reads,result_index,result_score,run_cycles);
        $finish;
    end
endmodule
