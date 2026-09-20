# KWS DCIM + PE 混合推論專案:現況理解與未來規劃

整理日期:2026-09-17
整理方式:逐一閱讀 `KWS/` 下全部 RTL(`.sv`)、testbench、Markdown、Makefile、Tcl/XDC、Python 腳本、模型匯出資料、Vivado 報告,以及 `0622.pptx`、`5_27.pptx`、`Proposal_for_ITRI_NVM.docx` 的文字內容。
分析期間**未修改任何原始檔案**;Verilator 回歸是把 RTL/TB 複製到 session scratchpad 後執行,不寫回專案目錄。

---

## 0. 一頁摘要

| 區塊 | 狀態 | 一句話 |
|---|---|---|
| 模型 / 數值契約 | 已凍結 | 12-filter QAT checkpoint,activation UINT8 zp=127、weight INT8 per-channel zp=0、bias=0、INT8 test accuracy 90.875% |
| CIM_CHIP(128×128 DCIM 數位模型 + Pin Master + CDC) | RTL 完成、23 份 TB 全 PASS、已上板 bitstream | 晶片規格已定;**FPGA 側「KWS 層級控制」(DCIM adapter / layer controller)完全未開始** |
| PE_CHIP(PE9,A−127) | 算術 + 12-lane array 完成 | 沒有 controller / core / standalone top;文件中的 `pe_core_12` 仍是規劃 |
| PE_CHIP_8x8(PE8,A−128 + ΣW 修正) | 算術、array、controller、core、板級自測 top 完成;Vivado 125 MHz 通過 | 是目前唯一有完整 core 的 PE |
| PE_COMPARISON | 等價 stream top 與比較框架完成;PE8 已合成(1,477 LUT) | PE9 等價 top 尚未合成;OOC hold 違規未處理 |
| HYBRID_SYSTEM | 後處理(requant/ReLU/pool/argmax)完成;PE backend 積木(loader、buffer、ΣW、align、group/result controller)完成單元與整合 TB | `memory/`、`dcim_adapter/`、`integration/`、`top/` 全部空目錄;**沒有任何可合成的系統 top** |

**最重要的兩個具體發現**

1. `CIM_CHIP/cell/fesram_cell_model.sv` 目前含 `(* EXTRACT_ENABLE = "no" *)`(2026-09-13 的 control-set 實驗)。Vivado 報告顯示它把 `dcim_master_chip_top` 的 LUT 從 **21,067 推高到 36,840**(+75%),control set 從 2,064 降到 17,時序幾乎沒變。這個實驗結果是負面的,但屬性仍留在正式 RTL 中。
2. DCIM 晶片只能算 **unsigned A × unsigned W(4+4 bit)**,模型權重卻是 **signed INT8**;目前所有文件只寫了 activation zero-point 修正(`raw − 127·ΣW`),**signed weight 在 unsigned CIM 上的編碼與修正公式尚未定義**。這是 DCIM adapter 動工前必須先拍板的規格。

---

## 1. 資料夾地圖

```text
/home/LAB505/projects/KWS/
├── KWS_result.ipynb / KWS_result copy.ipynb   訓練 + QAT + 轉換 + 匯出的 notebook(33 cells)
├── hardware_export.py                          匯出 INT8 權重與逐層 UINT8 activation 的腳本
├── KWS_experiment_20260805_v01_qnnpack_seed42.json   實驗紀錄(accuracy、qparams、環境)
├── data.npy (8000×16001 f64, 1 GB) / noise.npy (1465×16000)   原始音訊與噪音
├── mini_speech_commands/ (+zip)                8 類 × 1000 wav
├── no_variation_symmetric_qat_outputs-*/       4 份 QAT summary JSON(含 x86 vs qnnpack 對照)
├── layer_weights_int8/        ← 硬體使用的 12-filter 權重(sha a0d08dec…)
├── layer_activation_uint8/    ← 對應 dataset_index=1362 的逐層 golden(label 1 → 預測 1)
├── layer_weights_int8_filters14/ / layer_activation_uint8_filters14/   14-filter 變體,不可混用
├── 0622.pptx / 5_27.pptx / Proposal_for_ITRI_NVM.docx   晶片架構與講義
├── CIM_CHIP/                  ← 2026-09-10 建立的 Vivado 專案,RTL 是「匯入複本」(不含 EXTRACT_ENABLE)
└── KWS_DNN_Hybrid/            ← 真正的 RTL source of truth
    ├── HYBRID_PROJECT_DIRECTORY_STRUCTURE.md   三專案責任邊界與規劃
    ├── CIM_CHIP/       25 RTL、23 TB、13 md、Makefile、XDC、Tcl、Vivado 報告
    ├── PE_CHIP/        6 RTL、5 TB、6 md、Makefile
    ├── PE_CHIP_8x8/    9 RTL、8 TB、2 md、Makefile、XDC、Tcl、Vivado 報告
    ├── PE_COMPARISON/  5 RTL、3 TB、8 md、Makefile、Tcl×13、XDC×2、snapshots×4 tarball、Vivado 報告
    └── HYBRID_SYSTEM/  15 RTL、14 TB、8 md、Makefile、2 Python 腳本、3 份 TB 資料
```

