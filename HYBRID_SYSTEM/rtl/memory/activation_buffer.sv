`timescale 1ns/1ps
// Local BRAM backend, NOT a variable-latency DDR interface.
// Requests are sampled on clk rising edges. Read data/valid appear after
// that edge and can be consumed by downstream registers on the next edge.
module activation_buffer (
    input  logic clk,
    input  logic rst,
    input  logic wr_en,
    input  kws_system_pkg::activation_addr_t wr_addr,
    input  kws_system_pkg::activation_t wr_data,
    input  logic rd_en,
    input  kws_system_pkg::activation_addr_t rd_addr,
    output logic rd_valid,
    output kws_system_pkg::activation_t rd_data
);
    // No reset loop or initialization: preserve block RAM inference.
    (* ram_style = "block" *)
    logic [kws_system_pkg::ACT_DATA_WIDTH-1:0] mem [0:kws_system_pkg::ACT_DEPTH-1];

    always_ff @(posedge clk) begin
        if (!rst && wr_en)
            mem[wr_addr] <= wr_data;
        if (!rst && rd_en)
            rd_data <= mem[rd_addr];
    end

    always_ff @(posedge clk) begin
        if (rst) rd_valid <= 1'b0;
        else     rd_valid <= rd_en;
    end

    // Same-address read/write is outside the interface contract. No hardware
    // comparator is synthesized; upstream scheduling must prevent collisions.
    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst && wr_en && rd_en && wr_addr == rd_addr)
            $fatal(1, "ACTIVATION_BUFFER_COLLISION: simultaneous read/write address %0d", rd_addr);
    end
    // synthesis translate_on
endmodule
