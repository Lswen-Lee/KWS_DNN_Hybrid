`timescale 1ns/1ps
module tb_postprocess_board;
    logic clk=0, button=1;
    always #3.333 clk=~clk;
    wire [3:0] comb_led, pipe_led;
    postprocess_board_top #(.POSTPROCESS_PIPELINED(0)) comb (
        .sys_clk_125m(clk),.reset_button(button),.led(comb_led));
    postprocess_board_top #(.POSTPROCESS_PIPELINED(1)) pipe (
        .sys_clk_125m(clk),.reset_button(button),.led(pipe_led));
    task automatic run_test;
        integer cycles;
        begin
            cycles=0;
            while(!(comb_led[2] && pipe_led[2]) && cycles<20000) begin
                @(negedge clk); cycles=cycles+1;
                if(comb_led[3] || pipe_led[3]) $fatal(1,"Board self-test failed");
            end
            if(cycles==20000) $fatal(1,"Timeout");
            if(comb.test.index!=607 || pipe.test.index!=607) $fatal(1,"Incomplete test");
            $display("PASS comb + pipeline: 608 transactions each; cycles=%0d",cycles);
        end
    endtask
    initial begin
        repeat(10) @(negedge clk);
        button=0;
        run_test();
        // Button reset must clear sticky results and rerun all transactions.
        button=1;
        repeat(10) @(negedge clk);
        if(comb_led[2] || pipe_led[2]) $fatal(1,"Reset failed");
        button=0;
        run_test();
        // Negative test: corrupt the registered golden value, expect sticky FAIL.
        button=1; repeat(10) @(negedge clk); button=0;
        wait(comb.test.state==2);
        @(negedge clk);
        force comb.test.expected_q=8'd255;
        repeat(20) @(negedge clk);
        if(!comb_led[3] || comb_led[2]) $fatal(1,"Fault not detected");
        release comb.test.expected_q;
        $display("PASS fault injection and sticky FAIL");
        $finish;
    end
endmodule
