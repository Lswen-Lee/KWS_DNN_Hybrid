# PoT 整數卷積與後處理：公式推導報告及講解稿

## 報告目的與範圍

說明目前硬體為何能以整數乘加與右移實現量化模型的卷積，並區分「精確整數運算」和「對浮點模型的量化近似」。本文是數學與既有架構說明，不是新的 RTL、準確率或 PPA 實驗結果。

搭配閱讀：[簡明公式版](POT_DERIVATION_SUMMARY.md)、[既有數學指南](POSTPROCESS_POT_MATH_GUIDE.md)。

## 第一頁：問題與設計前提

**建議講法：**「原本模型做實數卷積，但 FPGA 希望使用低位元整數運算。問題不是單純把 FP32 截成八位元，而是必須保留每個整數所代表的尺度，才能讓下一層理解運算結果。」

| 項目 | 本文前提 |
|---|---|
| activation 儲存 | UINT8，0～255，zero-point＝128 |
| weight 儲存 | INT8，−128～127，zero-point＝0 |
| activation scale | 每個量化位置使用一個 scale |
| weight scale | 每個輸出 channel 各自一個 scale |
| bias | 不使用 |
| 乘加結果 | INT32；推導假設累加沒有溢位 |
| 輸出 | UINT8，zero-point＝128 |
| 重新量化捨入 | RNE，半值取偶數 |

注意：討論 UINT8 是指儲存形式；A−128 已經是 signed INT8 可表示的 −128～127。

## 第二頁：原始卷積如何變成內積？

以 stride＝1、有效視窗為例：

$$
Y_{c,y,x}=\sum_{d=0}^{C_{\mathrm{in}}-1}\sum_{u=0}^{H_k-1}
\sum_{v=0}^{W_k-1}a_{d,y+u,x+v}w_{c,d,u,v}
$$

固定 (y,x)，選擇一致的攤平索引：

$$
i=dH_kW_k+uW_k+v,\qquad K=C_{\mathrm{in}}H_kW_k
$$

因此：

$$
Y_c=\sum_{i=0}^{K-1}a_iw_{c,i}
$$

**推導理由：** 每一組 (d,u,v) 都對應唯一 i；只是重新排列索引，沒有遺漏乘積或改變實數數學上的總和。此處省略 Y_c 的空間索引，只代表某一個輸出位置，不是整張 feature map。浮點程式若更改加法順序，仍可能有微小浮點捨入差異。

**建議講法：**「Conv2 的 12 個 channel，每個有 3×3 個數值，因此一個 filter 在一個位置需要 108 個乘積。不同 channel 的乘積本來就要加總，攤平不會混錯資料，前提是 activation 與 weight 使用相同索引。」

## 第三頁：整數代碼如何代表實數？

量化的概念為：

$$
A_i=\operatorname{clip}_{0,255}\left(\operatorname{RNE}(a_i/s_a)+128\right)
$$

$$
W_{c,i}=\operatorname{clip}_{-128,127}\left(\operatorname{RNE}(w_{c,i}/s_{w,c})\right)
$$

定義由代碼還原的實數：

$$
\tilde a_i=s_a(A_i-128),\qquad \tilde w_{c,i}=s_{w,c}W_{c,i}
$$

這兩個等號是定義，成立；原本的 a_i≈tilde a_i、w_c,i≈tilde w_c,i 才是量化近似。

**例子：** s_a＝0.125、a_i＝1.03，量化成 A_i＝136，還原為 1.00，不再是原本的 1.03。

**建議講法：**「Scale 是每個整數刻度的實數大小，zero-point 指出哪個整數代表零。近似符號表示量化誤差，而不是硬體算錯。」

## 第四頁：如何把浮點尺度與整數 MAC 分開？

使用量化還原後的輸入與權重，定義其卷積結果：

$$
\tilde Y_c=\sum_i\tilde a_i\tilde w_{c,i}
$$

代入後可以精確提出固定 scale：

$$
\tilde Y_c=s_as_{w,c}\sum_i(A_i-128)W_{c,i}
=s_as_{w,c}ACC_c
$$

$$
ACC_c=\sum_i(A_i-128)W_{c,i}
$$

這裡 tilde Y_c＝s_a s_w,c ACC_c 是等式；原始浮點卷積則只有 Y_c≈tilde Y_c。

