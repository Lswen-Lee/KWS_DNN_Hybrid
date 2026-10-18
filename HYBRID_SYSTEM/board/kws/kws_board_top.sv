`timescale 1ns/1ps
module kws_board_top #(
    parameter DEMO_FILE="kws_demo.mem",
    parameter bit RESULT_PIPELINED=0, POSTPROCESS_PIPELINED=1,
    parameter integer RELEASE_CYCLES=2500000,
    parameter integer TIMEOUT_CYCLES=125000000
) (
    input logic sys_clk_125m, reset_button,
    output logic [3:0] led
);
    wire clk,clk_cim,locked,rst,rst_cim;
    wire busy,pass,fail;
    // Retain 47 diagnostic bits for optional Vivado Set Up Debug/ILA.
    // This is board-harness overhead, not part of a PE/DCIM area comparison.
    (* MARK_DEBUG="TRUE" *) wire [2:0] result_index;
    (* MARK_DEBUG="TRUE" *) wire [7:0] result_score;
    (* MARK_DEBUG="TRUE" *) wire [3:0] failure_code;
    (* MARK_DEBUG="TRUE" *) wire [31:0] run_cycles;
    kws_clock_reset #(.RELEASE_CYCLES(RELEASE_CYCLES)) clocks (.*);
    kws_board_core #(.DEMO_FILE(DEMO_FILE),.RESULT_PIPELINED(RESULT_PIPELINED),
        .POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) core (.*);
    // Stable status, no pin-level data interface. Optional ILA probes are internal.
    assign led={fail,pass,busy,locked && !rst && !rst_cim};
endmodule
