# 2026-09-13：四項 Methodology 警告檢查

基準：build/dcim_master_chip/dcim_master_chip_pynq_z2.runs/impl_1/
dcim_master_chip_top_methodology_drc_routed.rpt（2026-09-12）。
本次是部分改善實驗，不代表四項警告皆已排除。

| 項目 | 原因 | 本次處理 |
|---|---|---|
| LUTAR-1 #1 | model_rst_n 與 reset2 組合後驅動 SRAM serializer 非同步 clear | 保留原規格，未改 RTL |
| LUTAR-1 #2 | reset_button OR !clock_locked 驅動 reset release pipe 非同步 preset | 保留失鎖／按鍵立即 reset 行為，未改 RTL |
| LUTAR-1 #3 | master 的 reset／CIM_RESET 狀態組合解碼驅動 ACC 與輸出暫存器非同步 clear | 保留命令時序，未改 RTL |
| ULMTCS-2 | 2064 control sets，超過報告 13300 基準的 15%（約15.52%） | cell_bit 加 EXTRACT_ENABLE="no"，嘗試將 write_en 映射到 D-input mux |

## 本次修改的原理

cell 仍然是一顆 FF；非同步清零、write_en 時寫入、否則保持都不改變。
原本不同 byte 的寫入 enable 可形成不同 CE control set；128 rows × 16
byte pairs = 2048 個獨立寫入位置，與報告數量接近，但確切歸屬需由
report_control_sets -verbose 確認。EXTRACT_ENABLE="no" 要求將 enable
功能移至 FF 的 D 端，而不是獨立 CE。這可能減少 control sets，但可能
增加資料 mux、切換活動或改變路由，不能保證 LUT／時序一定改善。

report_dcim_common.tcl 新增 control_sets.rpt，以及 post-route 的
methodology.rpt，方便重跑比較；原有報告沒有修改或刪除。

## Reset 後續方案（尚未實作）

不要僅用 false_path 或降低警告等級隱藏 LUTAR-1。
對 SRAM serializer／ACC：可以分開全域 reset 與同步 command clear，
但會改變 reset1/reset2 在非時脈邊緣時立即清除的行為，需同步更新晶片
規格與 TB。另一方案是由 master 以 next-state 產生已註冊 reset 輸出，
但還需處理 chip 內合併 reset 的 LUT，不能只多加一顆 FF 就宣稱解決。
對板上 reset：可以各自做 reset 同步／釋放鏈後，將合併結果作同步控制，
必須另行檢驗 MMCM 未鎖定、失鎖停鐘、按鍵中途 reset 的安全行為。

## 驗證與重跑

本地執行 make test-cell；此測試驗證功能，不會證明 Vivado 的 CE 映射。
Vivado GUI 對原專案重新 Run Synthesis，再 Run Implementation（需要
重設 runs 時確認提示）。比較 methodology.rpt、control_sets.rpt、
hierarchy.rpt、timing_summary.rpt；保留原報告作基準。
預期觀察 ULMTCS-2 是否下降／消失，LUTAR-1 三項本輪仍可能存在。
本地沒有 Vivado，不能宣稱警告已消除。
