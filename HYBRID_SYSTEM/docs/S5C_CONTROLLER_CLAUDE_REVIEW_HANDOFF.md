# S5-C 第一批實作：Claude 獨立審查交接

日期：2026-10-15。實作版本：`19376487d46432d8073dc3baa6476257f034c8f7`。
本文件整理實作內容、變更與驗證證據，**不代表Claude已審查，不代表完整S5-C已完成**。

更新（2026-10-15）：使用者提供Claude對`1937648`的審查結果後，已完成V1～V6補測，見本文件第10節。第1～9節保留原交接版本背景；其中「未測」項目以第10節最新狀態為準。

## 1. 可直接使用的審查任務

> 請依本文件閱讀實際RTL、TB、Makefile與版本差異，獨立判斷dcim_layer_controller是否符合S5-C第一批目標，以及pot_result_stream改名是否完整且未改變行為。請先只審查、不修改程式、不commit/push。不要只根據PASS或作者文件判斷；請追查握手、同拍完成、反壓、reset、錯誤與組合回授。如果執行測試，輸出寫入獨立log，完成後再檢查，不持續查看每拍數值。回報確定問題時請附檔案與行號、觸發條件、影響與最小修正建議。將功能錯誤、驗證缺口、可選最佳化、未完成整合及實體時序限制分開。最後說明是否可進入真實DCIM/RAM整合測試。

根目錄：`/home/LAB505/projects/KWS/KWS_DNN_Hybrid`。下列檔案路徑均相對根目錄。

## 2. 目標與本次交付邊界

本次新增**整層排程控制器與協定單測**，並完成後處理名稱遷移。

- 固定12輸入channel、12 filters、K=108、3×3、stride1、padding0。
- layer_id=1/2，對應PoT ROM的Conv2/Conv3；不等同整體九操作descriptor的索引。
- W/H可配置，接受合法小圖與正式模型尺寸，不是只接受兩個固定尺寸。
- 每層Writer命令一次，每patch DCIM及Reader命令各一次。
- 每patch 108筆activation、12筆後處理結果；下一patch不能覆蓋尚未排空的座標。
- raw INT32、UINT8 payload不經控制器保存；不新增RAM、FIFO、CDC或MAC。
- CONFIG非法回IDLE並error脈波；執行期錯誤進FAULT，等待共同reset。
- 名稱改為`pot_result_stream`，原量化、ReLU、FIFO與pipeline參數不變。

**沒有完成**：controller與真實DCIM/RAM整合、Conv2/3整層軟體golden、共享top接入、FULL推論、Vivado時序與板測。單測中的端點是受控協定刺激，不是實際運算核心。

## 3. 變更清單（21份檔案）

### 新增（3份）

| 檔案 | 內容 |
|---|---|
| `HYBRID_SYSTEM/rtl/control/dcim_layer_controller.sv` | 八狀態、配置驗界、握手／座標／完成／FAULT |
| `HYBRID_SYSTEM/tb/control/tb_dcim_layer_controller.sv` | 公開介面協定測試與負向期望值測試 |
| `HYBRID_SYSTEM/docs/DCIM_LAYER_CONTROLLER.md` | 設計決定、連接、FSM、驗證及限制 |

### 改名（2份）

- `HYBRID_SYSTEM/rtl/datapath/pe_pot_result_stream.sv` → `pot_result_stream.sv`。
- `HYBRID_SYSTEM/tb/datapath/tb_pe_pot_result_stream.sv` → `tb_pot_result_stream.sv`。

module名稱與實例引用同步改名；舊名稱無相容wrapper。RTL首行用途註解也改為PE或DCIM的INT32結果。

### 來源／實例引用與測試入口（7份）

- `HYBRID_SYSTEM/Makefile`：新controller test/lint、PoT來源與TB改名。
- `HYBRID_SYSTEM/board/postprocess/Makefile`。
- `HYBRID_SYSTEM/board/postprocess/create_project.tcl`。
- `HYBRID_SYSTEM/board/postprocess/postprocess_self_test.sv`。
- `HYBRID_SYSTEM/rtl/integration/pe_pot_engine.sv`。
- `PE_COMPARISON/Makefile`。
- `PE_COMPARISON/vivado/create_pe_board_project.tcl`。

