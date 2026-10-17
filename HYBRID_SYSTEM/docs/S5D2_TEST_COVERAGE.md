# S5-D2 定向覆蓋補強及Claude驗證任務

日期：2026-10-17。只修改TB/Makefile/文件，沒有修改正式RTL。目的是補足3f78310審查的雙完成契約及reset/error證據，不宣稱所有異常已覆蓋。

## 1. 新增案例

| plusarg | 注入／觸發點 | 必須檢查 |
|---|---|---|
| DELAY_READ_DONE | 真實分類開始後遮住path_read_done，8筆實際資料送完後再等12拍，補送一拍完成 | 等待期間busy保持，done/class_valid/start_ready/read_ready不得出現；補脈波後正常完成 |
| DELAY_ARG_VALID | 同上但遮住arg_valid，不修改class值 | read先完成不能提早done；補脈波後正常完成 |
| RESET_CLASSIFY | 真實分類已接收第3筆後共同reset | reset後10拍無交易/done/class_valid，完成旗標與Argmax count清零，再跑完整FULL |
| RESET_DCIM | Conv2的CIM時脈正緣實際觀察到mode_sel與output_en（至少一次SAMPLE），下一system negedge reset | 非僅activation載入reset；共同reset後重新載入五層權重並完整FULL通過 |
| CLASS_SOURCE_ERROR | 分類已接收3筆，從公開source_error輸入報錯 | LERR_SOURCE、無成功通知，FAILED鎖定5拍；共同reset後完整FULL |
| CLASS_READ_ERROR | 分類已接收3筆，force path_read_error模擬Reader失敗 | LERR_OPERATION、無成功通知，FAILED鎖定5拍；共同reset後完整FULL |

force僅用於完成／錯誤通知故障注入，不force FSM、RAM、MAC、分類值或計數器。DELAY案例把被遮住的真實完成事件延後補送，不能視為改變真實Reader延遲的常態模擬。兩種完成脈波在頂層相接，因此單獨controller TB無法證明兩條路徑；此處直接測真實top。

額外檢查：done時path_busy必須為0且PoT empty；以path_busy表示owner釋放，不依賴enum數字。殘留測試PASS加入DCIM_WEIGHT=0/1。

reset不清RAM，TB清除initialized標記、操作/權重/分類計數後重跑；已寫的RAM不是假設零。時間watchdog不重置，兩次FULL預設2000萬system clocks；慢CIM須提高S5D_MAX_CYCLES。
一次只能選一個新定向注入，避免多個force/reset相互遮蔽。一般RAW/COMMIT/Golden負測仍保留。

## 2. 執行方式

在HYBRID_SYSTEM目錄，先lint，然後執行定向測試。每種PIPE/POST只需build一次，六個scenario順序執行，失敗立即停止。等完成再查看log，不持續輪詢。

```bash
make lint-inference-tests
make test-inference-directed S5D_PIPE=0 S5D_POST=0 S5D_SEED=505
make test-inference-directed S5D_PIPE=0 S5D_POST=1 S5D_SEED=128
make test-shared-review
# S5-D2尚缺的PIPE=1正常全鏈證據：
make test-inference-top S5D_PIPE=1 S5D_POST=0 S5D_SEED=505
make test-inference-top S5D_PIPE=1 S5D_POST=1 S5D_SEED=128
```

時間有限可先只跑兩個完成契約：

```bash
make test-inference-directed S5D_CASES='DELAY_READ_DONE DELAY_ARG_VALID'
```

之後再跑其餘四個，不必重複全部。directed目標須同時找到注入PASS、分類PASS、FULL PASS，只有退出0不算驗收。
log：`build/inference_p<PIPE>_post<POST>/directed_<SCENARIO>_seed_<SEED>.log`。
正常test-inference-top另有S5D_TAG（預設normal），避免reset與一般run同seed覆蓋；不同時脈的directed測試請另外複製log或換BUILD_DIR，預設directed檔名不含時脈。

## 3. Claude必做的獨立效力檢查

在scratchpad拷貝，不修改正式RTL：

1. 重做M3：`classify_done=(arg_seen || arg_valid)`，執行DELAY_READ_DONE，預期非零退出並命中`S5D missing terminal did not block completion`。
2. 對稱突變：只等`read_seen || path_read_done`，執行DELAY_ARG_VALID，預期同一指定失敗。
3. 正常RTL兩案例均須完成完整FULL；不可只有mutation失敗、正常案例也失敗。

M3原先未被正常時序測試抓到，故此次不能以lint或一般FULL PASS替代以上mutation證據。

## 4. 請回傳

- HEAD/dirty範圍、工具版本，確認本次正式RTL diff為零（排除使用者既有空白／cell屬性）。
- 每案例PIPE/POST/seed、exit code、注入摘要、分類index/score、FULL/RAM摘要及log路徑。
- reset兩案例各確實觸發一次，恢復後input_requests=1、weights=5、ops=9、class reads/beats=8、RAM_checks=32040；這些計數不含被取消的run。
- error兩案例是否核對正確error_code及FAILED保持，再恢復完整推論。
- M3及對稱突變的最小diff和指定失敗訊息。
- 嚴重度排序的問題、最小修法；未跑項目明列，不以舊log冒充新TB證據。

## 5. 邊界

作者檢查：`make lint-inference-tests`通過（exit 0，Verilator 5.030，沿用既有warning例外），log `/tmp/s5d2-coverage-final-lint.log`；本次staged diff空白檢查通過。新增六個功能案例及mutation未執行，交Claude，不能據lint標PASS。

仍未覆蓋：CDC錯誤/weight-load backend錯誤注入、全鏈PoT滿反壓、多樣本準確率、全鏈分類平手、所有clock相位、Vivado/STA/BRAM/板測。RESET_DCIM是第一個SAMPLE後reset，不代表DCIM所有狀態reset都測過。完成通知force案例驗證契約，不能作為實體CDC證明。
