`timescale 1ns/1ps

module tb_dcim_master_chip_top;

    logic       sys_clk_125m;
    logic       reset_button;
    logic [3:0] led;
    integer     timeout_count;

    dcim_master_chip_top dut (
        .sys_clk_125m (sys_clk_125m),
        .reset_button (reset_button),
        .led          (led)
    );

    // In RTL simulation dcim_clock_gen_125_to_50 is a pass-through, so this
    // clock is intentionally 50 MHz.  Synthesis uses the real 125-to-50 MMCM.
    initial sys_clk_125m = 1'b0;
    always #10 sys_clk_125m = ~sys_clk_125m;

    initial begin
        $display("============================================================");
        $display("Testbench : tb_dcim_master_chip_top");
        $display("Path      : self-test -> pin master -> real 128x128 chip top");
        $display("Coverage  : one 2048-word burst + 2048 reads + one A8W8 compute");
        $display("============================================================");

        reset_button = 1'b1;
        repeat (5) @(posedge sys_clk_125m);
        reset_button = 1'b0;

        timeout_count = 0;
        while (!led[2] && !led[3] && (timeout_count < 100000)) begin
            @(posedge sys_clk_125m);
            timeout_count = timeout_count + 1;
        end

        if (!led[0]) begin
            $error("FAIL: simulated clock generator never asserted locked");
            $fatal;
        end

        if (led[3]) begin
            $error("FAIL: board self-test asserted fail LED");
            $fatal;
        end

        if (!led[2]) begin
            $error("FAIL: board self-test timeout after %0d clocks",
                   timeout_count);
            $fatal;
        end

        if (led[1]) begin
            $error("FAIL: busy LED remained high after PASS");
            $fatal;
        end

        $display("PASS: LED mapping locked/busy/pass/fail = %b", led);
        $display("PASS: complete single-50-MHz master/chip self-test passed");
        $display("============================================================");
        $finish;
    end

endmodule
