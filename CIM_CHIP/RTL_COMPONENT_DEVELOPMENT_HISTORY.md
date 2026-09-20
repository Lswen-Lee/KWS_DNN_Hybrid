# CIM_CHIP RTL 元件開發歷程與建構順序

本文件整理 `CIM_CHIP` 從最底層儲存 cell 到完整128×128 array的實作順序、每個元件的功能、上下層關係與驗證方式。詳細測試案例與完整指令另見 [`TB_VERIFICATION_GUIDE.md`](./TB_VERIFICATION_GUIDE.md)。

主要架構依據：

- `/home/LAB505/projects/KWS/0622.pptx`
- `/home/LAB505/projects/KWS/5_27.pptx`
- `/home/LAB505/projects/KWS/Proposal_for_ITRI_NVM.docx`

## 1. 為什麼採用由小到大的實作順序

DCIM 是高度重複的階層式結構。如果一開始直接建立128×128 array，錯誤可能同時來自cell儲存、NOR計算、adder tree、decoder、Input Path或accumulator，很難定位。因此目前採用下列順序：

```text
1-bit storage cell
        ↓
1-bit DCIM compute cell
        ↓
4-bit weight row
        ↓
32-row × 4-bit segment/bank
        ↓
address decoder與mode routing
        ↓
Input Path與output selection
        ↓
bit-serial accumulation
        ↓
128×128 array
        ↓
chip macro core
        ↓
read serializer與pin top（下一階段）
```

每完成一層，就先建立獨立testbench，確認正確後才讓上一層重複實例化它。這樣可以保留L0、L1及後續每一層的回歸測試。

## 2. 目前整體資料流

### 2.1 SRAM權重寫入路徑

```text
Din[3:0]
   ↓ 每個bufclk載入4 bits
input_buffer_32x4的前兩級DFF
   ↓ 兩個clock組成8 bits
sram_write_buffer_8bit
   ↓ write_data[7:0]
bank_decoder_4to16 + bank_pair_selector
   ↓ 選擇一對相鄰32×4 segments
row_decoder_7to128
   ↓ 選擇一條WL
兩個dcim_bank_32x4
   ↓ write_en有效時
每個cell儲存1-bit weight
```

上述元件現已由`dcim_macro_core`統一接線，並以整合testbench驗證兩個Input Buffer clocks加一個write clock的權重寫入流程。外部實體pad與SRAM serial read仍留給`dcim_chip_pin_top`及後續read serializer。

### 2.2 CIM計算路徑

```text
Din[3:0]
   ↓ 8個clock
input_buffer_32x4：形成32個activation bits
   ↓ one-to-four fanout
cim_group_decoder_2to4：選擇一個32-row group
   ↓
bank_decoder_4to16 + bank_pair_selector：選擇一對segments
   ↓
dcim_cell_logic：activation bit × stored weight bit
   ↓
dcim_row_4bit：形成一個4-bit row product
   ↓ 32 rows parallel
adder_tree_32x4：輸出9-bit partial sum
   ↓
bank_output_or_tree：分別選出even/odd partial sums
   ↓
兩個bitserial_accumulator：整合8個activation bit-planes
   ↓
18-bit even/odd results
   ↓
serial_output：兩路MSB-first平行轉序列
   ↓
sume / sumo
```

## 3. 已完成元件的實作順序

### 步驟1：建立1-bit FeSRAM儲存模型

檔案：[`cell/fesram_cell_model.sv`](./cell/fesram_cell_model.sv)

目的：先建立所有權重儲存的最小單位。

目前功能：

- 使用一個FF儲存1-bit權重。
- `write_en=1`時，在`clk`上升緣寫入`write_data`。
- `write_en=0`時保持原值。
- 同時輸出互補節點`q`與`qb`。
- 保留`nv_store`、`nv_recall`與`pd_en`腳位，方便未來加入FeRAM行為。

目前抽象限制：

- 尚未模擬真正FeSRAM的store、power-down與recall。
- 目前只代表可合成的1-bit數位儲存行為。

驗證指令：

```bash
make test-fesram
```

### 步驟2：建立1-bit DCIM計算cell

