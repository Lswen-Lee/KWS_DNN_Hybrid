# DCIM 操作控制表

Excel： [DCIM_PIN_CONTROL_TABLE.xlsx](DCIM_PIN_CONTROL_TABLE.xlsx)

以 chip 為方向基準，正常操作 rst=0。以下與 Excel 同源生成；RTL 未修改。

## 使用說明

| 項目 | 內容 |
| --- | --- |
| 依據 | dcim_pin_master.sv 與 dcim_chip_pin_top.sv；目前數位 RTL，不是實體晶片電性規格。 |
| 方向 | 以 chip 為基準：輸入由 Master 驅動；sume／sumo 由 chip 回傳。clk 是共用時脈。 |
| 前提 | 各操作表皆為 rst=0、model_rst_n=1；clk 持續運行，表列動作在上升緣發生。綠底 1 表示高電位。 |
| 初始化 | Master rst=1 且狀態已重設：model_rst_n=0，reset1=reset2=1；其他控制=0，din=0，地址=0。初始化會清 cell。 |
| Idle／Done | rst=0 時 model_rst_n=1；其他單 bit 控制全部=0，din=0；地址保留。輸出可能保留舊值，不採樣。 |
| 命令接受 | 僅 ST_IDLE 且 start=1 的上升緣接受命令並保存參數；ST_DONE 時 busy=0，但不接受新命令。 |
| cycle 定義 | 從命令被接受的上升緣，到進入 ST_DONE：寫3、讀9、CIM91；不包含下一筆命令接受間隔。 |
| 命令間隔 | ST_DONE 下一緣回 IDLE，再下一緣才可接受 start；請勿只因 busy=0 就在 DONE 發出單拍 start。 |
| 模型限制 | pre_en 保留但沒有類比預充電功能；nv_store／nv_recall／pd_en 固定0且未模擬NV／電源行為。 |
| 驗證範圍 | 產表腳本核對13個狀態的控制值與RTL；Excel重新載入逐格核對。非功能模擬或Vivado驗證。 |

## 腳位定義

| Chip 腳位 | Master 對應 | 方向（以 chip 為準） | 位寬 | 功能 |
| --- | --- | --- | --- | --- |
| clk | 共用 clk（不是 chip_clk_en） | 輸入 | 1 | 持續時脈，上升緣運作。 |
| model_rst_n | chip_model_rst_n | 輸入 | 1 | 低有效模型初始化；正常為 1。不要每筆命令清除，會影響儲存內容。 |
| reset1 | chip_reset1 | 輸入 | 1 | 高有效；清除 accumulator。 |
| reset2 | chip_reset2 | 輸入 | 1 | 高有效；清除序列輸出狀態。 |
| mode_sel | chip_mode_sel | 輸入 | 1 | 0：SRAM；1：CIM。 |
| wl_en | chip_wl_en | 輸入 | 1 | SRAM row 選擇使能；目前 CIM 計算時為 0。 |
| write_en | chip_write_en | 輸入 | 1 | 將 buffer 中的權重寫入選定 row／bank pair。 |
| sense_en | chip_sense_en | 輸入 | 1 | SRAM 讀取擷取控制。 |
| pre_en | chip_pre_en | 輸入 | 1 | 讀取 capture 時為 1；模型不實現類比預充電。 |
| clk_en | chip_clk_en | 輸入 | 1 | 輸入 buffer 移入使能，不是外部 clk 本身。 |
| sel_next | chip_sel_next | 輸入 | 1 | 切換輸入路徑，提供已載入的 buffer 資料。 |
| output_en | chip_output_en | 輸入 | 1 | 接受一次 CIM partial sum，不是逐 bit 輸出使能。 |
| nv_store | chip_nv_store | 輸入 | 1 | 保留腳位，目前 Master 固定輸出 0。 |
| nv_recall | chip_nv_recall | 輸入 | 1 | 保留腳位，目前 Master 固定輸出 0。 |
| pd_en | chip_pd_en | 輸入 | 1 | 保留腳位，目前 Master 固定輸出 0。 |
| row_addr | chip_row_addr | 輸入 | 7 | SRAM：row 0..127；CIM：[6:5] 選 group 0..3。 |
| bank_addr | chip_bank_addr | 輸入 | 4 | pair 0..15；pair b 對應 even bank 2b 與 odd bank 2b+1。 |
| din | chip_din | 輸入 | 4 | 權重 nibble 或同一 plane 的四個 activation bits。 |
| sume | chip_sume | 輸出 | 1 | CIM even／高權重 nibble 的序列結果；SRAM不使用。 |
| sumo | chip_sumo | 輸出 | 1 | SRAM序列讀回，或CIM odd／低權重 nibble 序列結果。 |

