`timescale 1ns/1ps
module tb_pe8_multiplier_s8xs8;
    logic signed [7:0] activation_s8, weight_i8;
    logic signed [15:0] product;
    integer a,w,expected;
    pe8_multiplier_s8xs8 dut (.*);
    initial begin
        $display("TEST: exhaustive signed8 x signed8, including -128 x -128");
        for(a=-128;a<128;a=a+1)
            for(w=-128;w<128;w=w+1) begin
                activation_s8=8'(a);
                weight_i8=8'(w);
                expected=a*w;
                #1;
                if(int'(product)!=expected)
                    $fatal(1,"A=%0d W=%0d actual=%0d expected=%0d",a,w,product,expected);
            end
        $display("PASS multiplier: 65536 cases");
        $finish;
    end
endmodule

