`timescale 1ns/1ps

// Standalone PYNQ-Z2 top for Method 1: every functional block uses 50 MHz.
// No CDC bridge is required because the self-test controller, pin master and
// digital DCIM chip model share clk_50m.
module dcim_master_chip_top (
    input  logic       sys_clk_125m,
    input  logic       reset_button,
    output logic [3:0] led
);

    logic clk_50m;
    logic clock_locked;
    logic reset_async;
    logic [1:0] reset_release_pipe;
    logic reset_50m;

    logic         master_start;
    logic [1:0]   master_operation;
    logic [6:0]   master_row_addr;
    logic [3:0]   master_bank_addr;
    logic [7:0]   master_weight;
    logic [255:0] master_activation_flat;
    logic         master_activation_is_a8;
    logic [11:0]  master_burst_length;
    logic         master_burst_weight_valid;
    logic [7:0]   master_burst_weight_data;
    logic         master_burst_weight_ready;
    logic [6:0]   master_burst_weight_row_addr;
    logic [3:0]   master_burst_weight_bank_addr;
    logic         master_busy;
    logic         master_done;
    logic         master_result_valid;
    logic         master_error;
    logic [7:0]   master_sram_read_data;
    logic [17:0]  master_even_raw_result;
    logic [17:0]  master_odd_raw_result;

    logic         chip_model_rst_n;
    logic         chip_reset1;
    logic         chip_reset2;
    logic [6:0]   chip_row_addr;
    logic [3:0]   chip_bank_addr;
    logic         chip_mode_sel;
    logic         chip_wl_en;
    logic         chip_write_en;
    logic         chip_sense_en;
    logic         chip_pre_en;
    logic         chip_clk_en;
    logic         chip_sel_next;
    logic [3:0]   chip_din;
    logic         chip_output_en;
    logic         chip_nv_store;
    logic         chip_nv_recall;
    logic         chip_pd_en;
    logic         chip_sume;
    logic         chip_sumo;

    logic test_busy;
    logic test_pass;
    logic test_fail;

    dcim_clock_gen_125_to_50 u_clock_gen (
        .clk_in_125m (sys_clk_125m),
        .reset       (reset_button),
        .clk_out_50m (clk_50m),
        .locked      (clock_locked)
    );

    // Asynchronous assertion protects the design immediately when the button
    // is pressed or the MMCM loses lock.  Deassertion takes two local clocks.
    assign reset_async = reset_button | ~clock_locked;

    always_ff @(posedge clk_50m or posedge reset_async) begin
        if (reset_async)
            reset_release_pipe <= 2'b11;
        else
            reset_release_pipe <= {reset_release_pipe[0], 1'b0};
    end

    assign reset_50m = reset_release_pipe[1];

    dcim_board_self_test u_self_test (
        .clk                       (clk_50m),
        .rst                       (reset_50m),
        .master_start              (master_start),
        .master_operation          (master_operation),
        .master_row_addr           (master_row_addr),
        .master_bank_addr          (master_bank_addr),
        .master_weight             (master_weight),
        .master_activation_flat    (master_activation_flat),
        .master_activation_is_a8   (master_activation_is_a8),
        .master_burst_length       (master_burst_length),
        .master_burst_weight_valid (master_burst_weight_valid),
        .master_burst_weight_data  (master_burst_weight_data),
        .master_burst_weight_ready (master_burst_weight_ready),
        .master_burst_weight_row_addr(master_burst_weight_row_addr),
        .master_burst_weight_bank_addr(master_burst_weight_bank_addr),
        .master_busy               (master_busy),
        .master_done               (master_done),
        .master_result_valid       (master_result_valid),
        .master_error              (master_error),
        .master_sram_read_data     (master_sram_read_data),
        .master_even_raw_result    (master_even_raw_result),
        .master_odd_raw_result     (master_odd_raw_result),
        .test_busy                 (test_busy),
        .test_pass                 (test_pass),
        .test_fail                 (test_fail)
    );

    dcim_pin_master u_pin_master (
        .clk                       (clk_50m),
        .rst                       (reset_50m),
        .start                     (master_start),
        .operation                 (master_operation),
        .command_row_addr          (master_row_addr),
        .command_bank_addr         (master_bank_addr),
        .command_weight            (master_weight),
        .activation_flat           (master_activation_flat),
        .activation_is_a8          (master_activation_is_a8),
        .command_burst_length      (master_burst_length),
        .burst_weight_valid        (master_burst_weight_valid),
        .burst_weight_data         (master_burst_weight_data),
        .burst_weight_ready        (master_burst_weight_ready),
        .burst_weight_row_addr     (master_burst_weight_row_addr),
        .burst_weight_bank_addr    (master_burst_weight_bank_addr),
        .busy                      (master_busy),
        .done                      (master_done),
        .result_valid              (master_result_valid),
        .error                     (master_error),
        .sram_read_data            (master_sram_read_data),
        .even_raw_result           (master_even_raw_result),
        .odd_raw_result            (master_odd_raw_result),
        .chip_model_rst_n          (chip_model_rst_n),
        .chip_reset1               (chip_reset1),
        .chip_reset2               (chip_reset2),
        .chip_row_addr             (chip_row_addr),
        .chip_bank_addr            (chip_bank_addr),
        .chip_mode_sel             (chip_mode_sel),
        .chip_wl_en                (chip_wl_en),
        .chip_write_en             (chip_write_en),
        .chip_sense_en             (chip_sense_en),
        .chip_pre_en               (chip_pre_en),
        .chip_clk_en               (chip_clk_en),
        .chip_sel_next             (chip_sel_next),
        .chip_din                  (chip_din),
        .chip_output_en            (chip_output_en),
        .chip_nv_store             (chip_nv_store),
        .chip_nv_recall            (chip_nv_recall),
        .chip_pd_en                (chip_pd_en),
        .chip_sume                 (chip_sume),
        .chip_sumo                 (chip_sumo)
    );

    (* DONT_TOUCH = "TRUE" *) dcim_chip_pin_top u_chip (
        .clk          (clk_50m),
        .model_rst_n  (chip_model_rst_n),
        .reset1       (chip_reset1),
        .reset2       (chip_reset2),
        .row_addr     (chip_row_addr),
        .bank_addr    (chip_bank_addr),
        .mode_sel     (chip_mode_sel),
        .wl_en        (chip_wl_en),
        .write_en     (chip_write_en),
        .sense_en     (chip_sense_en),
        .pre_en       (chip_pre_en),
        .clk_en       (chip_clk_en),
        .sel_next     (chip_sel_next),
        .din          (chip_din),
        .output_en    (chip_output_en),
        .nv_store     (chip_nv_store),
        .nv_recall    (chip_nv_recall),
        .pd_en        (chip_pd_en),
        .sume         (chip_sume),
        .sumo         (chip_sumo)
    );

    // PYNQ-Z2 LED0..LED3: lock, busy, pass and fail respectively.
    assign led[0] = clock_locked;
    assign led[1] = test_busy;
    assign led[2] = test_pass;
    assign led[3] = test_fail;

endmodule
