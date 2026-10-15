# Claude 審查交接：S5-C 真實端點整層整合

## 審查目標

請獨立確認測試是否真正驗證「RAM → Reader → DCIM backend/CDC/master/chip → PoT/ReLU → Writer → RAM」，而不是以Golden代替DUT結果。請區分設計缺陷、TB缺陷、未覆蓋風險與非本階段需求。不要只依本文件的PASS敘述判定正確。

## 本次修改範圍

| 檔案（HYBRID_SYSTEM下） | 用途 |
|---|---|
| `tb/integration/tb_dcim_layer_memory.sv`（新增） | 真實端點接線、四種尺寸、兩種PoT配置、逐級scoreboard、全RAM讀回及故意破壞Golden |
| `scripts/generate_activation_path_vectors.py` | 增加Conv2/3權重、activation、獨立MAC及shift；保留原S3/S4測資 |
| `scripts/test_activation_path_vectors.py` | 新數量/shape及Conv2/3 metadata拒絕檢查 |
| `Makefile` | 新增`test-dcim-layer-memory`，保留既有回歸入口 |
| `docs/S5C_DCIM_LAYER_MEMORY.md`（新增） | 接線、控制流程、數學、驗證與限制 |
| `docs/SINGLE_BUFFER_ARCHITECTURE.md` | 更新S5-C進度，不開放FULL |
| 本文件（新增） | 獨立審查入口 |

本次沒有改動任何RTL。執行時工作樹另有使用者的cell/clock/board/argmax、文件及`pot_result_stream`空白修改，未納入本次commit。測試結果是當時工作樹結果，不應冒稱在完全乾淨checkout重跑。請先用`git status`/`git diff`辨識。

## 閱讀順序

1. `docs/SINGLE_BUFFER_ARCHITECTURE.md`：固定zp128、signed weight、CHW、單buffer與S5階段。
2. `docs/S5C_DCIM_LAYER_MEMORY.md`：本次接線與測試規格。
3. `rtl/control/dcim_layer_controller.sv` 及 `docs/DCIM_LAYER_CONTROLLER.md`：八狀態、逐patch完成條件、fault契約。
4. 新TB，特別是valid/ready雙向gate、run_owner、reference_mac、output_index及posedge scoreboards。
5. `rtl/datapath/activation_reader.sv`、`rtl/control/feature_map_writer.sv`、`rtl/memory/activation_buffer.sv`：同步RAM延遲、握手與commit。
6. `rtl/integration/kws_dcim_subsystem.sv` → `rtl/dcim_adapter/kws_dcim_backend.sv` → `CIM_CHIP/fpga/dcim_cdc_bridge.sv`／`dcim_pin_master.sv` → chip RTL（CIM_CHIP相對repo根目錄）。
7. `rtl/datapath/pot_result_stream.sv`、`kws_pot_shift_rom.sv`及PoT算術模組。
8. Python產生器、單測及輸出`build/activation_path_vectors/manifest.json`。

## 重點檢查問題

- 真實Conv2/3每筆結果是否與原軟體export相符？INT32是否另外驗證，避免ReLU/飽和遮蔽錯誤？
- k的攤平順序是否始終為d/u/v？跨32-row group是否正確，是否真有1296個權重送進backend？
- output順序是patch→channel，RAM順序是CHW；地址Golden是否獨立於DUT地址？
- writer最後一筆pending write時，controller可否過早換patch座標或宣告done？
- ready停頓的刺激是否避開posedge競爭？post_ready與實際Writer握手是否一致？
- result_last是每patch最後channel，不是整層最後資料；是否有混用？
- 未修改原檔的軟體binary/decimal、shape、dtype、zp、checkpoint、sample、scale及bias檢查是否充分？
- 負向測試是否確認指定失敗訊息，而非任意非零exit就通過？
- 本次沒有整合reset/fault注入；既有controller／subsystem單測覆蓋不等於完整端到端reset已測。
- 週期性短暫停頓不等同FIFO-full覆蓋；不得宣稱所有反壓邊界已窮盡。

## 執行方式

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM
make test-activation-path-vectors
make test-dcim-layer-memory > build/claude_s5c_real.log 2>&1
make test-dcim-layer-controller lint-dcim-layer-controller
```

等待命令結束再檢查log。完整DCIM層模擬比controller單測慢。此次兩配置各4案例、419patch、5028個raw/UINT8/commit、131072筆RAM讀回均PASS；各自負向Golden測試在第0筆正確拒絕。Python三組測試及controller回歸/lint也通過。實際摘要見設計文件第6節；請獨立重跑確認。

**非本次完成項目：**共享top整合、Conv2→Pool→Conv3連續鏈、FULL／Argmax、Vivado/STA/CDC實體驗收、板測。請輸出依嚴重度排序的findings，附檔案行號、可重現案例與最小建議修正；不要直接重構RTL。
