# S5-A：單筆權重寫入與單patch DCIM backend

日期：2026-10-13。這是固定K=108、12 filters、UINT8 zp128、signed INT8權重、無bias的第一版。S5-B CDC、S5-C整層Reader/Writer/後處理、S5-D FULL仍未完成。不是已通過Vivado或板測的宣告。

## 1. 本次檔案與邊界

- 新增 `rtl/dcim_adapter/kws_dcim_backend.sv`：九狀態控制與資料暫存。
- 新增 `tb/integration/tb_kws_dcim_backend.sv`：真正master與chip，無cell預載、無算術回應stub。
- 更新Makefile與架構基準；原有測試保留。
- 沿用 `dcim_u8_offset_correction.sv`；不改chip、master、CDC及FULL控制器。
- 工作樹中原有其他修改不屬本次提交。

## 2. 整體連接

```mermaid
flowchart TD
 W[1296筆signed權重] --> B[Backend：編碼/映射/48份weight sum]
 A[108筆UINT8 activation] --> T[Backend：32-byte tile與activation sum]
 T --> B
 B --> L[cmd/rsp握手介面]
 L --> M[dcim_pin_master]
 M --> C[真實dcim_chip_pin_top]
 C --> M
 M --> L
 L --> R[even/odd重組及既有修正器]
 R --> P[12份INT32跨group partial sums]
 P --> O[12筆結果：filter_id/data/last]
```

Backend本身不實例化master/chip，不綁定時脈頻率。TB的同時脈轉接器保存/延遲真實master回應；S5-B才改接既有CDC。此TB不是CDC驗證。CIM chip input buffer僅32 bits；backend tile則32 bytes，不得混稱。Backend為同步reset，原master/chip包含非同步reset，因此整合TB針對共同reset關閉SYNCASYNCNET警告；獨立backend lint不關閉此警告。

## 3. 外部協定

| 介面 | 規格 |
|---|---|
| clk/rst | backend同步active-high reset；transport/master/chip須共同reset，不能只reset backend後接舊回應 |
| load_valid/ready | 開始整層載入；同時load與patch時load優先 |
| weight_valid/ready/data | signed8，filter→channel→kernel row→kernel col，1296筆；valid等待ready時資料必須穩定 |
| load_done | 最後padding寫入成功回應的正緣後脈衝，不是外部第1296筆接受時 |
| weights_ready | 只有整層1536筆write成功後有效；load開始/reset/fault失效 |
| patch_valid/ready | 只有權重有效且IDLE才接受；沒有權重時ready=0，並非自動進FAULT |
| activation_valid/ready/data | UINT8，c→u→v，108筆；計算期間ready=0 |
| result_valid/ready/data/filter_id/last | signed32、filter0→11；反壓時保持；last只在valid時解讀 |
| patch_done | 第12筆結果握手後脈衝；不代表後處理或RAM commit |
| source_error | sticky FAULT入口，停止新傳輸；已發出的master操作可能完成，需共同reset清除 |
| busy/error | 非IDLE為busy；FAULT的error保持至reset |
| cmd/rsp | 一筆在途；operation=0 write、2 CIM；欄位對齊既有CDC；不使用SRAM read回應欄位 |

固定計數協定沒有tlast：上層須恰好提供1296/108筆。缺資料會等待；額外資料不會在非接收狀態握手。未加入硬體timeout/長度錯誤偵測；TB有watchdog。下一階段若需可變長度或timeout須另外規劃。

## 4. Mapping、padding及運算

有效權重 `k=9c+3u+v`，實體row=k、pair=f。每個filter依序寫row0..107，再自行寫row108..127=128，然後換filter。共1296有效bytes+240 padding=1536次單筆write；pair12..15不使用。

`Wu=Ws+128` 在8-bit二補數編碼等價於反轉MSB；不是直接reinterpret signed byte。每個write成功回應才將byte加進對應group/filter的13-bit ΣWu（最大8160）。write成功可以沒有rsp_data_valid；CIM成功必須有rsp_data_valid。

每patch：讀32、算12pairs→讀32、算12pairs→讀32、算12pairs→讀12補20、算12pairs。48次CIM命令；同一tile在backend保留，但每次master命令仍完整LOAD八個planes。每組ΣAu也是13-bit。

進最後group時tile[12..31]平行設128，ΣAu初始化2560；不花20拍填activation padding。這是FF tile設計，不宣稱能以單埠BRAM同拍写20地址。

$$U=odd+(even\ll4)$$

先將兩份18-bit结果zero-extend到32位再左移。修正器計算：

$$P=U-128\Sigma A_u-128\Sigma W_u+16384\times32.$$

12份signed32 ACC各自累加四個P，等於 `Σ(Au−128)Ws`。33-bit加法檢查signed overflow，任何修正/累加overflow進FAULT。輸出raw INT32，不做量化或ReLU。

## 5. 九個主要狀態

