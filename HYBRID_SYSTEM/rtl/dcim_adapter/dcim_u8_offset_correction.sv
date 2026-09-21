`timescale 1ns/1ps
// Boundary adapter ONLY: assumes DCIM weights encoded Wu=Ws+128 (not reinterpret).
// ACC = sum(Au*Wu)-128*sum(Au)-128*sum(Wu)+16384*K = sum((Au-128)*Ws).
// Inputs cover a complete tile/group for ONE output and must share the same K.
// One registered stage, II=1, no ready. Invalid INT32 result saturates and flags.
module dcim_u8_offset_correction (
    input logic clk, rst, in_valid,
    input logic [31:0] unsigned_mac, activation_sum, offset_weight_sum,
    input logic [15:0] term_count,
    output logic out_valid,
    output logic signed [31:0] accumulator,
    output logic overflow
);
    logic signed [47:0] value;
    always_comb value=$signed({16'd0,unsigned_mac})
        - ($signed({16'd0,activation_sum}) <<< 7)
        - ($signed({16'd0,offset_weight_sum}) <<< 7)
        + ($signed({32'd0,term_count}) <<< 14);
    always_ff @(posedge clk) begin
        if(rst) begin out_valid<=0; accumulator<=0; overflow<=0; end
        else begin
            out_valid<=in_valid;
            if(in_valid) begin
                overflow<=value>48'sd2147483647 || value< -48'sd2147483648;
                if(value>48'sd2147483647) accumulator<=32'sh7fffffff;
                else if(value< -48'sd2147483648) accumulator<=32'sh80000000;
                else accumulator<=value[31:0];
            end
        end
    end
endmodule
