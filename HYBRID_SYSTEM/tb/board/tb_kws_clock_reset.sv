`timescale 1ns/1ps
// Tests reset/debounce logic with the explicit behavioral clock branch only.
module tb_kws_clock_reset;
    logic sys_clk_125m=0,reset_button=1;
    wire clk,clk_cim,locked,rst,rst_cim;
    always #4 sys_clk_125m=~sys_clk_125m;
    kws_clock_reset #(.RELEASE_CYCLES(8)) dut (.*);
    time last_sys_edge=0,last_cim_edge=0;
    integer stable_edges=0, sys_release_edges=0, cim_release_edges=0;
    always @(posedge clk) begin
        last_sys_edge=$time;
        if(dut.startup_reset_sync[1] || dut.button_sync[1] || !dut.lock_sync[1]) stable_edges=0;
        else if(!dut.release_ready) stable_edges++;
        if(dut.common_reset || !dut.release_ready) sys_release_edges=0;
        else sys_release_edges++;
        #0.001;
        if(dut.release_ready && stable_edges<8) $fatal(1,"release counter too early");
    end
    always @(posedge clk_cim) begin
        last_cim_edge=$time;
        if(dut.common_reset || !dut.release_ready) cim_release_edges=0;
        else cim_release_edges++;
    end
    always @(negedge rst) begin
        if($time!=last_sys_edge || sys_release_edges<4) $fatal(1,"system reset released before four edges time=%0t edge=%0t count=%0d",$time,last_sys_edge,sys_release_edges);
    end
    always @(negedge rst_cim) begin
        if($time!=last_cim_edge || cim_release_edges<4) $fatal(1,"CIM reset released before four edges");
    end
    initial begin
        #30;reset_button=0;
        #20;reset_button=1; // Bounce must prevent a short premature run.
        #3;reset_button=0;
        #20;if(!rst || !rst_cim) $fatal(1,"reset release too early");
        wait(!rst && !rst_cim);
        #13;reset_button=1;#0.001;
        if(!rst || !rst_cim) $fatal(1,"reset assertion not common/asynchronous");
        #30;reset_button=0;wait(!rst && !rst_cim);
        // Independent MMCM lock loss; force only the external primitive output.
        #2; force dut.locked=1'b0; #0.001;
        if(!rst || !rst_cim) $fatal(1,"lock loss did not assert both resets");
        #32; release dut.locked;
        wait(!rst && !rst_cim);
        // Very short button pulse must be captured even between system edges.
        @(negedge clk); #1; reset_button=1; #0.2; reset_button=0;
        #0.001;if(!rst || !rst_cim) $fatal(1,"short pulse lost");
        wait(!rst && !rst_cim);
        // Missing CIM clock must not allow reset release in that domain.
        #2; reset_button=1; force dut.sim_cim=1'b0;
        #24; reset_button=0;
        wait(!rst); #100;
        if(!rst_cim) $fatal(1,"CIM reset released with stopped clock");
        release dut.sim_cim;
        wait(!rst_cim);
        $display("PASS board reset: bounce, lock loss, short pulse, stopped CIM clock, counter and four-edge release (not MMCM/metastability verification)");$finish;
    end
    initial begin #5000;$fatal(1,"clock/reset watchdog");end
endmodule
