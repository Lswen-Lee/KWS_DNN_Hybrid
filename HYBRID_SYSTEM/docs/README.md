# HYBRID_SYSTEM 文件入口

整理完成：2026-10-20（接續2026-10-19的整理）。**先看現行基準，再看元件規格；歷史階段的「未完成」不是目前狀態，舊PASS也不代表新RTL已重測。**

## 建議閱讀順序

1. [架構基準](SINGLE_BUFFER_ARCHITECTURE.md)：固定單buffer、分工與階段歷史。
2. [共享資料路徑](SHARED_POSTPROCESS_STEP2.md)：PE/DCIM如何使用同一Reader／Writer／PoT／RAM。
3. [完整推論排程](S5D1_FULL_INFERENCE.md) → [分類整合](S5D2_ARGMAX.md) → [板級整合](S6_BOARD_INTEGRATION.md)。
4. [時序與合成統一入口](TIMING_AND_SYNTHESIS_GUIDE.md)：最新PoT輸出FF、過去實驗、Tcl與結果解讀。

目前RTL已有PoT輸出暫存級（c1ca412），順序檢查預設保留；局部測試與lint通過，該次更動的完整全鏈及實體時序仍待驗證。Backend候選加總暫存級只有討論，**尚未實作**。

## 按用途找文件

| 主題 | 文件與用途 |
|---|---|
| 記憶體／控制 | [Activation控制流程](ACTIVATION_PATH_CONTROL_GUIDE.md)、[Writer最新管線規格](FEATURE_MAP_WRITER_PIPELINE.md)、[延後最佳化清單](DEFERRED_OPTIMIZATION_BACKLOG.md) |
| PE | [層控制器](PE_LAYER_CONTROLLER.md)、[PE/PoT整合](PE_POT_INTEGRATION.md)、[組合後處理設計脈絡](PE_COMBINATIONAL_POSTPROCESS.md) |
| DCIM | [Backend](S5A_DCIM_BACKEND.md)、[CDC整合](S5B_DCIM_CDC_INTEGRATION.md)、[層控制器](DCIM_LAYER_CONTROLLER.md)、[整層記憶體整合](S5C_DCIM_LAYER_MEMORY.md)、[數學與mapping](DCIM_S5_FORMULAS.md) |
| 系統排程 | [S4 PE區段](S4_LAYER_SEQUENCER.md)、[FULL九操作](S5D1_FULL_INFERENCE.md)、[Argmax](S5D2_ARGMAX.md)；S4拒絕FULL為歷史版本限制 |
| 共享後處理 | [Step 1歷史](SHARED_POSTPROCESS_STEP1.md)、[Step 2整合](SHARED_POSTPROCESS_STEP2.md)、[最新輸出FF](POT_OUTPUT_REGISTER.md) |
| 後處理實作 | [UINT8原始設計](UINT8_POSTPROCESS_DESIGN.md)、[PoT量化器](REQUANTIZER_POT_ARCHITECTURE.md)、[後處理獨立板測](POSTPROCESS_BOARD_TEST.md) |
| 公式／簡報 | [完整數學指南](POSTPROCESS_POT_MATH_GUIDE.md)、[簡報摘要](POT_DERIVATION_SUMMARY.md)、[逐式講解稿](POT_DERIVATION_PRESENTATION_REPORT.md)；三份用途不同，未刪除 |
| 合成／時序 | [統一指南](TIMING_AND_SYNTHESIS_GUIDE.md)、[板級規格](S6_BOARD_INTEGRATION.md) |

## 驗證與審查入口

| 範圍 | 文件 |
|---|---|
| Pool軟體golden | [SOFTWARE_POOL_GOLDEN](SOFTWARE_POOL_GOLDEN.md) |
| PE共享路徑 | [S3驗證紀錄](S3_SHARED_PATH_VERIFICATION.md) |
| 全鏈分類／錯誤／reset | [S5D2覆蓋](S5D2_TEST_COVERAGE.md) |
| Writer待複驗 | [Writer Claude任務](WRITER_PIPELINE_CLAUDE_REVIEW_PROMPT.md) |
| 板級待複驗 | [S6 Claude任務](S6_CLAUDE_REVIEW_PROMPT.md) |
| 最新PoT改動待全鏈複驗 | [PoT輸出級：驗證與Claude交接](POT_OUTPUT_REGISTER.md) |
| 歷史階段任務 | [八份交接合輯與原檔對照](archive/LEGACY_REVIEW_HANDOFFS.md) |

## 本次整理規則

- 原八份S5B/C/D、共享PoT審查及S5C提案合併至archive，保留全部正文與版本證據，刪除原根目錄副本並更新Markdown連結。
- 沒有刪除獨有設計、公式或測試結果，也沒有重跑RTL測試或變更實作。
- `PE_POT_INTEGRATION.md`、`POSTPROCESS_BOARD_TEST.md`、`POT_DERIVATION_SUMMARY.md`存在使用者未提交修改，本次完全不改動。
- 新功能應更新對應規格與本入口，不再為每次對話另開一份重複總覽。歷史結果需標示版本；不能將計畫、局部PASS、全鏈PASS與STA混為一談。
- 專案外層入口：[HYBRID_SYSTEM README](../README.md)、[資料夾規劃](../../HYBRID_PROJECT_DIRECTORY_STRUCTURE.md)。

### 整理驗收

原根目錄41份Markdown，整理後根目錄34份，加archive合輯共35份。八份舊文件逐份比對HEAD原文，除連結目標重定位外正文一致。已檢查133個相對Markdown連結及合輯review錨點，沒有缺失目標（程式碼區塊不當作連結）。本次只整理文件，沒有重跑RTL／Vivado，也未改寫使用者原有三份文件。
