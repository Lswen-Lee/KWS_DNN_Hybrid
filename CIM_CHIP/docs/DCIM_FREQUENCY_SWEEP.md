# CIM 板級自動掃頻：45／50／51／52／53／54／55 MHz

目前預設及支援清單均為上述七組；不會執行 40／60／65 MHz。舊 run01 的六頻率實測結果請參考 `DCIM_SWEEP_RUN01_RESULTS.md`，本次範例使用新的 `run02` 目錄，不覆寫 run01。若 Vivado Console 留有舊變數，請明確重新設定下列頻率清單。

## 比較的範圍

此實驗使用 `dcim_master_chip_top`，包含 chip、pin master、self test、MMCM／BUFG 與按鍵 reset。採正常頂層流程，不使用 OOC。RTL 邏輯不變，每次只改建置副本的 MMCM 參數。

```text
相同 RTL／XDC 快照
  ├─45 MHz ─ synthesis ─ place/route ─ reports／DCP
  ├─50 MHz ─ synthesis ─ place/route ─ reports／DCP
  ├─51 MHz ─ synthesis ─ place/route ─ reports／DCP
  ├─52 MHz ─ synthesis ─ place/route ─ reports／DCP
  ├─53 MHz ─ synthesis ─ place/route ─ reports／DCP
  ├─54 MHz ─ synthesis ─ place/route ─ reports／DCP
  └─55 MHz ─ synthesis ─ place/route ─ reports／DCP
                         ↓
            CSV＋Markdown＋LUT／FF–MHz 圖
```

提供整體 top、u_chip、macro、pin master、self test 的 LUT／FF。圖畫 top、macro、controller 三條曲線。macro 指 `u_chip/u_dcim_macro_core`，controller 指 `u_pin_master`；不要把 top 與 macro 混為同一面積，也不要把 FPGA LUT 當成實體 CIM 晶片面積。階層資料可能受跨階層最佳化影響，板級常數測資亦可能讓 controller 簡化。

## 頻率設定

實體輸入保持 125 MHz，XDC 為 8 ns。輸入除數固定 1，輸出為 `125 × M / O`。

| MHz | M | O | VCO MHz | 輸出週期 ns |
|---:|---:|---:|---:|---:|
|45|9|25|1125|22.222|
|50|8|20|1000|20.000|
|51|6.375|15.625|796.875|19.608|
|52|6.5|15.625|812.5|19.231|
|53|6.625|15.625|828.125|18.868|
|54|6.75|15.625|843.75|18.519|
|55|5.5|12.5|687.5|18.182|

45／50／55 MHz 保留前次相同 MMCM 設定。51～54 MHz 採 0.125 步進的 fractional multiplier／divider，頻率計算為精確目標值；實際 clock period 與 MMCM DRC 仍由 Vivado 檢查。

MMCM 的合法性仍由 Vivado 器件檢查確認。各頻率的 VCO／fractional divider 不同，jitter／clock uncertainty 可能跟著改變；實驗是在比較可實現的板級時脈配置，不是假設時脈理想且完全相同。時脈檔中舊 `50m` 名稱仍保留，實際頻率由參數與 `report_clocks` 判定。

## Windows Vivado 2023.2 執行

先關閉目前專案。建議使用短路徑，避免 Windows 260 字元限制；不依賴目前 `pwd`。

```tcl
# 在沒有開啟專案的 Vivado Tcl Console 執行
set dcim_sweep_root {C:/dcim_sweep/run02}
set dcim_sweep_frequencies {45 50 51 52 53 54 55}
# Windows 可使用 python，或設定為 {py -3} / {C:/Python311/python.exe}
set dcim_sweep_python {py -3}
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP/vivado/sweep_dcim_frequency.tcl}
```

若想放在原資料夾，可將 root 改成：

```tcl
set dcim_sweep_root {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP/build/frequency_sweep/run02}
```

較推薦短路徑。腳本會同步等待每一頻率完成，GUI 可能較不方便操作；也可在 Vivado Command Prompt 執行：

```bat
vivado -mode batch -source C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP/vivado/sweep_dcim_frequency.tcl -tclargs C:/dcim_sweep/run02
```

這是自動 non-project 流程（**non-project 不等於 OOC**），不建立 XPR，不使用 runs/hook，也不產生 bitstream。建立完整 input 快照與 synthesis／routed DCP，避免舊專案設定污染比較。相同 flow／四個 threads，每輪都是新的 in-memory project，正常 `synth_design → opt_design → place_design → phys_opt_design -directive AggressiveFanoutOpt → route_design`。

### 2026-09-24：AggressiveFanoutOpt 實驗

實際指令位於 Tcl 中 `place_design` 之後、`route_design` 之前；`experiment.txt` 的 `Flow:` 只是紀錄，由同一支 Tcl 自動產生。兩處已同步，不能只改舊的 experiment.txt 就期待實驗策略改變。舊 run01／run02 不修改，必須重跑到新目錄。

只測 54 MHz：

