# Verilator regression entry point for the DCIM RTL hierarchy.
# Future segment/array/chip tests can be added without changing how users run
# the existing cell-level regression.

SHELL := /bin/bash

VERILATOR ?= verilator

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CIM_ROOT     := $(patsubst %/,%,$(MAKEFILE_DIR))
BUILD_ROOT  ?= $(CIM_ROOT)/build/sim

CELL_DIR    := $(CIM_ROOT)/cell
CELL_TB_DIR := $(CIM_ROOT)/tb/cell
SEGMENT_DIR := $(CIM_ROOT)/segment
SEGMENT_TB_DIR := $(CIM_ROOT)/tb/segment
PERIPHERAL_DIR := $(CIM_ROOT)/peripheral
PERIPHERAL_TB_DIR := $(CIM_ROOT)/tb/peripheral
ARRAY_DIR := $(CIM_ROOT)/array
ARRAY_TB_DIR := $(CIM_ROOT)/tb/array
CHIP_DIR := $(CIM_ROOT)/chip
CHIP_TB_DIR := $(CIM_ROOT)/tb/chip
FPGA_DIR := $(CIM_ROOT)/fpga
FPGA_TB_DIR := $(CIM_ROOT)/tb/fpga

FESRAM_TOP  := tb_fesram_cell_model
FESRAM_MDIR := $(BUILD_ROOT)/cell/fesram
FESRAM_BIN  := $(FESRAM_MDIR)/V$(FESRAM_TOP)
FESRAM_SRCS := \
	$(CELL_DIR)/fesram_cell_model.sv \
	$(CELL_TB_DIR)/tb_fesram_cell_model.sv

DCIM_TOP    := tb_dcim_cell_logic
DCIM_MDIR   := $(BUILD_ROOT)/cell/dcim
DCIM_BIN    := $(DCIM_MDIR)/V$(DCIM_TOP)
DCIM_SRCS   := \
	$(CELL_DIR)/fesram_cell_model.sv \
	$(CELL_DIR)/dcim_cell_logic.sv \
	$(CELL_TB_DIR)/tb_dcim_cell_logic.sv

ROW_TOP     := tb_dcim_row_4bit
ROW_MDIR    := $(BUILD_ROOT)/segment/row_4bit
ROW_BIN     := $(ROW_MDIR)/V$(ROW_TOP)
ROW_SRCS    := \
	$(CELL_DIR)/fesram_cell_model.sv \
	$(CELL_DIR)/dcim_cell_logic.sv \
	$(SEGMENT_DIR)/dcim_row_4bit.sv \
	$(SEGMENT_TB_DIR)/tb_dcim_row_4bit.sv

ADDER_TOP   := tb_adder_tree_32x4
ADDER_MDIR  := $(BUILD_ROOT)/segment/adder_tree_32x4
ADDER_BIN   := $(ADDER_MDIR)/V$(ADDER_TOP)
ADDER_SRCS  := \
	$(SEGMENT_DIR)/adder_tree_32x4.sv \
	$(SEGMENT_TB_DIR)/tb_adder_tree_32x4.sv

BANK_TOP    := tb_dcim_bank_32x4
BANK_MDIR   := $(BUILD_ROOT)/segment/bank_32x4
BANK_BIN    := $(BANK_MDIR)/V$(BANK_TOP)
BANK_SRCS   := \
	$(CELL_DIR)/fesram_cell_model.sv \
	$(CELL_DIR)/dcim_cell_logic.sv \
	$(SEGMENT_DIR)/dcim_row_4bit.sv \
	$(SEGMENT_DIR)/dcim_bank_32x4.sv \
	$(SEGMENT_TB_DIR)/tb_dcim_bank_32x4.sv

ROW_DECODER_TOP  := tb_row_decoder_7to128
ROW_DECODER_MDIR := $(BUILD_ROOT)/peripheral/row_decoder_7to128
ROW_DECODER_BIN  := $(ROW_DECODER_MDIR)/V$(ROW_DECODER_TOP)
ROW_DECODER_SRCS := \
	$(PERIPHERAL_DIR)/row_decoder_7to128.sv \
	$(PERIPHERAL_TB_DIR)/tb_row_decoder_7to128.sv

CIM_GROUP_DECODER_TOP  := tb_cim_group_decoder_2to4
CIM_GROUP_DECODER_MDIR := $(BUILD_ROOT)/peripheral/cim_group_decoder_2to4
CIM_GROUP_DECODER_BIN  := $(CIM_GROUP_DECODER_MDIR)/V$(CIM_GROUP_DECODER_TOP)
CIM_GROUP_DECODER_SRCS := \
	$(PERIPHERAL_DIR)/cim_group_decoder_2to4.sv \
	$(PERIPHERAL_TB_DIR)/tb_cim_group_decoder_2to4.sv