環境:Verilator 5.030、Python 3.11(numpy 1.26、torch 2.10 cpu)、gtkwave。**沒有 Vivado、沒有 iverilog**(Makefile 的 `*-iverilog` 目標無法在本機執行)。整個目錄**不是 git repository**;版本管理目前靠 `PE_COMPARISON/snapshots/*.tar.gz` 手動備份。

---

## 2. 模型與數值契約(已凍結)

| 項目 | 值 |
|---|---|
| 網路 | quant → pool1 → conv1(12@3×3) → relu → pool2 → conv2(12×12@3×3) → relu → pool3 → conv3(12×12@3×3) → relu → pool4 → flatten(144) → fc1(32) → relu → fc2(8) → argmax |
| 輸入 | Mel 64×126,QuantStub 後 UINT8,scale 0.00784、zp 127 |
| Activation | UINT8,per-tensor symmetric,**所有層 zp = 127** |
| Weight | INT8 two's complement,per-channel symmetric,**所有 zp = 0**,共 7,564 bytes |
| Bias | 無(`bias=False`,轉換後全 0) |
| Requant | `q = sat_u8(round(acc × M_q31 / 2^31) + 127)`,共 76 個 per-channel Q31 乘數 |
| Accuracy(800 test) | FP32 91.125% / QAT 90.875% / INT8 converted(qnnpack) 90.875% |
| 硬體 golden | `scripts/verify_uint8_postprocess.py` 以純整數重算 62,448 個中間值,與 PyTorch 匯出 bit-exact |

層分工(HYBRID_PROJECT_DIRECTORY_STRUCTURE.md):**Conv1、FC1、FC2 → PE;Conv2、Conv3 → DCIM**。K 值:Conv1=9、Conv2/3=108、FC1=144、FC2=32。

注意事項:
- x86 backend 轉換曾出現 73.75% 的 kernel mismatch;現行 golden 全部來自 qnnpack,硬體驗證必須只用 `layer_*_int8 / layer_activation_uint8`(12-filter)。
- 目前只有 **一筆** test sample 的逐層 golden(index 1362)。完整 800 筆 test-set 的 UINT8 輸入尚未批次匯出。

---

## 3. CIM_CHIP 現況

### 3.1 架構(已實作並驗證)

```text
dcim_master_chip_top (PYNQ-Z2, 125 MHz → MMCM → 50 MHz)
├── dcim_board_self_test   開機自動:2048-word burst 寫入 → 2048 次 read 比對 → 1 次 A8W8 → LED
├── dcim_pin_master        15 狀態 FSM:Write(3clk) / Burst(3N) / Read(9) / CIM(91)
└── dcim_chip_pin_top      講義 pin 邊界 + SRAM read serializer + sumo mux
    └── dcim_macro_core    input_buffer_32x4、row/group/bank decoder、pair selector、
                           dcim_array_128x128(4 row group × 16 pair × 2 bank × 32 row × 4 cell)、
                           2 棵共享 adder_tree_32x4、2 個 bitserial_accumulator(18-bit, 8 planes)
dcim_cdc_bridge            125/50 MHz 單筆 mailbox + toggle 同步器(不支援 burst 跨域)
```

- 一次 CIM 交易 = 1 個 32-row group × 1 個 bank pair(= 1 個 W8 filter 的 32 項 dot product),回傳 even/odd 兩個 18-bit raw sum;W8 結果由上層以 ≥21-bit 做 `odd + (even << 4)`。
- A4 與 A8 都花 91 clocks(A4 前 4 個 plane 送 0);連續命令最短間隔 93 clocks。
- 保留但無功能的腳位:`pre_en`、`nv_store`、`nv_recall`、`pd_en`;`nv_power_controller.sv` 是空 module。
- Cell 是 1 個 FF 的數位抽象,沒有 FeFET 電性、precharge、sense amp、tri-state。

### 3.2 Vivado 結果(xc7z020clg400-1,Vivado 2023.2)

