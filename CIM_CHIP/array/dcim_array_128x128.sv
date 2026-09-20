`timescale 1ns/1ps

// Structural 128-row x 128-column DCIM array.
//
// 0622.pptx slide 2 partitions the macro into four 32-row groups.  Every
// group contains thirty-two 32x4 segments and receives one of the four
// 32-bit fanouts from the slide-3 Input Path:
//
//   4 row groups x 32 rows x 32 segments x 4 cells = 128 x 128 cells
//
// The address decoders, Input Path and SRAM/CIM mode demultiplexer are
// intentionally outside this module.  This array receives their predecoded
// internal controls.  The later dcim_macro_core will connect those peripheral
// blocks to this structural array.
//
// Only one row group and one adjacent segment pair are enabled during a
// normal CIM operation.  This FPGA implementation therefore selects the
// thirty-two four-bit row products first, then reduces them with exactly two
// shared adder trees: one even path and one odd path.  The external partial-
// sum behavior stays equivalent to the presentation while avoiding 128
// physically duplicated adder trees.
module dcim_array_128x128 (
    input  logic         clk,
    input  logic         rst_n,

    // Predecoded SRAM word lines from row_decoder_7to128.  Each row group
    // receives one contiguous 32-bit slice.
    input  logic [127:0] wl_select,
    input  logic         write_en,
    input  logic         sense_en,

    // Predecoded column-pair controls from bank_pair_selector.  Pair p owns
    // physical segments 2*p and 2*p+1 in every row group.
    input  logic [15:0]  sram_pair_en,
    input  logic [15:0]  cim_pair_en,

    // Independent four-bit data for the adjacent even and odd segments.
    // Their high/low-nibble significance is deliberately not fixed here.
    input  logic [3:0]   even_write_data,
    input  logic [3:0]   odd_write_data,

    // One-hot group selection from cim_group_decoder_2to4 and the four
    // physical one-to-four activation fanouts from input_buffer_32x4.
    input  logic [3:0]   cim_group_select,
    // Explicit net kind keeps this unpacked-array port compatible with
    // Vivado 2023.2.
    input  wire logic [31:0] activation_group_bits [0:3],

    // Reserved FeSRAM nonvolatile/power controls, broadcast to all cells.
    input  logic         nv_store,
    input  logic         nv_recall,
    input  logic         pd_en,

    // Selected combinational SRAM pair readback.  The array contains no read
    // register; the chip-level SRAM serializer is the only clocked stage.
    output logic [3:0]   selected_even_read_data,
    output logic [3:0]   selected_odd_read_data,
    output logic         selected_pair_read_valid,

    // One activation-bit-plane result for each independent 4-bit path.
    output logic [8:0]   selected_even_sum,
    output logic [8:0]   selected_odd_sum
);

    // Each row group selects its SRAM bank pair locally.  The array only
    // merges four compact pair results instead of 4 x 32 raw bank buses.
    logic [3:0] group_even_read_data [0:3];
    logic [3:0] group_odd_read_data  [0:3];
    logic       group_pair_read_valid[0:3];

    // Each row group has already selected one of its sixteen bank pairs.
    // cim_group_select makes only one group's vectors nonzero.
    logic [3:0] group_even_product [0:3][0:31];
    logic [3:0] group_odd_product  [0:3][0:31];

    // Inputs to the only two adder trees in the complete array.
    logic [3:0] selected_even_product [0:31];
    logic [3:0] selected_odd_product  [0:31];

    // Four physical 32-row groups form the complete 128-row array.  The
    // part-select is constant for every elaborated instance and is
    // synthesizable by Vivado.
    genvar group_index;
    generate
        for (group_index = 0; group_index < 4; group_index = group_index + 1) begin : g_row_group
            dcim_row_group u_dcim_row_group (
                .clk             (clk),
                .rst_n           (rst_n),
                .local_wl_select (wl_select[(group_index * 32) +: 32]),
                .write_en        (write_en),
                .sense_en        (sense_en),
                .sram_pair_en    (sram_pair_en),
                .cim_pair_en     (cim_pair_en),
                .even_write_data (even_write_data),
                .odd_write_data  (odd_write_data),
                .cim_group_en    (cim_group_select[group_index]),
                .activation_bits (activation_group_bits[group_index]),
                .nv_store        (nv_store),
                .nv_recall       (nv_recall),
                .pd_en           (pd_en),
                .selected_even_read_data(group_even_read_data[group_index]),
                .selected_odd_read_data (group_odd_read_data[group_index]),
                .selected_pair_read_valid(group_pair_read_valid[group_index]),
                .selected_even_product  (group_even_product[group_index]),
                .selected_odd_product   (group_odd_product[group_index])
            );
        end
    endgenerate

    // The global row decoder enables at most one 32-row group for SRAM.
    // Mask invalid groups and OR the four compact results as a one-hot mux.
    always_comb begin
        selected_even_read_data =
            (group_even_read_data[0] & {4{group_pair_read_valid[0]}}) |
            (group_even_read_data[1] & {4{group_pair_read_valid[1]}}) |
            (group_even_read_data[2] & {4{group_pair_read_valid[2]}}) |
            (group_even_read_data[3] & {4{group_pair_read_valid[3]}});
        selected_odd_read_data =
            (group_odd_read_data[0] & {4{group_pair_read_valid[0]}}) |
            (group_odd_read_data[1] & {4{group_pair_read_valid[1]}}) |
            (group_odd_read_data[2] & {4{group_pair_read_valid[2]}}) |
            (group_odd_read_data[3] & {4{group_pair_read_valid[3]}});
        selected_pair_read_valid = group_pair_read_valid[0] |
                                   group_pair_read_valid[1] |
                                   group_pair_read_valid[2] |
                                   group_pair_read_valid[3];
    end

    // Select one of the four row groups before arithmetic.  All inactive
    // groups produce zero because cim_group_en gates every cell product.
    genvar product_index;
    generate
        for (product_index = 0; product_index < 32;
             product_index = product_index + 1) begin : g_select_group_products
            assign selected_even_product[product_index] =
                group_even_product[0][product_index] |
                group_even_product[1][product_index] |
                group_even_product[2][product_index] |
                group_even_product[3][product_index];

            assign selected_odd_product[product_index] =
                group_odd_product[0][product_index] |
                group_odd_product[1][product_index] |
                group_odd_product[2][product_index] |
                group_odd_product[3][product_index];
        end
    endgenerate

    // The complete 128x128 FPGA model contains only these two arithmetic
    // reducers.  Bit-serial accumulation across activation bit planes remains
    // outside the array, exactly as before.
    adder_tree_32x4 u_shared_even_adder_tree (
        .row_product (selected_even_product),
        .bank_sum    (selected_even_sum)
    );

    adder_tree_32x4 u_shared_odd_adder_tree (
        .row_product (selected_odd_product),
        .bank_sum    (selected_odd_sum)
    );

endmodule