## SRAM寫入

| 腳位或項目 | 方向 | ST_WRITE_LOAD_HIGH | ST_WRITE_LOAD_LOW | ST_WRITE_CELL | 備註 |
| --- | --- | --- | --- | --- | --- |
| 持續 cycles | — | 1 | 1 | 1 | 詳見使用說明的cycle起算方式。 |
| model_rst_n | chip 輸入 | 1 | 1 | 1 | 低有效模型初始化；正常為 1。不要每筆命令清除，會影響儲存內容。 |
| reset1 | chip 輸入 | 0 | 0 | 0 | 高有效；清除 accumulator。 |
| reset2 | chip 輸入 | 0 | 0 | 0 | 高有效；清除序列輸出狀態。 |
| mode_sel | chip 輸入 | 0 | 0 | 0 | 0：SRAM；1：CIM。 |
| wl_en | chip 輸入 | 0 | 0 | 1 | SRAM row 選擇使能；目前 CIM 計算時為 0。 |
| write_en | chip 輸入 | 0 | 0 | 1 | 將 buffer 中的權重寫入選定 row／bank pair。 |
| sense_en | chip 輸入 | 0 | 0 | 0 | SRAM 讀取擷取控制。 |
| pre_en | chip 輸入 | 0 | 0 | 0 | 讀取 capture 時為 1；模型不實現類比預充電。 |
| clk_en | chip 輸入 | 1 | 1 | 0 | 輸入 buffer 移入使能，不是外部 clk 本身。 |
| sel_next | chip 輸入 | 0 | 0 | 1 | 切換輸入路徑，提供已載入的 buffer 資料。 |
| output_en | chip 輸入 | 0 | 0 | 0 | 接受一次 CIM partial sum，不是逐 bit 輸出使能。 |
| nv_store | chip 輸入 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| nv_recall | chip 輸入 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| pd_en | chip 輸入 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| clk | chip 輸入 | 持續時脈 | 持續時脈 | 持續時脈 | 共用 Master／chip 時脈。 |
| din[3:0] | chip 輸入 | weight[7:4] | weight[3:0] | 0000 | 0000 是實際驅動值，不以 X 代替。 |
| row_addr[6:0] | chip 輸入 | 保存的 row_addr_q | 保存的 row_addr_q | 保存的 row_addr_q | CIM只以[6:5]選group；讀寫使用完整7-bit。Burst每筆自動遞增。 |
| bank_addr[3:0] | chip 輸入 | 保存的 bank_addr_q | 保存的 bank_addr_q | 保存的 bank_addr_q | 整筆讀／寫／CIM期間保持；Burst先遞增pair，15之後換row。 |
| sume | chip 輸出 | 不採樣 | 不採樣 | 不採樣 | 由chip產生，Master不能設定0或1。 |
| sumo | chip 輸出 | 不採樣 | 不採樣 | 不採樣 | 讀capture緣後顯示bit7；第8次CIM sample緣後顯示bit17。 |
| 階段動作 | — | 輸入高 nibble | 輸入低 nibble | 上升緣將 buffer 的 8 bits 寫入 cell pair | 各操作正常完成後進入 ST_DONE。 |

## SRAM讀取

