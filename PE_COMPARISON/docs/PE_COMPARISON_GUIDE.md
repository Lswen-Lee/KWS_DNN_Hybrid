# PE9 / PE8 比較操作說明

## 最新：等價stream top已實作

操作請見 [PE_EQUIVALENT_IMPLEMENTATION.md](PE_EQUIVALENT_IMPLEMENTATION.md)。
新增make test-equivalent/lint-equivalent及create_pe_equivalent_project.tcl。
舊create_pe8_project/create_pe9_project仍是raw array，與新比較範圍不同，
請勿將報告混用。下方保留歷史進度；第一階段top已不再只是規劃。

## 2026-09-14：兩邊統一LUT／FF

PE9已移除explicit DSP，保留Product FF與32-bit ACC；PE8亦為LUT／FF。
common_setup.tcl的MAX_DSP改為0（新建專案生效）。歷史DSP章節／報告保留，
不代表目前RTL；不要執行要求12DSP的report_dsp_mac.tcl。
等價top與LUT/FF表格規劃見 [PE_LUT_EQUIVALENT_PLAN.md](PE_LUT_EQUIVALENT_PLAN.md)。
本次未建立等價top，現有create腳本仍是array範圍，不能當成完整補償backend面積。

## 2026-09-12 PE8 LUT Core 更新

PE_CHIP_8x8 現在改為 LUT/FF MAC 並新增 pe8_core_controller、pe8_core_12；PE_CHIP 保持 explicit DSP。原 array 數值比較仍可使用，但 PPA 已同時包含資源實作差異，不能視為只改位寬的公平比較。report_dsp_mac.tcl 的12DSP檢查目前僅適用PE9，不適用PE8。PE8應確認DSP=0。既有create_pe8_project.tcl仍建立array，不會自動改成core top；core來源与介面見PE8架構文件。

## 最新狀態：explicit DSP48E1（2026-09-12）

推導版產生了 24 DSP，現在每 lane 改為直接實例化一顆 DSP48E1（MREG=1、PREG=1），目標 array=12 DSP。原本五份 RTL source 清單不需增加檔案；只更新 lane 的實際來源副本。**不要將 sim_vendor、sim_verilator 匯入 Vivado synthesis**。Vivado/XSim 應使用內建 primitive/UNISIM。

`report_dsp_mac.tcl` 現在會檢查數量是否恰好 12 且 MREG/PREG=1。單靠減少 DSP 不能保證 reset Hold 違反消失，請仍查看 routed WNS/WHS。之前的 24 DSP 推導版備份為 snapshots/pre_explicit_dsp48_20260912.tar.gz。

普通 make test/lint 使用限定功能 Verilator model；新增 `make test-unisim` 使用官方 Xilinx 模型與 Icarus，兩種模型不可混用。已完成官方模型測試：兩份 lane 各 280241 checks、兩份 array 2928/2964 checks、comparison 10812 checks 全通過。完整來源/版本/啟動假設見 sim_vendor/README.md。

## 最新比較對象：Pipelined DSP MAC

兩份 lane 已改為 product_reg + 48-bit feedback accumulator，對外仍取低 32-bit。最後接受資料後需多一個 drain clock；兩邊 TB 都以延遲一拍的有效交易做 reference。舊版來源與測試保存在 `../snapshots/pre_dsp_mac_20260911.tar.gz`，舊報告沒有刪除。請勿將舊版週期契約當作新版使用。

Open Synthesized Design 後，可執行：

```tcl
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/PE_COMPARISON/vivado/report_dsp_mac.tcl}
```

除了 DSP 數量，應檢查 DSP Final Report 是否將累加一併映射（A*B+P）、MREG/PREG 是否啟用，以及最長路徑是否仍經外部累加 carry chain。一般 RTL 推導不能保證實際映射；此環境沒有 Vivado，尚未確認 125 MHz 或實際 PPA。

本次 Verilator 驗證：PE9/PE8 的 test/lint 全通過，各 MAC 280241 checks，array 分別 2928/2964 checks；comparison 10812 lane checks（三種判斷各次），工具測試 6 項全通過。獨立 multiplier/accumulator 舊單元測試仍保留並通過。MAC TB 重寫為 pipeline/control/overflow 測試，8×8 的補償正確性仍由 array/comparison TB 驗證。

