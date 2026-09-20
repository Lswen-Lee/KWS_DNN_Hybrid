`timescale 1ns/1ps

// External-pin wrapper for the lecture's 128x128 DCIM chip.
//
// The wrapper keeps transaction sequencing outside the chip, matching the
// control-pin style shown on 0622.pptx slide 11.  It adds only the two pieces
// that belong at the pin boundary rather than inside dcim_macro_core:
//
//   1. One eight-bit SRAM read serializer.  The selected even/odd 32x4 banks
//      form {even, odd}; the first sense-enabled rising edge exposes bit 7.
//   2. The shared odd/read output mux.  SRAM mode sends the serialized read
//      bit to sumo, while CIM mode sends the odd accumulator serial result.
//
// pre_en and the nonvolatile controls are retained as pins, but the present
// synthesizable model does not reproduce analog precharge, sense-amplifier,
// FeRAM, IO-pad, or power-domain behavior.
module dcim_chip_pin_top (
    input  logic       clk,

    // RTL storage-model reset.  This is not identified as a separate pin in
    // the lecture; it is retained so the FF-based FPGA model can be reset.
    input  logic       model_rst_n,

    // Lecture output-state resets, fixed by the project specification as
    // active-high: reset1 clears ACC state; reset2 clears serial outputs.
    input  logic       reset1,
    input  logic       reset2,

    // Lecture address pins A[6:0] and B[3:0].
    input  logic [6:0] row_addr,
    input  logic [3:0] bank_addr,

    // SRAM/CIM data-path controls.
    input  logic       mode_sel,       // 0: SRAM, 1: CIM
    input  logic       wl_en,
    input  logic       write_en,
    input  logic       sense_en,
    input  logic       pre_en,
    input  logic       clk_en,
    input  logic       sel_next,
    input  logic [3:0] din,
    input  logic       output_en,

    // Reserved nonvolatile/power pins.  They currently have no functional
    // effect in the one-FF cell abstraction.
    input  logic       nv_store,
    input  logic       nv_recall,
    input  logic       pd_en,

    // Normal logical levels are used.  Any physical PAD inversion belongs in
    // a technology-specific IO wrapper, not in this synthesizable RTL.
    output logic       sume,
    output logic       sumo
);

    logic [3:0]  even_read_data;
    logic [3:0]  odd_read_data;
    logic        pair_read_valid;
    logic        core_sume;
    logic        core_sumo;
    logic        serial_read_bit;
    logic        read_serializer_rst_n;

    // reset2 is the active-high output reset.  model_rst_n also clears the
    // serializer during initialization of the synthesizable storage model.
    assign read_serializer_rst_n = model_rst_n & ~reset2;

    dcim_macro_core u_dcim_macro_core (
        .clk                       (clk),
        .model_rst_n               (model_rst_n),
        .reset1                    (reset1),
        .reset2                    (reset2),
        .row_addr                  (row_addr),
        .bank_addr                 (bank_addr),
        .mode_sel                  (mode_sel),
        .wl_en                     (wl_en),
        .write_en                  (write_en),
        .sense_en                  (sense_en),
        .pre_en                    (pre_en),
        .clk_en                    (clk_en),
        .sel_next                  (sel_next),
        .din                       (din),
        .output_en                 (output_en),
        .nv_store                  (nv_store),
        .nv_recall                 (nv_recall),
        .pd_en                     (pd_en),
        .selected_even_read_data   (even_read_data),
        .selected_odd_read_data    (odd_read_data),
        .selected_pair_read_valid  (pair_read_valid),
        .selected_even_partial_sum (),
        .selected_odd_partial_sum  (),
        .even_accumulated_sum      (),
        .odd_accumulated_sum       (),
        .sume                      (core_sume),
        .sumo                      (core_sumo)
    );

    // The sole clocked register in the SRAM read-output path.  Bank, Row
    // Group, Array and Macro read selection are combinational before here.
    sram_read_serializer_8bit u_sram_read_serializer_8bit (
        .clk             (clk),
        .rst_n           (read_serializer_rst_n),
        .even_read_data  (even_read_data),
        .odd_read_data   (odd_read_data),
        .pair_read_valid (pair_read_valid),
        .serial_read_bit (serial_read_bit)
    );

    // Slide 6 keeps the even and odd accumulator paths separate.  The project
    // pin plan shares the odd output with SRAM readback, so only sumo needs a
    // mode mux.  There is deliberately no output-pad inversion in this RTL.
    assign sume = core_sume;
    assign sumo = mode_sel ? core_sumo : serial_read_bit;

endmodule
