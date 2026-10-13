# 後處理數學說明：k 的來源與 Q31／PoT 比較

本文整理目前 UINT8 activation、INT8 weight、zero-point＝128、無 bias 的後處理架構。本文只說明現有設計，不變更 RTL。

## 1. 核心觀念

**k 是把 INT32 乘加結果換成下一層 UINT8 時，需要使用的縮放右移量。**

後處理不是直接截取 INT32 的八個位元，而是將「乘加結果的比例尺」轉換成「下一層 activation 的比例尺」，再捨入、加上 zero-point、限制輸出範圍。

## 2. 量化數值與變數定義

量化整數和實數的關係為：

$$
a_i \approx s_a(A_i-128)
$$

$$
w_{c,i}\approx s_{w,c}W_{c,i}
$$

| 變數 | 定義 |
|---|---|
| $a_i$ | 原本實數 activation |
| $A_i$ | UINT8 activation，範圍 0～255 |
| $128$ | activation zero-point；整數 128 代表實數 0 |
| $s_a$ | 輸入 activation scale |
| $w_{c,i}$ | 第 c 個輸出 channel 的實數權重 |
| $W_{c,i}$ | INT8 權重，範圍 −128～127；weight zero-point 為 0 |
| $s_{w,c}$ | 第 c 個輸出 channel 的 weight scale |
| $i$ | 內積中的項目索引 |
| $c$ | 輸出 channel／filter 索引 |
| $K$ | 內積長度，例如 Conv2 為 12×3×3＝108 |
| $ACC_c$ | 第 c 個輸出的 INT32 整數乘加結果 |
| $s_y$ | 輸出 activation scale |
| $Q_c$ | 重新量化後的 UINT8 輸出 |
| $M_c$ | 重新量化倍率 |
| $k_c$ | 第 c 個輸出的右移量；不是內積長度 K |

例如 s_a＝0.125、A＝136，表示的實數為 0.125×(136−128)＝1。

## 3. 從乘加推導重新量化公式

目前不包含 bias，PE／DCIM 路徑應交給後處理的整數結果為：

$$
ACC_c=\sum_{i=0}^{K-1}(A_i-128)W_{c,i}
$$

這個整數代表的實數約為：

$$
y_c\approx s_a s_{w,c}ACC_c
$$

下一層用自己的 scale 表示同一個值：

$$
y_c\approx s_y(Q_c-128)
$$

將兩式合併，得到：

$$
Q_c=\operatorname{clip}_{0,255}\left(
\operatorname{Round}\left(ACC_c\frac{s_a s_{w,c}}{s_y}\right)+128
\right)
$$

其中 clip 代表飽和限制：小於 0 輸出 0，大於 255 輸出 255；不是溢位後截斷。

## 4. k 是怎麼來的？

定義倍率：

$$
M_c=\frac{s_a s_{w,c}}{s_y}
$$

PoT（Power of Two）將 scale 限制成二的整數次方：

$$
s_a=2^{e_a},\quad s_{w,c}=2^{e_{w,c}},\quad s_y=2^{e_y}
$$

所以：

$$
M_c=2^{e_a+e_{w,c}-e_y}=2^{-k_c}
$$

$$
k_c=e_y-e_a-e_{w,c}=-\log_2\left(\frac{s_a s_{w,c}}{s_y}\right)
$$

因此乘上 M_c 等同於除以 2 的 k_c 次方，可以用右移加上捨入邏輯實現。

### 軟體來源

目前 [KWS_result_pot.ipynb](../../../KWS_result_pot.ipynb) 使用 `POT_ROUNDING = "ceil"`，對正 scale 做：

$$
s_{\mathrm{PoT}}=2^{\lceil\log_2(s)\rceil}
$$

流程如下：

```text
軟體取得量化 scale
        ↓
將 scale 調整成 2 的次方
        ↓
由 input／weight／output scale 計算各 channel 的 k
        ↓
匯出到硬體 shift ROM
        ↓
硬體用 layer_id、channel_id 查詢 shift_amount
```

