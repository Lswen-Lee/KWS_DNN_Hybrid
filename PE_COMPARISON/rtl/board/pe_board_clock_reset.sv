`timescale 1ns/1ps
module pe_board_clock_reset #(
    parameter integer RELEASE_BITS = 20
) (
    input wire sys_clk_125m, reset_button,
    output wire clk,
    output wire rst
);
    wire clk_ibuf;
    IBUF input_clock (.I(sys_clk_125m), .O(clk_ibuf));
    BUFG global_clock (.I(clk_ibuf), .O(clk));
    // Initial values are configuration INIT values on this Xilinx FPGA.
    (* ASYNC_REG = "TRUE" *) logic button_meta = 1'b1;
    (* ASYNC_REG = "TRUE" *) logic button_sync = 1'b1;
    logic [RELEASE_BITS-1:0] release_count = '0;
    logic reset_q = 1'b1;
    always_ff @(posedge clk) begin
        button_meta <= reset_button;
        button_sync <= button_meta;
        if (button_sync) begin
            release_count <= '0;
            reset_q <= 1'b1;
        end else if (!(&release_count)) begin
            release_count <= release_count + 1'b1;
            reset_q <= 1'b1;
        end else reset_q <= 1'b0;
    end
    assign rst = reset_q;
endmodule
