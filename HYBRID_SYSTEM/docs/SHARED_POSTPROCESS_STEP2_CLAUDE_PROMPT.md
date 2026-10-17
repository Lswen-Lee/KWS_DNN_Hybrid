# Claude第二步獨立審查

## 2026-10-17定向複驗（優先）

本次只補審查後防護，不需無差別重跑全套。先核對`idle_residue`是否同時控制idle_clean與FAULT，避免殘留與命令同拍被子模組接受。確認DCIM cmd_count=0、非法weight load仍使該端resident失效且文件清楚。新的檢查命令：

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM
make test-shared-review lint-activation-path > /tmp/claude_shared_review.log 2>&1
```

完成後才讀摘要。預期兩種PoT各18個殘留／命令案例、FAULT鎖定、reset後FC2八筆，以及RAW/COMMIT各一種指定訊息負測。檢查force只注入非法valid/empty，沒有force狀態或乘加結果；必要時在scratchpad移除ready gate，確認TB能抓到同拍握手漏洞。此目標不測完整Conv2/3，也不測兩筆合法命令的優先仲裁；原全層結果與此次定向結果請分開報告。若已有相同原始碼的可信log，先閱讀再決定是否重跑。

下方保留完整Step 2閱讀背景，無需每次重讀所有檔案。

請只讀與測試，不修改、不commit、不push。倉庫：`/home/LAB505/projects/KWS/KWS_DNN_Hybrid`。

先讀AGENTS.md與git status；使用者另有cell屬性、板級頻率、argmax、PoT空白與文件修改，不能混入本次責任範圍。

閱讀順序：

1. HYBRID_SYSTEM/docs/SINGLE_BUFFER_ARCHITECTURE.md
2. SHARED_POSTPROCESS_STEP1.md（F1～F3修正commit4538316）
3. SHARED_POSTPROCESS_STEP2.md（架構、介面、限制與驗證）
4. rtl/integration/kws_activation_path.sv、rtl/control/pe_layer_controller.sv、dcim_layer_controller.sv
5. rtl/integration/pe_memory_engine.sv、kws_dcim_subsystem.sv、rtl/datapath/pot_result_stream.sv
6. tb/integration/tb_kws_shared_postprocess.sv及Makefile；既有controller／軟體TB

除了第一行倉庫路徑，其餘相對HYBRID_SYSTEM或docs目錄。

請獨立確認：

- 只有一個PoT實例？PE/DCIM metadata、raw ready/valid及量化結果路由是否一致？
- 是否有runtime_bad→raw gate→backend ready形成組合迴圈？lint與閱讀兩者都檢查。
- DCIM done早於PoT排空時會等待？最後Writer commit前不釋放owner？
- PE/DCIM權重resident獨立？weight_backend在命令握手後已保存？非法DCIMK/channels不觸發load？
- busy期間命令與錯誤時的責任是否清楚？有無未選中來源阻塞造成後續錯誤的風險？
- Reset是否清在途PoT/CDC/控制器而非單域reset？未測邊界需明確列出。
- 真實軟體資料是否只作輸入與scoreboard，不直接寫中間結果到DUT？Pool3到Conv3是否真的接硬體值？
- Golden負測是否要求指定訊息，而非任意失敗就PASS？
- S4 FULL仍拒絕；不得把手動TB順序當作完整layer scheduler已實現。

依設計文件的命令執行，輸出重導log、完成才讀。結果請列：閱讀與執行範圍、PASS/FAIL、具體檔案行號／重現／最小修正、未覆蓋風險，以及能否進入S5-D完整排程。不要僅因模擬通過即判斷實體CDC或頻率達標。
