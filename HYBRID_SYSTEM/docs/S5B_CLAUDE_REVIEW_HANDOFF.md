# S5-B 獨立審查交接：給 Claude 的閱讀與驗證清單

日期：2026-10-15。審查對象：實作提交 `8cf17a370025aba38bdec697259c690163349fd8`。
本文件只整理審查材料，不代表 Claude 已經審查，也不是要求審查者認同原作者的結論。

## 1. 可直接交給 Claude 的任務

> 請獨立審查 KWS_DNN_Hybrid 的 S5-B `kws_dcim_subsystem`。先讀本文件與架構基準，再讀實際 RTL、TB 和 Makefile；不要僅根據文件或 PASS 判定正確。請只分析、不修改檔案、不 commit/push。確認薄封裝是否忠於目標、四模組介面與 reset 是否正確、CDC 在契約內有無遺失／重複交易，以及測試是否真的能捕捉錯誤。若執行工具，請記錄命令、版本、退出狀態與範圍。請將確定 bug、設計限制、缺少測試、待實體簽核分開，列出檔案與行號、觸發條件、影響與最小改善建議。不要求本階段完成 S5-C 或板級設計；但若某缺口阻礙下一階段，請明確標示。未找到 bug 時，也請列出仍無法證明的項目。

專案根目錄：`/home/LAB505/projects/KWS/KWS_DNN_Hybrid`。
以下除 Markdown 連結外的程式路徑皆相對此根目錄。

## 2. 本次目標與不可混淆的邊界

目標是把已存在的單 patch backend 接到真正雙時脈 CDC、pin master、FPGA chip RTL 模型；保持既有計算與握手協定，不新增一層調度 FSM。

| 固定條件 | 內容 |
|---|---|
| 計算 | K=108，12 filters，無 bias |
| 外部資料 | UINT8 activation、zp128；signed INT8 weight |
| 輸出 | 12筆 signed INT32，filter_id=0..11 |
| 系統域 | backend及所有公開資料握手，`clk_sys/rst_sys` |
| CIM域 | bridge slow、master、chip，`clk_cim/rst_cim` |
| 權重命令 | 單筆write；burst固定停用 |
| reset | 同一reset原因，兩域各自同步解除；不支援單域獨立reset |
| 所在階段 | S5-B功能整合；S5-C才是整層Reader/PoT/Writer |

不包含：整層Conv2/3排程、共享activation RAM接線、PoT/ReLU、Argmax、完整推論、板級MMCM/reset產生器、外接實體晶片IO、NV電性模型或Vivado實體CDC簽核。模擬頻率不等於實體可達頻率。

```text
上層（sys）
  │ load/weight/patch/activation
  ▼
kws_dcim_backend ── cmd/rsp ── dcim_cdc_bridge
  ▲                            sys │ cim
  │                               ▼
  │                        dcim_pin_master
  │                               ↕ chip pins
  │                        dcim_chip_pin_top
  └─ raw回應 → 修正／跨group累加
  │
  └─ result_valid/ready + signed INT32 → 上層（sys）
```

## 3. 本次修改清單

| 類型 | 檔案 | 審查重點 |
|---|---|---|
| 新增RTL | `HYBRID_SYSTEM/rtl/integration/kws_dcim_subsystem.sv` | 四模組具名接線；signed、位寬、時脈/reset；沒有額外FSM |
| 新增TB | `HYBRID_SYSTEM/tb/integration/tb_kws_dcim_subsystem.sv` | 真實全鏈路、獨立golden、多時脈、反壓、reset/fault |
| 修改建置 | `HYBRID_SYSTEM/Makefile` | 新test/lint入口、四組設定、負向測試判定；舊S5-A負向搜尋改grep |
| 新增設計說明 | [S5B_DCIM_CDC_INTEGRATION.md](S5B_DCIM_CDC_INTEGRATION.md) | 完整ports、FSM、reset契約、測試結果與限制 |
| 修改架構基準 | [SINGLE_BUFFER_ARCHITECTURE.md](SINGLE_BUFFER_ARCHITECTURE.md) | S5-B功能通過，S5-C/D與實體簽核仍待完成 |

本交接文件是後續文件補充，不屬於上述五份原始實作變更。

## 4. 建議閱讀順序與檔案用途

### A. 先確認目標

1. 根目錄 `AGENTS.md`：工作規則；本次只審查，不自動執行修改工作流。
2. [SINGLE_BUFFER_ARCHITECTURE.md](SINGLE_BUFFER_ARCHITECTURE.md)：整體階段與不變的責任邊界，特別是S5及進度。
3. [S5A_DCIM_BACKEND.md](S5A_DCIM_BACKEND.md)：原backend協定、mapping、單時脈驗收。
4. [DCIM_S5_FORMULAS.md](DCIM_S5_FORMULAS.md)：數學與權重／activation順序。
5. [S5B_DCIM_CDC_INTEGRATION.md](S5B_DCIM_CDC_INTEGRATION.md)：本次實作宣稱；需逐項對照程式，不視為獨立證據。

### B. 四個實例與必要下層

