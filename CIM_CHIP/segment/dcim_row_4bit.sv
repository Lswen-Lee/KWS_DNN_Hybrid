`timescale 1ns/1ps

// One row of a 32-row x 4-column DCIM bank.
//
// The four cells store one unsigned 4-bit weight (bit 3 is the MSB).  During
// CIM operation, one activation bit is shared by all four cells.  The row
// emits either the stored 4-bit weight or zero; the 32-row addition belongs in
// adder_tree_32x4 and bit-serial shifting belongs in the accumulator.
module dcim_row_4bit (
    input  logic       clk,
    input  logic       rst_n,

    // Predecoded SRAM row-write control and the four weight bits.
    input  logic       row_write_en,
    input  logic [3:0] write_data,

    // Predecoded asynchronous read control.  No precharge or sense-amplifier
    // timing is modeled: a selected row directly drives its stored four bits.
    input  logic       sense_en,
    output logic [3:0] read_data,

    // Reserved nonvolatile/power controls, broadcast to all four cells.
    input  logic       nv_store,
    input  logic       nv_recall,
    input  logic       pd_en,

    // Shared DCIM input controls for this row.
    input  logic       cim_en,
    input  logic       cim_row,
    input  logic       activation_bit,

    // Observable storage nodes and the four one-bit products.
    output logic [3:0] stored_q,
    output logic [3:0] stored_qb,
    output logic [3:0] row_product
);

    logic cim_input_b;

    // Shared Input Control from the presentation.  Generating IN_b once per
    // row avoids four identical NAND gates in the four storage/compute cells.
    assign cim_input_b = ~(cim_en & cim_row & activation_bit);

    // FPGA-friendly SRAM read abstraction.  An unselected row contributes
    // zero so multiple row outputs can be combined by a one-hot OR mux in the
    // bank.  The external decoder must select at most one row for SRAM read.
    assign read_data = sense_en ? stored_q : 4'b0000;

    genvar bit_index;
    generate
        for (bit_index = 0; bit_index < 4; bit_index++) begin : g_weight_cell
            dcim_cell_logic u_dcim_cell_logic (
                .clk         (clk),
                .rst_n       (rst_n),
                .write_en    (row_write_en),
                .write_data  (write_data[bit_index]),
                .nv_store    (nv_store),
                .nv_recall   (nv_recall),
                .pd_en       (pd_en),
                .cim_input_b (cim_input_b),
                .read_q      (stored_q[bit_index]),
                .read_qb     (stored_qb[bit_index]),
                .cim_product (row_product[bit_index])
            );
        end
    endgenerate

endmodule
