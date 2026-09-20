`timescale 1ns/1ps
module pe_board_test_case #(parameter integer VARIANT=0)(output logic done=0);
    logic clk=0, button=0;
    always #4 clk=~clk;
    wire [3:0] led;
    pe_board_top #(.PE8_MODE(VARIANT!=0),.RESULT_PIPELINED(VARIANT==2),.RELEASE_BITS(4)) dut (
        .sys_clk_125m(clk),.reset_button(button),.led(led)
    );
    integer checks=0;
    integer expected, a, w, k_count, t, c;
    always @(posedge clk) begin
        if(!dut.rst && dut.self_test.out_valid && dut.self_test.out_ready) begin
            t=integer'(dut.test_id); c=integer'(dut.self_test.out_channel_id);
            k_count=t==0 ? 9 : (t==1 ? 144 : 32);
            expected=0;
            for(integer k=0;k<k_count;k++) begin
                a=(k*43+17+t*61)%256;
                w=(c*71+k*29+128+t*17)%256;
                if(w>=128) w=w-256;
                expected=expected+(a-127)*w;
            end
            if(dut.self_test.out_data!==32'(expected)) $fatal(1,"independent golden mismatch");
            checks=checks+1;
        end
        if(led[3]) $fatal(1,"board fail variant=%0d code=%0d",VARIANT,dut.failure_code);
    end
    task automatic rerun;
        @(negedge clk); button=1;
        repeat(6) @(negedge clk);
        if(!dut.rst || led[2] || led[3]) $fatal(1,"button reset failed");
        // Bounce on release; restart only after a stable release interval.
        button=0; repeat(3) @(negedge clk);
        button=1; repeat(3) @(negedge clk);
        button=0;
        wait(!dut.rst);
    endtask
    initial begin
        wait(!dut.rst);
        repeat(80) @(negedge clk);
        rerun(); // Abort during loading, then restart through external button.
        wait(led[2]);
        if(dut.checked_outputs!=52 || checks!=52 || led[1]) $fatal(1,"incomplete suite");
        repeat(30) @(negedge clk);
        if(!led[2]) $fatal(1,"PASS not sticky");
        checks=0; rerun();
        wait(led[2]);
        if(dut.checked_outputs!=52 || checks!=52) $fatal(1,"rerun failed");
        $display("PASS board variant=%0d two complete suites, reset/bounce, 104 outputs",VARIANT);
        done=1;
    end
endmodule
module tb_pe_board;
    wire [2:0] done;
    pe_board_test_case #(.VARIANT(0)) case_pe9(done[0]);
    pe_board_test_case #(.VARIANT(1)) case_pe8(done[1]);
    pe_board_test_case #(.VARIANT(2)) case_pipe(done[2]);
    logic clk=0, rst=1;
    always #4 clk=~clk;
    wire busy, pass, fail;
    wire [3:0] failure_code;
    wire [1:0] test_id;
    wire [6:0] checked_outputs;
    pe_board_self_test #(.TIMEOUT_CYCLES(2)) timeout_test (.*);
    initial begin
        repeat(4) @(negedge clk); rst=0;
        repeat(8) @(negedge clk);
        if(!fail || pass || busy || failure_code!=3) $fatal(1,"timeout detection failed");
        wait(&done);
        $display("PASS all board variants and sticky timeout FAIL");
        $finish;
    end
    initial begin #2000000; $fatal(1,"board watchdog"); end
endmodule
