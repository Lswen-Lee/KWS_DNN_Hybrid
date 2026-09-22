`timescale 1ns/1ps
module pe8_compact_pot_comb_board_top(input wire sys_clk_125m, reset_button, output wire [3:0] led);
    pe_board_top #(.PE8_MODE(1'b1), .RESULT_PIPELINED(1'b0), .POT_MODEL(1'b1),
        .POSTPROCESS_PIPELINED(1'b0)) board (.*);
endmodule
