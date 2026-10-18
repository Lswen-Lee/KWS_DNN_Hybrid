# Claude Writer管線獨立驗收

先讀AGENTS.md及FEATURE_MAP_WRITER_PIPELINE.md；保留使用者dirty檔案，不修改正式RTL、commit/push。作者本次未執行功能測試，請勿沿用舊PASS。僅Writer RTL改動，上層未改；tb_kws_inference_top只增加PERF monitor。

## 執行

在HYBRID_SYSTEM中，先短測；輸出導向log，完成後看摘要，失敗再看上下文：

```bash
make lint-feature-map-writer test-feature-map-writer test-writer-pipeline
make test-activation-path lint-activation-path
make generate-activation-path-vectors
make -o generate-activation-path-vectors test-pe-external-post
make -o generate-activation-path-vectors test-shared-postprocess
make -o generate-activation-path-vectors test-inference-top S5D_PIPE=1 S5D_POST=1 S5D_SEED=128
```

再補PIPE0/POST0正常FULL與reset/error定向回歸；依時間分批，未跑明確列未測。避免同一build目錄並行編譯及重產golden。新短TB負向由make內建，須匹配PIPELINE_SCOREBOARD，不接受watchdog替代。

## 靜態與動態檢查

1. data/coordinate/valid對齊：E0握手、E5commit，正常最後commit後下一拍done。
2. 保持LINEAR/任意CHW、不新增去重，32-bit中間地址後檢查再截位；命令metadata排空前不變。
3. 首/中/末非法筆後所有較晚交易取消，但較早pending可commit；偵測同拍握手也取消。檢查accepted_count新語意。
4. 五級reset取消、無殘留wr_en、共同RAM reset、不假done；正常滿速輸入每拍commit。
5. 上層等待writer_done沒有固定延遲假設，pool無ready輸出仍安全。
6. 補至少data少延遲一級或done提前的scratchpad突變，證明TB有效，不修改正式碼。
7. 舊WriterTB全RAM讀回應保留，不用只看分類取代逐層比較。

## 延遲回傳

收集`PERF weight`、`PERF operation`及`PERF inference`；start到done不含後面的debug scan。驗證分項加總與remainder，標明來源停頓、時脈、配置；重置/負向run不要混入正常推論數字。operations包含Reader、後處理、Writer與該層計算，不是純MAC。

## Vivado（具備環境才執行）

相同PIPE1/POST1、125/53MHz與約束重新synth/route（需reset舊runs以免沿用checkpoint）。比較WNS/TNS、owner→Writer路徑是否切開、各乘法/加法級新最差路徑、LUT/FF/DSP/BRAM。不要以false_path或multicycle掩蓋。reset/CDC警告不在本次修改範圍，仍須單獨處理，不可宣稱全系統已安全。

## 回傳格式

- HEAD、diff範圍、工具版本、是否動正式檔案。
- 指令/配置/exit/摘要/log路徑；實際成功/錯誤/commit計數。
- 負向與突變的確切失敗訊息。
- PERF表：含載入端到端、各層operation、權重、輸入、其餘；cycles與ms。
- 問題行號、重現、最小修正；未測項目。
- 分開結論：功能是否通過／時序是否通過／是否可上板。
