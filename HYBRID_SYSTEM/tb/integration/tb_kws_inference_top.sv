`timescale 1ns/1ps
// S5-D1: real full network. Only initial input and requested weights enter DUT.
// Golden intermediate tensors are scoreboard data, never DUT stimulus.
module tb_kws_inference_top;
    import kws_system_pkg::*;
    parameter bit RESULT_PIPELINED=0;
    parameter bit POSTPROCESS_PIPELINED=0;
    logic clk=0,clk_cim=0,reset_request=1;
    always #4 clk=~clk;
    integer cim_half_ps=9434,phase_ps=2700;
    initial begin
        if ($value$plusargs("CIM_HALF_PS=%d",cim_half_ps)) begin end
        if ($value$plusargs("PHASE_PS=%d",phase_ps)) begin end
        if(cim_half_ps<=0 || phase_ps<0) $fatal(1,"Invalid clock configuration");
        #(phase_ps*1ps);
        forever #(cim_half_ps*1ps) clk_cim=~clk_cim;
    end
    logic [1:0] sr=3,cr=3;
    always @(posedge clk or posedge reset_request)
        if(reset_request) sr<=3; else sr<={sr[0],1'b0};
    always @(posedge clk_cim or posedge reset_request)
        if(reset_request) cr<=3; else cr<={cr[0],1'b0};
    wire rst=sr[1],rst_cim=cr[1];
    logic start_valid=0,start_ready,busy,done,error,op_done;
    inference_mode_t run_mode=RUN_FULL;
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
    kws_inference_top #(.RESULT_PIPELINED(RESULT_PIPELINED),
        .POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) dut (.*);

    logic [7:0] quant_input[0:8063],pool1[0:2015],relu1[0:21959],pool2[0:5399];
    logic [7:0] relu2[0:4367],pool3[0:1007],relu3[0:575],pool4[0:143],relu4[0:31],fc2[0:7];
    logic [7:0] w0[0:107],w1[0:1295],w2[0:1295],w3[0:4607],w4[0:255];
    logic [7:0] reference_mem[0:32767];
    bit initialized[0:32767];
    string vectors;
    logic [31:0] rng=505;
    integer seed_arg=505,cycles=0,phase=-1,next_op=0,reads=0,writes=0;
    integer input_requests=0,weight_requests=0,read_checks=0,read_stalls=0;
    integer read_totals[0:8]='{8064,16470,21960,39312,4368,5184,576,432,32};
    integer counts[0:8]='{2016,21960,5400,4368,1008,576,144,32,8};
    integer bases[0:8]='{8064,10080,0,5400,0,1008,0,144,0};
    bit checking=0;
    function automatic bit random_ready;
        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
        return rng[0] || rng[3];
    endfunction
    function automatic logic [7:0] golden(input integer op,n);
        case(op)
            0:return pool1[n]; 1:return relu1[n]; 2:return pool2[n];
            3:return relu2[n]; 4:return pool3[n]; 5:return relu3[n];
            6:return pool4[n]; 7:return relu4[n]; 8:return fc2[n];
            default:return 0;
        endcase
    endfunction
    // Independent CHW patch formula, not the DUT's address increment logic.
    function automatic integer read_address(input integer op,n);
        integer k,iw,ih,ow,p,t,base;
        case(op)
            0:return n;
            2:return 10080+n;
            4:return 5400+n;
            6:return 1008+n;
            7:return n%144;
            8:return 144+n;
            1:begin k=9;iw=63;ih=32;ow=61;base=8064;end
            3:begin k=108;iw=30;ih=15;ow=28;base=0;end
            5:begin k=108;iw=14;ih=6;ow=12;base=0;end
            default:return -1;
        endcase
        p=n/k;t=n%k;
        return base+(t/9)*iw*ih+(p/ow+(t%9)/3)*iw+p%ow+t%3;
    endfunction
    always @(posedge clk) begin : monitor
        integer idx,address;
        logic [7:0] expected;
        cycles++;
        if(cycles>20000000) $fatal(1,"S5D watchdog op=%0d",current_op);
        if(!rst && checking) begin
            if(error || dut.path_fault) $fatal(1,"S5D unexpected error code=%0d",error_code);
            if(dut.controller_busy && (read_ready || start_ready)) $fatal(1,"S5D ownership leaked");
            if(dut.load_valid && dut.load_ready) begin phase=-2;writes=0;end
            if((dut.pe_cmd_valid && dut.pe_cmd_ready) || (dut.dcim_cmd_valid && dut.dcim_cmd_ready) ||
               (dut.pool_valid && dut.pool_ready)) begin
                if(int'(current_op)!=next_op) $fatal(1,"S5D operation order");
                if(dut.dcim_cmd_valid != (next_op==3 || next_op==5) ||
                   dut.pe_cmd_valid != (next_op==1 || next_op==7 || next_op==8))
                    $fatal(1,"S5D backend selection");
                if(!dut.path.postprocess_empty) $fatal(1,"S5D command before drain");
                phase=next_op;reads=0;writes=0;
            end
            if(dut.path.raw_ready && dut.path.d_raw_ready) $fatal(1,"S5D simultaneous raw ready");
            if(dut.path.raw_ready && (phase==3 || phase==5)) $fatal(1,"S5D non-owner PE ready");
            if(dut.path.d_raw_ready && !(phase==3 || phase==5)) $fatal(1,"S5D non-owner DCIM ready");
            if(dut.path.r_en) begin
                if(phase<0 || phase>8) $fatal(1,"S5D unscheduled read");
                address=read_address(phase,reads);
                if(reads>=read_totals[phase] || int'(dut.path.r_addr)!=address || !initialized[address])
                    $fatal(1,"S5D read mismatch op=%0d n=%0d",phase,reads);
                reads++;
            end
            if(dut.path.w_en) begin
                if(phase==-2) begin
                    if(writes>=8064) $fatal(1,"S5D excess input");
                    address=writes;expected=quant_input[writes];
                end else begin
                    if(phase<0 || phase>8) $fatal(1,"S5D unscheduled write");
                    if(writes>=counts[phase]) $fatal(1,"S5D excess output");
                    idx=(phase==1 || phase==3 || phase==5) ? (writes%12)*(counts[phase]/12)+writes/12 : writes;
                    address=bases[phase]+idx;expected=golden(phase,idx);
                end
                if(int'(dut.path.w_addr)!=address || dut.path.w_data!==expected)
                    $fatal(1,"S5D commit mismatch op=%0d n=%0d addr=%0d expected_addr=%0d got=%0d expected=%0d",
                        phase,writes,dut.path.w_addr,address,dut.path.w_data,expected);
                reference_mem[address]=expected;initialized[address]=1;writes++;
            end
            if(dut.load_done && (phase!=-2 || writes!=8064)) $fatal(1,"S5D early input done");
            if(op_done) begin
                if(phase!=next_op || int'(current_op)!=next_op) $fatal(1,"S5D wrong op_done");
                if(reads!=read_totals[phase] || writes!=counts[phase] || !dut.path.postprocess_empty)
                    $fatal(1,"S5D early operation done");
                $display("PASS S5D op=%0d reads=%0d commits=%0d PIPE=%0d POST=%0d cycles=%0d",
                    phase,reads,writes,RESULT_PIPELINED,POSTPROCESS_PIPELINED,cycles);
                next_op++;phase=-1;
            end
        end
    end
    task automatic supply_input;
        if(input_requests!=0 || input_count!=8064 || input_is_flatten) $fatal(1,"S5D input request");
        repeat(4) begin
            @(negedge clk);
            if(!input_request_valid || input_count!=8064 || input_is_flatten || input_ready)
                $fatal(1,"S5D input request unstable");
        end
        input_request_ready=1;@(negedge clk);input_request_ready=0;input_requests++;
        for(integer n=0;n<8064;n++) begin
            while(!random_ready()) begin input_valid=0;@(negedge clk);end
            input_valid=1;input_data=quant_input[n];
            do @(posedge clk); while(!input_ready);
            @(negedge clk);
        end
        input_valid=0;
    endtask
    task automatic supply_weights;
        integer id,k,c;
        id=int'(weight_layer_id);
        if(id!=weight_requests) $fatal(1,"S5D weight order");
        k=id==0 ? 9 : id==3 ? 144 : id==4 ? 32 : 108;
        c=id==3 ? 32 : id==4 ? 8 : 12;
        if(int'(weight_k)!=k || int'(weight_channels)!=c) $fatal(1,"S5D weight metadata");
        repeat(4) begin
            @(negedge clk);
            if(!weight_request_valid || int'(weight_layer_id)!=id || weight_ready)
                $fatal(1,"S5D weight request unstable");
        end
        weight_request_ready=1;@(negedge clk);weight_request_ready=0;weight_requests++;
        for(integer n=0;n<k*c;n++) begin
            while(!random_ready()) begin weight_valid=0;@(negedge clk);end
            case(id)
                0:weight_i8=$signed(w0[n]);1:weight_i8=$signed(w1[n]);2:weight_i8=$signed(w2[n]);
                3:weight_i8=$signed(w3[n]);4:weight_i8=$signed(w4[n]);
                default:$fatal(1,"S5D invalid weight id");
            endcase
            weight_valid=1;do @(posedge clk);while(!weight_ready);@(negedge clk);
        end
        weight_valid=0;
    endtask
    task automatic scan_ram;
        integer n;
        bit held;
        logic [8:0] payload;
        @(negedge clk);read_valid=1;
        do @(posedge clk);while(!read_ready);
        @(negedge clk);read_valid=0;n=0;held=0;payload=0;
        while(!read_done) begin
            read_out_ready=random_ready();@(posedge clk);
            if(start_ready) $fatal(1,"S5D read ownership");
            if(held && (!read_out_valid || {read_last,read_data}!==payload)) $fatal(1,"S5D read unstable");
            held=read_out_valid && !read_out_ready;payload={read_last,read_data};
            if(held) read_stalls++;
            if(read_out_valid && read_out_ready) begin
                if(n>=32768 || read_last!=(n==32767)) $fatal(1,"S5D read last/count");
                if(initialized[n]) begin
                    if(read_data!==reference_mem[n]) $fatal(1,"S5D RAM mismatch address=%0d",n);
                    read_checks++;
                end
                n++;
            end
            @(negedge clk);
        end
        if(n!=32768 || read_error) $fatal(1,"S5D incomplete RAM scan");
        read_out_ready=0;
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"Missing vectors");
        if($value$plusargs("SEED=%d",seed_arg)) rng=32'(seed_arg);
        if(rng==0) $fatal(1,"Nonzero seed required");
        for(integer n=0;n<32768;n++) initialized[n]=0;
        $readmemh({vectors,"/quant_input.mem"},quant_input);
        $readmemh({vectors,"/pool1.mem"},pool1);$readmemh({vectors,"/relu1.mem"},relu1);
        $readmemh({vectors,"/pool2.mem"},pool2);$readmemh({vectors,"/relu2.mem"},relu2);
        $readmemh({vectors,"/pool3.mem"},pool3);$readmemh({vectors,"/relu3.mem"},relu3);
        $readmemh({vectors,"/pool4.mem"},pool4);$readmemh({vectors,"/relu4.mem"},relu4);
        $readmemh({vectors,"/fc2.mem"},fc2);
        $readmemh({vectors,"/conv1_weights.mem"},w0);$readmemh({vectors,"/conv2_weights.mem"},w1);
        $readmemh({vectors,"/conv3_weights.mem"},w2);$readmemh({vectors,"/fc1_weights.mem"},w3);
        $readmemh({vectors,"/fc2_weights.mem"},w4);
        if($test$plusargs("CORRUPT_GOLDEN")) relu2[0]^=8'd1;
        repeat(5) @(negedge clk);reset_request=0;
        wait(!rst && !rst_cim);repeat(4) @(negedge clk);
        checking=1;start_valid=1;read_valid=1;
        #1;if(!start_ready || read_ready) $fatal(1,"S5D start priority");
        @(negedge clk);start_valid=0;run_mode=RUN_FC_TAIL; // Saved FULL must survive.
        while(!done) begin
            if(input_request_valid) supply_input();
            else if(weight_request_valid) supply_weights();
            else @(negedge clk);
        end
        read_valid=0;checking=0;
        if(next_op!=9 || input_requests!=1 || weight_requests!=5 || busy || error)
            $fatal(1,"S5D completion coverage");
        @(negedge clk);if(done) $fatal(1,"S5D done not pulse");
        scan_ram();
        if(read_checks!=32040 || read_stalls==0) $fatal(1,"S5D RAM coverage");
        $display("PASS S5D FULL PIPE=%0d POST=%0d ops=%0d weights=%0d RAM_checks=%0d read_stalls=%0d cycles=%0d seed=%0d half_ps=%0d phase_ps=%0d",
            RESULT_PIPELINED,POSTPROCESS_PIPELINED,next_op,weight_requests,read_checks,read_stalls,cycles,seed_arg,cim_half_ps,phase_ps);
        $finish;
    end
endmodule
