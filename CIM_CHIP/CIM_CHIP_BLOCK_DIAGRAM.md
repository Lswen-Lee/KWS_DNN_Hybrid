# CIM_CHIP RTL 關係與方塊圖

本文件描述目前 `CIM_CHIP` 資料夾內**已實作的 RTL**。目前已採用「先選Bank Pair與Row Group，再使用Even/Odd兩棵共享Adder Tree」的FPGA最佳化，完整Array只實例化兩棵 `adder_tree_32x4`。

## 1. 完整階層關係

```mermaid
flowchart TB
    TOP[dcim_chip_pin_top<br/>晶片接腳頂層]
    CORE[dcim_macro_core<br/>DCIM 巨集整合核心]
    RDS[sram_read_serializer_8bit<br/>8-bit SRAM 序列讀出]
    OUTMUX{mode_sel<br/>SUMO 輸出選擇}

    TOP --> CORE
    TOP --> RDS
    CORE -- Even/odd 4-bit read data --> RDS
    CORE -- CIM sume --> SUME[sume]
    CORE -- CIM sumo --> OUTMUX
    RDS -- SRAM serial bit --> OUTMUX
    OUTMUX --> SUMO[sumo]

    subgraph MACRO[dcim_macro_core 內部]
        INBUF[input_buffer_32x4]
        WBUF[sram_write_buffer_8bit]
        ROWDEC[row_decoder_7to128]
        GRPDEC[cim_group_decoder_2to4]
        BANKDEC[bank_decoder_4to16]
        PAIRSEL[bank_pair_selector]
        ARRAY[dcim_array_128x128]
        ACCE[bitserial_accumulator<br/>Even ACC]
        ACCO[bitserial_accumulator<br/>Odd ACC]
        SOE[serial_output<br/>Even 18-bit MSB-first]
        SOO[serial_output<br/>Odd 18-bit MSB-first]

        INBUF --> WBUF
        WBUF -- 8-bit weight write data --> ARRAY
        INBUF -- 4 x 32-bit activation fanout --> ARRAY
        ROWDEC -- 128-bit SRAM WL one-hot --> ARRAY
        GRPDEC -- 4-bit CIM group one-hot --> ARRAY
        BANKDEC -- 16-bit pair one-hot --> PAIRSEL
        PAIRSEL -- SRAM/CIM pair enable --> ARRAY
        ARRAY -- even partial sum 9-bit --> ACCE
        ARRAY -- odd partial sum 9-bit --> ACCO
        ACCE --> SOE
        ACCO --> SOO
    end

    CORE -. contains .-> MACRO
```

> `serial_output` 實際上實例化在 `bitserial_accumulator` 內；圖中將它展開是為了顯示 18-bit 序列輸出階段。

## 2. 外部接腳到核心的控制關係

```mermaid
flowchart LR
    DIN[din 4-bit<br/>clk_en / sel_next] --> INBUF[input_buffer_32x4]
    MODE[mode_sel] --> INBUF
    MODE --> PAIR[bank_pair_selector]
    MODE --> MUX[SUMO output mux]

    RA[row_addr 7-bit] --> ROW[row_decoder_7to128]
    RA -- A6:A5 --> GROUP[cim_group_decoder_2to4]
    BA[bank_addr 4-bit] --> BANK[bank_decoder_4to16]
    BANK --> PAIR

    CTRL[write_en / sense_en<br/>wl_en / output_en] --> CORE[Macro datapath]
    NV[nv_store / nv_recall / pd_en] -. retained pins<br/>currently no function .-> CORE
    PRE[pre_en] -. physical precharge pin<br/>currently no digital effect .-> CORE
```

地址意義：

| 訊號 | 解碼結果 | 目前用途 |
|---|---|---|
| `row_addr[6:0]` | 7-to-128 one-hot | SRAM mode 選一個實體 row |
| `row_addr[6:5]` | 2-to-4 one-hot | CIM mode 選一個 32-row group |
| `bank_addr[3:0]` | 4-to-16 one-hot | 選一個 even/odd bank pair |
| `mode_sel` | SRAM/CIM demux | `0` 選 SRAM pair，`1` 選 CIM pair |

## 3. Input Path

```mermaid
flowchart LR
    DIN[Din 4-bit] --> SHIFT[8 stages x 4 lanes DFF<br/>input_buffer_32x4]
    SHIFT -- stage 1 : stage 0 --> WDATA[8-bit SRAM write word]
    SHIFT -- 32 buffered bits --> TAP[CIM tap selection]
    TAP --> G0[Group 0 activation 32-bit]
    TAP --> G1[Group 1 activation 32-bit]
    TAP --> G2[Group 2 activation 32-bit]
    TAP --> G3[Group 3 activation 32-bit]
```

- SRAM mode：前兩個 4-bit DFF stage 組成 `{stage1, stage0}` 的 8-bit write word。
- CIM mode：八個 stage 共形成 32 個 activation bits，並以一對四 fanout送到四個row groups。
- activation雖然廣播到四組，但 `cim_group_select[3:0]` 為one-hot，正常操作只允許一組產生有效結果。

