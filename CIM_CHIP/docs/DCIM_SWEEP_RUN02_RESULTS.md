# DCIM run02：45／50／51／52／53／54／55 MHz 實測分析

## 範圍與結論

資料：`CIM_CHIP/build/dcim_sweep/run02`；Windows Vivado 2023.2，`xc7z020clg400-1`，`dcim_master_chip_top`，正常板級 non-project 流程，非 OOC。七組都是 COMPLETE、routing errors 均為 0。此處整理使用者提供的真實報告，不是於 Docker 重新合成或執行板上測試。

**本次最高已測且 setup／hold 通過的頻率為 53 MHz，但 setup 裕量僅 7 ps。54 MHz 有 2 個 setup endpoints 違例。**不能將 53 MHz 宣稱為理論 Fmax，亦不代表未來增加電路後仍會通過。

## Post-route 資源與時序

| MHz | Top LUT | Top FF | Macro LUT | Macro FF | Controller LUT | Controller FF | WNS ns | WHS ns | 結果 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
|45|21,062|16,624|18,611|16,504|168|96|1.597|0.138|通過|
|50|21,067|16,624|18,611|16,504|169|96|0.771|0.168|通過|
|51|21,064|16,624|18,611|16,504|167|96|0.092|0.155|通過|
|52|21,065|16,624|18,609|16,504|170|96|0.203|0.186|通過|
|53|21,064|16,624|18,610|16,504|168|96|0.007|0.046|通過，裕量很小|
|54|21,090|16,624|18,637|16,504|170|96|-0.017|0.178|Setup 未通過|
|55|21,062|16,624|18,608|16,504|169|96|-0.399|0.177|Setup 未通過|

Macro 是 `u_chip/u_dcim_macro_core`，Controller 是 `u_pin_master`。階層有包含關係，不可把 Top、Chip、Macro 加在一起當成總面積。

| MHz | TNS ns | Setup failing endpoints | Hold failing endpoints | WPWS ns |
|---:|---:|---:|---:|---:|
|45|0|0|0|2.000|
|50|0|0|0|2.000|
|51|0|0|0|2.000|
|52|0|0|0|2.000|
|53|0|0|0|2.000|
|54|-0.021|2|0|2.000|
|55|-5.775|32|0|2.000|

### 可以在簡報中提出的觀察

1. **限制主要表現在時序，不是資源容量增加。**七組 Top LUT 最多相差 28 顆（約 0.13%），FF 完全相同；但 setup 從正裕量轉為違例。此結論不代表繞線資源／局部擁擠完全不重要。
2. **52 MHz 的 WNS 比 51 MHz 好，不是資料算錯。**每組都重新實作，最差路徑的映射、布局、clock skew 與 MMCM 設定不完全相同。首條資料路徑延遲從 19.430 ns 降為 18.873 ns，邏輯層數從 22 降為 20；不能假設 slack 必須隨頻率單調下降。
3. **53 MHz 是本次通過點，不是充裕的工作點。**WNS 0.007 ns、WHS 0.046 ns 都很小。報告正值仍是有效的 STA 通過，不應因此宣稱此版本必然上板出錯；但對未來 RTL／布局變更幾乎沒有額外餘裕。
4. **54 MHz 的 -0.017 ns 仍然是違例，不能四捨五入視為通過。**只有兩個 endpoints 失敗，可能值得獨立做物理最佳化實驗；這次沒有更動 RTL、約束或最佳化設定，也不保證能消除。
5. 對於後續系統整合，50 MHz 在本次報告具有 0.771 ns 的較大 setup 裕量，可以作為保守基準；53 MHz 則作為目前架構的高頻實測點。兩者都不能取代完整板級驗證。

## 最長 setup 路徑與延遲組成

| MHz | Data path ns | Logic ns | Routing ns | Routing 比例 | Logic levels |
|---:|---:|---:|---:|---:|---:|
|45|20.387|5.962|14.425|70.756%|22|
|50|19.148|5.302|13.846|72.311%|21|
|51|19.430|6.198|13.232|68.100%|22|
|52|18.873|5.272|13.601|72.067%|20|
|53|18.796|5.687|13.109|69.743%|22|
|54|18.427|5.158|13.269|72.009%|21|
|55|18.429|5.657|12.772|69.303%|21|

各組最差路徑都由 `u_pin_master/FSM_sequential_state_reg` 出發。

- 45／51／52 MHz：到 odd accumulator 的 `u_serial_output/shift_register_reg[17]/D`。
- 50 MHz：到 even accumulator 的 `accumulated_sum_reg[14]/D`。
- 53／54／55 MHz：到 even accumulator 的 `u_serial_output/shift_register_reg[17]/D`。

**最差路徑的約七成延遲來自 routing。**這支持後續優先檢視控制訊號 fanout、選擇網路、共享 adder tree 的實體連線與 pipeline 切割位置；但並未證明把 adder tree 數量增加就一定改善，也不能只看終點就把原因全部歸給 serializer。

WNS 不等於單純的「period − data path delay」；還涉及 clock skew、uncertainty 及暫存器 timing requirement。亦不能從一條最差路徑的 routing 比例推出整個晶片都被 routing 限制。

## 與 run01 的一致性

已比較兩次 `snapshot` 原始輸入檔，未發現內容差異。45／50／55 MHz 的 LUT／FF、WNS／WHS 與前次一致；51～54 MHz 是本次新增點。沒有因後處理腳本改變 FPGA 數據。

## 仍需審核的項目

- 七組均為 no_clock=0、unconstrained_internal_endpoints=0；hold／pulse-width failing endpoints 都是 0。
- 缺 input delay：`reset_button`；缺 output delay：`led[1:3]`。它們是板級非同步介面，需按實際用途審核約束，不應把本表解讀成全部 I/O 都已完整約束。
- 七組 DRC 仍有 `ZPS7-1`，methodology 有 `LUTAR-1`（LUT 驅動 asynchronous reset）及 `ULMTCS-2`（control sets）。沒有 TIMING-16 也不表示 WNS 已通過，54／55 MHz 即是例子。
- 本次未消除 warning、未變更 timing exceptions，未執行板上功能測試。這是 FPGA 數位模型的結果，不代表實體 FeFET／CIM 晶片速度或面積。

## 圖表與重現方式

```bash
python3 CIM_CHIP/scripts/summarize_dcim_sweep.py CIM_CHIP/build/dcim_sweep/run02
python3 CIM_CHIP/scripts/plot_dcim_path_analysis.py CIM_CHIP/build/dcim_sweep/run02
```

- [面積與時序四格總覽](../build/dcim_sweep/run02/frequency_overview.png)
- [臨界路徑延遲組成與 WNS](../build/dcim_sweep/run02/critical_path_analysis.png)
- [LUT–MHz](../build/dcim_sweep/run02/lut_vs_mhz.png)／[FF–MHz](../build/dcim_sweep/run02/ff_vs_mhz.png)
- [所有階層與兩階段 CSV](../build/dcim_sweep/run02/summary.csv)／[臨界路徑 CSV](../build/dcim_sweep/run02/critical_path_analysis.csv)

各圖均有 SVG 向量版。Build 與生成圖表不提交 Git，版本庫保存數據摘要及繪圖程式。

驗證：七組 WNS／WHS 與 timing summary 交叉核對；route errors 均為 0；繪圖使用真實報告，邏輯與繞線延遲和數據總延遲一致。未重新執行 Vivado。
