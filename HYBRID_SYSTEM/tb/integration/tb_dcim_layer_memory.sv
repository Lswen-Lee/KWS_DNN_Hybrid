`timescale 1ns/1ps
// Real S5-C endpoints. Host writes input/weights through ports only.
// Golden arrays never drive compute results or initialize internal cells.
module tb_dcim_layer_memory;
    import kws_system_pkg::*;
    parameter bit POSTPROCESS_PIPELINED=0;
    logic clk=0, clk_cim=0, reset_request=1;
    always #4 clk=~clk;
    integer phase_ps=2700;
    initial begin
        if($value$plusargs("PHASE_PS=%d",phase_ps)) begin end
        #(phase_ps * 1ps);
        forever #9434ps clk_cim=~clk_cim;
    end
    logic [1:0] sys_reset=3, cim_reset=3;
    always @(posedge clk or posedge reset_request)
        if(reset_request) sys_reset<=3; else sys_reset<={sys_reset[0],1'b0};
    always @(posedge clk_cim or posedge reset_request)
        if(reset_request) cim_reset<=3; else cim_reset<={cim_reset[0],1'b0};
    wire rst=sys_reset[1], rst_cim=cim_reset[1];

    logic cmd_valid=0, cmd_ready, cmd_relu_enable=1;
    logic [2:0] cmd_layer_id=1, resident_layer_id=0;
    logic [14:0] cmd_src_base=0, cmd_dst_base=0;
    logic [7:0] cmd_width=3,cmd_height=3;
    logic resident_valid=0,busy,done,error,fault;
    logic reader_cmd_valid,reader_cmd_ready,reader_done,reader_error;
    logic [14:0] reader_base;
    logic [7:0] reader_width,reader_height,reader_x,reader_y;
    logic reader_out_valid,reader_out_last,reader_out_ready;
    logic dcim_activation_valid,dcim_activation_ready;
    logic dcim_patch_valid,dcim_patch_ready,dcim_patch_done,dcim_error;
    logic raw_path_enable,dcim_source_error;
    wire postprocess_empty;
    logic [2:0] post_layer_id;
    logic post_relu_enable,post_valid,post_last,post_error,post_ready;
    logic [4:0] post_channel;
    logic writer_cmd_valid,writer_cmd_ready,writer_in_ready,writer_done,writer_error;
    logic [14:0] writer_base;
    logic [7:0] writer_width,writer_height,writer_x,writer_y;
    logic [5:0] writer_channel;
    logic writer_in_valid;
    dcim_layer_controller control (.*);

    logic run_owner=0,host_we=0,host_re=0;
    logic [14:0] host_addr=0;
    logic [7:0] host_data=0;
    wire rr_en,mem_valid,ww_en;
    wire [14:0] rr_addr,ww_addr;
    wire [7:0] mem_data,reader_data,ww_data,post_data;
    wire reader_busy,writer_busy,writer_ready_actual;
    integer cycles=0;
    // Change stimulus away from the sampling edge; do not race DUT handshakes.
    always @(negedge clk) cycles <= cycles+1;
    // Periodic sink stalls; FIFO-full coverage belongs to its unit test.
    wire allow_sink=(cycles%173)>=45;
    assign writer_in_ready=writer_ready_actual && allow_sink;
    activation_buffer memory (
        .clk(clk),.rst(rst),.wr_en(run_owner ? ww_en : host_we),
        .wr_addr(run_owner ? ww_addr : host_addr),.wr_data(run_owner ? ww_data : host_data),
        .rd_en(run_owner ? rr_en : host_re),.rd_addr(run_owner ? rr_addr : host_addr),
        .rd_valid(mem_valid),.rd_data(mem_data)
    );
    activation_reader reader (
        .clk(clk),.rst(rst),.cmd_valid(reader_cmd_valid),.cmd_ready(reader_cmd_ready),
        .cmd_mode(READ_PATCH),.cmd_base(reader_base),.cmd_count(16'd108),
        .cmd_width(reader_width),.cmd_height(reader_height),.cmd_channels(6'd12),
        .cmd_x(reader_x),.cmd_y(reader_y),.ram_rd_en(rr_en),.ram_rd_addr(rr_addr),
        .ram_rd_valid(mem_valid && run_owner),.ram_rd_data(mem_data),
        .out_valid(reader_out_valid),.out_ready(reader_out_ready),.out_data(reader_data),
        .out_last(reader_out_last),.busy(reader_busy),.done(reader_done),.error(reader_error)
    );
    feature_map_writer writer (
        .clk(clk),.rst(rst),.cmd_valid(writer_cmd_valid),.cmd_ready(writer_cmd_ready),
        .cmd_mode(WRITE_CHW),.cmd_base(writer_base),.cmd_width(writer_width),
        .cmd_height(writer_height),.cmd_channels(6'd12),.cmd_count(16'd0),
        .in_valid(writer_in_valid && allow_sink),.in_ready(writer_ready_actual),.in_data(post_data),
        .in_channel(writer_channel),.in_y(writer_y),.in_x(writer_x),
        .wr_en(ww_en),.wr_addr(ww_addr),.wr_data(ww_data),.busy(writer_busy),
        .done(writer_done),.error(writer_error)
    );
    logic load_valid=0,load_ready,load_done,weight_valid=0,weight_ready;
    logic signed [7:0] weight_data=0;
    wire result_valid,result_ready,result_last,dcim_busy,weights_ready;
    wire [3:0] filter_id;
    wire signed [31:0] result_data;
    kws_dcim_subsystem dcim (
        .clk_sys(clk),.rst_sys(rst),.clk_cim(clk_cim),.rst_cim(rst_cim),
        .load_valid(load_valid),.load_ready(load_ready),.load_done(load_done),
        .weight_valid(weight_valid),.weight_ready(weight_ready),.weight_data(weight_data),
        .patch_valid(dcim_patch_valid),.patch_ready(dcim_patch_ready),.patch_done(dcim_patch_done),
        .activation_valid(dcim_activation_valid),.activation_ready(dcim_activation_ready),
        .activation_data(reader_data),.result_valid(result_valid),.result_ready(result_ready),
        .filter_id(filter_id),.result_data(result_data),.result_last(result_last),
        .busy(dcim_busy),.weights_ready(weights_ready),.error(dcim_error),.source_error(dcim_source_error)
    );
    wire pot_ready;
    assign result_ready=pot_ready && raw_path_enable;
    pot_result_stream #(.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) post (
        .clk(clk),.rst(rst),.in_valid(result_valid && raw_path_enable),.in_ready(pot_ready),
        .accumulator(result_data),.layer_id(post_layer_id),.channel_id({1'b0,filter_id}),
        .in_last(result_last),.in_error(1'b0),.relu_enable(post_relu_enable),
        .out_valid(post_valid),.out_ready(post_ready),.output_uint8(post_data),
        .out_channel_id(post_channel),.out_last(post_last),.out_error(post_error),.empty(postprocess_empty)
    );

    logic [7:0] input_bytes[0:5399],golden[0:4367],weights[0:1295],shifts[0:11];
    logic signed [31:0] golden_acc[0:4367];
    logic [7:0] expected_ram[0:32767];
    string vectors;
    integer iw,ih,ow,oh,src,dst,layer,total_patches;
    integer reads=0,acts=0,raws=0,posts=0,commits=0,patches=0,wcommands=0;
    integer cases=0,ram_checks=0,total_raw=0,total_commits=0;
    bit checking=0;
    function automatic integer input_address(input integer n);
        integer p,k,d,u,v;
        p=n/108;k=n%108;d=k/9;u=(k%9)/3;v=k%3;
        return src+d*iw*ih+(p/ow+u)*iw+p%ow+v;
    endfunction
    function automatic integer output_index(input integer n);
        return (n%12)*ow*oh+n/12;
    endfunction
    function automatic integer reference_mac(input integer p,c);
        integer acc;
        acc=0;
        for(integer k=0;k<108;k++)
            acc+=(int'(input_bytes[input_address(p*108+k)-src])-128)*int'($signed(weights[c*108+k]));
        return acc;
    endfunction
    function automatic integer reference_quant(input integer acc,shift);
        integer mag,q,remn,divisor,z;
        mag=acc<0 ? -acc : acc;divisor=1<<shift;q=mag/divisor;remn=mag%divisor;
        if(2*remn>divisor || (2*remn==divisor && (q%2)!=0)) q++;
        z=(acc<0 ? -q : q)+128;
        if(z<128) z=128; // ReLU enabled in these cases.
        if(z>255) z=255;
        return z;
    endfunction
    always @(posedge clk) begin : scoreboards
        integer idx,p,c;
        if(!rst && checking) begin
            if(error || fault || dcim_error) $fatal(1,"unexpected endpoint error");
            if(reader_cmd_valid && reader_cmd_ready) begin
                if(int'(reader_x)!=patches%ow || int'(reader_y)!=patches/ow)
                    $fatal(1,"patch coordinate mismatch");
                patches++;
            end
            if(writer_cmd_valid && writer_cmd_ready) wcommands++;
            if(rr_en) begin
                if(reads>=total_patches*108 || int'(rr_addr)!=input_address(reads)) $fatal(1,"read address mismatch");
                reads++;
            end
            if(dcim_activation_valid && dcim_activation_ready) begin
                if(acts>=total_patches*108 || reader_data!==input_bytes[input_address(acts)-src] ||
                   reader_out_last!=(acts%108==107)) $fatal(1,"activation data/last mismatch");
                acts++;
            end
            if(result_valid && result_ready) begin
                idx=output_index(raws);p=raws/12;c=raws%12;
                if(raws>=total_patches*12 || int'(filter_id)!=c || result_last!=(c==11) ||
                   result_data!==golden_acc[idx] || int'(result_data)!=reference_mac(p,c))
                    $fatal(1,"raw INT32 mismatch n=%0d got=%0d expected=%0d",raws,result_data,golden_acc[idx]);
                raws++;
            end
            if(post_valid && post_ready) begin
                idx=output_index(posts);
                if(posts>=total_patches*12 || post_data!==golden[idx] || int'(post_channel)!=posts%12 ||
                   post_last!=(posts%12==11) || post_error) $fatal(1,"post UINT8 mismatch n=%0d",posts);
                posts++;
            end
            if(ww_en) begin
                idx=output_index(commits);
                if(commits>=total_patches*12 || int'(ww_addr)!=dst+idx || ww_data!==golden[idx])
                    $fatal(1,"commit mismatch n=%0d addr=%0d expected_addr=%0d data=%0d expected_data=%0d",commits,ww_addr,dst+idx,ww_data,golden[idx]);
                commits++;
            end
            if(done && (commits!=total_patches*12 || raws!=commits || posts!=commits ||
                        reads!=total_patches*108 || acts!=reads || patches!=total_patches || wcommands!=1))
                $fatal(1,"early done or transaction count mismatch");
        end
    end
    task automatic reset_all;
        @(negedge clk);reset_request=1;cmd_valid=0;load_valid=0;weight_valid=0;
        host_we=0;host_re=0;run_owner=0;checking=0;resident_valid=0;
        repeat(5) @(negedge clk);
        reset_request=0;wait(!rst && !rst_cim);@(negedge clk);
    endtask
    task automatic host_write(input integer address,input logic [7:0] data);
        host_we=1;host_addr=15'(address);host_data=data;@(negedge clk);host_we=0;
    endtask
    task automatic prepare(input integer kind);
        string name;
        layer=(kind==2) ? 2 : 1;
        iw=(kind==0) ? 3 : (kind==1) ? 5 : (kind==2) ? 14 : 30;
        ih=(kind==0) ? 3 : (kind==1) ? 4 : (kind==2) ? 6 : 15;
        ow=iw-2;oh=ih-2;src=0;dst=iw*ih*12;total_patches=ow*oh;
        name=layer==1 ? "conv2" : "conv3";
        $readmemh({vectors,"/",name,"_weights.mem"},weights);
        $readmemh({vectors,"/",name,"_shift.mem"},shifts);
        if(kind<2) begin
            for(integer i=0;i<iw*ih*12;i++) input_bytes[i]=8'((i*37+11)%256);
            for(integer p=0;p<total_patches;p++) for(integer c=0;c<12;c++) begin
                golden_acc[c*total_patches+p]=reference_mac(p,c);
                golden[c*total_patches+p]=8'(reference_quant(reference_mac(p,c),int'(shifts[c])));
            end
        end else begin
            if(kind==2) $readmemh({vectors,"/pool3.mem"},input_bytes,0,1007);
            else $readmemh({vectors,"/pool2.mem"},input_bytes,0,5399);
            $readmemh({vectors,"/",name,"_acc.mem"},golden_acc,0,total_patches*12-1);
            name=layer==1 ? "relu2" : "relu3";
            $readmemh({vectors,"/",name,".mem"},golden,0,total_patches*12-1);
        end
        if($test$plusargs("CORRUPT_GOLDEN")) golden[0]^=8'd1;
        for(integer i=0;i<32768;i++) begin
            expected_ram[i]=8'hA6;host_write(i,8'hA6);
        end
        for(integer i=0;i<iw*ih*12;i++) begin expected_ram[src+i]=input_bytes[i];host_write(src+i,input_bytes[i]); end
        for(integer i=0;i<total_patches*12;i++) expected_ram[dst+i]=golden[i];
    endtask
    task automatic load_weights;
        load_valid=1;while(!load_ready) @(negedge clk);
        @(negedge clk);load_valid=0;
        for(integer i=0;i<1296;i++) begin
            weight_data=$signed(weights[i]);weight_valid=1;
            do @(posedge clk); while(!weight_ready);
            @(negedge clk);weight_valid=0;
            if(i%19==0) repeat(2) @(negedge clk);
        end
        while(!load_done) @(negedge clk);
        if(!weights_ready || dcim_error) $fatal(1,"weight load failed");
        resident_layer_id=3'(layer);resident_valid=1;
    endtask
    task automatic run_layer;
        integer start_cycles;
        reads=0;acts=0;raws=0;posts=0;commits=0;patches=0;wcommands=0;
        run_owner=1;checking=1;start_cycles=cycles;
        cmd_width=8'(iw);cmd_height=8'(ih);cmd_src_base=15'(src);cmd_dst_base=15'(dst);
        cmd_layer_id=3'(layer);cmd_valid=1;
        do @(posedge clk); while(!cmd_ready);
        @(negedge clk);cmd_valid=0;
        while(!done) @(negedge clk);
        @(negedge clk); // monitor observes registered done before disabling checks
        checking=0;run_owner=0;
        if(busy || writer_busy || reader_busy || post_valid) $fatal(1,"not drained");
        total_raw+=raws;total_commits+=commits;
        for(integer i=0;i<32768;i++) begin
            host_re=1;host_addr=15'(i);@(negedge clk);
            if(!mem_valid || mem_data!==expected_ram[i]) $fatal(1,"readback mismatch addr=%0d",i);
            ram_checks++;
        end
        host_re=0;@(negedge clk);
        cases++;
        $display("PASS real layer=%0d W=%0d H=%0d patches=%0d raw=%0d commits=%0d cycles=%0d",
                 layer,iw,ih,patches,raws,commits,cycles-start_cycles);
    endtask
    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"VECTORS required");
        for(integer kind=0;kind<4;kind++) begin
            reset_all();prepare(kind);load_weights();run_layer();
            if($test$plusargs("SMOKE_ONLY") && kind==0) break;
        end
        $display("PASS S5-C REAL pipe=%0d cases=%0d raw=%0d commits=%0d ram_checks=%0d",
                 POSTPROCESS_PIPELINED,cases,total_raw,total_commits,ram_checks);
        $finish;
    end
    initial begin #100000000; $fatal(1,"real integration watchdog"); end
endmodule
