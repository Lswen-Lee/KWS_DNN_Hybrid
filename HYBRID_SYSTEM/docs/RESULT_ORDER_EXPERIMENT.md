# S6：關閉結果順序檢查的獨立合成實驗

## 目的與限制

使用者授權只關閉後處理結果的 channel 順序及 last 一致性比較，量測是否改善跨模組控制路徑。不是刪除 metadata，不是刪除所有錯誤處理，也不是新增 PoT output pipeline。
`CHECK_RESULT_ORDER` 為 elaboration 參數，預設 1，沒有增加晶片腳位。0 是研究配置，不應當作具有同等防護能力的正式版本。

## 修改範圍

參數傳遞：`kws_board_top → kws_board_core → kws_inference_top → kws_activation_path → pe_layer_controller / dcim_layer_controller`。

| 項目 | CHECK=1 | CHECK=0 |
|---|---|---|
| 結果 channel 與預期計數相等 | 檢查 | 不檢查 |
| 結果 last 與預期結尾相等 | 檢查 | 不檢查 |
| post/PE error、超出結果筆數 | 保留 | 保留 |
| 非運算期結果、owner／idle residue | 保留 | 保留 |
| Reader last/count、PE replay | 保留 | 保留 |
| resident、設定範圍、Writer error | 保留 | 保留 |
| valid/ready、FIFO容量、empty排空 | 保留 | 保留 |

Writer 仍使用真實 channel tag 定址。關閉檢查時，合法範圍但錯序或重複 channel 可能導致靜默錯誤；這不是新的正確重排功能。

## 控制流程變化

```text
原：FIFO metadata → channel/last比較 ─┐
     error/count/phase等檢查 ────────┴→ runtime_bad → 握手控制 → backend CE

實驗：FIFO channel/last ───────────────→ Writer等原有資料路徑
       error/count/phase等檢查 ─────────→ runtime_bad → 握手控制 → backend CE
```

只移除 channel/last 比較分支，FIFO error/valid 到 runtime_bad 的路徑仍存在。因此不能保證 WNS 改善或完全切斷 FIFO→CE。FSM 狀態數、正常命令順序、週期、PoT算術、時脈及CDC不變。

## Vivado 2023.2：兩個獨立非OOC專案

### 一鍵自動合成／實作（2026-10-19新增）

先關閉目前專案，在Vivado Tcl Console執行：

```tcl
set order_root {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/build/kws_order_auto_run01}
set order_variants {checked unchecked}
set order_jobs 4
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/board/kws/run_order_experiment.tcl}
```

不指定order_root時使用時間戳目錄。已存在會拒絕，不重設舊runs。只跑關閉版可設`order_variants {unchecked}`。此腳本呼叫既有匯入與報告腳本，整個board/kws資料夾及來源RTL需保留，並先生成build/kws_board_vectors。腳本不修改RTL/XDC，不生成bitstream；兩版各自合成至route_design，以相同Default策略比較。

根目錄`summary.csv`記錄flow_status、WNS、WHS與setup_hold_status；COMPLETE只代表run完成，負slack仍記FAIL。TNS／失敗端點／pulse width請查看各版`reports/order/timing_summary.rpt`。另產生utilization、hierarchy、100條setup、20條hold、CDC、DRC、methodology、exceptions、clocks、route_status及routed.dcp。某版流程出錯會留下`<variant>_error.txt`，繼續另一版，最後回報錯誤；不把錯誤列成PASS。

不得在兩版執行之間修改live來源。setup/hold PASS不代表CDC或未約束路徑已通過。

`python3 board/kws/test_order_experiment_tcl.py`已通過Tcl 8.6 mock（透過libtcl，不需tclsh）：正常兩版、合成失敗後繼續另一版、負slack標FAIL、既有目錄拒絕且報告不變。mock只驗證控制流程，未驗證Vivado命令API／合成／布局繞線。Windows Vivado尚待使用者執行。

### 手動GUI流程（沿用）

