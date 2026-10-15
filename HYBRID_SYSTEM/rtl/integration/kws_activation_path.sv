`timescale 1ns/1ps
// S3: host / pool / PE share one RAM, reader and writer, without preemption.
// Shared-postprocess step 1: raw PE and external PoT; DCIM not yet connected.
// Host ports are local synchronous streams, NOT AXI or a board pin interface.
module kws_activation_path #(
    parameter bit RESULT_PIPELINED=1'b0,
    parameter bit POSTPROCESS_PIPELINED=1'b1
) (
    input logic clk, rst,
    input logic load_valid,
    output logic load_ready,
    input kws_system_pkg::activation_write_mode_t load_mode,
    input logic [14:0] load_base,
    input logic [15:0] load_count,
    input logic [7:0] load_width, load_height,
    input logic [5:0] load_channels,
    input logic load_data_valid,
    output logic load_data_ready,
    input logic [7:0] load_data, load_x, load_y,
    input logic [5:0] load_channel,
    output logic load_done, load_error,
    input logic read_valid,
    output logic read_ready,
    input logic [14:0] read_base,
    input logic [15:0] read_count,
    output logic read_out_valid,
    input logic read_out_ready,
    output logic [7:0] read_data,
    output logic read_last, read_done, read_error,
    input logic pool_valid,
    output logic pool_ready,
    input logic [14:0] pool_src_base, pool_dst_base,
    input logic [7:0] pool_width, pool_height,
    input logic [5:0] pool_channels,
    output logic pool_done, pool_error, fault, busy,
    input logic weight_load_valid,
    output logic weight_load_ready,
    input logic [2:0] weight_layer_id,
    input logic [7:0] weight_k,
    input logic [5:0] weight_channels,
    input logic weight_valid,
    output logic weight_ready,
    input logic signed [7:0] weight_i8,
    output logic weight_load_done, weight_load_error, resident_valid,
    input logic pe_cmd_valid,
    output logic pe_cmd_ready,
    input logic pe_is_fc, pe_relu_enable,
    input logic [2:0] pe_layer_id,
    input logic [14:0] pe_src_base, pe_dst_base,
    input logic [7:0] pe_width, pe_height, pe_vector_length,
    input logic [5:0] pe_input_channels, pe_output_channels,
    output logic pe_done, pe_error
);
    import kws_system_pkg::*;
    typedef enum logic [2:0] {HOST_IDLE, HOST_LOAD, HOST_READ, POOL, WEIGHT_LOAD, PE_RUN, FAULT} owner_t;
    owner_t owner;
    wire wc_ready, wc_done, wc_error, w_ready, w_en;
    wire rc_ready, rc_done, rc_error, r_valid, r_ready, r_last, r_en;
    wire [7:0] r_data, w_data;
    wire [14:0] w_addr, r_addr;
    wire ctrl_ready, ctrl_done, ctrl_error, ctrl_fault;
    wire pc_wvalid, pc_rvalid, pc_rready, pixel_valid, frame_start;
    wire [14:0] pc_wbase, pc_rbase;
    wire [15:0] pc_wcount, pc_rcount;
    wire [7:0] cfg_w, cfg_h, pooled_data;
    wire [4:0] cfg_c;
    wire pooled_valid;
    wire ram_valid;
    wire [7:0] ram_data;

    // Resident identity is internal; only actual successful loads validate it.
    logic [2:0] resident_layer_id,pending_layer;
    logic [7:0] resident_k,pending_k;
    logic [5:0] resident_channels,pending_channels;
    wire el_ready,el_done,el_error,engine_layer_ready,ew_ready;
    wire lc_ready,lc_done,lc_error,lc_fault;
    wire pr_cmd,pw_cmd,pr_ready,pw_valid;
    activation_read_mode_t pr_mode;
    activation_write_mode_t pw_mode;
    wire [14:0] pr_base,pw_base;
    wire [15:0] pr_count,pw_count;
    wire [7:0] pr_width,pr_height,pr_x,pr_y,pw_width,pw_height,pw_x,pw_y;
    wire [5:0] pr_channels,pw_channels,pw_channel;
    wire compute_valid,compute_ready,compute_done,compute_error;
    wire [2:0] compute_layer;
    wire compute_relu,replay_valid,replay_ready,activation_valid,activation_ready;
    wire [7:0] replay_k,pe_data;
    wire [4:0] replay_base,pe_channel;
    wire result_valid,result_ready,result_last,result_error;
    wire postprocess_empty, raw_valid, raw_ready, raw_last, raw_error;
    wire signed [31:0] raw_data;
    wire [4:0] raw_channel;
    wire raw_enable = !rst && !fault && owner == PE_RUN;
    wire post_input_ready;
    assign raw_ready = raw_enable && post_input_ready;
    wire weight_fire=weight_load_valid && weight_load_ready;

    // Priority at acceptance only: weights > PE > pool > host load > read.
    // No preemption. Unused command-valid inputs MUST be tied low.
    assign weight_load_ready = !rst && owner == HOST_IDLE && el_ready;
    assign pe_cmd_ready = !rst && owner == HOST_IDLE && !weight_load_valid && lc_ready;
    assign pool_ready = !rst && owner == HOST_IDLE && !weight_load_valid && !pe_cmd_valid && ctrl_ready;
    assign load_ready = !rst && owner == HOST_IDLE && !weight_load_valid && !pe_cmd_valid && !pool_valid && wc_ready;
    assign read_ready = !rst && owner == HOST_IDLE && !weight_load_valid && !pe_cmd_valid && !pool_valid && !load_valid && rc_ready;
    assign weight_ready = !rst && owner == WEIGHT_LOAD && ew_ready;
    assign busy = owner != HOST_IDLE;
    assign fault = ctrl_fault || lc_fault || owner == FAULT;
    assign load_data_ready = owner == HOST_LOAD && w_ready;
    assign read_out_valid = owner == HOST_READ && r_valid;
    assign read_data = r_data;
    assign read_last = r_last;
    assign r_ready = owner == POOL ? pc_rready : owner == PE_RUN ? pr_ready : (owner == HOST_READ && read_out_ready);
    // Terminal pulses remain visible while the owner is released on this edge.
    always_ff @(posedge clk) begin
        if (rst) begin
            owner <= HOST_IDLE;
            load_done <= 0; load_error <= 0; read_done <= 0; read_error <= 0;
            pool_done <= 0; pool_error <= 0;
            weight_load_done <= 0; weight_load_error <= 0; pe_done <= 0; pe_error <= 0;
            resident_valid <= 0; resident_layer_id <= 0; resident_k <= 0; resident_channels <= 0;
            pending_layer <= 0; pending_k <= 0; pending_channels <= 0;
        end else begin
            load_done <= 0; load_error <= 0; read_done <= 0; read_error <= 0;
            pool_done <= 0; pool_error <= 0;
            weight_load_done <= 0; weight_load_error <= 0; pe_done <= 0; pe_error <= 0;
            case (owner)
                HOST_IDLE: begin
                    if (weight_fire) begin
                        resident_valid <= 0;
                        pending_layer <= weight_layer_id; pending_k <= weight_k; pending_channels <= weight_channels;
                        if (weight_layer_id > 4) weight_load_error <= 1;
                        else owner <= WEIGHT_LOAD;
                    end else if (pe_cmd_valid && pe_cmd_ready) owner <= PE_RUN;
                    else if (pool_valid && pool_ready) owner <= POOL;
                    else if (load_valid && load_ready) owner <= HOST_LOAD;
                    else if (read_valid && read_ready) owner <= HOST_READ;
                end
                HOST_LOAD: if (wc_done || wc_error) begin
                    load_done <= wc_done; load_error <= wc_error; owner <= HOST_IDLE;
                end
                HOST_READ: if (rc_done || rc_error) begin
                    read_done <= rc_done; read_error <= rc_error; owner <= HOST_IDLE;
                end
                POOL: begin
                    pool_done <= ctrl_done; pool_error <= ctrl_error;
                    if (ctrl_fault) owner <= FAULT;
                    else if (ctrl_done || ctrl_error) owner <= HOST_IDLE;
                end
                WEIGHT_LOAD: if (el_done || el_error) begin
                    weight_load_done <= el_done && !el_error;
                    weight_load_error <= el_error;
                    resident_valid <= el_done && !el_error && engine_layer_ready;
                    if (el_done && !el_error) begin
                        resident_layer_id <= pending_layer; resident_k <= pending_k;
                        resident_channels <= pending_channels;
                    end
                    owner <= HOST_IDLE;
                end
                PE_RUN: begin
                    pe_done <= lc_done; pe_error <= lc_error;
                    if (lc_fault) owner <= FAULT;
                    else if (lc_done || lc_error) owner <= HOST_IDLE;
                end
                FAULT: ;
                default: owner <= HOST_IDLE;
            endcase
        end
    end

    pool_transfer_controller controller (
        .clk(clk),.rst(rst),.cmd_valid(pool_valid && pool_ready),.cmd_ready(ctrl_ready),
        .cmd_src_base(pool_src_base),.cmd_dst_base(pool_dst_base),
        .cmd_width(pool_width),.cmd_height(pool_height),.cmd_channels(pool_channels),
        .reader_cmd_valid(pc_rvalid),.reader_cmd_ready(rc_ready),.reader_done(owner==POOL && rc_done),
        .reader_error(owner==POOL && rc_error),.reader_base(pc_rbase),.reader_count(pc_rcount),
        .writer_cmd_valid(pc_wvalid),.writer_cmd_ready(wc_ready),.writer_in_ready(w_ready),
        .writer_done(owner==POOL && wc_done),.writer_error(owner==POOL && wc_error),
        .writer_base(pc_wbase),.writer_count(pc_wcount),.reader_out_valid(r_valid),
        .reader_out_ready(pc_rready),.pool_in_valid(pixel_valid),.pool_frame_start(frame_start),
        .pool_width(cfg_w),.pool_height(cfg_h),.pool_channels(cfg_c),.pool_out_valid(pooled_valid),
        .busy(),.done(ctrl_done),.error(ctrl_error),.fault(ctrl_fault)
    );
    activation_reader reader (
        .clk(clk),.rst(rst),.cmd_valid(pc_rvalid || pr_cmd || (read_valid && read_ready)),.cmd_ready(rc_ready),
        .cmd_mode(owner==PE_RUN ? pr_mode : READ_LINEAR),
        .cmd_base(owner==PE_RUN ? pr_base : owner==POOL ? pc_rbase : read_base),
        .cmd_count(owner==PE_RUN ? pr_count : owner==POOL ? pc_rcount : read_count),
        .cmd_width(pr_width),.cmd_height(pr_height),.cmd_channels(pr_channels),.cmd_x(pr_x),.cmd_y(pr_y),
        .ram_rd_en(r_en),.ram_rd_addr(r_addr),.ram_rd_valid(ram_valid),.ram_rd_data(ram_data),
        .out_valid(r_valid),.out_ready(r_ready),.out_data(r_data),.out_last(r_last),
        .busy(),.done(rc_done),.error(rc_error)
    );
    maxpool2x2_uint8 pool (
        .clk(clk),.rst(rst),.frame_start(frame_start),.in_valid(pixel_valid),.input_uint8(r_data),
        .input_width(cfg_w),.input_height(cfg_h),.input_channels(cfg_c),
        .out_valid(pooled_valid),.output_uint8(pooled_data),
        .output_channel(),.output_y(),.output_x(),.out_frame_done()
    );
    feature_map_writer writer (
        .clk(clk),.rst(rst),.cmd_valid(pc_wvalid || pw_cmd || (load_valid && load_ready)),.cmd_ready(wc_ready),
        .cmd_mode(owner==PE_RUN ? pw_mode : owner==POOL ? WRITE_LINEAR : load_mode),
        .cmd_base(owner==PE_RUN ? pw_base : owner==POOL ? pc_wbase : load_base),
        .cmd_count(owner==PE_RUN ? pw_count : owner==POOL ? pc_wcount : load_count),
        .cmd_width(owner==PE_RUN ? pw_width : load_width),
        .cmd_height(owner==PE_RUN ? pw_height : load_height),
        .cmd_channels(owner==PE_RUN ? pw_channels : load_channels),
        .in_valid(!fault && (owner==PE_RUN ? pw_valid : owner==POOL ? pooled_valid : (owner==HOST_LOAD && load_data_valid))),
        .in_ready(w_ready),.in_data(owner==PE_RUN ? pe_data : owner==POOL ? pooled_data : load_data),
        .in_channel(owner==PE_RUN ? pw_channel : load_channel),
        .in_y(owner==PE_RUN ? pw_y : load_y),.in_x(owner==PE_RUN ? pw_x : load_x),
        .wr_en(w_en),.wr_addr(w_addr),.wr_data(w_data),.busy(),.done(wc_done),.error(wc_error)
    );
    pe_layer_controller pe_controller (
        .clk(clk),.rst(rst),.cmd_valid(pe_cmd_valid && pe_cmd_ready),.cmd_ready(lc_ready),
        .cmd_is_fc(pe_is_fc),.cmd_layer_id(pe_layer_id),.cmd_relu_enable(pe_relu_enable),
        .cmd_src_base(pe_src_base),.cmd_dst_base(pe_dst_base),.cmd_width(pe_width),.cmd_height(pe_height),
        .cmd_vector_length(pe_vector_length),.cmd_input_channels(pe_input_channels),.cmd_output_channels(pe_output_channels),
        .resident_valid(resident_valid && engine_layer_ready),.resident_layer_id(resident_layer_id),
        .resident_k(resident_k),.resident_channels(resident_channels),.busy(),.done(lc_done),.error(lc_error),.fault(lc_fault),
        .reader_cmd_valid(pr_cmd),.reader_cmd_ready(rc_ready),.reader_done(owner==PE_RUN && rc_done),
        .reader_error(owner==PE_RUN && rc_error),.reader_mode(pr_mode),.reader_base(pr_base),.reader_count(pr_count),
        .reader_width(pr_width),.reader_height(pr_height),.reader_channels(pr_channels),.reader_x(pr_x),.reader_y(pr_y),
        .reader_out_valid(owner==PE_RUN && r_valid),.reader_out_last(r_last),.reader_out_ready(pr_ready),
        .pe_compute_valid(compute_valid),.pe_compute_ready(compute_ready),.pe_compute_done(compute_done),
        .pe_compute_error(compute_error),.pe_layer_id(compute_layer),.pe_relu_enable(compute_relu),
        .postprocess_empty(postprocess_empty),
        .pe_replay_valid(replay_valid),.pe_replay_ready(replay_ready),.pe_replay_k(replay_k),.pe_replay_channel_base(replay_base),
        .pe_activation_valid(activation_valid),.pe_activation_ready(activation_ready),
        .pe_out_valid(result_valid),.pe_out_group_last(result_last),.pe_out_error(result_error),
        .pe_out_channel_id(pe_channel),.pe_out_ready(result_ready),
        .writer_cmd_valid(pw_cmd),.writer_cmd_ready(wc_ready),.writer_in_ready(owner==PE_RUN && w_ready),
        .writer_done(owner==PE_RUN && wc_done),.writer_error(owner==PE_RUN && wc_error),
        .writer_mode(pw_mode),.writer_base(pw_base),.writer_count(pw_count),.writer_width(pw_width),
        .writer_height(pw_height),.writer_channels(pw_channels),.writer_in_valid(pw_valid),
        .writer_channel(pw_channel),.writer_x(pw_x),.writer_y(pw_y)
    );
    pe_memory_engine #(.PE8_MODE(1'b1),.RESULT_PIPELINED(RESULT_PIPELINED),
        .INPUT_ZERO_POINT(128)) pe_engine (
        .clk(clk),.rst(rst),.load_valid(weight_fire && weight_layer_id<=4),.load_ready(el_ready),
        .load_k(weight_k),.load_channels(weight_channels),.load_busy(),.load_done(el_done),.load_error(el_error),
        .layer_ready(engine_layer_ready),.weight_valid(owner==WEIGHT_LOAD && weight_valid),.weight_ready(ew_ready),.weight_i8(weight_i8),
        .compute_valid(compute_valid),.compute_ready(compute_ready),
        .compute_busy(),.compute_done(compute_done),.compute_error(compute_error),
        .replay_valid(replay_valid),.replay_ready(replay_ready),.replay_k(replay_k),.replay_channel_base(replay_base),
        .activation_valid(activation_valid),.activation_ready(activation_ready),.activation_u8(r_data),
        .out_valid(raw_valid),.out_ready(raw_ready),.out_data(raw_data),.out_channel_id(raw_channel),
        .out_group_last(raw_last),.out_error(raw_error)
    );
    // Step 1: one external postprocessor; DCIM selection is a later milestone.
    pot_result_stream #(.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) postprocess (
        .clk(clk),.rst(rst),.in_valid(raw_valid && raw_enable),.in_ready(post_input_ready),
        .accumulator(raw_data),.layer_id(compute_layer),.channel_id(raw_channel),
        .in_last(raw_last),.in_error(raw_error),.relu_enable(compute_relu),
        .out_valid(result_valid),.out_ready(result_ready),.output_uint8(pe_data),
        .out_channel_id(pe_channel),.out_last(result_last),.out_error(result_error),
        .empty(postprocess_empty)
    );
    activation_buffer memory (
        .clk(clk),.rst(rst),.wr_en(w_en && !fault),.wr_addr(w_addr),.wr_data(w_data),
        .rd_en(r_en),.rd_addr(r_addr),.rd_valid(ram_valid),.rd_data(ram_data)
    );
endmodule
