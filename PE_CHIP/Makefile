VERILATOR ?= verilator
BUILD_DIR := build
ARRAY_RTL := rtl/pe_pkg.sv rtl/arithmetic/pe_multiplier_s9xs8.sv rtl/arithmetic/pe_accumulator_s32.sv rtl/arithmetic/pe_mac_lane.sv rtl/array/pe_array_12.sv

.PHONY: test-array

.PHONY: help structure test test-activation-center test-multiplier test-accumulator test-mac-lane lint clean

help:
	@echo "PE_CHIP verification targets"
	@echo "  make test                    - run all implemented PE tests"
	@echo "  make test-activation-center  - test UINT8 minus zero-point 127"
	@echo "  make test-multiplier         - test signed 9-bit by signed 8-bit multiplier"
	@echo "  make test-accumulator        - test signed INT32 accumulation and control"
	@echo "  make test-mac-lane           - test one complete signed multiply-accumulate lane"
	@echo "  make test-array              - test 12 lanes, masks, packing and K=9/32/144"
	@echo "  make lint                    - lint implemented PE RTL"
	@echo "  make structure               - list source/test structure"
	@echo "  make clean                   - remove generated simulation files"

structure:
	@find rtl tb constraints filelists docs -maxdepth 3 -print | sort

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

test-activation-center: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_activation_center_127 \
		-Mdir $(BUILD_DIR)/activation_center \
		rtl/arithmetic/activation_center_127.sv \
		tb/arithmetic/tb_activation_center_127.sv
	@$(BUILD_DIR)/activation_center/Vtb_activation_center_127

test-multiplier: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_pe_multiplier_s9xs8 \
		-Mdir $(BUILD_DIR)/multiplier \
		rtl/arithmetic/pe_multiplier_s9xs8.sv \
		tb/arithmetic/tb_pe_multiplier_s9xs8.sv
	@$(BUILD_DIR)/multiplier/Vtb_pe_multiplier_s9xs8

test-accumulator: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_pe_accumulator_s32 \
		-Mdir $(BUILD_DIR)/accumulator \
		rtl/arithmetic/pe_accumulator_s32.sv \
		tb/arithmetic/tb_pe_accumulator_s32.sv
	@$(BUILD_DIR)/accumulator/Vtb_pe_accumulator_s32

test-mac-lane: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_pe_mac_lane \
		-Mdir $(BUILD_DIR)/mac_lane \
		rtl/arithmetic/pe_multiplier_s9xs8.sv \
		rtl/arithmetic/pe_accumulator_s32.sv \
		rtl/arithmetic/pe_mac_lane.sv \
		tb/arithmetic/tb_pe_mac_lane.sv
	@$(BUILD_DIR)/mac_lane/Vtb_pe_mac_lane

test-array: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ \
		--top-module tb_pe_array_12 -Mdir $(BUILD_DIR)/array \
		$(ARRAY_RTL) tb/array/tb_pe_array_12.sv
	@$(BUILD_DIR)/array/Vtb_pe_array_12

test: test-activation-center test-multiplier test-accumulator test-mac-lane test-array

lint:
	$(VERILATOR) --lint-only --timing -Wall --top-module pe_array_12 $(ARRAY_RTL)
	$(VERILATOR) --lint-only --timing -Wall -Wno-fatal \
		--top-module activation_center_127 \
		rtl/arithmetic/activation_center_127.sv
	$(VERILATOR) --lint-only --timing -Wall -Wno-fatal \
		--top-module pe_multiplier_s9xs8 \
		rtl/arithmetic/pe_multiplier_s9xs8.sv
	$(VERILATOR) --lint-only --timing -Wall -Wno-fatal \
		--top-module pe_accumulator_s32 \
		rtl/arithmetic/pe_accumulator_s32.sv
	$(VERILATOR) --lint-only --timing -Wall -Wno-fatal \
		--top-module pe_mac_lane \
		rtl/arithmetic/pe_multiplier_s9xs8.sv \
		rtl/arithmetic/pe_accumulator_s32.sv \
		rtl/arithmetic/pe_mac_lane.sv

clean:
	rm -rf $(BUILD_DIR)