## 4. 128 x 128 Array 結構

```mermaid
flowchart TB
    ARRAY[dcim_array_128x128]

    subgraph GROUPS[4 個 32-row groups]
        G0[dcim_row_group 0<br/>32 banks]
        G1[dcim_row_group 1<br/>32 banks]
        G2[dcim_row_group 2<br/>32 banks]
        G3[dcim_row_group 3<br/>32 banks]
    end

    ARRAY --> G0
    ARRAY --> G1
    ARRAY --> G2
    ARRAY --> G3

    G0 --> PAIRSEL[每組先以cim_pair_en<br/>選出Even/Odd row products]
    G1 --> PAIRSEL
    G2 --> PAIRSEL
    G3 --> PAIRSEL

    PAIRSEL --> GROUPSEL[cim_group_select<br/>選出一組32筆row products]
    GROUPSEL --> EADD[Shared Even adder_tree_32x4]
    GROUPSEL --> OADD[Shared Odd adder_tree_32x4]
    EADD --> EVEN[selected_even_sum 9-bit]
    OADD --> ODD[selected_odd_sum 9-bit]
```

Array容量計算：

```text
4 groups
x 32 banks/group
x 32 rows/bank
x 4 cells/row
= 16,384 cells = 128 x 128 bits
```

正常CIM操作只選中一個位置：

```text
1個 row group x 1個 bank pair
                    ├── Even 32x4 bank
                    └── Odd  32x4 bank
```

未選bank的row products為0，因此pair與group選擇可使用one-hot OR mux；完成選擇後才進入兩棵共享加法樹。

## 5. 一個 Row Group 與 Bank Pair

```mermaid
flowchart TB
    RG[dcim_row_group<br/>32 rows x 128 columns]
    SEL[cim_pair_en 16-bit one-hot]

    subgraph PAIRS[16 個 Bank Pairs]
        P0[Pair 0<br/>Bank 0 Even + Bank 1 Odd]
        P1[Pair 1<br/>Bank 2 Even + Bank 3 Odd]
        PX[...]
        P15[Pair 15<br/>Bank 30 Even + Bank 31 Odd]
    end

    RG --> PAIRS
    SEL --> P0
    SEL --> P1
    SEL --> P15

    P0 --> E[dcim_bank_32x4<br/>Even]
    P0 --> O[dcim_bank_32x4<br/>Odd]
```

每個pair共享同一個pair enable，但even與odd bank具有獨立的：

- 4-bit write data。
- 4-bit SRAM read data。
- 9-bit CIM partial sum。

SRAM read不把32個bank輸出全部送往Array；Row Group先用
`sram_pair_en[15:0]`選出一組Pair，再只輸出：

```text
selected_even_read_data[3:0]
selected_odd_read_data[3:0]
selected_pair_read_valid
```

目前核准的8-bit寫入排列為：

```text
even bank = sram_write_data[7:4]
odd bank  = sram_write_data[3:0]
```

## 6. Bank、Row與Cell的階層

```mermaid
flowchart TB
    BANK[dcim_bank_32x4<br/>32 rows x 4 weight bits]

    subgraph ROWS[32 個 dcim_row_4bit]
        R0[Row 0<br/>4 cells]
        R1[Row 1<br/>4 cells]
        RD[...]
        R31[Row 31<br/>4 cells]
    end

    BANK --> ROWS
    R0 -- row_product 4-bit --> OUT[32筆row_product輸出]
    R1 -- row_product 4-bit --> OUT
    R31 -- row_product 4-bit --> OUT
    OUT --> SELECT[Row Group/Array選擇網路]
    SELECT --> ADD[Array層共享adder_tree_32x4]
    ADD --> SUM[selected sum 9-bit<br/>maximum 32 x 15 = 480]

    R0 --> C0[4 x dcim_cell_logic]
    C0 --> FF[fesram_cell_model<br/>1 FF stores 1 weight bit]
```

目前Adder Tree數量：

```text
Even path 1棵 + Odd path 1棵 = 2棵 adder_tree_32x4
```

`bank_output_or_tree.sv`仍保留為講義原始Output Path的獨立參考與單元測試，但已不在正式Array/Macro合成階層中。

## 7. 單一Cell的寫入、讀取與CIM邏輯

```mermaid
flowchart LR
    WD[write_data] --> FF[1-bit FF<br/>cell_bit]
    WE[write_en] --> FF
    FF --> Q[Q = weight]
    FF --> QB[QB = inverted weight]

    ACT[activation_bit] --> NAND[Input Control NAND<br/>IN_b = NOT cim_en AND cim_row AND activation]
    CE[cim_en / cim_row] --> NAND
    NAND --> NOR[Cell NOR]
    QB --> NOR
    NOR --> PROD[cim_product<br/>activation AND weight]

    Q --> READ{sense_en}
    READ --> RDATA[read_data]

    NV[nv_store / nv_recall / pd_en] -. interface retained<br/>no effect in current 1-FF model .-> FF
```

