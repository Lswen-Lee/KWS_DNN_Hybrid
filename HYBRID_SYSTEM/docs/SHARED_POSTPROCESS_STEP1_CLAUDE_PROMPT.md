# Claude獨立審查prompt

請在 `/home/LAB505/projects/KWS/KWS_DNN_Hybrid` 獨立審查「共用後處理第一步：PE raw engine＋外置PoT」。只讀與測試，不修改、不commit、不push。先看git status與本次commit差異，不覆蓋其他未提交工作。

閱讀順序：

1. AGENTS.md、HYBRID_SYSTEM/docs/SINGLE_BUFFER_ARCHITECTURE.md。
2. HYBRID_SYSTEM/docs/SHARED_POSTPROCESS_STEP1.md。
3. rtl/integration/kws_activation_path.sv、rtl/control/pe_layer_controller.sv。
4. rtl/integration/pe_memory_engine.sv、pe_pot_engine.sv、rtl/datapath/pot_result_stream.sv。
5. tb/control/tb_pe_layer_controller.sv、tb/datapath/tb_pot_result_stream.sv、tb/integration/tb_pe_conv1_pool_memory.sv及Makefile（以上相對HYBRID_SYSTEM）。

確認以下問題：

- path是否真的只例化一份外置PoT，raw PE明確設zp128？是否保持Host/Pool/PE互斥？
- raw done與quantized output是否分開計算？pipeline未排空是否可能更新patch或釋放owner？
- empty是否涵蓋reserved在途資料，不只是out_valid？reset契約是否一致？
- 缺少結果、超量、錯誤tag、replay、fault是否仍被偵測？禁止把無限等待誤稱錯誤已被處理。
- raw valid與ready的gate是否一致，有無組合迴圈？停止流量後是否有舊結果洩漏？
- FC1的last=11/23/31是否仍正確？layer/ReLU metadata是否保持？
- TB是否使用真實端點、獨立golden、有效覆蓋計數，而非force狀態假造成功？reset案例是否在目標階段真正發生？
- 舊pe_pot_engine是否保持相容？本次尚未接DCIM共用，不應聲稱第二步或全段完成。

執行：

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM
make test-pe-external-post > /tmp/claude_external_post.log 2>&1
make test-pot-stream test-pot-engine > /tmp/claude_post_units.log 2>&1
make test-s4-software lint-s4 lint-pe-layer-controller > /tmp/claude_external_s4.log 2>&1
```

等待每組完成再讀log。請回覆閱讀範圍、實際命令與結果、依嚴重度排序的findings（檔案行號/重現/最小修正）、未覆蓋風險，以及是否能進入DCIM共享接入。無確定錯誤時請明確說明，不把模擬通過視為實體時序通過。

測試使用當時工作樹；cell屬性、board、argmax及部分文件另有使用者修改，pot_result_stream原已有兩處空白變動，請區分本次提交，不假設乾淨checkout與工作樹完全相同。
