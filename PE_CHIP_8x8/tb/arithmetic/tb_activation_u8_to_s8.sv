`timescale 1ns/1ps
module tb_activation_u8_to_s8;
    logic [7:0] activation_u8;
    logic signed [7:0] activation_s8;
    integer a;
    activation_u8_to_s8 dut (.*);
    initial begin
        $display("TEST: all 256 UINT8 codes -> signed A-128");
        for (a=0; a<256; a=a+1) begin
            activation_u8=8'(a);
            #1;
            if (int'(activation_s8) != a-128)
                $fatal(1,"A=%0d actual=%0d expected=%0d",a,activation_s8,a-128);
        end
        $display("PASS activation: 256 cases");
        $finish;
    end
endmodule