### 文件更新（9份）

`HYBRID_SYSTEM/docs/`：

- `PE_COMBINATIONAL_POSTPROCESS.md`
- `PE_POT_INTEGRATION.md`
- `POSTPROCESS_BOARD_TEST.md`
- `POSTPROCESS_POT_MATH_GUIDE.md`
- `POT_DERIVATION_PRESENTATION_REPORT.md`
- `S5C_ARCHITECTURE_REVIEW_PLAN.md`
- `SINGLE_BUFFER_ARCHITECTURE.md`

`PE_COMPARISON/docs/`：`PE8_BOTTOM_UP_GUIDE.md`、`PE8_CONTROL_STATE_ATLAS.md`。

另有使用者尚未追蹤的三個`sweep_postprocess_{comb,fine,strategy}.tcl`在工作樹更新來源名稱，但未整份納入提交，避免帶入既有未授權內容。已產生build/snapshot/XPR不改寫；需重新產生專案或更新來源。

## 4. 閱讀順序

1. `AGENTS.md`：工作樹保護規則。此次任務是審查，非授權修改。
2. [SINGLE_BUFFER_ARCHITECTURE.md](SINGLE_BUFFER_ARCHITECTURE.md)：單buffer與階段邊界。
3. [S5C_ARCHITECTURE_REVIEW_PLAN.md](S5C_ARCHITECTURE_REVIEW_PLAN.md)：原提案，部分待定事項已在實作文件定案。
4. [DCIM_LAYER_CONTROLLER.md](DCIM_LAYER_CONTROLLER.md)：本次實作契約與已測範圍。
5. 新RTL與新TB，逐行對照，不把文件當作程式本身。
6. `HYBRID_SYSTEM/rtl/datapath/activation_reader.sv`、`rtl/control/feature_map_writer.sv`（均在HYBRID_SYSTEM）：核對真實ready/done與commit時序。
7. `HYBRID_SYSTEM/rtl/integration/kws_dcim_subsystem.sv`、`rtl/dcim_adapter/kws_dcim_backend.sv`（均在HYBRID_SYSTEM）：核對patch_done、activation_ready、source_error。
8. `HYBRID_SYSTEM/rtl/datapath/pot_result_stream.sv`、`kws_pot_shift_rom.sv`（同目錄）：核對FIFO及模型layer/channel ID。
9. `HYBRID_SYSTEM/Makefile`與改名引用檔，確認測試及Vivado入口沒有漏改。

若要審查下一步整合，可再讀`kws_activation_path.sv`、`layer_descriptor_rom.sv`、`layer_controller.sv`；它們本次沒有接上新controller，不可假設已支援DCIM整層。

## 5. 程式結構與必要不變條件

```text
IDLE → CONFIG(4 phases) → START_WRITER → START_PATCH → START_READER
                                                    ↑                ↓
                                                    └── RUN_PATCH ───┘
                                                          │ 最後patch
                                                          ▼
                                                     DRAIN_LAYER → IDLE/done
執行期錯誤 → FAULT → 共同reset
```

| RTL區域 | 審查重點 |
|---|---|
| 配置暫存與CONFIG | 外部命令改變是否影響當前任務；尺寸乘積／端點是否正確擴位；區域不得重疊 |
| candidate/after計數 | 當拍最後握手是否計入；是否形成runtime_bad自我回授 |
| activation_bad/result_bad | 非法last/channel/error是否在握手前阻擋 |
| completion_bad | 早到／重複done、不同狀態done是否按契約處理 |
| 輸出gate | Reader↔DCIM與PoT↔Writer兩端握手是否相等 |
| RUN_PATCH | Reader/DCIM done可不同拍；12筆post全部接受前座標不得更新 |
| DRAIN_LAYER | 接受最後資料不等於commit；writer_done早到是否保存 |
| FAULT/source_error | 本地gate立即停；source_error由註冊FAULT輸出，避免經backend ready回授 |

