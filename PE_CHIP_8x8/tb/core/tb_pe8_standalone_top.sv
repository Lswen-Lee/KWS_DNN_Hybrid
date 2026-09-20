`timescale 1ns/1ps
module tb_pe8_standalone_top;
    logic clk=0,reset_btn=0;
    wire [3:0] led, bad_led, timeout_led;
    integer checks=0, jobs=0, accepted=0, beats=0;
    integer sums[0:11];
    logic [383:0] held_result;
    bit was_holding=0, saw_heartbeat=0;
    always #4 clk=~clk;

    pe8_standalone_top #(.HEARTBEAT_BITS(4)) dut (.*);
    pe8_standalone_top #(.HEARTBEAT_BITS(4),.INJECT_GOLDEN_ERROR(1))
        bad (.clk(clk),.reset_btn(reset_btn),.led(bad_led));
    pe8_standalone_top #(.HEARTBEAT_BITS(4),.TIMEOUT_CYCLES(8))
        timed (.clk(clk),.reset_btn(reset_btn),.led(timeout_led));

    // Independent scoreboard consumes the actual interface, not DUT golden ROM.
    always @(posedge clk) begin
        if(dut.rst) begin
            jobs=0; accepted=0; was_holding=0; beats=0;
            for(integer j=0;j<12;j=j+1) sums[j]=0;
        end else begin
            if(led[0]) saw_heartbeat=1;
            if(dut.start) begin
                if(dut.busy) $fatal(1,"Start while busy");
                beats=0;
                for(integer j=0;j<12;j=j+1) sums[j]=0;
            end
            if(dut.sample_valid && dut.sample_ready) begin
                beats=beats+1; accepted=accepted+1;
                for(integer j=0;j<12;j=j+1)
                    if(dut.lane_mask[j])
                        sums[j]=sums[j]+(int'(dut.activation_u8)-128)*
                                int'($signed(dut.weight_vector_i8[j*8+:8]));
            end
            if(was_holding && dut.result_vector_s32!==held_result)
                $fatal(1,"Result changed under backpressure");
            was_holding=dut.result_valid && !dut.result_ready;
            held_result=dut.result_vector_s32;
            if(dut.result_valid && dut.result_ready) begin
                if(beats!=int'(dut.k_length)) $fatal(1,"Wrong accepted count");
                for(integer j=0;j<12;j=j+1) begin
                    checks=checks+1;
                    if($signed(dut.result_vector_s32[j*32+:32])!==sums[j])
                        $fatal(1,"Scoreboard lane %0d",j);
                end
                jobs=jobs+1;
            end
        end
    end

    task automatic wait_pass;
        integer elapsed;
        begin
            elapsed=0;
            while(!led[2] && elapsed<10000) begin
                @(negedge clk); elapsed=elapsed+1;
                if(led[3]) $fatal(1,"Unexpected fail: reason=%0d test=%0d lane=%0d",
                                 dut.fail_reason,dut.test_id,dut.check_lane);
            end
            if(!led[2] || jobs!=7 || accepted!=236)
                $fatal(1,"Missing complete suite: jobs=%0d samples=%0d",jobs,accepted);
            if(bad_led!=={3'b100,led[0]} || bad.fail_reason!=1)
                $fatal(1,"Golden-error detection failed");
            if(timeout_led!=={3'b100,led[0]} || timed.fail_reason!=2)
                $fatal(1,"Timeout detection failed");
            repeat(5) @(negedge clk);
            if(!led[2] || led[1] || !bad_led[3] || !timeout_led[3])
                $fatal(1,"Terminal state not sticky");
        end
    endtask
    task automatic press_reset;
        begin
            // Deliberately asynchronous to the clock, held across clock edges.
            #1 reset_btn=1;
            repeat(4) @(negedge clk);
            #1 reset_btn=0;
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        // FPGA INIT reset must start tests even without pressing BTN0.
        wait_pass();
        if(!saw_heartbeat) $fatal(1,"Heartbeat not running");
        press_reset();
        // Abort during the K144 test, then ensure a complete fresh run.
        wait(dut.test_id==3 && dut.sample_index==10);
        @(negedge clk);
        press_reset();
        wait_pass();
        $display("PASS standalone: %0d result checks; power-up, 7 cases, reset/rerun, mismatch, timeout, sticky LEDs",checks);
        $finish;
    end
    initial begin #200000; $fatal(1,"Testbench watchdog"); end
endmodule
