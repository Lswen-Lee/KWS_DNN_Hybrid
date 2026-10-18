`timescale 1ns/1ps
// 16KiB physical image: 15628 useful bytes followed by zero padding.
// Synchronous read; no reset on data/array so block-ROM inference is possible.
module kws_demo_rom #(parameter DEMO_FILE="kws_demo.mem") (
    input logic clk, en,
    input logic [13:0] address,
    output logic [7:0] data
);
    (* rom_style="block" *) logic [7:0] memory [0:16383];
    initial $readmemh(DEMO_FILE, memory);
    always_ff @(posedge clk) if(en) data <= memory[address];
endmodule
