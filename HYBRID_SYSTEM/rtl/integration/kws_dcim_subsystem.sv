`timescale 1ns/1ps
// S5-B: synthesizable on-FPGA DCIM subsystem. No extra transaction FSM.
// Fixed Conv2/3 geometry: K=108, 12 filters, A=UINT8/zp128, W=signed INT8.
// All public data/handshakes/status belong to clk_sys. Outputs are raw INT32.
//
// RESET CONTRACT (owned by the enclosing system/board wrapper):
// - Both resets originate from ONE reset event (including clock-lock loss).
// - Assert both domains; release each synchronously to its own clock.
// - rst_sys must span a clk_sys edge: backend uses synchronous reset.
// - The CDC slow side and master share exactly the same rst_cim net.
// - No unilateral reset or in-flight retry; after reset reload all weights.
// - source_error aborts a transaction; discard any partial output downstream.
// This wrapper has no MMCM/reset generator, AXI, PoT, RAM writer or burst port.
// Bundled-data CDC still needs physical timing constraints/sign-off; RTL
// simulation alone does not prove metastability or routing-delay safety.
module kws_dcim_subsystem (
    input logic clk_sys, rst_sys,
    input logic clk_cim, rst_cim,

    input logic load_valid,
    output logic load_ready, load_done,
    input logic weight_valid,
    output logic weight_ready,
    input logic signed [7:0] weight_data,

    input logic patch_valid,
    output logic patch_ready, patch_done,
    input logic activation_valid,
    output logic activation_ready,
    input logic [7:0] activation_data,

    output logic result_valid,
    input logic result_ready,
    output logic [3:0] filter_id,
    output logic signed [31:0] result_data,
    output logic result_last,
    output logic busy, weights_ready, error,
    input logic source_error
);
    // 1. Backend <-> CDC: one outstanding command and one retained response.
    logic cmd_valid, cmd_ready, cmd_activation_is_a8;
    logic [1:0] cmd_operation;
    logic [6:0] cmd_row_addr;
    logic [3:0] cmd_bank_addr;
    logic [7:0] cmd_weight;
    logic [255:0] cmd_activation_flat;
    logic rsp_valid, rsp_ready, rsp_data_valid, rsp_error;
    logic [17:0] rsp_even_raw_result, rsp_odd_raw_result;
    logic [7:0] unused_rsp_sram_read_data;

    // 2. CDC <-> pin master: entirely in clk_cim domain.
    logic master_start, master_busy, master_done, master_result_valid, master_error;
    logic [1:0] master_operation;
    logic [6:0] master_row_addr;
    logic [3:0] master_bank_addr;
    logic [7:0] master_weight, master_sram_read_data;
    logic [255:0] master_activation_flat;
    logic master_activation_is_a8;
    logic [17:0] master_even_raw_result, master_odd_raw_result;
    logic unused_burst_weight_ready;
    logic [6:0] unused_burst_weight_row_addr;
    logic [3:0] unused_burst_weight_bank_addr;

    // 3. Pin master <-> synthesizable chip model. Never drive these twice.
    logic chip_model_rst_n, chip_reset1, chip_reset2;
    logic [6:0] chip_row_addr;
    logic [3:0] chip_bank_addr, chip_din;
    logic chip_mode_sel, chip_wl_en, chip_write_en, chip_sense_en, chip_pre_en;
    logic chip_clk_en, chip_sel_next, chip_output_en;
    logic chip_nv_store, chip_nv_recall, chip_pd_en, chip_sume, chip_sumo;

    kws_dcim_backend u_backend (
        .clk(clk_sys), .rst(rst_sys),
        .load_valid(load_valid), .load_ready(load_ready), .load_done(load_done),
        .weight_valid(weight_valid), .weight_ready(weight_ready), .weight_data(weight_data),
        .patch_valid(patch_valid), .patch_ready(patch_ready), .patch_done(patch_done),
        .activation_valid(activation_valid), .activation_ready(activation_ready),
        .activation_data(activation_data),
        .result_valid(result_valid), .result_ready(result_ready), .filter_id(filter_id),
        .result_data(result_data), .result_last(result_last),
        .busy(busy), .weights_ready(weights_ready), .error(error), .source_error(source_error),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_operation(cmd_operation),
        .cmd_row_addr(cmd_row_addr), .cmd_bank_addr(cmd_bank_addr), .cmd_weight(cmd_weight),
        .cmd_activation_flat(cmd_activation_flat), .cmd_activation_is_a8(cmd_activation_is_a8),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_data_valid(rsp_data_valid),
        .rsp_error(rsp_error), .rsp_even_raw_result(rsp_even_raw_result),
        .rsp_odd_raw_result(rsp_odd_raw_result)
    );

    dcim_cdc_bridge u_cdc (
        .clk_125m(clk_sys), .rst_125m(rst_sys),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_operation(cmd_operation),
        .cmd_row_addr(cmd_row_addr), .cmd_bank_addr(cmd_bank_addr), .cmd_weight(cmd_weight),
        .cmd_activation_flat(cmd_activation_flat), .cmd_activation_is_a8(cmd_activation_is_a8),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_data_valid(rsp_data_valid),
        .rsp_error(rsp_error), .rsp_sram_read_data(unused_rsp_sram_read_data),
        .rsp_even_raw_result(rsp_even_raw_result), .rsp_odd_raw_result(rsp_odd_raw_result),
        .clk_50m(clk_cim), .rst_50m(rst_cim),
        .master_start(master_start), .master_operation(master_operation),
        .master_row_addr(master_row_addr), .master_bank_addr(master_bank_addr),
        .master_weight(master_weight), .master_activation_flat(master_activation_flat),
        .master_activation_is_a8(master_activation_is_a8),
        .master_busy(master_busy), .master_done(master_done),
        .master_result_valid(master_result_valid), .master_error(master_error),
        .master_sram_read_data(master_sram_read_data),
        .master_even_raw_result(master_even_raw_result), .master_odd_raw_result(master_odd_raw_result)
    );

    dcim_pin_master u_pin_master (
        .clk(clk_cim), .rst(rst_cim), .start(master_start), .operation(master_operation),
        .command_row_addr(master_row_addr), .command_bank_addr(master_bank_addr),
        .command_weight(master_weight), .activation_flat(master_activation_flat),
        .activation_is_a8(master_activation_is_a8),
        // CDC transports single writes, not a burst stream. Explicitly disabled.
        .command_burst_length(12'd0), .burst_weight_valid(1'b0), .burst_weight_data(8'd0),
        .burst_weight_ready(unused_burst_weight_ready),
        .burst_weight_row_addr(unused_burst_weight_row_addr),
        .burst_weight_bank_addr(unused_burst_weight_bank_addr),
        .busy(master_busy), .done(master_done), .result_valid(master_result_valid),
        .error(master_error), .sram_read_data(master_sram_read_data),
        .even_raw_result(master_even_raw_result), .odd_raw_result(master_odd_raw_result),
        .chip_model_rst_n(chip_model_rst_n), .chip_reset1(chip_reset1), .chip_reset2(chip_reset2),
        .chip_row_addr(chip_row_addr), .chip_bank_addr(chip_bank_addr),
        .chip_mode_sel(chip_mode_sel), .chip_wl_en(chip_wl_en), .chip_write_en(chip_write_en),
        .chip_sense_en(chip_sense_en), .chip_pre_en(chip_pre_en), .chip_clk_en(chip_clk_en),
        .chip_sel_next(chip_sel_next), .chip_din(chip_din), .chip_output_en(chip_output_en),
        .chip_nv_store(chip_nv_store), .chip_nv_recall(chip_nv_recall), .chip_pd_en(chip_pd_en),
        .chip_sume(chip_sume), .chip_sumo(chip_sumo)
    );

    dcim_chip_pin_top u_chip (
        .clk(clk_cim), .model_rst_n(chip_model_rst_n), .reset1(chip_reset1), .reset2(chip_reset2),
        .row_addr(chip_row_addr), .bank_addr(chip_bank_addr), .mode_sel(chip_mode_sel),
        .wl_en(chip_wl_en), .write_en(chip_write_en), .sense_en(chip_sense_en),
        .pre_en(chip_pre_en), .clk_en(chip_clk_en), .sel_next(chip_sel_next), .din(chip_din),
        .output_en(chip_output_en), .nv_store(chip_nv_store), .nv_recall(chip_nv_recall),
        .pd_en(chip_pd_en), .sume(chip_sume), .sumo(chip_sumo)
    );
endmodule
