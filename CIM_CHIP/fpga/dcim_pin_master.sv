`timescale 1ns/1ps

// FPGA-side transaction controller for dcim_chip_pin_top.
//
// The chip wrapper intentionally exposes lecture-style control pins.  This
// master converts one start pulse into the multi-cycle pin sequences required
// by four transactions:
//
//   OP_WEIGHT_WRITE : load high/low weight nibbles, then write one cell pair
//   OP_SRAM_READ    : sense one cell pair and receive its eight serial bits
//   OP_CIM_COMPUTE  : send 32 activations bit-serially and receive two 18-bit
//                     accumulator results (even/high and odd/low nibbles)
//   OP_WEIGHT_BURST : program consecutive row/bank locations from a ready/
//                     valid weight stream at three clocks per accepted word
//
// activation_flat stores one byte per local CIM row:
//   activation_flat[(row * 8) +: 8] = activation[row], row = 0..31
//
// activation_is_a8 selects how those bytes are interpreted.  A8 sends all
// eight planes.  A4 sends four zero planes followed by bits [3:0], but still
// uses the chip's native eight-sample accumulator sequence.
//
// This block returns the raw even/odd 18-bit accumulator streams.  For W8,
// the later FPGA backend must reconstruct:
//
//   full_unsigned_result = odd_raw_result + (even_raw_result << 4)
//
// Bias, requantization, activation functions and layer scheduling do not
// belong in this pin-level transaction controller.
module dcim_pin_master (
    input  logic         clk,
    input  logic         rst,

    input  logic         start,
    input  logic [1:0]   operation,
    input  logic [6:0]   command_row_addr,
    input  logic [3:0]   command_bank_addr,
    input  logic [7:0]   command_weight,
    input  logic [255:0] activation_flat,
    input  logic         activation_is_a8,

    // SRAM burst-write command and streaming-data interface.  A burst walks
    // bank 0..15 first, then increments the row.  command_burst_length is the
    // number of eight-bit words and must be 1..2048 without crossing the end
    // of the 128-row x 16-pair address space.  The first stream word may be
    // transferred on the same edge as start.  Later words are prefetched on
    // the preceding cell-write edge, sustaining three clocks per word.
    input  logic [11:0]  command_burst_length,
    input  logic         burst_weight_valid,
    input  logic [7:0]   burst_weight_data,
    output logic         burst_weight_ready,
    output logic [6:0]   burst_weight_row_addr,
    output logic [3:0]   burst_weight_bank_addr,

    output logic         busy,
    output logic         done,
    output logic         result_valid,
    output logic         error,
    output logic [7:0]   sram_read_data,
    output logic [17:0]  even_raw_result,
    output logic [17:0]  odd_raw_result,

    // Direct connections to dcim_chip_pin_top.
    output logic         chip_model_rst_n,
    output logic         chip_reset1,
    output logic         chip_reset2,
    output logic [6:0]   chip_row_addr,
    output logic [3:0]   chip_bank_addr,
    output logic         chip_mode_sel,
    output logic         chip_wl_en,
    output logic         chip_write_en,
    output logic         chip_sense_en,
    output logic         chip_pre_en,
    output logic         chip_clk_en,
    output logic         chip_sel_next,
    output logic [3:0]   chip_din,
    output logic         chip_output_en,
    output logic         chip_nv_store,
    output logic         chip_nv_recall,
    output logic         chip_pd_en,
    input  logic         chip_sume,
    input  logic         chip_sumo
);

    localparam logic [1:0] OP_WEIGHT_WRITE = 2'd0;
    localparam logic [1:0] OP_SRAM_READ    = 2'd1;
    localparam logic [1:0] OP_CIM_COMPUTE  = 2'd2;
    localparam logic [1:0] OP_WEIGHT_BURST = 2'd3;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_WRITE_LOAD_HIGH,
        ST_WRITE_LOAD_LOW,
        ST_WRITE_CELL,
        ST_READ_CAPTURE,
        ST_READ_SHIFT,
        ST_CIM_RESET,
        ST_CIM_LOAD,
        ST_CIM_SAMPLE,
        ST_RESULT_CAPTURE,
        ST_DONE,
        ST_BURST_WAIT_DATA,
        ST_BURST_LOAD_HIGH,
        ST_BURST_LOAD_LOW,
        ST_BURST_WRITE_CELL
    } state_t;

    state_t state;
    state_t next_state;

    logic [1:0]   operation_q;
    logic [6:0]   row_addr_q;
    logic [3:0]   bank_addr_q;
    logic [7:0]   weight_q;
    logic [255:0] activation_q;
    logic         activation_is_a8_q;
    logic         error_q;
    logic [11:0]  burst_remaining_q;

    logic [6:0]   incremented_row_addr;
    logic [3:0]   incremented_bank_addr;
    logic         burst_command_invalid;

    // The input path contains eight four-bit shift stages.  stage_count starts
    // at seven because values for rows 28..31 must enter first and shift to
    // the end before rows 0..3 enter last.
    logic [2:0] stage_count;
    logic [2:0] plane_count;
    logic [2:0] read_bit_count;
    logic [4:0] result_bit_count;

    integer lane_index;

    // Linear address is {row, bank}; bank is the fast-changing dimension.
    // Reject zero length and commands that would wrap beyond address 2047.
    assign burst_command_invalid =
        (command_burst_length == 12'd0) ||
        (({2'b00, command_row_addr, command_bank_addr} +
          {1'b0, command_burst_length}) > 13'd2048);

    always_comb begin
        if (bank_addr_q == 4'd15) begin
            incremented_bank_addr = 4'd0;
            incremented_row_addr  = row_addr_q + 7'd1;
        end else begin
            incremented_bank_addr = bank_addr_q + 4'd1;
            incremented_row_addr  = row_addr_q;
        end
    end

    // These addresses identify the word currently requested from the stream,
    // not necessarily the word being written to the chip on this cycle.  In
    // ST_BURST_WRITE_CELL they point one word ahead for zero-bubble prefetch.
    always_comb begin
        burst_weight_row_addr  = row_addr_q;
        burst_weight_bank_addr = bank_addr_q;

        if ((state == ST_IDLE) && start &&
            (operation == OP_WEIGHT_BURST)) begin
            burst_weight_row_addr  = command_row_addr;
            burst_weight_bank_addr = command_bank_addr;
        end else if ((state == ST_BURST_WRITE_CELL) &&
                     (burst_remaining_q > 12'd1)) begin
            burst_weight_row_addr  = incremented_row_addr;
            burst_weight_bank_addr = incremented_bank_addr;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state                <= ST_IDLE;
            operation_q          <= OP_WEIGHT_WRITE;
            row_addr_q           <= 7'd0;
            bank_addr_q          <= 4'd0;
            weight_q             <= 8'd0;
            activation_q         <= 256'd0;
            activation_is_a8_q   <= 1'b0;
            error_q              <= 1'b0;
            burst_remaining_q    <= 12'd0;
            stage_count          <= 3'd7;
            plane_count          <= 3'd7;
            read_bit_count       <= 3'd7;
            result_bit_count     <= 5'd17;
            sram_read_data       <= 8'd0;
            even_raw_result      <= 18'd0;
            odd_raw_result       <= 18'd0;
        end else begin
            state <= next_state;

            // Commands are accepted only while idle.  All command inputs may
            // change after this edge because local copies are retained.
            if ((state == ST_IDLE) && start) begin
                operation_q        <= operation;
                row_addr_q         <= command_row_addr;
                bank_addr_q        <= command_bank_addr;
                weight_q           <= command_weight;
                activation_q       <= activation_flat;
                activation_is_a8_q <= activation_is_a8;
                error_q            <= (operation == OP_WEIGHT_BURST) &&
                                      burst_command_invalid;
                burst_remaining_q  <= command_burst_length;
                stage_count        <= 3'd7;
                plane_count        <= 3'd7;
                read_bit_count     <= 3'd7;
                result_bit_count   <= 5'd17;
                sram_read_data     <= 8'd0;
                even_raw_result    <= 18'd0;
                odd_raw_result     <= 18'd0;

                // A valid first stream word can be accepted together with
                // the burst command, avoiding a startup wait state.
                if ((operation == OP_WEIGHT_BURST) &&
                    !burst_command_invalid && burst_weight_valid)
                    weight_q <= burst_weight_data;
            end

            case (state)
                ST_CIM_LOAD: begin
                    if (stage_count == 3'd0)
                        stage_count <= 3'd7;
                    else
                        stage_count <= stage_count - 3'd1;
                end

                ST_CIM_SAMPLE: begin
                    if (plane_count != 3'd0)
                        plane_count <= plane_count - 3'd1;
                    else
                        result_bit_count <= 5'd17;
                end

                ST_READ_SHIFT: begin
                    // The chip serializer shifts on this same edge.  With
                    // nonblocking sequential logic this samples the bit that
                    // was visible immediately before the shift: bit 7 first.
                    sram_read_data[read_bit_count] <= chip_sumo;
                    if (read_bit_count != 3'd0)
                        read_bit_count <= read_bit_count - 3'd1;
                end

                ST_RESULT_CAPTURE: begin
                    // The accumulator serializer likewise presents bit 17
                    // first, followed by bit 16 down through bit 0.
                    even_raw_result[result_bit_count] <= chip_sume;
                    odd_raw_result[result_bit_count]  <= chip_sumo;
                    if (result_bit_count != 5'd0)
                        result_bit_count <= result_bit_count - 5'd1;
                end

                ST_BURST_WAIT_DATA: begin
                    if (burst_weight_valid)
                        weight_q <= burst_weight_data;
                end

                ST_BURST_WRITE_CELL: begin
                    if (burst_remaining_q > 12'd1) begin
                        burst_remaining_q <= burst_remaining_q - 12'd1;
                        row_addr_q        <= incremented_row_addr;
                        bank_addr_q       <= incremented_bank_addr;

                        // When valid is high, prefetch the next word on the
                        // same edge that writes the current word.
                        if (burst_weight_valid)
                            weight_q <= burst_weight_data;
                    end else begin
                        burst_remaining_q <= 12'd0;
                    end
                end

                default: begin
                    // State-independent registers retain their values.
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (start) begin
                    case (operation)
                        OP_WEIGHT_WRITE: next_state = ST_WRITE_LOAD_HIGH;
                        // Capture overwrites all eight serializer bits.
                        OP_SRAM_READ:    next_state = ST_READ_CAPTURE;
                        OP_CIM_COMPUTE:  next_state = ST_CIM_RESET;
                        OP_WEIGHT_BURST: begin
                            if (burst_command_invalid)
                                next_state = ST_DONE;
                            else if (burst_weight_valid)
                                next_state = ST_BURST_LOAD_HIGH;
                            else
                                next_state = ST_BURST_WAIT_DATA;
                        end
                    endcase
                end
            end

            ST_WRITE_LOAD_HIGH: next_state = ST_WRITE_LOAD_LOW;
            ST_WRITE_LOAD_LOW:  next_state = ST_WRITE_CELL;
            ST_WRITE_CELL:      next_state = ST_DONE;

            ST_READ_CAPTURE:    next_state = ST_READ_SHIFT;
            ST_READ_SHIFT: begin
                if (read_bit_count == 3'd0)
                    next_state = ST_DONE;
            end

            ST_CIM_RESET:       next_state = ST_CIM_LOAD;
            ST_CIM_LOAD: begin
                if (stage_count == 3'd0)
                    next_state = ST_CIM_SAMPLE;
            end
            ST_CIM_SAMPLE: begin
                if (plane_count == 3'd0)
                    next_state = ST_RESULT_CAPTURE;
                else
                    next_state = ST_CIM_LOAD;
            end
            ST_RESULT_CAPTURE: begin
                if (result_bit_count == 5'd0)
                    next_state = ST_DONE;
            end

            ST_BURST_WAIT_DATA: begin
                if (burst_weight_valid)
                    next_state = ST_BURST_LOAD_HIGH;
            end
            ST_BURST_LOAD_HIGH: next_state = ST_BURST_LOAD_LOW;
            ST_BURST_LOAD_LOW:  next_state = ST_BURST_WRITE_CELL;
            ST_BURST_WRITE_CELL: begin
                if (burst_remaining_q == 12'd1)
                    next_state = ST_DONE;
                else if (burst_weight_valid)
                    next_state = ST_BURST_LOAD_HIGH;
                else
                    next_state = ST_BURST_WAIT_DATA;
            end

            ST_DONE: next_state = ST_IDLE;
            default: next_state = ST_IDLE;
        endcase
    end

    // Moore-style pin control keeps every chip transaction phase explicit.
    // Registered command fields remain stable for the complete transaction.
    always_comb begin
        busy              = (state != ST_IDLE) && (state != ST_DONE);
        done              = (state == ST_DONE);
        result_valid      = (state == ST_DONE) && !error_q &&
                            ((operation_q == OP_SRAM_READ) ||
                             (operation_q == OP_CIM_COMPUTE));
        error             = (state == ST_DONE) && error_q;

        chip_model_rst_n  = ~rst;
        chip_reset1       = rst;
        chip_reset2       = rst;
        chip_row_addr     = row_addr_q;
        chip_bank_addr    = bank_addr_q;
        chip_mode_sel     = 1'b0;
        chip_wl_en        = 1'b0;
        chip_write_en     = 1'b0;
        chip_sense_en     = 1'b0;
        chip_pre_en       = 1'b0;
        chip_clk_en       = 1'b0;
        chip_sel_next     = 1'b0;
        chip_din          = 4'b0000;
        chip_output_en    = 1'b0;
        burst_weight_ready = 1'b0;

        // The present one-FF chip model retains these lecture pins but does
        // not model nonvolatile store/recall or power-domain behavior.
        chip_nv_store     = 1'b0;
        chip_nv_recall    = 1'b0;
        chip_pd_en        = 1'b0;

        case (state)
            ST_WRITE_LOAD_HIGH: begin
                chip_clk_en    = 1'b1;
                chip_din       = weight_q[7:4];
            end

            ST_WRITE_LOAD_LOW: begin
                chip_clk_en    = 1'b1;
                chip_din       = weight_q[3:0];
            end

            ST_WRITE_CELL: begin
                chip_wl_en     = 1'b1;
                chip_write_en  = 1'b1;
                chip_sel_next  = 1'b1;
            end

            ST_READ_CAPTURE: begin
                chip_wl_en     = 1'b1;
                chip_sense_en  = 1'b1;
                chip_pre_en    = 1'b1;
                chip_sel_next  = 1'b1;
            end

            ST_CIM_RESET: begin
                chip_mode_sel  = 1'b1;
                chip_reset1    = 1'b1;
                chip_reset2    = 1'b1;
            end

            ST_CIM_LOAD: begin
                chip_mode_sel  = 1'b1;
                chip_clk_en    = 1'b1;

                // Select four rows from the captured activation vector for
                // the current input-buffer stage and activation bit plane.
                for (lane_index = 0; lane_index < 4; lane_index = lane_index + 1) begin
                    if (activation_is_a8_q || (plane_count < 3'd4))
                        chip_din[lane_index] =
                            activation_q[{stage_count, lane_index[1:0], plane_count}];
                    else
                        chip_din[lane_index] = 1'b0;
                end
            end

            ST_CIM_SAMPLE: begin
                chip_mode_sel  = 1'b1;
                chip_sel_next  = 1'b1;
                chip_output_en = 1'b1;
            end

            ST_RESULT_CAPTURE: begin
                chip_mode_sel  = 1'b1;
                chip_sel_next  = 1'b1;
            end

            ST_BURST_WAIT_DATA: begin
                burst_weight_ready = 1'b1;
            end

            ST_BURST_LOAD_HIGH: begin
                chip_clk_en = 1'b1;
                chip_din    = weight_q[7:4];
            end

            ST_BURST_LOAD_LOW: begin
                chip_clk_en = 1'b1;
                chip_din    = weight_q[3:0];
            end

            ST_BURST_WRITE_CELL: begin
                chip_wl_en     = 1'b1;
                chip_write_en  = 1'b1;
                chip_sel_next  = 1'b1;
                burst_weight_ready = (burst_remaining_q > 12'd1);
            end

            default: begin
                // Defaults describe IDLE, DONE and any recovered bad state.
            end
        endcase

        // Permit the first stream word to handshake with the command itself.
        if ((state == ST_IDLE) && start &&
            (operation == OP_WEIGHT_BURST) && !burst_command_invalid)
            burst_weight_ready = 1'b1;
    end

endmodule
