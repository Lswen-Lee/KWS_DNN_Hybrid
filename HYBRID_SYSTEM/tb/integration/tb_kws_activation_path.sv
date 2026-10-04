`timescale 1ns/1ps
module tb_kws_activation_path;
    import kws_system_pkg::*;
    logic clk=0;
    always #5 clk=~clk;
    logic rst=1;
    logic load_valid=0, load_ready, load_data_valid=0, load_data_ready;
    activation_write_mode_t load_mode=WRITE_LINEAR;
    logic [14:0] load_base=0;
    logic [15:0] load_count=0;
    logic [7:0] load_width=0, load_height=0, load_data=0, load_x=0, load_y=0;
    logic [5:0] load_channels=0, load_channel=0;
    logic load_done,load_error;
    logic read_valid=0,read_ready,read_out_valid,read_out_ready=0,read_last,read_done,read_error;
    logic [14:0] read_base=0;
    logic [15:0] read_count=0;
    logic [7:0] read_data;
    logic pool_valid=0,pool_ready,pool_done,pool_error,fault,busy;
    logic [14:0] pool_src_base=0,pool_dst_base=0;
    logic [7:0] pool_width=0,pool_height=0;
    logic [5:0] pool_channels=0;
    logic [7:0] golden [0:32767];
    integer pool_reads=0,pool_writes=0,starts=0,checks=0,cases=0,rejections=0;
    integer expected_in=0,expected_out=0,src=0,dst=0;
    bit checking=0;
    integer early_writer_events=0;
    logic [31:0] rng=32'h5052026;
    kws_activation_path dut (.*);
    string software_root;

    // Software exports are the reference, not an RTL-derived pooling formula.
    task automatic read_export(input string filename, input integer base_addr, count);
        integer fd, status;
        string token;
        logic [7:0] value;
        fd=$fopen(filename,"r");
        if(fd==0) $fatal(1,"Cannot open software export: %s",filename);
        for(integer i=0;i<count;i++) begin
            status=$fscanf(fd,"%s",token);
            if(status!=1 || token.len()!=8) $fatal(1,"Invalid export %s index=%0d",filename,i);
            value=0;
            for(integer bit_index=0;bit_index<8;bit_index++) begin
                if(token[bit_index]!=8'h30 && token[bit_index]!=8'h31)
                    $fatal(1,"Non-binary export %s index=%0d",filename,i);
                value={value[6:0],(token[bit_index]==8'h31)};
            end
            golden[base_addr+i]=value;
        end
        status=$fscanf(fd,"%s",token);
        if(status==1) $fatal(1,"Extra data in %s",filename);
        $fclose(fd);
    endtask

    task automatic software_pool_case(input string input_layer, output_layer,
                                      input integer b,d,w,h,c);
        integer check_before;
        read_export({software_root,"/",input_layer,"/activation_uint8_binary.txt"},b,c*h*w);
        read_export({software_root,"/",output_layer,"/activation_uint8_binary.txt"},d,c*(h/2)*(w/2));
        // Exercise CHW addressing with channel-interleaved host writes.
        load_command(1,b,w,h,c,0);
        for(integer y=0;y<h;y++) for(integer x=0;x<w;x++) for(integer ch=0;ch<c;ch++)
            send(ch,y,x,golden[b+ch*h*w+y*w+x]);
        finish_load();
        src=b;dst=d;expected_in=c*h*w;expected_out=c*(h/2)*(w/2);
        pool_reads=0;pool_writes=0;starts=0;
        start_pool(b,d,w,h,c);checking=1;
        while(!pool_done && !pool_error) @(negedge clk);
        checking=0;
        if(pool_error || fault || pool_reads!=expected_in || pool_writes!=expected_out || starts!=1)
            $fatal(1,"Software pool completion mismatch: %s",output_layer);
        check_before=checks;
        @(negedge clk);scan();
        cases++;
        $display("PASS software %s -> %s input=%0d output=%0d RAM_checks=%0d",
                 input_layer,output_layer,expected_in,expected_out,checks-check_before);
    endtask

    function automatic [7:0] pattern(input integer c,y,x);
        return 8'((c*73+y*29+x*17) ^ (x>>2));
    endfunction

    // Observe real RAM transactions, not replacement/stub modules.
    always @(posedge clk) if(!rst && checking) begin
        if(dut.r_en) begin
            if(pool_reads>=expected_in || int'(dut.r_addr)!=src+pool_reads)
                $fatal(1,"Pool read address mismatch");
            pool_reads++;
        end
        if(dut.w_en) begin
            if(pool_writes>=expected_out || int'(dut.w_addr)!=dst+pool_writes ||
               dut.w_data!==golden[dst+pool_writes])
                $fatal(1,"Pool write mismatch index=%0d addr=%0d actual=%0d expected=%0d",
                       pool_writes,dut.w_addr,dut.w_data,golden[dst+pool_writes]);
            pool_writes++;
        end
        if(dut.frame_start) begin
            if(!dut.pixel_valid || !dut.w_ready) $fatal(1,"Incorrect first pixel/start");
            starts++;
        end
        if(dut.pooled_valid && !dut.w_ready) $fatal(1,"Pool output dropped");
        if(dut.wc_done && !dut.controller.reader_done_seen && !dut.rc_done)
            early_writer_events++;
        if(load_ready || read_ready) $fatal(1,"Host obtained busy RAM");
    end

    task automatic load_command(input bit chw,input integer b,w,h,c,n);
        if(b<0 || b>32767 || w<0 || w>255 || h<0 || h>255 || c<0 || c>63 || n<0 || n>65535)
            $fatal(1,"TB load port range");
        @(negedge clk);
        load_mode=chw?WRITE_CHW:WRITE_LINEAR; load_base=15'(b); load_count=16'(n);
        load_width=8'(w); load_height=8'(h); load_channels=6'(c); load_valid=1;
        if(!load_ready) $fatal(1,"load not ready");
        @(negedge clk); load_valid=0;
        while(!load_data_ready) @(negedge clk);
    endtask
    task automatic send(input integer c,y,x,input logic [7:0] d);
        if(c<0 || c>63 || y<0 || y>255 || x<0 || x>255) $fatal(1,"TB coordinate range");
        @(negedge clk);
        if(!load_data_ready) $fatal(1,"writer unexpectedly stalled");
        load_data_valid=1;load_channel=6'(c);load_y=8'(y);load_x=8'(x);load_data=d;
    endtask
    task automatic finish_load;
        @(negedge clk);load_data_valid=0;
        while(!load_done && !load_error) @(negedge clk);
        if(load_error) $fatal(1,"load error");
        @(negedge clk);
    endtask
    task automatic scan;
        integer index;
        logic held;
        logic [8:0] payload;
        @(negedge clk); read_base=0;read_count=32768;read_valid=1;
        #1; if(!read_ready) $fatal(1,"read not ready");
        @(negedge clk);read_valid=0;
        index=0;held=0;payload=0;
        while(!read_done) begin
            rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
            read_out_ready=rng[0];
            @(posedge clk);
            if(held && (!read_out_valid || {read_last,read_data}!==payload))
                $fatal(1,"host readback changed under stall");
            held=read_out_valid && !read_out_ready;payload={read_last,read_data};
            if(read_out_valid && read_out_ready) begin
                if(index>=32768 || read_data!==golden[index] || read_last!==(index==32767))
                    $fatal(1,"Memory/sentinel mismatch address=%0d",index);
                index++;checks++;
            end
            @(negedge clk);
        end
        if(index!=32768 || read_error) $fatal(1,"Incomplete readback");
        read_out_ready=0;
        @(negedge clk);
    endtask
    task automatic start_pool(input integer b,d,w,h,c);
        if(b<0 || b>32767 || d<0 || d>32767 || w<0 || w>255 || h<0 || h>255 || c<0 || c>63)
            $fatal(1,"TB pool port range");
        @(negedge clk);
        pool_src_base=15'(b);pool_dst_base=15'(d);pool_width=8'(w);pool_height=8'(h);pool_channels=6'(c);
        pool_valid=1;
        load_valid=1;read_valid=1;
        #1;
        if(!pool_ready) $fatal(1,"pool not ready");
        if(load_ready || read_ready) $fatal(1,"Pool priority not enforced");
        @(negedge clk);pool_valid=0;load_valid=0;read_valid=0;
        // Configuration must have been saved, including source/destination.
        pool_width=0;pool_height=0;pool_channels=0;pool_src_base=0;pool_dst_base=0;
    endtask
    task automatic pool_case(input integer b,d,w,h,c);
        integer out_index;
        integer early_before;
        logic [7:0] maximum;
        $display("POOL %0dx%0dx%0d source=%0d destination=%0d",c,h,w,b,d);
        load_command(1,b,w,h,c,0);
        for(integer y=0;y<h;y++) for(integer x=0;x<w;x++) for(integer ch=0;ch<c;ch++) begin
            send(ch,y,x,pattern(ch,y,x)); golden[b+ch*h*w+y*w+x]=pattern(ch,y,x);
        end
        finish_load();
        out_index=0;
        for(integer ch=0;ch<c;ch++) for(integer y=0;y<h/2;y++) for(integer x=0;x<w/2;x++) begin
            maximum=0;
            for(integer u=0;u<2;u++) for(integer v=0;v<2;v++)
                if(golden[b+ch*h*w+(2*y+u)*w+2*x+v]>maximum)
                    maximum=golden[b+ch*h*w+(2*y+u)*w+2*x+v];
            golden[d+out_index]=maximum;out_index++;
        end
        src=b;dst=d;expected_in=c*h*w;expected_out=out_index;
        pool_reads=0;pool_writes=0;starts=0;early_before=early_writer_events;
        start_pool(b,d,w,h,c);checking=1;
        while(!pool_done && !pool_error) @(negedge clk);
        checking=0;
        if(pool_error || fault || pool_reads!=expected_in || pool_writes!=expected_out || starts!=1)
            $fatal(1,"Pool completion/coverage mismatch");
        if(w==5 && h==3 && early_writer_events==early_before) $fatal(1,"Odd tail early-writer coverage missing");
        cases++; @(negedge clk); scan();
    endtask
    task automatic reject(input integer b,d,w,h,c);
        expected_in=0;expected_out=0;pool_reads=0;pool_writes=0;starts=0;
        start_pool(b,d,w,h,c);checking=1;
        while(!pool_error && !pool_done) @(negedge clk);
        checking=0;
        if(!pool_error || pool_done || fault || pool_reads!=0 || pool_writes!=0 || starts!=0)
            $fatal(1,"Illegal command not safely rejected");
        rejections++;@(negedge clk);
    endtask
    initial begin
        repeat(2) @(negedge clk);rst=0;
        load_command(0,0,0,0,0,32768);
        for(integer a=0;a<32768;a++) begin send(0,0,0,8'ha5);golden[a]=8'ha5;end
        finish_load();
        if($value$plusargs("SOFTWARE_ROOT=%s",software_root)) begin
            software_pool_case("quant_input","pool1",0,8064,126,64,1);
            software_pool_case("relu1","pool2",10080,0,61,30,12);
            software_pool_case("relu2","pool3",5400,0,28,13,12);
            software_pool_case("relu3","pool4",1008,0,12,4,12);
            if(cases!=4 || checks!=131072) $fatal(1,"Software coverage incomplete");
            $display("PASS software golden: 4 pools, 8568 outputs, 131072 RAM checks");
            $finish;
        end else begin
        pool_case(100,200,5,3,2);
        pool_case(0,8064,126,64,1);
        pool_case(10080,0,61,30,12);
        pool_case(5400,0,28,13,12);
        pool_case(1008,0,12,4,12);
        pool_case(32760,32764,2,2,1);
        pool_case(30000,30200,2,2,31);
        reject(0,1,5,3,1); reject(100,90,5,3,12);
        reject(32760,0,5,3,1);reject(0,32767,5,3,1);
        reject(0,1000,0,3,1);reject(0,1000,1,3,1);
        reject(0,1000,3,1,1);reject(0,1000,127,3,1);
        reject(0,1000,3,3,0);reject(0,1000,3,3,32);
        reject(0,1000,126,255,31);
        // Reset while real pipeline is active; then rerun with reloaded input.
        start_pool(100,200,5,3,2);
        while(!dut.pixel_valid) @(negedge clk);
        rst=1;repeat(2) @(negedge clk);rst=0;
        pool_case(100,200,5,3,2);
        // Deliberate fault injection only: never replace the normal datapath.
        start_pool(100,200,5,3,2);
        while(!dut.pooled_valid) @(negedge clk);
        force dut.controller.writer_in_ready=0;
        @(negedge clk);release dut.controller.writer_in_ready;
        repeat(3) @(negedge clk);
        if(!fault || !busy || pool_ready || load_ready || read_ready) $fatal(1,"FAULT not locked");
        rst=1;repeat(2) @(negedge clk);rst=0;
        pool_case(100,200,5,3,2);
        if(cases!=9 || rejections!=11 || checks!=294912) $fatal(1,"Coverage missing");
        $display("PASS activation_path pool_cases=%0d rejected=%0d memory_checks=%0d",cases,rejections,checks);
        $finish;
        end
    end
    initial begin #20000000;$fatal(1,"Watchdog timeout");end
endmodule