INPUT_BUFFER_TOP  := tb_input_buffer_32x4
INPUT_BUFFER_MDIR := $(BUILD_ROOT)/peripheral/input_buffer_32x4
INPUT_BUFFER_BIN  := $(INPUT_BUFFER_MDIR)/V$(INPUT_BUFFER_TOP)
INPUT_BUFFER_SRCS := \
	$(PERIPHERAL_DIR)/sram_write_buffer_8bit.sv \
	$(PERIPHERAL_DIR)/input_buffer_32x4.sv \
	$(PERIPHERAL_TB_DIR)/tb_input_buffer_32x4.sv

SRAM_WRITE_BUFFER_TOP  := tb_sram_write_buffer_8bit
SRAM_WRITE_BUFFER_MDIR := $(BUILD_ROOT)/peripheral/sram_write_buffer_8bit
SRAM_WRITE_BUFFER_BIN  := $(SRAM_WRITE_BUFFER_MDIR)/V$(SRAM_WRITE_BUFFER_TOP)
SRAM_WRITE_BUFFER_SRCS := \
	$(PERIPHERAL_DIR)/sram_write_buffer_8bit.sv \
	$(PERIPHERAL_TB_DIR)/tb_sram_write_buffer_8bit.sv

BITSERIAL_ACCUMULATOR_TOP  := tb_bitserial_accumulator
BITSERIAL_ACCUMULATOR_MDIR := $(BUILD_ROOT)/peripheral/bitserial_accumulator
BITSERIAL_ACCUMULATOR_BIN  := $(BITSERIAL_ACCUMULATOR_MDIR)/V$(BITSERIAL_ACCUMULATOR_TOP)
BITSERIAL_ACCUMULATOR_SRCS := \
	$(PERIPHERAL_DIR)/serial_output.sv \
	$(PERIPHERAL_DIR)/bitserial_accumulator.sv \
	$(PERIPHERAL_TB_DIR)/tb_bitserial_accumulator.sv

SERIAL_OUTPUT_TOP  := tb_serial_output
SERIAL_OUTPUT_MDIR := $(BUILD_ROOT)/peripheral/serial_output
SERIAL_OUTPUT_BIN  := $(SERIAL_OUTPUT_MDIR)/V$(SERIAL_OUTPUT_TOP)
SERIAL_OUTPUT_SRCS := \
	$(PERIPHERAL_DIR)/serial_output.sv \
	$(PERIPHERAL_TB_DIR)/tb_serial_output.sv

SRAM_READ_SERIALIZER_TOP  := tb_sram_read_serializer_8bit
SRAM_READ_SERIALIZER_MDIR := $(BUILD_ROOT)/peripheral/sram_read_serializer_8bit
SRAM_READ_SERIALIZER_BIN  := $(SRAM_READ_SERIALIZER_MDIR)/V$(SRAM_READ_SERIALIZER_TOP)
SRAM_READ_SERIALIZER_SRCS := \
	$(PERIPHERAL_DIR)/sram_read_serializer_8bit.sv \
	$(PERIPHERAL_TB_DIR)/tb_sram_read_serializer_8bit.sv

BANK_DECODER_TOP  := tb_bank_decoder_4to16
BANK_DECODER_MDIR := $(BUILD_ROOT)/peripheral/bank_decoder_4to16
BANK_DECODER_BIN  := $(BANK_DECODER_MDIR)/V$(BANK_DECODER_TOP)
BANK_DECODER_SRCS := \
	$(PERIPHERAL_DIR)/bank_decoder_4to16.sv \
	$(PERIPHERAL_TB_DIR)/tb_bank_decoder_4to16.sv

BANK_PAIR_SELECTOR_TOP  := tb_bank_pair_selector
BANK_PAIR_SELECTOR_MDIR := $(BUILD_ROOT)/array/bank_pair_selector
BANK_PAIR_SELECTOR_BIN  := $(BANK_PAIR_SELECTOR_MDIR)/V$(BANK_PAIR_SELECTOR_TOP)
BANK_PAIR_SELECTOR_SRCS := \
	$(ARRAY_DIR)/bank_pair_selector.sv \
	$(ARRAY_TB_DIR)/tb_bank_pair_selector.sv

BANK_OUTPUT_OR_TREE_TOP  := tb_bank_output_or_tree
BANK_OUTPUT_OR_TREE_MDIR := $(BUILD_ROOT)/array/bank_output_or_tree
BANK_OUTPUT_OR_TREE_BIN  := $(BANK_OUTPUT_OR_TREE_MDIR)/V$(BANK_OUTPUT_OR_TREE_TOP)
BANK_OUTPUT_OR_TREE_SRCS := \
	$(ARRAY_DIR)/bank_output_or_tree.sv \
	$(ARRAY_TB_DIR)/tb_bank_output_or_tree.sv

ROW_GROUP_TOP  := tb_dcim_row_group
ROW_GROUP_MDIR := $(BUILD_ROOT)/array/dcim_row_group
ROW_GROUP_BIN  := $(ROW_GROUP_MDIR)/V$(ROW_GROUP_TOP)
ROW_GROUP_SRCS := \
	$(CELL_DIR)/fesram_cell_model.sv \
	$(CELL_DIR)/dcim_cell_logic.sv \
	$(SEGMENT_DIR)/dcim_row_4bit.sv \
	$(SEGMENT_DIR)/dcim_bank_32x4.sv \
	$(ARRAY_DIR)/dcim_row_group.sv \
	$(ARRAY_TB_DIR)/tb_dcim_row_group.sv

