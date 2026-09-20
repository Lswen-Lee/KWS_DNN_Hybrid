`timescale 1ns/1ps

// Input path corresponding to slide 3 of 0622.pptx.
//
// The circuit contains four Din lanes.  Each lane passes through eight DFF
// stages, so one enabled bufclk loads four bits and eight clocks fill the 32
// local CIM rows.  The DFF outputs are routed by the slide's first one-to-two
// demultiplexer:
//
//   sel_next = 0 : connect each DFF to the next DFF and load the shift chain
//   sel_next = 1 : disconnect the shift path and expose the stored stage taps
//
// The first two stages of every lane also pass through the mode_sel
// demultiplexer.  In SRAM mode they form the shared eight-bit write word; in
// CIM mode they join stages 2..7 on the CIM input path.  Stages 2..7 do not
// have a mode_sel demultiplexer in the slide and therefore remain visible when
// sel_next is asserted.  The downstream CIM enable must keep computation off
// while mode_sel selects SRAM operation.
//
// rst_n is an FPGA-friendly active-low reset abstraction.  The presentation
// labels the DFF reset pin "rst" but does not specify its RTL polarity or
// synchronous/asynchronous implementation.
module input_buffer_32x4 (
    input  logic        bufclk,
    input  logic        rst_n,
    input  logic        clk_en,
    input  logic        sel_next,
    input  logic        mode_sel,       // 0: SRAM mode, 1: CIM mode
    input  logic [3:0]  din,            // din[3] is the nibble MSB

    // Raw DFF contents exposed for integration/debug.  This is not a chip pin.
    output logic [31:0] buffered_bits,

    // Two four-bit DFF stages form one shared eight-bit SRAM write word.
    output logic [7:0]  sram_write_data,

    // One-to-four buffers broadcast each local 32-row input to four row groups.
    output logic [31:0] cim_group_bits [0:3]
);

    // stage_q[stage][lane]
    //
    // stage 0, lanes 0..3 -> local rows 0..3
    // stage 1, lanes 0..3 -> local rows 4..7
    // ...
    // stage 7, lanes 0..3 -> local rows 28..31
    logic [3:0] stage_q [0:7];
    logic [31:0] cim_tap_bits;

    // The first DFF of each of the four independent lanes samples Din.
    always_ff @(posedge bufclk or negedge rst_n) begin
        if (!rst_n) begin
            stage_q[0] <= 4'b0000;
        end else if (clk_en && !sel_next) begin
            stage_q[0] <= din;
        end
    end

    // The remaining seven DFF stages sample the preceding stage.  This fixed
    // generate loop elaborates into seven banks of four flip-flops and is
    // synthesizable by Vivado.
    genvar stage_index;
    generate
        for (stage_index = 1; stage_index < 8; stage_index = stage_index + 1) begin : g_dff_stage
            always_ff @(posedge bufclk or negedge rst_n) begin
                if (!rst_n) begin
                    stage_q[stage_index] <= 4'b0000;
                end else if (clk_en && !sel_next) begin
                    stage_q[stage_index] <= stage_q[stage_index - 1];
                end
            end
        end
    endgenerate

    // Flatten the physical stage/lane arrangement into local-row order.
    // buffered_bits[(4*stage)+lane] is one stored activation bit.
    genvar tap_index;
    generate
        for (tap_index = 0; tap_index < 8; tap_index = tap_index + 1) begin : g_flatten_tap
            assign buffered_bits[(tap_index * 4) +: 4] = stage_q[tap_index];
        end
    endgenerate

    // Only the first two stages own the second (mode_sel) demultiplexer in the
    // slide.  Their SRAM-side outputs are assembled without adding another
    // register or another clock of latency.
    sram_write_buffer_8bit u_sram_write_buffer_8bit (
        .sram_path_en (sel_next && !mode_sel),
        .stage0_bits  (stage_q[0]),
        .stage1_bits  (stage_q[1]),
        .write_data   (sram_write_data)
    );

    // Slide-3 CIM tap behavior:
    //   rows 0..7  : sel_next followed by mode_sel
    //   rows 8..31 : sel_next only (there is no second demux in the drawing)
    assign cim_tap_bits[7:0]  = (sel_next && mode_sel) ?
                                  buffered_bits[7:0] : 8'b0000_0000;
    assign cim_tap_bits[31:8] = sel_next ?
                                  buffered_bits[31:8] : 24'b0;

    // The physical schematic uses one-to-four output buffers.  In
    // synthesizable RTL they are represented as four wire fanouts.
    assign cim_group_bits[0] = cim_tap_bits;
    assign cim_group_bits[1] = cim_tap_bits;
    assign cim_group_bits[2] = cim_tap_bits;
    assign cim_group_bits[3] = cim_tap_bits;

endmodule