| 腳位或項目 | 方向 | ST_READ_CAPTURE | ST_READ_SHIFT | 備註 |
| --- | --- | --- | --- | --- |
| 持續 cycles | — | 1 | 8 | 詳見使用說明的cycle起算方式。 |
| model_rst_n | chip 輸入 | 1 | 1 | 低有效模型初始化；正常為 1。不要每筆命令清除，會影響儲存內容。 |
| reset1 | chip 輸入 | 0 | 0 | 高有效；清除 accumulator。 |
| reset2 | chip 輸入 | 0 | 0 | 高有效；清除序列輸出狀態。 |
| mode_sel | chip 輸入 | 0 | 0 | 0：SRAM；1：CIM。 |
| wl_en | chip 輸入 | 1 | 0 | SRAM row 選擇使能；目前 CIM 計算時為 0。 |
| write_en | chip 輸入 | 0 | 0 | 將 buffer 中的權重寫入選定 row／bank pair。 |
| sense_en | chip 輸入 | 1 | 0 | SRAM 讀取擷取控制。 |
| pre_en | chip 輸入 | 1 | 0 | 讀取 capture 時為 1；模型不實現類比預充電。 |
| clk_en | chip 輸入 | 0 | 0 | 輸入 buffer 移入使能，不是外部 clk 本身。 |
| sel_next | chip 輸入 | 1 | 0 | 切換輸入路徑，提供已載入的 buffer 資料。 |
| output_en | chip 輸入 | 0 | 0 | 接受一次 CIM partial sum，不是逐 bit 輸出使能。 |
| nv_store | chip 輸入 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| nv_recall | chip 輸入 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| pd_en | chip 輸入 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| clk | chip 輸入 | 持續時脈 | 持續時脈 | 共用 Master／chip 時脈。 |
| din[3:0] | chip 輸入 | 0000 | 0000 | 0000 是實際驅動值，不以 X 代替。 |
| row_addr[6:0] | chip 輸入 | 保存的 row_addr_q | 保存的 row_addr_q | CIM只以[6:5]選group；讀寫使用完整7-bit。Burst每筆自動遞增。 |
| bank_addr[3:0] | chip 輸入 | 保存的 bank_addr_q | 保存的 bank_addr_q | 整筆讀／寫／CIM期間保持；Burst先遞增pair，15之後換row。 |
| sume | chip 輸出 | 不採樣 | 不採樣 | 由chip產生，Master不能設定0或1。 |
| sumo | chip 輸出 | 不採樣 | 接收 bit7→0 | 讀capture緣後顯示bit7；第8次CIM sample緣後顯示bit17。 |
| 階段動作 | — | 上升緣載入讀取 serializer；該緣後 sumo 顯示 bit7 | 每個上升緣接收 sumo：bit7→bit0；同緣 chip 移位 | 各操作正常完成後進入 ST_DONE。 |

## CIM計算

