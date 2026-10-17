# Claude驗證任務：S5-D2分類整合

先讀AGENTS.md、SINGLE_BUFFER_ARCHITECTURE.md最新段落、S5D2_ARGMAX.md，再核對提交diff及其中的RTL/TB。記錄HEAD及原有dirty修改；不修改正式RTL，不重跑未變更的所有歷史單測。

## 必查設計

1. FULL/FC_TAIL等FC2最後commit後才讀RAM0..7；FRONTEND沒有分類。
2. 原Reader共用而非新增RAM；host read不能於分類間隙被接受、不能看到內部read完成。
3. Argmax命令前clear，每次只吃8筆；done與arg_valid不同拍時兩旗標正確保存。class_valid與成功done同拍；reset/error不出舊class。
4. TB只用真實八筆UINT8求期望類別，不把原FP32 argmax當作必然相同；同值選最早index。
5. class輸出沒有ready：屬單拍通知，不聲稱可承受分類輸出反壓。

## 必跑（在HYBRID_SYSTEM，分別存log，完成再看摘要）

```bash
make lint-inference-top lint-inference-tests
make test-layer-controller test-argmax
make test-shared-review
make test-s4-software
make test-inference-top S5D_PIPE=0 S5D_POST=0 S5D_SEED=505
make test-inference-top S5D_PIPE=0 S5D_POST=1 S5D_SEED=128 S5D_EXTRA_ARGS=+RESET_BEFORE_FULL
make test-inference-class-negative S5D_PIPE=0 S5D_POST=0
```

預期controller summary 3成功、19操作、10錯誤。FULL除原9操作/5權重/32040 RAM checks，另須classification reads=8、beats=8，index與score正確。
RESET案例須同時出現reset abort摘要及之後FULL PASS。負測須命中特定classification mismatch，不能將watchdog當通過。
可補PIPE=1兩POST及CLASSIFY_WAIT中共同reset的scratchpad案例；若未做須列為未覆蓋。
作者已跑的短單測可先查log再決定獨立重跑，不重複跑所有舊全層。

## 回傳格式

- HEAD、dirty範圍、工具版本、讀取與執行清單。
- 每命令exit code、PIPE/POST/seed/clock/reset模式、PASS摘要及log路徑。
- class_index、class_score、8筆讀取/輸出及done時機是否成立；FRONTEND是否無class_valid。
- 正式DCIM_WEIGHT殘留案例及reset後完整恢復結果。
- 問題嚴重度、檔案行號、重現條件、最小修法；突變僅在scratchpad並附diff。
- 未測項目與能否進入板級整合的結論；不得將功能PASS視為125/53MHz STA通過。

請不要自行commit/push或更改使用者無關檔案。
