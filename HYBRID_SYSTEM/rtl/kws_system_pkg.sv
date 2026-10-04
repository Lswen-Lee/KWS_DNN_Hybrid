`timescale 1ns/1ps
package kws_system_pkg;
    localparam integer ACT_DATA_WIDTH = 8;
    localparam integer ACT_DEPTH = 32768;
    localparam integer ACT_ADDR_WIDTH = 15;
    localparam integer ACT_COUNT_WIDTH = 16;
    localparam logic [7:0] ACT_ZERO_POINT = 8'd128;
    typedef logic [ACT_DATA_WIDTH-1:0] activation_t;
    typedef logic [ACT_ADDR_WIDTH-1:0] activation_addr_t;
    typedef logic [ACT_COUNT_WIDTH-1:0] activation_count_t;
    typedef enum logic {READ_LINEAR, READ_PATCH} activation_read_mode_t;
    typedef enum logic {WRITE_LINEAR, WRITE_CHW} activation_write_mode_t;
    typedef enum logic [1:0] {RUN_FRONTEND, RUN_FC_TAIL, RUN_FULL} inference_mode_t;
    typedef enum logic [1:0] {OP_POOL, OP_CONV, OP_FC} layer_op_t;
    typedef enum logic [1:0] {BACKEND_POOL, BACKEND_PE, BACKEND_DCIM} layer_backend_t;
    typedef struct packed {
        layer_op_t op_kind;
        layer_backend_t backend;
        logic [2:0] layer_id;
        logic [14:0] src_base, dst_base;
        logic [7:0] input_width, input_height;
        logic [5:0] input_channels, output_channels;
        logic [7:0] k;
        logic relu_enable;
    } layer_descriptor_t;
    typedef enum logic [3:0] {
        LERR_NONE, LERR_MODE, LERR_DESCRIPTOR, LERR_SOURCE,
        LERR_INPUT, LERR_WEIGHT, LERR_OPERATION, LERR_PATH
    } layer_error_t;
endpackage
