`timescale 1ns/1ps
// Minimal synthesizable storage model for one FeSRAM/DCIM cell.
//
// Only one flip-flop is implemented at this stage.  The nonvolatile-control
// ports are intentionally retained so a future FeRAM store/recall model can be
// added without changing the interfaces of row, segment, array, or chip levels.
module fesram_cell_model (
    input  logic clk,
    input  logic rst_n,

    // SRAM operation
    input  logic write_en,
    input  logic write_data,

    // Reserved for a future normally-off / nonvolatile implementation.
    // These inputs do not affect cell_bit in the current one-FF model.
    input  logic nv_store,
    input  logic nv_recall,
    input  logic pd_en,

    // SRAM storage nodes
    output logic q,
    output logic qb
);

    // Keep write-enable in the D-input mux instead of a dedicated FF CE.
    // The 2048 independently written bytes otherwise create many control
    // sets. Storage/reset behavior is unchanged; placement must be rechecked.
    (* EXTRACT_ENABLE = "no" *) logic cell_bit;

    // One physical FPGA flip-flop stores the programmed weight bit.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cell_bit <= 1'b0;
        end else if (write_en) begin
            cell_bit <= write_data;
        end
    end

    assign q  = cell_bit;
    assign qb = ~cell_bit;

endmodule
