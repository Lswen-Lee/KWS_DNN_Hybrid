# CIM_CHIP Testbench 驗證指南

Demo快速展示請見 [DCIM_DEMO_GUIDE.md](./docs/DCIM_DEMO_GUIDE.md)：包含分區波形Tcl、98筆命令順序、腳位控制表、測資公式與預期值、逐clock講稿及三張16:9狀態圖。可執行腳本：[dcim_grouped_wave.tcl](./docs/dcim_grouped_wave.tcl)。

這份文件集中整理所有已建立的SystemVerilog testbench、執行指令、測試內容、講義架構對照與目前已知的RTL抽象差異；元件開發順序另見`RTL_COMPONENT_DEVELOPMENT_HISTORY.md`。

主要對照資料：

- `/home/LAB505/projects/KWS/0622.pptx`
- `/home/LAB505/projects/KWS/5_27.pptx`
- `/home/LAB505/projects/KWS/Proposal_for_ITRI_NVM.docx`

目前共有 **23 份 testbench**：

- Cell 層：2 份
- Segment 層：3 份
- Peripheral 層：8 份
- Array 層：4 份
- Chip整合層：2份
- FPGA控制與板級整合層：4份

完整128×128 array、目前已完成的peripheral元件、`dcim_macro_core`、`dcim_chip_pin_top`、`dcim_pin_master`與`dcim_cdc_bridge`皆具有testbench。尚未完成的`nv_power_controller`不會被`make test`執行。KWS backend、window generator與layer controller已劃歸`../HYBRID_SYSTEM`，不再是CIM_CHIP的待實作模組。

## 1. 執行環境

測試使用 Verilator，Makefile 會以以下主要選項編譯 testbench：

```text
--binary --timing --assert --sv
```

各選項的作用如下：

- `--binary`：將 SystemVerilog testbench 編譯成可直接執行的模擬程式。
- `--timing`：支援 testbench 中的 `#1`、`#5` 與 clock delay。
- `--assert`：啟用 SystemVerilog assertion。
- `--sv`：使用 SystemVerilog 語法。

先進入專案目錄：

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP
```

確認 Verilator 是否存在：

```bash
verilator --version
```

查看 Makefile 提供的全部指令：

```bash
make help
```

## 2. 所有功能模擬指令

### 2.1 完整回歸測試

執行目前全部 23 份 testbench：

```bash
make test
```

`make all` 目前等同於 `make test`：

```bash
make all
```

### 2.2 依層級執行

| 指令 | 執行範圍 | 包含的 testbench |
|---|---|---|
| `make test-cell` | Cell 層 | FeSRAM cell、DCIM cell |
| `make test-segment` | Segment 層 | 4-bit row、adder tree、32×4 bank |
| `make test-peripheral` | Peripheral 層 | row decoder、CIM group decoder、input buffer、SRAM write buffer、bit-serial accumulator、CIM serial output、SRAM read serializer、bank decoder |
| `make test-array` | Array 層 | bank pair selector、bank output OR tree、32×128 row group、128×128 array |
| `make test-chip` | Chip整合層 | DCIM Macro Core與Chip Pin Top完整資料流程 |
| `make test-fpga` | FPGA控制層 | Pin Master、CDC單元測試、CDC整合、單一50 MHz板級Top自測 |

### 2.3 單獨執行一份 testbench

| 指令 | Testbench | 被測模組 DUT |
|---|---|---|
| `make test-fesram` | `tb_fesram_cell_model.sv` | `fesram_cell_model.sv` |
| `make test-dcim-cell` | `tb_dcim_cell_logic.sv` | `dcim_cell_logic.sv` |
| `make test-row` | `tb_dcim_row_4bit.sv` | `dcim_row_4bit.sv` |
| `make test-adder` | `tb_adder_tree_32x4.sv` | `adder_tree_32x4.sv` |
| `make test-bank` | `tb_dcim_bank_32x4.sv` | `dcim_bank_32x4.sv` |
| `make test-row-decoder` | `tb_row_decoder_7to128.sv` | `row_decoder_7to128.sv` |
| `make test-cim-group-decoder` | `tb_cim_group_decoder_2to4.sv` | `cim_group_decoder_2to4.sv` |
| `make test-input-buffer` | `tb_input_buffer_32x4.sv` | `input_buffer_32x4.sv` |
| `make test-sram-write-buffer` | `tb_sram_write_buffer_8bit.sv` | `sram_write_buffer_8bit.sv` |
| `make test-bitserial-accumulator` | `tb_bitserial_accumulator.sv` | `bitserial_accumulator.sv` |
| `make test-serial-output` | `tb_serial_output.sv` | `serial_output.sv` |
| `make test-sram-read-serializer` | `tb_sram_read_serializer_8bit.sv` | `sram_read_serializer_8bit.sv` |
| `make test-bank-decoder` | `tb_bank_decoder_4to16.sv` | `bank_decoder_4to16.sv` |
| `make test-bank-pair-selector` | `tb_bank_pair_selector.sv` | `bank_pair_selector.sv` |
| `make test-bank-output-or-tree` | `tb_bank_output_or_tree.sv` | `bank_output_or_tree.sv` |
| `make test-row-group` | `tb_dcim_row_group.sv` | `dcim_row_group.sv`及其下層cell/segment |
| `make test-array-128` | `tb_dcim_array_128x128.sv` | `dcim_array_128x128.sv`及完整16384-cell階層 |
| `make test-macro-core` | `tb_dcim_macro_core.sv` | `dcim_macro_core.sv`及完整write/read/CIM/output階層 |
| `make test-chip-pin-top` | `tb_dcim_chip_pin_top.sv` | `dcim_chip_pin_top.sv`、正式SRAM serializer、共用`sumo/read` MUX及完整下層階層 |
| `make test-dcim-pin-master` | `tb_dcim_pin_master.sv` | `dcim_pin_master.sv`與真實`dcim_chip_pin_top` |
| `make test-dcim-cdc-bridge` | `tb_dcim_cdc_bridge.sv` | `dcim_cdc_bridge.sv`與variable-latency mock master |
| `make test-dcim-cdc-integration` | `tb_dcim_cdc_bridge_integration.sv` | 125 MHz Bridge、50 MHz Pin Master與真實Chip Top |
| `make test-dcim-master-chip-top` | `tb_dcim_master_chip_top.sv` | 單一50 MHz Self-test、Pin Master與真實128×128 Chip Top；驗證一筆2,048-word Burst、2,048次讀回及A8W8 |

第一次執行或 RTL/TB 有更新時，Makefile 會先重新編譯，再執行模擬；如果來源沒有改變，會直接執行已建立的模擬程式。

## 3. Cell 層測試內容

### 3.1 `tb_fesram_cell_model.sv`

執行指令：

```bash
make test-fesram
```

測試對象是目前以一個 FF 表示的 1-bit FeSRAM 儲存 cell。Clock 週期為 10 ns，控制訊號在正緣被取樣。

測試順序：

1. 將 `rst_n=0`，確認 `Q=0` 且 `QB=1`。
2. 設定 `write_en=1`、`write_data=1`，確認正緣後寫入 1。
3. 分別切換保留腳位 `nv_store`、`pd_en`、`nv_recall`，確認目前簡化模型不會因此改變資料。
4. 設定 `write_en=1`、`write_data=0`，確認正緣後寫入 0。
5. 設定 `write_en=0` 並改變 `write_data`，確認 cell 保持原值。
6. 每個步驟都同時驗證 `QB = ~Q`。

這份測試驗證的是「FF 儲存行為」；尚未模擬實體 FeSRAM 的 store、power-down、recall 時序。

### 3.2 `tb_dcim_cell_logic.sv`

執行指令：

```bash
make test-dcim-cell
```

測試單一 DCIM cell 的儲存節點與 NOR 計算路徑：

```text
cim_product = ~(cim_input_b | read_qb)
```

測試內容：

1. 分別寫入權重 `Q=0` 和 `Q=1`。
2. 每次寫入後確認 `read_q=Q`、`read_qb=~Q`。
3. 對每個權重測試 `cim_input_b=0` 與 `cim_input_b=1`。
4. 總共涵蓋 2 種權重 × 2 種輸入，共 4 種 NOR 組合。

注意：`cim_input_b` 是 active-low 計算輸入。產生 `cim_input_b` 的共享 Input Control 不包含在這個 cell testbench 內。

## 4. Segment 層測試內容

### 4.1 `tb_dcim_row_4bit.sv`

執行指令：

```bash
make test-row
```

測試由 4 個 1-bit cell 組成的一列。這一列儲存一個 unsigned 4-bit 權重，其中 `write_data[3]` 為 MSB。

計算關係：

```text
IN_b = ~(cim_en & cim_row & activation_bit)
row_product[k] = ~(IN_b | stored_qb[k])
```

因此：

```text
cim_en=1、cim_row=1、activation_bit=1
    → row_product = stored weight

