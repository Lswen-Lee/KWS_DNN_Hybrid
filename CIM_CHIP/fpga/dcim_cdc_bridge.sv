`timescale 1ns/1ps

// Single-outstanding clock-domain bridge for dcim_pin_master.
//
// The command producer runs in the fast clock domain and uses a conventional
// valid/ready handshake.  The DCIM pin master runs in the slow clock domain.
// A request toggle and a response toggle cross through independent two-FF
// synchronizers; the wide command/result buses are held stable in mailbox
// registers while their corresponding toggle crosses the clock boundary.
//
// Only one transaction may be outstanding.  This matches the serial nature
// of dcim_pin_master, avoids an unnecessary deep asynchronous FIFO, and makes
// the multi-bit bundled-data stability rule explicit:
//
//   * command_mailbox_125 remains unchanged from command acceptance until the
//     returned response has been consumed in the 125 MHz domain.
//   * response_mailbox_50 is written before response_toggle_50 can be observed
//     in the 125 MHz domain and remains unchanged until the next transaction.
//
// rst_125m and rst_50m are active-high.  System integration must assert both
// resets together; deassertion should be synchronized to each local clock.
module dcim_cdc_bridge (
    // Fast command/response domain.  The names describe the intended system
    // frequencies, but the logic does not depend on an exact clock ratio.
    input  logic         clk_125m,
    input  logic         rst_125m,

    input  logic         cmd_valid,
    output logic         cmd_ready,
    input  logic [1:0]   cmd_operation,
    input  logic [6:0]   cmd_row_addr,
    input  logic [3:0]   cmd_bank_addr,
    input  logic [7:0]   cmd_weight,
    input  logic [255:0] cmd_activation_flat,
    input  logic         cmd_activation_is_a8,

    output logic         rsp_valid,
    input  logic         rsp_ready,
    output logic         rsp_data_valid,
    output logic         rsp_error,
    output logic [7:0]   rsp_sram_read_data,
    output logic [17:0]  rsp_even_raw_result,
    output logic [17:0]  rsp_odd_raw_result,

    // Slow dcim_pin_master domain.
    input  logic         clk_50m,
    input  logic         rst_50m,

    output logic         master_start,
    output logic [1:0]   master_operation,
    output logic [6:0]   master_row_addr,
    output logic [3:0]   master_bank_addr,
    output logic [7:0]   master_weight,
    output logic [255:0] master_activation_flat,
    output logic         master_activation_is_a8,

    input  logic         master_busy,
    input  logic         master_done,
    input  logic         master_result_valid,
    input  logic         master_error,
    input  logic [7:0]   master_sram_read_data,
    input  logic [17:0]  master_even_raw_result,
    input  logic [17:0]  master_odd_raw_result
);

    typedef enum logic [1:0] {
        F_IDLE,
        F_WAIT_RESPONSE,
        F_RESPONSE
    } fast_state_t;

    typedef enum logic [1:0] {
        S_WAIT_REQUEST,
        S_START_MASTER,
        S_WAIT_MASTER
    } slow_state_t;

    fast_state_t fast_state;
    fast_state_t fast_next_state;
    slow_state_t slow_state;
    slow_state_t slow_next_state;

    // One command mailbox owned and written only by clk_125m logic.
    logic [1:0]   command_operation_125;
    logic [6:0]   command_row_addr_125;
    logic [3:0]   command_bank_addr_125;
    logic [7:0]   command_weight_125;
    logic [255:0] command_activation_125;
    logic         command_activation_is_a8_125;
    logic         request_toggle_125;

    // Two-stage synchronizer for the one-bit request event.
    (* ASYNC_REG = "TRUE" *) logic request_sync_meta_50;
    (* ASYNC_REG = "TRUE" *) logic request_sync_50;
    logic request_seen_50;

    // One response mailbox owned and written only by clk_50m logic.
    logic        response_data_valid_50;
    logic        response_error_50;
    logic [7:0]  response_sram_read_data_50;
    logic [17:0] response_even_raw_result_50;
    logic [17:0] response_odd_raw_result_50;
    logic        response_toggle_50;

    // Two-stage synchronizer for the one-bit response event.
    (* ASYNC_REG = "TRUE" *) logic response_sync_meta_125;
    (* ASYNC_REG = "TRUE" *) logic response_sync_125;
    logic response_seen_125;

    logic command_accept;
    logic response_accept;
    logic new_request_50;
    logic new_response_125;

    assign command_accept  = cmd_valid && (fast_state == F_IDLE) &&
                             !rst_125m;
    assign response_accept = rsp_ready && (fast_state == F_RESPONSE) &&
                             !rst_125m;
    assign new_request_50  = request_sync_50 != request_seen_50;
    assign new_response_125 = response_sync_125 != response_seen_125;

    // The command mailbox remains stable for the complete transaction.  The
    // slow master captures these values on its master_start edge.
    assign master_operation        = command_operation_125;
    assign master_row_addr         = command_row_addr_125;
    assign master_bank_addr        = command_bank_addr_125;
    assign master_weight           = command_weight_125;
    assign master_activation_flat  = command_activation_125;
    assign master_activation_is_a8 = command_activation_is_a8_125;

    // Fast-domain command capture, response synchronization and response
    // output registration.
    always_ff @(posedge clk_125m or posedge rst_125m) begin
        if (rst_125m) begin
            fast_state                 <= F_IDLE;
            command_operation_125      <= 2'd0;
            command_row_addr_125       <= 7'd0;
            command_bank_addr_125      <= 4'd0;
            command_weight_125         <= 8'd0;
            command_activation_125     <= 256'd0;
            command_activation_is_a8_125 <= 1'b0;
            request_toggle_125         <= 1'b0;
            response_sync_meta_125     <= 1'b0;
            response_sync_125          <= 1'b0;
            response_seen_125          <= 1'b0;
            rsp_data_valid             <= 1'b0;
            rsp_error                  <= 1'b0;
            rsp_sram_read_data         <= 8'd0;
            rsp_even_raw_result        <= 18'd0;
            rsp_odd_raw_result         <= 18'd0;
        end else begin
            response_sync_meta_125 <= response_toggle_50;
            response_sync_125      <= response_sync_meta_125;
            fast_state             <= fast_next_state;

            if (command_accept) begin
                command_operation_125        <= cmd_operation;
                command_row_addr_125         <= cmd_row_addr;
                command_bank_addr_125        <= cmd_bank_addr;
                command_weight_125           <= cmd_weight;
                command_activation_125       <= cmd_activation_flat;
                command_activation_is_a8_125 <= cmd_activation_is_a8;
                request_toggle_125           <= ~request_toggle_125;
            end

            if ((fast_state == F_WAIT_RESPONSE) && new_response_125) begin
                // response_toggle_50 has already crossed two synchronizer
                // stages, so the bundled result mailbox has been stable long
                // before this destination-domain capture edge.
                response_seen_125   <= response_sync_125;
                rsp_data_valid      <= response_data_valid_50;
                rsp_error           <= response_error_50;
                rsp_sram_read_data  <= response_sram_read_data_50;
                rsp_even_raw_result <= response_even_raw_result_50;
                rsp_odd_raw_result  <= response_odd_raw_result_50;
            end
        end
    end

    always_comb begin
        fast_next_state = fast_state;
        cmd_ready       = 1'b0;
        rsp_valid       = 1'b0;

        case (fast_state)
            F_IDLE: begin
                cmd_ready = !rst_125m;
                if (command_accept)
                    fast_next_state = F_WAIT_RESPONSE;
            end

            F_WAIT_RESPONSE: begin
                if (new_response_125)
                    fast_next_state = F_RESPONSE;
            end

            F_RESPONSE: begin
                rsp_valid = !rst_125m;
                if (response_accept)
                    fast_next_state = F_IDLE;
            end

            default: fast_next_state = F_IDLE;
        endcase
    end

    // Slow-domain request synchronization, pin-master launch and response
    // mailbox capture.
    always_ff @(posedge clk_50m or posedge rst_50m) begin
        if (rst_50m) begin
            slow_state                  <= S_WAIT_REQUEST;
            request_sync_meta_50        <= 1'b0;
            request_sync_50             <= 1'b0;
            request_seen_50             <= 1'b0;
            response_data_valid_50      <= 1'b0;
            response_error_50           <= 1'b0;
            response_sram_read_data_50  <= 8'd0;
            response_even_raw_result_50 <= 18'd0;
            response_odd_raw_result_50  <= 18'd0;
            response_toggle_50          <= 1'b0;
        end else begin
            request_sync_meta_50 <= request_toggle_125;
            request_sync_50      <= request_sync_meta_50;
            slow_state           <= slow_next_state;

            if (slow_state == S_START_MASTER)
                request_seen_50 <= request_sync_50;

            if ((slow_state == S_WAIT_MASTER) && master_done) begin
                response_data_valid_50      <= master_result_valid;
                response_error_50           <= master_error;
                response_sram_read_data_50  <= master_sram_read_data;
                response_even_raw_result_50 <= master_even_raw_result;
                response_odd_raw_result_50  <= master_odd_raw_result;
                response_toggle_50          <= ~response_toggle_50;
            end
        end
    end

    always_comb begin
        slow_next_state = slow_state;
        master_start    = 1'b0;

        case (slow_state)
            S_WAIT_REQUEST: begin
                if (new_request_50 && !master_busy)
                    slow_next_state = S_START_MASTER;
            end

            S_START_MASTER: begin
                master_start    = !rst_50m;
                slow_next_state = S_WAIT_MASTER;
            end

            S_WAIT_MASTER: begin
                if (master_done)
                    slow_next_state = S_WAIT_REQUEST;
            end

            default: slow_next_state = S_WAIT_REQUEST;
        endcase
    end

endmodule
