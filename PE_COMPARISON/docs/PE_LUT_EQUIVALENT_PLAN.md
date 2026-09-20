# PE8／PE9 LUT、FF等價比較規劃（2026-09-14）

更新：第一階段已實作，狀態／介面／驗證／GUI操作詳見
[PE_EQUIVALENT_IMPLEMENTATION.md](PE_EQUIVALENT_IMPLEMENTATION.md)。
以下保留原規劃作對照；新增共用pe_compare_engine避免重複程式，
PE8每job需配置ΣW，尚未做跨patch參數重用。尚無Vivado面積數據。

## 本次實作與範圍

PE9 MAC已改為LUT／FF，原DSP來源與Makefile已備份。以下兩份top與
比較環境是規劃，尚未建立或產生Vivado報告。舊build不刪除、不覆寫。

## 第一階段：相同範圍的stream dot-product top

以兩邊已完成的array為基础，不直接拿PE8完整core對PE9 array比較。
兩份top使用同一個排程controller、輸入暫存、K計數與12路result drain；
只替換activation轉換、MAC array，以及PE8補償路徑。

```text
共同：命令(K/lane_mask) → CLEAR → RUN → DRAIN → OUTPUT → IDLE
共同：UINT8 A + 12×INT8 W → 相同輸入暫存/握手 → MAC array
PE9 ：A−127 → S9×S8乘法 → 17-bit Product FF → INT32 ACC
PE8 ：A−128 → S8×S8乘法 → 16-bit Product FF → INT32 ACC
共同：result drain逐筆送lane/channel結果，core在輸出完成前不可clear
PE9 ：raw → 輸出握手
PE8 ：raw + 該channel ΣW → pe8_result_correction → 輸出握手
```

共同controller需依真實管線排空（含輸入暫存及Product FF），不能最後一筆
接受後立刻輸出。PE8補償有一級可停頓暫存，PE9先不加人工延遲來湊級數；
讓額外補償成本／延遲如實計入，依output handshake完成才結束工作。
同時報raw array階層大小可分辨位寬差異。

命令接口：cmd_valid/ready、K、lane_mask；K=0不接受，沒有error狀態。
運算接口：in_valid/ready、activation_u8、weights_flat(12×8)。
結果接口：out_valid/ready、signed32 result、lane_id、last、overflow。
以完成out_last握手定義工作結束。權重、activation在反壓時保持。

本階段PE8的ΣW由獨立參數載入接口提供並存12×32-bit暫存器，每次job
前載入對應group。PE9不放虛假的ΣW記憶體；兩邊計算／結果接口相同，
PE8額外的配置接口應明確列出，不要求所有pin完全相同。
參數讀取延遲必須與raw及channel對齊；PE8配置儲存與補償都計入top。
此結果應稱「含補償與參數暫存的stream compute top」，不是完整layer backend。
兩邊都不含weight RAM、feature-map RAM、完整layer scheduler或ΣW建立器。
ΣW由TB供應，不可宣稱已驗證硬體自主建立補償參數。

## 第二階段：完整backend

納入兩邊實際使用的weight RAM、loader、feature-map介面與layer control。
PE8另計入ΣW builder與全layer參數儲存。載入時成功握手才累加ΣW，
每channel最後一筆須包含在寫回值；layer/group索引不可混用。
不可用第一階段外部給ΣW的報告宣稱完整backend節省率。

## 規劃新增的檔案（不是已實作清單）

```text
PE_COMPARISON/
├── rtl/equivalent/
│   ├── pe_compare_stream_controller.sv  共同工作排程
│   ├── pe_compare_result_drain.sv       lane選擇及結果反壓
│   ├── pe9_equivalent_top.sv            PE9轉換/array/共用控制
│   └── pe8_equivalent_top.sv            PE8轉換/array/ΣW暫存/補償
├── tb/tb_pe_equivalence.sv              獨立數學golden、跨延遲比對
├── constraints/pe_equivalent_ooc.xdc    同8ns與邊界延遲假設
├── vivado/create_pe_equivalent_project.tcl  依pe8/pe9建立獨立專案
├── vivado/report_pe_equivalent.tcl      輸出總量/階層/時序
├── scripts/summarize_pe_equivalent.py   檢查範圍/階段並生成表格
└── build/
    ├── pe8_equivalent/                 runs與reports
    └── pe9_equivalent/                 runs與reports
```

現有PE_COMPARISON/Makefile與guide日後新增等價測試目標，保留array比較。
採OOC避免寬資料接口變成實體IO；OOC不是bitstream且邊界routing可能不完整，
時序結果須標明限制。125MHz/相同器件/相同策略/MAX_DSP=0。
以post-route LUT/FF為主，另記DSP=0、WNS/WHS及每job cycles作有效性檢查。
不要引用constant自測top的最佳化結果來代表通用運算器。

## 數值驗證與公平性

Golden=Σ(A−127)W，bias=0。比對交易ID/lane，而非相同clock。
K=9/32/144，mask=12路/8路/部分/0，A=0/127/128/255，W=−128/−1/0/127，
隨機與固定混合、bubble、反壓、reset；兩邊依各自ready送同一批交易。
raw沒有中途溢位才適用等價公式。正常模型測試要求overflow=0。
PE8 correction採飽和但PE9 raw ACC採wrap，因此不可對任意已溢位raw
宣稱bit-exact等價；本比較限定上述可證明不溢位的dot products。
K≤255時signed8/9乘加遠低於INT32上界，適用本模型。

## 使用者要求的主要面積表格

同一組表格只放同階段、同範圍、同限制的結果。無新報告前不填猜測值。

| Resource | PE8（含ΣW補償與參數暫存） | PE9（直接A−127） |
|---|---:|---:|
| LUT | 待實作與合成 | 待實作與合成 |
| FF | 待實作與合成 | 待實作與合成 |

LUT節省率 = (LUT_PE9 − LUT_PE8) / LUT_PE9 × 100%。
正數表示PE8節省；負數表示PE8用更多LUT；分母為0時標N/A。
例如PE9=2000、PE8=1800，節省10%（僅算式示例，不是實測）。
不要把LUT與FF相加成面積，也不以DSP版PE9報告代入本表。
另列一份raw array同格式表格，可說明MAC少1-bit的收益，但主要結論
使用完整指定比較top；FF列數量即可，不強制另算FF節省率。
