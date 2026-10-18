`timescale 1ns/1ps
module tb_kws_board_top;
    logic sys_clk_125m=0,reset_button=1;
    wire [3:0] led;
    always #4 sys_clk_125m=~sys_clk_125m;
    kws_board_top #(.DEMO_FILE("build/kws_board_vectors/kws_demo.mem"),.RELEASE_CYCLES(32)) dut (.*);
    integer cycles=0;
    always @(posedge sys_clk_125m) begin
        cycles++;
        if(cycles>20000000) $fatal(1,"board pin top watchdog");
    end
    initial begin
        #40;reset_button=0;
        wait(led[0]);wait(led[1]);wait(led[2] || led[3]);
        @(negedge sys_clk_125m);
        if(led!==4'b0101) $fatal(1,"board LED result mismatch %b",led);
        repeat(100) begin @(negedge sys_clk_125m);if(led!==4'b0101) $fatal(1,"board LED not sticky");end
        reset_button=1;#1;
        if(led!==4'b0000) $fatal(1,"board button did not clear status");
        $display("PASS S6 pin top LEDs=0101 and reset clears; behavioral clock only");$finish;
    end
endmodule