依序閱讀：

| 路徑 | 要確認什麼 |
|---|---|
| `HYBRID_SYSTEM/rtl/integration/kws_dcim_subsystem.sv` | 頂層所有連接、burst常數、未用輸出 |
| `HYBRID_SYSTEM/rtl/dcim_adapter/kws_dcim_backend.sv` | nine-state流程、load/patch優先、tile、done/error、回應接受條件 |
| `HYBRID_SYSTEM/rtl/dcim_adapter/dcim_u8_offset_correction.sv` | unsigned偏移修正與位寬 |
| `CIM_CHIP/fpga/dcim_cdc_bridge.sv` | toggle同步器、穩定mailbox、單筆在途、reset |
| `CIM_CHIP/fpga/dcim_pin_master.sv` | start/busy/done語義、W8A8組合、pin時序 |
| `CIM_CHIP/chip/dcim_chip_pin_top.sv` | master控制到macro/serializer的實際接線 |
| `CIM_CHIP/chip/dcim_macro_core.sv` | array/input buffer/accumulator路徑 |
| `CIM_CHIP/peripheral/input_buffer_32x4.sv` | 每次bit-plane資料載入方式 |
| `CIM_CHIP/peripheral/bitserial_accumulator.sv`、`serial_output.sv`（同目錄） | 位序、累加與輸出時間 |
| `CIM_CHIP/cell/fesram_cell_model.sv` | reset/write及工作樹差異對實驗的影響 |

若發現raw結果或mapping問題，再向array、segment、cell追蹤；不需先讀所有無關PE/後處理檔案。完整合成來源清單由Makefile的`DCIM_SUBSYSTEM_RTL`、`DCIM_BACKEND_RTL`、`DCIM_CHIP_RTL`提供。

### C. 測試與建置

1. 新TB：`HYBRID_SYSTEM/tb/integration/tb_kws_dcim_subsystem.sv`。
2. `HYBRID_SYSTEM/Makefile`：`test-dcim-subsystem`、`lint-dcim-subsystem`。
3. 舊backend TB：`HYBRID_SYSTEM/tb/integration/tb_kws_dcim_backend.sv`。
4. 舊CDC TB：`CIM_CHIP/tb/fpga/tb_dcim_cdc_bridge.sv`。
5. 舊全鏈路TB：`CIM_CHIP/tb/fpga/tb_dcim_cdc_bridge_integration.sv`。
6. `CIM_CHIP/Makefile`：對應CDC回歸入口。

## 5. 數學與流程驗收基準

權重輸入順序filter→channel→u→v，每filter 108筆。硬體配置 `row=k, pair=filter`，每filter補到128筆；有效1296加padding240，共1536次write。

activation順序channel→u→v，108筆按32/32/32/12分組；最後20筆補128。每group依序算12 filters，共48次CIM，不是把108筆同時塞進32筆buffer。

對每個32筆group，令 `Wu=Ws+128`：

\[
U=\sum_{j=0}^{31}A_{u,j}W_{u,j},\qquad
P=U-128\sum_j A_{u,j}-128\sum_j W_{u,j}+32\cdot16384.
\]

四組累加應為：

\[
ACC_c=\sum_{i=0}^{107}(A_i-128)W_{c,i}.
\]

需從程式核對本專案even/odd定義：文件宣稱 `U=odd+(even<<4)`，先擴位再左移；不可套用別的even/odd命名習慣。padding在修正後貢獻須為0。

Write成功是done，不需要result_valid；CIM成功則必須帶有效raw資料。最後12筆結果必須在ready接受後才算完成，不能因結果產生就提早patch_done。

## 6. 請逐項審查的風險

| 面向 | 請回答的問題 |
|---|---|
| 接線 | 有無漏接、重複驅動、截位、signed轉型錯誤、reset極性錯誤？ |
| 命令 | cmd_valid且ready=0是否保持？load與patch競爭是否只接受一個？ |
| CDC | mailbox在對方擷取前能否被覆寫？request/response toggle是否一對一？ |
| 完成 | master_done與busy的邊界會否漏啟動？response是否保持到消費？ |
| reset | 兩種解除順序是否安全？sys先送命令、cim仍reset時是否保留？ |
| fault | 在途交易與部分結果如何取消？是否只靠共同reset恢復，文件是否說清楚？ |
| 算術 | shift擴位、符號、raw重組、四組累加、padding是否正確？ |
| TB獨立性 | expected是否由輸入與獨立公式建立，而非由DUT結果倒推？ |
| TB排程 | posedge/NBA比較是否有race？各中斷位置是否真的到達，不是只跑到timeout？ |
| TB完整性 | 是否核對數量、位址、順序、資料與done，而非只看PASS或最後一筆？ |
| 範圍 | 有無把RTL功能通過混稱為時序、CDC實體或完整CNN通過？ |

特別請檢查：`check_sys`、`check_cim`兩個monitor；`reset_all`、`check_quiet`、`load_layer`、`prepare_patch`、`send_activations`、`run_patch`、`interrupt_patch`各task及最後initial測試順序。

