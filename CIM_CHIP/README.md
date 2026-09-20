# CIM_CHIP

`CIM_CHIP`是可獨立驗證的128x128數位DCIM晶片模型及其主機介面，不負責
完整KWS模型的layer排程與後處理。

## Ownership

```text
cell/        1-bit FeSRAM/FeFET數位儲存抽象與cell邏輯
segment/     4-bit row、32x4 bank與adder tree
array/       row group、bank pair選擇與128x128 array
peripheral/  decoder、input path、accumulator與serial read/output
chip/        dcim_macro_core與dcim_chip_pin_top
fpga/        dcim_pin_master與dcim_cdc_bridge
```

下列模型相關功能由`../HYBRID_SYSTEM`負責：

- Conv2/Conv3 window與im2col資料產生
- Weight mapping、tile scheduling與weight reload
- Signed/zero-point correction、bias、requantization與activation
- Feature-map memory與layer controller
- PE/DCIM engine routing與完整KWS system top

## Completion definition

`dcim_chip_pin_top`已完成目前約定的可合成數位pin-level規格，並已通過
SRAM write/read、A4W8、A8W8、serial output及完整階層測試。它不是實體
FeFET電性模型；`pre_en`、`nv_store`、`nv_recall`與`pd_en`目前只保留腳位。

尚未完成、且仍屬於CIM_CHIP範圍的項目是：

- `nv_power_controller`的非揮發store/recall/power sequencing
- FeFET極化、遲滯、variation與retention模型
- Precharge、sense amplifier、PAD與電壓域的實體行為
- 若要提高操作頻率，adder tree/partial-sum路徑的pipeline版本

前三項若目標只是FPGA數位功能驗證，可以明確列為out of scope，不必為了
完成混合KWS加速器而實作。

## Verification

```bash
make test
```

目前回歸包含23份testbench，並覆蓋125 MHz bridge、50 MHz pin master、
真實128x128 chip hierarchy，以及單一50 MHz PYNQ-Z2自動板級測試Top。
