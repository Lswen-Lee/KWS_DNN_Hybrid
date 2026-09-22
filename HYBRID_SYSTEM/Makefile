VERILATOR ?= verilator
.DEFAULT_GOAL := help
IVERILOG ?= iverilog
VVP ?= vvp
IVL_FLAGS ?=
BUILD_DIR := build
RTL_DATAPATH := rtl/datapath
TB_DATAPATH := tb/datapath

POT_RTL := $(RTL_DATAPATH)/requantizer_int32_to_uint8_pot.sv $(RTL_DATAPATH)/requantizer_int32_to_uint8_pot_comb.sv
POT_TB := $(TB_DATAPATH)/tb_requantizer_int32_to_uint8_pot.sv
.PHONY: lint-requantizer-pot build-requantizer-pot test-requantizer-pot test-requantizer-pot-exports
test: test-requantizer-pot
lint: lint-requantizer-pot
lint-requantizer-pot:
	$(VERILATOR) --lint-only -Wall --top-module requantizer_int32_to_uint8_pot $(POT_RTL)
	$(VERILATOR) --lint-only -Wall --top-module requantizer_int32_to_uint8_pot_comb $(POT_RTL)
build-requantizer-pot: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ --top-module tb_requantizer_int32_to_uint8_pot -Mdir $(BUILD_DIR)/requantizer_pot $(POT_RTL) $(POT_TB)
test-requantizer-pot: build-requantizer-pot
	$(BUILD_DIR)/requantizer_pot/Vtb_requantizer_int32_to_uint8_pot
test-requantizer-pot-exports: build-requantizer-pot
	python3 scripts/export_pot_requant_vectors.py
	python3 scripts/check_pot_shift_rom.py
	$(BUILD_DIR)/requantizer_pot/Vtb_requantizer_int32_to_uint8_pot +VECTORS=$(BUILD_DIR)/requantizer_pot/software_vectors.txt

PIPE_RESULT_RTL := rtl/control/pe8_result_controller_pipeline.sv $(RTL_DATAPATH)/pe8_result_correction.sv
.PHONY: test-result-pipeline lint-result-pipeline test-result-pipeline-iverilog
test: test-result-pipeline
lint: lint-result-pipeline
test-result-pipeline: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ --top-module tb_pe8_result_controller_pipeline -Mdir $(BUILD_DIR)/result_pipeline $(PIPE_RESULT_RTL) $(RTL_DATAPATH)/pe_channel_sum_memory.sv tb/control/tb_pe8_result_controller_pipeline.sv
	$(BUILD_DIR)/result_pipeline/Vtb_pe8_result_controller_pipeline
lint-result-pipeline:
	$(VERILATOR) --lint-only -Wall --top-module pe8_result_controller_pipeline $(PIPE_RESULT_RTL)
test-result-pipeline-iverilog: | $(BUILD_DIR)
	$(IVERILOG) $(IVL_FLAGS) -g2012 -s tb_pe8_result_controller_pipeline -o $(BUILD_DIR)/result_pipeline.vvp $(PIPE_RESULT_RTL) $(RTL_DATAPATH)/pe_channel_sum_memory.sv tb/control/tb_pe8_result_controller_pipeline.sv
	$(VVP) $(BUILD_DIR)/result_pipeline.vvp

ENGINE_RTL = $(GROUP_RTL) rtl/control/pe_result_controller.sv rtl/control/pe8_result_controller_pipeline.sv rtl/integration/pe_memory_engine.sv
POT_STREAM_RTL = $(POT_RTL) rtl/datapath/kws_pot_shift_rom.sv rtl/datapath/pe_pot_result_stream.sv
POT_ENGINE_RTL = $(ENGINE_RTL) $(POT_STREAM_RTL) rtl/integration/pe_pot_engine.sv
.PHONY: test-pot-engine
test: test-memory-engine-zp128 test-pot-engine test-pot-stream test-postprocess-pot test-dcim-offset check-engine-elaboration-zp128
.PHONY: test-pot-stream test-postprocess-pot test-dcim-offset
test-pot-stream: | $(BUILD_DIR)
	@for post in 0 1; do \
		$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ "-GPOSTPROCESS_PIPELINED=1'b$$post" --top-module tb_pe_pot_result_stream -Mdir $(BUILD_DIR)/pot_stream_$$post $(POT_STREAM_RTL) tb/datapath/tb_pe_pot_result_stream.sv && \
		$(BUILD_DIR)/pot_stream_$$post/Vtb_pe_pot_result_stream || exit $$?; \
	done
