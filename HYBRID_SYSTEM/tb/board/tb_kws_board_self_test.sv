`timescale 1ns/1ps
module tb_kws_board_self_test;
    logic clk=0,rst=1,engine_start_ready=0,engine_done=0,engine_error=0,source_fault=0,class_valid=0;
    logic [2:0] class_index=6,result_index;
    logic [7:0] class_score=183,result_score;
    logic engine_start_valid,source_enable,busy,pass,fail;
    logic [3:0] failure_code;
    logic [31:0] run_cycles;
    always #4 clk=~clk;
    kws_board_self_test #(.TIMEOUT_CYCLES(32)) dut (.*);
    task automatic start;
        @(negedge clk);rst=1;engine_start_ready=0;engine_done=0;engine_error=0;source_fault=0;class_valid=0;class_index=6;class_score=183;
        repeat(2) @(negedge clk);rst=0;
        repeat(3) begin @(negedge clk);if(!engine_start_valid || !busy) $fatal(1,"start not held");end
        engine_start_ready=1;@(negedge clk);engine_start_ready=0;
        if(engine_start_valid) $fatal(1,"repeated start");
    endtask
    task automatic check_fail(input integer code);
        @(negedge clk);
        if(!fail || pass || busy || int'(failure_code)!=code) $fatal(1,"wrong failure %0d",failure_code);
        repeat(4) begin @(negedge clk);if(!fail || engine_start_valid || source_enable) $fatal(1,"failure not sticky");end
    endtask
    initial begin
        start();engine_done=1;class_valid=1;@(negedge clk);engine_done=0;class_valid=0;
        if(!pass || fail || result_index!=6 || result_score!=183) $fatal(1,"good result rejected");
        class_index=0;class_score=0;
        repeat(10) begin @(negedge clk);if(!pass || busy || result_index!=6 || result_score!=183) $fatal(1,"result not retained");end
        start();engine_error=1;check_fail(1);
        start();source_fault=1;check_fail(2);
        start();while(!fail) @(negedge clk);check_fail(3);
        start();engine_done=1;check_fail(4);
        start();class_valid=1;check_fail(4);
        start();engine_done=1;class_valid=1;class_score=182;check_fail(5);
        start();engine_done=1;class_valid=1;class_index=5;check_fail(5);
        $display("PASS board supervisor success=1 failures=7 sticky_result=1");$finish;
    end
    initial begin #10000;$fatal(1,"supervisor watchdog");end
endmodule
