`timescale 1ns/1ps

// One 32-row x 128-column group of the complete DCIM array.
//
// Slide 2 of 0622.pptx arranges the 128x128 macro as four row groups.  Each
// row group receives the same 32 local activation inputs (IN0..IN31) and
// contains thirty-two 32x4 segments:
//
//   pair p -> even segment 2*p and odd segment 2*p+1
//
// The two segments in a pair share the selected column control but retain
// independent four-bit write/read data and four-bit products for every row.
// This matches the proposal statement that one write driver feeds two
// segments to form an eight-bit word, while their partial sums are preserved
// as two independent accumulator paths.
//
// This FPGA-optimized version selects one of the sixteen pairs before doing
// arithmetic.  It emits the selected even and odd row-product vectors; the
// array above this module selects one of four row groups and owns the only two
// adder trees in the complete macro.
module dcim_row_group (
    input  logic        clk,
    input  logic        rst_n,

    // Local slice of the global 7-to-128 word-line decoder.  At most one of
    // these 32 bits is active during a normal SRAM read or write transaction.
    input  logic [31:0] local_wl_select,
    input  logic        write_en,
    input  logic        sense_en,

    // One-hot pair enables produced by bank_pair_selector.  Normal operation
    // enables either the SRAM vector or the CIM vector, never both.
    input  logic [15:0] sram_pair_en,
    input  logic [15:0] cim_pair_en,

    // The two nibbles are deliberately named even/odd rather than high/low.
    // The presentation does not unambiguously assign bit significance to the
    // physical segment parity; that mapping belongs at the array/chip level.
    input  logic [3:0]  even_write_data,
    input  logic [3:0]  odd_write_data,

    // This group's output of cim_group_decoder_2to4 and the 32 activation bits
    // broadcast by the slide-3 one-to-four input buffers.
    input  logic        cim_group_en,
    input  logic [31:0] activation_bits,

    // Nonvolatile/power controls are broadcast to all 4096 cells in the group.
    input  logic        nv_store,
    input  logic        nv_recall,
    input  logic        pd_en,

    // SRAM read selection is completed inside the row group.  Only the two
    // nibbles belonging to the selected adjacent pair leave this module.
    output logic [3:0]  selected_even_read_data,
    output logic [3:0]  selected_odd_read_data,
    output logic        selected_pair_read_valid,

    // Products from the one selected pair.  Unselected banks emit zero and
    // are combined as one-hot OR muxes before the shared array-level adders.
    output logic [3:0]  selected_even_product [0:31],
    output logic [3:0]  selected_odd_product  [0:31]
);

    logic [3:0] bank_read_data   [0:31];
    logic       bank_read_valid  [0:31];
    logic [3:0] bank_row_product [0:31][0:31];

    // There are sixteen adjacent segment pairs in one 32x128 row group.
    // Each fixed generate iteration elaborates two complete 32x4 banks.
    genvar pair_index;
    generate
        for (pair_index = 0; pair_index < 16; pair_index = pair_index + 1) begin : g_bank_pair
            logic [31:0] pair_row_write_en;
            logic        pair_sense_en;

            // SRAM writes require all three conditions: a selected local WL,
            // the external write command, and the selected SRAM pair.
            assign pair_row_write_en = local_wl_select &
                                       {32{write_en & sram_pair_en[pair_index]}};

            // Both four-bit segments in the pair are sensed together to form
            // the shared eight-bit SRAM read path described by the proposal.
            assign pair_sense_en = sense_en & sram_pair_en[pair_index];

            dcim_bank_32x4 u_even_bank (
                .clk             (clk),
                .rst_n           (rst_n),
                .row_write_en    (pair_row_write_en),
                .write_data      (even_write_data),
                .sense_en        (pair_sense_en),
                .row_read_en     (local_wl_select),
                .read_data       (bank_read_data[(pair_index * 2)]),
                .read_valid      (bank_read_valid[(pair_index * 2)]),
                .nv_store        (nv_store),
                .nv_recall       (nv_recall),
                .pd_en           (pd_en),
                .cim_en          (cim_pair_en[pair_index]),
                .cim_row         (cim_group_en),
                .activation_bits (activation_bits),
                .row_product     (bank_row_product[(pair_index * 2)])
            );

            dcim_bank_32x4 u_odd_bank (
                .clk             (clk),
                .rst_n           (rst_n),
                .row_write_en    (pair_row_write_en),
                .write_data      (odd_write_data),
                .sense_en        (pair_sense_en),
                .row_read_en     (local_wl_select),
                .read_data       (bank_read_data[(pair_index * 2) + 1]),
                .read_valid      (bank_read_valid[(pair_index * 2) + 1]),
                .nv_store        (nv_store),
                .nv_recall       (nv_recall),
                .pd_en           (pd_en),
                .cim_en          (cim_pair_en[pair_index]),
                .cim_row         (cim_group_en),
                .activation_bits (activation_bits),
                .row_product     (bank_row_product[(pair_index * 2) + 1])
            );
        end
    endgenerate

    // The SRAM column decoder enables one adjacent bank pair.  Reduce the
    // thirty-two local bank outputs here instead of exporting all of them to
    // the array.  A pair is valid only when both four-bit bank senses are
    // valid; invalid data is masked to zero before the OR-mux reduction.
    integer read_pair_index;
    always_comb begin
        selected_even_read_data  = 4'b0000;
        selected_odd_read_data   = 4'b0000;
        selected_pair_read_valid = 1'b0;

        for (read_pair_index = 0; read_pair_index < 16;
             read_pair_index = read_pair_index + 1) begin
            selected_even_read_data = selected_even_read_data |
                (bank_read_data[read_pair_index * 2] &
                 {4{bank_read_valid[read_pair_index * 2] &
                    bank_read_valid[(read_pair_index * 2) + 1]}});
            selected_odd_read_data = selected_odd_read_data |
                (bank_read_data[(read_pair_index * 2) + 1] &
                 {4{bank_read_valid[read_pair_index * 2] &
                    bank_read_valid[(read_pair_index * 2) + 1]}});
            selected_pair_read_valid = selected_pair_read_valid |
                (bank_read_valid[read_pair_index * 2] &
                 bank_read_valid[(read_pair_index * 2) + 1]);
        end
    end

    // Pair selection precedes arithmetic.  Under the normal one-hot
    // cim_pair_en contract, at most one even and one odd bank contribute.
    // Explicit OR reduction is equivalent to the presentation's inactive-zero
    // selection while allowing the following array to share its adders.
    integer product_row_index;
    integer product_pair_index;
    always_comb begin
        for (product_row_index = 0; product_row_index < 32;
             product_row_index = product_row_index + 1) begin
            selected_even_product[product_row_index] = 4'b0000;
            selected_odd_product[product_row_index]  = 4'b0000;

            for (product_pair_index = 0; product_pair_index < 16;
                 product_pair_index = product_pair_index + 1) begin
                selected_even_product[product_row_index] =
                    selected_even_product[product_row_index] |
                    bank_row_product[product_pair_index * 2]
                                    [product_row_index];
                selected_odd_product[product_row_index] =
                    selected_odd_product[product_row_index] |
                    bank_row_product[(product_pair_index * 2) + 1]
                                    [product_row_index];
            end
        end
    end

endmodule
