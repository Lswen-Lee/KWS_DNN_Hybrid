# 架構完成後再評估的最佳化清單

決定日期：2026-10-05。參考基準：S4 commit `268ec2a`。

## 1. 已確認的工作順序

使用者希望先完成架構，再評估FSM、介面與面積最佳化。本清單全部為**候選／暫緩／未實作**，不是後續整合時可自動套用的變更授權。

目前沿用已通過S1～S4功能模擬的介面與完成條件，繼續S5 DCIM backend、跨層整合及最終分類。不要為了少幾個狀態而同步重構已驗證的PE／Pool／記憶體路徑。
現階段沒有由前次審查證實必須先套用本清單才能繼續整合的阻礙。若後續發現正確性錯誤、介面不相容、實測資源超限或關鍵時序阻塞，另行提出最小必要修正與證據，經確認再提前處理；不因「暫緩最佳化」而保留已知錯誤。

可持續補註解、文件與新模組的清楚命名，但本次不連帶更名既有狀態／腳位或改RTL。

## 2. 候選項目

以下優先度是未來重新評估的起點，不是已確定的施工順序；屆時需重新檢查最新RTL與合成報告。

| ID／優先度 | 檔案／範圍 | 候選修改 | 預期目的／風險 | 必要驗證 |
|---|---|---|---|---|
| O01／1 | `rtl/integration/kws_activation_path.sv` | 合併pending與resident metadata；命令接受時保存新欄位並清valid，真正載入成功才設valid | RTL可少一套3+8+6=17-bit欄位；不保證實際省17個FF。不得保留失敗reload的有效狀態 | 成功／失敗reload、中途reset、命令後外部欄位變動、resident匹配 |
| O02／2 | Reader／Writer／Pool／PE控制器 | CONFIG數字phase改具名常數，保持原拍數 | 可讀性改善，不宣稱省面積 | lint及原回歸，phase順序與時序不變 |
| O03／3 | `pe_layer_controller.sv`、`kws_activation_path.sv`及其TB | 移除PE支路的writer_count／pw_count，因該支路固定WRITE_CHW | 介面清理；工具可能已消除，面積未必改變。不能刪Writer的cmd_count，LINEAR仍需要 | PE Conv／FC、Host／Pool LINEAR與獨立controller TB |
| O04／4 | `pool_transfer_controller.sv` | 合併RUN／DRAIN | 可能減少狀態及控制延遲；必須保留Reader、Writer各自done_seen | 奇數尾列／尾欄、Writer提早完成、最後commit、FAULT |
| O05／5 | `layer_controller.sv` | 刪COMPLETE，在ADVANCE最後操作直接done並回IDLE | 最後完成少一拍，改變done／busy時序；LUT/FF效益待量測 | op_done對應current_op、done單拍、start/read交界、錯誤優先 |
| O06／5 | `layer_controller.sv` | last_op由mode解碼，不另保存 | 消除語意重複；合成可能已簡化兩個常數 | FRONTEND／FC_TAIL，以及未來FULL模式不能沿用過時解碼 |
| O07／6 | `layer_controller.sv` | 將CHECK_RUN合併至IDLE的start握手 | 少一拍／狀態；加長接受命令的判斷路徑，錯誤通知時機改變 | 保存mode、非法mode／FULL拒絕、所有權與時序 |
| O08／6 | `pe_layer_controller.sv` | 在RUN完成時更新座標，合併NEXT_PATCH | 非最後patch可能少一拍；完成檢查與座標更新路徑變長 | Conv1全部patch、換列、最後patch、FC/replay、反壓 |
| O09／後評估 | `layer_controller.sv` | 合併FETCH_DESC／CHECK_DESC | 少一拍，但形成ROM→合法性判斷→FSM的路徑；目前建議保留暫存邊界 | ROM非法地址、backend檢查、配置保持、post-route timing |
| O10／7 | `feature_map_writer.sv`及上游契約 | 固定順序CHW地址產生，使用patch_offset與plane_stride遞增，取代每筆座標乘法 | 較值得量測的算術最佳化；會失去任意座標／反向channel的通用性，不是無條件等價改寫 | 先確認PE與未來DCIM輸出順序；保留通用版作基準，驗證分組尾端、地址／數值／commit與反壓 |
| O11／可讀性候選 | 命令設定介面 | 用struct整理PE設定欄位 | struct不減少實際資料位數，不宣稱省線或省LUT；更動所有实例及TB | 編譯相依、位寬、欄位連接與既有回歸 |
| O12／目前不推薦 | 多命令介面 | 合併成opcode＋payload共用命令 | 需解碼與多工器，少腳位不保證省面積；增加協定改動 | 若另行採用，需完整命令互斥、握手、錯誤與吞吐驗證 |

所有路徑相對於HYBRID_SYSTEM。表內僅列候選，不表示原設計有功能錯誤。

## 3. 不可為了精簡而直接刪除的語意

- 外部request握手與內部load命令握手不同；request accepted不等於資料已載完。
- WAIT_WRITER_READY保護Writer配置尚未完成的時間。
- Reader FIFO／在途計數保護同步RAM回應與反壓。
- resident_valid保護失敗載入與reset後無效權重。
- 接受資料與RAM commit不同；done必須等待實際完成。
- 擴位算術與範圍檢查不可先截斷，否則可能漏掉溢位／重疊。
- 跨層controller、單層patch controller與path owner各有不同責任，不因狀態多就合成一個巨型FSM。

## 4. 何時重新啟動評估

先完成的功能基準：

1. 真實DCIM backend與共享RAM／控制器完成整合，Conv2／Conv3逐層數值比對。
2. 串接完整模型與最終分類，保留逐層golden及異常／reset回歸；不以外部中間golden代替硬體計算。
3. 凍結一個可重現的基準commit，記錄軟體模型／量化／樣本、參數、測試命令與各層cycles。

接著建立相同頂層／板級環境的Vivado資源與時序基準，再挑實際占比高或關鍵路徑上的項目。若基準不能完成implementation，記錄失敗階段與原因，再針對阻礙做最小修改，不以沒有route結果的版本宣稱時序優勢。
不必等所有效能目標與板測完全達成才開始必要的收斂工作；但功能等價與比較基準須先清楚。

## 5. 每項修改的驗收

- 一次一項或一個明確不可拆的修改，保留修改前commit；不混合換PE管線／頻率／時脈拓撲。
- 先跑元件TB、S3、S4真實軟體資料；完整系統完成後還需全層回歸。不得刪失敗案例來使測試通過。
- 狀態合併若改變cycles，更新時序契約與測試；不可宣稱逐拍完全等價。
- 同裝置、top、頻率／XDC、參數、工具版本、策略及相同工作負載，比較LUT／FF／BRAM／DSP、WNS／TNS與hold、分層資源及每層cycles。
- 至少區分：可讀性改善、模擬延遲改善、實測面積改善、實測時序改善；不能互相代稱。
- 尚未量測任何本清單候選的修改後面積節省率。若收益不明顯或時序／可維護性變差，可不採用。

本次僅新增決策紀錄及基準連結，未改RTL／TB／Makefile，也未重新執行模擬或Vivado。
