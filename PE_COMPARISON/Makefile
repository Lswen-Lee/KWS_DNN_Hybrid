VERILATOR ?= verilator
.DEFAULT_GOAL := test
HYBRID := ../HYBRID_SYSTEM
BOARD_RTL = $(wildcard rtl/board/*.sv) $(HYBRID)/rtl/integration/pe_pot_engine.sv $(addprefix $(HYBRID)/rtl/datapath/,requantizer_int32_to_uint8_pot.sv requantizer_int32_to_uint8_pot_comb.sv kws_pot_shift_rom.sv pot_result_stream.sv)
.PHONY: test-board lint-board
test-board:
	@mkdir -p build/board_sim
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME --top-module tb_pe_board -Mdir build/board_sim $(MEMORY_RTL) $(BOARD_RTL) sim_verilator/pe_board_clock_primitives.sv tb/tb_pe_board.sv
	build/board_sim/Vtb_pe_board
lint-board:
	@for top in pe9_board_top pe8_compact_board_top pe8_pipeline_board_top pe9_pot_board_top pe8_compact_pot_board_top pe8_pipeline_pot_board_top pe8_compact_pot_comb_board_top pe8_pipeline_pot_comb_board_top; do \
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME --top-module $$top $(MEMORY_RTL) $(BOARD_RTL) sim_verilator/pe_board_clock_primitives.sv || exit $$?; done
MEMORY_RTL = $(RTL9) $(RTL8) $(addprefix $(HYBRID)/rtl/datapath/,pe_weight_buffer_12.sv pe_layer_weight_loader.sv pe_weight_sum_builder.sv pe_channel_sum_memory.sv pe_weight_read_align.sv pe8_result_correction.sv) $(addprefix $(HYBRID)/rtl/control/,pe_group_controller.sv pe_result_controller.sv pe8_result_controller_pipeline.sv) $(HYBRID)/rtl/integration/pe_memory_engine.sv $(wildcard rtl/memory_backed/*.sv)
.PHONY: test-memory-comparison lint-memory-comparison test-memory-comparison-iverilog
test-memory-comparison:
	@mkdir -p build/memory_comparison_sim
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME --top-module tb_pe_memory_comparison -Mdir build/memory_comparison_sim $(MEMORY_RTL) tb/tb_pe_memory_comparison.sv
	build/memory_comparison_sim/Vtb_pe_memory_comparison
lint-memory-comparison:
	$(VERILATOR) --lint-only --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME --top-module tb_pe_memory_comparison $(MEMORY_RTL) tb/tb_pe_memory_comparison.sv
test-memory-comparison-iverilog:
	@mkdir -p build/memory_comparison_sim
	$(IVERILOG) $(IVL_FLAGS) -g2012 -s tb_pe_memory_comparison -o build/memory_comparison_sim/comparison.vvp $(MEMORY_RTL) tb/tb_pe_memory_comparison.sv
	$(VVP) build/memory_comparison_sim/comparison.vvp
IVERILOG ?= iverilog
IVL_FLAGS ?=
VVP ?= vvp
DSP_SIM := sim_verilator/DSP48E1.v
PE9 := ../PE_CHIP
PE8 := ../PE_CHIP_8x8
RTL9 := $(PE9)/rtl/pe_pkg.sv $(wildcard $(PE9)/rtl/arithmetic/*.sv) $(PE9)/rtl/array/pe_array_12.sv
RTL8 := $(PE8)/rtl/pe8_pkg.sv $(wildcard $(PE8)/rtl/arithmetic/*.sv) $(PE8)/rtl/array/pe8_array_12.sv
TB := tb/tb_pe_array_comparison.sv
EQUIV_RTL := $(wildcard rtl/equivalent/*.sv) ../HYBRID_SYSTEM/rtl/datapath/pe8_result_correction.sv
SUM_INTEGRATION := ../HYBRID_SYSTEM/rtl/datapath/pe_weight_sum_builder.sv tb/tb_pe8_weight_sum_integration.sv
.PHONY: test-weight-sum-integration lint-weight-sum-integration
test-weight-sum-integration:
	@mkdir -p build/weight_sum_integration
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL --top-module tb_pe8_weight_sum_integration -Mdir build/weight_sum_integration $(RTL8) $(EQUIV_RTL) $(SUM_INTEGRATION)
	build/weight_sum_integration/Vtb_pe8_weight_sum_integration
lint-weight-sum-integration:
	$(VERILATOR) --lint-only --timing -Wall -Wno-BLKSEQ -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL --top-module tb_pe8_weight_sum_integration $(RTL8) $(EQUIV_RTL) $(SUM_INTEGRATION)
.PHONY: test-equivalent lint-equivalent
test-equivalent:
	@mkdir -p build/equivalent_sim
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY --top-module tb_pe_equivalence -Mdir build/equivalent_sim $(RTL9) $(RTL8) $(EQUIV_RTL) tb/tb_pe_equivalence.sv
	build/equivalent_sim/Vtb_pe_equivalence
lint-equivalent:
	$(VERILATOR) --lint-only --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY --top-module tb_pe_equivalence $(RTL9) $(RTL8) $(EQUIV_RTL) tb/tb_pe_equivalence.sv
.PHONY: test lint check-tools summary
test:
	@mkdir -p build/sim
	$(VERILATOR) -v $(DSP_SIM) --binary --timing -Wall -Wno-BLKSEQ --top-module tb_pe_array_comparison -Mdir build/sim $(RTL9) $(RTL8) $(TB)
	build/sim/Vtb_pe_array_comparison
lint:
	$(VERILATOR) -v $(DSP_SIM) --lint-only --timing -Wall -Wno-BLKSEQ --top-module tb_pe_array_comparison $(RTL9) $(RTL8) $(TB)
check-tools:
	python3 -m unittest discover -s scripts -p 'test_*.py'
summary:
	python3 scripts/summarize_reports.py $(PE9_REPORT) $(PE8_REPORT)

# Official vendor model, not the restricted Verilator model. Simulation only.
.PHONY: test-unisim
test-unisim:
	@mkdir -p build/unisim
	@set -e; for tb in $(PE9)/tb/arithmetic/tb_pe_mac_lane.sv $(PE8)/tb/arithmetic/tb_pe8_mac_lane.sv $(PE9)/tb/array/tb_pe_array_12.sv $(PE8)/tb/array/tb_pe8_array_12.sv $(TB); do \
		top=$$(basename $$tb .sv); \
		$(IVERILOG) $(IVL_FLAGS) -g2012 -s $$top -s glbl -o build/unisim/$$top.vvp $(RTL9) $(RTL8) sim_vendor/DSP48E1.v sim_vendor/glbl.v $$tb; \
		$(VVP) build/unisim/$$top.vvp; \
	done