任一控制值為 0
    → row_product = 0000
```

測試內容：

1. Reset 後確認 `stored_q=0000`、`stored_qb=1111`。
2. 依序寫入全部 16 種 4-bit 權重 `0～15`。
3. 每個權重都使用 `sense_en` 直接讀回，確認寫入與 bit order 正確。
4. `sense_en=0` 時確認 `read_data=0000`。
5. 每個權重窮舉 `{cim_en, cim_row, activation_bit}` 的全部 8 種組合。
6. 總計進行 16 × 8 = 128 次計算檢查。
7. 最後令 `row_write_en=0` 並切換保留腳位，確認權重仍保持為最後寫入的 `1111`。

目前 row、bank、row-group與array層的`read_data`都是組合式SA-equivalent讀出；唯一的SRAM read暫存器放在`sram_read_serializer_8bit`。因此`sense_en`有效後，資料必須在第一個正緣前穩定，該正緣擷取完整8-bit並立即輸出bit[7]。

### 4.2 `tb_adder_tree_32x4.sv`

執行指令：

```bash
make test-adder
```

測試 32 組 unsigned 4-bit `row_product` 的加總：

```text
bank_sum = row_product[0] + ... + row_product[31]
```

輸入最大值為 15，因此輸出最大值為：

```text
32 × 15 = 480
```

9-bit unsigned 輸出可表示 0～511，不會在最大測試中 overflow。

10 組測試資料：

| 測試 | 輸入內容 | 預期總和 |
|---|---|---:|
| 1 | 32 列全部為 0 | 0 |
| 2 | 只有 row 0 為 15 | 15 |
| 3 | row 0、row 1 都為 15 | 30 |
| 4 | `15 + 15 + 3 + 3` | 36 |
| 5 | 32 列全部為 1 | 32 |
| 6 | 32 列全部為 2 | 64 |
| 7 | 32 列全部為 4 | 128 |
| 8 | 32 列全部為 8 | 256 |
| 9 | 32 列全部為 15 | 480 |
| 10 | `0～15` 重複兩次 | 240 |

這份 testbench 驗證純組合加法結果，不驗證 pipeline latency，因為目前 adder tree 沒有 register。

### 4.3 `tb_dcim_bank_32x4.sv`

執行指令：

```bash
make test-bank
```

這份testbench驗證Bank在移除局部Adder Tree後仍正確輸出32筆row products：

```text
32 個 dcim_row_4bit
        │
        ▼
32 個4-bit row_product
        │
        ▼
Testbench reference sum（不屬於DUT）
```

主要運算式：

```text
reference_sum = Σ row_product[i], i=0...31
```

測試流程：

1. Reset 後確認所有權重與全部`row_product`清除，reference sum為0。
2. 將 row 0～31 寫成 `0～15` 重複兩次。
3. 選擇 row 15並開啟`sense_en`，在下一個clock前確認`read_valid=1`且`read_data=15`，驗證Bank輸出是組合式SA-equivalent結果。
4. 跨過下一個正緣後確認資料維持不變，證明Bank內沒有第二級read register。
5. 依序讀回全部 32 列，確認內容為 `0～15` 重複兩次。
6. `sense_en=0` 時立即確認`read_valid=0`、`read_data=0`。
7. `sense_en=1` 但沒有選擇任何 row 時，也必須輸出 invalid 和 0。
8. 全部 activation 為 1，確認總和為 240。
9. 單獨啟用 row 15，確認結果為 15。
10. 單獨啟用 row 31，確認結果為 15，藉此檢查高位 row 連線。
11. 只啟用偶數列，確認結果為 112。
12. 只啟用奇數列，確認結果為 128。
13. `cim_en=0` 時確認所有乘積被關閉，結果為 0。
14. `cim_row=0` 時確認整個 32-row group 被關閉，結果為 0。
15. 只覆寫 row 31，將權重由 15 改成 7，並直接讀回確認。
16. 只啟用 row 31，確認結果改成 7。
17. 全部 activation 為 1，確認總和由 240 改為 232，代表其他列未被覆寫。
18. 將全部 32 列寫成最大權重 15，確認最大輸出為 480。
19. 對 32 條 activation 逐條做 one-hot 測試；每一列都應輸出 15。
20. `row_write_en=0` 時切換 write data 與保留控制腳，確認所有權重保持不變。

這份測試同時驗證寫入、組合式SA-equivalent讀出、DCIM bit multiplication、32-row累加與row wiring；真正的單一read register由serializer測試與Macro整合測試驗證。

## 5. Peripheral 層測試內容

### 5.1 `tb_row_decoder_7to128.sv`

執行指令：

```bash
make test-row-decoder
```

測試 7-to-128 active-high wordline decoder：

```text
row_addr[6:0] + wl_en → wl_select[127:0]
```

測試內容：

1. `wl_en=0` 時，分別改變位址為 0、63、127，確認 128 條 WL 全部關閉。
2. 窮舉位址 0～127。
3. 每次改位址前先將 `wl_en=0`，模擬安全的位址切換流程。
4. `wl_en=1` 後確認只有 `wl_select[row_addr]` 為 1。
5. 以簡單迴圈計算 active output 數量，確認每個位址都嚴格 one-hot。
6. 額外確認 7→8 的 local 3-to-8 邊界。
7. 額外確認 31→32 的 32-row CIM group 邊界。
8. 測試結束時將 `wl_en=0`，回到安全狀態。

### 5.2 `tb_cim_group_decoder_2to4.sv`

執行指令：

```bash
make test-cim-group-decoder
```

測試 `{A6,A5}` 對四個 32-row group 的 one-hot 選擇：

| `group_addr` | `cim_row` | 對應全域 row |
|---|---|---|
| `00` | `0001` | 0～31 |
| `01` | `0010` | 32～63 |
| `10` | `0100` | 64～95 |
| `11` | `1000` | 96～127 |

testbench 窮舉全部 4 個位址，並確認輸出值與 active bit 數量皆正確。

### 5.3 `tb_input_buffer_32x4.sv`

執行指令：

```bash
make test-input-buffer
```

測試 `0622.pptx` 第3頁 Input Path 的4條Din lane × 8級DFF、兩層demux及one-to-four fanout：

```text
sel_next=0：clk_en有效時，資料沿DFF chain前進
sel_next=1：停止shift並將各級DFF tap送往輸出路徑
mode_sel=0：前兩級DFF送往8-bit SRAM write path
mode_sel=1：前兩級DFF送往CIM path
```

測試內容：

1. Reset清除8級DFF、SRAM輸出及四組CIM fanout。
2. `sel_next=0`時，一個有效`bufclk`將`Din=1010`載入stage 0。
3. DFF loading期間，確認SRAM與CIM輸出分支皆為0。
4. `clk_en=0`時，確認DFF chain保持原值。
5. 依第12頁例子先輸入9再輸入1，確認前兩級DFF得到`8'h91`。
6. `sel_next=1, mode_sel=0`時，確認SRAM write path輸出`8'h91`。
7. 模擬第三個SRAM write clock，確認Input Path不再shift且資料維持`8'h91`；真正的`write_en`由下游controller產生。
8. 只切換`mode_sel=1`，確認相同DFF資料轉到CIM branch且不改變儲存內容。
9. 以high-nibble-first順序載入`8,9,a,b,c,d,e,f`，確認8個clock後DFF內容為`0x89abcdef`。
10. `sel_next=1, mode_sel=1`時，確認四個32-row group得到相同資料。
11. 驗證stage 0、1、7分別對應local row 0、4、28起始位置。
12. 驗證第3頁只有前兩級具有`mode_sel` demux：SRAM mode時CIM rows 0～7為0，rows 8～31仍保留實體連線；系統必須由下游`cim_en`關閉計算。
13. `sel_next`返回0後，確認輸出隔離但DFF內容不被破壞。

