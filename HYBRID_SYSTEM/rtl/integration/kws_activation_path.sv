`timescale 1ns/1ps
// S2: host load / host readback / memory-to-memory pool are mutually exclusive.
// Host ports are local synchronous streams, NOT AXI or a board pin interface.
module kws_activation_path (
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
    output logic pool_done, pool_error, fault, busy
);
    import kws_system_pkg::*;
    typedef enum logic [1:0] {HOST_IDLE, HOST_LOAD, HOST_READ, POOL} owner_t;
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

    // Fixed priority at command acceptance only: pool > load > readback.
    assign pool_ready = !rst && owner == HOST_IDLE && ctrl_ready;
    assign load_ready = !rst && owner == HOST_IDLE && !pool_valid && wc_ready;
    assign read_ready = !rst && owner == HOST_IDLE && !pool_valid && !load_valid && rc_ready;
    assign busy = owner != HOST_IDLE;
    assign fault = ctrl_fault;
    assign load_data_ready = owner == HOST_LOAD && w_ready;
    assign read_out_valid = owner == HOST_READ && r_valid;
    assign read_data = r_data;
    assign read_last = r_last;
    assign r_ready = owner == POOL ? pc_rready : (owner == HOST_READ && read_out_ready);
    // Terminal pulses remain visible while the owner is released on this edge.
    always_ff @(posedge clk) begin
        if (rst) begin
            owner <= HOST_IDLE;
            load_done <= 0; load_error <= 0; read_done <= 0; read_error <= 0;
            pool_done <= 0; pool_error <= 0;
        end else begin
            load_done <= 0; load_error <= 0; read_done <= 0; read_error <= 0;
            pool_done <= 0; pool_error <= 0;
            case (owner)
                HOST_IDLE: begin
                    if (pool_valid && pool_ready) owner <= POOL;
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
                    if ((ctrl_done || ctrl_error) && !ctrl_fault) owner <= HOST_IDLE;
                end
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
        .clk(clk),.rst(rst),.cmd_valid(pc_rvalid || (read_valid && read_ready)),.cmd_ready(rc_ready),
        .cmd_mode(READ_LINEAR),.cmd_base(owner==POOL ? pc_rbase : read_base),
        .cmd_count(owner==POOL ? pc_rcount : read_count),.cmd_width(8'd0),.cmd_height(8'd0),
        .cmd_channels(6'd0),.cmd_x(8'd0),.cmd_y(8'd0),
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
        .clk(clk),.rst(rst),.cmd_valid(pc_wvalid || (load_valid && load_ready)),.cmd_ready(wc_ready),
        .cmd_mode(owner==POOL ? WRITE_LINEAR : load_mode),
        .cmd_base(owner==POOL ? pc_wbase : load_base),.cmd_count(owner==POOL ? pc_wcount : load_count),
        .cmd_width(load_width),.cmd_height(load_height),.cmd_channels(load_channels),
        .in_valid(owner==POOL ? (pooled_valid && !fault) : (owner==HOST_LOAD && load_data_valid)),
        .in_ready(w_ready),.in_data(owner==POOL ? pooled_data : load_data),
        .in_channel(load_channel),.in_y(load_y),.in_x(load_x),
        .wr_en(w_en),.wr_addr(w_addr),.wr_data(w_data),.busy(),.done(wc_done),.error(wc_error)
    );
    activation_buffer memory (
        .clk(clk),.rst(rst),.wr_en(w_en && !fault),.wr_addr(w_addr),.wr_data(w_data),
        .rd_en(r_en),.rd_addr(r_addr),.rd_valid(ram_valid),.rd_data(ram_data)
    );
endmodule