檔案：[`cell/dcim_cell_logic.sv`](./cell/dcim_cell_logic.sv)

目的：把1-bit儲存值與1-bit activation組成最小乘法單元。

計算式：

```text
IN_b = ~(cim_en & cim_row & activation_bit)
cim_product = ~(IN_b | QB)

啟用時等價於：
cim_product = activation_bit & stored_weight_bit
```

目前功能：

- 內部實例化一個`fesram_cell_model`。
- 使用儲存節點`QB`與外部產生的`cim_input_b`進行NOR計算。
- 未啟用時輸出0，使其能安全送入後續adder tree。

與講義關係：

- 對應Proposal中FeSRAM cell旁的NOR compute gate。
- 實體tri-state在RTL中以「未啟用輸出0」做功能等效抽象。

驗證指令：

```bash
make test-dcim-cell
```

### 步驟3：用4個cell組成一列4-bit weight

檔案：[`segment/dcim_row_4bit.sv`](./segment/dcim_row_4bit.sv)

目的：建立一筆unsigned 4-bit weight的儲存與計算單位。

結構：

```text
同一個activation_bit
        │
        ├── cell bit0，權重1
        ├── cell bit1，權重2
        ├── cell bit2，權重4
        └── cell bit3，權重8

row_product[3:0] = activation_bit ? stored_weight : 4'b0000
```

目前功能：

- 4個`dcim_cell_logic`儲存一個4-bit weight。
- 共享`cim_en`、`cim_row`及`activation_bit`。
- 只產生一次共用`cim_input_b`，再送給4個cell。
- `sense_en=1`時可讀出該列4-bit權重；未選擇時輸出0。

後續修改：

- 原始版本只有寫入與CIM計算。
- 後來加入`sense_en`與`read_data`，提供SRAM read功能。
- 這裡的read仍是理想組合式模型，沒有precharge與sense-amplifier類比行為。

驗證指令：

```bash
make test-row
```

### 步驟4：建立32輸入平衡Adder Tree

檔案：[`segment/adder_tree_32x4.sv`](./segment/adder_tree_32x4.sv)

目的：將32列的4-bit row products相加，得到一個segment的partial sum。

五級結構：

```text
32個4-bit
   ↓ Level 1
16個5-bit
   ↓ Level 2
 8個6-bit
   ↓ Level 3
 4個7-bit
   ↓ Level 4
 2個8-bit
   ↓ Level 5
 1個9-bit bank_sum
```

數值範圍：

```text
最小值 = 0
最大值 = 32 × 15 = 480
```

與講義關係：

- 對應32×4 Segment後方的adder tree。
- RTL驗證數值與位寬，不模擬layout、gate delay及佈線負載。

驗證指令：

```bash
make test-adder
```

### 步驟5：整合32×4 DCIM Bank/Segment

檔案：[`segment/dcim_bank_32x4.sv`](./segment/dcim_bank_32x4.sv)

目的：把32個4-bit rows與一棵adder tree組成簡報中的基本32×4 Segment。

結構：

```text
32 × dcim_row_4bit
        ↓ 32個4-bit row_product
adder_tree_32x4
        ↓
9-bit bank_sum
```

目前功能：

- `row_write_en[31:0]` one-hot選擇寫入列。
- `row_read_en[31:0]` one-hot選擇讀出列。
- `activation_bits[31:0]`同時驅動32列進行CIM計算。
- 產生最大480的9-bit partial sum。
- SRAM sense結果採一個clock延遲的RTL模型，並輸出`read_valid`。

重要限制：

- 一個clock的sense延遲是同步RTL建模選擇，不是簡報明確畫出的數位register。
- 尚未模擬`pre_en`、bitline充放電與sense amplifier電壓行為。

驗證指令：

```bash
make test-bank
```

### 步驟6：建立7-to-128 Row Decoder

檔案：[`peripheral/row_decoder_7to128.sv`](./peripheral/row_decoder_7to128.sv)

目的：把手動one-hot row控制改成真正的7-bit位址控制。

結構：

