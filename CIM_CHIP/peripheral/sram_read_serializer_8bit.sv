`timescale 1ns/1ps

// SRAM read parallel-to-serial stage.
//
// The presentation reads one selected pair of 32x4 banks through eight
// shared sense amplifiers, then sends the resulting byte through the shared
// sumo/read pin in eight clocks.  In this digital model, even_read_data and
// odd_read_data are the two 4-bit sense-amplifier-equivalent results:
//
//     read word[7:4] = even_read_data
//     read word[3:0] = odd_read_data
//
// This is the one and only clocked register in the digital SRAM read-output
// path.  pair_read_valid and both nibbles must be stable before the same
// rising edge.  That edge loads the complete byte, and serial_read_bit
// immediately presents bit 7.
// Each following rising edge shifts the next bit to the output.  Zeros are
// shifted in after bit 0 has been sent.
//
// The valid signal is an internal RTL handshake, not an additional chip pin.
// A normal read controller must produce a one-clock sense/read-valid pulse;
// holding pair_read_valid high reloads the byte instead of shifting it.
module sram_read_serializer_8bit (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [3:0] even_read_data,
    input  logic [3:0] odd_read_data,
    input  logic       pair_read_valid,
    output logic       serial_read_bit
);

    logic [7:0] read_shift_register;
    logic       read_capture;

    assign read_capture    = pair_read_valid;
    assign serial_read_bit = read_shift_register[7];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_shift_register <= 8'b0;
        end else if (read_capture) begin
            read_shift_register <= {even_read_data, odd_read_data};
        end else begin
            read_shift_register <= {read_shift_register[6:0], 1'b0};
        end
    end

endmodule
