VERILATOR ?= verilator
.DEFAULT_GOAL := help
IVERILOG ?= iverilog
VVP ?= vvp
IVL_FLAGS ?=
BUILD_DIR := build
RTL_DATAPATH := rtl/datapath
TB_DATAPATH := tb/datapath

.PHONY: test-dcim-layer-controller lint-dcim-layer-controller
lint-dcim-layer-controller:
	$(VERILATOR) --lint-only -Wall --top-module dcim_layer_controller rtl/control/dcim_layer_controller.sv
test-dcim-layer-controller: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDSIGNAL --top-module tb_dcim_layer_controller -Mdir $(BUILD_DIR)/dcim_layer_controller rtl/control/dcim_layer_controller.sv tb/control/tb_dcim_layer_controller.sv
	$(BUILD_DIR)/dcim_layer_controller/Vtb_dcim_layer_controller
	@ulimit -c 0; if $(BUILD_DIR)/dcim_layer_controller/Vtb_dcim_layer_controller +CORRUPT_EXPECTATION > $(BUILD_DIR)/dcim_layer_controller/negative.log 2>&1; then echo "FAIL: corrupt coordinate expectation accepted"; exit 1; else grep -q 'reader coordinates mismatch' $(BUILD_DIR)/dcim_layer_controller/negative.log && echo "PASS expected controller coordinate rejection"; fi
	@ulimit -c 0; if $(BUILD_DIR)/dcim_layer_controller/Vtb_dcim_layer_controller +CORRUPT_WRITER > $(BUILD_DIR)/dcim_layer_controller/negative_writer.log 2>&1; then echo "FAIL: corrupt Writer expectation accepted"; exit 1; else grep -q 'output coordinate/tag mismatch' $(BUILD_DIR)/dcim_layer_controller/negative_writer.log && echo "PASS expected controller Writer coordinate rejection"; fi