| 日期 | Top | LUT | FF | WNS / WHS | 備註 |
|---|---|---:|---:|---|---|
| 08-17 | dcim_chip_pin_top(125 MHz 約束) | 31,576 | 16,512 | 1.286 / 0.181 | 共享 adder tree 後第一版 |
| 08-23 | dcim_master_chip_top | 20,997 | 16,620 | 0.237 / 0.063 | **有 .bit**(`vivado_master_chip_build/`) |
| 09-10 | dcim_master_chip_top(`/KWS/CIM_CHIP` 專案) | 21,067 | 16,624 | 0.771 / 0.168 | fully routed,無 .bit |
| 09-12 | dcim_master_chip_top(`build/dcim_master_chip`) | 21,067 | 16,624 | 0.771 / 0.168 | control sets 2,064;methodology ULMTCS-2 + LUTAR-1×3 |
| **09-14** | 同上,**加 EXTRACT_ENABLE="no"** | **36,840** | 16,624 | 0.784 / 0.142 | control sets 17;`u_input_buffer_32x4` 階層吸收 16,517 LUT(寫入 D-mux 被拉到這裡);LUTAR-1×3 仍在 |

歷史(LUT_OPTIMIZATION_HISTORY.md):pin top 49,849 → 31,576 → 20,423,靠「先選 pair/group 再算」把 128 棵 adder tree 減成 2 棵,以及 read path 先在 row group 內選 pair。

### 3.3 已完成 vs 未完成

已完成:全部數位資料路徑、Pin Master 四種交易、CDC bridge、板級自測 top、23 份 TB、lint、demo 波形 Tcl、狀態圖、cmd62 記憶體快照。

未完成(CIM_CHIP 範圍內):`nv_power_controller`、FeFET/NV 行為、adder tree pipeline、CDC 上的 burst 串流。

**未完成(使用者所指「控制端」,規劃歸 HYBRID_SYSTEM,目前 0 行 RTL):**
- Conv2/Conv3 的 im2col window 產生(3×3×12 = 108 → 4 個 32-row group,補 20 列 0)
- 權重 mapping / loader(12 filter × 108 row 寫入 12 個 bank pair;可用一次 2048-word burst)
- 命令排程(每個輸出像素 × 12 filter × 4 group 的交易序列)
- 4 個 group partial sum 合併、W8 重組、signed weight 與 zp 修正
- 送入共用 `kws_postprocess`

---

## 4. PE 側現況

### 4.1 PE_CHIP(PE9:signed 9×8,activation 直接減 127)

| 模組 | 狀態 |
|---|---|
| `pe_pkg`、`activation_center_127`、`pe_multiplier_s9xs8`(use_dsp=no)、`pe_accumulator_s32` | 完成 + TB |
| `pe_mac_lane` | 2026-09-14 改為 LUT/FF:product FF → 32-bit ACC;N 接受、N+1 累加 |
| `pe_array_12` | 12 個明確實例;完成 + TB(2,928 次比對) |
| `pe_core_controller`、`pe_core_12`、`pe_standalone_top` | **未實作**(`rtl/control`、`rtl/core`、`rtl/buffer` 是空目錄);`PE_CORE_ARCHITECTURE.md` 第 6–8 節只是規格 |

Vivado:只有 DSP 時期的 raw array OOC 報告(12 DSP、8 LUT,hold −0.014)。LUT 版 PE9 從未合成。

### 4.2 PE_CHIP_8x8(PE8:signed 8×8,activation 先轉 A−128,結果再加 ΣW)

| 模組 | 狀態 |
|---|---|
| 算術四件、`pe8_array_12`(generate) | 完成 + TB |
| `pe8_core_controller`(IDLE/CLEAR/RUN/DRAIN/RESULT)、`pe8_core_12` | 完成 + TB(288 checks);K=0 忽略、無 error port |
| `pe8_standalone_top` + XDC + Tcl | 完成;7 個自測 case、watchdog、LED、BTN0 |
| Vivado(09-12) | **1,702 LUT / 960 FF / 0 DSP / 0 BRAM,WNS 0.450 / WHS 0.025 @125 MHz 全部達標**;未產生 .bit |

數學:`Σ(A−127)W = Σ(A−128)W + ΣW`,補償由 `HYBRID_SYSTEM/pe8_result_correction` 做(33-bit 加、飽和、overflow 旗標)。

### 4.3 PE_COMPARISON