### 5.4 `tb_sram_write_buffer_8bit.sv`

執行指令：

```bash
make test-sram-write-buffer
```

這個模組沒有另外增加FF。第3頁Input Path的前兩級DFF本身就是8-bit暫存來源，模組只表示`mode_sel` demux後的SRAM側組合路由：

```text
write_data[7:4] = stage1_bits  （第一個輸入的nibble）
write_data[3:0] = stage0_bits  （第二個輸入的nibble）
```

測試內容：

1. `sram_path_en=0`時，確認inactive demux輸出為0。
2. 驗證stage 1為9、stage 0為1時組成`8'h91`。
3. 使用`stage1=a, stage0=5`確認nibble順序沒有顛倒。
4. 關閉route後，確認不需要clock即可隔離輸出，證明此模組沒有加入簡報未畫出的額外DFF與cycle latency。

### 5.5 `tb_bitserial_accumulator.sv`

執行指令：

```bash
make test-bitserial-accumulator
```

測試一條完整的unsigned、MSB-first講義ACC路徑。Macro Core會各實例化一份，分別形成even→`sume`與odd→`sumo`：

```text
ACC_next = (ACC << 1) + partial_sum
```

每個 `partial_sum` 是一個32×4 Bank的9-bit activation bit-plane結果。只有 `output_en=1` 的 `bufclk` 上升緣會執行一次shift-and-add。內部3-bit counter只計算「已接受幾個bit-plane」；第8次使用包含本次partial sum的`next_acc`載入18-bit serial stage，因此該edge後立刻在`serial_sum`看到bit[17]，不再需要Macro Core外部的`serial_load`。

講義第6頁把累加與serial output畫在同一個`acc`方塊，第14頁又只列出`output_en`而沒有`serial_load`晶片pin。講義沒有畫出3-bit counter的閘級電路；此counter是依照本專案明確指定的「UINT8固定8次、第8次自動開始輸出」所加入的可合成控制抽象。

測試內容：

1. Active-high `reset1`清除Accumulator、active-high `reset2`清除serial stage。
2. `output_en=0`時，改變partial sum也不影響狀態。
3. 以UINT8 `00001111`重現講義的`480×15=7200`。
4. 確認第8次`output_en`後立即出現bit[17]，並由18個serial bits重建7200。
5. 第8次後再送第9筆，確認完成鎖定會忽略它，必須以`reset1`開始下一筆結果。
6. 八個bit-plane都輸入480，驗證最大值`480×255=122400`。
7. 在有效資料之間插入disabled clocks，確認不會產生隱藏shift或消耗sample count。
8. 分別啟動`reset1`與`reset2`，確認兩者只清除各自負責的狀態。

### 5.6 `tb_serial_output.sv`

執行指令：

```bash
make test-serial-output
```

測試一條ACC內部的18-bit serial-output stage。講義把累加與輸出畫成單一`acc`方塊；RTL以階層方式保留小型`serial_output`子模組，讓bit順序與reset可以單獨驗證：

```text
一條ACC的 next_acc[17:0]
              ↓ internal load（只存在於ACC內部）
      18-bit shift register
              ↓
 serial_sum（bit[17]→bit[0]）
```

在內部`load=1`的`bufclk`上升緣載入一條18-bit結果。該edge後立即輸出bit[17]；之後17個`bufclk`依序輸出bit[16]到bit[0]，再回到0。`remaining_bits`與`serial_active`只供模組內部控制/驗證，不是講義新增的晶片pin。

測試內容：

1. Active-high `reset2`清除serial bit與active狀態。
2. 載入講義範例7200，即18-bit `000001110000100000`，確認load edge後立即看到bit[17]。
3. 逐一印出並核對bit[17]到bit[0]，確認MSB-first順序並重建7200。
4. 18 bits送完後，確認output與active回到0。
5. 串流途中重新load，確認新資料載入優先於舊資料shift。
6. 串流途中啟動`reset2`，確認shift register立即清除。

`load`只連接在`bitserial_accumulator`與其`serial_output`子模組之間，由第8次accepted sample的`final_sample`自動產生；Macro Core與Chip Pin Top都不含`serial_load`。

### 5.7 `tb_sram_read_serializer_8bit.sv`

執行指令：

```bash
make test-sram-read-serializer
```

測試講義第12～13頁的SRAM serial-read資料路徑。選定的兩個32×4 Banks各提供一個4-bit sense結果，目前專案固定以下mapping：

```text
read_word[7:4] = even_read_data
read_word[3:0] = odd_read_data
read_word       = {even_read_data, odd_read_data}
```

`selected_pair_read_valid`和兩份4-bit資料必須在同一個`clk`上升緣前穩定；該上升緣把完整8-bit word載入唯一的read shift register，並立即輸出bit 7。Row Group已在內部從16組Pairs選出一組Even/Odd資料，Array再從4個Row Groups選出有效資料，因此不再把32組bank read bus傳到上層。之後每個上升緣依序送出bit 6到bit 0，最後補0。載入優先於shift；模組沒有counter、busy、額外FSM或外部`read_load` pin。

測試內容：

