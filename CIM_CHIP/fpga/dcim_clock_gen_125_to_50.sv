`timescale 1ns/1ps

// PYNQ-Z2 clock generator for the standalone DCIM board test.
//
// Synthesis uses a 7-series MMCM:
//   125 MHz / 1 * 8 = 1000 MHz VCO
//   1000 MHz / 20   =   50 MHz output
//
// RTL simulation intentionally bypasses the vendor primitive.  A testbench
// must therefore drive clk_in_125m at the desired simulated DCIM frequency.
module dcim_clock_gen_125_to_50 (
    input  logic clk_in_125m,
    input  logic reset,
    output logic clk_out_50m,
    output logic locked
);

// The open-source RTL simulator has no Xilinx UNISIM library, so its build
// uses the pass-through branch.  Vivado synthesis and xsim see the real MMCM.
`ifndef VERILATOR
    wire clk_in_buffered;
    wire clk_feedback;
    wire clk_feedback_buffered;
    wire clk_out_mmcm;
    wire mmcm_locked;

    IBUF u_clock_input_buffer (
        .I (clk_in_125m),
        .O (clk_in_buffered)
    );

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKIN1_PERIOD      (8.000),
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (8.000),
        .CLKOUT0_DIVIDE_F   (20.000),
        .CLKOUT0_DUTY_CYCLE (0.500),
        .CLKOUT0_PHASE      (0.000),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1   (clk_in_buffered),
        .CLKFBIN  (clk_feedback_buffered),
        .RST      (reset),
        .PWRDWN   (1'b0),
        .CLKFBOUT (clk_feedback),
        .CLKOUT0  (clk_out_mmcm),
        .LOCKED   (mmcm_locked)
    );

    BUFG u_feedback_buffer (
        .I (clk_feedback),
        .O (clk_feedback_buffered)
    );

    BUFG u_output_buffer (
        .I (clk_out_mmcm),
        .O (clk_out_50m)
    );

    assign locked = mmcm_locked;
`else
    always_comb begin
        clk_out_50m = clk_in_125m;
        locked      = ~reset;
    end
`endif

endmodule