## 7. 已執行測試與可追溯證據

原實作環境Verilator 5.030。下表是已記錄的結果，不取代審查者自行重跑。

| sys MHz | CIM half period ps | phase ps | seed | 完整載入/patch/結果 | reset/fault |
|---:|---:|---:|---:|---|---|
| 125 | 10000 | 1300 | 505 | 13/16/192 PASS | 5/5 PASS |
| 125 | 9434 | 2700 | 128 | 13/16/192 PASS | 5/5 PASS |
| 125 | 4000 | 0 | 505 | 13/16/192 PASS | 5/5 PASS |
| 125 | 3000 | 1900 | 128 | 13/16/192 PASS | 5/5 PASS |

合計768筆完整patch輸出一致，不含故意中止的patch。頻率較高的案例只測協定，沒有延遲回標。

本機log位置：

```text
HYBRID_SYSTEM/build/dcim_subsystem/
  half_10000_phase_1300_seed_505.log
  half_9434_phase_2700_seed_128.log
  half_4000_phase_0_seed_505.log
  half_3000_phase_1900_seed_128.log
  negative_golden.log
HYBRID_SYSTEM/build/dcim_backend/
  seed_505.log
  seed_128.log
  negative_golden.log
```

四份subsystem log應有 `PASS S5-B SUMMARY loads=13 patches=16 results=192 targeted_resets=5 source_faults=5`。負向golden須非零退出且包含`result mismatch`；只看到程式失敗不算驗證成功。

原有backend兩seed各5次載入、6個成功patch/72結果、4個reset恢復通過。既有CDC測試36命令、reset對齊通過；真實CDC/master/chip的SRAM、A4W8、A8W8、非法burst亦通過。新TB沒有公開SRAM read介面，不能將舊TB讀回數量算成新TB的覆蓋率。

這些build log未納入Git；遠端審查若沒有log，應重跑或明確標記「只有作者紀錄，未獨立重現」。

## 8. 重現方式與版本差異

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid
git status --short
git show --stat 8cf17a3
git diff 8cf17a3^ 8cf17a3 -- HYBRID_SYSTEM
verilator --version

cd HYBRID_SYSTEM
make lint-dcim-subsystem
make test-dcim-subsystem
make test-dcim-backend
cd ../CIM_CHIP
make test-dcim-cdc-bridge test-dcim-cdc-integration
```

建議將每項命令輸出重新導向獨立review log，記錄退出碼，等完成再看摘要；不要覆寫原始證據。測試會生成build檔案，但不需修改RTL。沒有Verilator時請只做靜態審查，不能宣稱重跑PASS。

**工作樹與提交不是完全相同的實驗輸入。** 原測試在含使用者未提交修改的工作樹執行；其中`CIM_CHIP/cell/fesram_cell_model.sv`在編譯依賴內。請用`git diff -- CIM_CHIP/cell/fesram_cell_model.sv`核對，不能直接宣稱乾淨checkout已通過。其他既有clock/top/PE/後處理修改未納入此提交；MMCM檔沒有被本TB實例化。請保留所有使用者修改，禁止reset/checkout清除它們。若需乾淨提交比對，用另外的worktree/複本並清楚標示結果來源。

## 9. 尚未證明與可補測項目

- 無Vivado synthesis/implementation、CDC report、routed timing、面積或板測證據。
- 無類比metastability注入，也未隨機延長同步器辨識延遲；數位模擬不能證明MTBF。
- bundled-data mailbox需實體資料延遲／必要skew約束與同步器placement檢查，不可一律false-path後視為安全。
- 同源MMCM時脈的關係需依實際板級設計處理；不預先假定非同步或固定max-delay值。
- 外部reset產生器、最小reset pulse、clock停止/lock遺失未做板級驗證。
- 本次五個reset/fault位置以計算／輸出交易為主；權重寫入途中中止與所有狀態逐一覆蓋不應自行宣稱完成。
- 缺少輸入筆數、永久反壓沒有硬體timeout；這是介面限制，需由上層負責。
- 未驗完整軟體Conv2/3資料與整層RAM commit；下一階段需真實軟體golden。
- Verilator測試不是四態X傳播或形式驗證；亦沒有宣稱完整覆蓋率數字。

請判斷每項是S5-B功能阻擋、S5-C整合必要條件，還是上板前必要條件，不要混為同一等級。

## 10. 請回傳的審查格式

1. **總結**：符合／部分符合／不符合S5-B目標，以及判斷範圍。
2. **閱讀清單與版本**：實際讀了哪些檔案、提交與工作樹差異。
3. **問題表**：嚴重度、類別、檔案:行號、可重現觸發條件、影響、最小建議、需新增的測試。
4. **架構／數學／CDC／reset／TB各自結論**：不要用一個PASS概括所有項目。
5. **實際執行的驗證**：命令、退出碼、結果；未執行的原因。
6. **能否進入S5-C**：必要修正與可以延後的實體驗證分列。

若無確定錯誤，請寫「在已審查範圍內未找到確定功能錯誤」，不要寫「保證所有情況正確」或「保證125/53MHz可上板」。