1. Active-low reset清除8-bit shift register及`serial_read_bit`。
2. 兩份data存在但`selected_pair_read_valid=0`時不得載入資料。
3. 以講義範例`even=1001, odd=0001`載入`8'h91`，逐clock印出並核對`10010001`。
4. 重建完整serial word，並顯示講義未包含output PAD時的反相參考`~8'h91=8'h6e`。
5. 八個bits送完後，確認zero-fill讓輸出回到0。
6. 以第二個講義範例`even=0101, odd=0010`重建`8'h52`，同時確認high/low nibble沒有交換；PAD前反相參考為`8'had`。
7. 串流途中載入新的完整SA word，確認load優先於舊資料shift。
8. 串流途中reset，確認shift register立即清除。

這個模組只負責8-bit PISO。`sense_en`仍由Array讀取路徑處理，最後由已完成的`dcim_chip_pin_top`將`serial_read_bit`與CIM `sumo`做2-to-1選擇。

### 5.8 `tb_bank_decoder_4to16.sv`

執行指令：

```bash
make test-bank-decoder
```

測試 `B[3:0]` 到 16 條 active-high bank select 的 one-hot decode：

```text
bank_addr = N → 只有 bank_select[N] = 1
```

測試內容：

1. 窮舉全部 16 個輸入位址。
2. 對每個位址建立預期 one-hot vector。
3. 確認實際輸出與預期 vector 完全相同。
4. 計算 active output 數量，確認恆為 1。
5. 額外檢查輸出邊界 `o0`、`o7`、`o8`、`o15`，確認 bit ordering。

這個 testbench 只驗證 4-to-16 decoder；CIM/SRAM mode routing 與實體 bank pairing 是後續模組的責任。

## 6. Array 層測試內容

### 6.1 `tb_bank_pair_selector.sv`

執行指令：

```bash
make test-bank-pair-selector
```

測試 4-to-16 decoder 後方的 16 組 one-to-two mode routing：

```text
cim_pair_en  = bank_select & mode_sel
sram_pair_en = bank_select & ~mode_sel
```

`mode_sel=0` 代表 SRAM mode，`mode_sel=1` 代表 CIM mode。Pair `p` 對應 physical even segment `2p` 與 odd segment `2p+1`，但此 selector 只產生 pair enable，不會合併兩個 accumulator 的數值。

測試內容：

1. `bank_select=0` 時，確認 CIM 與 SRAM 路徑全部關閉。
2. 在 SRAM mode 窮舉 pair 0～15，確認每次只有 `sram_pair_en[p]` 為 1，CIM 路徑全為 0。
3. 每個 SRAM 測試同時印出 pair 對應的 even/odd physical segment，例如 pair 5 對應 segment 10/11。
4. 在 CIM mode 窮舉 pair 0～15，確認每次只有 `cim_pair_en[p]` 為 1，SRAM 路徑全為 0。
5. 固定選擇 pair 5，只切換 `mode_sel`，確認 enable 由 SRAM 路徑互斥地轉移到 CIM 路徑。
6. 輸入 `bank_select=16'h8001`，確認 selector 不會偷偷加入 priority encoder，而是原樣將輸入送到被選擇的 mode path。
7. 測試結束時清除 `bank_select`，讓所有 pair 回到關閉狀態。

正常系統操作時 `bank_select` 應由 `bank_decoder_4to16` 保證為 one-hot。Multi-hot 測試只是確認這個模組的責任是 routing，不是替上游修正非法輸入。

若兩個 32×4 Segment 被映射為同一個 8-bit weight，後續數值應使用：

```text
result = low_acc + (high_acc << 4)
```

這項 shift-and-add 不屬於 `bank_pair_selector` 的功能，應由後續 accumulator/output datapath 處理。

### 6.2 `tb_bank_output_or_tree.sv`

執行指令：

```bash
make test-bank-output-or-tree
```

測試 16 個 pair slots 的 even/odd 9-bit partial sums，是否經由兩棵獨立的兩級 OR tree 正確匯集。每棵 tree 第一級有四組 OR4，第二級再以一組 OR4 合併，對應講義 Output Path。

測試內容：

1. 所有 bank sums 為零時，確認兩個輸出皆為零。
2. 在 pair 0 輸入 even=100、odd=200，確認兩路數值保持獨立。
3. 窮舉 pair slot 0～15，確認全部 input wiring、OR4 分組邊界和 segment `2p/2p+1` mapping。
4. 分別只驅動 even 或 odd 路徑，確認兩棵 OR tree 互不干擾。
5. 在 pair 15 輸入最大合法 partial sum 480，確認 9-bit 數值不被截斷。
6. 使用 `101010101` 與 `010101010` 驗證 bit ordering 及 even/odd path 沒有交換。
7. 刻意輸入 multi-active bank，確認元件執行 bitwise OR 而非算術加法；正常系統仍必須維持 one-hot pair enable。

### 6.3 `tb_dcim_row_group.sv`

執行指令：

```bash
make test-row-group
```

測試一個完整32-row×128-column group：

```text
32個dcim_bank_32x4
= 16組even/odd pairs
= 1024個4-bit rows
= 4096個1-bit storage/compute cells
```

本層先用`cim_pair_en[15:0]`選出一組bank pair，輸出`selected_even_product[0:31]`與`selected_odd_product[0:31]`。真正的兩棵Adder Tree位於上一層`dcim_array_128x128`；testbench用reference sum檢查這兩組向量，但不在DUT內建立加法樹。

測試內容：

1. Reset清除全部32個segments、read data與valid。
2. 在pair 0、local row 0寫入even/odd=`3/c`並讀回，驗證第一個pair邊界。
3. 在pair 15、local row 31寫入even/odd=`5/a`並讀回，再讀pair 0確認column isolation。
4. 啟用group及CIM pair 0，只打開activation row 0，確認selected Even/Odd向量的reference sums為3與12。
5. 關閉`cim_group_en`，確認即使pair仍被選擇，全部CIM輸出也為0。
6. 驗證pair 15與local row 31的CIM邊界結果為5與10。
7. Activation全0時確認兩組32-row products皆為0。
8. 只啟用`cim_pair_en`並嘗試寫入，讀回仍為0，證明CIM控制不能開啟SRAM write path。
9. 只啟用`sram_pair_en`時，確認不能啟動CIM計算。
10. 將pair 7的32 rows全部寫入15並令activation全1，確認selected Even/Odd vectors各自加總為講義最大值480。

第一次編譯會展開完整4096 cells，因此時間明顯長於底層單元測試；只要來源未變，Makefile會重用既有模擬執行檔。

### 6.4 `tb_dcim_array_128x128.sv`

執行指令：

```bash
make test-array-128
```

測試完整128-row×128-column array：

```text
4個dcim_row_group
    × 每組32 rows
    × 每組32個32×4 segments
= 128 rows × 128 columns
= 16384個1-bit storage/compute cells
```

Array接收decoder與Input Path產生的預解碼內部訊號，不在本層重複實作decoder。`wl_select[127:0]`依序切成四組32-bit local WL；四份`activation_group_bits[0:3]`則分別接到四個row groups。每個group先選出一組Even/Odd pair的32筆4-bit row products，Array再依one-hot group控制合併，最後只送入Even與Odd各一棵共享`adder_tree_32x4`。

測試內容：

1. Reset及所有enable關閉時，確認SRAM read與CIM輸出皆為0。
2. 在global rows 0、32、64、96寫入不同值，驗證四個row-group邊界及資料隔離。
3. 驗證global row 127與pair 15的兩個最高邊界，並確認不會破壞row 0/pair 0。
4. 逐一啟用四個CIM groups，確認相同pair的row products可正確送入兩棵共享Adder Tree。
5. 把activation放在未選group，確認不能流入已選group；`cim_group_select=0`時兩路結果皆為0。
6. 驗證group 3、local row 31、pair 15可穿過完整group/pair選擇網路。
7. 將group 2、pair 7的32 rows全部寫成15，確認兩路最大partial sum皆為`32×15=480`。
8. 只打開`sram_pair_en`時，確認不能啟動CIM計算。

