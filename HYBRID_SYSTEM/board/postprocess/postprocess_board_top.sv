`timescale 1ns/1ps
// Normal PYNQ-Z2 top, not OOC. 750 MHz VCO / 5 = 150 MHz default.
module postprocess_board_top #(
    parameter bit POSTPROCESS_PIPELINED = 1'b0,
    parameter real OUTPUT_DIVIDE = 5.0
) (
    input wire sys_clk_125m, reset_button,
    output wire [3:0] led
);
    wire clk, locked;
`ifndef VERILATOR
    wire ci, fb, fbg, co;
    IBUF ib (.I(sys_clk_125m), .O(ci));
    MMCME2_BASE #(.CLKIN1_PERIOD(8.0), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(6.0), .CLKOUT0_DIVIDE_F(OUTPUT_DIVIDE),
        .STARTUP_WAIT("FALSE")) mmcm (
        .CLKIN1(ci), .CLKFBIN(fbg), .CLKFBOUT(fb), .CLKOUT0(co),
        .RST(1'b0), .PWRDWN(1'b0), .LOCKED(locked));
    BUFG feedback_buffer (.I(fb), .O(fbg));
    BUFG output_buffer (.I(co), .O(clk));
`else
    // Functional simulation only: this does NOT model MMCM or physical timing.
    assign clk = sys_clk_125m;
    assign locked = 1'b1;
`endif
    (* ASYNC_REG = "TRUE" *) logic button_meta = 1'b1;
    (* ASYNC_REG = "TRUE" *) logic button_sync = 1'b1;
    (* ASYNC_REG = "TRUE" *) logic [2:0] reset_sync = 3'b111;
    always_ff @(posedge clk) begin
        button_meta <= reset_button;
        button_sync <= button_meta;
    end
    // Lock loss asserts reset asynchronously; release is synchronous.
    always_ff @(posedge clk or negedge locked) begin
        if (!locked) reset_sync <= 3'b111;
        else reset_sync <= {reset_sync[1:0], button_sync};
    end
    wire busy, pass, fail;
    postprocess_self_test #(.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) test (
        .clk(clk), .rst(reset_sync[2]), .busy(busy), .pass(pass), .fail(fail));
    assign led = {fail, pass, busy, locked};
endmodule