ARRAY_128_TOP  := tb_dcim_array_128x128
ARRAY_128_MDIR := $(BUILD_ROOT)/array/dcim_array_128x128
ARRAY_128_BIN  := $(ARRAY_128_MDIR)/V$(ARRAY_128_TOP)
ARRAY_128_SRCS := \
	$(CELL_DIR)/fesram_cell_model.sv \
	$(CELL_DIR)/dcim_cell_logic.sv \
	$(SEGMENT_DIR)/dcim_row_4bit.sv \
	$(SEGMENT_DIR)/adder_tree_32x4.sv \
	$(SEGMENT_DIR)/dcim_bank_32x4.sv \
	$(ARRAY_DIR)/dcim_row_group.sv \
	$(ARRAY_DIR)/dcim_array_128x128.sv \
	$(ARRAY_TB_DIR)/tb_dcim_array_128x128.sv

MACRO_CORE_TOP  := tb_dcim_macro_core
MACRO_CORE_MDIR := $(BUILD_ROOT)/chip/dcim_macro_core
MACRO_CORE_BIN  := $(MACRO_CORE_MDIR)/V$(MACRO_CORE_TOP)
MACRO_CORE_SRCS := \
	$(CELL_DIR)/fesram_cell_model.sv \
	$(CELL_DIR)/dcim_cell_logic.sv \
	$(SEGMENT_DIR)/dcim_row_4bit.sv \
	$(SEGMENT_DIR)/adder_tree_32x4.sv \
	$(SEGMENT_DIR)/dcim_bank_32x4.sv \
	$(PERIPHERAL_DIR)/sram_write_buffer_8bit.sv \
	$(PERIPHERAL_DIR)/input_buffer_32x4.sv \
	$(PERIPHERAL_DIR)/row_decoder_7to128.sv \
	$(PERIPHERAL_DIR)/cim_group_decoder_2to4.sv \
	$(PERIPHERAL_DIR)/bank_decoder_4to16.sv \
	$(PERIPHERAL_DIR)/sram_read_serializer_8bit.sv \
	$(PERIPHERAL_DIR)/serial_output.sv \
	$(PERIPHERAL_DIR)/bitserial_accumulator.sv \
	$(ARRAY_DIR)/bank_pair_selector.sv \
	$(ARRAY_DIR)/dcim_row_group.sv \
	$(ARRAY_DIR)/dcim_array_128x128.sv \
	$(CHIP_DIR)/dcim_macro_core.sv \
	$(CHIP_TB_DIR)/tb_dcim_macro_core.sv

PIN_TOP_TOP  := tb_dcim_chip_pin_top
PIN_TOP_MDIR := $(BUILD_ROOT)/chip/dcim_chip_pin_top
PIN_TOP_BIN  := $(PIN_TOP_MDIR)/V$(PIN_TOP_TOP)
PIN_TOP_RTL_SRCS := \
	$(filter-out $(CHIP_TB_DIR)/tb_dcim_macro_core.sv,$(MACRO_CORE_SRCS)) \
	$(CHIP_DIR)/dcim_chip_pin_top.sv
PIN_TOP_SRCS := \
	$(PIN_TOP_RTL_SRCS) \
	$(CHIP_TB_DIR)/tb_dcim_chip_pin_top.sv

PIN_MASTER_TOP  := tb_dcim_pin_master
PIN_MASTER_MDIR := $(BUILD_ROOT)/fpga/dcim_pin_master
PIN_MASTER_BIN  := $(PIN_MASTER_MDIR)/V$(PIN_MASTER_TOP)
PIN_MASTER_SRCS := \
	$(PIN_TOP_RTL_SRCS) \
	$(FPGA_DIR)/dcim_pin_master.sv \
	$(FPGA_TB_DIR)/tb_dcim_pin_master.sv

CDC_BRIDGE_TOP  := tb_dcim_cdc_bridge
CDC_BRIDGE_MDIR := $(BUILD_ROOT)/fpga/dcim_cdc_bridge
CDC_BRIDGE_BIN  := $(CDC_BRIDGE_MDIR)/V$(CDC_BRIDGE_TOP)
CDC_BRIDGE_SRCS := \
	$(FPGA_DIR)/dcim_cdc_bridge.sv \
	$(FPGA_TB_DIR)/tb_dcim_cdc_bridge.sv

CDC_INTEGRATION_TOP  := tb_dcim_cdc_bridge_integration
CDC_INTEGRATION_MDIR := $(BUILD_ROOT)/fpga/dcim_cdc_bridge_integration
CDC_INTEGRATION_BIN  := $(CDC_INTEGRATION_MDIR)/V$(CDC_INTEGRATION_TOP)
CDC_INTEGRATION_SRCS := \
	$(PIN_TOP_RTL_SRCS) \
	$(FPGA_DIR)/dcim_pin_master.sv \
	$(FPGA_DIR)/dcim_cdc_bridge.sv \
	$(FPGA_TB_DIR)/tb_dcim_cdc_bridge_integration.sv