## 1. 範圍與完整性

本資料夾直接引用相鄰 PE_CHIP 與 PE_CHIP_8x8，不複製 RTL，不修改兩版。
本階段比較 raw array：不包含 activation 轉換器、weight-sum 補償、參數記憶體、core 控制器。
功能測試包含外部轉換器，但 Vivado 比較來源刻意不包含它們。
不自動執行 Vivado synthesis、implementation，也不產生 bitstream。

S=Σ(A−127)W，D=Σ(A−128)W，S=D+ΣW。
8×8 的補償在 testbench 中計算，不代表硬體已完成補償。
所有 sum 只計入 accumulate_en 且 mask 有效的 operand。
目前測試長度不會溢位；不是任意長度的形式等價證明。

## 2. 功能測試

```sh
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/PE_COMPARISON
make test
make lint
make check-tools
```

TB 同時接兩版原始 RTL，每次正緣後比對全部12路：
原版對照獨立整數 gold9、新版對照 gold8、兩者再檢查 weight sum 等價關係。
涵蓋 packing、reset/clear優先、hold、FFF/0FF/AAA/555/000/12種one-hot、
A=0/127/128/255、W=−128/127、K=9/32/144、正負零權重、停頓重啟。
LCG 固定 seed=0x19a2b3c4，混合 activation、weight 與 mask 可重現。
測試成功只列摘要，失敗列 lane、實際值與reference並 $fatal。
舊的單元回歸仍在各自資料夾，這個 Makefile 不會刪除它們。

## 3. Tcl 每份檔案做什麼

| 檔案 | 行為 |
|---|---|
| create_pe9_project.tcl | 載入 common_setup，再建立原版專案 |
| create_pe8_project.tcl | 載入 common_setup，再建立新版專案 |
| common_setup.tcl | 找相鄰RTL、確認檔案存在、建立獨立project、設定part/top/SystemVerilog/OOC/共用XDC |
| export_reports.tcl | 對當下已開啟的design輸出資源、時序、DRC、route status及methodology報告；不launch runs |

路徑由 info script 所在位置推導，不依赖 Linux 固定路徑，Windows 也可搬移使用。
搬移時請保留三個資料夾為相鄰目錄。
common_setup 不會關閉既有project，也不使用 -force 覆蓋。若資料夾已存在，請直接 Open Project 開啟其 XPR。
part 預設 xc7z020clg400-1（PYNQ-Z2使用的器件），請核對實際板卡器件。
target_language=Verilog 只設定專案預設語言；每個 .sv 都另外指定 file_type=SystemVerilog，兩者不衝突。
flatten_hierarchy=rebuilt；不額外設定 DONT_TOUCH/KEEP_HIERARCHY 或強迫 DSP。兩版使用同一預設策略。
MORE OPTIONS 的 -mode out_of_context 是 synth_design 選項，目的是將array視為核心而非板級IO。
update_compile_order 讓 package 排在使用它的module之前。

## 4. 使用 Tcl 建立專案（不自動合成）

在 Vivado 2023.2 開啟 Tcl Console，且先關閉目前project：

```tcl
source {C:/your_workspace/KWS_DNN_Hybrid/PE_COMPARISON/vivado/create_pe9_project.tcl}
```

Linux 將上面路徑改為實際路徑。使用大括號保護空白，Windows使用正斜線。
建立後由你按 Run Synthesis。另一個版本在不同 Vivado 視窗或關閉原專案後：
```tcl
source {C:/your_workspace/KWS_DNN_Hybrid/PE_COMPARISON/vivado/create_pe8_project.tcl}
```

專案產生於 build/pe9 與 build/pe8，與 build/sim 模擬輸出不同。
若 MORE OPTIONS property 在你的介面不接受，停止並依下一節 GUI 設定；不可忽略OOC設定後繼續當作同條件比較。
本環境未安裝 Vivado，Tcl 的 Vivado API/property 尚須在你的2023.2實測。

