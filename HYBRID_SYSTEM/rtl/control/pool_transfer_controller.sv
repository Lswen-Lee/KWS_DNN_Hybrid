`timescale 1ns/1ps
// Control only: the integration module owns data wiring and RAM arbitration.
module pool_transfer_controller (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [14:0] cmd_src_base, cmd_dst_base,
    input logic [7:0] cmd_width, cmd_height,
    input logic [5:0] cmd_channels,
    output logic reader_cmd_valid,
    input logic reader_cmd_ready, reader_done, reader_error,
    output logic [14:0] reader_base,
    output logic [15:0] reader_count,
    output logic writer_cmd_valid,
    input logic writer_cmd_ready, writer_in_ready, writer_done, writer_error,
    output logic [14:0] writer_base,
    output logic [15:0] writer_count,
    input logic reader_out_valid,
    output logic reader_out_ready,
    output logic pool_in_valid, pool_frame_start,
    output logic [7:0] pool_width, pool_height,
    output logic [4:0] pool_channels,
    input logic pool_out_valid,
    output logic busy, done, error, fault
);
    typedef enum logic [2:0] {
        IDLE, CONFIG, START_WRITER, WAIT_WRITER_READY,
        START_READER, RUN, DRAIN, FAULT
    } state_t;
    state_t state;
    logic [1:0] config_phase;
    logic [5:0] channels_q;
    logic [15:0] input_area, output_area;
    logic [31:0] input_total, output_total, source_end, destination_end;
    logic reader_done_seen, writer_done_seen, first_pixel;
    wire active_stream = state == RUN || state == DRAIN;
    wire runtime_error = reader_error || writer_error ||
                         (pool_out_valid && !writer_in_ready);

    assign cmd_ready = !rst && state == IDLE;
    assign busy = state != IDLE;
    assign fault = state == FAULT;
    assign reader_cmd_valid = !rst && state == START_READER;
    assign writer_cmd_valid = !rst && state == START_WRITER;
    assign reader_count = 16'(input_total);
    assign writer_count = 16'(output_total);
    assign pool_channels = channels_q[4:0];
    assign source_end = 32'(reader_base) + input_total;
    assign destination_end = 32'(writer_base) + output_total;
    // Do NOT gate this with writer_in_ready: writer can finish before odd tails.
    assign reader_out_ready = !rst && active_stream && !runtime_error;
    assign pool_in_valid = reader_out_valid && reader_out_ready;
    assign pool_frame_start = pool_in_valid && first_pixel;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; config_phase <= 0;
            reader_base <= 0; writer_base <= 0;
            pool_width <= 0; pool_height <= 0; channels_q <= 0;
            input_area <= 0; output_area <= 0; input_total <= 0; output_total <= 0;
            reader_done_seen <= 0; writer_done_seen <= 0; first_pixel <= 0;
            done <= 0; error <= 0;
        end else begin
            done <= 0; error <= 0;
            if (reader_done) reader_done_seen <= 1;
            if (writer_done) writer_done_seen <= 1;
            if (pool_in_valid) first_pixel <= 0;
            // A child may still own transactions on a runtime failure.
            // Remain locked until a shared reset; never restart only this FSM.
            if (state != IDLE && state != CONFIG && state != FAULT && runtime_error) begin
                state <= FAULT;
                error <= 1;
            end else case (state)
                IDLE: if (cmd_valid) begin
                    reader_base <= cmd_src_base; writer_base <= cmd_dst_base;
                    pool_width <= cmd_width; pool_height <= cmd_height; channels_q <= cmd_channels;
                    reader_done_seen <= 0; writer_done_seen <= 0; first_pixel <= 1;
                    config_phase <= 0; state <= CONFIG;
                end
                CONFIG: case (config_phase)
                    0: begin
                        input_area <= 16'(pool_width) * 16'(pool_height);
                        output_area <= 16'(pool_width >> 1) * 16'(pool_height >> 1);
                        config_phase <= 1;
                    end
                    1: begin
                        input_total <= 32'(input_area) * 32'(channels_q);
                        output_total <= 32'(output_area) * 32'(channels_q);
                        config_phase <= 2;
                    end
                    default: begin
                        if (pool_width < 2 || pool_width > 126 || pool_height < 2 ||
                            channels_q == 0 || channels_q > 31 ||
                            source_end > 32768 || destination_end > 32768 ||
                            (32'(reader_base) < destination_end && 32'(writer_base) < source_end)) begin
                            error <= 1; state <= IDLE;
                        end else state <= START_WRITER;
                    end
                endcase
                START_WRITER: if (writer_cmd_ready) state <= WAIT_WRITER_READY;
                WAIT_WRITER_READY: if (writer_in_ready) state <= START_READER;
                START_READER: if (reader_cmd_ready) state <= RUN;
                RUN: if (reader_done_seen || reader_done) state <= DRAIN;
                DRAIN: if ((reader_done_seen || reader_done) && (writer_done_seen || writer_done)) begin
                    done <= 1; state <= IDLE;
                end
                FAULT: ;
                default: state <= FAULT;
            endcase
        end
    end
endmodule
