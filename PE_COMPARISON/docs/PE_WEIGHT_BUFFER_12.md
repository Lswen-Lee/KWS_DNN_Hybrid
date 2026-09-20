# pe_weight_buffer_12：實作與交叉驗證

## 2026-09-15 更新

已參數化 ADDR_WIDTH（預設 8，深度256；整層使用9，深度512）。
原 TB 保留；新增 loader 整合 TB 驗證512-depth容量與多group映射。
本文件以下的256容量與單組範圍為原基準設定；最新整層設計參考
[PE_LAYER_WEIGHT_LOADER.md](PE_LAYER_WEIGHT_LOADER.md)。新 loader 已在 TB 接上 buffer/ΣW builder，
尚未整合 PE 運算 top。

## 範圍與檔案

RTL：HYBRID_SYSTEM/rtl/datapath/pe_weight_buffer_12.sv。
TB：HYBRID_SYSTEM/tb/datapath/tb_pe_weight_buffer_12.sv。
PE8、PE9共用的單組12-lane權重buffer。尚未接loader、ΣW builder、PE array；
不包含全layer排程，也没有新的Vivado資源／時序報告。

## 記憶體架構

```text
wr_lane、wr_addr、wr_data → 12選1寫入
                           ↓
    bank0[256×8] bank1[256×8] ... bank11[256×8]
                           ↑
                   共用rd_addr/read_fire
                           ↓
           各bank同步read_q → 96-bit weights_flat
                           ↓
                  out_valid/out_ready
```

每bank以ram_style="block"標記，沒有RAM清零迴圈；讀取與寫入在posedge，
RAM/read_q沒有reset，只有out_valid同步reset。邏輯容量24576bits=3072bytes。
不能以此直接推論實體BRAM数量；12個窄bank可能浪費容量，需看Vivado。
weights_flat[8*j+:8]屬於lane j；8-bit pattern保持不變，MAC端解讀signed。

## 介面與控制

| 介面 | 定義 |
|---|---|
| clk/rst | 單一時脈、同步active-high reset；reset時禁止新讀寫 |
| wr_valid/wr_ready | 寫入接受事件，wr_lane必須<12 |
| wr_lane[3:0]/wr_addr[7:0]/wr_data[7:0] | 每拍最多寫入一個byte |
| rd_valid/rd_ready/rd_addr[7:0] | 每次接受並行12路同地址讀取 |
| out_valid/out_ready/weights_flat[95:0] | 一級同步讀取響應，可反壓 |

```text
write_fire = wr_valid && wr_ready
wr_ready = !rst && wr_lane<12
rd_ready = !rst && !write_fire && (!out_valid || out_ready)
read_fire = rd_valid && rd_ready
```

合法write優先，當拍不接受read；讀取請求上游必須保持直到ready。
非法lane12..15不寫入，也不阻止合法read，沒有error狀態。
寫入期間已存在的輸出可被下游接收；若下游停頓，read_q保持，即使
寫入地址與待接收資料的舊讀址相同，也不改變舊響應。
從控制上禁止同拍read_fire與write_fire，不依賴讀寫同地址的碰撞行為。
輸出空或被消費時才接受新read；每拍可以consume/replace。

## 時序與reset

N上升緣read_fire：RAM對rd_addr取值存read_q，N邊緣後out_valid及資料
有效；N+1上升緣可交付並同時接受下一個rd_addr。無額外第二級96-bit FIFO。
write_fire在N邊緣更新RAM，之後接受的讀取看到新資料。
reset清out_valid、丟棄未交付響應，但不清RAM/read_q。
上電未寫地址無有效資料保證，不可依賴Verilator初始0當真實RAM內容。
有效權重／layer ready由未來loader管理。本模組沒有逐byte valid bitmap。

## 與loader／ΣW builder的對接要求

將RAM實際write_fire與builder實際weight handshake設成同一事件。
不能讓其中一個接受、另一個停頓；loader需知道builder是否能接受，
再產生RAM wr_valid，同時保持權重位址與數值。尚未在本次連接。
下一個模組是pe_weight_loader：channel/K計數、載入完成標記、共同握手。
再來是RAM讀取與A/valid對齊，最後整合weight-loaded PE8／PE9 top。

## 測試與觀察

TB使用獨立model與initialized bitmap，以外部handshake更新，不讀DUT RAM。
同一筆read在接受時保存expected快照，之後RAM改寫不改變該expected。
每次valid響應比較12路，同時檢查read/write仲裁、輸出valid與N邊緣後延遲。

1. 寫滿12×256=3072bytes，pattern含00/7F/80/FF與lane/address相依值。
2. 連續讀256個地址、每次比較12個bank。
3. 停住一筆響應，同地址改寫全部12個bank，舊輸出仍保持，再讀到新值。
4. 合法write與read同拍出現，write優先，read在下一拍重試。
5. 非法lane12..15被拒絕，且同拍read仍可進行。
6. reset丟棄待交付響應，reset期間讀寫禁止；重新讀回全部地址驗證RAM保留。
7. 插入read bubbles並檢查不產生額外響應。

實際Verilator與Icarus Verilog結果一致：3085次寫入、521次read接受、
520次響應交付、1次reset丟棄、6420次lane比較、15拍stall檢查、
13次合法write優先、4次非法lane拒絕，全部PASS。Verilator RTL嚴格lint通過。
兩個模擬器使用同一TB與獨立reference，交叉驗證模擬語意，不是形式等價驗證。

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM
make test-weight-buffer
make lint-weight-buffer
make test-weight-buffer-iverilog  # 需要iverilog/vvp在PATH，或指定工具變數
make test lint
```

本機Icarus位於/tmp/pe_dsp_iverilog/extracted，可指定：

```bash
make test-weight-buffer-iverilog \
 IVERILOG=/tmp/pe_dsp_iverilog/extracted/usr/bin/iverilog \
 VVP=/tmp/pe_dsp_iverilog/extracted/usr/bin/vvp \
 IVL_FLAGS='-B /tmp/pe_dsp_iverilog/extracted/usr/lib/x86_64-linux-gnu/ivl'
```

## 合成驗收（尚未執行）

只匯入RTL、top選pe_weight_buffer_12，不加入TB。使用相同PYNQ-Z2器件
及明確時脈限制，確認RAMB18/RAMB36資源與hierarchy，而非只看LUT下降。
模組有寬資料口，不應直接當板上pin top；單模組資源檢查可OOC，最終
時序需帶真實上層clock與邊界驗證。不得把現有OOC hold違反視為已解決。
ram_style是推導意圖，不是已合成證明；若映射為大量FF，先檢查RAM模板
及Vivado訊息再修正，不能宣稱一定125MHz／一定放得下。