第一次建置會展開16384 cells，實測Verilator初次編譯約需數分鐘；模擬本身很快，來源未變時Makefile會直接重用執行檔。

## 7. Chip整合層測試內容

### 7.1 `tb_dcim_macro_core.sv`

執行指令：

```bash
make test-macro-core
```

這份測試把Proposal Figure 4與`0622.pptx`第2～6、12、14～15頁的數位資料路徑整合在同一次transaction中：

```text
Input Path + Decoders + Bank Selector
                 ↓
          128×128 DCIM Array
                 ↓
       even/odd 9-bit partial sums
                 ↓
       two 18-bit accumulators
                 ↓
              sume/sumo
```

測試內容：

1. 驗證`model_rst_n`、active-high `reset1`與active-high `reset2`三個reset domains。
2. 用兩個Input Buffer clocks及一個write clock寫入`A=0/B=0/8'hA5`、`A=1/B=0/8'h32`。
3. 在`A=32/B=15`寫入`8'hC9`，驗證row-group與bank-pair邊界。
4. 使用組合式平行SRAM readback確認high nibble送到even、low nibble送到odd；再由測試平台暫時接上的serializer驗證第一個`sense_en`有效正緣立即輸出bit[7]，並重建`8'hA5`、`8'h32`與`8'hC9`。
5. 單獨清除Accumulator後重新讀回權重，確認開始新MAC不會擦除Array。
6. 設定row0 activation=3、row1 activation=2，依bit7到bit0載入八個bit-planes。
7. 逐plane核對9-bit partial sum與Horner accumulator狀態。
8. 驗證最終結果：`even=3×10+2×3=36`、`odd=3×5+2×2=19`。
9. 第8次`output_en`後不送額外load，直接從當下的bit[17]開始，以`sume/sumo`重建18-bit結果36與19。

Macro Core保留兩個組合式平行4-bit結果；Macro testbench另接一份serializer直接驗證單一暫存時序。正式階層已由Pin Top完成：

```text
Macro Core平行even/odd read data
              ↓
peripheral/sram_read_serializer_8bit（已建立並獨立驗證）
              ↓ serial_read_bit
dcim_chip_pin_top中的output mux
       ├─ CIM mode  → sumo
       └─ SRAM mode → serial_read_bit
              ↓
        實體sumo/read共用pad
```

### 7.2 Macro Core的reset責任

`model_rst_n`控制Input Buffer與目前以FF建模的weight Array；active-high `reset1`只清除兩個Accumulator及其8-sample狀態；active-high `reset2`只清除兩個output shift registers。這項分離可讓新MAC清除計算狀態而不擦除已寫入的weight cells。

講義列出`reset1/reset2`，但沒有提供完整reset電路與明確極性；本專案已依使用者確認固定為active-high。`model_rst_n`是目前FF-based weight/input模型所需的額外RTL模型介面，講義沒有列出對應的實體pin。Pin Top目前保留此介面；SRAM serializer以`model_rst_n & ~reset2`重置，使初始化reset與active-high output reset都能清除read shift register。

### 7.3 `tb_dcim_chip_pin_top.sv`

執行指令：

```bash
make test-chip-pin-top
```

這份測試只從Pin Top公開腳位驅動及觀察，不使用Macro的parallel read、partial sum或accumulator debug輸出。驗證內容：

1. `model_rst_n=0`、`reset1=1`、`reset2=1`時，`sume/sumo`皆為0。
2. 依第12頁的「兩個Input DFF clocks加一個SRAM write clock」流程，寫入`A=0/B=0/8'hA5`與`A=1/B=0/8'h32`。
3. 在`sense_en`有效後的第一個正緣立即從共用`sumo`取得bit[7]；接著七個正緣取得bit[6:0]，分別重建`8'hA5`與`8'h32`。
4. 串列讀取途中啟動active-high `reset2`，確認SRAM serializer與ACC output都立即歸零；解除後重新讀回`8'hA5`，確認reset2不會擦除weight cells。
5. 設定row0 activation=3、row1 activation=2，從Pin Top輸入八個MSB-first UINT8 bit-planes及八次`output_en`。
6. 在`mode_sel=1`時從`sume/sumo`重建18-bit結果，確認even=`3×10+2×3=36`、odd=`3×5+2×2=19`，同時驗證`sumo` MUX已從SRAM read切換到odd ACC。
7. 使用固定seed的LCG偽隨機資料寫入128 rows × 16 bank pairs，共2048個8-bit words，覆蓋完整16384個1-bit cells；大量寫入只顯示四次row-group進度，不逐筆列印。
8. 從Row 0、31、32、63、64、95、96、127抽樣八組serial readback，確認完整寫入後的邊界與跨group地址。
9. 為四個Groups建立32筆固定非零UINT8 activations，執行4 groups × 16 pairs共64組完整運算，逐組比對18-bit Even、18-bit Odd與`odd+(even<<4)`的21-bit W8 Golden Model結果。

Top腳位的完整操作順序、cycle表、Weight mapping與Golden公式另見
[`DCIM_CHIP_PIN_TOP_OPERATION_GUIDE.md`](./DCIM_CHIP_PIN_TOP_OPERATION_GUIDE.md)。

Pin Top正式資料路徑為：

```text
Macro combinational even/odd read
              ↓
sram_read_serializer_8bit
              ↓ serial_read_bit
mode_sel=0 ───┤
              ├─→ sumo共用輸出pin
mode_sel=1 ─ core_sumo

core_sume ──────→ sume輸出pin
```

## 8. Lint 與可合成語法檢查指令

Lint 不會施加測試資料或驗證數值答案。它用來檢查語法、寬度、連接與常見 RTL 問題。

| 指令 | 檢查內容 |
|---|---|
| `make lint` | 執行目前全部 testbench lint，加上可合成 RTL lint |
| `make lint-cell` | 檢查兩份 cell testbench 與其 RTL |
| `make lint-segment` | 檢查三份 segment testbench 與其 RTL |
| `make lint-peripheral` | 檢查八份 peripheral testbench 與其 RTL |
| `make lint-array` | 檢查四份array testbench與其RTL |
| `make lint-chip` | 檢查Macro Core、Chip Pin Top兩份整合testbench與全部下層RTL |
| `make lint-synth` | 定義 `SYNTHESIS`，只檢查目前已納入的可合成 RTL |

建議每次修改後執行：

```bash
make lint
make test
```

兩者皆通過，才能同時表示目前沒有被 Verilator 發現的 lint 問題，而且功能測試結果正確。

## 9. Build 目錄與清除指令

預設模擬執行檔與中間產物會放在：

```text
CIM_CHIP/build/
```

只清除這個專案的 build 產物：

```bash
make clean
```

清除後重新執行 `make test`，Makefile 會重新編譯全部 testbench。

也可以將 build 輸出改到其他位置：

```bash
make BUILD_ROOT=/tmp/dcim-build test
```

或指定其他 Verilator 執行檔：

```bash
make VERILATOR=/path/to/verilator test
```

## 10. 如何判斷測試是否通過