- `pe_compare_engine`(PE8 為 elaboration 參數)+ `pe_compare_stream_controller` + `pe_compare_result_drain`,包成 `pe8_equivalent_top` / `pe9_equivalent_top`,兩者共用命令/輸入/輸出契約,PE8 多 cfg(ΣW)介面。
- TB:`tb_pe_array_comparison`(10,812 lane 檢查,同時驗 S = D + ΣW)、`tb_pe_equivalence`(每邊 75 筆輸出)、`tb_pe8_weight_sum_integration`(builder → cfg → PE8)。
- Vivado PE8 equivalent post-route(09-14):**1,477 LUT / 1,166 FF / 0 DSP**,WNS 0.406,**WHS −0.202(217 endpoints)**,違規來源是 OOC 輸入 port `cmd_lane_mask` → `lane_mask_reg`(0.5 ns min input delay 造成的邊界假象,不是內部路徑)。
- PE9 equivalent:**沒有 build/pe9_equivalent**,表格 LUT/FF 仍是「待 Vivado」。
- `snapshots/`:4 個 tarball 保存 DSP 版、explicit DSP48 版、LUT 版之前的 RTL。
- `sim_vendor/` / `sim_verilator/` DSP48E1 模型:現行 RTL 已不含 DSP primitive,`make test` 仍傳 `-v sim_verilator/DSP48E1.v`,無害但已無必要。

### 4.4 HYBRID_SYSTEM 已有的 PE backend 積木(全部只到單元 / 整合 TB,尚未合成)

```text
pe_layer_weight_loader(SUM_ENABLE) ─┬→ pe_weight_buffer_12 (12 × 512 × 8, ram_style=block)
                                    └→ pe_weight_sum_builder → pe_channel_sum_memory (32 × s32)
pe_group_controller(9 states) → pe_weight_read_align → {A−128 | A−127} → pe8/pe9 array
                              → pe_result_controller(PE8_MODE) → [pe8_result_correction] → out valid/ready
```

- 整合 TB `tb_pe_group_controller` / `tb_pe_group_result_controller`:真實 loader/RAM/align/兩個 array/ΣW/correction,48 筆 job、728 個 channel、C=1..32 全覆蓋、隨機停頓、reset 中斷,PE8/PE9 兩模式都 PASS。
- 仍由 TB 代替的部分:**上游命令來源、activation 重播來源**(FC1 三組要重播同一 144 筆 activation)、最外層 result 消費者。
- `kws_postprocess` 只有 valid 沒有 ready,接 result controller 前要加 FIFO 或確認逐拍可收。

---

## 5. 對「控制端」缺口的整理

使用者描述:「CIM 規格已定但控制端未完成;PE 還在設計控制狀態」。對照程式碼:

| 層級 | 已有 | 缺少 |
|---|---|---|
| CIM 交易層 | `dcim_pin_master`(4 種交易)、`dcim_cdc_bridge` | — |
| CIM 層級層(DCIM adapter) | 無 | window/im2col、weight mapper/loader、tile scheduler、partial-sum 合併、signed/zp 修正、與 postprocess 的介接 |
| PE 交易層 | `pe8_core_controller`(PE8);PE9 無 | PE9 的 core(若最終選 PE9) |
| PE 層級層 | `pe_group_controller`、`pe_result_controller`、loader/RAM/align/ΣW | activation replay buffer、layer descriptor、可合成 memory-backed top、Vivado 結果 |
| 系統層 | `kws_postprocess`、`argmax_8` | feature-map ping-pong buffer、requant 參數 ROM(76 個 Q31)、inference FSM / engine router、PE↔DCIM 結果匯流、clock/reset、`kws_hybrid_system_top`、XDC、host 介面 |

---

## 6. 關鍵發現、風險與建議

1. **EXTRACT_ENABLE 實驗應撤回或改成可選。** 21,067 → 36,840 LUT 讓 CIM 佔掉 69% 的 xc7z020,留給 PE、buffer、postprocess 的空間變小;而 LUTAR-1 警告並沒有因此消失。建議把屬性移除(或包在 `ifdef`),並以 09-12 的 21,067 LUT 版本作為 hybrid 的基準。`/KWS/CIM_CHIP` 專案內的匯入複本正好是沒有該屬性的版本,可交叉確認。
2. **signed weight 在 unsigned DCIM 上的表示法尚未定義。** 建議採 offset-binary:存 `W_u = W_s + 128`(0..255,自然拆成 even/odd 兩個 nibble),則
   `Σ(A−127)·W_s = Σ A·W_u − 128·ΣA − 127·ΣW_u + 127·128·K`,
   其中 `ΣA` 由 adapter 在送 activation 時累加(每個 patch 一個 16-bit 加法器),`ΣW_u` 每個 filter 一個常數,`K=108` 固定,**補零列不得計入 K**。這個公式需先用 Python 對 conv2/conv3 golden 驗證(4,368 + 576 個值)再寫 RTL。另一種做法是 two's-complement MSB 分兩次交易相減,交易數加倍,不建議。