## 5. 完全以 GUI 建立（Tcl 匯入失敗的替代步驟）

### 5.1 New Project

1. Create Project，建立 pe_compare_pe9。選一個新的空專案目錄。
2. 選 RTL Project。不要同時匯入整個 KWS_DNN_Hybrid。
3. Add Sources：只選下面列出的5個原版檔案。
4. 每份來源確認 Type=SystemVerilog。不要加入 tb、build、另一版RTL。
5. Add Constraints：選 PE_COMPARISON/constraints/pe_array_ooc.xdc。
6. Default Part → Parts：選 xc7z020clg400-1。不需要 Board Files 或PS Block Design。
7. 完成後，在 Sources 右鍵 pe_array_12 → Set as Top。
8. Sources 的 Compile Order 確認 pe_pkg.sv 在使用它的module之前。
9. Settings → Synthesis：flatten_hierarchy 設 rebuilt。
10. 在 synthesis 的 More Options 欄填 -mode out_of_context（不同介面可能需展開 Options）。
11. Run Synthesis 後查看 runme.log，確認實際 synth_design 命令含 -mode out_of_context。
12. Open Synthesized Design，確認不是空電路，且不是數百個板級 IBUF/OBUF。

原版五個 Design Sources：
```text
PE_CHIP/rtl/pe_pkg.sv
PE_CHIP/rtl/arithmetic/pe_multiplier_s9xs8.sv
PE_CHIP/rtl/arithmetic/pe_accumulator_s32.sv
PE_CHIP/rtl/arithmetic/pe_mac_lane.sv
PE_CHIP/rtl/array/pe_array_12.sv
```

新版另建 pe_compare_pe8，其他設定相同，五個來源：
```text
PE_CHIP_8x8/rtl/pe8_pkg.sv
PE_CHIP_8x8/rtl/arithmetic/pe8_multiplier_s8xs8.sv
PE_CHIP_8x8/rtl/arithmetic/pe8_accumulator_s32.sv
PE_CHIP_8x8/rtl/arithmetic/pe8_mac_lane.sv
PE_CHIP_8x8/rtl/array/pe8_array_12.sv
```
新版 top 為 pe8_array_12。

若 GUI 找不到 More Options，不要誤用一般板級 implementation。
可以先檢查 Tcl Console 的 run properties：
```tcl
report_property [get_runs synth_1]
set_property {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} {-mode out_of_context} [get_runs synth_1]
```
若仍不接受，保留錯誤與Vivado版本資訊，不能宣稱OOC已設定。

### 5.2 Implementation 的重要檢查

OOC 必須保留到 implementation，不能把寬port當作真實外部引腳。
可嘗試 GUI Run Implementation（止於 Route Design，不生成bitstream）。
若遇到 IO placement 數量不足、要求 PACKAGE_PIN，或電路被大量trim，
應停止並核對run的OOC設定。不要替數百個核心port亂配板子引腳。

若專案式 implementation 無法保留OOC，使用下列官方 module-analysis 思路，手動在 Tcl Console 操作：
```tcl
# 先開啟OOC的 synthesized design，再執行；不要先重開成一般頂層。
opt_design
place_design
route_design
```
這些是你手動執行的合成後處理命令，建立專案腳本不會替你執行。
跨session載入netlist時需要保留OOC，例如 link_design -mode out_of_context；
不熟悉此流程時請提供run log，勿用一般 link_design 取代。
本方案無板級IO，不應產生拿去上板的bitstream。

## 6. XDC 每個參數的意義

| 約束 | 設定 | 含義 |
|---|---|---|
| create_clock | 8ns，125MHz | 兩版相同目標，需重新合成／實作 |
| clock_uncertainty | 0.2ns | 相同保守時序預算，非實測抖動 |
| input_delay max/min | 2ns / 0.5ns | 假設上游送入data/control的時間 |
| output_delay max/min | 2ns / 0.5ns | 假設下游接收需求 |
| reset | 同步，不設false path | 不把reset路徑藏起來 |
| PACKAGE_PIN/IOSTANDARD | 不設 | OOC內部核心，不是實體板子pin |

