`timescale 1ns/1ps

// Structural integration of the lecture's 128x128 DCIM macro datapath.
//
// This module corresponds to the Input Control, Logic Control, Row Decoder,
// Group Selector, Bank Selector, memory array, two accumulators, and sume/sumo
// output paths in Proposal Figure 4 and 0622.pptx slides 2 through 6.
// SRAM/CIM transaction sequencing remains external.  Each accumulator does,
// however, count its eight UINT8 bit planes and starts its own 18-bit serial
// output on the eighth accepted output_en edge, as required by the agreed
// reset1/reset2 and output timing.
module dcim_macro_core (
    input  logic        clk,

    // model_rst_n resets only the synthesizable digital storage abstraction.
    // The lecture output controls reset1/reset2 are active-high and never
    // erase stored weights.
    input  logic        model_rst_n,
    input  logic        reset1,
    input  logic        reset2,

    // Lecture address pins A[6:0] and B[3:0].  A[6:0] selects one SRAM row;
    // A[6:5] selects one 32-row CIM group; B selects one 8-bit bank pair.
    input  logic [6:0]  row_addr,
    input  logic [3:0]  bank_addr,

    // SRAM/CIM input-path and memory-operation controls.
    input  logic        mode_sel,       // 0: SRAM mode, 1: CIM mode
    input  logic        wl_en,
    input  logic        write_en,
    input  logic        sense_en,
    input  logic        pre_en,
    input  logic        clk_en,
    input  logic        sel_next,
    input  logic [3:0]  din,

    // output_en accepts one nine-bit CIM bit-plane result.  Exactly eight
    // accepted pulses form one UINT8 result; no external serial_load exists.
    input  logic        output_en,

    // Reserved nonvolatile controls.  They are preserved through the current
    // hierarchy even though the one-FF FeSRAM abstraction ignores them.
    input  logic        nv_store,
    input  logic        nv_recall,
    input  logic        pd_en,

    // Parallel SRAM readback remains visible at the core boundary.  The
    // dcim_chip_pin_top wrapper will connect these combinational SA-equivalent
    // results to sram_read_serializer_8bit, the only clocked SRAM read-output
    // stage, and multiplex its serial bit with sumo on the shared pad.
    output logic [3:0]  selected_even_read_data,
    output logic [3:0]  selected_odd_read_data,
    output logic        selected_pair_read_valid,

    // Debug/verification observability.  These are internal core signals, not
    // additional physical chip pins.
    output logic [8:0]  selected_even_partial_sum,
    output logic [8:0]  selected_odd_partial_sum,
    output logic [17:0] even_accumulated_sum,
    output logic [17:0] odd_accumulated_sum,

    // Lecture serial compute outputs.
    output logic        sume,
    output logic        sumo
);

    logic [31:0]  buffered_bits;
    logic [7:0]   sram_write_data;
    logic [31:0]  activation_group_bits [0:3];

    logic [127:0] wl_select;
    logic [3:0]   cim_group_select;
    logic [15:0]  bank_select;
    logic [15:0]  sram_pair_en;
    logic [15:0]  cim_pair_en;

    // pre_en is a real lecture pin for physical bit-line precharge.  The
    // current digital read abstraction has no voltage/precharge model, so the
    // signal is deliberately preserved at this boundary without changing the
    // functional read result.
    logic pre_en_reserved;
    assign pre_en_reserved = pre_en;

    input_buffer_32x4 u_input_buffer_32x4 (
        .bufclk         (clk),
        .rst_n          (model_rst_n),
        .clk_en         (clk_en),
        .sel_next       (sel_next),
        .mode_sel       (mode_sel),
        .din            (din),
        .buffered_bits  (buffered_bits),
        .sram_write_data(sram_write_data),
        .cim_group_bits (activation_group_bits)
    );

    row_decoder_7to128 u_row_decoder_7to128 (
        .row_addr  (row_addr),
        .wl_en     (wl_en),
        .wl_select (wl_select)
    );

    cim_group_decoder_2to4 u_cim_group_decoder_2to4 (
        .group_addr (row_addr[6:5]),
        .cim_row    (cim_group_select)
    );

    bank_decoder_4to16 u_bank_decoder_4to16 (
        .bank_addr   (bank_addr),
        .bank_select (bank_select)
    );

    bank_pair_selector u_bank_pair_selector (
        .bank_select  (bank_select),
        .mode_sel     (mode_sel),
        .cim_pair_en  (cim_pair_en),
        .sram_pair_en (sram_pair_en)
    );

    dcim_array_128x128 u_dcim_array_128x128 (
        .clk                      (clk),
        .rst_n                    (model_rst_n),
        .wl_select                (wl_select),
        .write_en                 (write_en),
        .sense_en                 (sense_en),
        .sram_pair_en             (sram_pair_en),
        .cim_pair_en              (cim_pair_en),

        // The first loaded nibble reaches stage 1 and becomes bits [7:4].
        // The approved mapping stores it in the even segment; the second
        // nibble is bits [3:0] and is stored in the odd segment.
        .even_write_data          (sram_write_data[7:4]),
        .odd_write_data           (sram_write_data[3:0]),

        .cim_group_select         (cim_group_select),
        .activation_group_bits    (activation_group_bits),
        .nv_store                 (nv_store),
        .nv_recall                (nv_recall),
        .pd_en                    (pd_en),
        .selected_even_read_data  (selected_even_read_data),
        .selected_odd_read_data   (selected_odd_read_data),
        .selected_pair_read_valid (selected_pair_read_valid),
        .selected_even_sum        (selected_even_partial_sum),
        .selected_odd_sum         (selected_odd_partial_sum)
    );

    bitserial_accumulator u_even_accumulator (
        .bufclk          (clk),
        .reset1          (reset1),
        .reset2          (reset2),
        .output_en       (output_en),
        .partial_sum     (selected_even_partial_sum),
        .accumulated_sum (even_accumulated_sum),
        .serial_sum      (sume),
        .serial_active   ()
    );

    bitserial_accumulator u_odd_accumulator (
        .bufclk          (clk),
        .reset1          (reset1),
        .reset2          (reset2),
        .output_en       (output_en),
        .partial_sum     (selected_odd_partial_sum),
        .accumulated_sum (odd_accumulated_sum),
        .serial_sum      (sumo),
        .serial_active   ()
    );

endmodule