MASTER_CHIP_TOP_TOP  := tb_dcim_master_chip_top
MASTER_CHIP_TOP_MDIR := $(BUILD_ROOT)/fpga/dcim_master_chip_top
MASTER_CHIP_TOP_BIN  := $(MASTER_CHIP_TOP_MDIR)/V$(MASTER_CHIP_TOP_TOP)
MASTER_CHIP_TOP_SRCS := \
	$(PIN_TOP_RTL_SRCS) \
	$(FPGA_DIR)/dcim_pin_master.sv \
	$(FPGA_DIR)/dcim_clock_gen_125_to_50.sv \
	$(FPGA_DIR)/dcim_board_self_test.sv \
	$(FPGA_DIR)/dcim_master_chip_top.sv \
	$(FPGA_TB_DIR)/tb_dcim_master_chip_top.sv

SIM_FLAGS   := --binary --timing --assert --sv
LINT_FLAGS  := --lint-only --timing --assert --sv

.DEFAULT_GOAL := help

.PHONY: help all test test-cell test-segment test-peripheral test-array test-chip test-fpga test-fesram \
	test-dcim-cell test-row test-adder test-bank test-row-decoder \
	test-cim-group-decoder test-input-buffer test-sram-write-buffer \
	test-bitserial-accumulator test-serial-output test-sram-read-serializer \
	test-bank-decoder \
	test-bank-pair-selector test-bank-output-or-tree test-row-group test-array-128 \
	test-macro-core test-chip-pin-top test-dcim-pin-master \
	test-dcim-cdc-bridge test-dcim-cdc-integration test-dcim-master-chip-top \
	lint lint-cell \
	lint-segment lint-peripheral \
	lint-array lint-chip lint-fpga lint-synth clean

help:
	@printf '%s\n' \
	  'DCIM verification targets:' \
	  '  make test             Run every available regression test' \
	  '  make test-cell        Run all cell-level tests' \
	  '  make test-segment     Run all segment-level tests' \
	  '  make test-peripheral  Run all peripheral-level tests' \
	  '  make test-array       Run all array-level tests' \
	  '  make test-chip        Run all chip-integration tests' \
	  '  make test-fpga        Run all FPGA-side controller tests' \
	  '  make test-fesram      Run the one-FF storage-cell test' \
	  '  make test-dcim-cell   Run the storage/NOR cell test' \
	  '  make test-row         Run the exhaustive four-bit row test' \
	  '  make test-adder       Run the 32-input adder-tree test' \
	  '  make test-bank        Run the integrated 32x4 bank test' \
	  '  make test-row-decoder Run the exhaustive 7-to-128 decoder test' \
	  '  make test-cim-group-decoder Run the exhaustive 2-to-4 CIM group test' \
	  '  make test-input-buffer Run the slide-3 dual-mode Input Path test' \
	  '  make test-sram-write-buffer Run the shared 8-bit SRAM write-path test' \
	  '  make test-bitserial-accumulator Run integrated UINT8 ACC/serial test' \
	  '  make test-serial-output Run one internal 18-bit output-stage test' \
	  '  make test-sram-read-serializer Run the 8-bit SRAM read serializer test' \
	  '  make test-bank-decoder Run the exhaustive 4-to-16 bank-decoder test' \
	  '  make test-bank-pair-selector Run the SRAM/CIM bank-pair routing test' \
	  '  make test-bank-output-or-tree Run the even/odd bank-output OR-tree test' \
	  '  make test-row-group   Run the integrated 32-row x 128-column group test' \
	  '  make test-array-128   Run the complete 128-row x 128-column array test' \
	  '  make test-macro-core  Run SRAM write/read, CIM accumulation and serial output' \
	  '  make test-chip-pin-top Run the lecture-pin wrapper and shared sumo/read test' \
	  '  make test-dcim-pin-master Run write/read/A4W8/A8W8 master integration test' \
	  '  make test-dcim-cdc-bridge Run randomized 125/50 MHz CDC unit test' \
	  '  make test-dcim-cdc-integration Run bridge/master/real-chip integration test' \
	  '  make test-dcim-master-chip-top Run autonomous single-50-MHz board-top test' \
	  '  make lint             Lint simulation and synthesis sources' \
	  '  make lint-cell        Lint the two cell testbenches' \
	  '  make lint-segment     Lint the segment testbenches' \
	  '  make lint-peripheral  Lint the peripheral testbenches' \
	  '  make lint-array       Lint the implemented array testbenches' \
	  '  make lint-chip        Lint the implemented chip testbenches' \
	  '  make lint-fpga        Lint the FPGA master and chip integration testbench' \
	  '  make lint-synth       Lint all currently implemented synthesizable RTL' \
	  '  make clean            Remove only CIM_CHIP/build/sim (preserve Vivado)' \
	  '' \
	  'Optional overrides:' \
	  '  make VERILATOR=/path/to/verilator test' \
	  '  make BUILD_ROOT=/tmp/dcim-build test'