成功時，每一份 testbench 最後會印出 `PASS`，且 shell return code 為 0。例如：

```text
PASS: all 16 bank-decoder addresses are correct and one-hot
```

完整測試成功時，最後會看到：

```text
PASS: all chip-level regression tests completed
```

如果 assertion 或數值比對失敗，testbench 會使用 `$fatal(1)` 結束，`make` 也會回傳非 0，並停止後續 regression。

## 11. 目前驗證範圍限制

目前測試確認的是「RTL 是否符合 testbench 定義的行為」，不等於 RTL 已經完全重現講義中的電晶體、類比周邊或晶片 pin 時序。尚未完成：

- Vivado synthesis、implementation 與 timing closure
- FPGA 實板 I/O 與 clock domain crossing
- 實體 FeSRAM 的 non-volatile store/recall 行為
- Gate-level simulation、post-route simulation
- 類比 variation、PVT、功耗與實體電路延遲
- KWS layer controller與FPGA pin master/backend

這些項目需要在對應 RTL 完成後，逐層增加 testbench 或使用 Vivado 的合成與時序報告驗證。

## 12. 講義中的主要架構基準

這一節保存原先分散在各模組 Markdown 的講義對照，作為後續 RTL 與 testbench 的共同基準。

### 12.1 Array、Bank與Segment

`0622.pptx` 與 Proposal 使用：

```text
Array size   = 128 × 128
Segment size = 32 × 4
```

因此一個32-row group橫向包含32個4-column Segments；兩個相鄰Segments形成一個8-bit bank pair：

```text
pair p：even segment=2p，odd segment=2p+1
pair 0：segment 0/1，columns 0～7
pair 5：segment 10/11，columns 40～47
pair15：segment 30/31，columns 120～127
```

每個32×4 Segment最多輸出：

```text
32 rows × 4-bit maximum 15 = 480
```

所以Segment partial sum是9-bit unsigned。

### 12.2 Column Decoder與Mode Routing

`0622.pptx`第4～5頁顯示：

```text
B[3:0] → 4-to-16 column decoder → 16組one-to-two demux
```

講義第14頁明確說明 `mode_sel=1` 是CIM mode，因此目前方程為：

```text
cim_pair_en[p]  = bank_select[p] &  mode_sel
sram_pair_en[p] = bank_select[p] & ~mode_sel
```

正常操作由4-to-16 decoder保證one-hot。Selector本身只是demux，不加入priority encoder。

### 12.3 DCIM Input NAND與Cell NOR

講義Column Decoder and NOR Input圖顯示：

```text
IN_b = NAND(cim_en, cim_row, activation_bit)
```

Proposal說明每個FeSRAM computing unit增加NOR gate與tri-state buffer。目前數位乘法方程為：

```text
cim_product = NOR(IN_b, QB)
            = cim_en & cim_row & activation_bit & Q
```

### 12.4 Output OR Tree

`0622.pptx`第6頁說明未選Bank輸出為0，只有選定Bank影響結果。每一條even/odd路徑使用兩級OR4：

```text
Stage 1：bank[0..3]、[4..7]、[8..11]、[12..15]各進一個OR4
Stage 2：四個Stage-1結果再進一個OR4
```

這個動作是選擇，不是數學加法。如果多個Bank同時為非零，輸出是bitwise OR，不是Bank sums總和。

### 12.5 Bit-Serial Accumulator

講義Accumulator輸入為 `C + S[7:0]`，等效9-bit partial sum，並具有 `bufclk` 與 `load`。第14頁新增獨立 `output_en`，避免同一筆CIM結果被重複shift。

目前unsigned shift-and-accumulate使用：

```text
ACC_next = (ACC << 1) + partial_sum
```

UINT8由外部controller提供八個MSB-first partial sums。由於講義chip pin沒有`serial_load`，且本專案要求第8次`output_en`後立即輸出bit[17]，Accumulator以3-bit accepted-sample counter辨認最後一筆、載入serial stage並鎖住第9筆；下一筆運算由active-high `reset1`重新啟動。這是控制層的可合成補充，不是講義明示的閘級counter。

講義範例：

```text
480 × (1+2+4+8) = 7200
15 × 15 × 32 = 7200
```

UINT8單一32×4 Segment路徑最大值：

```text
480 × 255 = 122400
```

符合 `0622.pptx` 第15頁的18-bit output規格。

文件間有一項明確版本差異：`Proposal_for_ITRI_NVM.docx`的Figure 9說明文字仍寫「16-bit accumulator」，但`0622.pptx`第15頁的較新規格表寫「Output 18bit」。7200同時能放入16與18 bits，因此單靠該範例無法判斷寬度；本RTL依較新簡報與已確認需求固定採18-bit。

### 12.6 Even/Odd與8-bit Weight責任邊界

Even與Odd partial sums必須分開進入兩個Accumulator。若weight mapping把兩個4-bit Segments定義為同一個8-bit weight的low/high nibble，後續才執行：

```text
final_result = low_acc + (high_acc << 4)
```

講義以`9`再`1`形成`8'h91`說明先輸入的nibble為高位，但沒有在文字中明確命名哪一個實體Segment是even或odd。目前專案為了讓write、parallel read與serial read一致，固定採用：

```text
even = high nibble
odd  = low nibble
```

這是專案層級的mapping決策；selector與OR tree仍只保持兩條路徑獨立，不在其內部做位移或合併。

## 13. RTL與講義逐模組稽核

稽核日期：2026-08-17。這裡的「部分符合」表示主要數位功能合理，但模組介面、周邊電路或時序仍有講義未支持的抽象；不代表既有testbench失敗。

