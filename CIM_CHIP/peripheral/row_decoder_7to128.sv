`timescale 1ns/1ps

// Seven-to-128 wordline decoder for SRAM read and write operations.
//
// The decoder follows the hierarchy shown in the design presentation:
//   A[2:0] -> 3-to-8 low-address predecoder
//   A[6:3] -> 4-to-16 high-address predecoder
//
// One high predecode line and one low predecode line are combined to form
// each of the 128 wordlines.  wl_en is kept separate from write_en and
// sense_en so the controller can disable every wordline while the address is
// changing.
module row_decoder_7to128 (
    input  logic [6:0]   row_addr,
    input  logic         wl_en,
    output logic [127:0] wl_select
);

    logic [7:0]  low_decode;
    logic [15:0] high_decode;

    // A0-A2 select one of eight rows inside a predecode group.
    always_comb begin
        low_decode = 8'b0;
        low_decode[row_addr[2:0]] = 1'b1;
    end

    // A3-A6 select one of sixteen predecode groups.
    always_comb begin
        high_decode = 16'b0;
        high_decode[row_addr[6:3]] = 1'b1;
    end

    // Combine 16 high groups with eight local rows: 16 x 8 = 128 WLs.
    // These are elaboration-time generate loops and are synthesizable by
    // Vivado as combinational decode logic.
    genvar high_index;
    genvar low_index;
    generate
        for (high_index = 0; high_index < 16; high_index = high_index + 1) begin : gen_high_group
            for (low_index = 0; low_index < 8; low_index = low_index + 1) begin : gen_low_row
                assign wl_select[(high_index * 8) + low_index] =
                    wl_en & high_decode[high_index] & low_decode[low_index];
            end
        end
    endgenerate

endmodule
