`timescale 1ns/1ps
module pe_board_test_case #(parameter integer VARIANT=0, parameter bit POT_MODEL=0)(output logic done=0);
    logic clk=0, button=0;
    always #4 clk=~clk;
    wire [3:0] led;
    pe_board_top #(.PE8_MODE(VARIANT!=0),.RESULT_PIPELINED(VARIANT==2),.POT_MODEL(POT_MODEL),.RELEASE_BITS(4)) dut (
        .sys_clk_125m(clk),.reset_button(button),.led(led)
    );
    integer checks=0;
    integer expected, a, w, k_count, t, c, shift_count, divisor, magnitude, quotient, remainder_value;
    always @(posedge clk) begin
        if(!dut.rst && dut.self_test.out_valid && dut.self_test.out_ready) begin
            t=integer'(dut.test_id); c=integer'(dut.self_test.out_channel_id);
            k_count=t==0 ? 9 : (t==1 ? 144 : 32);
            expected=0;
            for(integer k=0;k<k_count;k++) begin
                a=(k*43+17+t*61)%256;
                w=(c*71+k*29+128+t*17)%256;
                if(w>=128) w=w-256;
                expected=expected+(a-(POT_MODEL ? 128 : 127))*w;
            end
            if(POT_MODEL) begin
                if(t==0) shift_count=(c==0 || c==4 || c==10) ? 8 : 9;
                else if(t==1) shift_count=(c==10 || c==13 || c==23 || c==27 || c==28) ? 8 : 7;
                else shift_count=6;
                divisor=1<<shift_count; magnitude=expected<0 ? -expected : expected;
                quotient=magnitude/divisor; remainder_value=magnitude%divisor;
                if(2*remainder_value>divisor || (2*remainder_value==divisor && quotient%2==1)) quotient++;
                expected=(expected<0 ? -quotient : quotient)+128;
                if(expected<0) expected=0;
                if(expected>255) expected=255;
                if(t!=2 && expected<128) expected=128;
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
        $display("PASS board variant=%0d POT=%0d two complete suites, reset/bounce, 104 outputs",VARIANT,POT_MODEL);
        done=1;
    end
endmodule
module tb_pe_board;
    wire [5:0] done;
    pe_board_test_case #(.VARIANT(0)) case_pe9(done[0]);
    pe_board_test_case #(.VARIANT(1)) case_pe8(done[1]);
    pe_board_test_case #(.VARIANT(2)) case_pipe(done[2]);
    pe_board_test_case #(.VARIANT(0),.POT_MODEL(1)) case_pe9_pot(done[3]);
    pe_board_test_case #(.VARIANT(1),.POT_MODEL(1)) case_pe8_pot(done[4]);
    pe_board_test_case #(.VARIANT(2),.POT_MODEL(1)) case_pipe_pot(done[5]);
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