test-postprocess-pot: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ --top-module tb_kws_postprocess_pot -Mdir $(BUILD_DIR)/postprocess_pot $(POT_RTL) $(addprefix rtl/datapath/,relu_uint8_zp127.sv maxpool2x2_uint8.sv kws_postprocess_pot.sv) tb/datapath/tb_kws_postprocess_pot.sv
	$(BUILD_DIR)/postprocess_pot/Vtb_kws_postprocess_pot
test-dcim-offset: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ --top-module tb_dcim_u8_offset_correction -Mdir $(BUILD_DIR)/dcim_offset rtl/dcim_adapter/dcim_u8_offset_correction.sv tb/datapath/tb_dcim_u8_offset_correction.sv
	$(BUILD_DIR)/dcim_offset/Vtb_dcim_u8_offset_correction
test-pot-engine: | $(BUILD_DIR)
	@for post in 0 1; do for cfg in 0_0 1_0 1_1; do mode=$${cfg%_*}; pipe=$${cfg#*_}; \
		$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b$$mode" "-GRESULT_PIPELINED=1'b$$pipe" "-GPOSTPROCESS_PIPELINED=1'b$$post" --top-module tb_pe_pot_engine -Mdir $(BUILD_DIR)/pot_engine_$${cfg}_post$$post $(POT_ENGINE_RTL) tb/integration/tb_pe_pot_engine.sv && \
		$(BUILD_DIR)/pot_engine_$${cfg}_post$$post/Vtb_pe_pot_engine || exit $$?; \
	done; \
	done
.PHONY: test-memory-engine-zp128
.PHONY: check-engine-elaboration-zp128
check-engine-elaboration-zp128: | $(BUILD_DIR)
	@for cfg in 0_0 1_0 1_1; do mode=$${cfg%_*}; pipe=$${cfg#*_}; \
		$(VERILATOR) --xml-only -Wall -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b$$mode" "-GRESULT_PIPELINED=1'b$$pipe" -GINPUT_ZERO_POINT=128 --top-module pe_memory_engine --xml-output $(BUILD_DIR)/zp128_$$cfg.xml $(ENGINE_RTL) || exit $$?; \
	done
	python3 scripts/verify_engine_elaboration.py $(BUILD_DIR)/zp128_1_0.xml $(BUILD_DIR)/zp128_0_0.xml $(BUILD_DIR)/zp128_1_1.xml 128
test-memory-engine-zp128: | $(BUILD_DIR)
	@for cfg in 0_0 1_0 1_1; do mode=$${cfg%_*}; pipe=$${cfg#*_}; \
		$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b$$mode" "-GRESULT_PIPELINED=1'b$$pipe" -GINPUT_ZERO_POINT=128 --top-module tb_pe_memory_engine -Mdir $(BUILD_DIR)/zp128_$$cfg $(ENGINE_RTL) tb/integration/tb_pe_memory_engine.sv && \
		$(BUILD_DIR)/zp128_$$cfg/Vtb_pe_memory_engine || exit $$?; \
	done
.PHONY: test-invalid-engine
test: test-invalid-engine
test-invalid-engine: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-USERFATAL "-GPE8_MODE=1'b0" "-GRESULT_PIPELINED=1'b1" --top-module tb_pe_memory_engine -Mdir $(BUILD_DIR)/invalid_engine $(ENGINE_RTL) tb/integration/tb_pe_memory_engine.sv
	@ulimit -c 0; python3 scripts/check_invalid_engine.py $(BUILD_DIR)/invalid_engine/Vtb_pe_memory_engine
.PHONY: check-engine-elaboration
test: check-engine-elaboration
check-engine-elaboration: | $(BUILD_DIR)
	@for cfg in 0_0 1_0 1_1; do mode=$${cfg%_*}; pipe=$${cfg#*_}; \
		$(VERILATOR) --xml-only -Wall -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b$$mode" "-GRESULT_PIPELINED=1'b$$pipe" --top-module pe_memory_engine --xml-output $(BUILD_DIR)/engine_$$cfg.xml $(ENGINE_RTL) || exit $$?; \
	done
	python3 scripts/verify_engine_elaboration.py $(BUILD_DIR)/engine_1_0.xml $(BUILD_DIR)/engine_0_0.xml $(BUILD_DIR)/engine_1_1.xml
.PHONY: test-memory-engine lint-memory-engine test-memory-engine-iverilog
test: test-memory-engine
lint: lint-memory-engine
test-memory-engine: | $(BUILD_DIR)
	@for cfg in 0_0 1_0 1_1; do mode=$${cfg%_*}; pipe=$${cfg#*_}; \
		$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b$$mode" "-GRESULT_PIPELINED=1'b$$pipe" --top-module tb_pe_memory_engine -Mdir $(BUILD_DIR)/memory_engine_$$cfg $(ENGINE_RTL) tb/integration/tb_pe_memory_engine.sv && \
		$(BUILD_DIR)/memory_engine_$$cfg/Vtb_pe_memory_engine || exit $$?; \
	done
lint-memory-engine:
	@for cfg in 0_0 1_0 1_1; do mode=$${cfg%_*}; pipe=$${cfg#*_}; \
		$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b$$mode" "-GRESULT_PIPELINED=1'b$$pipe" --top-module pe_memory_engine $(ENGINE_RTL) || exit $$?; \
	done
test-memory-engine-iverilog: | $(BUILD_DIR)
	@for cfg in 0_0 1_0 1_1; do mode=$${cfg%_*}; pipe=$${cfg#*_}; \
		$(IVERILOG) $(IVL_FLAGS) -g2012 -s tb_pe_memory_engine -Ptb_pe_memory_engine.PE8_MODE=$$mode -Ptb_pe_memory_engine.RESULT_PIPELINED=$$pipe -o $(BUILD_DIR)/memory_engine_$$cfg.vvp $(ENGINE_RTL) tb/integration/tb_pe_memory_engine.sv && \
		$(VVP) $(BUILD_DIR)/memory_engine_$$cfg.vvp || exit $$?; \
	done

RESULT_RTL := rtl/control/pe_result_controller.sv $(RTL_DATAPATH)/pe8_result_correction.sv
.PHONY: check-result-elaboration
test: check-result-elaboration
check-result-elaboration: | $(BUILD_DIR)
	$(VERILATOR) --xml-only -Wall --top-module pe_result_controller "-GPE8_MODE=1'b1" --xml-output $(BUILD_DIR)/result_pe8.xml $(RESULT_RTL)
	$(VERILATOR) --xml-only -Wall -Wno-UNUSEDSIGNAL --top-module pe_result_controller "-GPE8_MODE=1'b0" --xml-output $(BUILD_DIR)/result_pe9.xml $(RESULT_RTL)
	python3 scripts/verify_result_elaboration.py $(BUILD_DIR)/result_pe8.xml $(BUILD_DIR)/result_pe9.xml
.PHONY: test-result-controller test-group-result-controller lint-result-controller test-result-controller-iverilog
test: test-result-controller test-group-result-controller
lint: lint-result-controller
test-result-controller: | $(BUILD_DIR)
	@for mode in 1 0; do \
		$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b$$mode" --top-module tb_pe_result_controller -Mdir $(BUILD_DIR)/result_controller_$$mode $(RESULT_RTL) $(RTL_DATAPATH)/pe_channel_sum_memory.sv tb/control/tb_pe_result_controller.sv && \
		$(BUILD_DIR)/result_controller_$$mode/Vtb_pe_result_controller || exit $$?; \
	done
test-group-result-controller: | $(BUILD_DIR)
	@for mode in 1 0; do \
		$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b$$mode" --top-module tb_pe_group_result_controller -Mdir $(BUILD_DIR)/group_result_$$mode $(GROUP_RTL) rtl/control/pe_result_controller.sv tb/control/tb_pe_group_result_controller.sv && \
		$(BUILD_DIR)/group_result_$$mode/Vtb_pe_group_result_controller || exit $$?; \
	done
lint-result-controller:
	$(VERILATOR) --lint-only -Wall --top-module pe_result_controller $(RESULT_RTL)
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL "-GPE8_MODE=1'b0" --top-module pe_result_controller $(RESULT_RTL)
test-result-controller-iverilog: | $(BUILD_DIR)
	@for mode in 1 0; do \
		$(IVERILOG) $(IVL_FLAGS) -g2012 -s tb_pe_result_controller -Ptb_pe_result_controller.PE8_MODE=$$mode -o $(BUILD_DIR)/result_cross_$$mode.vvp $(RESULT_RTL) $(RTL_DATAPATH)/pe_channel_sum_memory.sv tb/control/tb_pe_result_controller.sv && \
		$(VVP) $(BUILD_DIR)/result_cross_$$mode.vvp && \
		$(IVERILOG) $(IVL_FLAGS) -g2012 -s tb_pe_group_result_controller -Ptb_pe_group_result_controller.PE8_MODE=$$mode -o $(BUILD_DIR)/group_result_cross_$$mode.vvp $(GROUP_RTL) rtl/control/pe_result_controller.sv tb/control/tb_pe_group_result_controller.sv && \
		$(VVP) $(BUILD_DIR)/group_result_cross_$$mode.vvp || exit $$?; \
	done

GROUP_RTL := ../PE_CHIP_8x8/rtl/pe8_pkg.sv ../PE_CHIP/rtl/pe_pkg.sv \
	../PE_CHIP_8x8/rtl/arithmetic/activation_u8_to_s8.sv \
	../PE_CHIP/rtl/arithmetic/activation_center_127.sv \
	../PE_CHIP_8x8/rtl/arithmetic/pe8_mac_lane.sv ../PE_CHIP/rtl/arithmetic/pe_mac_lane.sv \
	../PE_CHIP_8x8/rtl/array/pe8_array_12.sv ../PE_CHIP/rtl/array/pe_array_12.sv \
	rtl/control/pe_group_controller.sv $(RTL_DATAPATH)/pe_weight_read_align.sv \
	$(RTL_DATAPATH)/pe_weight_buffer_12.sv $(RTL_DATAPATH)/pe_layer_weight_loader.sv \
	$(RTL_DATAPATH)/pe_weight_sum_builder.sv $(RTL_DATAPATH)/pe_channel_sum_memory.sv \
	$(RTL_DATAPATH)/pe8_result_correction.sv
.PHONY: test-group-controller test-group-controller-iverilog lint-group-controller
test: test-group-controller
lint: lint-group-controller
test-group-controller: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ --top-module tb_pe_group_controller -Mdir $(BUILD_DIR)/group_controller $(GROUP_RTL) tb/control/tb_pe_group_controller.sv
	$(BUILD_DIR)/group_controller/Vtb_pe_group_controller
test-group-controller-iverilog: | $(BUILD_DIR)
	$(IVERILOG) $(IVL_FLAGS) -g2012 -s tb_pe_group_controller -o $(BUILD_DIR)/group_controller_cross.vvp $(GROUP_RTL) tb/control/tb_pe_group_controller.sv
	$(VVP) $(BUILD_DIR)/group_controller_cross.vvp
lint-group-controller:
	$(VERILATOR) --lint-only -Wall --top-module pe_group_controller rtl/control/pe_group_controller.sv

.PHONY: test-weight-read-align lint-weight-read-align
test: test-weight-read-align
lint: lint-weight-read-align
test-weight-read-align: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ --top-module tb_pe_weight_read_align -Mdir $(BUILD_DIR)/weight_read_align $(RTL_DATAPATH)/pe_weight_read_align.sv $(RTL_DATAPATH)/pe_weight_buffer_12.sv $(TB_DATAPATH)/tb_pe_weight_read_align.sv
	$(BUILD_DIR)/weight_read_align/Vtb_pe_weight_read_align
lint-weight-read-align:
	$(VERILATOR) --lint-only -Wall --top-module pe_weight_read_align $(RTL_DATAPATH)/pe_weight_read_align.sv

LOADER_RTL := $(RTL_DATAPATH)/pe_layer_weight_loader.sv $(RTL_DATAPATH)/pe_weight_sum_builder.sv $(RTL_DATAPATH)/pe_weight_buffer_12.sv $(RTL_DATAPATH)/pe_channel_sum_memory.sv
.PHONY: test-channel-sum-memory test-layer-sum-integration lint-channel-sum-memory
test: test-channel-sum-memory test-layer-sum-integration
lint: lint-channel-sum-memory
test-channel-sum-memory: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ --top-module tb_pe_channel_sum_memory -Mdir $(BUILD_DIR)/channel_sum_memory $(RTL_DATAPATH)/pe_channel_sum_memory.sv $(TB_DATAPATH)/tb_pe_channel_sum_memory.sv
	$(BUILD_DIR)/channel_sum_memory/Vtb_pe_channel_sum_memory
test-layer-sum-integration: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ "-GSTORE_SUM=1'b1" --top-module tb_pe_layer_weight_loader -Mdir $(BUILD_DIR)/layer_sum_integration $(LOADER_RTL) $(TB_DATAPATH)/tb_pe_layer_weight_loader.sv
	$(BUILD_DIR)/layer_sum_integration/Vtb_pe_layer_weight_loader
lint-channel-sum-memory:
	$(VERILATOR) --lint-only -Wall --top-module pe_channel_sum_memory $(RTL_DATAPATH)/pe_channel_sum_memory.sv
.PHONY: test-layer-weight-loader lint-layer-weight-loader
test: test-layer-weight-loader
lint: lint-layer-weight-loader
test-layer-weight-loader: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ --top-module tb_pe_layer_weight_loader -Mdir $(BUILD_DIR)/layer_loader $(LOADER_RTL) $(TB_DATAPATH)/tb_pe_layer_weight_loader.sv
	$(BUILD_DIR)/layer_loader/Vtb_pe_layer_weight_loader
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -GSUM_ENABLE=0 --top-module tb_pe_layer_weight_loader -Mdir $(BUILD_DIR)/layer_loader_pe9 $(LOADER_RTL) $(TB_DATAPATH)/tb_pe_layer_weight_loader.sv
	$(BUILD_DIR)/layer_loader_pe9/Vtb_pe_layer_weight_loader
lint-layer-weight-loader:
	$(VERILATOR) --lint-only -Wall --top-module pe_layer_weight_loader $(LOADER_RTL)

.PHONY: help structure test test-requantizer test-relu test-maxpool test-argmax \
	test-postprocess test-python-golden lint clean

help:
	@echo "  make test-memory-engine-zp128 / check-engine-elaboration-zp128 - three raw zp128 configurations"
	@echo "  make test-pot-engine / test-pot-stream - end-to-end PE/PoT and elastic result path"
	@echo "  make test-postprocess-pot / test-dcim-offset - frame postprocessing and standalone DCIM correction"
	@echo "  make test-requantizer-pot-exports - software bytes and model shift ROM consistency"
	@echo "HYBRID_SYSTEM verification targets"
	@echo "  make test-result-pipeline / lint-result-pipeline / test-result-pipeline-iverilog - standalone PE8 result pipeline"
	@echo "  make test-memory-engine / lint-memory-engine - PE9, PE8 compact, PE8 pipeline engine"
	@echo "  make test-invalid-engine - reject unsupported PE9 plus RESULT_PIPELINED"
	@echo "  make check-engine-elaboration / test-memory-engine-iverilog - hierarchy and cross-simulator checks"
	@echo "  make test-result-controller / test-group-result-controller / lint-result-controller - PE8 and PE9 result RTL"
	@echo "  make test-group-controller / lint-group-controller - actual RAM, align, PE8/PE9 and correction"
	@echo "  make test-weight-read-align / lint-weight-read-align - align activation with synchronous weights"
	@echo "  make test-channel-sum-memory / test-layer-sum-integration / lint-channel-sum-memory"
	@echo "  make test-layer-weight-loader / lint-layer-weight-loader - full-layer RAM mapping, PE8/PE9"
	@echo "  make test-weight-buffer / lint-weight-buffer - 12-bank synchronous RAM"
	@echo "  make test-weight-sum-builder / lint-weight-sum-builder - channel weight sum"
	@echo "  make test-pe8-result-correction - PE8 raw + weight sum, no bias"
	@echo "  make lint-pe8-result-correction - strict standalone RTL lint"
	@echo "  make test              - run PE backend, engine, and post-process regression"
	@echo "  make test-requantizer  - INT32 to UINT8 Q31 requantization"
	@echo "  make test-relu         - UINT8 zero-point-127 ReLU"
	@echo "  make test-maxpool      - streaming 2x2 max-pool"
	@echo "  make test-argmax       - sequential eight-class argmax"
	@echo "  make test-postprocess  - integrated requant/ReLU/pool path"
	@echo "  make test-python-golden - exhaustively compare the exported sample"
	@echo "  make lint              - lint PE backend, engine, and post-process RTL"
	@echo "  make structure         - list project files"
	@echo "  make clean             - remove generated simulation files"

structure:
	@find rtl tb constraints ip filelists scripts docs -maxdepth 3 -print | sort

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

test-requantizer: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_requantizer_int32_to_uint8 \
		-Mdir $(BUILD_DIR)/requantizer \
		$(RTL_DATAPATH)/requantizer_int32_to_uint8.sv \
		$(TB_DATAPATH)/tb_requantizer_int32_to_uint8.sv
	@$(BUILD_DIR)/requantizer/Vtb_requantizer_int32_to_uint8

test-relu: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_relu_uint8_zp127 \
		-Mdir $(BUILD_DIR)/relu \
		$(RTL_DATAPATH)/relu_uint8_zp127.sv \
		$(TB_DATAPATH)/tb_relu_uint8_zp127.sv
	@$(BUILD_DIR)/relu/Vtb_relu_uint8_zp127

test-maxpool: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_maxpool2x2_uint8 \
		-Mdir $(BUILD_DIR)/maxpool \
		$(RTL_DATAPATH)/maxpool2x2_uint8.sv \
		$(TB_DATAPATH)/tb_maxpool2x2_uint8.sv
	@$(BUILD_DIR)/maxpool/Vtb_maxpool2x2_uint8

test-argmax: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_argmax_8 \
		-Mdir $(BUILD_DIR)/argmax \
		$(RTL_DATAPATH)/argmax_8.sv \
		$(TB_DATAPATH)/tb_argmax_8.sv
	@$(BUILD_DIR)/argmax/Vtb_argmax_8

test-postprocess: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-fatal -Wno-BLKSEQ \
		--top-module tb_kws_postprocess \
		-Mdir $(BUILD_DIR)/postprocess \
		$(RTL_DATAPATH)/requantizer_int32_to_uint8.sv \
		$(RTL_DATAPATH)/relu_uint8_zp127.sv \
		$(RTL_DATAPATH)/maxpool2x2_uint8.sv \
		$(RTL_DATAPATH)/kws_postprocess.sv \
		$(TB_DATAPATH)/tb_kws_postprocess.sv
	@$(BUILD_DIR)/postprocess/Vtb_kws_postprocess

test-python-golden:
	python3 scripts/verify_uint8_postprocess.py

test: test-weight-buffer test-weight-sum-builder test-pe8-result-correction test-requantizer test-relu test-maxpool test-argmax test-postprocess \
	test-python-golden

lint: lint-weight-buffer lint-weight-sum-builder lint-pe8-result-correction
	$(VERILATOR) --lint-only --timing -Wall -Wno-fatal -Wno-MULTITOP \
		$(RTL_DATAPATH)/requantizer_int32_to_uint8.sv \
		$(RTL_DATAPATH)/relu_uint8_zp127.sv \
		$(RTL_DATAPATH)/maxpool2x2_uint8.sv \
		$(RTL_DATAPATH)/argmax_8.sv \
		$(RTL_DATAPATH)/kws_postprocess.sv

clean:
	rm -rf $(BUILD_DIR)

.PHONY: test-pe8-result-correction lint-pe8-result-correction
test-pe8-result-correction: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ \
		--top-module tb_pe8_result_correction \
		-Mdir $(BUILD_DIR)/pe8_result_correction \
		$(RTL_DATAPATH)/pe8_result_correction.sv \
		$(TB_DATAPATH)/tb_pe8_result_correction.sv
	@$(BUILD_DIR)/pe8_result_correction/Vtb_pe8_result_correction

lint-pe8-result-correction:
	$(VERILATOR) --lint-only -Wall --top-module pe8_result_correction \
		$(RTL_DATAPATH)/pe8_result_correction.sv

.PHONY: test-weight-sum-builder lint-weight-sum-builder
test-weight-sum-builder: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ \
		--top-module tb_pe_weight_sum_builder -Mdir $(BUILD_DIR)/weight_sum_builder \
		$(RTL_DATAPATH)/pe_weight_sum_builder.sv $(TB_DATAPATH)/tb_pe_weight_sum_builder.sv
	@$(BUILD_DIR)/weight_sum_builder/Vtb_pe_weight_sum_builder

lint-weight-sum-builder:
	$(VERILATOR) --lint-only -Wall --top-module pe_weight_sum_builder \
		$(RTL_DATAPATH)/pe_weight_sum_builder.sv

.PHONY: test-weight-buffer lint-weight-buffer
test-weight-buffer: | $(BUILD_DIR)
	$(VERILATOR) --binary --timing -Wall -Wno-BLKSEQ \
		--top-module tb_pe_weight_buffer_12 -Mdir $(BUILD_DIR)/weight_buffer \
		$(RTL_DATAPATH)/pe_weight_buffer_12.sv $(TB_DATAPATH)/tb_pe_weight_buffer_12.sv
	@$(BUILD_DIR)/weight_buffer/Vtb_pe_weight_buffer_12

lint-weight-buffer:
	$(VERILATOR) --lint-only -Wall --top-module pe_weight_buffer_12 \
		$(RTL_DATAPATH)/pe_weight_buffer_12.sv

.PHONY: test-weight-buffer-iverilog
test-weight-buffer-iverilog: | $(BUILD_DIR)
	$(IVERILOG) $(IVL_FLAGS) -g2012 -s tb_pe_weight_buffer_12 \
		-o $(BUILD_DIR)/weight_buffer_cross.vvp \
		$(RTL_DATAPATH)/pe_weight_buffer_12.sv $(TB_DATAPATH)/tb_pe_weight_buffer_12.sv
	$(VVP) $(BUILD_DIR)/weight_buffer_cross.vvp
