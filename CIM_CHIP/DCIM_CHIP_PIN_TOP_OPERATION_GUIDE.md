# DCIM Chip Pin Top操作與驗證說明

## 1. 文件目的

本文件說明如何透過`dcim_chip_pin_top`的外部介面完成：

1. 初始化與Reset。
2. 寫入一個8-bit Weight。
3. 從SRAM模式序列讀回一個8-bit Weight。
4. 載入32筆UINT8 Activation並完成一次A8×W8運算。
5. 從`sume`與`sumo`重建Even/Odd 18-bit結果。
6. 執行Top-level testbench的全陣列隨機驗證。

這是可合成數位模型的操作規格，不代表真實FeRAM電性、Precharge或Sense Amplifier類比延遲。

## 2. Top介面

RTL檔案：[`chip/dcim_chip_pin_top.sv`](./chip/dcim_chip_pin_top.sv)

| 訊號 | 方向 | 位寬 | 功能 |
|---|---|---:|---|
| `clk` | Input | 1 | 系統與Input Buffer時脈 |
| `model_rst_n` | Input | 1 | Active-low數位Cell/Input Buffer初始化Reset |
| `reset1` | Input | 1 | Active-high Accumulator Reset |
| `reset2` | Input | 1 | Active-high CIM/SRAM Serial Output Reset |
| `row_addr` | Input | 7 | SRAM選擇0～127列；CIM使用`row_addr[6:5]`選擇四個Row Groups |
| `bank_addr` | Input | 4 | 選擇0～15 Bank Pairs |
| `mode_sel` | Input | 1 | `0`：SRAM；`1`：CIM |
| `wl_en` | Input | 1 | SRAM Word Line Enable |
| `write_en` | Input | 1 | SRAM寫入命令 |
| `sense_en` | Input | 1 | SRAM讀取Sense/Capture命令 |
| `pre_en` | Input | 1 | 保留的Precharge腳位；目前數位模型無功能 |
| `clk_en` | Input | 1 | 允許Input Buffer Shift |
| `sel_next` | Input | 1 | `0`：Shift Input Buffer；`1`：輸出已保存的Taps |
| `din` | Input | 4 | 每個Clock輸入一個4-bit Nibble |
| `output_en` | Input | 1 | 接受目前9-bit Partial Sum進入Bit-serial Accumulator |
| `nv_store` | Input | 1 | 保留的NV控制腳，目前無功能 |
| `nv_recall` | Input | 1 | 保留的NV控制腳，目前無功能 |
| `pd_en` | Input | 1 | 保留的Power-down腳，目前無功能 |
| `sume` | Output | 1 | Even Accumulator的18-bit MSB-first序列輸出 |
| `sumo` | Output | 1 | CIM模式為Odd序列輸出；SRAM模式為8-bit Read序列輸出 |

## 3. Reset順序

初始化時使用：

```text
model_rst_n = 0
reset1      = 1
reset2      = 1
等待至少兩個clk上升緣

model_rst_n = 1
reset1      = 0
reset2      = 0
```

- `model_rst_n=0`會清除FPGA模型中的Weight Cells與Input Buffer。
- `reset1=1`只清除Accumulator，不會擦除Weights。
- `reset2=1`只清除Serial Output，不會擦除Weights。

## 4. Weight與Bank Pair排列

完整Array具有：

```text
128 rows × 128 columns
= 128 rows × 16 pairs × 8 bits
= 2048個8-bit Weight words
```

每個`bank_addr`選擇一組相鄰的Even/Odd 4-bit Banks：

```text
Bank Pair p
├── Even Bank：Weight[7:4]
└── Odd Bank ：Weight[3:0]
```

因此目前專案的W8結果重組公式是：

```text
W8_result = odd_result + (even_result << 4)
```

## 5. 寫入一個8-bit Weight

寫入範例：將`8'hA5`寫到`row_addr=0`、`bank_addr=0`。

| Clock | 控制與資料 | 動作 |
|---:|---|---|
| 1 | `mode_sel=0, sel_next=0, clk_en=1, din=4'hA` | 載入High Nibble |
| 2 | `mode_sel=0, sel_next=0, clk_en=1, din=4'h5` | 載入Low Nibble |
| 3 | `clk_en=0, sel_next=1, row_addr=0, bank_addr=0, wl_en=1, write_en=1` | 將`8'hA5`寫入選定Pair |
| 4 | `wl_en=0, write_en=0` | 結束交易 |

High Nibble必須先送入，因為兩個Nibble經過Input Buffer shift後形成：

```text
sram_write_data = {stage1, stage0} = {High, Low}
```

## 6. SRAM序列讀取

讀取選定Row/Pair時：

| Clock | 控制 | `sumo`內容 |
|---:|---|---|
| 1 | `mode_sel=0, row_addr=A, bank_addr=B, wl_en=1, sense_en=1` | Read Word bit[7] |
| 2 | `sense_en=0, wl_en=0` | bit[6] |
| 3 | 保持Sense關閉 | bit[5] |
| ... | ... | ... |
| 8 | 保持Sense關閉 | bit[0] |

`sense_en`只能維持一個Capture Clock；若持續保持為1，Serializer會重複載入同一個Byte而不會正常Shift。

## 7. 載入一個32-bit Activation Plane

