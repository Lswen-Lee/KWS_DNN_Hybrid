`timescale 1ns/1ps
// SIMULATION ONLY: restricted functional model for this project's DSP MAC.
// Not a general DSP48E1 model. Never add this file to Vivado sources.
// Official Xilinx UNISIM regression is provided separately by test-unisim.
// Port/parameter declaration follows Xilinx's Apache-2.0 UNISIM interface.
// Copyright (c) 1995/2015 Xilinx, Inc.; see ../sim_vendor/LICENSE.
 /* verilator lint_off UNUSEDPARAM */
 /* verilator lint_off UNUSEDSIGNAL */
module DSP48E1 #(
  `ifdef XIL_TIMING
  parameter LOC = "UNPLACED",  
  `endif
  parameter integer ACASCREG = 1,
  parameter integer ADREG = 1,
  parameter integer ALUMODEREG = 1,
  parameter integer AREG = 1,
  parameter AUTORESET_PATDET = "NO_RESET",
  parameter A_INPUT = "DIRECT",
  parameter integer BCASCREG = 1,
  parameter integer BREG = 1,
  parameter B_INPUT = "DIRECT",
  parameter integer CARRYINREG = 1,
  parameter integer CARRYINSELREG = 1,
  parameter integer CREG = 1,
  parameter integer DREG = 1,
  parameter integer INMODEREG = 1,
  parameter [3:0] IS_ALUMODE_INVERTED = 4'b0000,
  parameter [0:0] IS_CARRYIN_INVERTED = 1'b0,
  parameter [0:0] IS_CLK_INVERTED = 1'b0,
  parameter [4:0] IS_INMODE_INVERTED = 5'b00000,
  parameter [6:0] IS_OPMODE_INVERTED = 7'b0000000,
  parameter [47:0] MASK = 48'h3FFFFFFFFFFF,
  parameter integer MREG = 1,
  parameter integer OPMODEREG = 1,
  parameter [47:0] PATTERN = 48'h000000000000,
  parameter integer PREG = 1,
  parameter SEL_MASK = "MASK",
  parameter SEL_PATTERN = "PATTERN",
  parameter USE_DPORT = "FALSE",
  parameter USE_MULT = "MULTIPLY",
  parameter USE_PATTERN_DETECT = "NO_PATDET",
  parameter USE_SIMD = "ONE48"
)(
  output [29:0] ACOUT,
  output [17:0] BCOUT,
  output CARRYCASCOUT,
  output [3:0] CARRYOUT,
  output MULTSIGNOUT,
  output OVERFLOW,
  output [47:0] P,
  output PATTERNBDETECT,
  output PATTERNDETECT,
  output [47:0] PCOUT,
  output UNDERFLOW,

  input [29:0] A,
  input [29:0] ACIN,
  input [3:0] ALUMODE,
  input [17:0] B,
  input [17:0] BCIN,
  input [47:0] C,
  input CARRYCASCIN,
  input CARRYIN,
  input [2:0] CARRYINSEL,
  input CEA1,
  input CEA2,
  input CEAD,
  input CEALUMODE,
  input CEB1,
  input CEB2,
  input CEC,
  input CECARRYIN,
  input CECTRL,
  input CED,
  input CEINMODE,
  input CEM,
  input CEP,
  input CLK,
  input [24:0] D,
  input [4:0] INMODE,
  input MULTSIGNIN,
  input [6:0] OPMODE,
  input [47:0] PCIN,
  input RSTA,
  input RSTALLCARRYIN,
  input RSTALUMODE,
  input RSTB,
  input RSTC,
  input RSTCTRL,
  input RSTD,
  input RSTINMODE,
  input RSTM,
  input RSTP
);
  

    reg signed [42:0] m=0;
    reg signed [47:0] p_reg=0;
    assign P=p_reg;
    assign PCOUT=p_reg;
    assign ACOUT=0;
    assign BCOUT=0;
    assign CARRYCASCOUT=0;
    assign CARRYOUT=0;
    assign MULTSIGNOUT=0;
    assign OVERFLOW=0;
    assign UNDERFLOW=0;
    assign PATTERNDETECT=0;
    assign PATTERNBDETECT=0;

    initial begin
        if(AREG!=0 || BREG!=0 || ACASCREG!=0 || BCASCREG!=0 ||
           MREG!=1 || PREG!=1 || OPMODEREG!=0 || ALUMODEREG!=0 ||
           INMODEREG!=0 || CARRYINREG!=0 || CARRYINSELREG!=0 ||
           A_INPUT!="DIRECT" || B_INPUT!="DIRECT" ||
           USE_MULT!="MULTIPLY" || USE_SIMD!="ONE48" || USE_DPORT!="FALSE")
            $fatal(1,"Unsupported DSP48E1 simulation configuration");
    end
    always @(posedge CLK) begin
        if(OPMODE!==7'b0100101 || ALUMODE!==0 || INMODE!==0 ||
           CARRYIN!==0 || CARRYINSEL!==0)
            $fatal(1,"Unsupported DSP48E1 simulation operation");
        if(RSTM) m<=0;
        else if(CEM) m <= $signed(A[24:0]) * $signed(B);
        if(RSTP) p_reg<=0;
        else if(CEP) p_reg <= p_reg + {{5{m[42]}},m};
    end
endmodule
 /* verilator lint_on UNUSEDPARAM */
 /* verilator lint_on UNUSEDSIGNAL */
