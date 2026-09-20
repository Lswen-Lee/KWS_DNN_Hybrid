`timescale 1ns/1ps
// One 18-bit MSB-first serial-output stage used inside one lecture ACC path.
//
// The lecture draws accumulation and serial output as one ACC block.  The RTL
// keeps this shift stage in a small submodule so its reset and bit ordering can
// still be verified independently.  Its load signal is strictly internal to
// bitserial_accumulator; it is not a chip pin or a Macro Core input.
//
// Timing:
//   * On a load rising edge, parallel_data is captured and bit[17] appears
//     immediately after that edge.
//   * The following 17 rising edges expose bit[16] through bit[0].
//   * One more rising edge ends the stream and returns serial_bit to zero.
module serial_output (
    input  logic        bufclk,
    input  logic        reset2,
    input  logic        load,
    input  logic [17:0] parallel_data,
    output logic        serial_bit,
    output logic        serial_active
);

    logic [17:0] shift_register;
    logic [4:0]  remaining_bits;

    assign serial_active = (remaining_bits != 5'd0);
    assign serial_bit    = serial_active ? shift_register[17] : 1'b0;

    always_ff @(posedge bufclk or posedge reset2) begin
        if (reset2) begin
            shift_register <= 18'b0;
            remaining_bits <= 5'd0;
        end else if (load) begin
            shift_register <= parallel_data;
            remaining_bits <= 5'd18;
        end else if (serial_active) begin
            shift_register <= {shift_register[16:0], 1'b0};
            remaining_bits <= remaining_bits - 5'd1;
        end
    end

endmodule
