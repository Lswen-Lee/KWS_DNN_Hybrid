`timescale 1ns/1ps

// Sequential argmax for eight UINT8 FC2 results.  The module consumes eight
// accepted values in class order 0..7 and produces one 3-bit class index.
// A strict greater-than comparison preserves the first index on a tie, which
// matches torch.argmax.  clear aborts a partially collected set.
module argmax_8 (
    input  logic       clk,
    input  logic       rst,
    input  logic       clear,
    input  logic       in_valid,
    input  logic [7:0] input_uint8,
    output logic       out_valid,
    output logic [2:0] class_index,
    output logic [7:0] maximum_value
);

    logic [2:0] sample_count;
    logic [2:0] best_index;
    logic [7:0] best_value;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            sample_count  <= 3'd0;
            best_index    <= 3'd0;
            best_value    <= 8'd0;
            out_valid     <= 1'b0;
            class_index   <= 3'd0;
            maximum_value <= 8'd0;
        end else begin
            out_valid <= 1'b0;

            if (in_valid) begin
                if (sample_count == 3'd0) begin
                    best_index <= 3'd0;
                    best_value <= input_uint8;
                end else if (input_uint8 > best_value) begin
                    best_index <= sample_count;
                    best_value <= input_uint8;
                end

                if (sample_count == 3'd7) begin
                    if (input_uint8 > best_value) begin
                        class_index   <= 3'd7;
                        maximum_value <= input_uint8;
                    end else begin
                        class_index   <= best_index;
                        maximum_value <= best_value;
                    end
                    out_valid    <= 1'b1;
                    sample_count <= 3'd0;
                end else begin
                    sample_count <= sample_count + 3'd1;
                end
            end
        end
    end

endmodule
