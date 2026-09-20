`timescale 1ns/1ps

// Shared centered activation; one independent output-stationary ACC per lane.
// Each lane has a product pipeline stage. Drain one clock after the last input.
// No K counter, result handshake or quantization is added.
module pe_array_12 (
    input logic clk,
    input logic rst,
    input logic clear,
    input logic accumulate_en,
    input logic [pe_pkg::LANE_COUNT-1:0] lane_mask,
    input pe_pkg::activation_t activation_centered,
    input logic [pe_pkg::WEIGHT_VECTOR_WIDTH-1:0] weight_vector_i8,
    output logic [pe_pkg::RESULT_VECTOR_WIDTH-1:0] result_vector_s32
);
    // Fixed 12-lane implementation; explicit slices show the packing order.
    // All lanes share activation/control but have independent weights and sums.

    // PE 0: weight bits [7:0], result bits [31:0].
    pe_mac_lane pe_lane_0 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[0]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[7:0])),
        .accumulator         (result_vector_s32[31:0])
    );

    // PE 1: weight bits [15:8], result bits [63:32].
    pe_mac_lane pe_lane_1 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[1]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[15:8])),
        .accumulator         (result_vector_s32[63:32])
    );

    // PE 2: weight bits [23:16], result bits [95:64].
    pe_mac_lane pe_lane_2 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[2]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[23:16])),
        .accumulator         (result_vector_s32[95:64])
    );

    // PE 3: weight bits [31:24], result bits [127:96].
    pe_mac_lane pe_lane_3 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[3]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[31:24])),
        .accumulator         (result_vector_s32[127:96])
    );

    // PE 4: weight bits [39:32], result bits [159:128].
    pe_mac_lane pe_lane_4 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[4]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[39:32])),
        .accumulator         (result_vector_s32[159:128])
    );

    // PE 5: weight bits [47:40], result bits [191:160].
    pe_mac_lane pe_lane_5 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[5]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[47:40])),
        .accumulator         (result_vector_s32[191:160])
    );

    // PE 6: weight bits [55:48], result bits [223:192].
    pe_mac_lane pe_lane_6 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[6]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[55:48])),
        .accumulator         (result_vector_s32[223:192])
    );

    // PE 7: weight bits [63:56], result bits [255:224].
    pe_mac_lane pe_lane_7 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[7]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[63:56])),
        .accumulator         (result_vector_s32[255:224])
    );

    // PE 8: weight bits [71:64], result bits [287:256].
    pe_mac_lane pe_lane_8 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[8]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[71:64])),
        .accumulator         (result_vector_s32[287:256])
    );

    // PE 9: weight bits [79:72], result bits [319:288].
    pe_mac_lane pe_lane_9 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[9]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[79:72])),
        .accumulator         (result_vector_s32[319:288])
    );

    // PE 10: weight bits [87:80], result bits [351:320].
    pe_mac_lane pe_lane_10 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[10]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[87:80])),
        .accumulator         (result_vector_s32[351:320])
    );

    // PE 11: weight bits [95:88], result bits [383:352].
    pe_mac_lane pe_lane_11 (
        .clk                 (clk),
        .rst                 (rst),
        .clear               (clear),
        .accumulate_en       (accumulate_en && lane_mask[11]),
        .activation_centered (activation_centered),
        .weight_i8           ($signed(weight_vector_i8[95:88])),
        .accumulator         (result_vector_s32[383:352])
    );
endmodule