```text
A[2:0] → 3-to-8 low predecoder
A[6:3] → 4-to-16 high predecoder

16 high groups × 8 local rows = 128 WLs
```

目前功能：

- `row_addr[6:0]`選擇128條wordline中的一條。
- `wl_en=0`時關閉全部wordline。
- `wl_en=1`時輸出active-high one-hot `wl_select[127:0]`。
- Decoder本身同時可供SRAM read及write使用；實際讀寫由`write_en`或`sense_en`區分。

驗證指令：

```bash
make test-row-decoder
```

### 步驟7：建立2-to-4 CIM Row Group Decoder

檔案：[`peripheral/cim_group_decoder_2to4.sv`](./peripheral/cim_group_decoder_2to4.sv)

目的：在CIM模式選擇128 rows中的一個32-row group。

對應關係：

| `{A6,A5}` | `cim_row` | Global rows |
|---|---|---|
| `00` | `0001` | 0～31 |
| `01` | `0010` | 32～63 |
| `10` | `0100` | 64～95 |
| `11` | `1000` | 96～127 |

此模組只負責位址解碼；真正是否計算仍由獨立的`cim_en`控制。

驗證指令：

```bash
make test-cim-group-decoder
```

### 步驟8：建立第一版32-bit Input Buffer

檔案：[`peripheral/input_buffer_32x4.sv`](./peripheral/input_buffer_32x4.sv)

目的：先驗證四條Din lane是否能以8個clock形成32個CIM activation bits。

第一版採用簡化表示：

```text
shift_en控制32-bit shift register
        ↓
四份相同的32-bit CIM fanout
```

第一版已驗證reset、clock enable、8次nibble載入與四個row-group fanout，但尚未包含第3頁畫出的`sel_next`及`mode_sel` demux。後續逐項重讀Input Path圖與波形後，在步驟13完成重構。這項演進也說明：先建立最小資料儲存功能，再補齊講義控制路徑，可以把shift錯誤與mode-routing錯誤分開定位。

### 步驟9：建立4-to-16 Bank Decoder

檔案：[`peripheral/bank_decoder_4to16.sv`](./peripheral/bank_decoder_4to16.sv)

目的：使用簡報中的`B[3:0]`，在目前選定的32-row group中選擇16組相鄰segment pairs。

目前功能：

```text
bank_addr = N
    ↓
bank_select[N] = 1，其餘為0
```

這個decoder不判斷SRAM或CIM mode；模式分流由下一個`bank_pair_selector`負責。

驗證指令：

```bash
make test-bank-decoder
```

### 步驟10：建立SRAM/CIM Bank Pair Selector

檔案：[`array/bank_pair_selector.sv`](./array/bank_pair_selector.sv)

目的：把16條bank decoder輸出依`mode_sel`分流到SRAM或CIM路徑。

一個pair包含：

```text
pair p：
even segment = 2p
odd segment  = 2p+1

兩個32×4 segments合計形成8-bit資料路徑
```

控制式：

```text
cim_pair_en  = bank_select & mode_sel
sram_pair_en = bank_select & ~mode_sel
```

其中`mode_sel=0`為SRAM，`mode_sel=1`為CIM。

驗證指令：

```bash
make test-bank-pair-selector
```

### 步驟11：建立Even/Odd Bank Output OR Tree

檔案：[`array/bank_output_or_tree.sv`](./array/bank_output_or_tree.sv)

目的：從16組pair輸出中，分別取出被選擇的even與odd 9-bit partial sums。

結構：

```text
16個even sums → 4組OR4 → 1組OR4 → selected_even_sum
16個odd sums  → 4組OR4 → 1組OR4 → selected_odd_sum
```

正常操作只有一個pair有效，其他bank輸出0，因此簡報使用OR tree而不是算術加法器或priority mux。

Even與Odd維持兩條獨立路徑，之後各自進入accumulator。如果兩個4-bit segments代表同一個8-bit weight，最終才依mapping組合：

```text
result_8bit_weight = low_acc + (high_acc << 4)
```

目前講義沒有明確指定even或odd固定是哪一個nibble，因此這項對應尚未寫死。

驗證指令：