硬體不需要每筆計算 log2。更換模型時，必須同時核對 weights、scales 與 shift ROM，不能只換權重。

目前 [kws_pot_shift_rom.sv](../rtl/datapath/kws_pot_shift_rom.sv) 的數值為：

| Layer | k 的數值集合 |
|---|---|
| Conv1 | 8、9 |
| Conv2 | 7、8、9 |
| Conv3 | 8、9、10 |
| FC1 | 7、8 |
| FC2 | 6 |

因為 weight scale 可以逐 channel 不同，所以同一層的 k 不一定相同。現有 RTL 支援 k＝0～31 的右移；若新模型需要負 k，必須另行設計左移與溢位處理。

## 5. 完整數值例子

以下使用示意 scale，不代表特定實際 channel：

$$
s_a=2^{-4},\quad s_w=2^{-7},\quad s_y=2^{-3}
$$

$$
M=\frac{2^{-4}2^{-7}}{2^{-3}}=2^{-8},\quad k=8
$$

若 ACC＝2560：

$$
Q=\operatorname{clip}_{0,255}(2560/256+128)=138
$$

輸出代表的實數為：

$$
s_y(Q-128)=2^{-3}\times10=1.25
$$

乘加結果原本代表的實數為：

$$
s_as_wACC=2^{-11}\times2560=1.25
$$

兩者一致。右移不是任意縮小數字，而是在轉換比例尺。

## 6. 目前硬體後處理公式與資料流

PoT requantizer 實作：

$$
Q_c=\operatorname{clip}_{0,255}\left(
\operatorname{RNE}(ACC_c/2^{k_c})+128\right)
$$

RNE 是 round-to-nearest-even：選最近的整數，恰好一半時選偶數，例如 2.5→2、3.5→4。

**單純使用 `>>> k` 不等於完整的 RNE。** 還需要檢查餘數與半值，決定是否進位，包括負數的正確處理。

若啟用 ReLU：

$$
Q_{\mathrm{ReLU},c}=\max(Q_c,128)
$$

實數零對應整數 128，因此 ReLU 門檻不是整數 0。

```text
INT32 ACC
    │
    ▼
查詢 layer/channel 對應的 k
    │
    ▼
除以 2^k ＋ nearest-even 捨入
    │
    ▼
加上輸出 zero-point 128
    │
    ▼
飽和限制到 0～255
    │
    ▼
可選 ReLU：小於 128 改成 128
    │
    ▼
結果 FIFO／valid-ready
    │
    ▼
外部依層別選擇儲存、MaxPool 或 Argmax
```

[pe_pot_result_stream.sv](../rtl/datapath/pe_pot_result_stream.sv) 負責查表、重新量化、可選 ReLU、標籤對齊與 FIFO 背壓控制。組合版與管線版的目標數學公式相同，差異在暫存切分與延遲；組合版仍有結果 FIFO，不代表整個 stream 模組都沒有暫存器。

### 後續 MaxPool 與 Argmax

兩者不在 `pe_pot_result_stream` 內，而由後續模組處理。

2×2 MaxPool 在同一 channel 的視窗內取最大值：

$$
P_{c,y,x}=\max_{u,v\in\{0,1\}}Q_{c,2y+u,2x+v}
$$

分類 Argmax：

$$
\mathrm{class}=\arg\max_{c\in\{0,\ldots,7\}}Q_c
$$

目前 FC2 輸出使用共用輸出 scale 與 zero-point，可在共同尺度下比較 UINT8 分數；同分時目前選最前面的類別。量化與飽和可能產生實數原本沒有的同分，因此不是保證與未量化分類永遠相同。

## 7. Q31 與 PoT 的差異

Q31 的 31 指倍率的小數位數，不是 activation 位元數。

