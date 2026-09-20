`timescale 1ns/1ps

// One complete 32-row x 4-column DCIM bank/segment.
//
// A predecoded one-hot write-enable selects which row stores write_data.  In
// CIM mode, the 32 activation bits operate on the 32 stored four-bit weights
// in parallel.  This module deliberately stops at the thirty-two four-bit
// row products.  The complete 128x128 array selects one even/odd bank pair
// first and then feeds only those products to two shared adder trees.  Moving
// the reduction out of every bank reduces the synthesized adder-tree count
// from 128 to two without changing the stored-cell organization.
module dcim_bank_32x4 (
    input  logic        clk,
    input  logic        rst_n,

    // SRAM write path.  row_write_en is supplied by an external row decoder.
    input  logic [31:0] row_write_en,
    input  logic [3:0]  write_data,

    // SRAM sense-equivalent path.  row_read_en must be one-hot when sense_en
    // is asserted.  This bank deliberately contains no read register: the
    // selected nibble propagates combinationally to the shared eight-bit SRAM
    // serializer, which is the one and only clocked read-output stage.
    input  logic        sense_en,
    input  logic [31:0] row_read_en,
    output logic [3:0]  read_data,
    output logic        read_valid,

    // Reserved nonvolatile and power controls, shared by all cells.
    input  logic        nv_store,
    input  logic        nv_recall,
    input  logic        pd_en,

    // DCIM compute controls and one activation bit for each of the 32 rows.
    input  logic        cim_en,
    input  logic        cim_row,
    input  logic [31:0] activation_bits,

    // Thirty-two activation-gated four-bit weights.  The array-level shared
    // adder tree reduces the selected bank's complete vector.
    output wire logic [3:0] row_product [0:31]
);

    logic [3:0] row_read_data [0:31];
    logic [3:0] selected_read_data;

    // Thirty-two row slices store thirty-two independent four-bit weights.
    // The generate loop is elaborated into 32 parallel hardware instances.
    genvar row_index;
    generate
        for (row_index = 0; row_index < 32; row_index++) begin : g_dcim_row
            dcim_row_4bit u_dcim_row_4bit (
                .clk            (clk),
                .rst_n          (rst_n),
                
                .row_write_en   (row_write_en[row_index]),
                .write_data     (write_data),
                .sense_en       (sense_en & row_read_en[row_index]),
                .read_data      (row_read_data[row_index]),
                
                .nv_store       (nv_store),
                .nv_recall      (nv_recall),
                .pd_en          (pd_en),

                .cim_en         (cim_en),
                .cim_row        (cim_row),
                .activation_bit (activation_bits[row_index]),
                .stored_q       (),
                .stored_qb      (),
                .row_product    (row_product[row_index])
            );
        end
    endgenerate

    // One-hot OR read mux.  Every unselected row outputs zero, so ORing the
    // 32 row outputs returns the selected four-bit weight.  The fixed loop is
    // synthesizable and is expanded into combinational OR logic by Vivado.
    integer read_index;
    always_comb begin
        selected_read_data = 4'b0000;
        for (read_index = 0; read_index < 32; read_index = read_index + 1)
            selected_read_data = selected_read_data | row_read_data[read_index];
    end

    // Combinational SA-equivalent output.  The following serializer captures
    // this value on the first rising edge with sense_en asserted, eliminating
    // the former Bank-register + Serializer-register double latency.
    assign read_data = (rst_n && sense_en && (|row_read_en)) ?
                       selected_read_data : 4'b0000;
    assign read_valid = rst_n && sense_en && (|row_read_en);

endmodule