```bash
make test-bank-output-or-tree
```

### 步驟12：建立Unsigned Bit-Serial Accumulator

檔案：[`peripheral/bitserial_accumulator.sv`](./peripheral/bitserial_accumulator.sv)

目的：將UINT8 activation的8個bit-plane partial sums整合成完整數值。

每次`output_en=1`且`bufclk`上升時：

```text
ACC_next = (ACC << 1) + partial_sum
```

外部controller必須依MSB-first送入8筆partial sums：

```text
activation bit7 → bit6 → ... → bit0
```

目前設計原則：

- Accumulator只做shift-and-add。
- 不在內部加入`sample_count`、`valid`或自動停止。
- 外部controller精確產生8次`output_en`。
- Even與Odd各需要一個accumulator實例。
- 輸出寬度為18-bit，符合簡報規格。

數值範圍：

```text
單一bit-plane最大partial sum = 480
UINT8最大累加結果 = 480 × 255 = 122400
18 bits足以表示
```

驗證指令：

```bash
make test-bitserial-accumulator
```

### 步驟13：依0622第3頁重構Input Path

檔案：

- [`peripheral/input_buffer_32x4.sv`](./peripheral/input_buffer_32x4.sv)
- [`peripheral/sram_write_buffer_8bit.sv`](./peripheral/sram_write_buffer_8bit.sv)

原始版本只有簡化的32-bit shift register與四份fanout。重新閱讀 `0622.pptx` 第3頁後，加入DFF階層、`sel_next` demux與`mode_sel` demux。

#### 13.1 DFF Input Chain

```text
4 Din lanes × 8 DFF stages = 32 bits
```

每個有效clock輸入4 bits：

```text
stage0 → local rows  0～3
stage1 → local rows  4～7
...
stage7 → local rows 28～31
```

控制定義：

```text
clk_en=1, sel_next=0：DFF chain前進
sel_next=1：停止shift並送出各級tap
mode_sel=0：SRAM mode
mode_sel=1：CIM mode
```

#### 13.2 SRAM 8-bit Write Path

第3頁只有每條lane的前兩級DFF後方具有`mode_sel` demux：

```text
2 stages × 4 lanes = 8 bits
```

所以`sram_write_buffer_8bit`沒有再加入8個FF，只組合既有tap：

```text
write_data = {stage1_bits, stage0_bits}
```

以簡報第12頁的`9`、`1`為例：

```text
Clock 1：Din=9 → stage0=9
Clock 2：Din=1 → stage1=9、stage0=1
Clock 3：下游write_en將8'h91寫入SRAM
```

#### 13.3 CIM 32-bit Fanout

8個clock載入32 bits後，`sel_next=1, mode_sel=1`將資料送到四個32-row groups：

```text
Group 0：global rows   0～31
Group 1：global rows  32～63
Group 2：global rows  64～95
Group 3：global rows  96～127
```

第3頁只在前兩級畫出`mode_sel` demux，所以RTL也只對local rows 0～7做mode gating；SRAM mode時其餘CIM wires可能仍有0/1，但系統必須用下游`cim_en=0`禁止計算。

驗證指令：

```bash
make test-input-buffer
make test-sram-write-buffer
```

### 步驟14：整合32×128 DCIM Row Group

檔案：[`array/dcim_row_group.sv`](./array/dcim_row_group.sv)

目的：依`0622.pptx`第2頁，把32個`dcim_bank_32x4`組成一個共享IN0～IN31的32-row group。

結構：

```text
一個row group
    = 32個32×4 segments
    = 16組even/odd pairs
    = 32 rows × 128 columns
    = 4096個1-bit cells
```

每個pair `p`包含：

```text
even segment = 2p
odd segment  = 2p+1
```

SRAM寫入必須同時具備：

```text
local_wl_select
& write_en
& sram_pair_en[p]
```

CIM計算則必須同時具備：

```text
cim_pair_en[p]
& cim_group_en
& activation_bits[row]
```

這與第4～5頁NOR input的`cim_en`、`cim_row`及`IN`三輸入控制一致。

