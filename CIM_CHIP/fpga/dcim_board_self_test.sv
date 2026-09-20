`timescale 1ns/1ps

// Autonomous board-level test source for dcim_pin_master.
//
// The controller burst-writes and individually reads all 128 rows x 16 bank
// pairs so synthesis cannot reduce the test to one fixed address.  It then
// performs one A8W8 calculation over local rows 0..31.
module dcim_board_self_test (
    input  logic         clk,
    input  logic         rst,

    output logic         master_start,
    output logic [1:0]   master_operation,
    output logic [6:0]   master_row_addr,
    output logic [3:0]   master_bank_addr,
    output logic [7:0]   master_weight,
    output logic [255:0] master_activation_flat,
    output logic         master_activation_is_a8,
    output logic [11:0]  master_burst_length,
    output logic         master_burst_weight_valid,
    output logic [7:0]   master_burst_weight_data,

    input  logic         master_burst_weight_ready,
    input  logic [6:0]   master_burst_weight_row_addr,
    input  logic [3:0]   master_burst_weight_bank_addr,

    input  logic         master_busy,
    input  logic         master_done,
    input  logic         master_result_valid,
    input  logic         master_error,
    input  logic [7:0]   master_sram_read_data,
    input  logic [17:0]  master_even_raw_result,
    input  logic [17:0]  master_odd_raw_result,

    output logic         test_busy,
    output logic         test_pass,
    output logic         test_fail
);

    localparam logic [1:0] OP_WEIGHT_WRITE = 2'd0;
    localparam logic [1:0] OP_SRAM_READ    = 2'd1;
    localparam logic [1:0] OP_CIM_COMPUTE  = 2'd2;
    localparam logic [1:0] OP_WEIGHT_BURST = 2'd3;

    // Golden result for rows 0..31, activation[row]=row+1 and bank pair 0:
    //   even = sum(activation * weight[7:4]) = 4640
    //   odd  = sum(activation * weight[3:0]) = 1112
    localparam logic [17:0] GOLDEN_EVEN = 18'd4640;
    localparam logic [17:0] GOLDEN_ODD  = 18'd1112;

    typedef enum logic [3:0] {
        ST_WRITE_LAUNCH,
        ST_WRITE_WAIT,
        ST_READ_LAUNCH,
        ST_READ_WAIT,
        ST_COMPUTE_LAUNCH,
        ST_COMPUTE_WAIT,
        ST_PASS,
        ST_FAIL
    } state_t;

    state_t state;
    logic [6:0] row_counter;
    logic [3:0] bank_counter;
    integer activation_index;

    function automatic logic [7:0] test_weight_pattern (
        input logic [6:0] row_value,
        input logic [3:0] bank_value
    );
        begin
            test_weight_pattern = {
                row_value[3:0] ^ bank_value,
                row_value[6:3] ^ bank_value
            };
        end
    endfunction

    // Constant A8 vector used by the final CIM test.
    always_comb begin
        master_activation_flat = 256'd0;
        for (activation_index = 0; activation_index < 32;
            activation_index = activation_index + 1) begin
            master_activation_flat[(activation_index * 8) +: 8] =
                activation_index[7:0] + 8'd1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= ST_WRITE_LAUNCH;
            row_counter  <= 7'd0;
            bank_counter <= 4'd0;
        end else begin
            case (state)
                ST_WRITE_LAUNCH: begin
                    if (!master_busy)
                        state <= ST_WRITE_WAIT;
                end

                ST_WRITE_WAIT: begin
                    if (master_done) begin
                        if (master_error) begin
                            state <= ST_FAIL;
                        end else begin
                            row_counter  <= 7'd0;
                            bank_counter <= 4'd0;
                            state        <= ST_READ_LAUNCH;
                        end
                    end
                end

                ST_READ_LAUNCH: begin
                    if (!master_busy)
                        state <= ST_READ_WAIT;
                end

                ST_READ_WAIT: begin
                    if (master_done) begin
                        if (master_error || !master_result_valid ||
                            (master_sram_read_data !=
                             test_weight_pattern(row_counter, bank_counter))) begin
                            state <= ST_FAIL;
                        end else if ((row_counter == 7'd127) &&
                                     (bank_counter == 4'd15)) begin
                            row_counter  <= 7'd0;
                            bank_counter <= 4'd0;
                            state        <= ST_COMPUTE_LAUNCH;
                        end else if (bank_counter == 4'd15) begin
                            row_counter  <= row_counter + 7'd1;
                            bank_counter <= 4'd0;
                            state        <= ST_READ_LAUNCH;
                        end else begin
                            bank_counter <= bank_counter + 4'd1;
                            state        <= ST_READ_LAUNCH;
                        end
                    end
                end

                ST_COMPUTE_LAUNCH: begin
                    if (!master_busy)
                        state <= ST_COMPUTE_WAIT;
                end

                ST_COMPUTE_WAIT: begin
                    if (master_done) begin
                        if (master_error || !master_result_valid ||
                            (master_even_raw_result != GOLDEN_EVEN) ||
                            (master_odd_raw_result != GOLDEN_ODD))
                            state <= ST_FAIL;
                        else
                            state <= ST_PASS;
                    end
                end

                ST_PASS: state <= ST_PASS;
                ST_FAIL: state <= ST_FAIL;
                default: state <= ST_FAIL;
            endcase
        end
    end

    always_comb begin
        master_start            = 1'b0;
        master_operation        = OP_WEIGHT_WRITE;
        master_row_addr         = row_counter;
        master_bank_addr        = bank_counter;
        master_weight           = test_weight_pattern(row_counter,
                                                       bank_counter);
        master_activation_is_a8 = 1'b1;
        master_burst_length      = 12'd2048;
        master_burst_weight_valid = 1'b0;
        master_burst_weight_data =
            test_weight_pattern(master_burst_weight_row_addr,
                                master_burst_weight_bank_addr);

        test_busy = 1'b1;
        test_pass = 1'b0;
        test_fail = 1'b0;

        case (state)
            ST_WRITE_LAUNCH: begin
                master_start     = !master_busy;
                master_operation = OP_WEIGHT_BURST;
                master_row_addr  = 7'd0;
                master_bank_addr = 4'd0;
                master_burst_weight_valid = 1'b1;
            end

            ST_WRITE_WAIT: begin
                // The requested address advances only on a valid/ready
                // transfer, so a future data source may insert stalls safely.
                master_burst_weight_valid = 1'b1;
            end

            ST_READ_LAUNCH: begin
                master_start     = !master_busy;
                master_operation = OP_SRAM_READ;
            end

            ST_COMPUTE_LAUNCH: begin
                master_start     = !master_busy;
                master_operation = OP_CIM_COMPUTE;
                master_row_addr  = 7'd0;
                master_bank_addr = 4'd0;
            end

            ST_PASS: begin
                test_busy = 1'b0;
                test_pass = 1'b1;
            end

            ST_FAIL: begin
                test_busy = 1'b0;
                test_fail = 1'b1;
            end

            default: begin
                // Wait states retain the command values but do not pulse start.
            end
        endcase
    end

endmodule
