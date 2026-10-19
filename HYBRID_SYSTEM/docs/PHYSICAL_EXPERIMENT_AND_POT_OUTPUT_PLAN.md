# 不改RTL的實體實驗與PoT輸出邊界規劃

## 本次範圍

新增 `board/kws/run_physical_experiment.tcl`。沒有修改RTL、XDC、pre_opt或reset例外；PoT output register僅規劃，尚未實作。未執行Vivado，不能宣稱directive或路徑在使用者環境已實測通過。

目前基準：Writer管線版routed WNS=-0.918ns、TNS=-351.075ns、1036失敗端點，53MHz CIM WNS=+0.329ns。主要路徑為PoT FIFO讀出→runtime_bad控制→backend CE；另有weight_sum及量化器第一級。

## 實體實驗

新專案只合成一次，獨立implementation runs共用同一synth_1。預設baseline/fanout：唯一策略差異是post-place phys_opt directive，方便比較。baseline不是承諾重現上次每一位元相同的布局，而是本次受控基準。

| run | opt/place/route | post-place phys_opt |
|---|---|---|
| impl_baseline | Default | Default，明確啟用 |
| impl_fanout | Default | AggressiveFanoutOpt |
| impl_explore（可選） | Explore | Explore |

Explore是多參數實驗，不把改善全部歸因於fanout。沒有更改DONT_TOUCH、沒有降低時脈、沒有新增false_path、沒有啟用OOC或產生bitstream。既有DONT_TOUCH可能限制最佳化能力，保留以維持比較條件。

Vivado先關閉目前專案，在Tcl Console貼：

```tcl
set kws_destination {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/build/kws_phys_run01}
set px_jobs 4
set px_variants {baseline fanout}
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/board/kws/run_physical_experiment.tcl}
```

選擇Explore時改成 `{baseline fanout explore}`。目的目錄已存在則拒絕，不自動覆寫；重做選run02。必須已有kws_board_vectors，使用與原基準相同的資料。來源是live RTL，執行期間不要改RTL/ROM/約束。腳本會阻塞等待，每次完成後顯示run狀態；錯誤時看新專案的 `.runs/<run>/runme.log`，不能直接略過CDC hook錯誤。

報告在新專案 `reports/baseline`、`reports/fanout`，各有routed.dcp、setup100條、hold、clock、CDC、DRC、methodology、exceptions及資源報告。失敗不覆蓋原先writer_pipeline專案。

驗收比較：WNS/TNS/失敗端點、WHS/THS、LUT/FF/BRAM/DSP、最差路徑類別及logic/routing占比。route完成不等於時序通過。reset CDC-7/10仍需獨立處理；即使WNS正，也不能直接上板。回傳experiment.txt、兩組reports及runme.log。

參考AMD2023.2：[phys_opt_design](https://docs.amd.com/r/2023.2-English/ug904-vivado-implementation/phys_opt_design)、[opt/place directives](https://docs.amd.com/r/2023.2-English/ug904-vivado-implementation/Directives-Used-by-opt_design-and-place_design-in-Implementation-Strategies)。

## PoT輸出暫存（僅規劃）

```text
目前：quantizer → FIFO[8]非同步讀 → metadata檢查 → controller gate
建議：quantizer → FIFO[8]非同步讀 → output FF → metadata檢查 → controller gate
```

不增加新FSM，使用一筆15-bit payload FF與valid FF，payload為data8/channel5/last1/error1。讀FIFO到FF是內部搬移，不是下游消費。對兩種POSTPROCESS_PIPELINED配置都用同一輸出邊界。

### 握手與計數契約

```text
out_fire = output_valid && out_ready && !rst
slot_available = !output_valid || out_ready
fifo_to_output = fifo_count != 0 && slot_available && !rst
```

- fifo_to_output時整筆metadata/data存FF，rd_ptr前進。
- 若out_fire且fifo有下一筆，同一拍舊資料消費、新資料替換，連續每拍一筆。
- valid且!ready時FF保持，不能只保持data而變更channel/last。
- 無可搬移資料但out_fire時清output_valid；不從fifo_push組合旁路到輸出。
- fifo_count更新依 `{fifo_push,fifo_to_output}`，不是out_fire。
- 保留外部總容量8筆：`outstanding = quantizer在途 + fifo_count + output_valid`，依 `{accept,out_fire}`增減；內部搬移不改outstanding。
- POST=1沿用reserved概念但涵蓋output FF；POST=0也須納入output FF，可統一outstanding計數以簡化規格。`in_ready=!rst && outstanding<8`，不依賴out_ready。滿8時即使同拍pop仍下一拍恢復接受，保留原本保守行為。
- `empty=!rst && outstanding==0`；output_valid=1時絕不可empty，避免owner切換舊資料污染。
- reset清valid、count、ptr、outstanding與quantizer有效狀態；payload不必reset。

新增FF雖有物理儲存空間，外部容量仍定義8而不是9。沒有bypass時第一筆多一個搬移邊緣；連續有資料時吞吐量仍II=1。若FIFO原本空且同拍push，下一拍才搬至FF，是刻意且可驗證的bubble。

### 預計修改檔案

| 檔案 | 工作 |
|---|---|
| rtl/datapath/pot_result_stream.sv | output payload/valid、fifo_to_output、消費計數、empty |
| PoT既有單元TB及新定向TB | 停頓保持、滿/空、同拍替換、容量8、reset、metadata對齊、兩配置 |
| 共用後處理／PE/DCIM整合TB | owner切換排空、非法metadata仍被攔截、無丟失重複 |
| Makefile與文件 | 新測試入口與延遲契約 |

上層ports預期不變；controller先不修改runtime_bad語意。禁止直接延後錯誤旗標讓非法資料先握手。PoT檔目前有使用者空白修改，未來實作須保留。

驗證：outstanding等於參考queue長度；accept加入/out_fire移出；每筆逐一比對UINT8與metadata；8筆滿停止輸入、FIFO→FF不釋放容量、最後一筆停住empty必為0；同拍消費/補位不中斷；reset在quantizer/FIFO/output各有資料時恢復；負向破壞tag或empty必須被抓到。最後全段軟體golden回歸及route比較，不能只看class相同。

輸出FF主要切開FIFO讀出與控制鏈，不保證剩下runtime_bad→backend路徑必定通過；weight_sum與PoT輸入RNE長路徑也不會因此自動消失。

## Pipeline與序列式的區別

Writer五級是真pipeline，各級有獨立FF，A在S2時B可在S1、C可在S0；E0接收→E5 commit不代表只能每六拍接收一次，II=1。CONFIG雖是三拍序列設定，只在命令開頭執行。PoT POST=1的量化器同樣可同時處理多筆；POST=0用組合量化後FIFO。DCIM pin master則仍有逐bit-plane的多週期序列協定；全系統並非所有部分都每拍產生一個結果。