```tcl
set dcim_sweep_root {C:/dcim_sweep/f54_aggressive_run01}
set dcim_sweep_frequencies {54}
set dcim_sweep_python {py -3}
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP/vivado/sweep_dcim_frequency.tcl}
```

腳本不增刪 `DONT_TOUCH`；它會複製當下 RTL。若已手動移除 `u_chip` 的屬性，此次就同時測到屬性與策略變更，不能將差異全部歸因於 AggressiveFanoutOpt。要單獨比較策略，需確認輸入 RTL 與基準一致；可查看新目錄的 `snapshot/fpga/dcim_master_chip_top.sv`。

測試已確認七組實際呼叫的 directive 與 experiment.txt 記錄一致；這是 Tcl mock 驗證，不代表 Vivado 時序已改善。

已有目錄會拒絕執行，不刪除或覆寫舊結果；若 run02 已存在，請改 run03。單輪失敗寫入 status.txt 後繼續其餘頻率。原始 RTL（包括使用者已改為 75 MHz 的時脈檔）不會被修改。

## 彙整及繪圖

Windows 先安裝 Python 與 matplotlib：

```bat
py -3 -m pip install matplotlib
```

腳本最後自動呼叫 Python。如果環境找不到 Python 或 matplotlib，Vivado 報告仍保留；可另行執行：

```bat
py -3 C:/dcim_sweep/run02/summarize_dcim_sweep.py C:/dcim_sweep/run02
```

也可從 Docker 對可見的同一結果資料夾執行 `python3 .../summarize_dcim_sweep.py <結果資料夾>`。不安裝 matplotlib 時加 `--no-plot` 仍可取得 CSV 與 Markdown。不要把 Docker 路徑直接貼到 Windows Vivado。

```text
run02/
  snapshot/                 原始 RTL／XDC 快照
  experiment.txt            Vivado 版本、器件、流程
  source_manifest.txt
  sweep_script.tcl          本次腳本快照
  summarize_dcim_sweep.py
  f45/ f50/ f51/ f52/ f53/ f54/ f55/
    configuration.txt       MMCM 設定
    status.txt              COMPLETE 或 ERROR＋錯誤原因
    synthesized.dcp
    routed.dcp
    post_synth/             面積與時序報告
    post_route/             同上＋DRC、methodology、route status
  summary.csv               兩個階段，失敗／缺資料也保留
  SUMMARY.md                post-route 表格
  lut_vs_mhz.png / .svg
  ff_vs_mhz.png / .svg
```

圖的横軸是 MHz，縱軸是 LUT／FF **數量**，不是 LUT 數除以 MHz；未通過／未完整完成用叉號，缺資料不捏造為 0。CSV 的 PASS 只代表 setup／hold slack 非負，不代表全設計 sign-off。

## 結果判讀與查看路徑

主要比較 **post-route** 的 LUT／FF、WNS、WHS；保留 post-synth 供分析最佳化差異。升頻未必單調增加面積：複製、重構、buffer、布局及 timing-driven optimization 均可能改變 LUT／FF；FF 相同也合理。

還必須檢查 pulse width、未限制路徑、DRC、route status、methodology。此流程沿用既有 XDC，不新增 false path 或放寬限制來隱藏失敗。按鍵／LED 的 I/O 時序警告需依板級非同步介面另行審核，不能將所有警告視為可忽略。

```tcl
open_checkpoint {C:/dcim_sweep/run02/f55/routed.dcp}
report_clocks
report_timing_summary -delay_type min_max -report_unconstrained
report_timing -delay_type max -max_paths 10
```

55 MHz 通過只代表所測點通過，不能宣布它是最高頻率。若臨界路徑屬 self test 或 master，也不能直接宣布是 macro 的速度上限。單次布局結果適合初步比較，研究結論建議另做重複實驗／更細頻率點，並保留相同工具版本與來源快照。

## 本次驗證範圍

`python3 CIM_CHIP/scripts/test_frequency_sweep.py`：以 Tcl interpreter＋Vivado API mock 執行真正掃頻腳本，檢查七組頻率副本、非 OOC、各輪隔離、錯誤後繼續、禁止覆寫與錯誤 clock guard；以合成測試報表檢查彙整／缺失值／失敗標記和出圖。測試資料不是 FPGA 實測數據。

Docker 無 Vivado，**本次尚未執行七組真實合成／布局繞線**。舊六組實測報告已整理；新增 51～54 MHz 的真實結果仍須在 Windows 執行後取得。

已通過上述七組腳本回歸；報表解析器沿用已驗證流程。這不等於完成七組真實掃頻。RTL 沒有變更，因此本次未重新執行功能模擬。

參考 AMD Vivado 2023.2：[Non-Project 流程與 DCP](https://docs.amd.com/r/2023.2-English/ug892-vivado-design-flows-overview/Opening-Design-Checkpoints-in-the-Vivado-IDE)、[synth_design](https://docs.amd.com/r/2023.2-English/ug835-vivado-tcl-commands/synth_design)。
