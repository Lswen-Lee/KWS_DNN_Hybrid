`timescale 1ns/1ps
// Simulation ONLY; never import into the Vivado synthesis fileset.
module IBUF(input wire I, output wire O); assign O=I; endmodule
module BUFG(input wire I, output wire O); assign O=I; endmodule
