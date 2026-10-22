# 板級 reset 啟動控制修正（2026-10-22）

只修改board/kws/kws_clock_reset.sv；CIM_CHIP內部reset、pin master、CDC介面、MMCM參數及XDC/pre_opt.tcl均不改。封存的時序通過DCP保持不動，新RTL不能沿用其STA結論。

## 架構

```text
reset_button OR !MMCM_LOCKED
            │ startup_reset（非同步來源）
            ▼
兩級 startup_reset_sync（非同步置1、125MHz逐級移入0）
            ├─→ release_count/release_ready 的同步清除
            └─→ 兩域輸出reset同步器的非同步置1

button_sync / lock_sync → 穩定等待計數 → release_ready
                                              │ 資料端（反相）
                                ┌─────────────┴────────────┐
                                ▼                          ▼
                           sys_reset_sync             cim_reset_sync
                           125MHz四級                 53MHz四級
                                ↓                          ↓
                               rst                       rst_cim
```

舊版直接用startup_reset非同步清除22-bit計數器及ready；新版只有小型startup同步器接此來源，計數器改為posedge clk內同步清除。common_reset取startup_reset_sync[1]的FF輸出，不再是reset_button OR !locked OR !release_ready的組合結果。button_sync/lock_sync保留原名字與穩定檢查，避免破壞既有hook對lock_sync[0]的查找。

release_ready只進入兩域四級同步器第一級D，其他級逐級移動；不控制整條非同步PRE。啟動故障會非同步傳遞到兩域reset，但解除需本域時脈，CIM時脈停止時rst_cim保持1。startup_reset_sync延長短脈波，確保舊release_ready已被同步清除；直接用原始短脈波作common_reset會有舊ready穿入管線的風險，新增TB曾抓到此問題，已修正。

## 時序契約

故障解除後，startup同步器需要兩個125MHz上升緣移出reset；release_count必須看見startup/button/lock檢查均正常才開始計數。RELEASE_CYCLES預設2,500,000（125MHz下20ms）；另有同步與本域四級釋放延遲，總啟動時間不是精確20ms。此為reset啟動延遲變更，非推論每筆運算的延遲。

不保證兩域reset同一時刻解除。原有外部啟動/CDC協定仍需遵守共同reset要求。本修改沒有把CIM reset1/reset2改成同步清除，也沒有修正所有CDC/LUTAR警告。原始button/LOCKED合併仍接startup同步器，需實體審核；不能以數位TB證明沒有亞穩態或類比毛刺。

## 驗證

獨立命令：`make test-kws-clock-reset`。Verilator 5.030通過，日誌`/tmp/kws-reset-test.log`。

`make lint-kws-board` exit 0（使用專案既有warning豁免，行為clock分支），日誌`/tmp/kws-reset-board-lint.log`。不代表非VERILATOR的Xilinx primitive分支已經Vivado驗證。

- 按鍵抖動與再次reset恢復。
- 單獨MMCM失鎖／恢復：僅force模擬LOCKED邊界，未force FSM或reset輸出。
- 0.2ns短按鍵脈波：不能遺漏或沿用舊ready提前解除。
- CIM時脈停止：系統可完成等待，但CIM reset須等時脈恢復後才能解除。
- 每次穩定等待至少8拍（TB縮短參數），兩域解除必須在各自上升緣且至少經四級。
- watchdog防永久等待。

模擬使用VERILATOR的行為時脈分支，不是UNISIM/MMCM或metastability模擬。未執行全鏈reset回歸、Windows Vivado CDC/STA與板測。既有XDC對所有CLR/PRE的false path仍未縮小；新CDC與recovery/removal審核不可省略。

## 重新合成

### 後續補齊板級 CDC 約束

`kws_reset_strategy_run01` 四種策略完成但未通過時序。共同最差路徑為
`release_ready_reg/Q -> cim_reset_sync_reg[0]/D`，WNS=-8.109ns。
本次另修改 `board/kws/pre_opt.tcl`：只對這條同步器入口設定 source-Q 到 destination-D 的 false path。
此為前述「XDC/pre_opt 不改」初版範圍的後續補正，不改任何 RTL 或 CIM 內部 reset。

hook 檢查來源與目的 cell、Q/D pin 各恰好一個、目的 ASYNC_REG=TRUE，並用 all_fanin 核對來源 Q 確實連到第一級 D。
缺少、重複或連接不符立即停止。實際解析的腳位名稱以 `KWS RESET CDC:` 印入 implementation runme.log。
只解除第一級的跨域邊緣關係要求；同步器後續級、系統域 reset chain 與 mailbox 資料約束不變。
這不證明 reset 毛刺、亞穩態或 recovery/removal 已完成簽核；既有 CLR/PRE 廣泛例外仍需另行審核。

`python3 board/kws/test_reset_constraint_tcl.py` 驗證正常入口範圍，以及缺少、重複、缺 ASYNC_REG、來源未連接四種拒絕情況。
這是 Tcl mock，不是 Windows Vivado 實際網表驗證。實際命中需執行新 implementation 後查閱 log 與 exceptions.rpt。
請使用新目錄 `kws_reset_cdc_strategy_run01` 重跑 baseline/aggressive；不能假定其餘 -2ns 域內違規會隨之消失。

後續修正：原 hook 僅比較字串 TRUE，可能拒絕 Vivado 回傳的布林 1。
現改成嚴格 Tcl boolean 判斷，接受 TRUE/1 等合法真值，拒絕 FALSE/0、空值與非法字串，並印出實際屬性值。
九項 mock 通過（含兩種真值與四種屬性失敗情況）；使用者提供的舊 log 沒有屬性實值，因此尚不能斷言實際一定是 1。
若新 hook 顯示 0/FALSE，必須檢查合成網表與 RTL 屬性，不可直接刪除保護或強制設定。

使用者後續實測 Vivado 2023.2：startpoints_only 回傳 release_ready_reg/C，完整 fan-in 則包含 Q 與 C。
因此連接核對改用 `all_fanin -flat -to` 的完整 cone 檢查 Q，並印出 cone；不再把 Q 當成必須出現在 timing startpoint 清單的物件。
例外仍僅為來源 Q 到第一級 D，沒有擴大到 clock 或後續同步級。mock 已依實測清單重現 C-only startpoint，九項測試通過；實際 implementation 待重新執行。
RTL/synthesis 未變，可沿用成功的 synth_1，僅 reset_run impl_baseline/impl_aggressive 並重跑；此手動重跑不會自動刷新外層實驗腳本的 summary.csv。

最終約束修正：使用者實測 Constraints 18-402/18-513 證實 Q 不可作 set_false_path 起點。
上述 Q→D 的寫法已被取代：現在用同一顆 release_ready_reg 的 C pin 到 cim_reset_sync_reg[0]/D；Q 僅用於完整 fan-in 接線檢查。
這不是 get_clocks 的全域例外，只豁免該來源暫存器到該目的第一級的路徑，其他同步級維持計時。
mock 新增拒絕 Q 作 exception 起點，九項通過；仍須 Vivado 實際確認 exceptions 與時序報告，不將 mock 視為 STA 通過。

使用現有四策略腳本及全新目錄，例如kws_reset_strategy_run01，設定px_variants為{aggressive}即可先跑一版。需重新synthesis，不能開啟舊routed.dcp作post-route來測新RTL。核對新的CDC-7/10、LUTAR-1、setup/hold、reset例外範圍；不能預先承諾警告全消失或125MHz繼續通過。
