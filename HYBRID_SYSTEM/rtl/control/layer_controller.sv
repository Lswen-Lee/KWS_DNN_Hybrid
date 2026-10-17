`timescale 1ns/1ps
// S5-D1 sequencer. Bytes bypass this module; it owns the path for the WHOLE run.
// Request handshake means the source accepts the request, not load completion.
// Only registered path terminal pulses advance the operation index.
module layer_controller (
    input logic clk, rst,
    input logic start_valid,
    output logic start_ready,
    input kws_system_pkg::inference_mode_t run_mode,
    output logic busy, done, error,
    output kws_system_pkg::layer_error_t error_code,
    output logic [3:0] current_op,
    output logic op_done,
    output logic input_request_valid,
    input logic input_request_ready,
    output logic input_is_flatten,
    output logic [15:0] input_count,
    output logic weight_request_valid,
    input logic weight_request_ready,
    input logic source_error,
    output kws_system_pkg::layer_descriptor_t active_descriptor,
    output logic input_stream_enable, weight_stream_enable,
    output logic load_valid,
    input logic load_ready, load_done, load_error,
    output logic weight_load_valid,
    input logic weight_load_ready, weight_load_done, weight_load_error,
    output logic pe_cmd_valid,
    input logic pe_cmd_ready, pe_done, pe_error,
    output logic dcim_cmd_valid,
    input logic dcim_cmd_ready, dcim_done, dcim_error,
    output logic pool_valid,
    input logic pool_ready, pool_done, pool_error,
    output logic classify_valid, classify_active,
    input logic classify_ready, classify_done, classify_error,
    input logic path_busy, path_fault
);
    import kws_system_pkg::*;
    typedef enum logic [4:0] {
        IDLE, CHECK_RUN, REQUEST_INPUT, ISSUE_INPUT_LOAD, WAIT_INPUT,
        FETCH_DESC, CHECK_DESC, REQUEST_WEIGHT, ISSUE_WEIGHT_LOAD, WAIT_WEIGHT,
        ISSUE_OPERATION, WAIT_OPERATION, ADVANCE, COMPLETE, FAILED,
        CLASSIFY_REQUEST, CLASSIFY_WAIT
    } state_t;
    state_t state;
    inference_mode_t mode_q;
    logic [3:0] last_op;
    layer_descriptor_t rom_descriptor;
    logic rom_valid, descriptor_valid_q, enabled;
    logic operation_error, operation_done;
    layer_descriptor_rom descriptors (
        .op_index(current_op), .descriptor(rom_descriptor), .descriptor_valid(rom_valid)
    );
    assign busy = state != IDLE;
    assign start_ready = !rst && state == IDLE && !path_busy && !path_fault;
    // Kill new commands/stream handshakes immediately on a reported fault.
    assign enabled = !rst && !source_error && !path_fault && state != FAILED;
    assign input_request_valid = enabled && state == REQUEST_INPUT;
    assign weight_request_valid = enabled && state == REQUEST_WEIGHT;
    assign input_is_flatten = mode_q == RUN_FC_TAIL;
    assign input_count = input_is_flatten ? 16'd144 : 16'd8064;
    assign load_valid = enabled && state == ISSUE_INPUT_LOAD;
    assign weight_load_valid = enabled && state == ISSUE_WEIGHT_LOAD;
    assign input_stream_enable = enabled && state == WAIT_INPUT;
    assign weight_stream_enable = enabled && state == WAIT_WEIGHT;
    assign pe_cmd_valid = enabled && state == ISSUE_OPERATION && active_descriptor.backend == BACKEND_PE;
    assign dcim_cmd_valid = enabled && state == ISSUE_OPERATION && active_descriptor.backend == BACKEND_DCIM;
    assign pool_valid = enabled && state == ISSUE_OPERATION && active_descriptor.backend == BACKEND_POOL;
    assign classify_valid = enabled && state == CLASSIFY_REQUEST;
    assign classify_active = state == CLASSIFY_REQUEST || state == CLASSIFY_WAIT;
    // Never alias an unknown backend to PE. Descriptor validation rejects it.
    always_comb begin
        operation_error = 1'b0;
        operation_done = 1'b0;
        case (active_descriptor.backend)
            BACKEND_POOL: begin operation_error = pool_error; operation_done = pool_done; end
            BACKEND_PE: begin operation_error = pe_error; operation_done = pe_done; end
            BACKEND_DCIM: begin operation_error = dcim_error; operation_done = dcim_done; end
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; mode_q <= RUN_FRONTEND;
            current_op <= 0; last_op <= 0; active_descriptor <= '0;
            descriptor_valid_q <= 0; done <= 0; error <= 0; op_done <= 0;
            error_code <= LERR_NONE;
        end else begin
            done <= 0; error <= 0; op_done <= 0;
            if (state != IDLE && state != FAILED && (source_error || path_fault)) begin
                state <= FAILED; error <= 1;
                error_code <= path_fault ? LERR_PATH : LERR_SOURCE;
            end else begin
                case (state)
                    IDLE: if (start_valid && start_ready) begin
                        mode_q <= run_mode; error_code <= LERR_NONE; state <= CHECK_RUN;
                    end
                    CHECK_RUN: begin
                        if (mode_q == RUN_FRONTEND || mode_q == RUN_FC_TAIL || mode_q == RUN_FULL) begin
                            current_op <= mode_q == RUN_FC_TAIL ? 4'd7 : 4'd0;
                            last_op <= mode_q == RUN_FRONTEND ? 4'd2 : 4'd8;
                            state <= REQUEST_INPUT;
                        end else begin
                            // Reserved mode is rejected before any data movement.
                            error_code <= LERR_MODE; error <= 1; state <= FAILED;
                        end
                    end
                    REQUEST_INPUT: if (input_request_ready) state <= ISSUE_INPUT_LOAD;
                    ISSUE_INPUT_LOAD: if (load_ready) state <= WAIT_INPUT;
                    WAIT_INPUT: begin
                        if (load_error) begin
                            error_code <= LERR_INPUT; error <= 1; state <= FAILED;
                        end else if (load_done) state <= FETCH_DESC;
                    end
                    FETCH_DESC: begin
                        active_descriptor <= rom_descriptor;
                        descriptor_valid_q <= rom_valid;
                        state <= CHECK_DESC;
                    end
                    CHECK_DESC: begin
                        if (!descriptor_valid_q ||
                            !((active_descriptor.backend == BACKEND_POOL && active_descriptor.op_kind == OP_POOL) ||
                              (active_descriptor.backend == BACKEND_PE &&
                               (active_descriptor.op_kind == OP_CONV || active_descriptor.op_kind == OP_FC)) ||
                              (active_descriptor.backend == BACKEND_DCIM && active_descriptor.op_kind == OP_CONV))) begin
                            error_code <= LERR_DESCRIPTOR; error <= 1; state <= FAILED;
                        end else if (active_descriptor.backend == BACKEND_POOL) state <= ISSUE_OPERATION;
                        else state <= REQUEST_WEIGHT;
                    end
                    REQUEST_WEIGHT: if (weight_request_ready) state <= ISSUE_WEIGHT_LOAD;
                    ISSUE_WEIGHT_LOAD: if (weight_load_ready) state <= WAIT_WEIGHT;
                    WAIT_WEIGHT: begin
                        if (weight_load_error) begin
                            error_code <= LERR_WEIGHT; error <= 1; state <= FAILED;
                        end else if (weight_load_done) state <= ISSUE_OPERATION;
                    end
                    ISSUE_OPERATION: if ((pe_cmd_valid && pe_cmd_ready) || (pool_valid && pool_ready) ||
                                         (dcim_cmd_valid && dcim_cmd_ready))
                        state <= WAIT_OPERATION;
                    WAIT_OPERATION: begin
                        if (operation_error) begin
                            error_code <= LERR_OPERATION; error <= 1; state <= FAILED;
                        end else if (operation_done) begin
                            op_done <= 1; state <= ADVANCE;
                        end
                    end
                    ADVANCE: if (current_op == last_op)
                                 state <= mode_q == RUN_FRONTEND ? COMPLETE : CLASSIFY_REQUEST;
                             else begin current_op <= current_op + 4'd1; state <= FETCH_DESC; end
                    CLASSIFY_REQUEST: if (classify_valid && classify_ready) state <= CLASSIFY_WAIT;
                    CLASSIFY_WAIT: begin
                        if (classify_error) begin
                            error_code <= LERR_OPERATION; error <= 1; state <= FAILED;
                        end else if (classify_done) state <= COMPLETE;
                    end
                    COMPLETE: begin done <= 1; state <= IDLE; end
                    FAILED: ; // Partial writes are not rolled back. Shared reset required.
                    default: begin error_code <= LERR_DESCRIPTOR; error <= 1; state <= FAILED; end
                endcase
            end
        end
    end
endmodule
