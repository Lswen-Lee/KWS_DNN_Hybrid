`timescale 1ns/1ps

module tb_input_buffer_32x4;

    logic        bufclk = 1'b0;
    logic        rst_n;
    logic        clk_en;
    logic        sel_next;
    logic        mode_sel;
    logic [3:0]  din;
    logic [31:0] buffered_bits;
    logic [7:0]  sram_write_data;
    logic [31:0] cim_group_bits [0:3];

    integer error_count;
    integer load_clock_count;

    always #5 bufclk = ~bufclk;

    input_buffer_32x4 dut (
        .bufclk         (bufclk),
        .rst_n          (rst_n),
        .clk_en         (clk_en),
        .sel_next       (sel_next),
        .mode_sel       (mode_sel),
        .din            (din),
        .buffered_bits  (buffered_bits),
        .sram_write_data(sram_write_data),
        .cim_group_bits (cim_group_bits)
    );

    task automatic load_one_nibble(input logic [3:0] nibble_value);
        begin
            @(negedge bufclk);
            clk_en   = 1'b1;
            sel_next = 1'b0;
            din      = nibble_value;

            @(posedge bufclk);
            #1;
            load_clock_count = load_clock_count + 1;
            $display("  load clock %0d: Din=%04b, raw DFF bits=%08h",
                     load_clock_count, din, buffered_bits);
        end
    endtask

    initial begin
        rst_n           = 1'b0;
        clk_en          = 1'b0;
        sel_next        = 1'b0;
        mode_sel        = 1'b0;
        din             = 4'b0000;
        error_count     = 0;
        load_clock_count = 0;

        $display("============================================================");
        $display("Testbench : tb_input_buffer_32x4");
        $display("Reference : 0622.pptx slide 3 Input Path");
        $display("Structure : four Din lanes x eight DFF stages");
        $display("sel_next  : 0=load next DFF, 1=expose stored taps");
        $display("mode_sel  : 0=SRAM path, 1=CIM path");
        $display("============================================================");

        // Test 1: reset clears every DFF and both routed outputs.
        repeat (2) @(posedge bufclk);
        #1;
        if ((buffered_bits !== 32'b0) ||
            (sram_write_data !== 8'b0) ||
            (cim_group_bits[0] !== 32'b0) ||
            (cim_group_bits[1] !== 32'b0) ||
            (cim_group_bits[2] !== 32'b0) ||
            (cim_group_bits[3] !== 32'b0)) begin
            $display("FAIL: reset did not clear the Input Path");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - reset clears all DFF stages and outputs");
        end
        rst_n = 1'b1;

        // Test 2: sel_next=0 makes one bufclk move Din into stage 0.
        load_clock_count = 0;
        load_one_nibble(4'ha);
        if (buffered_bits !== 32'h0000_000a) begin
            $display("FAIL: expected raw buffer 0000000a, actual=%08h",
                     buffered_bits);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 2 - one clock loads Din into DFF stage 0");
        end

        // While sel_next=0, the first demux points toward the next DFF, so the
        // external SRAM and CIM branches must both remain inactive.
        if ((sram_write_data !== 8'b0) ||
            (cim_group_bits[0] !== 32'b0) ||
            (cim_group_bits[1] !== 32'b0) ||
            (cim_group_bits[2] !== 32'b0) ||
            (cim_group_bits[3] !== 32'b0)) begin
            $display("FAIL: output branches were active during DFF loading");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 3 - sel_next=0 isolates both output branches");
        end

        // Test 4: clk_en=0 holds the DFF chain.
        @(negedge bufclk);
        clk_en = 1'b0;
        din    = 4'h5;
        repeat (2) @(posedge bufclk);
        #1;
        if (buffered_bits !== 32'h0000_000a) begin
            $display("FAIL: clk_en=0 changed the DFF chain to %08h",
                     buffered_bits);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4 - clk_en=0 holds all DFF values");
        end

        // Clear the chain before testing the SRAM three-clock sequence.
        @(negedge bufclk);
        rst_n = 1'b0;
        #1;
        rst_n = 1'b1;

        // Slide 12 provides the concrete example 9 followed by 1.  The first
        // nibble moves to stage 1 on the second clock, producing write word 91.
        $display("\nSRAM example: first nibble 9, second nibble 1");
        load_clock_count = 0;
        load_one_nibble(4'h9);
        load_one_nibble(4'h1);

        if (buffered_bits[7:0] !== 8'h91) begin
            $display("FAIL: first two DFF stages expected 91, actual=%02h",
                     buffered_bits[7:0]);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5 - two load clocks place 9/1 in two DFF stages");
        end

        // sel_next=1 exposes the stored taps. mode_sel=0 selects the SRAM side
        // of the second demux used by the first two stages.
        @(negedge bufclk);
        sel_next = 1'b1;
        mode_sel = 1'b0;
        clk_en   = 1'b1;
        din      = 4'hf;
        #1;
        if (sram_write_data !== 8'h91) begin
            $display("FAIL: SRAM write data expected 91, actual=%02h",
                     sram_write_data);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 6 - SRAM mode routes the two DFF taps as 8'h91");
        end

        // The third clock belongs to the downstream SRAM write operation.
        // This Input Path must hold its two nibbles rather than shift again.
        @(posedge bufclk);
        #1;
        if ((buffered_bits[7:0] !== 8'h91) ||
            (sram_write_data !== 8'h91)) begin
            $display("FAIL: the third SRAM write clock changed input data");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 7 - sel_next=1 holds data on the third clock");
        end

        // Changing mode only changes the demux route; it must not alter DFFs.
        mode_sel = 1'b1;
        #1;
        if ((sram_write_data !== 8'b0) ||
            (cim_group_bits[0][7:0] !== 8'h91) ||
            (buffered_bits[7:0] !== 8'h91)) begin
            $display("FAIL: SRAM-to-CIM mode routing is incorrect");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 8 - mode_sel moves stage 0/1 taps to the CIM path");
        end

        // Clear the chain and load one complete 32-row CIM bit-plane.
        @(negedge bufclk);
        rst_n    = 1'b0;
        clk_en   = 1'b0;
        sel_next = 1'b0;
        mode_sel = 1'b0;
        #1;
        rst_n = 1'b1;

        $display("\nCIM example: load 32'h89abcdef high nibble first");
        load_clock_count = 0;
        load_one_nibble(4'h8);
        load_one_nibble(4'h9);
        load_one_nibble(4'ha);
        load_one_nibble(4'hb);
        load_one_nibble(4'hc);
        load_one_nibble(4'hd);
        load_one_nibble(4'he);
        load_one_nibble(4'hf);

        if (buffered_bits !== 32'h89ab_cdef) begin
            $display("FAIL: expected raw DFF contents 89abcdef, actual=%08h",
                     buffered_bits);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 9 - eight clocks fill all 32 local rows");
        end

        // Stop loading, expose the taps, and choose CIM mode.
        @(negedge bufclk);
        clk_en   = 1'b0;
        sel_next = 1'b1;
        mode_sel = 1'b1;
        #1;

        if ((cim_group_bits[0] !== 32'h89ab_cdef) ||
            (cim_group_bits[1] !== 32'h89ab_cdef) ||
            (cim_group_bits[2] !== 32'h89ab_cdef) ||
            (cim_group_bits[3] !== 32'h89ab_cdef)) begin
            $display("FAIL: four CIM group fanouts are not identical");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 10 - mode_sel=1 fans all 32 bits to four groups");
        end

        // Check the explicit stage/lane-to-local-row mapping boundaries.
        if ((buffered_bits[3:0]   !== 4'hf) ||
            (buffered_bits[7:4]   !== 4'he) ||
            (buffered_bits[31:28] !== 4'h8)) begin
            $display("FAIL: stage/lane to local-row ordering is incorrect");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 11 - stage 0/1/7 map to rows 0/4/28 correctly");
        end

        // Slide 3 only puts mode_sel demuxes after stages 0 and 1.  Therefore,
        // in SRAM mode rows 0..7 leave the CIM branch, while rows 8..31 remain
        // wired to the one-to-four buffers.  Downstream cim_en disables their
        // computation during real SRAM operation.
        mode_sel = 1'b0;
        #1;
        if ((sram_write_data !== 8'hef) ||
            (cim_group_bits[0] !== 32'h89ab_cd00) ||
            (cim_group_bits[1] !== 32'h89ab_cd00) ||
            (cim_group_bits[2] !== 32'h89ab_cd00) ||
            (cim_group_bits[3] !== 32'h89ab_cd00)) begin
            $display("FAIL: slide-3 partial mode routing is incorrect");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 12 - only the first two stages use mode_sel demuxes");
        end

        // Returning sel_next to load position isolates every visible output.
        sel_next = 1'b0;
        #1;
        if ((sram_write_data !== 8'b0) ||
            (cim_group_bits[0] !== 32'b0) ||
            (cim_group_bits[1] !== 32'b0) ||
            (cim_group_bits[2] !== 32'b0) ||
            (cim_group_bits[3] !== 32'b0) ||
            (buffered_bits !== 32'h89ab_cdef)) begin
            $display("FAIL: sel_next output isolation or DFF hold failed");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 13 - sel_next changes routing without corrupting DFFs");
        end

        $display("============================================================");
        if (error_count == 0) begin
            $display("PASS: all slide-3 Input Path tests passed");
        end else begin
            $display("FAIL: %0d Input Path checks failed", error_count);
            $fatal(1);
        end
        $display("============================================================");

        $finish;
    end

endmodule