SRAM read在Row Group內先從16組Pairs完成選擇，對外只保留
`selected_even_read_data[3:0]`、`selected_odd_read_data[3:0]`與
`selected_pair_read_valid`。這避免把32組bank read buses一路送到Array，
同時保持講義中一次讀取相鄰Even/Odd兩個4-bit banks的行為。

本層輸出32路原始9-bit `bank_sum`，沒有放入全域Output OR tree或Accumulator。原因是第2頁的`bank00/bank10/bank20/bank30`顯示相同bank位置分布於四個row groups；上一層Array先把四組相同位置合併，再執行第6頁的even/odd OR selection。

驗證涵蓋：

- pair 0與pair 15邊界寫讀。
- local row 0與31邊界。
- SRAM pair隔離及資料保留。
- `cim_pair_en`與`cim_group_en`雙重gating。
- SRAM/CIM控制互不誤觸。
- even/odd partial sums保持分離。
- 每個32×4 Segment最大值`32×15=480`。

驗證指令：

```bash
make test-row-group
```

### 步驟15：整合完整128×128 DCIM Array

檔案：[`array/dcim_array_128x128.sv`](./array/dcim_array_128x128.sv)

目的：依`0622.pptx`第2頁及Proposal Figure 4，把四個32×128 row groups組成完整16384-cell array，並接上第6頁的even/odd Output OR tree。

結構：

```text
4個32×128 row groups
    = 128 rows × 128 columns
    = 128個32×4 segments
    = 16384個1-bit cells

group 0 ← wl_select[31:0]
group 1 ← wl_select[63:32]
group 2 ← wl_select[95:64]
group 3 ← wl_select[127:96]
```

四個groups的相同segment位置先合併：

```text
merged_bank_sum[n]
    = group0.bank_sum[n]
    | group1.bank_sum[n]
    | group2.bank_sum[n]
    | group3.bank_sum[n]
```

合法操作一次只允許一個`cim_group_select`及一個`cim_pair_en`有效，因此未選路徑為0。合併後，偶數segments與奇數segments分別送入兩棵`bank_output_or_tree`，輸出兩個獨立9-bit partial sums。Array沒有加入Accumulator，也沒有假設even/odd哪一側是8-bit weight的high nibble。

驗證涵蓋：

- global rows 0、32、64、96與127的四group及上界接線。
- pair 0與pair 15的column邊界。
- 四個groups的SRAM資料隔離與readback。
- 四個CIM group逐一選擇及activation fanout隔離。
- 跨group相同bank位置合併與even/odd OR tree。
- 最大partial sum `32×15=480`。
- SRAM/CIM pair控制隔離。

驗證指令：

```bash
make test-array-128
```

### 步驟16：建立Even/Odd Serial Output

檔案：[`peripheral/serial_output.sv`](./peripheral/serial_output.sv)

目的：把兩個18-bit Accumulator的平行結果轉成簡報中的 `sume`、`sumo` serial outputs。

結構：

```text
even_parallel_sum[17:0] → 18-bit shift register → sume
odd_parallel_sum[17:0]  → 18-bit shift register → sumo
```

操作順序：

```text
第8筆output_en完成
        ↓ 下一個bufclk令serial_load=1
同時載入even/odd 18-bit結果
        ↓
先輸出bit 17
        ↓ 每個bufclk自動左移
依序輸出bit 16 ... bit 0
        ↓
shift register補0，輸出回到0
```

講義中的 `acc` block同時包含累加與 `sosum` serial output；目前RTL刻意拆成 `bitserial_accumulator` 與 `serial_output`，使算術與輸出順序能分開測試。`serial_load`是兩模組間的core內部交接訊號，不是新增的外部chip pin。

MSB-first方向可由講義7200範例波形交叉核對：

```text
7200 = 18'b000001110000100000
```

輸出先出現前導0，再出現連續三個1，之後有單一1，與投影片`sume`波形位置一致。

驗證涵蓋：

- Active-low reset及串流中reset。
- 講義7200範例的18-bit輸出順序。
- Even/odd兩路使用不同pattern，確認不交換、不合併。
- `serial_load`優先於shift。
- 18 bits後zero-fill。