| 腳位或項目 | 方向 | ST_CIM_RESET | ST_CIM_LOAD | ST_CIM_SAMPLE | ST_RESULT_CAPTURE | 備註 |
| --- | --- | --- | --- | --- | --- | --- |
| 持續 cycles | — | 1 | 每 plane 8，共 64 | 每 plane 1，共 8 | 18 | CIM 的 LOAD／SAMPLE 交替重複8次，不是先64次LOAD再8次SAMPLE。 |
| model_rst_n | chip 輸入 | 1 | 1 | 1 | 1 | 低有效模型初始化；正常為 1。不要每筆命令清除，會影響儲存內容。 |
| reset1 | chip 輸入 | 1 | 0 | 0 | 0 | 高有效；清除 accumulator。 |
| reset2 | chip 輸入 | 1 | 0 | 0 | 0 | 高有效；清除序列輸出狀態。 |
| mode_sel | chip 輸入 | 1 | 1 | 1 | 1 | 0：SRAM；1：CIM。 |
| wl_en | chip 輸入 | 0 | 0 | 0 | 0 | SRAM row 選擇使能；目前 CIM 計算時為 0。 |
| write_en | chip 輸入 | 0 | 0 | 0 | 0 | 將 buffer 中的權重寫入選定 row／bank pair。 |
| sense_en | chip 輸入 | 0 | 0 | 0 | 0 | SRAM 讀取擷取控制。 |
| pre_en | chip 輸入 | 0 | 0 | 0 | 0 | 讀取 capture 時為 1；模型不實現類比預充電。 |
| clk_en | chip 輸入 | 0 | 1 | 0 | 0 | 輸入 buffer 移入使能，不是外部 clk 本身。 |
| sel_next | chip 輸入 | 0 | 0 | 1 | 1 | 切換輸入路徑，提供已載入的 buffer 資料。 |
| output_en | chip 輸入 | 0 | 0 | 1 | 0 | 接受一次 CIM partial sum，不是逐 bit 輸出使能。 |
| nv_store | chip 輸入 | 0 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| nv_recall | chip 輸入 | 0 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| pd_en | chip 輸入 | 0 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| clk | chip 輸入 | 持續時脈 | 持續時脈 | 持續時脈 | 持續時脈 | 共用 Master／chip 時脈。 |
| din[3:0] | chip 輸入 | 0000 | 四個 activation 的同一 plane | 0000 | 0000 | 0000 是實際驅動值，不以 X 代替。 |
| row_addr[6:0] | chip 輸入 | 保存的 row_addr_q | 保存的 row_addr_q | 保存的 row_addr_q | 保存的 row_addr_q | CIM只以[6:5]選group；讀寫使用完整7-bit。Burst每筆自動遞增。 |
| bank_addr[3:0] | chip 輸入 | 保存的 bank_addr_q | 保存的 bank_addr_q | 保存的 bank_addr_q | 保存的 bank_addr_q | 整筆讀／寫／CIM期間保持；Burst先遞增pair，15之後換row。 |
| sume | chip 輸出 | 不採樣 | 不採樣 | 不採樣 | 接收 even bit17→0 | 由chip產生，Master不能設定0或1。 |
| sumo | chip 輸出 | 不採樣 | 不採樣 | 不採樣 | 接收 odd bit17→0 | 讀capture緣後顯示bit7；第8次CIM sample緣後顯示bit17。 |
| 階段動作 | — | 只清 ACC 與輸出狀態，不清權重 cell | stage=7→0，plane=7→0；詳見資料時序表 | 接受 partial sum；第八次 sample 緣後顯示結果 bit17 | 每個上升緣同時接收 sume／sumo：bit17→bit0 | 各操作正常完成後進入 ST_DONE。 |

## Burst寫入

