`timescale 1ns/1ps

// Integrated unsigned bit-serial accumulator and 18-bit serial output.
//
// This module is one complete ACC path from the lecture.  Two instances are
// used by the Macro Core: one produces sume and the other produces sumo.
// The external controller supplies exactly eight UINT8 activation bit planes
// in MSB-first order.  Every accepted output_en edge performs:
//
//     next_acc = (accumulated_sum << 1) + partial_sum
//
// An internal three-bit counter identifies the eighth accepted sample.  On
// that same rising edge, next_acc is also loaded into the internal 18-bit
// serial-output stage, so bit[17] is visible immediately after the edge.  No
// external serial_load signal is required.
//
// reset1 and reset2 implement the two active-high output-control resets from
// the agreed project specification:
//   reset1 clears accumulation state and rearms the eight-sample sequence.
//   reset2 clears only the serial-output shift state.
// Neither reset is connected to the weight-array storage model.
module bitserial_accumulator (
    input  logic        bufclk,
    input  logic        reset1,
    input  logic        reset2,
    input  logic        output_en,
    input  logic [8:0]  partial_sum,
    output logic [17:0] accumulated_sum,
    output logic        serial_sum,
    output logic        serial_active
);

    logic [2:0]  sample_count;
    logic        accumulation_complete;
    logic [17:0] partial_sum_extended;
    logic [17:0] next_accumulated_sum;
    logic        accept_sample;
    logic        final_sample;

    assign partial_sum_extended = {9'b0, partial_sum};
    assign next_accumulated_sum = (accumulated_sum << 1) +
                                  partial_sum_extended;

    assign accept_sample = output_en & ~reset1 &
                           ~accumulation_complete;
    assign final_sample  = accept_sample & (sample_count == 3'd7);

    always_ff @(posedge bufclk or posedge reset1) begin
        if (reset1) begin
            accumulated_sum     <= 18'b0;
            sample_count        <= 3'd0;
            accumulation_complete <= 1'b0;
        end else if (accept_sample) begin
            accumulated_sum <= next_accumulated_sum;

            if (final_sample) begin
                accumulation_complete <= 1'b1;
            end else begin
                sample_count <= sample_count + 3'd1;
            end
        end
    end

    // final_sample is an internal one-edge load request.  The combinational
    // next_accumulated_sum includes the eighth partial sum before the output
    // stage captures it on that same edge.
    serial_output u_serial_output (
        .bufclk       (bufclk),
        .reset2       (reset2),
        .load         (final_sample),
        .parallel_data(next_accumulated_sum),
        .serial_bit   (serial_sum),
        .serial_active(serial_active)
    );

endmodule