3. **DCIM 交易協定決定整體推論時間。** 依現行 91-clock 交易估算(50 MHz):Conv2 = 364 像素 × 12 filter × 4 group = 17,472 次交易 ≈ **32.5 ms**;Conv3 ≈ 4.3 ms;PE 三層合計 < 1 ms;權重重載每層 3,888 clocks(78 µs,Conv2/Conv3 各需 48 個 slot,64 個 slot 放不下兩層,必須重載)。KWS 一秒一次推論綽綽有餘,但若要談 throughput,瓶頸在 4-bit `din` 的 64 個 activation load clock,這是晶片 pin 規格,FPGA 端無法繞過。
4. **PE8 與 PE9 兩條線並行維護成本高。** PE8 已有完整 core、板級自測與 125 MHz 報告;PE9 只剩 array。若論文主張「8×8 + ΣW 補償比 9×8 省 LUT」,需要儘快補 PE9 equivalent 的 Vivado 報告來支撐;若不打算主張,建議 hybrid 系統直接以 PE8 路徑(含 ΣW 記憶體)定案,PE9 只留作對照。
5. **時脈架構未定。** CIM 50 MHz、PE/後處理規劃 125 MHz,但 `dcim_cdc_bridge` 不支援 burst 且是單筆 outstanding。第一版建議**全系統單一 50 MHz**(PE 速度本來就過剩),省掉 CDC 與雙 reset 同步;125/50 雙域留到效能量測階段。
6. **OOC hold 違規要說清楚。** PE8 equivalent 的 WHS −0.202 與 PE9 array 的 −0.014 都來自 OOC 輸入 port 假 delay,整合到真實 top 後會消失;論文引用時應註明,或改用 standalone/system top 的數字(PE8 standalone 已全部達標)。
7. **重複來源與版本管理。** CIM RTL 目前有三份(`KWS_DNN_Hybrid/CIM_CHIP`、`/KWS/CIM_CHIP` 專案匯入、`vivado_master_chip_project` 內的 TB 複本),且沒有 git。建議 `git init` 並把 Vivado 專案改用「不複製來源」的方式引用。
8. **後處理路徑的 backpressure。** `kws_postprocess`、`maxpool2x2_uint8` 無 ready;requantizer 內含 32×32 乘法(合成後預期用 DSP),每拍一筆。接上 12-to-1 result controller 後只要下游每拍能收就安全,但接 feature-map buffer(可能有寫入仲裁)時必須加 FIFO。
9. **驗證資料只有一筆樣本。** 目前所有 bit-exact 證據都來自 index 1362。要證明 90.875% 需要批次匯出 800 筆 UINT8 輸入與 FC2 輸出,並有 host 端串流介面。
10. **文件與 Makefile 的小落差。** `PE_VERIFICATION_GUIDE.md` 仍標 `tb_pe_array_12` 為 TODO(實際已完成);`HYBRID_SYSTEM/Makefile` 的 `test` 目標被多次 `test:` 追加而順序零散,但功能正確;`PE_COMPARISON` 的 `make test` 仍載入不再需要的 DSP 模型。

---

## 7. 規劃用的容量數字

| 項目 | 值 | 意義 |
|---|---:|---|
| 最大 feature map | 21,960 B(conv1 輸出,若 conv1→requant→relu→pool2 串流則只需存 pool2 的 5,400 B) | BRAM ping-pong 2 × 8 KB 即可(xc7z020 有 140 個 36 Kb tile) |
| 輸入 UINT8 mel | 8,064 B | host → BRAM |
| PE weight buffer | 12 × 512 = 6,144 B ≥ FC1 4,608 B | 現有 loader 已涵蓋 |
| ΣW memory | 32 × 32 bit | 現有 |
| DCIM 權重 | conv2/conv3 各 1,296 W8 → 48/64 slot | 每層一次 burst |
| Requant 參數 | 76 × 32-bit Q31 + 每層 zp(全為 127) | 需一個小 ROM |
| LUT 預算 | CIM 21.1k + PE8 backend ≈ 2–3k + 後處理/buffer/控制 ≈ 2–4k ≈ 28k / 53.2k | 使用 09-12 版 CIM 才成立;36.8k 版會到 ~45k |

---