### 原本 Q31 方式

$$
M_{\mathrm{Q31},c}=\operatorname{Round}(M_c2^{31})
$$

$$
Q_c=\operatorname{clip}_{0,255}\left(
\operatorname{Round}\left(\frac{ACC_cM_{\mathrm{Q31},c}}{2^{31}}\right)+z_y\right)
$$

z_y 是輸出 zero-point。原本 [requantizer_int32_to_uint8.sv](../rtl/datapath/requantizer_int32_to_uint8.sv) 使用 INT32 與倍率相乘，產生 64-bit 中間結果；目前舊版適用的倍率範圍為 0～1 之間。

### PoT 方式

倍率直接是 2 的負整數次方，不需要一般倍率乘法器。

| 比較內容 | 原本 Q31 | 現在 PoT |
|---|---|---|
| 倍率表示 | 32-bit 定點倍率 | 5-bit 右移量 |
| 支援倍率 | 可細緻近似一般倍率，受表示範圍限制 | 現有 RTL 為 2 的 −k 次方，k＝0～31 |
| 重新量化乘法器 | 需要 | 不需要 |
| 乘法中間結果 | 現有 RTL 為 64-bit | 不需要此 64-bit 乘積 |
| 主要運算 | 乘法、捨入、位移、飽和 | 位移、捨入、飽和 |
| scale 選擇 | 較自由 | 限制為二的次方 |
| 精度考量 | 倍率定點近似誤差 | scale 限制可能增加模型量化誤差 |

PoT 的主要硬體優點是消除寬位元倍率乘法器，並減少倍率參數儲存需求。但可變 k 的位移仍需要選擇邏輯，捨入、加法、飽和及 FIFO 也仍存在；實際 LUT／FF、最高頻率與功耗必須透過實測評估，不能僅由公式保證。

對已經採用 PoT scale 的模型，倍率可以精確表示成右移量；精度代價主要來自限制 scale 後的模型量化，以及整數捨入／飽和，不是右移本身又近似了一次倍率。

另須注意：舊 Q31 RTL 在恰好半值時採用「遠離零」，新 PoT 使用「ties-to-even」，所以比較兩個版本時，不能將所有輸出差異只歸因於倍率表示。

## 8. PoT 與 zero-point＝128 是兩個獨立選擇

| 選擇 | 解決的問題 |
|---|---|
| PoT scale | 讓重新量化倍率乘法可以改用右移 |
| zero-point＝128 | 讓 A−128 落在 signed INT8 範圍 −128～127 |

原本 zero-point＝127，但 PE8 使用 A−128 時，需要：

$$
\sum_i(A_i-127)W_i
=\sum_i(A_i-128)W_i+\sum_iW_i
$$

改為 zero-point＝128 後，目標就是：

$$
\sum_i(A_i-128)W_i
$$

因此不需要額外加上權重總和。**移除這個修正是因為 zero-point 改變，不是因為 PoT。**

## 9. 報告時可以使用的摘要

> 乘加結果使用輸入與權重的尺度，下一層則使用輸出的尺度，因此需要重新量化。將尺度限制為二的次方後，尺度比例便能以右移量 k 表示，讓硬體以位移、捨入與飽和取代一般倍率乘法；代價是尺度選擇較受限，必須透過模型準確率驗證其影響。

## 10. 文件與驗證範圍

- 本文整理已核對的軟體公式與 RTL 行為，不修改模型、RTL 或系統階段規劃。
- 本次為文件整理，未重新執行模擬、Vivado 合成、實作或板級測試。
- 架構與驗證細節可參考 [PE_POT_INTEGRATION.md](PE_POT_INTEGRATION.md)、[REQUANTIZER_POT_ARCHITECTURE.md](REQUANTIZER_POT_ARCHITECTURE.md)、[POSTPROCESS_BOARD_TEST.md](POSTPROCESS_BOARD_TEST.md)。
