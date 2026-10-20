`timescale 1ns/1ps
// S5-A: fixed Conv2/3 geometry, K=108, 12 filters, UINT8 zp128, no bias.
// Weight stream order: filter -> input channel -> kernel row -> kernel col.
// One outstanding command. Connect cmd/rsp to dcim_cdc_bridge in S5-B.
// All resets must also reset the transport/master/chip: no unilateral abort.
module kws_dcim_backend (
    input logic clk, rst,
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
    input logic source_error,

    output logic cmd_valid,
    input logic cmd_ready,
    output logic [1:0] cmd_operation,
    output logic [6:0] cmd_row_addr,
    output logic [3:0] cmd_bank_addr,
    output logic [7:0] cmd_weight,
    output logic [255:0] cmd_activation_flat,
    output logic cmd_activation_is_a8,
    input logic rsp_valid,
    output logic rsp_ready,
    input logic rsp_data_valid, rsp_error,
    input logic [17:0] rsp_even_raw_result, rsp_odd_raw_result
);
    typedef enum logic [3:0] {
        IDLE, W_PREPARE, W_SEND, W_WAIT, A_FILL,
        C_SEND, C_WAIT, EMIT, FAULT
    } state_t;
    state_t state;

    logic [6:0] weight_row;
    logic [3:0] weight_filter, pair_index, emit_index;
    logic [1:0] group_index;
    logic [4:0] fill_index;
    logic [7:0] write_byte;
    logic [7:0] tile [0:31];
    // Maximum sum: 32*255=8160, fits unsigned 13 bits.
    logic [12:0] weight_sum [0:3][0:11];
    logic [12:0] activation_sum;
    logic signed [31:0] partial_acc [0:11];
    logic correction_pending, correction_in_valid, correction_valid;
    logic correction_overflow;
    logic signed [31:0] corrected_value;
    logic [31:0] unsigned_mac;
    logic signed [32:0] extended_acc;
    logic enabled;

    assign enabled = !rst && !source_error && state != FAULT;
    assign busy = state != IDLE;
    assign error = state == FAULT;
    // Load wins if both requests are asserted; patch is not accepted.
    assign load_ready = enabled && state == IDLE;
    assign patch_ready = enabled && state == IDLE && weights_ready && !load_valid;
    assign weight_ready = enabled && state == W_PREPARE && weight_row < 7'd108;
    assign activation_ready = enabled && state == A_FILL;
    assign result_valid = enabled && state == EMIT;
    assign filter_id = emit_index;
    assign result_data = partial_acc[emit_index];
    assign result_last = emit_index == 4'd11;

    assign cmd_valid = enabled && (state == W_SEND || state == C_SEND);
    assign cmd_operation = state == W_SEND ? 2'd0 : 2'd2;
    assign cmd_row_addr = state == W_SEND ? weight_row : {group_index,5'b0};
    assign cmd_bank_addr = state == W_SEND ? weight_filter : pair_index;
    assign cmd_weight = write_byte;
    assign cmd_activation_is_a8 = 1'b1;
    for (genvar r=0; r<32; r=r+1) begin : gen_tile_bus
        assign cmd_activation_flat[r*8 +: 8] = tile[r];
    end
    assign rsp_ready = enabled && (state == W_WAIT ||
                                 (state == C_WAIT && !correction_pending));
    assign unsigned_mac = {14'd0,rsp_odd_raw_result} +
                          ({14'd0,rsp_even_raw_result} << 4);
    assign correction_in_valid = rsp_valid && rsp_ready && state == C_WAIT &&
                                 !rsp_error && rsp_data_valid;
    dcim_u8_offset_correction u_correction (
        .clk(clk), .rst(rst), .in_valid(correction_in_valid),
        .unsigned_mac(unsigned_mac), .activation_sum({19'd0,activation_sum}),
        .offset_weight_sum({19'd0,weight_sum[group_index][pair_index]}),
        .term_count(16'd32), .out_valid(correction_valid),
        .accumulator(corrected_value), .overflow(correction_overflow)
    );
    assign extended_acc = $signed({partial_acc[pair_index][31],partial_acc[pair_index]})
                        + $signed({corrected_value[31],corrected_value});

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            load_done <= 0; patch_done <= 0; weights_ready <= 0;
            weight_row <= 0; weight_filter <= 0; write_byte <= 0;
            pair_index <= 0; group_index <= 0; fill_index <= 0; emit_index <= 0;
            activation_sum <= 0; correction_pending <= 0;
            for (integer g=0; g<4; g=g+1)
                for (integer f=0; f<12; f=f+1) weight_sum[g][f] <= 0;
            for (integer f=0; f<12; f=f+1) partial_acc[f] <= 0;
            for (integer r=0; r<32; r=r+1) tile[r] <= 0;
        end else begin
            load_done <= 0;
            patch_done <= 0;
            if (source_error) begin
                state <= FAULT;
                weights_ready <= 0;
            end else begin
                case (state)
                    IDLE: begin
                        if (load_valid && load_ready) begin
                            weights_ready <= 0;
                            weight_row <= 0; weight_filter <= 0;
                            for (integer g=0; g<4; g=g+1)
                                for (integer f=0; f<12; f=f+1) weight_sum[g][f] <= 0;
                            state <= W_PREPARE;
                        end else if (patch_valid && patch_ready) begin
                            for (integer f=0; f<12; f=f+1) partial_acc[f] <= 0;
                            group_index <= 0; pair_index <= 0; fill_index <= 0;
                            emit_index <= 0; activation_sum <= 0;
                            correction_pending <= 0;
                            state <= A_FILL;
                        end
                    end
                    W_PREPARE: begin
                        if (weight_row >= 7'd108) begin
                            write_byte <= 8'd128;
                            state <= W_SEND;
                        end else if (weight_valid && weight_ready) begin
                            // INT8 +128 is exactly an MSB toggle in 8-bit encoding.
                            write_byte <= {~weight_data[7],weight_data[6:0]};
                            state <= W_SEND;
                        end
                    end
                    W_SEND: if (cmd_valid && cmd_ready) state <= W_WAIT;
                    W_WAIT: if (rsp_valid && rsp_ready) begin
                        if (rsp_error) begin state <= FAULT; weights_ready <= 0; end
                        else begin
                            // Write completion need not assert rsp_data_valid.
                            weight_sum[weight_row[6:5]][weight_filter] <=
                                weight_sum[weight_row[6:5]][weight_filter] + {5'd0,write_byte};
                            if (weight_row == 7'd127) begin
                                weight_row <= 0;
                                if (weight_filter == 4'd11) begin
                                    weights_ready <= 1;
                                    load_done <= 1;
                                    state <= IDLE;
                                end else begin
                                    weight_filter <= weight_filter + 1'b1;
                                    state <= W_PREPARE;
                                end
                            end else begin
                                weight_row <= weight_row + 1'b1;
                                state <= W_PREPARE;
                            end
                        end
                    end
                    A_FILL: if (activation_valid && activation_ready) begin
                        tile[fill_index] <= activation_data;
                        activation_sum <= activation_sum + {5'd0,activation_data};
                        if ((group_index == 2'd3 && fill_index == 5'd11) ||
                            fill_index == 5'd31) begin
                            pair_index <= 0;
                            state <= C_SEND;
                        end else fill_index <= fill_index + 1'b1;
                    end
                    C_SEND: if (cmd_valid && cmd_ready) begin
                        correction_pending <= 0;
                        state <= C_WAIT;
                    end
                    C_WAIT: begin
                        if (rsp_valid && rsp_ready) begin
                            if (rsp_error || !rsp_data_valid) begin
                                state <= FAULT; weights_ready <= 0;
                            end else correction_pending <= 1;
                        end
                        if (correction_pending && correction_valid) begin
                            // Legal K=108 INT8 dot products fit INT32:
                            // abs(partial sum) <= 108*128*128 = 1769472.
                            // Keep correction faults, but do not gate tile/state
                            // updates with the cross-group adder overflow bit.
                            if (correction_overflow) begin
                                state <= FAULT; weights_ready <= 0;
                            end else begin
                                partial_acc[pair_index] <= extended_acc[31:0];
                                correction_pending <= 0;
                                if (pair_index != 4'd11) begin
                                    pair_index <= pair_index + 1'b1;
                                    state <= C_SEND;
                                end else if (group_index != 2'd3) begin
                                    group_index <= group_index + 1'b1;
                                    fill_index <= 0;
                                    if (group_index == 2'd2) begin
                                        // Next group has 12 real entries. No padding-fill FSM.
                                        for (integer r=12; r<32; r=r+1) tile[r] <= 8'd128;
                                        activation_sum <= 13'd2560;
                                    end else activation_sum <= 0;
                                    state <= A_FILL;
                                end else begin
                                    emit_index <= 0;
                                    state <= EMIT;
                                end
                            end
                        end
                    end
                    EMIT: if (result_valid && result_ready) begin
                        if (emit_index == 4'd11) begin
                            patch_done <= 1;
                            state <= IDLE;
                        end else emit_index <= emit_index + 1'b1;
                    end
                    FAULT: weights_ready <= 0;
                    default: begin state <= FAULT; weights_ready <= 0; end
                endcase
            end
        end
    end
endmodule
