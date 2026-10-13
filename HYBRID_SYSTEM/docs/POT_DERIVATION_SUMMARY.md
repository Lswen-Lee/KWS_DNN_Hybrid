# 從卷積到 PoT 後處理：簡明公式推導

本文依原稿順序整理。前提為無 bias、activation 為 UINT8 且 zero-point＝128、weight 為 INT8 且 zero-point＝0；輸出 activation zero-point 同樣為 128。以下先不包含 ReLU。

## 1. 將卷積改寫為內積

以 stride＝1 的有效視窗為例，卷積會對輸入 channel 與 kernel 位置的乘積加總：

$$
Y_{c,y,x}=\sum_{d=0}^{C_{\mathrm{in}}-1}
\sum_{u=0}^{H_k-1}\sum_{v=0}^{W_k-1}
a_{d,y+u,x+v}w_{c,d,u,v}
$$

固定一個輸出位置，將 patch 與權重依相同順序攤平，即可省略空間索引並寫成：

$$
Y_c=\sum_{i=0}^{K-1}a_iw_{c,i},\qquad K=C_{\mathrm{in}}H_kW_k
$$

其中 c 為輸出 channel，K 為內積長度；例如 Conv2 的 K＝12×3×3＝108。

## 2. 以整數代碼與 scale 表示實數

量化後的 activation 與 weight 分別為 A_i、W_c,i；它們代表的近似實數為：

$$
a_i\approx s_a(A_i-128),\qquad
w_{c,i}\approx s_{w,c}W_{c,i}
$$

s_a 是輸入 activation scale，s_w,c 是第 c 個輸出 channel 的 weight scale。使用近似符號，是因為量化可能產生捨入與飽和誤差。

## 3. 將 scale 提出求和

同一個內積使用固定的 s_a 與 s_w,c，因此：

$$
Y_c\approx\sum_i[s_a(A_i-128)][s_{w,c}W_{c,i}]
=s_as_{w,c}\sum_i(A_i-128)W_{c,i}
$$

定義硬體整數乘加結果：

$$
ACC_c=\sum_{i=0}^{K-1}(A_i-128)W_{c,i}
$$

故 Y_c≈s_a s_w,c ACC_c。此時已將卷積分成整數乘加與後續尺度轉換。

## 4. 換成輸出 activation 的尺度

若輸出 UINT8 為 Q_c、輸出 scale 為 s_y，則其還原值定義為：

$$
\hat Y_c=s_y(Q_c-128)
$$

希望此還原值接近卷積結果，因此：

$$
Y_c\approx s_as_{w,c}ACC_c,\qquad
\hat Y_c=s_y(Q_c-128)\approx s_as_{w,c}ACC_c
$$

注意：不能寫成 s_y(Q_c−128)＝s_a s_w,c ACC_c，因為輸出量化通常還會有誤差。

在捨入前，所需的連續輸出代碼為 ACC_c×s_a×s_w,c／s_y＋128。因此實際 UINT8 定義為：

$$
Q_c=\operatorname{clip}_{0,255}\left(
\operatorname{RNE}\left(ACC_c\frac{s_as_{w,c}}{s_y}\right)+128
\right)
$$

RNE 表示取最近整數、恰好半值時選偶數；clip 表示飽和到 0～255。

## 5. 用 PoT 將倍率化為右移量

定義重新量化倍率：

$$
M_c=\frac{s_as_{w,c}}{s_y}
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
k_c=e_y-e_a-e_{w,c}
=-\log_2\left(\frac{s_as_{w,c}}{s_y}\right)
$$

目前軟體使用 `POT_ROUNDING = "ceil"`，對 observer 得到的正 scale 做：

$$
s_{\mathrm{PoT}}=2^{\lceil\log_2(s)\rceil}
$$

ceil 作用於 scale 的指數，不是對 ACC 做 RNE。三個 scale 都成為二的整數次方後，k_c 就是整數；**只有 k_c≥0 時才是右移，k_c＜0 時需要左移**。目前模型 k_c＝6～10，符合現有 RTL 支援的 0～31。

## 6. 最終輸出公式

$$
\boxed{
Q_c=\operatorname{clip}_{0,255}\left[
\operatorname{RNE}\left(
\frac{\displaystyle\sum_{i=0}^{K-1}(A_i-128)W_{c,i}}{2^{k_c}}
\right)+128\right]
}
$$

硬體流程為「整數乘加 → 右移與 RNE → 加 128 → 飽和」。如果該層啟用 ReLU，再計算 max(Q_c,128)。

Q31 用定點倍率近似 M_c，需要倍率乘法；PoT 將 M_c 限制為二的次方，可移除這個倍率乘法器，但仍需位移、捨入與飽和邏輯。實際面積／時序改善須由合成實測，準確率影響須由模型測試確認。

詳細講稿與等式成立條件見 [POT_DERIVATION_PRESENTATION_REPORT.md](POT_DERIVATION_PRESENTATION_REPORT.md)。