| 狀態 | 動作／轉移 |
|---|---|
| IDLE | 接受load時清sum/index；接受patch時清12份ACC/index；沒有獨立INIT拍 |
| W_PREPARE | 接收有效權重，或產生一筆padding byte |
| W_SEND | 保持write命令到握手 |
| W_WAIT | 等成功回應，更新sum與row/filter；最後一筆直接done+IDLE |
| A_FILL | 接收一個tile；最後group只接12筆 |
| C_SEND | 保持CIM命令至握手 |
| C_WAIT | 先等回應、再等registered修正結果；correction_pending區分兩階段 |
| EMIT | 按ready輸出12筆；最後一筆直接done+IDLE |
| FAULT | 停止新操作並撤銷weights_ready，直到reset |

```mermaid
flowchart TD
 I[IDLE] -->|load| WP[W_PREPARE]
 WP --> WS[W_SEND]
 WS --> WW[W_WAIT]
 WW -->|下一筆| WP
 WW -->|1536筆完成| I
 I -->|patch且權重有效| A[A_FILL]
 A --> CS[C_SEND]
 CS --> CW[C_WAIT：回應/修正/累加]
 CW -->|下一pair| CS
 CW -->|下一group| A
 CW -->|四組完成| E[EMIT]
 E -->|第12筆握手| I
 WW -->|error| F[FAULT]
 CW -->|error/缺data/overflow| F
```

減少的是獨立INIT/NEXT/DONE狀態；C_WAIT旗標仍是控制狀態，不因enum少就保證省FF。沒有未精簡版本的實測對照，因此不宣稱特定面積或加速率。既有修正器無ready，C_WAIT保證逐筆接收它的valid。

## 6. 驗證方式

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM
make lint-dcim-backend
make test-dcim-backend
```

固定兩個seed：505、128，同時傳入`+verilator+seed+N`讓不同process的隨機串流使用指定全域seed。命令隨機停頓，真實master回應再延遲0..4拍，權重/activation來源插入空拍，結果端插入反壓。driver在negedge改訊號，monitor在posedge檢查握手；watchdog拒絕永久等待。另有`+CORRUPT_GOLDEN`將參考結果故意加1，必須以result mismatch失敗，不能把任意失敗當成通過。

每seed驗證：

- 3次成功整層load：每次1296外部權重、1536實際write回應；每一命令檢查地址與編碼。
- 前兩層逐byte透過真實SRAM read讀回1536筆，共3072筆，包含padding。debug read僅在backend閒置、master完成時使用TB mux，不是新硬體介面。
- 6個patch：圖樣、zp128全零、activation全0/255、隨機；權重涵蓋−128、127、0與隨機負值。
- 每patch48次CIM，全部比對group/pair、32 bytes、raw even/odd；12筆INT32對獨立108項signed dot product，不以DUT修正公式作唯一golden。
- 一份權重連續計算多patch；整層重載改變權重。
- stalled命令及結果穩定；load/patch互斥；load_done與patch_done不可提前。
- source_error、真實write完成後注入transport error、CIM缺data_valid、在途write共同reset及重新載入恢復。

測試使用合成可執行的真實chip RTL，不預載cell、不force內部狀態。這批為演算法/協定測試資料，尚非軟體模型checkpoint的端到端Conv2/3 golden。

## 7. 驗證結果與限制

2026-10-13實測：

| 檢查 | 結果 |
|---|---|
| `make lint-dcim-backend` | PASS，獨立backend與修正器的`-Wall` lint |
| `make test-dcim-backend` seed505 | PASS：3 loads、3072 byte readbacks、6 patches、288成功CIM命令、72筆INT32 |
| 同上seed128 | PASS：相同檢查數量、不同隨機停頓/資料 |
| corrupted golden | 正確以`result mismatch`拒絕；Make入口整體成功 |
| `make test-dcim-offset` | PASS：302筆輸出及reset/bubble |
| CIM_CHIP的`make test-bitserial-accumulator test-dcim-pin-master` | PASS：既有ACC/serial及write/read/burst/A4/A8 master整合回歸 |

成功完整案例兩seed合計：6次load、9216次成功write、6144筆readback、12個patch、576次成功CIM、144筆INT32。另有故障注入及中斷交易，不混入成功計數。

| seed | 三次load clocks | 六個patch clocks（依測試順序） |
|---|---|---|
| 505 | 15788 / 15793 / 15729 | 5017 / 4994 / 5012 / 4999 / 5038 / 5035 |
| 128 | 15905 / 15861 / 15821 | 4998 / 5017 / 4995 / 5016 / 5030 / 5022 |

以上是TB从發起操作到觀察完成的同時脈cycle數，包含隨機source/transport/result停頓與測試取樣邊界；不是無停頓最低延遲，更不是125/53MHz的跨域量測。沒有舊backend比較基線，不宣稱精簡FSM降低了多少面積/時間。

Vivado synthesis/implementation、PYNQ-Z2上板與真正軟體Conv2/3完整golden尚未執行。報告不得將lint當成Vivado合成，或單時脈test當成CDC通過。

S5-B：接既有CDC、雙時脈reset與握手驗證。S5-C：真實軟體Conv2/3完整patch、PoT/ReLU/Pool與CHW commit。S5-D：FULL及Argmax。目前不開放FULL。
