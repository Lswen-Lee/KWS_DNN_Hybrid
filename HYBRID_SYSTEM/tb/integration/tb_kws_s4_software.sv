`timescale 1ns/1ps
// Real sequencer + RAM + Reader/Writer + PE/PoT + Pool. No arithmetic stubs.
// Source agent only supplies requested software input/weights; it never issues
// individual PE/Pool commands and never writes intermediate golden to the DUT.
module tb_kws_s4_software;
    import kws_system_pkg::*;
    parameter bit RESULT_PIPELINED=0;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic start_valid=0,start_ready,busy,done,error,op_done;
    inference_mode_t run_mode=RUN_FRONTEND;
    layer_error_t error_code;
    logic [3:0] current_op;
    logic input_request_valid,input_request_ready=0,input_is_flatten;
    logic [15:0] input_count;
    logic input_valid=0,input_ready;
    logic [7:0] input_data=0;
    logic weight_request_valid,weight_request_ready=0,weight_valid=0,weight_ready;
    logic [2:0] weight_layer_id;
    logic [7:0] weight_k;
    logic [5:0] weight_channels;
    logic signed [7:0] weight_i8=0;
    logic source_error=0,read_valid=0,read_ready,read_out_valid,read_out_ready=0;
    logic [14:0] read_base=0;
    logic [15:0] read_count=32768;
    logic [7:0] read_data;
    logic read_last,read_done,read_error;
    kws_inference_top #(.RESULT_PIPELINED(RESULT_PIPELINED)) dut (.clk_cim(clk), .rst_cim(rst), .*);
    logic [7:0] quant_input[0:8063],pool1[0:2015],relu1[0:21959],pool2[0:5399];
    logic [7:0] flatten[0:143],relu4[0:31],fc2[0:7];
    logic [7:0] wconv[0:107],wfc1[0:4607],wfc2[0:255];
    logic [7:0] reference_mem[0:32767];
    bit initialized[0:32767];
    string vectors;
    logic [31:0] rng=505;
    integer seed_arg,cycles=0,phase=-1,writes=0,reads=0;
    integer expected_writes=0,expected_reads=0,next_op=0;
    integer operations=0,runs=0,read_beats=0,checked_bytes=0,weight_requests=0;
    integer expected_weight_id=0,requests_this_run=0,stalls=0,gaps=0;
    bit flatten_run=0,checking=0;
    function automatic bit random_ready;
        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
        return rng[0] || rng[3];
    endfunction
    function automatic integer expected_read_address(input integer n);
        case(phase)
            0: return n;
            1: return 8064+(n/9/61+(n%9)/3)*63+(n/9)%61+n%3;
            2: return 10080+n;
            7: return n%144;
            8: return 144+n;
            default: return -1;
        endcase
    endfunction
    always @(posedge clk) begin : scoreboard
        integer address,index;
        logic [7:0] expected;
        cycles++;
        if(cycles>3000000) $fatal(1,"S4 watchdog");
        if(!rst) begin
            if(dut.controller_busy && (read_ready || start_ready)) $fatal(1,"Run ownership leaked");
            if(dut.controller_busy && !dut.path_busy) gaps++;
            if(error && checking) $fatal(1,"Unexpected S4 error %0d",error_code);
            if(checking) begin
                if(dut.load_valid && dut.load_ready) begin
                    phase=-2;writes=0;reads=0;expected_writes=flatten_run ? 144 : 8064;
                end
                if((dut.pe_cmd_valid && dut.pe_cmd_ready) || (dut.pool_valid && dut.pool_ready)) begin
                    if(int'(current_op)!=next_op) $fatal(1,"Operation order expected=%0d got=%0d",next_op,current_op);
                    phase=int'(current_op);writes=0;reads=0;
                    case(phase)
                        0: begin expected_writes=2016;expected_reads=8064;end
                        1: begin expected_writes=21960;expected_reads=16470;end
                        2: begin expected_writes=5400;expected_reads=21960;end
                        7: begin expected_writes=32;expected_reads=432;end
                        8: begin expected_writes=8;expected_reads=32;end
                        default: $fatal(1,"Unsupported command executed");
                    endcase
                end
                if(dut.path.r_en) begin
                    if(phase<0 || reads>=expected_reads || int'(dut.path.r_addr)!=expected_read_address(reads))
                        $fatal(1,"Read address/order phase=%0d n=%0d",phase,reads);
                    reads++;
                end
                if(dut.path.w_en && !dut.path.fault) begin
                    address=0;expected=0;index=writes;
                    case(phase)
                        -2: begin address=writes;expected=flatten_run ? flatten[index] : quant_input[index];end
                        0: begin address=8064+writes;expected=pool1[index];end
                        1: begin
                            index=(writes%12)*1830+writes/12;
                            address=10080+index;expected=relu1[index];
                        end
                        2: begin address=writes;expected=pool2[index];end
                        7: begin address=144+writes;expected=relu4[index];end
                        8: begin address=writes;expected=fc2[index];end
                        default: $fatal(1,"Unscheduled write");
                    endcase
                    if(writes>=expected_writes || int'(dut.path.w_addr)!=address || dut.path.w_data!==expected)
                        $fatal(1,"S4 commit mismatch op=%0d n=%0d addr=%0d expected_addr=%0d value=%0d expected=%0d",
                               phase,writes,dut.path.w_addr,address,dut.path.w_data,expected);
                    // Reference uses independently computed address/golden, NOT DUT data.
                    reference_mem[address]=expected;initialized[address]=1;writes++;
                end
                if(dut.load_done && (phase!=-2 || writes!=expected_writes)) $fatal(1,"Input load completed early");
                if(op_done) begin
                    if(phase!=int'(current_op) || reads!=expected_reads || writes!=expected_writes)
                        $fatal(1,"Operation completed before all transfers");
                    $display("PASS S4 op=%0d reads=%0d commits=%0d",phase,reads,writes);
                    next_op++;operations++;phase=-1;
                end
            end
        end
    end
    task automatic reset_all;
        @(negedge clk);checking=0;rst=1;
        start_valid=0;input_request_ready=0;weight_request_ready=0;input_valid=0;weight_valid=0;
        source_error=0;read_valid=0;read_out_ready=0;
        repeat(3) @(negedge clk);rst=0;@(negedge clk);
        if(busy || !start_ready) $fatal(1,"Top reset failed");
    endtask
    task automatic supply_input;
        integer count;
        count=flatten_run ? 144 : 8064;
        if(input_count!=16'(count) || input_is_flatten!=flatten_run || requests_this_run!=0)
            $fatal(1,"Wrong input request");
        repeat(4) begin
            @(negedge clk);
            if(!input_request_valid || input_ready) $fatal(1,"Input request hold failed");
        end
        input_request_ready=1;@(negedge clk);input_request_ready=0;requests_this_run++;
        for(integer i=0;i<count;i++) begin
            while(!random_ready()) begin input_valid=0;@(negedge clk);end
            input_valid=1;input_data=flatten_run ? flatten[i] : quant_input[i];
            do @(posedge clk); while(!input_ready);
            @(negedge clk);
        end
        input_valid=0;
    endtask
    task automatic supply_weights;
        integer count,id;
        id=int'(weight_layer_id);
        if(id!=expected_weight_id) $fatal(1,"Wrong requested weight layer");
        case(id)
            0: begin count=108;if(weight_k!=9 || weight_channels!=12) $fatal(1,"Conv1 metadata");end
            3: begin count=4608;if(weight_k!=144 || weight_channels!=32) $fatal(1,"FC1 metadata");end
            4: begin count=256;if(weight_k!=32 || weight_channels!=8) $fatal(1,"FC2 metadata");end
            default: $fatal(1,"Unexpected weight request");
        endcase
        repeat(4) begin
            @(negedge clk);
            if(!weight_request_valid || int'(weight_layer_id)!=id || weight_ready)
                $fatal(1,"Weight request hold failed");
        end
        weight_request_ready=1;@(negedge clk);weight_request_ready=0;weight_requests++;
        for(integer i=0;i<count;i++) begin
            while(!random_ready()) begin weight_valid=0;@(negedge clk);end
            case(id)
                0: weight_i8=$signed(wconv[i]);
                3: weight_i8=$signed(wfc1[i]);
                4: weight_i8=$signed(wfc2[i]);
            endcase
            weight_valid=1;
            do @(posedge clk); while(!weight_ready);
            @(negedge clk);
        end
        weight_valid=0;expected_weight_id=id+1;
    endtask
    task automatic run_segment(input bit fc);
        flatten_run=fc;next_op=fc ? 7 : 0;expected_weight_id=fc ? 3 : 0;
        requests_this_run=0;phase=-1;checking=1;
        @(negedge clk);run_mode=fc ? RUN_FC_TAIL : RUN_FRONTEND;start_valid=1;read_valid=1;
        #1;if(!start_ready || read_ready) $fatal(1,"Start/read priority");
        @(negedge clk);start_valid=0;run_mode=RUN_FULL;
        // Keep read requested throughout run, including gaps between operations.
        // It must not be accepted until this task withdraws it on done.
        while(!done) begin
            if(input_request_valid) supply_input();
            else if(weight_request_valid) supply_weights();
            else @(negedge clk);
        end
        read_valid=0;checking=0;
        if(error || busy || next_op!=(fc ? 9 : 3) || requests_this_run!=1)
            $fatal(1,"Wrong segment completion");
        runs++;@(negedge clk);
        if(done) $fatal(1,"Done pulse too long");
    endtask
    task automatic scan_ram;
        integer index;
        logic held;
        logic [8:0] held_payload;
        @(negedge clk);read_valid=1;read_base=0;read_count=32768;
        #1;if(!read_ready) $fatal(1,"Idle read unavailable");
        @(negedge clk);read_valid=0;index=0;held=0;held_payload=0;
        while(!read_done) begin
            // A pending start may not interrupt an active public read.
            if(start_ready) $fatal(1,"Read ownership leaked to start");
            read_out_ready=random_ready();
            @(posedge clk);
            if(held && (!read_out_valid || {read_last,read_data}!==held_payload)) $fatal(1,"Read payload unstable");
            held=read_out_valid && !read_out_ready;held_payload={read_last,read_data};
            if(held) stalls++;
            if(read_out_valid && read_out_ready) begin
                if(index>=32768 || read_last!==(index==32767)) $fatal(1,"Read order/count");
                if(initialized[index]) begin
                    if(read_data!==reference_mem[index]) $fatal(1,"Readback mismatch address=%0d",index);
                    checked_bytes++;
                end
                index++;read_beats++;
            end
            @(negedge clk);
        end
        if(index!=32768 || read_error) $fatal(1,"Incomplete scan");
        read_out_ready=0;@(negedge clk);
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"Missing vectors");
        if($value$plusargs("SEED=%d",seed_arg)) rng=32'(seed_arg);
        if(rng==0) $fatal(1,"Nonzero seed required");
        for(integer i=0;i<32768;i++) initialized[i]=0;
        $readmemh({vectors,"/quant_input.mem"},quant_input);
        $readmemh({vectors,"/pool1.mem"},pool1);
        $readmemh({vectors,"/relu1.mem"},relu1);
        $readmemh({vectors,"/pool2.mem"},pool2);
        $readmemh({vectors,"/flatten.mem"},flatten);
        $readmemh({vectors,"/relu4.mem"},relu4);
        $readmemh({vectors,"/fc2.mem"},fc2);
        $readmemh({vectors,"/conv1_weights.mem"},wconv);
        $readmemh({vectors,"/fc1_weights.mem"},wfc1);
        $readmemh({vectors,"/fc2_weights.mem"},wfc2);
        if($test$plusargs("CORRUPT_GOLDEN")) relu1[0]^=8'd1;
        reset_all();run_segment(0);scan_ram();run_segment(1);scan_ram();
        // Reserved mode must not issue requests or touch memory; FULL is now legal.
        @(negedge clk);run_mode=inference_mode_t'(3);start_valid=1;
        @(negedge clk);start_valid=0;
        while(!error) begin
            if(input_request_valid || weight_request_valid || dut.path.r_en || dut.path.w_en)
                $fatal(1,"Invalid mode moved data");
            @(negedge clk);
        end
        if(error_code!=LERR_MODE || done || !busy) $fatal(1,"Invalid mode rejection");
        reset_all();
        // Interrupt a real load via source_error; common reset recovers.
        @(negedge clk);run_mode=RUN_FC_TAIL;start_valid=1;
        @(negedge clk);start_valid=0;
        while(!input_request_valid) @(negedge clk);
        input_request_ready=1;@(negedge clk);input_request_ready=0;
        input_valid=1;input_data=flatten[0];
        do @(posedge clk); while(!input_ready);
        @(negedge clk);input_valid=0;source_error=1;
        while(!error) @(negedge clk);
        if(error_code!=LERR_SOURCE || input_ready || weight_ready || read_ready || start_ready)
            $fatal(1,"Source failure did not lock");
        reset_all();run_segment(1);scan_ram();
        if(runs!=3 || operations!=7 || weight_requests!=5 || read_beats!=98304 || checked_bytes!=96120 || stalls==0 || gaps==0)
            $fatal(1,"S4 coverage missing runs=%0d ops=%0d loads=%0d reads=%0d checks=%0d",runs,operations,weight_requests,read_beats,checked_bytes);
        $display("PASS S4 real software PIPE=%0d runs=%0d ops=%0d weight_requests=%0d read_beats=%0d checked_bytes=%0d stalls=%0d gaps=%0d",
                 RESULT_PIPELINED,runs,operations,weight_requests,read_beats,checked_bytes,stalls,gaps);
        $finish;
    end
endmodule