# S5-A uses the real chip hierarchy, not an arithmetic response stub.
DCIM_BACKEND_RTL := rtl/dcim_adapter/dcim_u8_offset_correction.sv rtl/dcim_adapter/kws_dcim_backend.sv
DCIM_CHIP_RTL := $(wildcard ../CIM_CHIP/cell/*.sv ../CIM_CHIP/segment/*.sv ../CIM_CHIP/array/*.sv ../CIM_CHIP/peripheral/*.sv ../CIM_CHIP/chip/*.sv) ../CIM_CHIP/fpga/dcim_pin_master.sv
DCIM_SUBSYSTEM_RTL := $(DCIM_BACKEND_RTL) $(DCIM_CHIP_RTL) ../CIM_CHIP/fpga/dcim_cdc_bridge.sv rtl/integration/kws_dcim_subsystem.sv
DCIM_LAYER_MEMORY_RTL = $(ACTIVATION_RTL) rtl/datapath/activation_reader.sv rtl/control/feature_map_writer.sv rtl/control/dcim_layer_controller.sv $(DCIM_SUBSYSTEM_RTL) $(POT_STREAM_RTL)
.PHONY: test-dcim-layer-memory
test-dcim-layer-memory: generate-activation-path-vectors | $(BUILD_DIR)
	@set -e; for pipe in 0 1; do \
	  $(VERILATOR) --binary -j 4 --timing -Wall -Wno-SYNCASYNCNET -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM "-GPOSTPROCESS_PIPELINED=1'b$$pipe" --top-module tb_dcim_layer_memory -Mdir $(BUILD_DIR)/dcim_layer_memory_$$pipe $(DCIM_LAYER_MEMORY_RTL) tb/integration/tb_dcim_layer_memory.sv; \
	  $(BUILD_DIR)/dcim_layer_memory_$$pipe/Vtb_dcim_layer_memory +VECTORS=$(BUILD_DIR)/activation_path_vectors > $(BUILD_DIR)/dcim_layer_memory_$$pipe/software.log 2>&1 || { tail -30 $(BUILD_DIR)/dcim_layer_memory_$$pipe/software.log; exit 1; }; \
	  cat $(BUILD_DIR)/dcim_layer_memory_$$pipe/software.log; \
	  ulimit -c 0; if $(BUILD_DIR)/dcim_layer_memory_$$pipe/Vtb_dcim_layer_memory +VECTORS=$(BUILD_DIR)/activation_path_vectors +SMOKE_ONLY +CORRUPT_GOLDEN > $(BUILD_DIR)/dcim_layer_memory_$$pipe/negative.log 2>&1; then echo 'FAIL corrupted golden accepted'; exit 1; else grep -q 'post UINT8 mismatch' $(BUILD_DIR)/dcim_layer_memory_$$pipe/negative.log; fi; \
	done
.PHONY: test-dcim-subsystem lint-dcim-subsystem
lint-dcim-subsystem:
	$(VERILATOR) --lint-only -Wall -Wno-SYNCASYNCNET -Wno-PINCONNECTEMPTY -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM --top-module kws_dcim_subsystem $(DCIM_SUBSYSTEM_RTL)
test-dcim-subsystem: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-SYNCASYNCNET -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM --top-module tb_kws_dcim_subsystem -Mdir $(BUILD_DIR)/dcim_subsystem $(DCIM_SUBSYSTEM_RTL) tb/integration/tb_kws_dcim_subsystem.sv
	@set -e; for config in '10000 1300 505' '9434 2700 128' '4000 0 505' '3000 1900 128'; do \
	  set -- $$config; log=$(BUILD_DIR)/dcim_subsystem/half_$${1}_phase_$${2}_seed_$${3}.log; \
	  $(BUILD_DIR)/dcim_subsystem/Vtb_kws_dcim_subsystem +CIM_HALF_PS=$$1 +PHASE_PS=$$2 +SEED=$$3 +verilator+seed+$$3 > $$log 2>&1 || { tail -40 $$log; exit 1; }; \
	  grep 'PASS S5-B SUMMARY' $$log; done
	@ulimit -c 0; if $(BUILD_DIR)/dcim_subsystem/Vtb_kws_dcim_subsystem +CORRUPT_GOLDEN > $(BUILD_DIR)/dcim_subsystem/negative_golden.log 2>&1; then echo "FAIL: corrupted golden accepted"; exit 1; else grep -q 'result mismatch' $(BUILD_DIR)/dcim_subsystem/negative_golden.log && echo "PASS expected S5-B corrupted-golden rejection"; fi
.PHONY: test-dcim-backend lint-dcim-backend
lint-dcim-backend:
	$(VERILATOR) --lint-only -Wall --top-module kws_dcim_backend $(DCIM_BACKEND_RTL)
test-dcim-backend: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-SYNCASYNCNET -Wno-BLKSEQ -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM --top-module tb_kws_dcim_backend -Mdir $(BUILD_DIR)/dcim_backend $(DCIM_BACKEND_RTL) $(DCIM_CHIP_RTL) tb/integration/tb_kws_dcim_backend.sv
	@for seed in 505 128; do $(BUILD_DIR)/dcim_backend/Vtb_kws_dcim_backend +SEED=$$seed +verilator+seed+$$seed > $(BUILD_DIR)/dcim_backend/seed_$$seed.log 2>&1; status=$$?; cat $(BUILD_DIR)/dcim_backend/seed_$$seed.log; test $$status -eq 0 || exit $$status; done
	@ulimit -c 0; if $(BUILD_DIR)/dcim_backend/Vtb_kws_dcim_backend +CORRUPT_GOLDEN > $(BUILD_DIR)/dcim_backend/negative_golden.log 2>&1; then echo "FAIL: corrupted golden accepted"; exit 1; else grep -q 'result mismatch' $(BUILD_DIR)/dcim_backend/negative_golden.log && echo "PASS expected S5-A corrupted-golden rejection"; fi

ACTIVATION_RTL := rtl/kws_system_pkg.sv rtl/memory/activation_buffer.sv
ACTIVATION_PATH_RTL = $(ACTIVATION_RTL) rtl/datapath/activation_reader.sv rtl/control/feature_map_writer.sv rtl/datapath/maxpool2x2_uint8.sv rtl/control/pool_transfer_controller.sv rtl/control/pe_layer_controller.sv $(POT_ENGINE_RTL) rtl/integration/kws_activation_path.sv
SOFTWARE_ACTIVATION_DIR ?= ../../layer_activation_uint8_pot_ceil_zp128
SOFTWARE_WEIGHT_DIR ?= ../../layer_weights_int8_pot_ceil_zp128
S4_CONTROL_RTL := rtl/kws_system_pkg.sv rtl/control/layer_descriptor_rom.sv rtl/control/layer_controller.sv
S4_RTL = $(ACTIVATION_PATH_RTL) rtl/control/layer_descriptor_rom.sv rtl/control/layer_controller.sv rtl/integration/kws_inference_top.sv
.PHONY: test-layer-descriptor test-layer-controller test-s4-software lint-s4
test-layer-descriptor: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-UNUSEDPARAM --top-module tb_layer_descriptor_rom -Mdir $(BUILD_DIR)/layer_descriptor rtl/kws_system_pkg.sv rtl/control/layer_descriptor_rom.sv tb/control/tb_layer_descriptor_rom.sv
	$(BUILD_DIR)/layer_descriptor/Vtb_layer_descriptor_rom
test-layer-controller: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-UNUSEDPARAM -Wno-BLKSEQ --top-module tb_layer_controller -Mdir $(BUILD_DIR)/layer_controller $(S4_CONTROL_RTL) tb/control/tb_layer_controller.sv
	$(BUILD_DIR)/layer_controller/Vtb_layer_controller
lint-s4:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY --top-module kws_inference_top $(S4_RTL)
test-s4-software: generate-activation-path-vectors | $(BUILD_DIR)
	@for pipe in 0 1; do \
		$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY "-GRESULT_PIPELINED=1'b$$pipe" --top-module tb_kws_s4_software -Mdir $(BUILD_DIR)/s4_$$pipe $(S4_RTL) tb/integration/tb_kws_s4_software.sv || exit $$?; \
		for seed in 505 128; do \
			$(BUILD_DIR)/s4_$$pipe/Vtb_kws_s4_software +VECTORS=$(abspath $(BUILD_DIR)/activation_path_vectors) +SEED=$$seed > $(BUILD_DIR)/s4_$$pipe/seed_$$seed.log 2>&1; status=$$?; \
			cat $(BUILD_DIR)/s4_$$pipe/seed_$$seed.log; test $$status -eq 0 || exit $$status; \
		done; \
	done
	@ulimit -c 0; if $(BUILD_DIR)/s4_0/Vtb_kws_s4_software +VECTORS=$(abspath $(BUILD_DIR)/activation_path_vectors) +CORRUPT_GOLDEN > $(BUILD_DIR)/s4_0/negative_golden.log 2>&1; then echo "FAIL: corrupted S4 golden accepted"; exit 1; else grep -q 'S4 commit mismatch' $(BUILD_DIR)/s4_0/negative_golden.log && echo "PASS expected S4 corrupted-golden rejection"; fi
test: test-layer-descriptor test-layer-controller
lint: lint-s4
.PHONY: generate-activation-path-vectors test-activation-path-vectors test-pe-conv1-pool-memory
test-activation-path-vectors:
	python3 scripts/test_activation_path_vectors.py
generate-activation-path-vectors:
	python3 scripts/generate_activation_path_vectors.py --activations "$(SOFTWARE_ACTIVATION_DIR)" --weights "$(SOFTWARE_WEIGHT_DIR)"
test-pe-conv1-pool-memory: generate-activation-path-vectors | $(BUILD_DIR)
	@for pipe in 0 1; do \
		$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY "-GRESULT_PIPELINED=1'b$$pipe" --top-module tb_pe_conv1_pool_memory -Mdir $(BUILD_DIR)/pe_conv1_pool_$$pipe $(ACTIVATION_PATH_RTL) tb/integration/tb_pe_conv1_pool_memory.sv || exit $$?; \
		for seed in 505 128; do \
			$(BUILD_DIR)/pe_conv1_pool_$$pipe/Vtb_pe_conv1_pool_memory +VECTORS=$(abspath $(BUILD_DIR)/activation_path_vectors) +SEED=$$seed > $(BUILD_DIR)/pe_conv1_pool_$$pipe/seed_$$seed.log 2>&1; status=$$?; \
			cat $(BUILD_DIR)/pe_conv1_pool_$$pipe/seed_$$seed.log; test $$status -eq 0 || exit $$status; \
		done; \
	done
	@ulimit -c 0; if $(BUILD_DIR)/pe_conv1_pool_0/Vtb_pe_conv1_pool_memory +VECTORS=$(abspath $(BUILD_DIR)/activation_path_vectors) +CORRUPT_GOLDEN > $(BUILD_DIR)/pe_conv1_pool_0/negative_golden.log 2>&1; then echo "FAIL: corrupted golden accepted"; exit 1; else grep -q 'Commit mismatch' $(BUILD_DIR)/pe_conv1_pool_0/negative_golden.log && echo "PASS expected corrupted-golden rejection"; fi
.PHONY: test-activation-path lint-activation-path test-activation-path-software
test-activation-path-software: test-activation-path
	$(BUILD_DIR)/activation_path/Vtb_kws_activation_path +SOFTWARE_ROOT=$(abspath $(SOFTWARE_ACTIVATION_DIR))
test: test-activation-path
lint: lint-activation-path
test-activation-path: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY --top-module tb_kws_activation_path -Mdir $(BUILD_DIR)/activation_path $(ACTIVATION_PATH_RTL) tb/integration/tb_kws_activation_path.sv
	$(BUILD_DIR)/activation_path/Vtb_kws_activation_path
lint-activation-path:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY --top-module kws_activation_path $(ACTIVATION_PATH_RTL)
READER_RTL := $(ACTIVATION_RTL) rtl/datapath/activation_reader.sv
.PHONY: test-activation-reader lint-activation-reader
test: test-activation-reader
lint: lint-activation-reader
test-activation-reader: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM --top-module tb_activation_reader -Mdir $(BUILD_DIR)/activation_reader $(READER_RTL) tb/datapath/tb_activation_reader.sv
	$(BUILD_DIR)/activation_reader/Vtb_activation_reader
lint-activation-reader:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM --top-module activation_reader rtl/kws_system_pkg.sv rtl/datapath/activation_reader.sv
WRITER_RTL := $(ACTIVATION_RTL) rtl/control/feature_map_writer.sv
.PHONY: test-feature-map-writer lint-feature-map-writer
test: test-feature-map-writer
lint: lint-feature-map-writer
test-feature-map-writer: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM --top-module tb_feature_map_writer -Mdir $(BUILD_DIR)/feature_map_writer $(WRITER_RTL) tb/control/tb_feature_map_writer.sv
	$(BUILD_DIR)/feature_map_writer/Vtb_feature_map_writer
lint-feature-map-writer:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM --top-module feature_map_writer rtl/kws_system_pkg.sv rtl/control/feature_map_writer.sv
.PHONY: build-activation-buffer test-activation-buffer lint-activation-buffer
test: test-activation-buffer
lint: lint-activation-buffer
build-activation-buffer: | $(BUILD_DIR)
	$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ --top-module tb_activation_buffer -Mdir $(BUILD_DIR)/activation_buffer $(ACTIVATION_RTL) tb/memory/tb_activation_buffer.sv
test-activation-buffer: build-activation-buffer
	$(BUILD_DIR)/activation_buffer/Vtb_activation_buffer
	@ulimit -c 0; if $(BUILD_DIR)/activation_buffer/Vtb_activation_buffer +collision > $(BUILD_DIR)/activation_buffer/collision.log 2>&1; then echo "FAIL: collision accepted"; exit 1; else grep -q 'ACTIVATION_BUFFER_COLLISION' $(BUILD_DIR)/activation_buffer/collision.log && echo "PASS expected collision rejection"; fi
lint-activation-buffer:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM --top-module activation_buffer $(ACTIVATION_RTL)

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
POT_STREAM_RTL = $(POT_RTL) rtl/datapath/kws_pot_shift_rom.sv rtl/datapath/pot_result_stream.sv
POT_ENGINE_RTL = $(ENGINE_RTL) $(POT_STREAM_RTL) rtl/integration/pe_pot_engine.sv
PE_LAYER_RTL = $(ACTIVATION_RTL) rtl/datapath/activation_reader.sv rtl/control/feature_map_writer.sv rtl/control/pe_layer_controller.sv $(POT_ENGINE_RTL)
.PHONY: test-pe-external-post
test-pe-external-post: generate-activation-path-vectors | $(BUILD_DIR)
	@set -e; for post in 0 1; do for pipe in 0 1; do \
	  $(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY "-GRESULT_PIPELINED=1'b$$pipe" "-GPOSTPROCESS_PIPELINED=1'b$$post" --top-module tb_pe_layer_controller -Mdir $(BUILD_DIR)/external_layer_$${pipe}_$$post $(PE_LAYER_RTL) tb/control/tb_pe_layer_controller.sv; \
	  $(BUILD_DIR)/external_layer_$${pipe}_$$post/Vtb_pe_layer_controller; \
	  $(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY "-GRESULT_PIPELINED=1'b$$pipe" "-GPOSTPROCESS_PIPELINED=1'b$$post" --top-module tb_pe_conv1_pool_memory -Mdir $(BUILD_DIR)/external_path_$${pipe}_$$post $(ACTIVATION_PATH_RTL) tb/integration/tb_pe_conv1_pool_memory.sv; \
	  $(BUILD_DIR)/external_path_$${pipe}_$$post/Vtb_pe_conv1_pool_memory +VECTORS=$(abspath $(BUILD_DIR)/activation_path_vectors) +SEED=505; \
	done; done
	@ulimit -c 0; if $(BUILD_DIR)/external_path_0_0/Vtb_pe_conv1_pool_memory +VECTORS=$(abspath $(BUILD_DIR)/activation_path_vectors) +CORRUPT_GOLDEN > $(BUILD_DIR)/external_path_0_0/negative.log 2>&1; then echo 'FAIL external golden accepted'; exit 1; else grep -q 'Commit mismatch' $(BUILD_DIR)/external_path_0_0/negative.log && echo 'PASS external corrupted golden rejection'; fi
.PHONY: test-pe-layer-controller lint-pe-layer-controller
test: test-pe-layer-controller
lint: lint-pe-layer-controller
test-pe-layer-controller: | $(BUILD_DIR)
	@for pipe in 0 1; do \
		$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY "-GRESULT_PIPELINED=1'b$$pipe" --top-module tb_pe_layer_controller -Mdir $(BUILD_DIR)/pe_layer_$$pipe $(PE_LAYER_RTL) tb/control/tb_pe_layer_controller.sv && \
		$(BUILD_DIR)/pe_layer_$$pipe/Vtb_pe_layer_controller || exit $$?; \
	done
lint-pe-layer-controller:
	$(VERILATOR) --lint-only -Wall -Wno-UNUSEDPARAM --top-module pe_layer_controller rtl/kws_system_pkg.sv rtl/control/pe_layer_controller.sv
.PHONY: test-pot-engine
test: test-memory-engine-zp128 test-pot-engine test-pot-stream test-postprocess-pot test-dcim-offset check-engine-elaboration-zp128
.PHONY: test-pot-stream test-postprocess-pot test-dcim-offset
test-pot-stream: | $(BUILD_DIR)
	@for post in 0 1; do \
		$(VERILATOR) --binary -j 4 --timing -Wall -Wno-BLKSEQ "-GPOSTPROCESS_PIPELINED=1'b$$post" --top-module tb_pot_result_stream -Mdir $(BUILD_DIR)/pot_stream_$$post $(POT_STREAM_RTL) tb/datapath/tb_pot_result_stream.sv && \
		$(BUILD_DIR)/pot_stream_$$post/Vtb_pot_result_stream || exit $$?; \
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
	@echo "  make test-dcim-layer-controller / lint-dcim-layer-controller - S5-C controller protocol (not full DCIM arithmetic integration)"
	@echo "  make test-dcim-layer-memory - S5-C real RAM/Reader/DCIM/PoT/Writer, Conv2/3 software golden, both PoT configurations"
	@echo "  make test-layer-descriptor / test-layer-controller / lint-s4 - S4 ROM, sequencing and integrated lint"
	@echo "  make test-s4-software - actual controller-driven FRONTEND/FC_TAIL, two PE8 configurations and seeds"
	@echo "  make test-activation-path / lint-activation-path - S2 real RAM-reader-pool-writer integration"
	@echo "  make test-pe-layer-controller / lint-pe-layer-controller - S3 real Reader/RAM/PE/Writer, PE8 pipe=0/1"
	@echo "  make test-pe-conv1-pool-memory - S3 software golden chain, PE8 pipe=0/1 and two seeds"
	@echo "  make generate-activation-path-vectors / test-activation-path-vectors - validate external exports"
	@echo "  make test-activation-reader / lint-activation-reader - LINEAR/PATCH reader, stalls and replay"
	@echo "  make test-feature-map-writer / lint-feature-map-writer - LINEAR/CHW writer with real activation RAM"
	@echo "  make test-activation-buffer / lint-activation-buffer - S1 32KiB synchronous activation RAM"
	@echo "  make test-memory-engine-zp128 / check-engine-elaboration-zp128 - three raw zp128 configurations"
	@echo "  make test-pot-engine / test-pot-stream - end-to-end PE/PoT and elastic result path"
	@echo "  make test-postprocess-pot / test-dcim-offset - frame postprocessing and standalone DCIM correction"
	@echo "  make test-requantizer-pot-exports - software bytes and model shift ROM consistency"
	@echo "  make test-dcim-backend / lint-dcim-backend - S5-A real chip single-patch backend, two seeds and negative golden"
	@echo "  make test-dcim-subsystem / lint-dcim-subsystem - S5-B real CDC+chip, four clock settings, reset/fault recovery"
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