驗證指令：

```bash
make test-serial-output
```

### 步驟17：整合DCIM Macro Core

檔案：[`chip/dcim_macro_core.sv`](./chip/dcim_macro_core.sv)

目的：對應Proposal Figure 4與`0622.pptx`第2～6頁，把已驗證的內部數位模組連成一次完整write/read/CIM/output資料流程。

整合結構：

```text
Input Buffer
    ↓
A[6:0] Row Decoder + A[6:5] Group Decoder
B[3:0] Bank Decoder + SRAM/CIM Pair Selector
    ↓
128×128 DCIM Array
    ↓
even/odd 9-bit partial sums
    ↓
two 18-bit Bit-Serial Accumulators
    ↓
Serial Output
    ↓
sume / sumo
```

Macro Core只做結構整合，沒有加入隱藏FSM。外部controller仍需控制：

- 兩個nibble loading clocks及一個SRAM write clock。
- UINT8每個bit-plane的8個Input Buffer clocks。
- 每個bit-plane一次`output_en`。
- 八個bit-planes結束後一次`serial_load`。

Reset分成三個domains：

```text
model_rst_n  → Input Buffer及weight Array
acc_rst_n    → even/odd Accumulators
serial_rst_n → sume/sumo shift registers
```

這樣開始新MAC時只清Accumulator，不會把Array內的模擬權重清除。講義`reset1/reset2`的最終映射仍留給chip pin top確認。

8-bit權重mapping已在本層明確定義：

```text
第一個/high nibble → even segment
第二個/low nibble  → odd segment
```

整合驗證使用：

```text
row0 weight = A5，activation = 3
row1 weight = 32，activation = 2

even = 3×10 + 2×3 = 36
odd  = 3×5  + 2×2 = 19
```

testbench依MSB-first送入八個UINT8 bit-planes，逐拍檢查partial sums及Accumulator，最後由`sume/sumo`重建36與19。此外也驗證A=32/B=15邊界與Accumulator reset不會擦除權重。

目前SRAM read輸出仍是兩個平行4-bit資料。未來資料流規劃為：

```text
Macro Core parallel read
    ↓
peripheral/sram_read_serializer_8bit
    ↓
dcim_chip_pin_top：與sumo做pad mux
    ↓
sumo/read共用pin
```

驗證指令：

```bash
make test-macro-core
```

## 4. 目前已完成的階層

| 層級 | 已完成元件 | 狀態 |
|---|---|---|
| Cell | `fesram_cell_model` | 已完成數位FF抽象與TB |
| Cell | `dcim_cell_logic` | 已完成1-bit NOR計算與TB |
| Segment | `dcim_row_4bit` | 已完成4-bit write/read/compute與TB |
| Segment | `adder_tree_32x4` | 已完成五級加法與TB |
| Segment | `dcim_bank_32x4` | 已完成32×4整合與TB |
| Peripheral | `row_decoder_7to128` | 已完成與TB |
| Peripheral | `cim_group_decoder_2to4` | 已完成與TB |
| Peripheral | `bank_decoder_4to16` | 已完成與TB |
| Peripheral | `input_buffer_32x4` | 已依0622第3頁重構並完成TB |
| Peripheral | `sram_write_buffer_8bit` | 已完成與TB |
| Peripheral | `bitserial_accumulator` | 已完成與TB |
| Peripheral | `serial_output` | 已完成雙路18-bit MSB-first輸出與TB |
| Array | `bank_pair_selector` | 已完成與TB |
| Array | `bank_output_or_tree` | 已完成與TB |
| Array | `dcim_row_group` | 已完成32×128結構整合與TB |
| Array | `dcim_array_128x128` | 已完成128×128結構整合與TB |
| Chip | `dcim_macro_core` | 已完成write/read/CIM/serial資料路徑整合與TB |

目前共有23份testbench，執行：

```bash
make test
make lint
```

目前結果：

```text
23份testbench全部PASS
simulation lint通過
-DSYNTHESIS可合成語法lint通過
```

這代表目前約定的數位128×128 DCIM、Chip Pin Top、Pin Master與CDC介面已通過RTL功能驗證；不代表已模擬FeFET電性，也不代表完整KWS推論系統已完成。

