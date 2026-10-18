# Claude：S6 獨立驗證任務

作者尚未執行新測試、生成器、lint或Vivado，請實際驗證，勿把檔案完成視為PASS。先讀AGENTS.md、SINGLE_BUFFER_ARCHITECTURE.md的S6段與S6_BOARD_INTEGRATION.md。

## 範圍／靜態檢查

- 新增board/kws、tb/board、兩支kws_board_vectors Python與Makefile的S6入口。先回報HEAD、status及diff。保留使用者原有cell/clock/postprocess/文件修改。
- 確認真正kws_inference_top、單一RAM、共用PoT、PE/DCIM，沒有用中間golden替代結果。正常完整測試禁止force FSM、MAC、分類或記憶體結果。
- ROM應是sample6988、8064輸入+7564權重=15628bytes，填零至16384。獨立比對原軟體檔；不能packed ROM自對自己。
- layer0..4 K/channels=9/12、108/12、108/12、144/32、32/8；offset=8064、8172、9468、10764、15372。
- 查同步ROM延遲、反壓保持、metadata保存、最後一筆、非法命令、reset恢復；supervisor的單拍class_valid保存、timeout、終態及錯誤優先。
- 查非VERILATOR的真實MMCM分支、雙域reset；Tcl字串generic/mem路徑、正常top無OOC、CDC物件匹配與例外覆蓋。
- 發現問題回報證據與最小修法，不擅改正式RTL、commit/push或部署板子。突變僅scratchpad副本。

## 執行順序

在HYBRID_SYSTEM執行；完整輸出寫log，結束後看摘要，失敗才看上下文。生成一次後以-o避免多個make改寫資料，記錄manifest SHA256前後一致。不要同時編譯相同build目錄。

```bash
make generate-kws-board-vectors
make -o generate-kws-board-vectors test-kws-board-vectors
make lint-kws-board
make -o generate-kws-board-vectors test-kws-board-units
make -o generate-kws-board-vectors test-kws-board-core S6_PIPE=0 S6_POST=0
make -o generate-kws-board-vectors test-kws-board-core S6_PIPE=0 S6_POST=1
make -o generate-kws-board-vectors test-kws-board-negative S6_PIPE=0 S6_POST=1
make -o generate-kws-board-vectors test-kws-board-top
```

資源允許補PIPE=1兩種POST，未跑明確列未測。來源hash出錯不得跳過或改golden迎合RTL。

## 驗收內容

| 測試 | 應確認內容 |
|---|---|
| Python vectors | offset/padding/hash/分類；損壞byte或sample拒絕且不產生有效輸出 |
| source | 原始檔逐byte、stall保持、握手後metadata更換、四個非法請求、reset恢復；預期checks=23692/rejects=4，核對計數實際意義 |
| source負向 | `source byte mismatch base=8172`，不能是watchdog或編譯失敗 |
| self_test | 正確答案、engine/source error、timeout、done/class協定、錯誤答案、終態保持；預期successes=1/failures=7 |
| clock_reset | bounce、共同assert、各域posedge解除、恢復；只驗證行為時脈分支 |
| core | 8064輸入、7564權重、五個weight request、九個operation、每層commit地址/資料/順序、八筆分類讀取、6/183、完成後不重啟 |
| core負向 | 損壞Conv2 golden必須報`board commit mismatch op=3` |
| top | ready→busy→LED0101、終態保持、BTN0 reset後0000；不是實體MMCM驗證 |

九操作commit數=2016、21960、5400、4368、1008、576、144、32、8；輸入載入另8064。Conv patch-major必須轉成CHW地址。這是逐commit檢查，不是以前32040筆全RAM讀回，勿混稱。

獨立核對fc2 `[103,144,102,78,102,84,183,133]` 的argmax=6、score=183；不代表資料集準確率或FP32等價。建議額外做source位址/資料突變證明scoreboard有效。若補完整板級reset重跑或錯誤案例，標明是補測，不是既有覆蓋。

## Vivado與實體證據

有工具才依設計文件執行，沒有Windows Vivado明確列未測。不能用Tcl mock或Verilator代替：

- ROM/RAM的BRAM推導與初始化是否成功；總體及core/source/supervisor/clock的LUT/FF/BRAM/DSP/BUFG/MMCM。
- 125/53MHz report_clocks；setup/hold WNS/TNS/WHS/THS、unconstrained、最差起終點、logic/routing時間。
- pre_opt matched物件數、mailbox穩定契約、同步器、reset例外是否隱藏不安全釋放；report_cdc/exception/DRC/methodology逐項分類。
- 板測需另獲授權；LED0101、按鍵reset重啟、鎖存結果分開確認。

## 必須回傳

1. HEAD、工具版本、dirty範圍、manifest/hash、是否更改正式檔案。
2. 命令/PIPE/POST/exit/PASS摘要/log路徑表。
3. 實際input/weight/operation/commit/classification計數，預期與實際分列。
4. 負向失敗訊息和位置，不接受timeout冒充有效負測。
5. 問題依嚴重度：行號、原因、重現、最小修法。
6. 未測配置、樣本、MMCM實體、STA、CDC、BRAM、板測。
7. 分開判斷功能模擬可接受／可開始Vivado／可上板，勿以單項PASS推論全部完成。