| RTL模組 | 稽核結果 | 說明 |
|---|---|---|
| `fesram_cell_model` | 明顯簡化 | 只有一個同步FF；未實作FeRAM store/recall、power-down與normally-off行為 |
| `dcim_cell_logic` | 部分符合 | NOR乘法方程符合；講義中的tri-state buffer未實作，以disabled=0取代 |
| `dcim_row_4bit` | 部分符合 | 4 cells、共享NAND input與4-bit結果符合；SRAM read是理想組合式抽象 |
| `adder_tree_32x4` | 功能符合 | 32個4-bit值經5級加法得到9-bit；未模擬講義layout/gate delay |
| `dcim_bank_32x4` | FPGA最佳化且有數位抽象 | 保留32×4 cells與row products，但局部Adder Tree已移至Array共享；read path缺類比precharge/sense amp |
| `row_decoder_7to128` | 邏輯符合 | 3-to-8與4-to-16 predecode及`wl_en` gating符合；未模擬decoder transition glitch |
| `cim_group_decoder_2to4` | 邏輯符合 | A5/A6選四個32-row groups符合講義 |
| `input_buffer_32x4` | 結構與功能符合、reset為RTL抽象 | 已實作4 Din lanes×8 DFF、`sel_next` demux、前兩級`mode_sel` demux及四組fanout；`rst_n`極性不是講義明示規格 |
| `sram_write_buffer_8bit` | 功能符合 | 使用前兩級DFF taps組成8-bit write word，沒有加入額外register；實體write driver與`write_en`不屬於此模組 |
| `bank_decoder_4to16` | 邏輯符合 | B[3:0]到16條one-hot column selects符合 |
| `bank_pair_selector` | 邏輯符合 | 16組SRAM/CIM one-to-two mode routing符合 |
| `bank_output_or_tree` | 保留的講義參考模組 | 單元測試仍驗證原始Even/Odd OR4結構，但正式Array/Macro已不再實例化 |
| `dcim_row_group` | 結構符合、算術位置為FPGA最佳化 | 32個32×4 segments組成32×128 group，先選pair並輸出Even/Odd兩組row products |
| `dcim_array_128x128` | Cell結構符合、Adder為FPGA共享架構 | 四個32×128 groups組成16384 cells；先選pair/group，再由Even/Odd兩棵共享Adder Tree輸出9-bit sums |
| `bitserial_accumulator` | 算術與整合行為符合、8次計數為控制抽象 | 一個實例對應講義一條ACC路徑；內含3-bit sample count與一個serial-output子模組，第8次後立即輸出bit[17]；active-high reset極性是已確認的專案規格 |
| `serial_output` | 功能符合、子模組邊界為RTL抽象 | 每個ACC實例各有一個18-bit shift register；MSB-first符合7200波形；內部`load/serial_active`不是chip pins |
| `sram_read_serializer_8bit` | 功能符合、SA介面為RTL抽象 | 是SRAM read path唯一clocked register；第一個capture edge立即輸出bit[7]，其後MSB-first輸出剩餘7 bits；雙`read_valid`是內部介面，不是講義chip pin，已由Pin Top整合共用輸出MUX |
| `dcim_macro_core` | 數位資料路徑整合符合、控制仍由外部提供 | 已整合Input Path、A/B decoders、mode routing、128×128 Array、雙Accumulator與`sume/sumo`；不含自動FSM、類比precharge及pad mux；Macro testbench已暫接serializer完成整合時序驗證 |
| `dcim_chip_pin_top` | 數位pin資料流符合、實體IO仍為抽象 | 已正式整合Macro、單一SRAM read serializer及`mode_sel`控制的`sumo/read` MUX；不暴露debug buses，不含PAD反相、電壓、類比SA/precharge或非揮發控制行為 |

### 13.1 FeSRAM模型不是講義中的實體Cell

目前 `fesram_cell_model` 使用：

```text
posedge clk + write_en → 一個FF儲存cell_bit
```

講義與Proposal描述的是SRAM cell加兩個FeRAM nonvolatile nodes，並包含SET/power-down相關控制。現在的 `nv_store`、`nv_recall`、`pd_en`只是保留port，對資料完全沒有作用；實體SRAM寫入也不是由這個RTL中的FF clock精確重現。

這是目前與講義差距最大的底層模型之一，但依要求此次不修改。

### 13.2 Tri-State Buffer被零值抽象取代

Proposal明確說明cell旁有NOR gate及tri-state buffer。目前 `dcim_cell_logic`只有NOR，inactive cell直接輸出0。這對後續數位adder的功能結果可等價，但不能驗證high-Z bus、output enable衝突、類比負載或tri-state timing。

### 13.3 SRAM Read Path與講義不完全相同

講義pin與投影片包含：

```text
pre_en / Prec_en
sense_en
write driver
sense amplifier
共用read output pin
```

目前`dcim_row_4bit`直接組合讀出storage bits，Bank、Row Group及Array只做組合式one-hot/OR選擇，不再各自暫存。`sram_read_serializer_8bit`是唯一的clocked read-output stage：`sense_en`使兩份4-bit資料與valid在第一個正緣前穩定，該正緣載入`{even,odd}`並立即看到bit[7]。`read_valid`只是RTL內部擷取條件，不是講義chip pin。

`sram_read_serializer_8bit`已經完成8-clock serial read的數位功能：兩個4-bit read results同時valid時載入`{even,odd}`，再MSB-first送出。它刻意輸出logical read value；講義模擬中因缺少output PAD所觀察到的反相值只列為testbench參考，不寫死在serializer內。Pin Top現已將這個serial bit與CIM `sumo`接到chip-level 2-to-1 logical mux。

講義第12頁支持「選定兩個Banks形成8-bit並以8 clocks讀出」，但沒有明示digital register位置。本次單一暫存器位置與「第一個`sense_en`有效正緣即取得bit[7]」是依已確認的專案時序規格；`pre_en`、sense-amplifier建立時間與類比延遲仍未建模。

### 13.4 Input Path已依第3頁重構

`input_buffer_32x4`現在把第3頁所畫的電路分成三層：

```text
4 Din lanes × 8 DFF stages
    → sel_next one-to-two routing
    → 前兩級再經mode_sel routing，全部CIM taps再做one-to-four fanout
```

第9頁波形顯示`sela`在八個Input loading clocks期間為0，資料完成後才切為1；因此RTL定義`sel_next=0`為shift、`sel_next=1`為expose taps。第14頁明確說明`mode_sel=1`為CIM mode，這兩個定義已寫入testbench。

第3頁只有每條Din lane的前兩級DFF後方畫出第二個`mode_sel` demux，剛好提供2×4=8-bit SRAM資料；其餘六級直接連接CIM buffer。因此RTL也只在CIM rows 0～7套用`mode_sel` gating。SRAM mode下rows 8～31仍有數位線值，但Column/NOR control必須讓`cim_en=0`，不會真的執行CIM。

仍屬RTL抽象而不是簡報直接規格的部分如下：

1. 使用active-low asynchronous `rst_n`，簡報只標示`rst`且後續頁面曾討論刪除input reset，未提供最終DFF reset電路。
2. `buffered_bits`是方便整合與驗證的內部觀察bus，不是晶片pin。
3. Demux與one-to-four buffer以理想組合邏輯表示，沒有電壓、drive strength、gate delay或fanout負載。
4. High-nibble-first不是只由第3頁決定；它由第12頁的`9`再`1`形成`8'h91`例子交叉確認。

### 13.5 Row Group符合32×128結構邊界

`dcim_row_group`依第2頁實例化32個32×4 Segments，形成一個32-row×128-column group。Pair `p`固定連接segments `2p/2p+1`；兩者共用SRAM/CIM pair enable，但保有獨立4-bit write/read data與32筆4-bit row products。CIM必須同時滿足`cim_pair_en[p]`及`cim_group_en`，對應第4～5頁NAND input中的column enable與row-group enable。

為降低FPGA資源，本層不再為32個Banks各自建立Adder Tree，而是先用one-hot pair enable把唯一有效的Even/Odd row-product vectors送往Array。這維持合法控制下的計算結果，但不同於講義每個Segment旁配置局部Adder Tree的實體layout。

### 13.6 完整Array保持128×128 cells，算術改為兩棵共享Adder Tree

`dcim_array_128x128`已實例化四個`dcim_row_group`，總共形成128個32×4 segments及16384個1-bit cells。`wl_select[127:0]`切成四個32-bit slices；四份activation fanout與`cim_group_select[3:0]`分別接到對應group。這與`0622.pptx`第2頁及Proposal Figure 4的array分割一致。

每個Row Group先選pair，Array再將四組Even/Odd row-product vectors以one-hot OR方式選出唯一有效group，最後分別送入`u_shared_even_adder_tree`與`u_shared_odd_adder_tree`。完整正式階層因此只有兩棵Adder Tree，而非原本4×32=128棵。

這是FPGA資源共享最佳化：外部9-bit partial sums、Accumulator介面與合法one-hot操作的數學結果不變，但不再逐一重現講義中每個Segment旁的局部Adder Tree layout。`bank_output_or_tree.sv`保留作原始講義架構的獨立參考，不列入正式Array/Macro source hierarchy。

