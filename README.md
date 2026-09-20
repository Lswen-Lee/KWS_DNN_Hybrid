# KWS_DNN_Hybrid

KWS 混合硬體推論研究：DCIM、PE9、PE8 與共用記憶體／控制／後處理。

| 目錄 | 內容 |
|---|---|
| CIM_CHIP | DCIM 行為模型、周邊、控制器與測試 |
| PE_CHIP | signed 9×8 PE |
| PE_CHIP_8x8 | signed 8×8 PE |
| HYBRID_SYSTEM | 共用 memory engine、控制器與後處理 |
| PE_COMPARISON | PE 比較、板級測試、Vivado 建立腳本 |

開始閱讀：

- [整體架構](TOP_DOWN_ARCHITECTURE_REVIEW.md)
- [板級 PE 操作與驗證](PE_COMPARISON/docs/PE_BOARD_TEST_GUIDE.md)
- [Operand Pipeline](PE_COMPARISON/docs/PE_OPERAND_PIPELINE.md)
- [PE8 架構紀錄](PE_CHIP_8x8/docs/PE8_CORE_ARCHITECTURE.md)

原始碼、TB、約束、建置腳本和文件納入 Git；大型編譯產物保留本地。
Vivado 專案應由 Tcl 重建，不依賴 build 目錄中的 Windows 專案快照。
要永久保留實驗報告，請先挑選必要文字報告／摘要放入非 build 的文件目錄，並記錄 RTL commit、工具版本及約束。

板級測試：

```bash
cd PE_COMPARISON
make lint-board
make test-board
python3 scripts/test_board_tcl.py
```

模擬 PASS 不代表 Vivado timing closure 或板級功能已驗證；各階段結果須分開記錄。