all: test

test: test-cell test-segment test-peripheral test-array test-chip test-fpga

test-cell: test-fesram test-dcim-cell
	@printf '%s\n' 'PASS: all cell-level regression tests completed'

test-segment: test-row test-adder test-bank
	@printf '%s\n' 'PASS: all segment-level regression tests completed'

test-peripheral: test-row-decoder test-cim-group-decoder test-input-buffer \
	test-sram-write-buffer \
	test-bitserial-accumulator test-serial-output test-sram-read-serializer \
	test-bank-decoder
	@printf '%s\n' 'PASS: all peripheral-level regression tests completed'

test-array: test-bank-pair-selector test-bank-output-or-tree test-row-group \
	test-array-128
	@printf '%s\n' 'PASS: all array-level regression tests completed'

test-chip: test-macro-core test-chip-pin-top
	@printf '%s\n' 'PASS: all chip-level regression tests completed'

test-fpga: test-dcim-pin-master test-dcim-cdc-bridge test-dcim-cdc-integration \
	test-dcim-master-chip-top
	@printf '%s\n' 'PASS: all FPGA-side regression tests completed'

test-fesram: $(FESRAM_BIN)
	@printf '%s\n' 'Running tb_fesram_cell_model'
	@$(FESRAM_BIN)

test-dcim-cell: $(DCIM_BIN)
	@printf '%s\n' 'Running tb_dcim_cell_logic'
	@$(DCIM_BIN)

test-row: $(ROW_BIN)
	@printf '%s\n' 'Running tb_dcim_row_4bit'
	@$(ROW_BIN)

test-adder: $(ADDER_BIN)
	@printf '%s\n' 'Running tb_adder_tree_32x4'
	@$(ADDER_BIN)

test-bank: $(BANK_BIN)
	@printf '%s\n' 'Running tb_dcim_bank_32x4'
	@$(BANK_BIN)

test-row-decoder: $(ROW_DECODER_BIN)
	@printf '%s\n' 'Running tb_row_decoder_7to128'
	@$(ROW_DECODER_BIN)

test-cim-group-decoder: $(CIM_GROUP_DECODER_BIN)
	@printf '%s\n' 'Running tb_cim_group_decoder_2to4'
	@$(CIM_GROUP_DECODER_BIN)

test-input-buffer: $(INPUT_BUFFER_BIN)
	@printf '%s\n' 'Running tb_input_buffer_32x4'
	@$(INPUT_BUFFER_BIN)

test-sram-write-buffer: $(SRAM_WRITE_BUFFER_BIN)
	@printf '%s\n' 'Running tb_sram_write_buffer_8bit'
	@$(SRAM_WRITE_BUFFER_BIN)

test-bitserial-accumulator: $(BITSERIAL_ACCUMULATOR_BIN)
	@printf '%s\n' 'Running tb_bitserial_accumulator'
	@$(BITSERIAL_ACCUMULATOR_BIN)

test-serial-output: $(SERIAL_OUTPUT_BIN)
	@printf '%s\n' 'Running tb_serial_output'
	@$(SERIAL_OUTPUT_BIN)

test-sram-read-serializer: $(SRAM_READ_SERIALIZER_BIN)
	@printf '%s\n' 'Running tb_sram_read_serializer_8bit'
	@$(SRAM_READ_SERIALIZER_BIN)

test-bank-decoder: $(BANK_DECODER_BIN)
	@printf '%s\n' 'Running tb_bank_decoder_4to16'
	@$(BANK_DECODER_BIN)

test-bank-pair-selector: $(BANK_PAIR_SELECTOR_BIN)
	@printf '%s\n' 'Running tb_bank_pair_selector'
	@$(BANK_PAIR_SELECTOR_BIN)

test-bank-output-or-tree: $(BANK_OUTPUT_OR_TREE_BIN)
	@printf '%s\n' 'Running tb_bank_output_or_tree'
	@$(BANK_OUTPUT_OR_TREE_BIN)

test-row-group: $(ROW_GROUP_BIN)
	@printf '%s\n' 'Running tb_dcim_row_group'
	@$(ROW_GROUP_BIN)

test-array-128: $(ARRAY_128_BIN)
	@printf '%s\n' 'Running tb_dcim_array_128x128'
	@$(ARRAY_128_BIN)

test-macro-core: $(MACRO_CORE_BIN)
	@printf '%s\n' 'Running tb_dcim_macro_core'
	@$(MACRO_CORE_BIN)

test-chip-pin-top: $(PIN_TOP_BIN)
	@printf '%s\n' 'Running tb_dcim_chip_pin_top'
	@$(PIN_TOP_BIN)

test-dcim-pin-master: $(PIN_MASTER_BIN)
	@printf '%s\n' 'Running tb_dcim_pin_master'
	@$(PIN_MASTER_BIN)

