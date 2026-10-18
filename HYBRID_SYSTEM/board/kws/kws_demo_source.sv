`timescale 1ns/1ps
// Fixed FULL-only source. One input followed by layers 0..4 per common reset.
// No generated intermediate tensors are sent to the inference engine.
module kws_demo_source #(parameter DEMO_FILE="kws_demo.mem") (
    input logic clk, rst, enable,
    input logic input_request_valid, input_is_flatten,
    input logic [15:0] input_count,
    output logic input_request_ready, input_valid,
    input logic input_ready,
    output logic [7:0] input_data,
    input logic weight_request_valid,
    input logic [2:0] weight_layer_id,
    input logic [7:0] weight_k,
    input logic [5:0] weight_channels,
    output logic weight_request_ready, weight_valid,
    input logic weight_ready,
    output logic signed [7:0] weight_i8,
    output logic fault, busy
);
    typedef enum logic [1:0] {IDLE, ROM_READ, SEND, FAULT} state_t;
    state_t state;
    logic sending_weight, input_served;
    logic [2:0] next_layer;
    logic [13:0] address;
    logic [15:0] remaining, selected_count;
    logic [13:0] selected_base;
    logic legal_weight;
    logic [7:0] rom_data;
    wire active = enable && !rst;
    wire consume = sending_weight ? weight_ready : input_ready;
    assign input_request_ready = active && state==IDLE;
    assign weight_request_ready = active && state==IDLE && !input_request_valid;
    assign input_valid = active && state==SEND && !sending_weight;
    assign weight_valid = active && state==SEND && sending_weight;
    assign input_data = rom_data;
    assign weight_i8 = $signed(rom_data);
    assign fault = state==FAULT;
    assign busy = state!=IDLE;
    kws_demo_rom #(.DEMO_FILE(DEMO_FILE)) rom (
        .clk(clk), .en(active && state==ROM_READ), .address(address), .data(rom_data)
    );
    always_comb begin
        selected_base=0; selected_count=0; legal_weight=0;
        case(weight_layer_id)
            0: begin selected_base=8064; selected_count=108; legal_weight=weight_k==9 && weight_channels==12; end
            1: begin selected_base=8172; selected_count=1296; legal_weight=weight_k==108 && weight_channels==12; end
            2: begin selected_base=9468; selected_count=1296; legal_weight=weight_k==108 && weight_channels==12; end
            3: begin selected_base=10764; selected_count=4608; legal_weight=weight_k==144 && weight_channels==32; end
            4: begin selected_base=15372; selected_count=256; legal_weight=weight_k==32 && weight_channels==8; end
            default: ;
        endcase
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE; sending_weight<=0; input_served<=0; next_layer<=0;
            address<=0; remaining<=0;
        end else if(enable) begin
            case(state)
                IDLE: begin
                    if(input_request_valid && input_request_ready) begin
                        if(input_served || input_is_flatten || input_count!=8064) state<=FAULT;
                        else begin sending_weight<=0; address<=0; remaining<=8064; state<=ROM_READ; end
                    end else if(weight_request_valid && weight_request_ready) begin
                        if(!input_served || next_layer>4 || weight_layer_id!=next_layer || !legal_weight) state<=FAULT;
                        else begin
                            sending_weight<=1; address<=selected_base; remaining<=selected_count; state<=ROM_READ;
                        end
                    end
                end
                ROM_READ: state<=SEND; // On this edge synchronous ROM captures data.
                SEND: if(consume) begin
                    if(remaining==1) begin
                        if(sending_weight) next_layer<=next_layer+1'b1;
                        else input_served<=1;
                        remaining<=0; state<=IDLE;
                    end else begin remaining<=remaining-1'b1; address<=address+1'b1; state<=ROM_READ; end
                end
                FAULT: ; // Reset both source and inference engine to recover.
                default: state<=FAULT;
            endcase
        end
    end
endmodule