raw資料外部接線需同時gate：

```systemverilog
pot_in_valid      = dcim_result_valid && raw_path_enable;
dcim_result_ready = pot_in_ready     && raw_path_enable;
```

請核對**實際端點的組合依賴**，不能只在stub ready獨立時認定整合無回授。

resident metadata由外層單一持有；controller不負責權重載入。PoT輸出channel/last須由FIFO延遲對齊，不能拿目前raw channel當Writer channel。任務失敗後目的層無效，已提交資料不rollback；上層須共同清理所有端點與兩個時脈域。

## 6. 已執行驗證與證據

原實作使用Verilator 5.030，記錄如下：

| 項目 | 結果與範圍 |
|---|---|
| controller lint | PASS；RTL沒有使用警告豁免 |
| controller正常案例 | 5層：3×3、5×4、Conv2 30×15、Conv3 14×6、恢復後無資料停頓3×3 |
| 正常交易 | 420完整patch、5040筆post結果；不含故意中止部分 |
| 非法配置 | 10個，全部正確拒絕 |
| 執行期fault | 11個，全部正確阻擋／鎖定 |
| reset位置 | 7個，未殘留舊命令 |
| 負向期望值 | 故意錯Reader座標，正確失敗且匹配指定訊息 |
| PoT stream | comb/pipeline各768筆，全部256個ROM位址、反壓/FIFO/reset |
| PE engine | PE9/PE8/PE8-pipeline × post comb/pipeline，六組各7 jobs/109 outputs |
| PoT後處理 | 80筆，RNE/ReLU/pool/frame tags |
| S4 lint | PASS；沒有重跑完整S4軟體資料集 |

controller摘要是`layers=5 rejected=10 faults=11 resets=7 patches=435 outputs=5052`。435含中止patch命令；5052含reset前已輸出的12筆，不是435個成功patch。請核對TB計數與報告是否一致。

本機證據（build未納入Git，遠端可能不存在）：

```text
HYBRID_SYSTEM/build/dcim_layer_controller/verification.log
HYBRID_SYSTEM/build/dcim_layer_controller/negative.log
HYBRID_SYSTEM/build/pot_rename_validation.log
HYBRID_SYSTEM/build/pot_rename_regression.log
```

`pot_rename_validation.log`中的controller是較早一輪；最終controller驗證以`verification.log`為準，包含最後加入的無資料停頓與負向期望值案例。

## 7. 重現指令

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid
git status --short
git show --stat 1937648
git diff 1937648^ 1937648 -- HYBRID_SYSTEM PE_COMPARISON
verilator --version

