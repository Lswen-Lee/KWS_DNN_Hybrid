`timescale 1ns/1ps
module pe_board_top #(
    parameter bit PE8_MODE=0,
    parameter bit RESULT_PIPELINED=0,
    parameter integer RELEASE_BITS=20
) (
    input wire sys_clk_125m, reset_button,
    output wire [3:0] led
);
    wire clk, rst, busy, pass, fail;
    wire [3:0] failure_code;
    wire [1:0] test_id;
    wire [6:0] checked_outputs;
    logic [26:0] heartbeat=0;
    pe_board_clock_reset #(.RELEASE_BITS(RELEASE_BITS)) clock_reset (.*);
    always_ff @(posedge clk) begin
        if(rst) heartbeat<=0;
        else heartbeat<=heartbeat+1'b1;
    end
    pe_board_self_test #(.PE8_MODE(PE8_MODE),.RESULT_PIPELINED(RESULT_PIPELINED)) self_test (
        .clk(clk),.rst(rst),.busy(busy),.pass(pass),.fail(fail),
        .failure_code(failure_code),.test_id(test_id),.checked_outputs(checked_outputs)
    );
    assign led={fail,pass,busy,heartbeat[26]};
endmodule