| 腳位或項目 | 方向 | ST_BURST_WAIT_DATA | ST_BURST_LOAD_HIGH | ST_BURST_LOAD_LOW | ST_BURST_WRITE_CELL | 備註 |
| --- | --- | --- | --- | --- | --- | --- |
| 持續 cycles | — | 依 valid 等待 | 每筆 1 | 每筆 1 | 每筆 1 | 詳見使用說明的cycle起算方式。 |
| model_rst_n | chip 輸入 | 1 | 1 | 1 | 1 | 低有效模型初始化；正常為 1。不要每筆命令清除，會影響儲存內容。 |
| reset1 | chip 輸入 | 0 | 0 | 0 | 0 | 高有效；清除 accumulator。 |
| reset2 | chip 輸入 | 0 | 0 | 0 | 0 | 高有效；清除序列輸出狀態。 |
| mode_sel | chip 輸入 | 0 | 0 | 0 | 0 | 0：SRAM；1：CIM。 |
| wl_en | chip 輸入 | 0 | 0 | 0 | 1 | SRAM row 選擇使能；目前 CIM 計算時為 0。 |
| write_en | chip 輸入 | 0 | 0 | 0 | 1 | 將 buffer 中的權重寫入選定 row／bank pair。 |
| sense_en | chip 輸入 | 0 | 0 | 0 | 0 | SRAM 讀取擷取控制。 |
| pre_en | chip 輸入 | 0 | 0 | 0 | 0 | 讀取 capture 時為 1；模型不實現類比預充電。 |
| clk_en | chip 輸入 | 0 | 1 | 1 | 0 | 輸入 buffer 移入使能，不是外部 clk 本身。 |
| sel_next | chip 輸入 | 0 | 0 | 0 | 1 | 切換輸入路徑，提供已載入的 buffer 資料。 |
| output_en | chip 輸入 | 0 | 0 | 0 | 0 | 接受一次 CIM partial sum，不是逐 bit 輸出使能。 |
| nv_store | chip 輸入 | 0 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| nv_recall | chip 輸入 | 0 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| pd_en | chip 輸入 | 0 | 0 | 0 | 0 | 保留腳位，目前 Master 固定輸出 0。 |
| clk | chip 輸入 | 持續時脈 | 持續時脈 | 持續時脈 | 持續時脈 | 共用 Master／chip 時脈。 |
| din[3:0] | chip 輸入 | 0000 | weight[7:4] | weight[3:0] | 0000 | 0000 是實際驅動值，不以 X 代替。 |
| row_addr[6:0] | chip 輸入 | 保存的 row_addr_q | 保存的 row_addr_q | 保存的 row_addr_q | 保存的 row_addr_q | CIM只以[6:5]選group；讀寫使用完整7-bit。Burst每筆自動遞增。 |
| bank_addr[3:0] | chip 輸入 | 保存的 bank_addr_q | 保存的 bank_addr_q | 保存的 bank_addr_q | 保存的 bank_addr_q | 整筆讀／寫／CIM期間保持；Burst先遞增pair，15之後換row。 |
| sume | chip 輸出 | 不採樣 | 不採樣 | 不採樣 | 不採樣 | 由chip產生，Master不能設定0或1。 |
| sumo | chip 輸出 | 不採樣 | 不採樣 | 不採樣 | 不採樣 | 讀capture緣後顯示bit7；第8次CIM sample緣後顯示bit17。 |
| 階段動作 | — | burst_weight_ready=1；等候下一筆權重 | 輸入高 nibble | 輸入低 nibble | 寫入本筆；若還有下一筆可同緣預取，資料不足則回 WAIT | 各操作正常完成後進入 ST_DONE。 |

## 資料時序與命令

| 操作 | Master命令（非chip pin） | 資料／時序 | 結果 |
| --- | --- | --- | --- |
| SRAM寫 | operation=0；row、pair、command_weight | LOAD_HIGH→LOAD_LOW→WRITE_CELL；3 cycles | done=1，result_valid=0；可另送讀命令驗證。 |
| SRAM讀 | operation=1；row、pair | CAPTURE→SHIFT×8；9 cycles。CAPTURE緣後bit7可見，下一緣Master接收。 | sram_read_data[7:0]；done=result_valid=1。 |
| CIM | operation=2；group取row[6:5]、pair、activation_flat、activation_is_a8 | RESET→(LOAD×8→SAMPLE)×8→RESULT_CAPTURE×18；91 cycles | even_raw_result與odd_raw_result各18 bits；done=result_valid=1。 |
| CIM plane | activation_flat[(row*8)+:8]=A[row] | plane p=7→0；每plane依序輸入rows28..31、24..27、…、0..3 | din[lane]=A[4*stage+lane][p]，stage=7→0，lane=0..3。 |
| CIM A4 | activation_is_a8=0 | 仍送8planes；p=7..4傳0，p=3..0傳activation低4bits | 與A8同為91cycles，並非縮成4次sample。 |
| CIM A8 | activation_is_a8=1 | 傳送每個activation的bit7..bit0 | unsigned原始結果；W8重建為odd+(even<<4)，須先擴位避免截斷；本Master未做此重建。 |
| Burst寫 | operation=3；長度1..2048且不得超出row/pair地址空間 | 資料連續且第一筆與start同緣接受時3N cycles；缺資料則等待 | valid與ready在上升緣同時1才接受；WRITE_CELL可能預取下一筆，不要混淆請求地址與chip當前寫入地址。 |
| 錯誤 | Burst長度0或超出2048個word的地址範圍 | 命令後進入DONE，不做cell write | error=1、result_valid=0。 |
