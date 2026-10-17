`timescale 1ns/1ps
// Public-port host stimulus, real PE + CDC + pin master + chip, one PoT.
// Normal computation uses real endpoints. REVIEW_ONLY explicitly forces stale
// valid/empty signals for fault injection, never FSM states or MAC results.
module tb_kws_shared_postprocess;
    import kws_system_pkg::*;
    parameter bit POSTPROCESS_PIPELINED=0;
    logic clk=0,clk_cim=0,reset_request=1;
    always #4 clk=~clk;
    initial begin #2.7; forever #9.434 clk_cim=~clk_cim; end
    logic [1:0] sr=3,cr=3;
    always @(posedge clk or posedge reset_request)
        if(reset_request) sr<=3; else sr<={sr[0],1'b0};
    always @(posedge clk_cim or posedge reset_request)
        if(reset_request) cr<=3; else cr<={cr[0],1'b0};
    wire rst=sr[1],rst_cim=cr[1];
    logic load_valid=0,load_data_valid=0;
    wire load_ready,load_data_ready,load_done,load_error;
    activation_write_mode_t load_mode=WRITE_LINEAR;
    logic [14:0] load_base=0;
    logic [15:0] load_count=0;
    logic [7:0] load_width=0,load_height=0,load_data=0,load_x=0,load_y=0;
    logic [5:0] load_channels=0,load_channel=0;
    logic read_valid=0,read_out_ready=0;
    wire read_ready,read_out_valid,read_last,read_done,read_error;
    logic [14:0] read_base=0;
    logic [15:0] read_count=0;
    wire [7:0] read_data;
    logic pool_valid=0;
    wire pool_ready,pool_done,pool_error,fault,busy;
    logic [14:0] pool_src_base=0,pool_dst_base=0;
    logic [7:0] pool_width=0,pool_height=0;
    logic [5:0] pool_channels=12;
    logic weight_load_valid=0,weight_valid=0,weight_backend=0;
    wire weight_load_ready,weight_ready,weight_load_done,weight_load_error,resident_valid;
    logic [2:0] weight_layer_id=0;
    logic [7:0] weight_k=0;
    logic [5:0] weight_channels=0;
    logic signed [7:0] weight_i8=0;
    logic pe_cmd_valid=0,pe_is_fc=1,pe_relu_enable=0;
    wire pe_cmd_ready,pe_done,pe_error;
    logic [2:0] pe_layer_id=4;
    logic [14:0] pe_src_base=30000,pe_dst_base=30100;
    logic [7:0] pe_width=1,pe_height=1,pe_vector_length=32;
    logic [5:0] pe_input_channels=1,pe_output_channels=8;
    logic dcim_cmd_valid=0,dcim_relu_enable=1;
    wire dcim_cmd_ready,dcim_done,dcim_error,dcim_resident_valid;
    logic [2:0] dcim_layer_id=1;
    logic [14:0] dcim_src_base=0,dcim_dst_base=5400;
    logic [7:0] dcim_width=30,dcim_height=15;
    kws_activation_path #(.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) dut (.*);

    string vectors;
    logic [7:0] reference_mem[0:32767];
    logic [7:0] source_data[0:5399],dc_weights[0:1295],dc_golden[0:4367];
    logic signed [31:0] dc_acc[0:4367];
    logic [7:0] fc_weights[0:255],fc_input[0:31],fc_golden[0:7];
    integer fc_acc[0:7];
    integer iw,ih,ow,oh,dst,expected_outputs;
    integer raw_count=0,post_count=0,commit_count=0,operations=0,read_checks=0;
    integer switches=0,last_backend=-1,active_backend=-1,cycles=0,host_stalls=0;
    bit checking=0,allow_fault=0;
    always @(negedge clk) cycles<=cycles+1;

    function automatic integer output_index(input integer n);
        return active_backend==0 ? n : (n%12)*ow*oh+n/12;
    endfunction
    function automatic integer mac_reference(input integer p,c);
        integer sum,ix,channel,u,v;
        sum=0;
        for(integer k=0;k<108;k++) begin
            channel=k/9;u=(k%9)/3;v=k%3;
            ix=channel*iw*ih+(p/ow+u)*iw+p%ow+v;
            sum+=(int'(reference_mem[ix])-128)*int'($signed(dc_weights[c*108+k]));
        end
        return sum;
    endfunction
    always @(posedge clk) if(!rst) begin : monitor
        integer idx,expected_acc,channel;
        if(!allow_fault && (fault || load_error || read_error || pool_error || pe_error || dcim_error))
            $fatal(1,"unexpected path error");
        if((pe_cmd_valid && pe_cmd_ready) || (dcim_cmd_valid && dcim_cmd_ready))
            if(!dut.postprocess_empty) $fatal(1,"new owner before drain");
        if(dut.raw_ready && dut.d_raw_ready) $fatal(1,"both raw sources ready");
        // Expected backend comes from the TB command, not the DUT mux select.
        if(checking && dut.raw_ready && active_backend!=0) $fatal(1,"PE ready during DCIM command");
        if(checking && dut.d_raw_ready && active_backend!=1) $fatal(1,"DCIM ready during PE command");
        if((pe_done || dcim_done) && !dut.postprocess_empty) $fatal(1,"done before drain");
        if(checking) begin
            if((dut.raw_valid && dut.raw_ready) || (dut.d_raw_valid && dut.d_raw_ready)) begin
                idx=output_index(raw_count);
                channel=active_backend==0 ? raw_count : raw_count%12;
                expected_acc=active_backend==0 ? fc_acc[idx] : int'(dc_acc[idx]);
                if(raw_count>=expected_outputs) $fatal(1,"extra raw");
                if(active_backend==0) begin
                    if(dut.raw_data!==32'(expected_acc) || int'(dut.raw_channel)!=channel || dut.raw_last!=(channel==7))
                        $fatal(1,"PE raw mismatch");
                end else if(dut.d_raw_data!==32'(expected_acc) || int'(dut.d_raw_channel)!=channel || dut.d_raw_last!=(channel==11))
                    $fatal(1,"DCIM raw mismatch n=%0d",raw_count);
                raw_count++;
            end
            if(dut.result_valid && dut.result_ready) begin
                idx=output_index(post_count);
                if(post_count>=expected_outputs || dut.result_error || dut.pe_data!==reference_mem[dst+idx])
                    $fatal(1,"shared post mismatch n=%0d got=%0d expected=%0d",post_count,dut.pe_data,reference_mem[dst+idx]);
                post_count++;
            end
            if(dut.w_en) begin
                idx=output_index(commit_count);
                if(commit_count>=expected_outputs ||
                   int'(dut.w_addr)!=dst+idx+($test$plusargs("CORRUPT_COMMIT") && commit_count==0 ? 1 : 0) ||
                   dut.w_data!==reference_mem[dst+idx])
                    $fatal(1,"shared commit mismatch");
                commit_count++;
            end
        end
    end
    task automatic reset_all;
        @(negedge clk);reset_request=1;checking=0;pe_cmd_valid=0;dcim_cmd_valid=0;
        weight_load_valid=0;weight_valid=0;load_valid=0;load_data_valid=0;
        read_valid=0;read_out_ready=0;pool_valid=0;
        repeat(5) @(negedge clk);
        reset_request=0;wait(!rst && !rst_cim);@(negedge clk);
        if(resident_valid || dcim_resident_valid || !dut.postprocess_empty) $fatal(1,"reset state mismatch");
        allow_fault=0;
    endtask
    // 3 residue sources x 6 command classes: residue and command on one cycle.
    // Force represents a broken producer; it does not prove backend arithmetic.
    task automatic review_residue;
        for(integer source_id=0;source_id<3;source_id++) begin
            for(integer command_id=0;command_id<6;command_id++) begin
                reset_all();allow_fault=1;
                case(source_id)
                    0: force dut.raw_valid=1'b1;
                    1: force dut.d_raw_valid=1'b1;
                    2: force dut.postprocess_empty=1'b0;
                endcase
                weight_backend=0;
                case(command_id)
                    0: weight_load_valid=1;
                    1: pe_cmd_valid=1;
                    2: dcim_cmd_valid=1;
                    3: pool_valid=1;
                    4: load_valid=1;
                    5: read_valid=1;
                endcase
                #1;
                if(weight_load_ready || pe_cmd_ready || dcim_cmd_ready || pool_ready || load_ready || read_ready ||
                   dut.raw_ready || dut.d_raw_ready || dut.w_en || dut.r_en ||
                   dut.pe_engine.load_valid || dut.pe_controller.cmd_valid || dut.dcim_controller.cmd_valid ||
                   dut.controller.cmd_valid || dut.writer.cmd_valid || dut.reader.cmd_valid)
                    $fatal(1,"residue accepted command source=%0d command=%0d",source_id,command_id);
                @(negedge clk);
                if(!fault || !busy || pe_done || dcim_done || load_done || read_done || pool_done || weight_load_done)
                    $fatal(1,"residue did not fault");
                release dut.raw_valid;
                release dut.d_raw_valid;
                release dut.postprocess_empty;
                weight_load_valid=0;pe_cmd_valid=0;dcim_cmd_valid=0;pool_valid=0;load_valid=0;read_valid=0;
                repeat(3) @(negedge clk);
                if(!fault || pe_cmd_ready || dcim_cmd_ready || dut.w_en || dut.r_en)
                    $fatal(1,"residue fault not sticky");
            end
        end
        reset_all();
        $display("PASS residue cases=18 POST=%0d",POSTPROCESS_PIPELINED);
    endtask
    // source=0: sentinel; 1: software Pool2; 2: software FC input.
    task automatic host_load(input integer base,count,source);
        load_base=15'(base);load_count=16'(count);load_valid=1;
        do @(posedge clk); while(!load_ready);
        @(negedge clk);load_valid=0;
        for(integer i=0;i<count;i++) begin
            load_data=source==0 ? 8'hA6 : source==1 ? source_data[i] : fc_input[i];
            reference_mem[base+i]=load_data;load_data_valid=1;
            do @(posedge clk); while(!load_data_ready);
            @(negedge clk);load_data_valid=0;
        end
        while(!load_done) @(negedge clk);
        @(negedge clk);
    endtask
    task automatic load_weights(input bit backend,input integer layer);
        weight_backend=backend;weight_layer_id=3'(layer);weight_k=backend ? 108 : 32;
        weight_channels=backend ? 12 : 8;weight_load_valid=1;
        do @(posedge clk); while(!weight_load_ready);
        @(negedge clk);weight_load_valid=0;
        // The latched selector, not the live command payload, controls routing.
        weight_backend=!backend;
        for(integer i=0;i<(backend ? 1296 : 256);i++) begin
            weight_i8=$signed(backend ? dc_weights[i] : fc_weights[i]);weight_valid=1;
            do @(posedge clk); while(!weight_ready);
            @(negedge clk);weight_valid=0;
            if(i%29==0) repeat(2) @(negedge clk);
        end
        while(!weight_load_done) begin
            if(weight_load_error) $fatal(1,"weight load error");
            @(negedge clk);
        end
        if(backend ? !dcim_resident_valid : !resident_valid) $fatal(1,"missing resident");
        @(negedge clk);
    endtask
    task automatic start_checks(input integer backend,count,base);
        raw_count=0;post_count=0;commit_count=0;expected_outputs=count;dst=base;
        active_backend=backend;checking=1;
        if(last_backend>=0 && last_backend!=backend) switches++;
        last_backend=backend;
    endtask
    task automatic finish_checks;
        if(raw_count!=expected_outputs || post_count!=expected_outputs || commit_count!=expected_outputs)
            $fatal(1,"result count mismatch raw=%0d post=%0d commit=%0d",raw_count,post_count,commit_count);
        if(!dut.postprocess_empty || busy) $fatal(1,"owner not drained");
        checking=0;operations++;
    endtask
    task automatic run_pe;
        for(integer c=0;c<8;c++) reference_mem[30100+c]=fc_golden[c];
        start_checks(0,8,30100);pe_cmd_valid=1;
        do @(posedge clk); while(!pe_cmd_ready);
        @(negedge clk);pe_cmd_valid=0;
        while(!pe_done) @(negedge clk);
        finish_checks();
    endtask
    task automatic run_dcim(input integer layer,width,height,base);
        iw=width;ih=height;ow=iw-2;oh=ih-2;
        for(integer p=0;p<ow*oh;p++) for(integer c=0;c<12;c++) begin
            if(mac_reference(p,c)!=int'(dc_acc[c*ow*oh+p])) $fatal(1,"software ACC versus independent math");
        end
        for(integer i=0;i<ow*oh*12;i++) reference_mem[base+i]=dc_golden[i];
        if($test$plusargs("CORRUPT_GOLDEN")) reference_mem[base]^=8'd1;
        start_checks(1,ow*oh*12,base);
        dcim_layer_id=3'(layer);dcim_width=8'(iw);dcim_height=8'(ih);dcim_dst_base=15'(base);
        dcim_cmd_valid=1;
        do @(posedge clk); while(!dcim_cmd_ready);
        @(negedge clk);dcim_cmd_valid=0;
        while(!dcim_done) @(negedge clk);
        finish_checks();
        $display("PASS shared DCIM layer=%0d patches=%0d POST=%0d",layer,ow*oh,POSTPROCESS_PIPELINED);
    endtask
    task automatic scan_ram;
        integer n;
        n=0;read_base=0;read_count=32768;read_valid=1;
        do @(posedge clk); while(!read_ready);
        @(negedge clk);read_valid=0;
        while(n<32768) begin
            read_out_ready=(cycles%3)!=0;
            @(posedge clk);
            if(read_out_valid && !read_out_ready) host_stalls++;
            if(read_out_valid && read_out_ready) begin
                if(read_data!==reference_mem[n] || read_last!=(n==32767)) $fatal(1,"shared readback mismatch addr=%0d",n);
                n++;read_checks++;
            end
            @(negedge clk);
        end
        read_out_ready=0;while(!read_done) @(negedge clk);
        @(negedge clk);
    endtask
    task automatic pool_layer(input integer base,width,height,count,input string golden_name);
        logic [7:0] pooled[0:1007];
        $readmemh({vectors,"/",golden_name,".mem"},pooled,0,count-1);
        for(integer i=0;i<count;i++) reference_mem[i]=pooled[i];
        pool_src_base=15'(base);pool_dst_base=0;pool_width=8'(width);pool_height=8'(height);pool_valid=1;
        do @(posedge clk); while(!pool_ready);
        @(negedge clk);pool_valid=0;
        while(!pool_done) @(negedge clk);
        @(negedge clk);scan_ram();
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"VECTORS required");
        $readmemh({vectors,"/relu4.mem"},fc_input);
        $readmemh({vectors,"/fc2_weights.mem"},fc_weights);
        $readmemh({vectors,"/fc2.mem"},fc_golden);
        for(integer c=0;c<8;c++) begin
            fc_acc[c]=0;
            for(integer k=0;k<32;k++) fc_acc[c]+=(int'(fc_input[k])-128)*int'($signed(fc_weights[c*32+k]));
        end
        if($test$plusargs("REVIEW_ONLY")) begin
            review_residue();
            host_load(30000,32,2);load_weights(0,4);
            if($test$plusargs("CORRUPT_RAW")) fc_acc[0]^=1;
            run_pe();
            $display("PASS review recovery POST=%0d raw=%0d post=%0d commit=%0d",POSTPROCESS_PIPELINED,raw_count,post_count,commit_count);
            $finish;
        end
        reset_all();host_load(0,32768,0);host_load(30000,32,2);load_weights(0,4);run_pe();
        $readmemh({vectors,"/pool2.mem"},source_data);
        $readmemh({vectors,"/conv2_weights.mem"},dc_weights);
        $readmemh({vectors,"/conv2_acc.mem"},dc_acc);
        $readmemh({vectors,"/relu2.mem"},dc_golden);
        host_load(0,5400,1);load_weights(1,1);
        // PE weights must survive DCIM loading and remain executable.
        run_pe();run_dcim(1,30,15,5400);run_pe();scan_ram();
        pool_layer(5400,28,13,1008,"pool3");
        // Conv3 uses HARDWARE Pool3 already in RAM, not reloaded golden.
        $readmemh({vectors,"/conv3_weights.mem"},dc_weights);
        $readmemh({vectors,"/conv3_acc.mem"},dc_acc,0,575);
        $readmemh({vectors,"/relu3.mem"},dc_golden,0,575);
        load_weights(1,2);run_dcim(2,14,6,1008);run_pe();scan_ram();
        pool_layer(1008,12,4,144,"pool4");
        if(switches!=4 || host_stalls==0) $fatal(1,"missing switching/stall coverage");
        $display("PASS SHARED POST=%0d operations=%0d switches=%0d read_checks=%0d host_stalls=%0d",POSTPROCESS_PIPELINED,operations,switches,read_checks,host_stalls);
        $finish;
    end
    initial begin #100000000; $fatal(1,"shared test watchdog"); end
endmodule
