# PE_CHIP_8x8

獨立的 signed 8×8 PE 基礎元件，原版 PE_CHIP 保留不動。
目前完成 arithmetic、pe8_pkg、pe8_array_12、pe8_core_controller、pe8_core_12，以及 PYNQ-Z2 standalone 自測頂層與測試。PE8使用LUT/FF，尚未包含weight-sum補償或完整模型推論。

板上自測：`make test-standalone`；全部回歸：`make test lint`。
Vivado 匯入：`vivado/create_pe8_standalone_project.tcl`（只建立一般頂層專案，不自動合成）。
頂層 `pe8_standalone_top`，約束 `constraints/pe8_standalone_top_pynq_z2.xdc`。
BTN0重測；LED0 heartbeat、LED1 busy、LED2 PASS、LED3 FAIL。詳細操作與限制見 `docs/PE8_CORE_ARCHITECTURE.md` 最上方章節。

執行：`make test` 與 `make lint`。
完整規格與驗證內容見 [架構文件](docs/PE8_CORE_ARCHITECTURE.md)。

Vivado 先匯入 rtl/pe8_pkg.sv，再匯入 rtl/arithmetic/*.sv 與 rtl/array/pe8_array_12.sv，檔案型態設定為 SystemVerilog；
單 lane 合成頂層為 pe8_mac_lane，array 頂層為 pe8_array_12。tb 不加入 synthesis sources。
目前沒有板級頂層或 XDC，不代表可直接產生可用 bitstream。
