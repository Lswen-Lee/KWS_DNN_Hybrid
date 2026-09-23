# DCIM 六頻率實測報告整理（2026-09-23）

來源：`CIM_CHIP/build/dcim_sweep/run01`，由使用者在 Windows Vivado 2023.2 完成。頂層 `dcim_master_chip_top`，器件 `xc7z020clg400-1`，正常 non-project 板級流程，非 OOC。

本次只執行報告彙整／繪圖與交叉檢查，沒有重新執行 Vivado，也沒有改動 RTL。

## 結果：以 post-route 為準

| MHz | Top LUT | Top FF | Macro LUT | Macro FF | Controller LUT | Controller FF | WNS ns | WHS ns | Setup／hold |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
|40|21,062|16,624|18,613|16,504|168|96|1.653|0.173|通過|
|45|21,062|16,624|18,611|16,504|168|96|1.597|0.138|通過|
|50|21,067|16,624|18,611|16,504|169|96|0.771|0.168|通過|
|55|21,062|16,624|18,608|16,504|169|96|-0.399|0.177|Setup 未通過|
|60|21,175|16,624|18,691|16,504|172|96|-0.423|0.177|Setup 未通過|
|65|21,649|16,624|18,762|16,504|172|96|-2.051|0.073|Setup 未通過|

- 六組 `status.txt` 都是 COMPLETE，且 routing errors 都是 0；這表示流程完成，不等於時序通過。
- 在這六個測試點中，最高 setup／hold 通過頻率是 **50 MHz**。不是精確 Fmax，也沒有證明 51～54 MHz 能否通過。
- Top FF 六組相同，都是 16,624；提高時序目標沒有自動加入新的運算 pipeline。
- Top LUT 從 50 MHz 的 21,067 增至 65 MHz 的 21,649，增加 582（約 2.76%），但 65 MHz 仍未通過 setup。不能把更多資源解讀為已達到更高速度。
- 40／45／55 MHz 的 Top LUT 相同，但 macro／controller 內的歸屬並非完全一致；各階層的結果應以其自身報告判讀。
- Macro 是 `u_chip/u_dcim_macro_core`，Controller 是 `u_pin_master`；Top 還包含 chip 外圍、自我測試、時脈及 reset。階層面積不可重複相加。

## 時序交叉檢查

已核對各頻率 `metrics.tsv` 與 `timing_summary.rpt` 的 WNS。六組 hold failing endpoints 都是 0，pulse-width failing endpoints 都是 0（WPWS 2.000 ns）。

| MHz | TNS ns | Setup failing endpoints |
|---:|---:|---:|
|40|0|0|
|45|0|0|
|50|0|0|
|55|-5.775|32|
|60|-6.783|32|
|65|-81.577|64|

55／60／65 MHz 的首條 setup path 都從 `u_pin_master/FSM_sequential_state_reg` 出發，到 `u_chip/u_dcim_macro_core/u_even_accumulator/u_serial_output/shift_register_reg[17]/D`。因此這是包含 master 控制與 chip 資料路徑的系統限制，不能單憑端點宣稱是 serial_output 或 macro 單獨造成全部延遲。詳細 combinational path 請看各頻率 `post_route/setup_paths.rpt`。

## 尚未消除的檢查項目

- 六組均沒有 no_clock 或 unconstrained_internal_endpoints。
- 仍有一個缺 input delay 的 `reset_button`，三個缺 output delay 的 `led[1:3]`；這些非同步板級介面需要按實際用途審核，不能把 setup／hold PASS 當成所有介面都完整約束。
- DRC：六組均有 `ZPS7-1`（PS7 block required）warning；後續上板／配置流程需另行確認。
- Methodology：六組有 `LUTAR-1`（邏輯驅動 asynchronous reset）及 `ULMTCS-2`（control sets）警告；65 MHz 另有 `TIMING-16`。Reset 毛刺風險不能僅憑正 WNS 排除。
- 本次沒有新增例外或隱藏上述警告，也未進行新的板上測試。

## 圖表與重現

執行：

```bash
python3 CIM_CHIP/scripts/summarize_dcim_sweep.py CIM_CHIP/build/dcim_sweep/run01
```

本地輸出（build 不提交 Git）：

- [四格總覽圖](../build/dcim_sweep/run01/frequency_overview.png)：Top LUT、Macro LUT、Top FF、WNS；LUT 子圖使用放大刻度並註明，所有點都有數值。
- [LUT–MHz](../build/dcim_sweep/run01/lut_vs_mhz.png)／[FF–MHz](../build/dcim_sweep/run01/ff_vs_mhz.png)：Top、Macro、Controller 的整體比較。
- [CSV](../build/dcim_sweep/run01/summary.csv)：包含 post-synth 與 post-route，共 12 筆。
- 圖片均另附 SVG 向量版。綠色圓點表示 setup／hold 通過；紅叉表示失敗或未完成，不表示已通過完整 sign-off。

檢查：六組報告解析、timing summary 交叉核對、routing errors 檢查已通過；`test_frequency_sweep.py` 的 Tcl mock／報告解析／新增總覽圖回歸通過。Mock 不代表本機執行了 Vivado；表格數據來自使用者提供的真實報告。
