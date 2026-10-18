`timescale 1ns/1ps
// Tests reset/debounce logic with the explicit behavioral clock branch only.
module tb_kws_clock_reset;
    logic sys_clk_125m=0,reset_button=1;
    wire clk,clk_cim,locked,rst,rst_cim;
    always #4 sys_clk_125m=~sys_clk_125m;
    kws_clock_reset #(.RELEASE_CYCLES(8)) dut (.*);
    always @(negedge rst) if(clk!==1) $fatal(1,"system reset released off edge");
    always @(negedge rst_cim) if(clk_cim!==1) $fatal(1,"CIM reset released off edge");
    initial begin
        #30;reset_button=0;
        #20;reset_button=1; // Bounce must prevent a short premature run.
        #3;reset_button=0;
        #20;if(!rst || !rst_cim) $fatal(1,"reset release too early");
        wait(!rst && !rst_cim);
        #13;reset_button=1;#0.001;
        if(!rst || !rst_cim) $fatal(1,"reset assertion not common/asynchronous");
        #30;reset_button=0;wait(!rst && !rst_cim);
        $display("PASS board reset common_assert synchronous_release bounce=1 (not MMCM verification)");$finish;
    end
    initial begin #5000;$fatal(1,"clock/reset watchdog");end
endmodule