## 8. 未來規劃(建議順序)

### Phase 0:收斂與決策(1 週內可完成)
- [ ] 決定是否移除 `EXTRACT_ENABLE="no"`(建議移除),重跑 CIM 合成確認回到 ~21k LUT。
- [ ] 決定 hybrid 使用 PE8 或 PE9(建議 PE8),以及第一版時脈(建議單一 50 MHz)。
- [ ] `git init`,把 `snapshots/*.tar.gz` 的歷史轉成 tag;Vivado 專案不再複製來源。
- [ ] 補 PE9 equivalent 的 Vivado 報告(若仍要做 8×8 vs 9×8 比較)。
- [ ] 寫 `HYBRID_SYSTEM/docs/MODEL_QUANTIZATION_SPEC.md` 與 `PE_DCIM_INTERFACE_SPEC.md`:把第 2 節契約、DCIM signed-weight 編碼(第 6 節第 2 點)、layer descriptor 欄位、每層 K/C/尺寸/relu/pool 設定表寫成單一權威文件。

### Phase 1:Python bit-accurate 參考模型(與 RTL 平行)
- [ ] 在 `HYBRID_SYSTEM/scripts/` 新增 `hybrid_reference.py`:用整數重現 PE 路徑(含 PE8 的 −128/+ΣW)與 DCIM 路徑(unsigned nibble、even/odd 18-bit、W8 重組、ΣA/ΣW 修正、4-group 合併、補零列),逐層對 `layer_activation_uint8` 比對。
- [ ] 產生每層的 RTL 向量檔(activation 串流、權重 burst 順序、每筆交易的期望 even/odd raw)。
- [ ] 批次匯出 800 筆 test 輸入(擴充 `hardware_export.py`),記錄 FC2/argmax 作為系統級 golden。

### Phase 2:PE backend 可合成 top(`HYBRID_SYSTEM/rtl/integration/pe_backend_top.sv`)
- [ ] 加 activation replay buffer(FC1 需要 144 B × 3 次重播)與 layer descriptor 暫存。
- [ ] 把 loader / buffer / ΣW memory / align / group controller / result controller 接成單一 top,PE8_MODE 參數化。
- [ ] 以真實 Conv1(1,830 個 patch)、FC1、FC2 向量做整層 TB;OOC 合成取得 LUT/FF/BRAM/DSP 與時序。

### Phase 3:DCIM adapter(`HYBRID_SYSTEM/rtl/dcim_adapter/`)
- [ ] `dcim_weight_mapper`:signed INT8 → offset-binary W8,排成 row-major(128 row × 16 pair,未用 pair 補 0),透過 pin master burst 一次寫入。
- [ ] `kws_window_generator`:從 feature buffer 產生 3×3×12 = 108 個 UINT8,切成 4 個 32-byte 向量(補 0),同時累加 ΣA。
- [ ] `dcim_command_scheduler`:每像素 × 12 filter × 4 group 的交易序列,含 done/result_valid 握手。
- [ ] `dcim_result_backend`:21-bit W8 重組 → 4 group 累加 → 減 128·ΣA、127·ΣW_u、加常數 → signed INT32 → `kws_postprocess`。
- [ ] TB 以 Phase 1 產生的 conv2/conv3 向量逐像素比對 4,368 + 576 個 UINT8 輸出。

### Phase 4:共用系統元件
- [ ] `kws_feature_buffer`(ping-pong BRAM、channel-major 定址)。
- [ ] `kws_quant_parameter_rom`(76 Q31)、`kws_layer_descriptor_rom`。
- [ ] `kws_inference_controller` / `kws_engine_router`:依 descriptor 依序驅動 PE backend 或 DCIM adapter,結果統一成 scalar stream 進 `kws_postprocess`(加 FIFO 解決 ready 缺口)。
- [ ] `argmax_8` 接 FC2 輸出,產生 3-bit class 與 done。

### Phase 5:`kws_hybrid_system_top` 與上板
- [ ] 單一 50 MHz(MMCM)、同步 reset、內建 self-test 模式(以 ROM 存 index 1362 的輸入,LED 顯示 class==1)。
- [ ] `HYBRID_SYSTEM/constraints/kws_hybrid_system_top_pynq_z2.xdc`、建專案 Tcl、報告 hooks(沿用 CIM 的模式)。
- [ ] Vivado 全流程,確認 WNS/WHS ≥ 0、fully routed、LUT/FF/BRAM/DSP;上板看 LED。

