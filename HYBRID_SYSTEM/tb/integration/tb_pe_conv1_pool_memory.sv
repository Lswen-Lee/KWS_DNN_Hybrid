`timescale 1ns/1ps
// Actual integrated RTL, loaded/read back solely through public host ports.
// Golden files stay in TB arrays; never preload intermediate golden into DUT.
module tb_pe_conv1_pool_memory;
    import kws_system_pkg::*;
    parameter bit RESULT_PIPELINED=0;
    logic clk=0,rst=1;
    always #5 clk=~clk;
    logic load_valid=0,load_ready,load_data_valid=0,load_data_ready;
    activation_write_mode_t load_mode=WRITE_LINEAR;
    logic [14:0] load_base=0;
    logic [15:0] load_count=0;
    logic [7:0] load_width=0,load_height=0,load_data=0,load_x=0,load_y=0;
    logic [5:0] load_channels=0,load_channel=0;
    wire load_done,load_error;
    logic read_valid=0,read_out_ready=0;
    wire read_ready,read_out_valid,read_last,read_done,read_error;
    logic [14:0] read_base=0;
    logic [15:0] read_count=0;
    wire [7:0] read_data;
    logic pool_valid=0;
    wire pool_ready,pool_done,pool_error,fault,busy;
    logic [14:0] pool_src_base=0,pool_dst_base=0;
    logic [7:0] pool_width=0,pool_height=0;
    logic [5:0] pool_channels=0;
    logic weight_load_valid=0,weight_valid=0;
    wire weight_load_ready,weight_ready,weight_load_done,weight_load_error,resident_valid;
    logic [2:0] weight_layer_id=0;
    logic [7:0] weight_k=0;
    logic [5:0] weight_channels=0;
    logic signed [7:0] weight_i8=0;
    logic pe_cmd_valid=0,pe_is_fc=0,pe_relu_enable=1;
    wire pe_cmd_ready,pe_done,pe_error;
    logic [2:0] pe_layer_id=0;
    logic [14:0] pe_src_base=8064,pe_dst_base=10080;
    logic [7:0] pe_width=63,pe_height=32,pe_vector_length=9;
    logic [5:0] pe_input_channels=1,pe_output_channels=12;
    kws_activation_path #(.RESULT_PIPELINED(RESULT_PIPELINED)) dut (.*);

    logic [7:0] input_bytes[0:8063],pool1_bytes[0:2015];
    logic [7:0] conv1_bytes[0:21959],relu1_bytes[0:21959],pool2_bytes[0:5399];
    logic [7:0] conv1_weights[0:107],fc1_weights[0:4607],fc2_weights[0:255];
    logic [7:0] flatten_bytes[0:143],fc1_bytes[0:31],relu4_bytes[0:31],fc2_bytes[0:7];
    logic [7:0] reference_mem[0:32767];
    string vectors;
    logic [31:0] rng=32'h5052026;
    integer seed_arg;
    integer checks=0,operations=0,rejections=0,weight_loads=0,cycles=0,stalls=0;
    integer writes=0,reads=0,activation_beats=0,patches=0,replays=0,writer_commands=0;
    integer expected_reads=0,expected_writes=0,src=0,dst=0,kind=0,k=0,channels=0,out_w=0;
    bit checking=0;
    function automatic bit random_ready;
        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
        return rng[0] || rng[3];
    endfunction
    function automatic integer input_address(input integer index);
        integer patch_index;
        if(kind==1) begin
            patch_index=index/9;
            return src+(patch_index/61+(index%9)/3)*63+patch_index%61+index%3;
        end
        if(kind==2) return src+index%k;
        return src+index;
    endfunction
    always @(posedge clk) begin : monitor
        integer addr,position,ch;
        cycles++;
        if(cycles>4000000) $fatal(1,"Watchdog timeout");
        if(!rst) begin
            if(int'(load_valid && load_ready)+int'(read_valid && read_ready)+
               int'(pool_valid && pool_ready)+int'(pe_cmd_valid && pe_cmd_ready)+
               int'(weight_load_valid && weight_load_ready)>1) $fatal(1,"Two owners accepted");
            if(busy && (load_ready || read_ready || pool_ready || pe_cmd_ready || weight_load_ready))
                $fatal(1,"Command accepted while busy");
        end
        if(!rst && checking) begin
            if(dut.r_en) begin
                if(reads>=expected_reads || int'(dut.r_addr)!=input_address(reads))
                    $fatal(1,"RAM read index=%0d addr=%0d expected=%0d",reads,dut.r_addr,input_address(reads));
                reads++;
            end
            if(dut.activation_valid && dut.activation_ready) begin
                if(dut.r_data!==reference_mem[input_address(activation_beats)])
                    $fatal(1,"PE activation mismatch index=%0d",activation_beats);
                activation_beats++;
            end
            if(dut.compute_valid && dut.compute_ready) patches++;
            if(dut.replay_valid && dut.replay_ready) replays++;
            if(dut.pw_cmd && dut.wc_ready) writer_commands++;
            if(dut.w_en) begin
                if(kind==1) begin
                    position=writes/channels;ch=writes%channels;
                    addr=dst+ch*1830+(position/out_w)*out_w+position%out_w;
                end else addr=dst+writes;
                if(writes>=expected_writes || int'(dut.w_addr)!=addr || dut.w_data!==reference_mem[addr])
                    $fatal(1,"Commit mismatch n=%0d addr=%0d expected_addr=%0d data=%0d expected=%0d",
                           writes,dut.w_addr,addr,dut.w_data,reference_mem[addr]);
                writes++;
            end
        end
    end
    task automatic reset_all;
        @(negedge clk);checking=0;rst=1;
        load_valid=0;read_valid=0;pool_valid=0;pe_cmd_valid=0;weight_load_valid=0;
        load_data_valid=0;weight_valid=0;read_out_ready=0;
        repeat(3) @(negedge clk);rst=0;
        @(negedge clk);
        if(busy || fault || resident_valid) $fatal(1,"Reset did not clear owner/metadata");
    endtask
    task automatic load_ram(input integer base_addr,count,selection);
        @(negedge clk);load_base=15'(base_addr);load_count=16'(count);load_valid=1;
        #1;if(!load_ready) $fatal(1,"Host load not ready");
        @(negedge clk);load_valid=0;
        while(!load_data_ready) @(negedge clk);
        for(integer i=0;i<count;i++) begin
            while(!random_ready()) begin load_data_valid=0;@(negedge clk);end
            case(selection)
                0: load_data=8'ha5;
                1: load_data=input_bytes[i];
                2: load_data=pool1_bytes[i];
                3: load_data=flatten_bytes[i];
                default: $fatal(1,"No golden-output injection allowed");
            endcase
            load_data_valid=1;reference_mem[base_addr+i]=load_data;
            do @(posedge clk); while(!load_data_ready);
            @(negedge clk);
        end
        load_data_valid=0;
        while(!load_done && !load_error) @(negedge clk);
        if(load_error) $fatal(1,"Host load failed");
        @(negedge clk);
    endtask
    task automatic scan_ram(input string label_text);
        integer index;
        logic held;
        logic [8:0] payload;
        @(negedge clk);read_base=0;read_count=32768;read_valid=1;
        #1;if(!read_ready) $fatal(1,"Host read not ready");
        @(negedge clk);read_valid=0;index=0;held=0;payload=0;
        while(!read_done) begin
            read_out_ready=random_ready();
            @(posedge clk);
            if(held && (!read_out_valid || {read_last,read_data}!==payload)) $fatal(1,"Readback stall corruption");
            held=read_out_valid && !read_out_ready;payload={read_last,read_data};
            if(held) stalls++;
            if(read_out_valid && read_out_ready) begin
                if(index>=32768 || read_data!==reference_mem[index] || read_last!==(index==32767))
                    $fatal(1,"%s RAM addr=%0d actual=%0d expected=%0d",label_text,index,read_data,reference_mem[index]);
                index++;checks++;
            end
            @(negedge clk);
        end
        if(index!=32768 || read_error) $fatal(1,"Readback incomplete");
        read_out_ready=0;@(negedge clk);
        $display("PASS readback %s: 32768 bytes",label_text);
    endtask
    task automatic load_weights(input integer layer_id,kk,cc);
        integer n;
        @(negedge clk);weight_layer_id=3'(layer_id);weight_k=8'(kk);weight_channels=6'(cc);weight_load_valid=1;
        pe_cmd_valid=1;pool_valid=1;load_valid=1;read_valid=1;
        #1;if(!weight_load_ready || pe_cmd_ready || pool_ready || load_ready || read_ready) $fatal(1,"Weight command priority");
        @(negedge clk);weight_load_valid=0;pe_cmd_valid=0;pool_valid=0;load_valid=0;read_valid=0;
        if(resident_valid) $fatal(1,"Old metadata retained during reload");
        // Live inputs can change after handshake; the owner saves identity.
        weight_layer_id=7;weight_k=0;weight_channels=0;
        n=kk*cc;
        for(integer i=0;i<n;i++) begin
            while(!random_ready()) begin weight_valid=0;@(negedge clk);end
            case(layer_id)
                0: weight_i8=$signed(conv1_weights[i]);
                3: weight_i8=$signed(fc1_weights[i]);
                4: weight_i8=$signed(fc2_weights[i]);
                default: $fatal(1,"Unsupported weight fixture");
            endcase
            weight_valid=1;
            do @(posedge clk); while(!weight_ready);
            @(negedge clk);
        end
        weight_valid=0;
        while(!weight_load_done && !weight_load_error) @(negedge clk);
        if(weight_load_error || !resident_valid || int'(dut.resident_layer_id)!=layer_id ||
           int'(dut.resident_k)!=kk || int'(dut.resident_channels)!=cc) $fatal(1,"Resident metadata wrong");
        weight_loads++;@(negedge clk);
    endtask
    task automatic clear_counters;
        writes=0;reads=0;activation_beats=0;patches=0;replays=0;writer_commands=0;
    endtask
    task automatic run_pool(input integer b,d,w,h,c);
        src=b;dst=d;kind=0;expected_reads=w*h*c;expected_writes=(w/2)*(h/2)*c;
        clear_counters();
        @(negedge clk);pool_src_base=15'(b);pool_dst_base=15'(d);pool_width=8'(w);pool_height=8'(h);pool_channels=6'(c);pool_valid=1;
        #1;if(!pool_ready) $fatal(1,"Pool command not ready");
        @(negedge clk);pool_valid=0;checking=1;
        while(!pool_done && !pool_error) @(negedge clk);
        checking=0;
        if(pool_error || fault || reads!=expected_reads || writes!=expected_writes) $fatal(1,"Pool completion mismatch");
        operations++;@(negedge clk);
    endtask
    task automatic configure_pe(input integer layer_id,input bit relu_on);
        pe_layer_id=3'(layer_id);pe_relu_enable=relu_on;pe_is_fc=(layer_id!=0);
        pe_width=layer_id==0 ? 8'd63 : 8'd0;pe_height=layer_id==0 ? 8'd32 : 8'd0;
        pe_input_channels=layer_id==0 ? 6'd1 : 6'd0;
        case(layer_id)
            0: begin pe_src_base=8064;pe_dst_base=10080;pe_vector_length=9;pe_output_channels=12;end
            3: begin pe_src_base=0;pe_dst_base=144;pe_vector_length=144;pe_output_channels=32;end
            4: begin pe_src_base=144;pe_dst_base=0;pe_vector_length=32;pe_output_channels=8;end
            default: $fatal(1,"Unsupported compute fixture");
        endcase
    endtask
    task automatic run_pe(input integer layer_id,input bit relu_on);
        configure_pe(layer_id,relu_on);
        src=int'(pe_src_base);dst=int'(pe_dst_base);kind=layer_id==0 ? 1 : 2;
        k=int'(pe_vector_length);channels=int'(pe_output_channels);out_w=layer_id==0 ? 61 : 1;
        expected_reads=layer_id==0 ? 16470 : k*((channels+11)/12);
        expected_writes=layer_id==0 ? 21960 : channels;
        clear_counters();
        @(negedge clk);pe_cmd_valid=1;pool_valid=1;load_valid=1;read_valid=1;
        #1;if(!pe_cmd_ready || pool_ready || load_ready || read_ready) $fatal(1,"PE arbitration failed");
        @(negedge clk);pe_cmd_valid=0;pool_valid=0;load_valid=0;read_valid=0;checking=1;
        pe_layer_id=7;pe_src_base=32767;pe_dst_base=32767;
        // Try all other operations while PE owns the path: no acceptance.
        weight_load_valid=1;pool_valid=1;load_valid=1;read_valid=1;
        repeat(3) @(negedge clk);
        weight_load_valid=0;pool_valid=0;load_valid=0;read_valid=0;
        while(!pe_done && !pe_error) @(negedge clk);
        checking=0;
        if(pe_error || fault || reads!=expected_reads || activation_beats!=expected_reads ||
           writes!=expected_writes || writer_commands!=1 ||
           patches!=(layer_id==0 ? 1830 : 1) || replays!=patches*((channels+11)/12))
            $fatal(1,"PE completion/count mismatch layer=%0d",layer_id);
        $display("PASS PE layer=%0d relu=%0d patches=%0d replays=%0d reads=%0d writes=%0d",
                 layer_id,relu_on,patches,replays,reads,writes);
        operations++;@(negedge clk);
    endtask
    task automatic reject_pe;
        @(negedge clk);pe_cmd_valid=1;
        @(negedge clk);pe_cmd_valid=0;
        while(!pe_error && !pe_done) begin
            if(dut.r_en || dut.w_en || dut.compute_valid) $fatal(1,"Rejected PE touched datapath");
            @(negedge clk);
        end
        if(!pe_error || pe_done || fault || busy) $fatal(1,"PE reject failed");
        rejections++;@(negedge clk);
    endtask
    task automatic reject_weights(input integer id,kk);
        @(negedge clk);weight_layer_id=3'(id);weight_k=8'(kk);weight_channels=12;weight_load_valid=1;
        @(negedge clk);weight_load_valid=0;
        while(!weight_load_error && !weight_load_done) @(negedge clk);
        if(!weight_load_error || weight_load_done || resident_valid || busy) $fatal(1,"Weight reject failed");
        rejections++;@(negedge clk);
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"Provide +VECTORS directory");
        if($value$plusargs("SEED=%d",seed_arg)) rng=32'(seed_arg);
        if(rng==0) $fatal(1,"Nonzero random seed required");
        $readmemh({vectors,"/quant_input.mem"},input_bytes);
        $readmemh({vectors,"/pool1.mem"},pool1_bytes);
        $readmemh({vectors,"/conv1.mem"},conv1_bytes);
        $readmemh({vectors,"/relu1.mem"},relu1_bytes);
        $readmemh({vectors,"/pool2.mem"},pool2_bytes);
        $readmemh({vectors,"/conv1_weights.mem"},conv1_weights);
        $readmemh({vectors,"/fc1_weights.mem"},fc1_weights);
        $readmemh({vectors,"/fc2_weights.mem"},fc2_weights);
        $readmemh({vectors,"/flatten.mem"},flatten_bytes);
        $readmemh({vectors,"/fc1.mem"},fc1_bytes);
        $readmemh({vectors,"/relu4.mem"},relu4_bytes);
        $readmemh({vectors,"/fc2.mem"},fc2_bytes);
        // A separate negative run proves that the checker is not vacuous.
        if($test$plusargs("CORRUPT_GOLDEN")) relu1_bytes[0]=relu1_bytes[0]^8'd1;
        reset_all();configure_pe(0,1);reject_pe(); // No resident weights.
        reject_weights(7,9);reject_weights(0,0);
        load_ram(0,32768,0);load_ram(0,8064,1);scan_ram("initial quant_input");
        for(integer i=0;i<2016;i++) reference_mem[8064+i]=pool1_bytes[i];
        run_pool(0,8064,126,64,1);scan_ram("hardware pool1");
        load_weights(0,9,12);
        configure_pe(0,1);pe_layer_id=1;reject_pe(); // Wrong layer identity.
        for(integer i=0;i<21960;i++) reference_mem[10080+i]=conv1_bytes[i];
        run_pe(0,0);scan_ram("conv1 before ReLU diagnostic");
        for(integer i=0;i<21960;i++) reference_mem[10080+i]=relu1_bytes[i];
        run_pe(0,1);scan_ram("hardware conv1 ReLU"); // Reuse weights, no reload.
        for(integer i=0;i<5400;i++) reference_mem[i]=pool2_bytes[i];
        run_pool(10080,0,61,30,12);scan_ram("hardware pool2 chained");
        // FC branch starts from exported flatten, NOT from unimplemented Conv2/3.
        load_ram(0,144,3);scan_ram("exported flatten input");load_weights(3,144,32);
        for(integer i=0;i<32;i++) reference_mem[144+i]=fc1_bytes[i];
        run_pe(3,0);scan_ram("fc1 before ReLU diagnostic");
        for(integer i=0;i<32;i++) reference_mem[144+i]=relu4_bytes[i];
        run_pe(3,1);scan_ram("hardware fc1 ReLU");
        load_weights(4,32,8);
        for(integer i=0;i<8;i++) reference_mem[i]=fc2_bytes[i];
        run_pe(4,0);scan_ram("hardware fc2 chained");
        // A failed reload must invalidate PREVIOUSLY successful weights.
        reject_weights(0,0);configure_pe(4,0);reject_pe();load_weights(4,32,8);
        // Error injection only, normal computation above uses unmodified RTL.
        configure_pe(4,0);@(negedge clk);pe_cmd_valid=1;
        @(negedge clk);pe_cmd_valid=0;
        while(!dut.result_valid) @(negedge clk);
        force dut.pe_controller.pe_out_error=1'b1;
        while(!pe_error) @(negedge clk);
        release dut.pe_controller.pe_out_error;
        repeat(3) @(negedge clk);
        if(!fault || !busy || weight_load_ready || pe_cmd_ready || pool_ready || load_ready || read_ready)
            $fatal(1,"FAULT did not lock all owners");
        reset_all();configure_pe(4,0);reject_pe();
        // Interrupt a partial weight load; no resident layer may survive it.
        @(negedge clk);weight_load_valid=1;weight_layer_id=4;weight_k=32;weight_channels=8;
        @(negedge clk);weight_load_valid=0;weight_valid=1;weight_i8=$signed(fc2_weights[0]);
        do @(posedge clk); while(!weight_ready);
        @(negedge clk);weight_valid=0;
        reset_all();configure_pe(4,0);reject_pe();
        load_weights(4,32,8);run_pe(4,0);scan_ram("post-reset recovery, RAM retained");
        if(operations!=8 || rejections!=8 || weight_loads!=5 || checks!=327680 || stalls==0)
            $fatal(1,"Coverage missing ops=%0d rejects=%0d loads=%0d checks=%0d",operations,rejections,weight_loads,checks);
        $display("PASS S3 software PIPE=%0d operations=%0d rejects=%0d loads=%0d RAM_checks=%0d stalls=%0d",
                 RESULT_PIPELINED,operations,rejections,weight_loads,checks,stalls);
        $finish;
    end
endmodule
