VERILATOR ?= verilator
BUILD ?= /tmp/kws_postprocess_board
RTL = $(wildcard *.sv) ../../rtl/datapath/pot_result_stream.sv ../../rtl/datapath/kws_pot_shift_rom.sv $(wildcard ../../rtl/datapath/requantizer_int32_to_uint8_pot*.sv) ../../rtl/datapath/maxpool2x2_uint8.sv ../../rtl/datapath/argmax_8.sv ../../rtl/integration/postprocess_tail.sv
.PHONY: test vectors
vectors:
	python3 generate_vectors.py
test:
	$(VERILATOR) --binary --timing --top-module tb_postprocess_board --Mdir $(BUILD) $(RTL) ../../tb/integration/tb_postprocess_board.sv
	$(BUILD)/Vtb_postprocess_board
