`timescale 1ns/1ps
// One LINEAR vector or one 3x3xC PATCH per command.
// RAM contract: exclusive fixed one-edge synchronous read, same clk/reset.
// DDR/variable-latency RAM requires a separate adapter, not this interface.
module activation_reader (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input kws_system_pkg::activation_read_mode_t cmd_mode,
    input kws_system_pkg::activation_addr_t cmd_base,
    input kws_system_pkg::activation_count_t cmd_count,
    input logic [7:0] cmd_width, cmd_height,
    input logic [5:0] cmd_channels,
    input logic [7:0] cmd_x, cmd_y,
    output logic ram_rd_en,
    output kws_system_pkg::activation_addr_t ram_rd_addr,
    input logic ram_rd_valid,
    input kws_system_pkg::activation_t ram_rd_data,
    output logic out_valid,
    input logic out_ready,
    output kws_system_pkg::activation_t out_data,
    output logic out_last,
    output logic busy, done, error
);
    import kws_system_pkg::*;

    // 1. Command and address-generator registers.
    typedef enum logic [1:0] {IDLE, CONFIG, ISSUE, DRAIN} state_t;
    state_t state;
    logic [1:0] config_phase;
    activation_read_mode_t mode_q;
    activation_addr_t base_q;
    activation_count_t count_q, total_count, issued_count;
    logic [7:0] width_q, height_q, x_q, y_q;
    logic [5:0] channels_q;
    logic [15:0] plane_stride;
    logic [31:0] source_size, start_address;
    logic [15:0] channel_start, row_start, current_address;
    logic [1:0] kernel_x, kernel_y;
    logic config_invalid;

    // 2. Two response slots. reserved_count includes both buffered responses
    // and the request whose response has not yet entered the FIFO.
    activation_t response_data [0:1];
    logic response_last [0:1];
    logic read_pointer, write_pointer;
    logic [1:0] buffered_count, reserved_count;
    logic pending_valid, pending_last;
    wire output_fire = out_valid && out_ready;
    wire response_fire = !rst && ram_rd_valid && pending_valid;
    wire request_last = issued_count == total_count - 16'd1;

    assign cmd_ready = !rst && state == IDLE;
    assign busy = state != IDLE;
    assign out_valid = !rst && buffered_count != 0;
    assign out_data = response_data[read_pointer];
    assign out_last = response_last[read_pointer];
    assign ram_rd_addr = activation_addr_t'(current_address);
    // A simultaneous downstream acceptance releases a slot on this edge.
    assign ram_rd_en = !rst && state == ISSUE &&
                       (reserved_count < 2 || output_fire);

    always_comb begin
        config_invalid = source_size == 0 || start_address >= 32'(ACT_DEPTH) ||
                         (32'(base_q) + source_size > 32'(ACT_DEPTH));
        if (mode_q == READ_PATCH)
            config_invalid = config_invalid || width_q < 3 || height_q < 3 ||
                             channels_q == 0 ||
                             (9'(x_q) + 9'd3 > 9'(width_q)) ||
                             (9'(y_q) + 9'd3 > 9'(height_q));
    end

    // 3. RAM response alignment and elastic output FIFO.
    // Payload does not need reset. Valid/count/pointers define ownership.
    always_ff @(posedge clk) begin
        if (rst) begin
            pending_valid <= 0; pending_last <= 0;
            buffered_count <= 0; reserved_count <= 0;
            read_pointer <= 0; write_pointer <= 0;
        end else begin
            pending_valid <= ram_rd_en;
            if (ram_rd_en) pending_last <= request_last;
            case ({ram_rd_en, output_fire})
                2'b10: reserved_count <= reserved_count + 1'b1;
                2'b01: reserved_count <= reserved_count - 1'b1;
                default: ;
            endcase
            case ({response_fire, output_fire})
                2'b10: buffered_count <= buffered_count + 1'b1;
                2'b01: buffered_count <= buffered_count - 1'b1;
                default: ;
            endcase
            if (response_fire) begin
                response_data[write_pointer] <= ram_rd_data;
                response_last[write_pointer] <= pending_last;
                write_pointer <= ~write_pointer;
            end
            if (output_fire) read_pointer <= ~read_pointer;
        end
    end

    // 4. Command FSM. Multiplication is confined to CONFIG; ISSUE uses adds.
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; config_phase <= 0;
            mode_q <= READ_LINEAR; base_q <= 0; count_q <= 0;
            width_q <= 0; height_q <= 0; channels_q <= 0; x_q <= 0; y_q <= 0;
            plane_stride <= 0; source_size <= 0; start_address <= 0;
            total_count <= 0; issued_count <= 0;
            channel_start <= 0; row_start <= 0; current_address <= 0;
            kernel_x <= 0; kernel_y <= 0;
            done <= 0; error <= 0;
        end else begin
            done <= 0; error <= 0;
            case (state)
                IDLE: if (cmd_valid) begin
                    mode_q <= cmd_mode; base_q <= cmd_base; count_q <= cmd_count;
                    width_q <= cmd_width; height_q <= cmd_height; channels_q <= cmd_channels;
                    x_q <= cmd_x; y_q <= cmd_y;
                    issued_count <= 0; kernel_x <= 0; kernel_y <= 0;
                    config_phase <= 0; state <= CONFIG;
                end
                CONFIG: case (config_phase)
                    0: begin
                        plane_stride <= 16'(width_q) * 16'(height_q);
                        start_address <= mode_q == READ_PATCH
                            ? 32'(base_q) + 32'(y_q) * 32'(width_q) + 32'(x_q)
                            : 32'(base_q);
                        config_phase <= 1;
                    end
                    1: begin
                        source_size <= mode_q == READ_PATCH
                            ? 32'(plane_stride) * 32'(channels_q) : 32'(count_q);
                        total_count <= mode_q == READ_PATCH ? 16'(channels_q) * 16'd9 : count_q;
                        config_phase <= 2;
                    end
                    default: begin
                        if (config_invalid) begin
                            error <= 1; state <= IDLE;
                        end else begin
                            channel_start <= 16'(start_address);
                            row_start <= 16'(start_address);
                            current_address <= 16'(start_address);
                            state <= ISSUE;
                        end
                    end
                endcase
                ISSUE: if (ram_rd_en) begin
                    issued_count <= issued_count + 1'b1;
                    if (request_last) state <= DRAIN;
                    else if (mode_q == READ_LINEAR) current_address <= current_address + 1'b1;
                    else if (kernel_x < 2) begin
                        kernel_x <= kernel_x + 1'b1;
                        current_address <= current_address + 1'b1;
                    end else if (kernel_y < 2) begin
                        kernel_x <= 0; kernel_y <= kernel_y + 1'b1;
                        row_start <= row_start + 16'(width_q);
                        current_address <= row_start + 16'(width_q);
                    end else begin
                        kernel_x <= 0; kernel_y <= 0;
                        channel_start <= channel_start + plane_stride;
                        row_start <= channel_start + plane_stride;
                        current_address <= channel_start + plane_stride;
                    end
                end
                DRAIN: if (output_fire && out_last) begin
                    done <= 1; state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

    // Integration-contract checks only; not extra synthesized hardware.
    // synthesis translate_off
    always @(posedge clk) begin
        if (!rst) begin
            if (ram_rd_valid != pending_valid) $fatal(1,"Reader RAM latency/ownership mismatch");
            if (reserved_count > 2 || buffered_count > reserved_count)
                $fatal(1,"Reader response capacity violated");
            if (output_fire && out_last && (reserved_count != 1 || state != DRAIN))
                $fatal(1,"Reader last output before pipeline drained");
        end
    end
    // synthesis translate_on
endmodule
