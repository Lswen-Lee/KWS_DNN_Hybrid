VERILATOR ?= verilator
BUILD ?= /tmp/kws_postprocess_board
RTL = $(wildcard *.sv) ../../rtl/datapath/pe_pot_result_stream.sv ../../rtl/datapath/kws_pot_shift_rom.sv $(wildcard ../../rtl/datapath/requantizer_int32_to_uint8_pot*.sv)
.PHONY: test vectors
vectors:
	python3 generate_vectors.py
test:
	$(VERILATOR) --binary --timing --top-module tb_postprocess_board --Mdir $(BUILD) $(RTL) ../../tb/integration/tb_postprocess_board.sv
	$(BUILD)/Vtb_postprocess_board
