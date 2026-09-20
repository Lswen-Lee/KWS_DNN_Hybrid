VERILATOR ?= verilator
RTL := $(sort $(wildcard rtl/arithmetic/*.sv))
ARRAY_RTL := rtl/pe8_pkg.sv $(RTL) rtl/array/pe8_array_12.sv
CORE_RTL := $(ARRAY_RTL) rtl/control/pe8_core_controller.sv rtl/core/pe8_core_12.sv
STANDALONE_RTL := $(CORE_RTL) rtl/core/pe8_standalone_top.sv
.PHONY: test-array
TESTS := activation_u8_to_s8 pe8_multiplier_s8xs8 pe8_accumulator_s32 pe8_mac_lane
FLAGS := --binary --timing -Wall -Wno-BLKSEQ
.PHONY: help test lint test-activation test-multiplier test-accumulator test-mac-lane $(addprefix run-,$(TESTS))
help:
	@echo "make test | lint | test-activation | test-multiplier | test-accumulator | test-mac-lane | test-array | test-controller | test-core | test-standalone"
test: $(addprefix run-,$(TESTS)) test-array test-controller test-core test-standalone
.PHONY: test-standalone
test-standalone:
	$(VERILATOR) $(FLAGS) --top-module tb_pe8_standalone_top -Mdir build/standalone $(STANDALONE_RTL) tb/core/tb_pe8_standalone_top.sv
	@build/standalone/Vtb_pe8_standalone_top
.PHONY: test-controller test-core
test-controller:
	$(VERILATOR) $(FLAGS) --top-module tb_pe8_core_controller -Mdir build/controller rtl/control/pe8_core_controller.sv tb/control/tb_pe8_core_controller.sv
	@build/controller/Vtb_pe8_core_controller
test-core:
	$(VERILATOR) $(FLAGS) --top-module tb_pe8_core_12 -Mdir build/core $(CORE_RTL) tb/core/tb_pe8_core_12.sv
	@build/core/Vtb_pe8_core_12
test-array:
	@mkdir -p build/array
	$(VERILATOR) $(FLAGS) --top-module tb_pe8_array_12 -Mdir build/array $(ARRAY_RTL) tb/array/tb_pe8_array_12.sv
	@build/array/Vtb_pe8_array_12
$(addprefix run-,$(TESTS)): run-%:
	@mkdir -p build/$*
	$(VERILATOR) $(FLAGS) --top-module tb_$* -Mdir build/$* $(RTL) tb/arithmetic/tb_$*.sv
	@build/$*/Vtb_$*
test-activation: run-activation_u8_to_s8
test-multiplier: run-pe8_multiplier_s8xs8
test-accumulator: run-pe8_accumulator_s32
test-mac-lane: run-pe8_mac_lane
lint:
	$(VERILATOR) --lint-only -Wall --top-module pe8_standalone_top $(STANDALONE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module pe8_core_12 $(CORE_RTL)
	$(VERILATOR) --lint-only -Wall --top-module pe8_array_12 $(ARRAY_RTL)
	@set -e; for top in $(TESTS); do \
		$(VERILATOR) --lint-only -Wall --top-module $$top $(RTL); \
	done