Input Buffer是四條Lanes、每條八級DFF。每個Clock輸入4 bits，因此32-bit Activation Plane需要8個Clocks。

載入順序必須由Stage 7到Stage 0：

```text
Clock 1：plane_bits[31:28]
Clock 2：plane_bits[27:24]
...
Clock 7：plane_bits[7:4]
Clock 8：plane_bits[3:0]
```

載入期間：

```text
mode_sel = 1
sel_next = 0
clk_en   = 1
```

載入完成後：

```text
clk_en   = 0
sel_next = 1
```

## 8. 完成一次UINT8 CIM運算

假設一個Group具有32筆UINT8 Activations：

```text
A[0], A[1], ..., A[31]
```

控制器必須由Activation bit 7到bit 0產生八個bit planes：

```text
plane7[row] = A[row][7]
plane6[row] = A[row][6]
...
plane0[row] = A[row][0]
```

每個Plane的操作為：

1. 用8個Clocks將32 bits載入Input Buffer。
2. 設定`row_addr[6:5]`選擇Group。
3. 設定`bank_addr`選擇Bank Pair。
4. Pulse一次`output_en`。
5. Accumulator執行：

```text
next_acc = (acc << 1) + partial_sum
```

八個Planes全部完成後：

```text
even_result = Σ A[row] × Weight[row][7:4]
odd_result  = Σ A[row] × Weight[row][3:0]
W8_result   = odd_result + (even_result << 4)
```

## 9. Row Group選擇

| Group | `row_addr[6:5]` | 對應Global Weight Rows |
|---:|---:|---:|
| 0 | `00` | 0～31 |
| 1 | `01` | 32～63 |
| 2 | `10` | 64～95 |
| 3 | `11` | 96～127 |

每次CIM交易只計算其中一個32-row Group。若模型的一個dot product超過32項，例如Conv2的`3×3×12=108`，FPGA Backend必須執行四個Group並在外部加總。

## 10. 擷取18-bit CIM輸出

第八次有效`output_en`上升緣後，`sume`與`sumo`立即提供bit[17]。接著每個Clock依序輸出bit[16]到bit[0]：

```text
Clock 1：bit[17]
Clock 2：bit[16]
...
Clock 18：bit[0]
```

兩條輸出可以同時擷取：

```text
even_result[bit] = sume
odd_result[bit]  = sumo
```

此時必須保持`mode_sel=1`，否則`sumo`會切換到SRAM Read Serializer。

## 11. Top Testbench新增驗證

Testbench：[`tb/chip/tb_dcim_chip_pin_top.sv`](./tb/chip/tb_dcim_chip_pin_top.sv)

除了原本的Reset、`8'hA5/8'h32`寫入讀回與36/19 CIM範例之外，現在新增：

### 11.1 全陣列偽隨機寫入

固定初始State：

```text
random_state = 32'h1A2B3C4D
```

每個Weight使用以下LCG更新，因此每次測試完全可重現：

```text
random_state = random_state × 1664525 + 1013904223
weight       = random_state[31:24]
```

測試會寫入：

```text
128 rows × 16 pairs = 2048個8-bit words
```

等同覆蓋全部16,384個1-bit Cells。大量寫入不逐筆輸出，只在每完成32 rows時顯示進度。

### 11.2 SRAM Read抽樣

寫完後透過真實`sumo`序列路徑讀回八組邊界與中間地址，包括Row 0、31、32、63、64、95、96與127。

### 11.3 Activation設定

四個Groups的32筆Activation使用固定非零公式：

```text
global_row = group × 32 + local_row
activation = ((global_row × 13 + 7) mod 255) + 1
```

所以Activation範圍為1～255，所有Rows都會參與計算。

### 11.4 Golden Model比對

測試共執行：

```text
4 groups × 16 bank pairs = 64個完整A8×W8 dot products
```

每一組都獨立比對：

1. 18-bit Even Accumulator。
2. 18-bit Odd Accumulator。
3. 21-bit W8重組結果。

任何一項不同都會顯示Group、Pair、Actual與Expected，並在測試結束時執行`$fatal(1)`。

## 12. 執行方式

在`CIM_CHIP`目錄下執行：

```bash
make test-chip-pin-top
```

完整Chip回歸測試：

```bash
make test-chip
```

完整專案回歸測試：

```bash
make test
```

靜態檢查：

```bash
make lint-chip
```

全陣列測試成功時，結尾應包含：

```text
PASS: all 2048 eight-bit words were programmed
PASS: 64/64 group-pair CIM cases matched Even, Odd and W8 golden results
PASS: complete dcim_chip_pin_top verification passed
```

## 13. 目前驗證邊界

這份測試可以證明：

- 所有Rows與Bank Pairs都能寫入並參與CIM計算。
- Four Row Groups與16 Bank Pair addresses沒有交叉覆寫。
- UINT8 Activation的八個bit planes順序正確。
- Even/Odd兩條18-bit輸出與W8重組公式正確。
- SRAM/CIM共用`sumo`的模式選擇正確。

這份測試仍不包含：

- 真實FeRAM/FeFET極化、Retention與Variation。
- 類比Precharge與Sense Amplifier延遲。
- FPGA端自動交易FSM；這將由`fpga/dcim_pin_master.sv`實作。
- CNN Window Generator、跨Group加總、Bias、Requantization、Activation與Pooling。

