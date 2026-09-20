# HYBRID_SYSTEM

`HYBRID_SYSTEM`是完整KWS推論的整合專案。它引用`../CIM_CHIP`與`../PE_CHIP`的RTL，不複製兩個core的source。

## Planned RTL

```text
rtl/
├── common/          clock/reset與共用型態
├── control/         layer descriptor、inference controller、engine router
├── memory/          feature、PE/DCIM weight與quant parameter memories
├── datapath/        window、pool、requant、post-process、argmax
├── dcim_adapter/    mapping、loader、tile scheduler與signed correction
├── integration/     DCIM wrapper、PE/DCIM result routing與compute subsystem
├── debug/           board self-test
└── top/             kws_hybrid_system_top.sv
```

## Dependencies

```text
CIM_CHIP ----\
              -> HYBRID_SYSTEM
PE_CHIP -----/
```

## Modules moved out of CIM_CHIP

下列功能原本曾以空module規劃在`CIM_CHIP/fpga`，現在正式由本專案負責：

```text
舊CIM_CHIP名稱              HYBRID_SYSTEM預定位置
window_generator.sv    ->  rtl/datapath/kws_window_generator.sv
layer_controller.sv    ->  rtl/control/kws_layer_controller.sv
kws_dcim_backend.sv    ->  rtl/dcim_adapter/kws_dcim_backend.sv
kws_dcim_system_top    ->  rtl/top/kws_hybrid_system_top.sv
```

`dcim_pin_master.sv`與`dcim_cdc_bridge.sv`仍保留在`CIM_CHIP/fpga`，因為它們
只處理可重用的DCIM pin protocol與clock-domain crossing。本專案應直接引用，
不可複製另一份RTL。

## Implemented UINT8 post-processing

目前已完成並驗證以下共用後處理RTL：

```text
rtl/datapath/requantizer_int32_to_uint8.sv
rtl/datapath/relu_uint8_zp127.sv
rtl/datapath/maxpool2x2_uint8.sv
rtl/datapath/argmax_8.sv
rtl/datapath/kws_postprocess.sv
```

架構、數值公式、測試資料與執行方法請參考：

- [`docs/UINT8_POSTPROCESS_DESIGN.md`](docs/UINT8_POSTPROCESS_DESIGN.md)

執行全部後處理測試：

```bash
make test
```

PE core、DCIM adapter、feature-map memory與全系統controller仍待後續整合。