這些delay是比較用的人為介面假設，不代表PYNQ-Z2外部時序。
clock port不加input delay；其餘輸入含rst/clear/mask/enable都套用。
只設clock而不设input delay，可能讓activation→MAC→ACC路徑未被完整評估。
要改頻率就修改共用XDC並重跑兩版，不能只改其中一版。
OOC仍非實際整合布局，不能把其頻率直接保證為完整混合系統頻率。

## 7. 匯出與GUI查看報告

Open Synthesized Design 或 Open Implemented Design 後：
```tcl
source {C:/your_workspace/KWS_DNN_Hybrid/PE_COMPARISON/vivado/export_reports.tcl}
```
自動依top判斷pe9/pe8，儲存至 reports/pe9或pe8/時間戳/，不覆蓋舊報告。

GUI替代：在已開啟design後，使用 Reports 選單：
Report Utilization（另做Hierarchical）、Report Timing Summary（含min/max與unconstrained）、
Report Timing（setup/hold各10條）、Check Timing、Report DRC、Report Methodology。
Route Status可在implementation狀態與報告查看；GUI名稱可能因layout不同。
若匯出不同檔名，手動改成 utilization.rpt、timing_summary.rpt 等約定名稱再整理。

必須確認：
- 兩邊都是post-synth，或兩邊都是post-route；不可混用。
- route_status無未完成routing，資源不是被trim成0。
- check_timing/timing_summary無遺漏約束，setup/hold都檢查。
- 同part、同Vivado版本、同clock/策略、同報告階段。
- 原始report_methodology/DRC警告不因測試PASS而免除。
- 不用 WNS 直接換算 Fmax；要找最高頻率須重新約束與實作。

## 8. 整理比較表

```sh
python3 scripts/summarize_reports.py reports/pe9/TIMESTAMP reports/pe8/TIMESTAMP
# 或
make summary PE9_REPORT=reports/pe9/TIMESTAMP PE8_REPORT=reports/pe8/TIMESTAMP
```
生成 reports/comparison.csv、comparison.md（這兩個摘要再次執行會更新，原始時間戳報告保留）。
摘要解析LUT/FF/DSP/BRAM及setup/hold summary，缺項一律NOT_AVAILABLE。
未約束項目、route stage與methodology需要人工讀報告，腳本不自動宣告timing closure。
不同Vivado報告格式可能導致未解析；以原始報告為準，不填造數值。
power/energy沒有資料，不生成假數字。

## 9. 官方參考

- [AMD synth_design OOC](https://docs.amd.com/r/2023.1-English/ug835-vivado-tcl-commands/synth_design)
- [AMD 2023.2 link_design OOC](https://docs.amd.com/r/2023.2-English/ug835-vivado-tcl-commands/link_design)
- [AMD UG905 Module Analysis](https://docs.amd.com/api/khub/documents/OxygJ77Iuo6WYMt0aniUOw/content)

## 10. 本次執行紀錄

2026-09-11 使用 Verilator 5.030 執行 `make test lint check-tools`，結束碼0。

| 項目 | 結果 |
|---|---|
| 雙版本testbench | PASS，10,812次lane檢查，每次包含兩個raw reference與補償等價比對 |
| 整合RTL/TB lint | PASS，無輸出警告／錯誤（原package既有局部metadata警告豁免保留） |
| 報告工具與腳本檢查 | 6項單元測試PASS，包含資源解析、時序解析、缺失資料、排除不相干列、Tcl/XDC命令完整性、摘要CLI |
| Vivado synthesis/implementation | 未執行，環境未安裝Vivado |

Tcl/XDC檢查使用libtcl的Tcl_CommandComplete，只確認引號/括號等命令完整性，不驗證Vivado命令或property是否存在。
報告工具測試使用人工建立的小型fixture，不是實際合成數值；未生成假PPA報告。
最初Python環境沒有tkinter，改以已存在的libtcl做命令完整性檢查後全數通過。
原版與新版RTL均未修改，所有比較相關變更限定在PE_COMPARISON。