cd HYBRID_SYSTEM
# 使用新目錄避免覆寫原先證據，實際路徑由mktemp輸出。
review_dir=$(mktemp -d /tmp/kws-s5c-review.XXXXXX)
make lint-dcim-layer-controller test-dcim-layer-controller > "$review_dir/controller.log" 2>&1
controller_status=$?
make test-pot-stream test-pot-engine test-postprocess-pot lint-s4 > "$review_dir/rename.log" 2>&1
rename_status=$?
printf 'controller=%s rename=%s logs=%s\n' "$controller_status" "$rename_status" "$review_dir"
```

等命令結束再檢查log；記錄兩個退出碼。負向測試必須因指定座標錯誤失敗，不能因build error/timeout失敗就當PASS。若未安裝工具或未執行，明確寫「未獨立重跑」。

改名檢查可使用`git grep -n pe_pot_result_stream`；歷史遷移文件提到舊名屬正常，不代表有未修正的實例。對SV/Tcl/Makefile來源引用逐一判斷，且不要改寫build snapshots。

## 8. 工作樹差異與限制

原驗證在包含使用者未提交修改的工作樹完成，例如pot_result_stream的空白差異、argmax及其他後處理內容。提交只包含本次變更，未包含這些無關內容；不能據此宣稱乾淨checkout已獨立通過。若需比較請另建worktree，不得reset/checkout清除使用者變更。

本次沒有RTL形式驗證、四態X測試、coverage百分比、Vivado、板測或完整軟體golden。協定TB沒有真實RAM/DCIM/PoT端點，其stub done可以刻意比實際端點更早；這是壓力測試，不是實際電路cycle效能證據。

請特別指出尚缺哪些測試：忙碌時新命令、合法最高地址、重複done、額外輸入／輸出、各非RUN狀態錯誤、fault部分commit、真實端點連接／組合迴圈。這些是待審查的覆蓋缺口，不應從已有測試數量推論已全部測過。

## 9. Claude 回覆格式

1. 實際閱讀檔案、版本、工作樹差異與實際執行命令。
2. 功能與規劃符合性：符合／部分符合／不符合，限定結論範圍。
3. 問題表：嚴重度、類別、檔案:行號、觸發條件、影響、最小修正與追加測試。
4. 冗餘評估：哪些狀態/暫存器可省、成立條件與失去的防護；不以狀態少保證面積小。
5. 改名完整性與行為保持結論。
6. 能否進入真實整層整合，及必須先處理的阻擋項。

沒有找到確定錯誤時，請寫「在已審查範圍內未找到確定功能錯誤」，並保留剩餘風險，不寫「保證無誤」或「保證125MHz」。

## 10. 審查後 V1～V6 補測交接（2026-10-15）

本輪只修改以下五份檔案，**沒有改controller、PoT或其他RTL**：

1. `HYBRID_SYSTEM/tb/control/tb_dcim_layer_controller.sv`
2. `HYBRID_SYSTEM/Makefile`
3. `HYBRID_SYSTEM/docs/DCIM_LAYER_CONTROLLER.md`
4. `HYBRID_SYSTEM/docs/SINGLE_BUFFER_ARCHITECTURE.md`
5. 本交接文件。

新增`nonrun_fault` task以公開交易到達四個目標狀態，內部state只讀確認，不force；每狀態注入五種錯誤，相關ready設高，核對無額外命令/資料握手且fault鎖定。`duplicate_or_excess`先核對count/done_seen，隔離重複done與超量條件。Writer的重複done以連續兩個edge高電位表示，第二次在DRAIN仍屬同一任務。

`boundary_mode`讓正常run_layer覆蓋來源/目的終點32768與反向相鄰，確實執行完整108/12交易，不只檢查CONFIG接受。`busy_probe`在六個位置送錯命令，保持三拍後在IDLE之前撤銷，檢查命令接受計數未增加且原層完整完成。`+CORRUPT_WRITER`破壞Writer x期望，Makefile確認指定錯誤訊息及非零退出。

實測命令：`make lint-dcim-layer-controller test-dcim-layer-controller`，Verilator5.030、退出0、無Warning/Error。原有案例保留，結果：

```text
PASS extensions nonrun_faults=20 duplicate_done=3 excess=2 boundaries=3 busy_probes=6
PASS dcim_layer_controller layers=9 rejected=10 faults=11 resets=7 patches=454 outputs=5184
PASS expected controller coordinate rejection
PASS expected controller Writer coordinate rejection
```

本機最新證據為`HYBRID_SYSTEM/build/dcim_layer_controller/verification_v1_v6.log`，負向log為同目錄`negative.log`與`negative_writer.log`；原verification.log保留第一批證據。完整計數分解見[DCIM_LAYER_CONTROLLER.md第7節](DCIM_LAYER_CONTROLLER.md)。新增fault獨立計數，不能把摘要faults=11誤讀為本輪只有11個fault測試。

請再次核對：V1是否真正在指定狀態注入；V2/V3是否先滿足count/done_seen前提；非法交易是否真的被阻擋；V4端點與相鄰區域是否正確；V5沒有誤把持續valid到IDLE應接受的新命令當錯誤；V6不是因其他原因失敗。

仍未涵蓋真實RAM部分commit、實際端點整合／UNOPTFLAT、完整Conv2/3軟體數值與Vivado。此次沒有重跑PoT/PE改名回歸，舊PASS是歷史結果，不是本輪執行。
