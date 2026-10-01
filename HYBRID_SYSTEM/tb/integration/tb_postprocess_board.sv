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
            while(!(comb_led[2] && pipe_led[2]) && cycles<40000) begin
                @(negedge clk); cycles=cycles+1;
                if(comb_led[3] || pipe_led[3]) $fatal(1,"Board self-test failed");
            end
            if(cycles==40000) $fatal(1,"Timeout");
            if(comb.test.index!=1647 || pipe.test.index!=1647) $fatal(1,"Incomplete test");
            $display("PASS comb + pipeline: 1648 transactions, 175 pool outputs, 4 argmax sets each; cycles=%0d",cycles);
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
        // Corrupt pooled golden data at a real valid pool result.
        button=1; repeat(10) @(negedge clk); button=0;
        wait(comb.test.mode_q==1 && comb.test.tail_valid_q && comb.test.state==2);
        @(negedge clk);
        force comb.test.tail_data_q=8'd0; // ReLU guarantees correct pool >=128.
        repeat(25) @(negedge clk);
        if(!comb_led[3]) $fatal(1,"Pool fault not detected");
        release comb.test.tail_data_q;
        // Corrupt first argmax result (all ties: expected class 0).
        button=1; repeat(10) @(negedge clk); button=0;
        wait(pipe.test.mode_q==2 && pipe.test.tail_valid_q && pipe.test.state==2);
        @(negedge clk);
        force pipe.test.class_q=3'd7;
        repeat(25) @(negedge clk);
        if(!pipe_led[3]) $fatal(1,"Argmax fault not detected");
        release pipe.test.class_q;
        $display("PASS pool and argmax fault injection");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1,"Global timeout");
    end
endmodule
