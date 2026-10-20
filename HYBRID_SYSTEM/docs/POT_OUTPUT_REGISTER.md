# 共用 PoT 輸出暫存級（2026-10-19）

## 2026-10-20更新：scale查表與RNE輸入切級

本節優先於下方2026-10-19歷史範圍。直接修改現有`pot_result_stream`的POST=1分支，不改quantizer內部算式，也不改backend。POST=0保持原狀。

```text
layer/channel → scale ROM → shift_q ─┐
INT32 ───────────────────→ ACC_q ───┼→ 原RNE三級 → FIFO → 輸出FF
error/last/channel/ReLU ──→ tag_q ───┘
                       accept時一起保存
```

新增32-bit ACC、5-bit k、8-bit tag、1-bit valid。非法ROM查詢與in_error在accept時合併保存，tag_q下一拍進入原三段tag pipeline，與quantizer輸出對齊。只有valid reset，payload無效時不使用。不增加外部port或FSM；CHECK_RESULT_ORDER仍預設1。

E0接受輸入：E0後輸入級有效；E1原quantizer Stage1；E2 Stage2；E3飽和輸出；E4入FIFO；E5輸出FF有效，下游最早E6握手。POST=0仍E0入FIFO、E1輸出FF、最早E2握手。新POST=1比輸出FF版再增加一拍，正常連續資料仍II=1。

reserved在外部accept增加、外部pop減少，已包含新輸入級，不需要再加計數或擴大容量。FIFO+output+所有在途總數最多8；reset取消input_valid及原在途valid。不直接延後shift_amount而漏掉ACC/tag。

新增合成入口`board/kws/run_pot_input_pipeline.tcl`（操作見統一指南），兩端FF都存在。現有最差emit_index→ROM→RNE路徑在RTL被切開；RNE自身及backend/PE CE路徑仍可能違反，沒有125MHz保證。

TB增加首筆精確延遲檢查（POST=1 E5，POST=0 E1），保留獨立數值、tag、反壓、reset、容量及64筆無bubble測試。全鏈及Vivado需重新執行，不能沿用輸出級版本的結果。Claude請依下方既有命令重跑，特別核對新增valid與tag的同拍關係。

本版實測：`make test-pot-stream lint-order-board` exit 0，POST=0/1各833筆比對通過，同拍輸入輸出分別782/778次，full_pop各41次；首筆延遲、連續64筆、反壓及reset檢查通過。板級lint沿用專案warning豁免。日誌`/tmp/pot-input-pipeline.log`。首次測試因新增延遲等待時TB未撤掉in_valid而重複送入資料，修正TB單筆握手後重跑上述完整命令通過，未放寬scoreboard或timeout。

`python3 board/kws/test_order_experiment_tcl.py` exit 0，底層Tcl mock的成功、Failed Timing仍產報告、合成失敗與防覆寫案例通過（`/tmp/pot-input-tcl.log`）；新薄入口已靜態核對，尚未執行Windows Vivado。完整推論與共享切換回歸留給Claude，不宣稱本版全鏈或STA已通過。

## 範圍

只修改pot_result_stream與其TB，新增獨立合成入口；PE/DCIM controller、backend加法、PoT數學公式、量化pipeline級數、CDC與時脈不變。合成入口強制checked（CHECK_RESULT_ORDER=1），PIPE=1/POST=1，125/53MHz。不刪除錯誤防護。

```text
INT32 → PoT/ReLU → FIFO → 15-bit payload FF + valid FF → controller → Writer
                           ↑ 新增時序邊界
```

payload為{error,last,channel[4:0],uint8[7:0]}。不reset payload，僅reset valid與計數；valid=0時資料無意義。

## 握手與容量

- accept=in_valid&&in_ready：接受新結果。
- fifo_take=count!=0 && (!output_valid_q || out_ready)：內部搬移，rst時禁止。
- pop=out_valid&&out_ready：外部真正消費。
- FIFO count隨fifo_push/fifo_take增減；rd_ptr只在fifo_take前進。
- reserved隨accept/pop增減，POST=0/1共用；總容量仍為8筆，含量化在途、FIFO與輸出級。
- in_ready=reserved<8，滿時即使同拍pop仍不旁路ready（保持原契約）。
- empty=reserved==0；不能只看FIFO count。reset時empty/out_valid/in_ready為0。

| 輸出級 | ready | FIFO非空 | 上升緣動作 |
|---|---|---|---|
| 空 | 任意 | 是 | 載入payload並設valid |
| 有資料 | 0 | 任意 | payload及valid保持 |
| 有資料 | 1 | 是 | 下游接收舊值，同拍補入下一筆 |
| 有資料 | 1 | 否 | 清valid |

沒有新增FSM，輸出級只有empty/valid兩種占用狀態。首筆延遲相對原FIFO輸出增加一拍，持續供應且下游ready時可維持II=1；不保證上游停頓或FIFO空時沒有空拍。Controller ports及狀態不變，但整體完成可能延後。

## 預期時序效果與限制

原rd_ptr→FIFO讀取→metadata比較→runtime_bad→backend CE被FF分隔。下游ready仍影響output FF的更新條件，其他控制、backend加法溢位路徑仍可能違反。不能保證125MHz通過；實際FF/LUT由合成決定。POST=0另外需要整體reserved計數，不能單以新增16bits估算全部面積。

## 合成

關閉目前專案，在Vivado Tcl Console執行：

```tcl
set pot_output_root {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/build/kws_pot_output_run01}
set order_jobs 4
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/board/kws/run_pot_output_register.tcl}
```

呼叫現有完整run_order_experiment流程，僅跑checked，不覆寫舊目錄。報告位於`<pot_output_root>/checked/reports/order`，摘要為根目錄summary.csv。已包含Complete, Failed Timing狀態修正。既有board vectors必須存在。來源是live RTL，執行期間不要修改。

## 驗證與Claude交接

```bash
make test-pot-stream
make lint-order-board
make test-shared-review
make test-inference-top S5D_PIPE=1 S5D_POST=1 S5D_CHECK_ORDER=1
make test-inference-negative S5D_PIPE=1 S5D_POST=1 S5D_CHECK_ORDER=1
```

單測POST=0/1使用獨立RNE/scale參考模型，保留768筆、256 ROM位址、error/tag、長停頓、滿容量、reset與在途取消。新增：首筆不可直接旁路output FF；FIFO已空但output持有最後一筆時empty必須為0；64筆連續串流首筆後逐拍檢查無bubble。持續逐拍檢查最多8筆、ready容量規則、停頓payload穩定、順序/數值完全相同。

請Claude審查：reserved只由外部accept/pop更新、內部搬移不能提早釋放容量、同拍pop/take及push/take不丟資料、reset後不殘留、metadata和數值同步。補跑shared-review與全鏈golden，回傳版本、命令、exit、配置、log、分類6/183及RAM_checks=32040，負測需命中特定錯誤而非timeout。不要force FSM或以golden替代中間運算。

Windows Vivado、完整推論與共享切換回歸尚待執行；不得把單測/lint當作完整系統或STA通過。

### 2026-10-19輸出級版本實測（非新增輸入級的結果）

Verilator 5.030：`make test-pot-stream`兩版exit 0，各833筆比對（768主測+64連續+1最後停頓），POST=0/1分別有782/779次同拍輸入輸出，full_pop各41次。`make lint-order-board`兩配置exit 0（沿用專案warning豁免）。日誌：`/tmp/pot-output-final-test.log`、`/tmp/pot-output-register.log`。新的Tcl薄入口只靜態檢查，底層run_order流程已有mock回歸；本次未執行Windows Vivado。
