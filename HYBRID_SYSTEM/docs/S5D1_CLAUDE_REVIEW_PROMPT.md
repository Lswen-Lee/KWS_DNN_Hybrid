# 給Claude：S5-D1獨立驗證任務

請審查本次FULL推論排程整合，先只讀與驗證，不修改正式RTL，不替作者補寫PASS。
目標：一張真實UINT8 input經九操作，PE負責Conv1/FC1/FC2、DCIM負責Conv2/3，唯一PoT及單一RAM，FC2八筆提交後done。Argmax不在此步。

## 1. 先固定版本及閱讀順序

1. `git rev-parse HEAD`、`git status --short`、`git diff`；記錄未提交變更。不要覆寫既有cell/clock/board/argmax/PoT等使用者修改。
2. `AGENTS.md`、`HYBRID_SYSTEM/docs/SINGLE_BUFFER_ARCHITECTURE.md`最新段落。
3. `HYBRID_SYSTEM/docs/S5D1_FULL_INFERENCE.md`：本次scope、接口、15-state流程及驗收表。
4. RTL：`rtl/control/layer_controller.sv`、`layer_descriptor_rom.sv`、`rtl/integration/kws_inference_top.sv`。
5. 接線核對：`kws_activation_path.sv`的weight_backend、cfg保存、ready/owner、DCIM與PE done/empty契約；`kws_dcim_subsystem.sv`共同reset契約。
6. TB：`tb/control/tb_layer_controller.sv`、`tb/integration/tb_kws_inference_top.sv`、`tb_kws_s4_software.sv`；Makefile新增目標。

除AGENTS外，上述RTL/TB路徑相對HYBRID_SYSTEM。請以真實source為準，不只閱讀作者文件。

## 2. 靜態檢查項目

- FULL第一個op=0、最後=8；舊FRONTEND=0..2、FC_TAIL=7..8仍有效，保留值3拒絕。
- PE/DCIM/Pool的valid、ready、done/error都選同backend；無隱性「非Pool即PE」。
- descriptor從FETCH保存至operation完成；weight layer_id/K/channels/backend不在load途中改變。
- 兩次DCIM weight load都實際經backend→CDC→master→chip，不透過readmem或Golden跳過寫入。
- 權重數為108/1296/1296/4608/256；不向DCIM來源索取padding。
- 頂層clk_cim/rst_cim全部實例有接，reset共同事件各域解除；不將功能模擬當成CDC STA。
- op_done/全段done不早於最後commit及PoT排空；層間idle仍禁止host read。
- TB參考位址／資料不由DUT結果反推，無中間golden回灌；單位TB stub與全鏈真實RTL界線清楚。
- 使用者未提交cell或PoT變更如影響結論，請明確標示，不歸因於本次排程修改。

## 3. 執行順序

在HYBRID_SYSTEM目錄執行，每個命令redirect至獨立log，等命令結束再查看摘要；失敗先停止分析，不盲目跑後續長測試。

```bash
make lint-inference-top
make test-layer-descriptor test-layer-controller
make test-shared-postprocess
make test-inference-top S5D_PIPE=0 S5D_POST=0 S5D_SEED=505
make test-inference-top S5D_PIPE=0 S5D_POST=1 S5D_SEED=128
make test-inference-negative S5D_PIPE=0 S5D_POST=0
make test-s4-software
```

test-shared-postprocess補上一輪90d05ef defensive patch後未重跑的全層證據；不要以舊log替代。
若最小矩陣通過且時間允許，補PIPE=1兩POST及不同CIM相位，否則明確列未測。
禁止因不明timeout或缺檔就將負測判PASS：負測必須是Conv2指定commit mismatch。
新TB沒有raw逐筆比較，中間UINT8 commit全比對；如需補raw/故障證據，可用scratchpad，不改正式程式。

## 4. 獨立驗證建議

- 至少靜態確認全鏈TB確實會檢查DCIM done，而非只測PE；必要時在scratchpad把operation_done的DCIM選擇改成PE done，應被單測／watchdog抓到。
- 可在scratchpad把weight_backend固定PE，應被真實全鏈或load/command錯誤抓到，不能出現正常PASS。
- 這些mutation是驗證TB效力，不是需求中的正常RTL；要註明改哪一行、使用何配置及預期失敗證據。
- 上輪殘留測試weight_backend=1的直接覆蓋缺口仍存在；本次正常全鏈兩次DCIM載權重不能取代「殘留同拍DCIM載權重」負向證據。可另列補測，不假稱已修復。

## 5. 請回傳的報告（務必區分觀察與推論）

1. **版本與範圍**：HEAD、dirty檔案、實際閱讀與實際執行項目、Verilator版本。
2. **結果表**：命令、PIPE/POST/seed/時脈相位、exit code、PASS摘要、log路徑。
3. **逐層表**：op0..8的read/commit數是否符合文件，最終ops=9、weight_requests=5、input_requests=1、RAM_checks=32040是否成立。
4. **負測**：實際失敗訊息、是否命中指定原因；若做mutation，附最小diff與結果。
5. **問題依嚴重度排序**：檔案:行號、觸發條件、影響、最小修法，區分RTL錯誤／TB不足／文件問題。
6. **仍未覆蓋**：中途reset、backend錯誤、其他clock phase、PIPE=1、Vivado/STA/CDC/BRAM/板測等，不以局部測試代替全top結論。
7. **准入結論**：能否進入S5-D2 Argmax；若不能，列出阻擋項及建議最小補測。

請提供摘要與必要error上下文，不貼整份編譯log。請勿自行推送、改寫歷史或提交未授權修改。
