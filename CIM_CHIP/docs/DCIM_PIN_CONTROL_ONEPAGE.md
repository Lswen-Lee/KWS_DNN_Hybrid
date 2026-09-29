# 一頁式 DCIM 操作控制表

- [Excel：單一工作表](DCIM_PIN_CONTROL_ONEPAGE.xlsx)
- [PDF：單頁報告](DCIM_PIN_CONTROL_ONEPAGE.pdf)
- [PNG：16:9 簡報圖片](DCIM_PIN_CONTROL_ONEPAGE.png)

包含 SRAM 寫入、SRAM 讀出、CIM 計算的九個操作狀態。各列提供腳位 0／1、din 內容、cycles 與功能，不列訊號方向。共用的時脈、reset、NV 與地址設定集中在頁尾。原七工作表詳細版保留，不覆寫。

Excel 設為橫向 A3、一頁寬一頁高；PDF 已直接排成一頁。綠底表示高電位。reset1／reset2 合併一欄，以「reset1 / reset2」順序列值。

重現：

```bash
python3 CIM_CHIP/scripts/export_pin_control_onepage.py --font /path/to/NotoSansCJKtc-Regular.otf
```

需要 openpyxl、matplotlib 及繁體中文字型。與詳細版共用狀態資料，先核對 RTL 控制值，再產表並重新載入 Excel 逐格檢查。已檢視圖片版面；不涉及 RTL 變更、功能模擬或 Vivado 合成。
