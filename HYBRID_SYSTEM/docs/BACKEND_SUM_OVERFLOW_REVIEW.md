# Backend 加總溢位檢查移除：設計與 Claude 驗證交接

## 範圍與契約

僅修改 `rtl/dcim_adapter/kws_dcim_backend.sv` 的條件：

```systemverilog
// 原本
if (correction_overflow || extended_acc[32] != extended_acc[31])
// 現在
if (correction_overflow)
```

保留33-bit extended_acc加法、低32-bit寫回、offset correction、PoT輸入/輸出FF、CDC、順序檢查、所有介面與FSM。正常操作cycle不變。沒有修改TB，亦未執行模擬、lint、Tcl mock、Vivado或板測；本次只做diff與文件靜態檢查。

合法模型：A為UINT8、W為signed INT8、K=108，ACC=Σ(A−128)W。任意部分和絕對值≤108×128×128=1,769,472；第四組20項padding的A=128，貢獻0。需要正確清除、每組只累加一次、合法correction結果。非法資料或控制錯誤造成超界時，低32-bit截斷，不再由加總溢位觸發FAULT。correction_overflow仍觸發FAULT並清除weights_ready。

原路徑：pair_index→partial_acc mux→加法→加總溢位→控制/tile CE。
新路徑：加法仍寫入partial_acc D，但tile CE不再由該加總的overflow控制。
可能仍有加法D、reader位址或其他失敗路徑；不承諾125MHz通過。

## Vivado 2023.2（Windows）

先關閉目前專案，確認既有board vectors可用；下列目錄必須不存在：

```tcl
set backend_no_sum_root {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/build/kws_backend_no_sum_run01}
set order_jobs 4
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/board/kws/run_backend_no_sum_overflow.tcl}
```

正常非OOC、PIPE=1、POST=1、CHECK_RESULT_ORDER=1、125/53MHz，自動synthesis與route並產報告，不產bitstream。報告在`<backend_no_sum_root>/checked/reports/order`，摘要在根目錄summary.csv。沿用既有run_order流程，包括防覆寫與Failed Timing仍產報告處理。腳本讀取live RTL，執行期間不要修改來源；保存commit與dirty diff。名稱checked表示順序檢查開啟，不代表加總溢位檢查開啟。

比較基準kws_pot_input_run01：WNS=-0.792ns、TNS=-149.289ns、660 setup失敗端點、WHS=+0.053ns、LUT=27006、FF=21681。追蹤tile CE、partial_acc D、reader/start_address D，並核對CDC/DRC與未約束路徑。

## 可直接交給 Claude 的任務

請閱讀AGENTS.md、本文件、backend RTL、dcim_u8_offset_correction.sv、tb_kws_dcim_backend.sv與相關Makefile。不覆寫既有使用者修改，不修改正式RTL；若要補測，放scratchpad或先列出正式TB建議。

1. 核對功能diff只有移除跨group加總溢位條件；介面、正常FSM/cycle、其他錯誤防護未改。獨立驗算K=108上下界及padding規則。
2. 執行下列命令，保存各自log與exit；不要僅以PASS文字代替exit狀態。完整測資只生成一次，不平行改寫golden。

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM
make lint-dcim-backend
make test-dcim-backend
make lint-order-board
make test-pot-stream
make test-shared-review
make test-inference-top S5D_PIPE=1 S5D_POST=1 S5D_CHECK_ORDER=1
make test-inference-negative S5D_PIPE=1 S5D_POST=1 S5D_CHECK_ORDER=1
```

3. 補合法極值：全部A=0/W=-128預期1,769,472；全部A=255/W=-128預期-1,755,648；正負混合、A=128全零。經真實四group運算，各filter逐筆比對，檢查partial sum範圍及無error。不可force乘加結果或FSM來取代運算。
4. 核對correction_overflow仍可FAULT且weights_ready清除。若需要注入錯誤，只在明確記錄的模組邊界注入，與合法數值測試分開。原TB若期待「加總overflow必FAULT」，標示為契約已更改，不可假稱通過。
5. extended_acc[32]現在不再被使用，strict lint可能報UNUSEDSIGNAL。若出現，原樣回報位置；不要全面關閉警告或擅改RTL，區分lint失敗與功能錯誤，功能模擬仍可按既有目標執行。
6. 正常FULL應分類index=6/score=183、RAM_checks=32040；負向測試需命中特定golden mismatch而非timeout。確認新PoT pipeline的tag/valid對齊、反壓及reset未受影響。

回傳：HEAD與dirty範圍、工具版本、逐命令exit/配置/log、極值刺激及實際結果、負測失敗原因、lint警告、是否有正常cycle變化、問題嚴重度與最小修改建議、未覆蓋項目。不要commit/push；模擬PASS不代表STA通過。