## 5. 尚未完成的元件

目前只有下列CIM_CHIP範圍內的module仍是空殼：

| 建議順序 | 元件 | 未來功能 |
|---:|---|---|
| 1 | `peripheral/nv_power_controller.sv` | 控制SET、store、power-down與recall流程 |

`sram_read_serializer_8bit`、`dcim_chip_pin_top`、`dcim_pin_master`與
`dcim_cdc_bridge`均已完成。Window generator、layer controller與KWS backend
屬於`../HYBRID_SYSTEM`，不再列為CIM_CHIP待實作元件。

專案原先規劃的`dcim_pkg.sv`目前尚未建立；等多個top-level模組需要共用位寬、array尺寸及型別時再加入，可避免過早建立尚未穩定的全域參數。

## 6. 建議後續開發順序

若論文範圍需要非揮發行為，CIM_CHIP接下來只需處理：

```text
nv_power_controller
      ↓
technology-specific FeFET / NV behavior model
```

若目標是FPGA數位混合KWS推論，則CIM_CHIP可凍結目前介面，後續直接在
`PE_CHIP`與`HYBRID_SYSTEM`開發。

每一步都應維持目前的規則：

1. 先畫出責任邊界與資料流。
2. 對照講義確定訊號名稱、極性與位寬。
3. 寫最小可合成RTL。
4. 建立該層獨立testbench。
5. 測試正常、邊界、disable及reset狀態。
6. 執行該層單元測試。
7. 執行`make test`確認沒有破壞舊元件。
8. 執行`make lint`檢查模擬與可合成語法。
9. 再把該元件接入上一層。

## 7. 目前最重要的責任邊界

- Cell只儲存1-bit並計算1-bit product，不負責位址與累加。
- Row儲存一個4-bit weight，不負責32-row加總。
- Adder tree只加總一個activation bit-plane，不處理UINT8位權。
- Accumulator只做shift-and-add，不自行計算八個cycle或產生valid。
- Serial output只做兩路18-bit平行轉序列，不自行計數或產生valid。
- Macro Core只整合資料路徑，不自行產生write、bit-plane或serial transaction FSM。
- Decoder只解碼位址，不自行判斷read、write或CIM操作。
- Input buffer只儲存及路由Din，不產生`write_en`或`output_en`。
- Controller必須負責所有操作順序、enable脈波及cycle數。
- Even/Odd的4-bit結果維持分離；8-bit high/low mapping確認後才進行`<<4`組合。

維持這些邊界，可以讓每個模組容易驗證，也避免在底層RTL加入簡報沒有規定的隱藏counter、valid或自動控制行為。

## 8. 2026-08-17 FPGA共享Adder Tree重構

原始版本依講義實體layout，在每個`dcim_bank_32x4`內放置一棵`adder_tree_32x4`，完整Array共形成`4 groups × 32 banks = 128`棵加法樹。由於合法操作一次只選一個row group與一個bank pair，FPGA版本改成先選資料、後做算術：

```text
128 banks的row products
        ↓ cim_pair_en選Pair
每組Even/Odd各32筆product
        ↓ cim_group_select選Group
selected Even/Odd各32筆product
        ↓
2棵共享adder_tree_32x4
        ↓
selected_even_sum / selected_odd_sum
```

修改後的責任邊界：

- `dcim_bank_32x4`只保存32×4權重、提供SRAM read與32筆4-bit row products。
- `dcim_row_group`從16個Pairs中選出一組Even/Odd row-product vectors。
- `dcim_array_128x128`從四個Groups選出有效vectors，並實例化唯一兩棵共享Adder Tree。
- `dcim_macro_core`、兩個Accumulator與chip pins的介面及cycle行為不變。
- `bank_output_or_tree.sv`保留作講義原始Output Path的獨立參考/TB，但不再進入正式Array/Macro合成階層。

這項修改保持合法one-hot操作下的數值等價，但屬於FPGA資源共享最佳化，不代表講義ASIC layout內的128個局部Adder Tree被物理共用。
