`timescale 1ns/1ps
module tb_layer_descriptor_rom;
    import kws_system_pkg::*;
    logic [3:0] op_index;
    layer_descriptor_t descriptor;
    logic descriptor_valid;
    integer checks=0;
    layer_descriptor_rom dut (.*);
    // Independent readable expected table; every field and address is checked.
    task automatic check_row(input integer idx,kind,backend,id,src,dst,w,h,ci,co,k,r);
        op_index=4'(idx); #1;
        if(!descriptor_valid || int'(descriptor.op_kind)!=kind || int'(descriptor.backend)!=backend ||
           int'(descriptor.layer_id)!=id || int'(descriptor.src_base)!=src || int'(descriptor.dst_base)!=dst ||
           int'(descriptor.input_width)!=w || int'(descriptor.input_height)!=h ||
           int'(descriptor.input_channels)!=ci || int'(descriptor.output_channels)!=co ||
           int'(descriptor.k)!=k || int'(descriptor.relu_enable)!=r) $fatal(1,"Descriptor row %0d",idx);
        checks++;
    endtask
    initial begin
        check_row(0,0,0,0,0,8064,126,64,1,1,0,0);
        check_row(1,1,1,0,8064,10080,63,32,1,12,9,1);
        check_row(2,0,0,0,10080,0,61,30,12,12,0,0);
        check_row(3,1,2,1,0,5400,30,15,12,12,108,1);
        check_row(4,0,0,0,5400,0,28,13,12,12,0,0);
        check_row(5,1,2,2,0,1008,14,6,12,12,108,1);
        check_row(6,0,0,0,1008,0,12,4,12,12,0,0);
        check_row(7,2,1,3,0,144,0,0,0,32,144,1);
        check_row(8,2,1,4,144,0,0,0,0,8,32,0);
        for(integer i=9;i<16;i++) begin
            op_index=4'(i); #1;
            if(descriptor_valid || descriptor!=='0) $fatal(1,"Invalid address %0d",i);
            checks++;
        end
        $display("PASS descriptor ROM checks=%0d",checks); $finish;
    end
endmodule