### Phase 6:批次驗證與效能量測
- [ ] Host 介面(UART 或 PS 端 AXI)串流 800 筆輸入,回收 argmax,對比 90.875%。
- [ ] cycle counter 量測每層時間,與第 6 節估算對照;評估 125/50 雙時脈是否值得。
- [ ] 若要做 NV/normally-off 論述,再回到 CIM_CHIP 補 `nv_power_controller`(目前可明確列 out of scope)。

每個 Phase 都沿用專案既有規則:先寫責任邊界與資料流 → 最小可合成 RTL → 獨立 TB(正常/邊界/停頓/reset)→ `make test` + `make lint` 全綠 → 才接上一層。

---

## 9. 附錄

### 9.1 各專案指令

```bash
cd KWS_DNN_Hybrid/CIM_CHIP      && make test && make lint     # 23 TB;可 make BUILD_ROOT=/tmp/x test
cd KWS_DNN_Hybrid/PE_CHIP       && make test && make lint     # 5 TB
cd KWS_DNN_Hybrid/PE_CHIP_8x8   && make test && make lint     # 8 TB(含 standalone 三實例)
cd KWS_DNN_Hybrid/PE_COMPARISON && make test lint check-tools test-equivalent test-weight-sum-integration
cd KWS_DNN_Hybrid/HYBRID_SYSTEM && make test && make lint     # 14 TB + Python golden + elaboration 檢查
```

### 9.2 Vivado 報告位置

| 內容 | 路徑 |
|---|---|
| CIM master top(21,067 LUT,09-12) | `CIM_CHIP/build/dcim_master_chip/.../reports/post_route/20260912_231604/` |
| CIM master top(36,840 LUT,09-14,EXTRACT_ENABLE) | `.../reports/post_route/20260914_145848/` |
| CIM master top bitstream(08-23) | `CIM_CHIP/vivado_master_chip_build/dcim_master_chip_pynq_z2.runs/impl_1/dcim_master_chip_top.bit` |
| PE8 standalone | `PE_CHIP_8x8/build/vivado_standalone/pe8_standalone.runs/impl_1/` |
| PE8 equivalent(1,477 LUT) | `PE_COMPARISON/build/pe8_equivalent/reports/post_route/20260914_200605/` |
| PE9 raw array(DSP 版) | `PE_COMPARISON/build/pe9/pe_compare_pe9.runs/impl_1/` |

### 9.3 本次在 scratchpad 副本執行的 Verilator 回歸結果(2026-09-17,Verilator 5.030)

RTL/TB 以 tar 複製到 session scratchpad 後執行,原始目錄的 `build/` 與來源檔時間戳均未變動。

| 專案 | 指令 | 結果 | 重點摘要 |
|---|---|---|---|
| PE_CHIP | `make test` / `make lint` | exit 0 / exit 0 | 乘法器 65,536 組、累加器 19 checks、MAC lane 280,241 checks、array 2,928 次 lane 比對 |
| PE_CHIP_8x8 | `make test` / `make lint` | exit 0 / exit 0 | activation 256、乘法器 65,536、累加器 131,084、MAC 280,241、array 2,964、controller 14、core 288、standalone 204 |
| PE_COMPARISON | `make test lint test-equivalent test-weight-sum-integration check-tools` | 全部 exit 0 | array 比較 10,812 lane checks;PE8/PE9 equivalent 各 75 筆輸出;builder→PE8 10 jobs / 83 輸出;Python 工具 8 tests OK |
| HYBRID_SYSTEM | `make test` / `make lint` | exit 0 / exit 0 | group+result controller 兩模式各 48 jobs / 728 輸出;group controller 373,164 次逐 cycle lane 比對;read align 516 筆;loader 16,642 寫入 / 33,282 讀回;後處理 5 份 TB;Python golden 62,448 值;elaboration 檢查 PE8=1 顆 / PE9=0 顆 correction |
| CIM_CHIP | `make test`(分兩次執行,第一次在 CDC 測試時因 session 結束中斷,第二次補跑 `make test-fpga`) | 23 份 TB 全部 PASS,exit 0 | pin top:2,048 words 全寫入、64/64 group-pair A8W8 golden 相符;pin master:A4W8 35,728 / A8W8 458,960、Read 9 cycles;CDC:36 筆命令;board top:LED=0101 |
| CIM_CHIP | `make lint` | exit 0 | `PASS: all available lint checks completed`(含 `-DSYNTHESIS` 的可合成 lint) |

補充:iverilog 交叉驗證目標(`*-iverilog`、`test-unisim`)因本機未安裝 iverilog 而未執行。

### 9.4 後處理整層 RTL 串流驗證(scratchpad 專用 TB,未加入專案)