先關閉現有 project，兩版使用相同 live RTL、ROM、125/53MHz與Default策略；兩次合成之間不要修改來源。不要直接拿不同策略的舊報告作為唯一baseline。

```tcl
set order_root {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/build/kws_order_run01}
set order_variant checked
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/board/kws/create_order_experiment.tcl}
```

GUI Run Synthesis → Run Implementation → Open Implemented Design，再執行：

```tcl
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/board/kws/report_order_experiment.tcl}
```

關閉專案後把 `order_variant` 改為 `unchecked`，重新 source 建立腳本並執行相同步驟。既有目錄會拒絕覆寫；重做時改用新的 order_root。

報告位於 `<order_root>/<checked或unchecked>/reports/order/`。
核對 configuration.txt 的 CHECK_RESULT_ORDER 分別為1與0。比較 WNS/TNS/違反端點、hold、LUT/FF/BRAM/DSP、前100條setup路徑與CDC。不得以Run Complete宣稱時序通過。

## 驗證入口

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM
make test-result-order-experiment lint-order-board
# 真實全層驗證，需另外執行；0使用獨立unchecked build目錄
make test-inference-top S5D_PIPE=1 S5D_POST=1 S5D_CHECK_ORDER=0
make test-inference-negative S5D_PIPE=1 S5D_POST=1 S5D_CHECK_ORDER=0
make test-inference-top S5D_PIPE=1 S5D_POST=1 S5D_CHECK_ORDER=1
```

controller協定TB以公開介面送交易，兩版跑完整Conv2/3幾何、反壓、reset、非法設定、重複完成、過量結果與錯誤鎖定。CHECK=0另外確認錯誤channel/last能通過，這只證明開關生效，不是數值正確。CHECK=1仍必須拒絕它們。協定TB不是完整算術驗收。

## Claude審查與回傳要求

1. 檢查git diff，只允許上述兩項比較被參數遮罩；不得刪除post_error、容量、非owner、idle residue或empty保護。
2. 檢查六層參數傳遞與Tcl generic，確認預設為1且兩專案策略相同。
3. 執行上面局部測試及三個全鏈命令，記錄版本、命令、exit、log與配置；勿把舊log當作新實驗通過。
4. 全鏈必須逐層比對真實軟體golden、分類6/183與32040 RAM checks；負測須命中指定Conv2 commit mismatch，不接受timeout當成功。
5. 補PE端channel/last定向案例，確認0放行、1拒絕，error兩版均拒絕；不要force FSM或算術結果。
6. 回傳未覆蓋項、是否改正式檔案、Vivado是否真的執行。若未執行不得宣稱LUT下降或125MHz通過。

本次不執行耗時全鏈或Windows Vivado；實際短測結果另記於完成紀錄。

## 本次完成紀錄

`make test-result-order-experiment lint-order-board` 已通過（Verilator 5.030）。

| 配置 | 正常層案例 | 非法配置 | fault案例 | reset案例 | patch命令 |
|---|---:|---:|---:|---:|---:|
| CHECK=1 | 9 | 10 | 11 | 7 | 454 |
| CHECK=0 | 9 | 10 | 9 | 7 | 454 |

兩版另均通過非運算期異常20例、重複done 3例、過量交易2例、完成邊界3例與busy探針6例。CHECK=0少掉的兩個FAULT就是channel/last案例，TB明確檢查它們被接收，不是跳過測試。兩版板級lint均exit 0（使用專案既有warning豁免）。

初次參數化後，Verilator在階層enum常數引用上產生異常位寬與bad_alloc。TB改為具名3-bit預期編碼，只做觀察不驅動FSM；重跑成功。RTL狀態編碼未變。

未執行：PE順序異常定向測試、全鏈golden回歸、Tcl動態mock、Vivado/STA/板測。環境沒有tclsh或Python tkinter，Tcl目前僅靜態檢查；應由Windows Vivado驗收。不能把lint當成合成或功能證明。
