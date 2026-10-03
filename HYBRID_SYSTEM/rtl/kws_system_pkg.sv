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
endpackage
