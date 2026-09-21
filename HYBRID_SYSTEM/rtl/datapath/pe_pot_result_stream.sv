`timescale 1ns/1ps
// Raw PE result -> model ROM -> PoT requant -> optional ReLU -> elastic FIFO.
// Reserve a FIFO slot at INPUT acceptance, including all in-flight pipeline data.
// Capacity 8; ready never depends on downstream ready. No dropped results on stalls.
module pe_pot_result_stream (
    input logic clk, rst,
    input logic in_valid, output wire in_ready,
    input logic signed [31:0] accumulator,
    input logic [2:0] layer_id,
    input logic [4:0] channel_id,
    input logic in_last, in_error, relu_enable,
    output wire out_valid, input logic out_ready,
    output wire [7:0] output_uint8,
    output wire [4:0] out_channel_id,
    output wire out_last, out_error
);
    wire [4:0] shift_amount;
    wire shift_valid;
    kws_pot_shift_rom rom (.layer_id(layer_id), .channel_id(channel_id),
        .shift_amount(shift_amount), .valid(shift_valid));
    logic [3:0] reserved, count;
    logic [2:0] wr_ptr, rd_ptr;
    logic [14:0] fifo [0:7];
    logic [7:0] tag [0:2]; // error, relu, last, channel
    wire accept = in_valid && in_ready;
    wire pop = out_valid && out_ready;
    wire q_valid;
    wire [7:0] q_data;
    wire [7:0] clamped = tag[2][6] && q_data<128 ? 8'd128 : q_data;
    assign in_ready = !rst && reserved<8;
    assign out_valid = !rst && count!=0;
    assign {out_error,out_last,out_channel_id,output_uint8}=fifo[rd_ptr];
    requantizer_int32_to_uint8_pot quantizer (
        .clk(clk),.rst(rst),.in_valid(accept),.accumulator(accumulator),
        .shift_amount(shift_amount),.out_valid(q_valid),.output_uint8(q_data)
    );
    always_ff @(posedge clk) begin
        if(rst) begin
            reserved<=0; count<=0; wr_ptr<=0; rd_ptr<=0;
            tag[0]<=0; tag[1]<=0; tag[2]<=0;
        end else begin
            tag[0]<={in_error || !shift_valid,relu_enable,in_last,channel_id};
            tag[1]<=tag[0]; tag[2]<=tag[1];
            case({accept,pop})
                2'b10: reserved<=reserved+1'b1;
                2'b01: reserved<=reserved-1'b1;
                default: ;
            endcase
            case({q_valid,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: ;
            endcase
            if(q_valid) begin
                fifo[wr_ptr]<={tag[2][7],tag[2][5:0],clamped};
                wr_ptr<=wr_ptr+1'b1;
            end
            if(pop) rd_ptr<=rd_ptr+1'b1;
        end
    end
endmodule
