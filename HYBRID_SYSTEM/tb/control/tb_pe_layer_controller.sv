`timescale 1ns/1ps
// Real endpoints throughout: RAM, reader, writer, weight loader and PE/PoT.
// TB alone initializes/readbacks RAM through its public synchronous ports.
module tb_pe_layer_controller;
    import kws_system_pkg::*;
    parameter bit RESULT_PIPELINED=0;
    logic clk=0, rst=1;
    always #5 clk=~clk;
    logic cmd_valid=0, cmd_ready, cmd_is_fc=0, cmd_relu_enable=1;
    logic [2:0] cmd_layer_id=0;
    logic [14:0] cmd_src_base=0, cmd_dst_base=0;
    logic [7:0] cmd_width=0,cmd_height=0,cmd_vector_length=0;
    logic [5:0] cmd_input_channels=0,cmd_output_channels=0;
    logic resident_valid=0;
    logic [2:0] resident_layer_id=0;
    logic [7:0] resident_k=0;
    logic [5:0] resident_channels=0;
    wire busy,done,error,fault;
    wire reader_cmd_valid,reader_cmd_ready,reader_done,reader_error;
    activation_read_mode_t reader_mode;
    wire [14:0] reader_base;
    wire [15:0] reader_count;
    wire [7:0] reader_width,reader_height,reader_x,reader_y;
    wire [5:0] reader_channels;
    wire reader_out_valid,reader_out_last,reader_out_ready;
    wire pe_compute_valid,pe_compute_ready,pe_compute_done,pe_compute_error;
    wire [2:0] pe_layer_id;
    wire pe_relu_enable,pe_replay_valid,pe_replay_ready;
    wire [7:0] pe_replay_k;
    wire [4:0] pe_replay_channel_base;
    wire pe_activation_valid,pe_activation_ready;
    wire pe_out_valid,pe_out_group_last,pe_out_error,pe_out_ready;
    wire [4:0] pe_out_channel_id;
    wire writer_cmd_valid,writer_cmd_ready,writer_in_ready,writer_done,writer_error;
    activation_write_mode_t writer_mode;
    wire [14:0] writer_base;
    wire [15:0] writer_count;
    wire [7:0] writer_width,writer_height,writer_x,writer_y;
    wire [5:0] writer_channels,writer_channel;
    wire writer_in_valid;
    pe_layer_controller dut (.*);

    wire [7:0] activation_data, result_data;
    wire ram_rd_en,ram_rd_valid,ram_wr_en;
    wire [14:0] ram_rd_addr,ram_wr_addr;
    wire [7:0] ram_rd_data,ram_wr_data;
    logic host_access=1,host_wr=0,host_rd=0;
    logic [14:0] host_addr=0;
    logic [7:0] host_data=0;
    activation_buffer memory (.clk(clk),.rst(rst),
        .wr_en(host_access ? host_wr : ram_wr_en),.wr_addr(host_access ? host_addr : ram_wr_addr),
        .wr_data(host_access ? host_data : ram_wr_data),
        .rd_en(host_access ? host_rd : ram_rd_en),.rd_addr(host_access ? host_addr : ram_rd_addr),
        .rd_valid(ram_rd_valid),.rd_data(ram_rd_data));
    activation_reader reader (.clk(clk),.rst(rst),
        .cmd_valid(reader_cmd_valid),.cmd_ready(reader_cmd_ready),.cmd_mode(reader_mode),
        .cmd_base(reader_base),.cmd_count(reader_count),.cmd_width(reader_width),
        .cmd_height(reader_height),.cmd_channels(reader_channels),.cmd_x(reader_x),.cmd_y(reader_y),
        .ram_rd_en(ram_rd_en),.ram_rd_addr(ram_rd_addr),
        .ram_rd_valid(ram_rd_valid && !host_access),.ram_rd_data(ram_rd_data),
        .out_valid(reader_out_valid),.out_ready(reader_out_ready),.out_data(activation_data),
        .out_last(reader_out_last),.busy(),.done(reader_done),.error(reader_error));
    // A test-only interconnect pause presents real backpressure to PE.
    // Both endpoints see exactly the same accepted transaction.
    logic pause_results=0;
    wire actual_writer_ready;
    assign writer_in_ready=actual_writer_ready && !pause_results;
    feature_map_writer writer (.clk(clk),.rst(rst),
        .cmd_valid(writer_cmd_valid),.cmd_ready(writer_cmd_ready),.cmd_mode(writer_mode),
        .cmd_base(writer_base),.cmd_count(writer_count),.cmd_width(writer_width),
        .cmd_height(writer_height),.cmd_channels(writer_channels),
        .in_valid(writer_in_valid && !pause_results),.in_ready(actual_writer_ready),
        .in_data(result_data),.in_channel(writer_channel),.in_x(writer_x),.in_y(writer_y),
        .wr_en(ram_wr_en),.wr_addr(ram_wr_addr),.wr_data(ram_wr_data),
        .busy(),.done(writer_done),.error(writer_error));
    logic load_valid=0,weight_valid=0;
    wire load_ready,load_done,load_error,layer_ready,weight_ready;
    logic [7:0] load_k=0;
    logic [5:0] load_channels=0;
    logic signed [7:0] weight_i8=0;
    wire [7:0] actual_replay_k;
    wire actual_out_error;
    logic inject_replay_error=0,inject_result_error=0;
    assign pe_replay_k=inject_replay_error ? actual_replay_k ^ 8'd1 : actual_replay_k;
    assign pe_out_error=actual_out_error || inject_result_error;
    pe_pot_engine #(.PE8_MODE(1),.RESULT_PIPELINED(RESULT_PIPELINED),.POSTPROCESS_PIPELINED(1)) pe (
        .clk(clk),.rst(rst),.load_valid(load_valid),.load_ready(load_ready),
        .load_k(load_k),.load_channels(load_channels),.load_busy(),.load_done(load_done),
        .load_error(load_error),.layer_ready(layer_ready),.weight_valid(weight_valid),
        .weight_ready(weight_ready),.weight_i8(weight_i8),
        .compute_valid(pe_compute_valid),.compute_ready(pe_compute_ready),
        .compute_layer_id(pe_layer_id),.relu_enable(pe_relu_enable),.compute_busy(),
        .compute_done(pe_compute_done),.compute_error(pe_compute_error),
        .replay_valid(pe_replay_valid),.replay_ready(pe_replay_ready),.replay_k(actual_replay_k),
        .replay_channel_base(pe_replay_channel_base),.activation_valid(pe_activation_valid),
        .activation_ready(pe_activation_ready),.activation_u8(activation_data),
        .out_valid(pe_out_valid),.out_ready(pe_out_ready),.out_data(result_data),
        .out_channel_id(pe_out_channel_id),.out_group_last(pe_out_group_last),.out_error(actual_out_error));

    // Independent mathematical reference and public-interface scoreboards.
    logic [7:0] reference_mem [0:32767];
    integer w=0,h=0,ci=0,co=0,k=0,ow=0,oh=0,src=0,dst=0,layer=0;
    bit is_fc=0,relu_on=0,checking=0;
    integer patches=0,replays=0,reads=0,results=0,writes=0,writer_commands=0;
    integer replay_position=0,replay_px=0,replay_py=0;
    integer expected_x=0,expected_y=0,expected_channel=0;
    integer checks=0,successes=0,rejected=0,fault_cases=0,cycles=0,stalls=0,final_pause=0;
    logic held=0;
    logic [30:0] held_payload;
    function automatic integer weight_value(input integer ch,idx);
        return ((ch*71+idx*29+17)%256)-128;
    endfunction
    function automatic integer shift_value(input integer l,ch);
        if(l==0) return ch==0 || ch==4 || ch==10 ? 8 : 9;
        if(l==3) return ch==10 || ch==13 || ch==23 || ch==27 || ch==28 ? 8 : 7;
        if(l==4) return 6;
        return 8;
    endfunction
    function automatic integer expected_value(input integer ch,yy,xx);
        longint signed acc,mag,divisor,q,remn;
        integer addr;
        acc=0;
        for(integer idx=0;idx<k;idx++) begin
            addr=is_fc ? src+idx : src+(idx/9)*h*w+(yy+(idx%9)/3)*w+xx+idx%3;
            acc+=(longint'(reference_mem[addr])-128)*longint'(weight_value(ch,idx));
        end
        divisor=64'sd1<<shift_value(layer,ch);
        mag=acc<0 ? -acc : acc; q=mag/divisor;remn=mag%divisor;
        if(remn*2>divisor || (remn*2==divisor && q%2!=0)) q++;
        if(acc<0) q=-q;
        q+=128;
        if(q<0) q=0;
        if(q>255) q=255;
        if(relu_on && q<128) q=128;
        return int'(q);
    endfunction

    always @(negedge clk) begin
        if(checking) begin
            pause_results=(cycles%7==0);
            if(results==co*ow*oh-1 && pe_out_valid && final_pause<13) begin
                pause_results=1;final_pause++;
            end
        end else pause_results=0;
    end
    always @(posedge clk) begin : scoreboard
        integer expected_addr,px,py,ch;
        cycles++;
        if(cycles>2000000) $fatal(1,"Watchdog");
        if(rst || !checking) held=0;
        else begin
            if(held && (!pe_out_valid || {writer_y,writer_x,pe_out_channel_id,
                pe_out_group_last,pe_out_error,result_data}!==held_payload))
                $fatal(1,"Result/tag/patch changed under stall");
            held=pe_out_valid && !pe_out_ready;
            held_payload={writer_y,writer_x,pe_out_channel_id,pe_out_group_last,pe_out_error,result_data};
            if(held) stalls++;
            if(cmd_ready) $fatal(1,"Layer accepted another command while active");
            if(writer_cmd_valid && writer_cmd_ready) writer_commands++;
            if(pe_compute_valid && pe_compute_ready) begin
                if(int'(writer_x)!=patches%ow || int'(writer_y)!=patches/ow)
                    $fatal(1,"Patch scan mismatch");
                patches++;
            end
            if(reader_cmd_valid && reader_cmd_ready) begin
                if(!(pe_replay_valid && pe_replay_ready)) $fatal(1,"Non-atomic replay");
                if(int'(pe_replay_k)!=k || int'(pe_replay_channel_base)!=(replays%((co+11)/12))*12)
                    $fatal(1,"Replay descriptor mismatch");
                replay_px=(replays/((co+11)/12))%ow;
                replay_py=(replays/((co+11)/12))/ow;
                if(int'(reader_x)!=replay_px || int'(reader_y)!=replay_py) $fatal(1,"Replay patch mismatch");
                replay_position=0;replays++;
            end
            if(ram_rd_en) begin
                expected_addr=is_fc ? src+replay_position : src+(replay_position/9)*h*w+
                    (replay_py+(replay_position%9)/3)*w+replay_px+replay_position%3;
                if(int'(ram_rd_addr)!=expected_addr || replay_position>=k)
                    $fatal(1,"Reader address mismatch actual=%0d expected=%0d",ram_rd_addr,expected_addr);
                replay_position++;reads++;
            end
            if(pe_out_valid && pe_out_ready) begin
                if(int'(writer_x)!=expected_x || int'(writer_y)!=expected_y ||
                   int'(pe_out_channel_id)!=expected_channel ||
                   int'(result_data)!=expected_value(expected_channel,expected_y,expected_x))
                    $fatal(1,"PE result mismatch c/y/x=%0d/%0d/%0d data=%0d expected=%0d",
                        expected_channel,expected_y,expected_x,result_data,expected_value(expected_channel,expected_y,expected_x));
                results++;
                if(expected_channel==co-1) begin
                    expected_channel=0;
                    if(expected_x==ow-1) begin expected_x=0;expected_y++;end
                    else expected_x++;
                end else expected_channel++;
            end
            if(ram_wr_en) begin
                ch=writes%co;px=(writes/co)%ow;py=(writes/co)/ow;
                expected_addr=dst+ch*oh*ow+py*ow+px;
                if(int'(ram_wr_addr)!=expected_addr || int'(ram_wr_data)!=expected_value(ch,py,px))
                    $fatal(1,"RAM commit mismatch address=%0d expected=%0d",ram_wr_addr,expected_addr);
                // This entry is OUTPUT only. Source bytes stay independent.
                reference_mem[expected_addr]=8'(expected_value(ch,py,px));writes++;
            end
            if(done && writes!=co*ow*oh) $fatal(1,"Early layer done");
        end
    end

    task automatic reset_all;
        @(negedge clk);checking=0;cmd_valid=0;rst=1;resident_valid=0;
        inject_replay_error=0;inject_result_error=0;
        repeat(3) @(negedge clk);
        rst=0;
        @(negedge clk);
        if(busy || fault || !cmd_ready) $fatal(1,"Reset failed");
    endtask
    task automatic load_weights;
        @(negedge clk);load_valid=1;load_k=8'(k);load_channels=6'(co);resident_valid=0;
        do @(posedge clk); while(!load_ready);
        @(negedge clk);load_valid=0;
        for(integer ch=0;ch<co;ch++) for(integer idx=0;idx<k;idx++) begin
            weight_valid=1;weight_i8=8'(weight_value(ch,idx));
            do @(posedge clk); while(!weight_ready);
            @(negedge clk);weight_valid=0;
            if(idx%5==0) @(negedge clk);
        end
        while(!load_done) @(negedge clk);
        if(load_error || !layer_ready) $fatal(1,"Real weight load failed");
        resident_valid=1;resident_layer_id=3'(layer);resident_k=8'(k);resident_channels=6'(co);
        @(negedge clk);
    endtask
    task automatic initialize_memory;
        host_access=1;
        for(integer addr=0;addr<32768;addr++) begin
            reference_mem[addr]=8'ha5;
            if(addr>=src && addr<src+(is_fc?k:ci*h*w))
                reference_mem[addr]=8'((addr-src)*43+((addr-src)/7)*19+17);
            @(negedge clk);host_wr=1;host_addr=15'(addr);host_data=reference_mem[addr];
        end
        @(negedge clk);host_wr=0;host_access=0;
    endtask
    task automatic readback;
        @(negedge clk);host_access=1;
        for(integer addr=0;addr<32768;addr++) begin
            @(negedge clk);host_rd=1;host_addr=15'(addr);
            @(posedge clk);#1;
            if(!ram_rd_valid || ram_rd_data!==reference_mem[addr])
                $fatal(1,"Readback address=%0d actual=%0d expected=%0d",addr,ram_rd_data,reference_mem[addr]);
            checks++;
        end
        @(negedge clk);host_rd=0;
        repeat(2) @(negedge clk);host_access=0;
    endtask
    task automatic set_command;
        cmd_is_fc=is_fc;cmd_layer_id=3'(layer);cmd_relu_enable=relu_on;
        cmd_src_base=15'(src);cmd_dst_base=15'(dst);
        cmd_width=8'(w);cmd_height=8'(h);cmd_input_channels=6'(ci);
        cmd_output_channels=6'(co);cmd_vector_length=8'(k);
    endtask
    task automatic launch;
        @(negedge clk);set_command();cmd_valid=1;
        if(!cmd_ready) $fatal(1,"Not ready to start");
        @(negedge clk);cmd_valid=0;
        // Prove all job fields were captured, not used live.
        cmd_src_base=32767;cmd_dst_base=32767;cmd_width=0;cmd_height=0;
        cmd_output_channels=0;cmd_input_channels=0;cmd_layer_id=7;
    endtask
    task automatic run_case(input bit fc,input integer l,ww,hh,ic,oc,kk,b,d,input bit relu_setting);
        is_fc=fc;layer=l;w=ww;h=hh;ci=ic;co=oc;k=kk;src=b;dst=d;relu_on=relu_setting;
        ow=fc?1:w-2;oh=fc?1:h-2;
        load_weights();initialize_memory();
        patches=0;replays=0;reads=0;results=0;writes=0;writer_commands=0;
        expected_x=0;expected_y=0;expected_channel=0;final_pause=0;
        launch();checking=1;
        while(!done && !error) @(negedge clk);
        checking=0;
        if(error || fault || writes!=co*ow*oh || results!=writes || patches!=ow*oh ||
           replays!=patches*((co+11)/12) || reads!=replays*k || writer_commands!=1 || final_pause!=13)
            $fatal(1,"Layer coverage/completion failed");
        $display("PASS layer fc=%0d C/H/W=%0d/%0d/%0d K=%0d patches=%0d replays=%0d reads=%0d writes=%0d",
                  fc,co,oh,ow,k,patches,replays,reads,writes);
        readback();successes++;
    endtask
    task automatic reject_command;
        @(negedge clk);cmd_valid=1;
        @(negedge clk);cmd_valid=0;
        while(!error && !done) begin
            if(writer_cmd_valid || reader_cmd_valid || pe_compute_valid || ram_wr_en || ram_rd_en)
                $fatal(1,"Rejected command touched endpoints");
            @(negedge clk);
        end
        if(!error || done || fault || busy) $fatal(1,"Bad config rejection");
        rejected++;@(negedge clk);
    endtask
    initial begin
        reset_all();
        run_case(0,0,5,4,2,12,18,100,500,1);
        run_case(0,0,3,3,1,1,9,32759,0,0);
        run_case(0,0,63,32,1,12,9,8064,10080,1);
        run_case(1,3,0,0,0,32,144,0,144,1);
        run_case(1,3,0,0,0,24,255,0,255,0);
        run_case(1,4,0,0,0,8,32,144,0,0);
        // Reject configuration before any Writer/PE/Reader side effect.
        set_command();cmd_vector_length=0;reject_command();
        set_command();cmd_output_channels=0;reject_command();
        set_command();cmd_output_channels=33;reject_command();
        set_command();cmd_dst_base=145;reject_command();
        set_command();cmd_src_base=32760;reject_command();
        set_command();cmd_dst_base=32767;reject_command();
        set_command();cmd_layer_id=7;reject_command();
        set_command();resident_valid=0;reject_command();resident_valid=1;
        set_command();resident_k=31;reject_command();resident_k=32;
        set_command();resident_layer_id=3;reject_command();resident_layer_id=4;
        set_command();cmd_is_fc=0;cmd_width=2;cmd_height=3;cmd_input_channels=1;reject_command();
        set_command();cmd_layer_id=3;cmd_vector_length=255;cmd_output_channels=32;
        cmd_src_base=0;cmd_dst_base=1000;
        resident_layer_id=3;resident_k=255;resident_channels=32;reject_command();
        // Fault injection at public protocol boundaries, not fake arithmetic.
        reset_all();load_weights();
        inject_replay_error=1;launch();
        while(!error) @(negedge clk);
        if(!fault || !busy || cmd_ready) $fatal(1,"Replay mismatch not latched as FAULT");
        repeat(3) @(negedge clk);
        if(error) $fatal(1,"Fault error should be one pulse");
        fault_cases++;
        reset_all();load_weights();launch();
        while(!pe_out_valid) @(negedge clk);
        inject_result_error=1;
        @(negedge clk);
        if(!fault || !error || writer_in_valid) $fatal(1,"Bad output not rejected");
        fault_cases++;
        reset_all();load_weights();launch();
        while(!reader_out_valid) @(negedge clk);
        reset_all(); // Cancel in-flight RAM/PE operation together.
        run_case(1,4,0,0,0,8,32,144,0,0);
        if(successes!=7 || rejected!=12 || fault_cases!=2 || checks!=229376 || stalls==0)
            $fatal(1,"Coverage missing");
        $display("PASS pe_layer_controller PIPE=%0d layers=%0d rejects=%0d faults=%0d RAM_checks=%0d stalls=%0d",
                 RESULT_PIPELINED,successes,rejected,fault_cases,checks,stalls);
        $finish;
    end
endmodule