數學關係：

```text
IN_b       = ~(cim_en & cim_row & activation)
QB         = ~weight
cim_product = ~(IN_b | QB)
            = cim_en & cim_row & activation & weight
```

## 8. CIM輸出路徑

```mermaid
flowchart LR
    PS[Selected 9-bit partial sum<br/>one activation bit-plane]
    ACC[bitserial_accumulator<br/>ACC = ACC shift-left 1 + partial_sum]
    COUNT[8 accepted output_en cycles]
    SERIAL[serial_output<br/>18-bit MSB-first]
    PIN[sume or CIM sumo]

    PS --> ACC
    COUNT --> ACC
    ACC --> SERIAL
    SERIAL --> PIN
```

Even與Odd各有一條完全獨立的路徑：

```text
selected_even_sum -> Even ACC -> sume
selected_odd_sum  -> Odd ACC  -> core_sumo
```

第8次有效 `output_en` 正緣後，Accumulator完成8個UINT8 activation bit planes的累積，並立即讓序列輸出的bit 17成為第一個輸出bit。

## 9. SRAM讀出路徑

```mermaid
flowchart LR
    CELL[Selected SRAM row]
    BANK[Row Group選出Even/Odd bank pair]
    GROUP[Array選出1 of 4 row groups]
    DATA[even 4-bit + odd 4-bit]
    SER[sram_read_serializer_8bit<br/>bit 7 first]
    MUX{mode_sel}
    SUMO[sumo pin]

    CELL --> BANK --> GROUP --> DATA --> SER --> MUX --> SUMO
    CIM[Odd CIM serial output] --> MUX
```

- Row Group先選1 of 16 bank pairs，Array再選1 of 4 row groups；到serializer之前皆是組合式read selection。
- 上層介面只有兩份4-bit data和一個`selected_pair_read_valid`，不再攜帶32組raw bank read buses。
- `sram_read_serializer_8bit` 是SRAM read path唯一的clocked output stage。
- `mode_sel=0`：`sumo`輸出SRAM serial read bit。
- `mode_sel=1`：`sumo`輸出Odd CIM accumulator結果。
- `sume`固定用於Even CIM accumulator結果。

## 10. CIM_CHIP的完成邊界

```mermaid
flowchart LR
    subgraph DONE[已實作並通過回歸測試]
        CHIP[chip/]
        PERI[peripheral/ 除NV controller]
        ARRAY2[array/]
        SEG[segment/]
        CELL2[cell/]
        PM[dcim_pin_master]
        CDC[dcim_cdc_bridge]
    end

    subgraph TODO[仍未實作的實體晶片行為]
        NVPC[nv_power_controller]
        ANALOG[FeFET / SA / precharge電性]
    end

    CDC --> PM --> CHIP
    NVPC -. future NV sequence .-> CHIP
    ANALOG -. technology-specific model .-> CHIP
```

`window_generator`、KWS layer controller、DCIM backend、requantization與完整
KWS system top屬於`../HYBRID_SYSTEM`，不屬於CIM_CHIP，因此不在本資料夾保留
空module。

目前尚未在RTL中重現：

- FeRAM/FeFET電性、極化與遲滯。
- 真實的NV store、power-down與recall狀態保存。
- Precharge與Sense Amplifier類比時序。
- 完整KWS layer/window/controller資料流；該部分由`HYBRID_SYSTEM`負責。
- 共享Adder Tree的pipeline版本；目前兩棵樹仍為組合邏輯。

## 11. 主要檔案對應

| 階層 | 模組 | 主要功能 |
|---|---|---|
| Chip | `dcim_chip_pin_top` | 外部pin、SRAM serializer、SUMO mode mux |
| Chip | `dcim_macro_core` | 解碼器、Array與兩條Accumulator整合 |
| Array | `dcim_array_128x128` | 四組product選擇與Even/Odd兩棵共享Adder Tree |
| Array | `dcim_row_group` | 16個bank pairs，共32個banks，先選pair products |
| Array | `bank_pair_selector` | SRAM/CIM模式下的pair enable |
| Array | `bank_output_or_tree` | 保留的講義原始OR tree參考；正式Array不再實例化 |
| Segment | `dcim_bank_32x4` | 32列權重、read mux與32筆4-bit row products |
| Segment | `dcim_row_4bit` | 同一activation對四個weight bits運算 |
| Segment | `adder_tree_32x4` | 32個4-bit product加總為9-bit |
| Cell | `dcim_cell_logic` | NOR型1-bit DCIM乘法 |
| Cell | `fesram_cell_model` | 目前以一個FF保存1-bit weight |
| Peripheral | `input_buffer_32x4` | 4-lane、8-stage輸入buffer與四組fanout |
| Peripheral | `bitserial_accumulator` | 8個bit planes累積及18-bit序列輸出 |
| Peripheral | `sram_read_serializer_8bit` | 8-bit SRAM資料MSB-first輸出 |
