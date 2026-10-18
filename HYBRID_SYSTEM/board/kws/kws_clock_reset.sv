`timescale 1ns/1ps
module kws_clock_reset #(parameter integer RELEASE_CYCLES=2500000) (
    input logic sys_clk_125m, reset_button,
    output wire clk, clk_cim, locked, rst, rst_cim
);
`ifndef VERILATOR
    wire input_clock,feedback,feedback_buf,cim_unbuffered;
    IBUF input_buffer(.I(sys_clk_125m),.O(input_clock));
    BUFG system_buffer(.I(input_clock),.O(clk));
    // Same 53MHz pair as the existing DCIM frequency sweep:
    // VCO=125*6.625=828.125MHz; CLKOUT0=828.125/15.625=53MHz.
    MMCME2_BASE #(.CLKIN1_PERIOD(8.0),.DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(6.625),.CLKOUT0_DIVIDE_F(15.625),.STARTUP_WAIT("FALSE")) mmcm (
        .CLKIN1(input_clock),.CLKFBIN(feedback_buf),.RST(reset_button),.PWRDWN(1'b0),
        .CLKFBOUT(feedback),.CLKOUT0(cim_unbuffered),.LOCKED(locked)
    );
    BUFG feedback_buffer(.I(feedback),.O(feedback_buf));
    BUFG cim_buffer(.I(cim_unbuffered),.O(clk_cim));
`else
    // Functional simulation ONLY: independent oscillator, not a UNISIM model.
    logic sim_cim=0;
    initial forever #9.434 sim_cim=~sim_cim;
    assign clk=sys_clk_125m;
    assign clk_cim=sim_cim;
    assign locked=!reset_button;
`endif
    // Button asserts common reset immediately; contact bounce extends reset.
    // Release requires stable synchronized low button + lock for 20ms at 125MHz.
    (* ASYNC_REG="TRUE" *) logic [1:0] button_sync=2'b11;
    (* ASYNC_REG="TRUE" *) logic [1:0] lock_sync=2'b00;
    localparam integer CW=RELEASE_CYCLES<=1 ? 1 : $clog2(RELEASE_CYCLES);
    logic [CW-1:0] release_count=0;
    logic release_ready=0;
    always_ff @(posedge clk) begin
        button_sync<={button_sync[0],reset_button};
        lock_sync<={lock_sync[0],locked};
    end
    wire startup_reset=reset_button || !locked;
    always_ff @(posedge clk or posedge startup_reset) begin
        if(startup_reset) begin release_count<=0; release_ready<=0; end
        else
        if(button_sync[1] || !lock_sync[1]) begin release_count<=0; release_ready<=0; end
        else if(!release_ready) begin
            if(release_count==CW'(RELEASE_CYCLES-1)) release_ready<=1;
            else release_count<=release_count+1'b1;
        end
    end
    wire common_reset=reset_button || !locked || !release_ready;
    (* ASYNC_REG="TRUE" *) logic [3:0] sys_reset_sync=4'b1111;
    (* ASYNC_REG="TRUE" *) logic [3:0] cim_reset_sync=4'b1111;
    always_ff @(posedge clk or posedge common_reset)
        if(common_reset) sys_reset_sync<=4'b1111;
        else sys_reset_sync<={sys_reset_sync[2:0],1'b0};
    always_ff @(posedge clk_cim or posedge common_reset)
        if(common_reset) cim_reset_sync<=4'b1111;
        else cim_reset_sync<={cim_reset_sync[2:0],1'b0};
    assign rst=sys_reset_sync[3];
    assign rst_cim=cim_reset_sync[3];
endmodule
