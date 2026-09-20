# Simulation-only Xilinx primitive model

DSP48E1.v is an unmodified download from the official Xilinx repository:
https://github.com/Xilinx/XilinxUnisimLibrary/blob/master/verilog/src/unisims/DSP48E1.v

Downloaded 2026-09-12. SHA256:
`a98661443ef3a3b41a64d1d26d20326ebc4f229a84e96192c02759e6b9f8b7b5`

Apache-2.0 license is preserved in LICENSE and source headers. The model identifies itself as 2016.1; it is not claimed to be the exact Vivado 2023.2 bundled model.

glbl.v is a local GSR=0 stub; testbenches explicitly assert synchronous reset. FPGA configuration startup and analog/device timing are not simulated. Array weights start X and are driven known with reset, so zero weights also create an initialization transition in event-driven simulation.

Run `make test-unisim` with Icarus Verilog and vvp installed. IVERILOG, IVL_FLAGS and VVP can override locations. This runs both lane tests, both array tests and the cross-version comparison against the official primitive model.

Verilator cannot execute this model's procedural assign/deassign. Regular `make test lint` uses the separate restricted functional model in sim_verilator/DSP48E1.v. That model checks supported configuration/operation and is not a general-purpose DSP model. Do not confuse its test success with vendor-model success.

NEVER import sim_vendor or sim_verilator into Vivado synthesis. Vivado resolves the RTL DSP48E1 instance from its own primitive library; XSim should also use its bundled UNISIM instead of these copies.
