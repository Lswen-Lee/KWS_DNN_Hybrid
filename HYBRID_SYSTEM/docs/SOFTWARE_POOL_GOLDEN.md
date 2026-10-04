# 真實軟體 activation：MaxPool 整合驗證

## 範圍與來源

本次補強S2，重用S1 RAM/Reader/Writer，不改RTL；下一步仍為S3真實PE Conv1→Pool，Argmax不是前置。

來源目錄：`/home/LAB505/projects/KWS/layer_activation_uint8_pot_ceil_zp128`。
已核對八份metadata：dataset_index=6988、UINT8、zp=128、CHW（x最快）、同一checkpoint：
`f5d5b047773f9efc2af9e80945927eba7d4edd7c66e8a88ee3e4d6fcff82b407`。

| 軟體輸入 → 軟體golden | 輸入C×H×W | 輸出C×H×W | source/destination base | 輸出筆數 |
|---|---|---|---|---:|
| quant_input → pool1 | 1×64×126 | 1×32×63 | 0 / 8064 | 2016 |
| relu1 → pool2 | 12×30×61 | 12×15×30 | 10080 / 0 | 5400 |
| relu2 → pool3 | 12×13×28 | 12×6×14 | 5400 / 0 | 1008 |
| relu3 → pool4 | 12×4×12 | 12×2×6 | 1008 / 0 | 144 |

使用各層 `activation_uint8_binary.txt`，不是centered_int16或FP32。後三組輸入是ReLU輸出，不是Conv輸出。

## 計算與驗證流程

2×2、stride2、無padding、floor尺寸：

`out[c,y,x] = max(in[c,2y,2x], in[c,2y,2x+1], in[c,2y+1,2x], in[c,2y+1,2x+1])`

每組池化前後scale/zp相同且scale>0，直接比較UINT8即可，不必減128或重新量化。四組scale依序0.015625、0.0625、0.125、0.25。

```text
軟體輸入檔 → TB交錯channel載入 → Writer → RAM
                                            ↓
                                          Reader
                                            ↓
                                          MaxPool
                                            ↓
軟體pool檔 → TB參考陣列 ← 比較 ← RAM讀回 ← RAM ← Writer
```

Golden只存TB參考陣列，沒有寫進DUT當作計算結果。四組各自載入軟體輸入；沒有假裝執行尚未接入的Conv。

1. 初始化全部RAM為A5；輸入透過公開load介面以y→x→channel交錯順序送入，驗證Writer轉換CHW。
2. 檔案每個token必須恰為8個0/1；少資料、多資料、非法字元或缺檔均失敗。
3. 監控池化真實RAM讀寫地址、寫回值、交易數、frame_start及無掉資料。
4. pool_done時確認全部輸入已消費、全部输出已提交。
5. 每組讀回全部32768位址，隨機ready停頓並檢查data/last穩定、筆數與完成。
6. 目的區逐值比對軟體golden；其他區域比對原輸入、先前資料或A5 sentinel，確定沒有誤寫。

## 執行方式

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM
make test-activation-path-software lint-activation-path
```

先執行原測試，再執行軟體golden模式。可指定其他目錄：

```bash
make test-activation-path-software SOFTWARE_ACTIVATION_DIR=/absolute/path/to/export
```

TB為 `tb/integration/tb_kws_activation_path.sv`；用 `+SOFTWARE_ROOT=...` 切換模式。
原 `make test-activation-path` 保留；一般回歸不強制依賴repo外資料。

## 結果與限制

Verilator 5.030：四組全部PASS，8568筆輸出完全相同、131072筆全RAM讀回通過；原9個池化案例、11個非法命令、294912筆讀回回歸及RTL lint通過。

這是單一軟體樣本的bit-exact測試，不代表整個資料集準確率、真實PE卷積、Vivado BRAM推導、時序或上板已通過。TB尺寸依此樣本固定，不自動解析metadata；更換資料時須重新核對shape、scale、zp與樣本來源。資料位於repo外，未複製或提交；換電腦須另外提供該匯出資料夾。