現有 5 份後處理 TB 都是少量 directed case(requant 11 筆、ReLU 5 筆、maxpool 1×3×5、argmax 2 組、整合 2 組),且 `tb/data/*.txt` 並未被任何 TB 讀取;bit-exact 的 62,448 值比對是 Python 對「公式」的驗證,不是對 RTL。為確認 RTL 本身,另寫 scratchpad TB 將 dataset_index=1362 的**完整各層 INT32 accumulator(channel-major 順序)**串流進未修改的 `kws_postprocess`、`maxpool2x2_uint8`、`argmax_8`:

| 路徑 | 輸入筆數 | 比對輸出 | 結果 |
|---|---:|---:|---|
| quant_input → Pool1(獨立 maxpool,126×64) | 8,064 | 2,016 | PASS |
| Conv1 acc → requant → ReLU → Pool2(61×30×12,奇數寬) | 21,960 | 5,400 | PASS(含 channel/y/x 座標與 frame_done) |
| Conv2 acc → … → Pool3(28×13×12,奇數高) | 4,368 | 1,008 | PASS |
| Conv3 acc → … → Pool4(12×4×12) | 576 | 144 | PASS |
| FC1 acc → requant → ReLU | 32 | 32 | PASS |
| FC2 acc → requant → argmax | 8 | 8 + class | PASS(class=1, max=171) |

兩輪(連續 valid、LFSR 隨機 bubble)共比對 17,216 個輸出全部一致;layer 之間不 reset、frame 背靠背。量得延遲:非 pool 路徑為輸入被取樣後第 3 個 clock 輸出(4 級暫存器),pool 路徑為完成 2×2 視窗的像素被取樣後第 4 個 clock(5 級)。一次推論的全部後處理約 35,000 clocks(50 MHz 下約 0.7 ms)。

同時確認一個整合層面的問題:`maxpool2x2_uint8` 要求 **channel-major**(`[c][y][x]`)輸入,但 PE 路徑每個 patch 一次產生 12 個 channel、由 `pe_result_controller` 依 lane 0..11 送出,屬於 **pixel-major**。Conv1 的結果若直接串進 `kws_postprocess` 的 pool 會錯位;需要先存成完整 feature map 再以 channel-major 讀出做 pool,或把 maxpool 的 line buffer 改為每 channel 一份(61×12 = 732 B)。DCIM 路徑因每筆交易只算一個 filter,排程可自行選 channel-major,不受影響。

### 9.5 全架構數學式的純整數驗算(scratchpad 腳本 `math_check/check_math.py`,未加入專案)

以 sample 1362 的 golden 資料,從 `quant_input` 以純整數一路算到 argmax,共 22 項檢查全部 PASS:

| 數學式 | 檢查內容 | 結果 |
|---|---|---|
| 輸入量化 | `q0 = clamp(round(x / s0) + 127, 0, 255)` 對 8,064 筆 | 0 mismatch |
| MaxPool | pool1 / pool2 / pool3 / pool4 | bit-exact |
| PE9 MAC | `acc = Σ(A−127)·W`,五層 | 作為基準 |
| PE8 MAC | `Σ(A−128)·W + ΣW == PE9`,五層 | 全部相等 |
| DCIM MAC | offset-binary `W_u = W+128`、高低 nibble 分 bank、32-row group 補零、MSB-first bit-serial `acc = (acc<<1) + partial`、`odd + (even<<4)`、4 group 合併後修正 | conv2 4,368 筆、conv3 576 筆與 PE9 全部相等 |
| Requant + ReLU + Pool | 五層輸出對 golden | bit-exact |
| Argmax | 嚴格大於規則 | class 1,與 torch 相同 |

第 6 節第 2 點的修正式可再化簡。因為 `ΣW_u = ΣW_s + 128·K`,常數項合併後 K 消失:

`Σ(A−127)·W_s = ΣA·W_u − 128·ΣA − 127·ΣW_s`

也就是 DCIM adapter 只需要每個 patch 的 `ΣA` 與每個 filter 的 `ΣW_s`,後者與 PE8 用的 `pe_weight_sum_builder` 輸出相同,可共用。補零列只要 activation 送 0 即可,不需另外處理 K。

實測位元寬(單一樣本):plane partial sum 最大 304(9 bit 上限 511);bank raw sum 最大 49,512(18 bit 上限 262,143);4 group 合併後 W8 總和最大 2,378,076,理論上限 108×255×255 = 7,022,700,需 23 bit unsigned;`ΣA` 最大 16,939,理論上限 27,540,需 15 bit。