**可選的誤差說明：** 若 a_i＝tilde a_i＋epsilon_a,i，w_c,i＝tilde w_c,i＋epsilon_w,c,i，则：

$$
Y_c-\tilde Y_c=\sum_i\left(
\epsilon_{a,i}\tilde w_{c,i}
+\tilde a_i\epsilon_{w,c,i}
+\epsilon_{a,i}\epsilon_{w,c,i}\right)
$$

所以輸入與權重量化的誤差本來就會影響卷積結果。

**建議講法：**「PE 負責算整數 ACC，scale 不必在每個乘法器內重複相乘；它可以集中到後處理。DCIM 若使用偏移編碼，也必須先修正成同樣的 ACC 定義。」

## 第五頁：為什麼需要重新量化？

ACC 的實數比例尺是 s_a×s_w,c，但下一層指定的比例尺是 s_y。先定義尚未取整的輸出代碼：

$$
q_c^*=\frac{\tilde Y_c}{s_y}+128
=ACC_c\frac{s_as_{w,c}}{s_y}+128
$$

定義倍率：

$$
M_c=\frac{s_as_{w,c}}{s_y}
$$

實際輸出代碼：

$$
Q_c=\operatorname{clip}_{0,255}\left(\operatorname{RNE}(ACC_cM_c)+128\right)
$$

最後定義輸出還原值：

$$
\hat Y_c=s_y(Q_c-128)\approx\tilde Y_c\approx Y_c
$$

**原稿須修正之處：** 不可寫成 s_y(Q_c−128)＝s_a s_w,c ACC_c，因為前者已經歷輸出捨入與飽和。只有特定恰可表示且未飽和的數值才會相等。

未飽和時，輸出這一步滿足 |hat Y_c−tilde Y_c|≤s_y/2；這不是原始 Y_c 到最終輸出的總誤差界限。

## 第六頁：一般倍率的 Q31 實作

Q31 是使用 31 個小數位元表示倍率，不是 activation 使用 31 bits。對目前舊 RTL 支援的正倍率範圍：

$$
M_{\mathrm{Q31},c}=\operatorname{Round}(M_c2^{31}),\qquad
M_c\approx M_{\mathrm{Q31},c}/2^{31}
$$

因此需要計算 ACC×M_Q31，再除以 2^31、捨入、加 zero-point 與飽和。舊 RTL 使用 64-bit 中間乘積。

**建議講法：**「Q31 可以細緻近似一般倍率，但要支付倍率乘法器的成本。PoT 則從模型量化限制倍率形式，換取硬體簡化。」

## 第七頁：PoT 如何得到整數 k？

目前軟體先從 observer 統計取得正 scale，再向上貼齊二的次方：

$$
s_{\mathrm{PoT}}=2^{\lceil\log_2(s)\rceil}
$$

例如 s＝0.023，log2(s)≈−5.442，ceil 後為 −5，所以新 scale＝0.03125。

對貼齊後的 scales：

$$
s_a=2^{e_a},\quad s_{w,c}=2^{e_{w,c}},\quad s_y=2^{e_y}
$$

$$
M_c=2^{e_a+e_{w,c}-e_y}=2^{-k_c},\qquad
k_c=e_y-e_a-e_{w,c}
$$

指數都是整數，所以 k 是整數；但它不保證非負。現有模型 k＝6～10，才可以全部用右移；現有硬體介面支援 0～31。

**建議講法：**「ceil 用於軟體選 scale；RNE 用於量化資料，兩者不是對同一個數值連續捨入。部署時 FPGA 只查詢已匯出的 k，不計算 log2 或 ceil。」

## 第八頁：右移為什麼還需要 RNE？

右移只給出向下取整的商，不能保證最近整數。令 k＞0、D＝2^k：

$$
t=\lfloor ACC/D\rfloor,\qquad r=ACC-tD,\quad0\le r<D
$$

$$
\operatorname{RNE}(ACC/D)=
\begin{cases}
t,&r<D/2\\
t+1,&r>D/2\\
t,&r=D/2\text{ 且 }t\text{ 是偶數}\\
t+1,&r=D/2\text{ 且 }t\text{ 是奇數}
\end{cases}
$$