test-dcim-cdc-bridge: $(CDC_BRIDGE_BIN)
	@printf '%s\n' 'Running tb_dcim_cdc_bridge'
	@$(CDC_BRIDGE_BIN)

test-dcim-cdc-integration: $(CDC_INTEGRATION_BIN)
	@printf '%s\n' 'Running tb_dcim_cdc_bridge_integration'
	@$(CDC_INTEGRATION_BIN)

test-dcim-master-chip-top: $(MASTER_CHIP_TOP_BIN)
	@printf '%s\n' 'Running tb_dcim_master_chip_top'
	@$(MASTER_CHIP_TOP_BIN)

$(FESRAM_BIN): $(FESRAM_SRCS)
	@mkdir -p $(FESRAM_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(FESRAM_TOP) \
	  --Mdir $(FESRAM_MDIR) \
	  $(FESRAM_SRCS)

$(DCIM_BIN): $(DCIM_SRCS)
	@mkdir -p $(DCIM_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(DCIM_TOP) \
	  --Mdir $(DCIM_MDIR) \
	  $(DCIM_SRCS)

$(ROW_BIN): $(ROW_SRCS)
	@mkdir -p $(ROW_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(ROW_TOP) \
	  --Mdir $(ROW_MDIR) \
	  $(ROW_SRCS)

$(ADDER_BIN): $(ADDER_SRCS)
	@mkdir -p $(ADDER_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(ADDER_TOP) \
	  --Mdir $(ADDER_MDIR) \
	  $(ADDER_SRCS)

$(BANK_BIN): $(BANK_SRCS)
	@mkdir -p $(BANK_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(BANK_TOP) \
	  --Mdir $(BANK_MDIR) \
	  $(BANK_SRCS)

$(ROW_DECODER_BIN): $(ROW_DECODER_SRCS)
	@mkdir -p $(ROW_DECODER_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(ROW_DECODER_TOP) \
	  --Mdir $(ROW_DECODER_MDIR) \
	  $(ROW_DECODER_SRCS)

$(CIM_GROUP_DECODER_BIN): $(CIM_GROUP_DECODER_SRCS)
	@mkdir -p $(CIM_GROUP_DECODER_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(CIM_GROUP_DECODER_TOP) \
	  --Mdir $(CIM_GROUP_DECODER_MDIR) \
	  $(CIM_GROUP_DECODER_SRCS)

$(INPUT_BUFFER_BIN): $(INPUT_BUFFER_SRCS)
	@mkdir -p $(INPUT_BUFFER_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(INPUT_BUFFER_TOP) \
	  --Mdir $(INPUT_BUFFER_MDIR) \
	  $(INPUT_BUFFER_SRCS)

$(SRAM_WRITE_BUFFER_BIN): $(SRAM_WRITE_BUFFER_SRCS)
	@mkdir -p $(SRAM_WRITE_BUFFER_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(SRAM_WRITE_BUFFER_TOP) \
	  --Mdir $(SRAM_WRITE_BUFFER_MDIR) \
	  $(SRAM_WRITE_BUFFER_SRCS)

$(BITSERIAL_ACCUMULATOR_BIN): $(BITSERIAL_ACCUMULATOR_SRCS)
	@mkdir -p $(BITSERIAL_ACCUMULATOR_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(BITSERIAL_ACCUMULATOR_TOP) \
	  --Mdir $(BITSERIAL_ACCUMULATOR_MDIR) \
	  $(BITSERIAL_ACCUMULATOR_SRCS)

$(SERIAL_OUTPUT_BIN): $(SERIAL_OUTPUT_SRCS)
	@mkdir -p $(SERIAL_OUTPUT_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(SERIAL_OUTPUT_TOP) \
	  --Mdir $(SERIAL_OUTPUT_MDIR) \
	  $(SERIAL_OUTPUT_SRCS)

$(SRAM_READ_SERIALIZER_BIN): $(SRAM_READ_SERIALIZER_SRCS)
	@mkdir -p $(SRAM_READ_SERIALIZER_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(SRAM_READ_SERIALIZER_TOP) \
	  --Mdir $(SRAM_READ_SERIALIZER_MDIR) \
	  $(SRAM_READ_SERIALIZER_SRCS)

$(BANK_DECODER_BIN): $(BANK_DECODER_SRCS)
	@mkdir -p $(BANK_DECODER_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(BANK_DECODER_TOP) \
	  --Mdir $(BANK_DECODER_MDIR) \
	  $(BANK_DECODER_SRCS)

$(BANK_PAIR_SELECTOR_BIN): $(BANK_PAIR_SELECTOR_SRCS)
	@mkdir -p $(BANK_PAIR_SELECTOR_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(BANK_PAIR_SELECTOR_TOP) \
	  --Mdir $(BANK_PAIR_SELECTOR_MDIR) \
	  $(BANK_PAIR_SELECTOR_SRCS)

$(BANK_OUTPUT_OR_TREE_BIN): $(BANK_OUTPUT_OR_TREE_SRCS)
	@mkdir -p $(BANK_OUTPUT_OR_TREE_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(BANK_OUTPUT_OR_TREE_TOP) \
	  --Mdir $(BANK_OUTPUT_OR_TREE_MDIR) \
	  $(BANK_OUTPUT_OR_TREE_SRCS)

$(ROW_GROUP_BIN): $(ROW_GROUP_SRCS)
	@mkdir -p $(ROW_GROUP_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(ROW_GROUP_TOP) \
	  --Mdir $(ROW_GROUP_MDIR) \
	  $(ROW_GROUP_SRCS)

$(ARRAY_128_BIN): $(ARRAY_128_SRCS)
	@mkdir -p $(ARRAY_128_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(ARRAY_128_TOP) \
	  --Mdir $(ARRAY_128_MDIR) \
	  $(ARRAY_128_SRCS)

$(MACRO_CORE_BIN): $(MACRO_CORE_SRCS)
	@mkdir -p $(MACRO_CORE_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(MACRO_CORE_TOP) \
	  --Mdir $(MACRO_CORE_MDIR) \
	  $(MACRO_CORE_SRCS)

$(PIN_TOP_BIN): $(PIN_TOP_SRCS)
	@mkdir -p $(PIN_TOP_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(PIN_TOP_TOP) \
	  --Mdir $(PIN_TOP_MDIR) \
	  $(PIN_TOP_SRCS)

$(PIN_MASTER_BIN): $(PIN_MASTER_SRCS)
	@mkdir -p $(PIN_MASTER_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(PIN_MASTER_TOP) \
	  --Mdir $(PIN_MASTER_MDIR) \
	  $(PIN_MASTER_SRCS)

$(CDC_BRIDGE_BIN): $(CDC_BRIDGE_SRCS)
	@mkdir -p $(CDC_BRIDGE_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(CDC_BRIDGE_TOP) \
	  --Mdir $(CDC_BRIDGE_MDIR) \
	  $(CDC_BRIDGE_SRCS)

$(CDC_INTEGRATION_BIN): $(CDC_INTEGRATION_SRCS)
	@mkdir -p $(CDC_INTEGRATION_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(CDC_INTEGRATION_TOP) \
	  --Mdir $(CDC_INTEGRATION_MDIR) \
	  $(CDC_INTEGRATION_SRCS)

$(MASTER_CHIP_TOP_BIN): $(MASTER_CHIP_TOP_SRCS)
	@mkdir -p $(MASTER_CHIP_TOP_MDIR)
	$(VERILATOR) $(SIM_FLAGS) \
	  --top-module $(MASTER_CHIP_TOP_TOP) \
	  --Mdir $(MASTER_CHIP_TOP_MDIR) \
	  $(MASTER_CHIP_TOP_SRCS)

lint: lint-cell lint-segment lint-peripheral lint-array lint-chip lint-fpga lint-synth
	@printf '%s\n' 'PASS: all available lint checks completed'

lint-cell:
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(FESRAM_TOP) \
	  $(FESRAM_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(DCIM_TOP) \
	  $(DCIM_SRCS)

lint-segment:
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(ROW_TOP) \
	  $(ROW_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(ADDER_TOP) \
	  $(ADDER_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(BANK_TOP) \
	  $(BANK_SRCS)

lint-peripheral:
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(ROW_DECODER_TOP) \
	  $(ROW_DECODER_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(CIM_GROUP_DECODER_TOP) \
	  $(CIM_GROUP_DECODER_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(INPUT_BUFFER_TOP) \
	  $(INPUT_BUFFER_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(SRAM_WRITE_BUFFER_TOP) \
	  $(SRAM_WRITE_BUFFER_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(BITSERIAL_ACCUMULATOR_TOP) \
	  $(BITSERIAL_ACCUMULATOR_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(SERIAL_OUTPUT_TOP) \
	  $(SERIAL_OUTPUT_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(SRAM_READ_SERIALIZER_TOP) \
	  $(SRAM_READ_SERIALIZER_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(BANK_DECODER_TOP) \
	  $(BANK_DECODER_SRCS)

lint-array:
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(BANK_PAIR_SELECTOR_TOP) \
	  $(BANK_PAIR_SELECTOR_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(BANK_OUTPUT_OR_TREE_TOP) \
	  $(BANK_OUTPUT_OR_TREE_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(ROW_GROUP_TOP) \
	  $(ROW_GROUP_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(ARRAY_128_TOP) \
	  $(ARRAY_128_SRCS)

lint-chip:
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(MACRO_CORE_TOP) \
	  $(MACRO_CORE_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(PIN_TOP_TOP) \
	  $(PIN_TOP_SRCS)

lint-fpga:
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(PIN_MASTER_TOP) \
	  $(PIN_MASTER_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(CDC_BRIDGE_TOP) \
	  $(CDC_BRIDGE_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(CDC_INTEGRATION_TOP) \
	  $(CDC_INTEGRATION_SRCS)
	$(VERILATOR) $(LINT_FLAGS) \
	  --top-module $(MASTER_CHIP_TOP_TOP) \
	  $(MASTER_CHIP_TOP_SRCS)

lint-synth:
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module row_decoder_7to128 \
	  $(PERIPHERAL_DIR)/row_decoder_7to128.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module cim_group_decoder_2to4 \
	  $(PERIPHERAL_DIR)/cim_group_decoder_2to4.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module input_buffer_32x4 \
	  $(PERIPHERAL_DIR)/sram_write_buffer_8bit.sv \
	  $(PERIPHERAL_DIR)/input_buffer_32x4.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module sram_write_buffer_8bit \
	  $(PERIPHERAL_DIR)/sram_write_buffer_8bit.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module bitserial_accumulator \
	  $(PERIPHERAL_DIR)/serial_output.sv \
	  $(PERIPHERAL_DIR)/bitserial_accumulator.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module serial_output \
	  $(PERIPHERAL_DIR)/serial_output.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module sram_read_serializer_8bit \
	  $(PERIPHERAL_DIR)/sram_read_serializer_8bit.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module bank_decoder_4to16 \
	  $(PERIPHERAL_DIR)/bank_decoder_4to16.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module dcim_row_4bit \
	  $(CELL_DIR)/fesram_cell_model.sv \
	  $(CELL_DIR)/dcim_cell_logic.sv \
	  $(SEGMENT_DIR)/dcim_row_4bit.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module adder_tree_32x4 \
	  $(SEGMENT_DIR)/adder_tree_32x4.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module dcim_bank_32x4 \
	  $(CELL_DIR)/fesram_cell_model.sv \
	  $(CELL_DIR)/dcim_cell_logic.sv \
	  $(SEGMENT_DIR)/dcim_row_4bit.sv \
	  $(SEGMENT_DIR)/dcim_bank_32x4.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module bank_pair_selector \
	  $(ARRAY_DIR)/bank_pair_selector.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module bank_output_or_tree \
	  $(ARRAY_DIR)/bank_output_or_tree.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module dcim_row_group \
	  $(CELL_DIR)/fesram_cell_model.sv \
	  $(CELL_DIR)/dcim_cell_logic.sv \
	  $(SEGMENT_DIR)/dcim_row_4bit.sv \
	  $(SEGMENT_DIR)/dcim_bank_32x4.sv \
	  $(ARRAY_DIR)/dcim_row_group.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module dcim_array_128x128 \
	  $(CELL_DIR)/fesram_cell_model.sv \
	  $(CELL_DIR)/dcim_cell_logic.sv \
	  $(SEGMENT_DIR)/dcim_row_4bit.sv \
	  $(SEGMENT_DIR)/adder_tree_32x4.sv \
	  $(SEGMENT_DIR)/dcim_bank_32x4.sv \
	  $(ARRAY_DIR)/dcim_row_group.sv \
	  $(ARRAY_DIR)/dcim_array_128x128.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module dcim_macro_core \
	  $(CELL_DIR)/fesram_cell_model.sv \
	  $(CELL_DIR)/dcim_cell_logic.sv \
	  $(SEGMENT_DIR)/dcim_row_4bit.sv \
	  $(SEGMENT_DIR)/adder_tree_32x4.sv \
	  $(SEGMENT_DIR)/dcim_bank_32x4.sv \
	  $(PERIPHERAL_DIR)/sram_write_buffer_8bit.sv \
	  $(PERIPHERAL_DIR)/input_buffer_32x4.sv \
	  $(PERIPHERAL_DIR)/row_decoder_7to128.sv \
	  $(PERIPHERAL_DIR)/cim_group_decoder_2to4.sv \
	  $(PERIPHERAL_DIR)/bank_decoder_4to16.sv \
	  $(PERIPHERAL_DIR)/sram_read_serializer_8bit.sv \
	  $(PERIPHERAL_DIR)/serial_output.sv \
	  $(PERIPHERAL_DIR)/bitserial_accumulator.sv \
	  $(ARRAY_DIR)/bank_pair_selector.sv \
	  $(ARRAY_DIR)/dcim_row_group.sv \
	  $(ARRAY_DIR)/dcim_array_128x128.sv \
	  $(CHIP_DIR)/dcim_macro_core.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module dcim_chip_pin_top \
	  $(PIN_TOP_RTL_SRCS)
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module dcim_pin_master \
	  $(FPGA_DIR)/dcim_pin_master.sv
	$(VERILATOR) --lint-only --sv -DSYNTHESIS \
	  --top-module dcim_cdc_bridge \
	  $(FPGA_DIR)/dcim_cdc_bridge.sv

clean:
	@test -n "$(BUILD_ROOT)" && test "$(BUILD_ROOT)" != "/"
	@test "$(abspath $(BUILD_ROOT))" != "$(CIM_ROOT)/build" || { echo 'Refusing to delete shared build directory containing Vivado projects'; exit 1; }
	rm -rf -- "$(BUILD_ROOT)"
	@printf 'Removed %s\n' "$(BUILD_ROOT)"
