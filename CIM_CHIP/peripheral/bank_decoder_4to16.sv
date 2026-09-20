`timescale 1ns/1ps

// Active-high four-to-16 decoder for selecting one column/bank position.
//
// The presentation connects B0-B3 to decoder inputs A0-A3 and shows outputs
// o0-o15.  bank_addr is therefore ordered as {B3, B2, B1, B0}.  Exactly one
// bank_select bit is high for every valid four-bit address.
//
// SRAM/CIM mode routing is intentionally kept outside this module.  The
// selected line is routed to sram_en or cim_en by the following mode-control
// logic, matching the separate one-to-two demultiplexer in the presentation.
module bank_decoder_4to16 (
    input wire logic [3:0]  bank_addr,
    output logic [15:0] bank_select
);

    always_comb begin
        bank_select = 16'b0;
        bank_select[bank_addr] = 1'b1;
    end

endmodule