k＝0 時直接保留 ACC。此方法適用於正負數，例如 −640／256＝−2.5：t＝−3、r＝128，半值且 t 為奇數，因此加一得到 −2。

**建議講法：**「我們不是單純丟掉低位元，而是利用被丟掉的部分判斷進位。這樣才能對齊軟體 golden 的半值取偶數規則。」

## 第九頁：完整算例與最終公式

選示意 scales：s_a＝2^−4、s_w＝2^−7、s_y＝2^−3，故 k＝8。若 ACC＝2688：

| 步驟 | 計算 |
|---|---|
| 縮放 | 2688／256＝10.5 |
| RNE | 10.5→10 |
| 加 zero-point | 10＋128＝138 |
| 飽和 UINT8 | Q＝138 |
| 輸出還原值 | 0.125×(138−128)＝1.25 |
| 重新量化前的值 | 2^−11×2688＝1.3125 |
| 輸出量化誤差 | 1.3125−1.25＝0.0625＝s_y／2 |

這個例子同時展示：硬體結果正確，但量化前後不一定相等。

最終公式為：

$$
\boxed{Q_c=\operatorname{clip}_{0,255}\left[
\operatorname{RNE}\left(\frac{\displaystyle\sum_{i=0}^{K-1}(A_i-128)W_{c,i}}{2^{k_c}}\right)+128\right]}
$$

若該層啟用 ReLU，另計算 max(Q_c,128)。ReLU 是非線性操作，不應與單純重新量化誤差混為一談。

## 第十頁：對應硬體及可以主張的結論

```text
UINT8 activation → 減 128 ─┐
                          ├→ 整數 MAC → INT32 ACC
INT8 weight ──────────────┘                 │
                                           ▼
layer/channel → shift ROM → k → 右移與 RNE
                                           │
                                           ▼
                                  加 128 → 飽和 UINT8
                                           │
                                           ▼
                                  可選 ReLU → FIFO
```

| 數學工作 | 現有模組角色 |
|---|---|
| scale 比例到 k | 軟體匯出，`kws_pot_shift_rom` 查表 |
| ACC／2^k、RNE、zero-point、飽和 | PoT requantizer 組合／管線版本 |
| 查表、可選 ReLU、標籤與背壓 | `pot_result_stream` |
| MaxPool／Argmax | 後續獨立模組，不包含在上述卷積公式內 |

PoT 可移除一般倍率乘法器，倍率參數也由 Q31 整數變成小位寬 k；但可變位移、捨入、加法與 FIFO 仍有面積與時序成本。限制 scale 也可能降低模型準確率，因此不能僅依公式聲稱更快、更省多少或準確率完全不變。

舊 Q31 RTL 半值採遠離零，新 PoT 採半值取偶數；數值比較需考慮捨入規則差異。zero-point＝128 使 PE8 不需原先的 ΣW 修正，這與 PoT 移除倍率乘法器是兩項不同改變。

## 報告問答與驗證界限

| 問題 | 回答 |
|---|---|
| 這證明與 FP32 完全相等嗎？ | 否；證明的是量化表示下的尺度換算與整數公式，FP32 有量化近似誤差。 |
| k 是訓練直接學到的嗎？ | 現有程式由 observer 統計 scales，再貼齊 PoT、匯出 k，不是將 k 當成梯度學習參數。 |
| k 是整數就能右移嗎？ | 還須 k≥0，並在 RTL 支援範圍內。 |
| RNE 是硬體自行選擇嗎？ | 是軟硬體共同約定的數值規則，必須一致。 |
| 全部 scales 都要同一個值嗎？ | 不需要；各自是二的整數次方即可，k 可逐 channel 不同。 |
| 數學正確就代表 RTL 正確嗎？ | 否；仍須驗證位寬、signed、溢位、捨入、握手及資料對齊。 |

建議驗證分三層：

1. 公式單元：正負值、半值奇偶、k 邊界、上下飽和、ReLU 門檻。
2. RTL 整合：以獨立整數 golden 對比 ACC→Q，涵蓋背壓、標籤、reset。
3. 模型與實體：真實軟體逐層輸出比對、整體準確率、Vivado 資源與時序分析。

本次只新增報告文件並檢查文件差異，沒有重新執行上述 RTL／模型／Vivado 驗證；不將數學推導視為新增測試通過的證據。
