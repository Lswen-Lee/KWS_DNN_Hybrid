# 時序最佳化與合成：統一閱讀入口

本頁集中「現在跑哪份Tcl、看哪份報告」。各元件詳細握手規格與歷史證據留在原文件，不重複複製。日期：2026-10-19。

## 現行選擇

最新實驗：保留下面PoT輸入pipeline，但移除backend的跨group加總溢位檢查。新指令與Claude驗證規格見[BACKEND_SUM_OVERFLOW_REVIEW](BACKEND_SUM_OVERFLOW_REVIEW.md)。基準為`kws_pot_input_run01`：WNS -0.792ns、TNS -149.289ns、660失敗端點。尚未量測本次變更的實體結果。下面指令為前一次實驗入口，讀取live RTL，不可用它重跑來假定還原舊RTL。

2026-10-20目前RTL包含Writer pipeline、共用PoT輸出FF及POST=1的scale查表輸入FF，順序檢查預設開啟。**下一個要合成的是PoT輸入pipeline checked配置**，不是舊unchecked或只有輸出FF的網表。

```tcl
# 先關閉目前專案；新目錄不得已存在。
set pot_input_root {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/build/kws_pot_input_run01}
set order_jobs 4
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/board/kws/run_pot_input_pipeline.tcl}
```

固定PIPE=1、POST=1、CHECK_RESULT_ORDER=1、125/53MHz、正常非OOC流程。報告在`<pot_input_root>/checked/reports/order/`；根目錄summary.csv是流程與setup/hold摘要。容量8筆、首筆延遲與反壓細節見[PoT暫存級](POT_OUTPUT_REGISTER.md)。

## 歷次修改／實驗，不可混用版本

| 階段 | 性質 | 文件 | 狀態／限制 |
|---|---|---|---|
| Writer pipeline | RTL變更 | [Writer規格](FEATURE_MAP_WRITER_PIPELINE.md) | 已實作；舊S1描述不能取代此時序契約 |
| baseline/fanout實體策略 | 不改RTL | [實體實驗](PHYSICAL_EXPERIMENT_AND_POT_OUTPUT_PLAN.md) | 當時兩版WNS -0.918ns、TNS -351.075ns，沒有改善 |
| 關閉channel/last順序比較 | 獨立實驗 | [順序檢查實驗](RESULT_ORDER_EXPERIMENT.md) | unchecked舊結果WNS -1.165ns、TNS -524.409ns；非現行PoT FF結果 |
| PoT output FF | RTL變更 | [規格及測試](POT_OUTPUT_REGISTER.md) | 舊版routed WNS -1.097ns、TNS -194.272ns、869端點未通過 |
| PoT lookup/input FF | RTL變更 | [最新規格](POT_OUTPUT_REGISTER.md) | 2026-10-20新增，尚待全鏈與Vivado驗證 |
| Backend候選加總暫存級 | 尚未實作 | 對話建議，未列為現行RTL | 若新報告仍由backend加法/overflow→CE主導，再另行規劃 |

上述舊數值來自先前已檢視的routed報告，不是在此次文件整理重跑的結果。Live RTL會影響新專案，重跑同名策略不代表重現舊版本；請保存commit、dirty diff、generics與工具版本。

## 判讀結果

1. synthesis完成：只代表綜合產生網表。
2. route完成：不等於滿足時序。`Complete, Failed Timing!`仍應產報告。
3. 查timing_summary：setup WNS/TNS/端點、hold WHS/THS、pulse width與未約束路徑。
4. 查setup_paths與utilization_hier：瓶頸是否移動、代價增加在哪個模組。
5. 查CDC、exceptions、DRC與methodology；setup/hold PASS不是實體簽核。

已完成舊unchecked run而被腳本誤擋時，依[順序實驗的補報告操作](RESULT_ORDER_EXPERIMENT.md)開啟impl_1並source report腳本即可，不必重跑合成。修正提交b8884db。

## 驗證責任

功能命令及Claude回傳要求以[POT_OUTPUT_REGISTER](POT_OUTPUT_REGISTER.md)為準。測試要對應當次RTL；先前S5-D2全鏈PASS不能自動涵蓋新PoT FF。完整分類、逐層數值、排空/reset/反壓與STA需分開記錄。