Array內的SRAM read merging是組合式數位OR/valid抽象，不含register；唯一read register位於後級serializer。這仍不代表簡報中precharge、8組sense amplifiers及read output pad的完整類比電路。

### 13.7 Accumulator與Serial Output的RTL切分

Accumulator在前8次accepted `output_en`執行shift-and-add，並以內部3-bit counter辨認第8次。第8次後產生內部`final_sample`，把包含最後一筆partial sum的`next_acc`直接載入serial stage，並鎖住第9筆直到`reset1`。講義第14頁確認了`output_en`的必要性，但沒有畫出counter；counter是為滿足已確認的固定UINT8與自動輸出時序所做的RTL控制抽象。

講義把累加與序列輸出畫在同一個`acc` block內；RTL的頂層模組邊界也維持一個`bitserial_accumulator`代表一條完整ACC，只把shift register寫成內部子模組以便單獨驗證。Macro Core各實例化一份：

```text
selected_even_sum → bitserial_accumulator（ACC + serial_output）→ sume
selected_odd_sum  → bitserial_accumulator（ACC + serial_output）→ sumo
```

仍存在三個整合假設：

1. 講義畫出`reset1/reset2`但未提供完整內部電路與極性；目前依已確認規格採active-high asynchronous reset：`reset1`清ACC，`reset2`清serial stage。
2. Serializer採MSB-first；這與講義7200輸出波形的前導0、連續`111`及後續單一`1`位置相符，但簡報沒有用文字定義bit編號。
3. 子模組的`load`由第8次`output_en`在ACC內部產生；Macro Core不再接收外部`serial_load`。`serial_active`只供內部控制/驗證，不是實體pin。

### 13.8 Decoder與組合邏輯未模擬實體延遲

`5_27.pptx`第6頁指出decoder地址切換時可能出現新舊輸出短暫重疊，再由 `wl_en` 保護。目前RTL是零延遲理想組合邏輯，testbench只驗證在地址切換時先關閉 `wl_en` 的安全流程，不能證明gate-level glitch或post-layout timing。

Adder tree、OR tree及NAND/NOR同樣只驗證Boolean/數值結果，未重現投影片中的ns級delay、PVT或佈線負載。

## 14. 尚未實作的CIM_CHIP模組

下列檔案目前只有空的module shell，不能視為已完成或已符合講義：

```text
peripheral/nv_power_controller.sv
```

KWS backend、window generator、layer controller、PE/DCIM routing、pooling與
requantization屬於`../HYBRID_SYSTEM`，已從CIM_CHIP移除。

與CIM_CHIP已知差異直接相關的後續責任為：

- `nv_power_controller`：實作SET、store/recall與power-down sequencing。
- `sram_read_serializer_8bit`與`dcim_chip_pin_top`已完成正式整合及獨立Pin Top testbench，不再屬於Skeleton。

### 14.1 `dcim_chip_pin_top`已完成架構

依`0622.pptx`第11～15頁的pin表、SRAM讀取例子及Output Path，Pin Top只做晶片腳位包裝與最後輸出選擇，不重複實作Array或控制FSM：

```text
外部 A[6:0]、B[3:0]、Din[3:0]、控制腳
                    │
                    ▼
             dcim_macro_core
        ┌───────────┴───────────┐
        │                       │
組合式 even/odd read       CIM sume / sumo
        │                       │
        ▼                       │
sram_read_serializer_8bit       │
  第1個sense edge出bit[7]       │
        │ serial_read_bit       │
        └───────────┬───────────┘
                    ▼
            mode_sel 2-to-1 MUX
        SRAM(0): serial_read_bit
        CIM (1): sumo
                    │
                    ▼
              共用sumo/read pin

sume在CIM模式維持even accumulator的正常邏輯輸出。
```

已實作介面原則：

1. `mode_sel=0`選SRAM serial read，`mode_sel=1`選CIM `sumo`，與現有Input/Bank routing定義一致。
2. 最終輸出使用正常邏輯，不在RTL加入PAD前反相；若實體IO cell反相，留到PAD wrapper或gate-level模型處理。
3. `sense_en`只需維持一個capture clock，否則serializer會在每拍重新載入；其後七拍解除`sense_en`完成bit[6:0] shift。
4. `pre_en`與NV控制腳保留，但目前不產生類比precharge、store/recall或power-down行為。
5. Macro的parallel read data、`read_valid`、partial sums與accumulated sums是內部驗證訊號，不增加為實體chip pins。
6. `reset1/reset2`依已確認規格使用active-high。`reset2`同時清除ACC output與SRAM read serializer；`model_rst_n`仍保留為FF模型初始化介面，因為講義未列出其對應實體pin。

與講義相符的部分是128×128 Macro、A/B/Din與mode/control資料路徑、雙ACC輸出、兩個4-bit Bank形成8-bit serial read，以及SRAM/CIM共用odd/read輸出路徑。無法由講義確認、因此仍屬RTL假設的部分是serializer內部暫存器的實體位置、`read_valid`內部handshake、reset電路細節、PAD極性與類比precharge/SA timing。

目前可宣稱128×128晶片的可合成數位功能路徑、SRAM/CIM mode routing及序列輸出行為已在RTL與testbench中完成；仍不能宣稱已重現講義中的FeRAM電性、類比SA/precharge、實體PAD、PVT與post-layout timing。

### 14.2 `dcim_pin_master`已完成

SRAM Read已省略每筆命令的Reset狀態：Capture完整覆寫Serializer，接受start到done為9 clocks（50 MHz下180 ns），下一命令最早於11 clocks後接受。系統reset與CIM reset仍保留。

`make test-dcim-pin-master`對每筆讀取檢查9-clock延遲、Read期間reset1/reset2皆不啟用，以及8-bit讀回資料。情境包括初始化後讀零、Write後Read、連續讀FF／00／A5、Burst後跨列逐筆讀回、A4W8及A8W8計算後立即發出Read。保留原有Burst 3N clocks與CIM算術結果驗證。`make test-dcim-master-chip-top`及`make test-dcim-cdc-integration`驗證上層控制器可適應縮短的Read延遲。

`dcim_pin_master`將Weight Write、SRAM Read與CIM Compute命令轉成Chip Pin Top所需的多clock控制腳位時序。它支援A4與A8 activation；A4先送四個零plane再送bit 3～0，兩者都符合現有Accumulator固定接受八次`output_en`的規格。測試會連接真實Chip Top，驗證SRAM read、A4W8、A8W8、Even/Odd結果與非法命令處理。完整狀態與操作方式見`DCIM_PIN_MASTER_ARCHITECTURE.md`。

### 14.3 `dcim_cdc_bridge`已完成

`dcim_cdc_bridge`使用單筆outstanding command mailbox、request/response toggle與雙2-FF synchronizer，在125 MHz backend domain和50 MHz Pin Master domain之間傳送278-bit命令與46-bit結果。它不包含line buffer或數值後處理。

`tb_dcim_cdc_bridge`使用3 ns clock phase offset、variable-latency mock master、36筆固定/隨機命令與response backpressure驗證CDC協定；`tb_dcim_cdc_bridge_integration`再連接真實Pin Master及128×128 Chip Top，驗證Write、Read、A4W8、A8W8與錯誤狀態。完整設計與接線方式見`DCIM_CDC_BRIDGE_ARCHITECTURE.md`。
