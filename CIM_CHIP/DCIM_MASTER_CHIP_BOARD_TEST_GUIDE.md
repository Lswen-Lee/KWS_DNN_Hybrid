# DCIM Pin Master單一50 MHz板級驗證

## 1. 驗證目的

此版本用PYNQ-Z2的125 MHz oscillator經MMCM產生真正50 MHz，且下列三個
模組全部使用同一個50 MHz clock：

```text
dcim_board_self_test
        -> dcim_pin_master
        -> dcim_chip_pin_top
```

因此不實例化`dcim_cdc_bridge`。這是DCIM數位模型的standalone bring-up，
不是最終125/50 MHz混合KWS系統。

## 2. 開機自動測試內容

Reset釋放後不需要外部命令，控制器會自動執行：

1. 以一筆2,048-word Burst對128 rows x 16 bank pairs全部位置寫入pattern。
2. 對全部2,048個位置逐筆SRAM serial readback並比對。
3. 對group 0、bank pair 0送入32個A8 activation：`1,2,...,32`。
4. 比對`even_raw_result=4640`與`odd_raw_result=1112`。
5. 將結果鎖存在Pass或Fail LED，直到再次Reset。

第一筆Burst資料與start同edge握手，後續資料在每個Cell write edge預取，
因此完整陣列寫入只需`2048 × 3 = 6144`個50 MHz clocks，即122.88 us。

Weight pattern為：

```text
weight[7:4] = row[3:0] XOR bank
weight[3:0] = row[6:3] XOR bank
```

## 3. PYNQ-Z2腳位與LED

| 訊號 | Package pin | 板上元件 | 意義 |
|---|---|---|---|
| `sys_clk_125m` | H16 | 125 MHz oscillator | MMCM輸入 |
| `reset_button` | D19 | BTN0 | 按下Reset，放開重新自測 |
| `led[0]` | R14 | LED0 | MMCM locked |
| `led[1]` | P14 | LED1 | Test busy |
| `led[2]` | N16 | LED2 | Test pass |
| `led[3]` | M14 | LED3 | Test fail |

正常完成後LED為：

```text
LED3 LED2 LED1 LED0 = 0 1 0 1
```

也就是LED0與LED2亮。Busy測試約在毫秒內完成，肉眼可能看不到LED1。

## 4. RTL模擬

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP
make test-dcim-master-chip-top
```

此 make 目標使用 Verilator，clock generator 依 `VERILATOR` 巨集採 pass-through，
testbench 直接提供50 MHz。Vivado synthesis 與 XSim 使用真正的 MMCME2_BASE；
若另建 XSim testbench，必須提供125 MHz輸入並等待locked，不可直接套用此pass-through時脈假設。

預期結果：

```text
PASS: LED mapping locked/busy/pass/fail = 0101
PASS: complete single-50-MHz master/chip self-test passed
```

## 5. 建立Vivado專案並手動合成

以下腳本只會建立Vivado專案、匯入RTL/XDC、設定Top與報告post hooks，不會自動執行
synthesis、implementation或bitstream。Linux下可執行：

```bash
cd /home/LAB505/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP
vivado -mode batch -source create_dcim_master_chip_project_pynq_z2.tcl
```

Windows 預設將專案與結果集中建立於 `CIM_CHIP/build/dcim_master_chip`：

```bat
vivado.bat -mode batch ^
  -source C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP/create_dcim_master_chip_project_pynq_z2.tcl
```

如果已經位於Vivado Tcl Console，應執行：

```tcl
# 先在GUI關閉目前專案。移除前次設定的輸出路徑，採用新的build預設位置。
unset -nocomplain dcim_project_dir
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP/create_dcim_master_chip_project_pynq_z2.tcl}
```

路徑對照：

| 用途 | 路徑 |
|---|---|
| Docker/Linux 原始碼 | `/home/LAB505/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP` |
| Windows 原始碼 | `C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP` |
| 預設專案位置 | `CIM_CHIP/build/dcim_master_chip` |
| 自動報告位置 | `CIM_CHIP/build/dcim_master_chip/reports` |
| Verilator 模擬產物 | `CIM_CHIP/build/sim` |

Tcl 會以腳本所在目錄尋找RTL/XDC，不必更改各RTL內的路徑，也不必移動原始碼。
`dcim_project_dir` 優先於 batch 的 `-tclargs`；兩者都未指定才使用預設目錄。
腳本不再使用 `create_project -force`：專案已開啟或目標目錄存在時會停止，不覆蓋舊成果。
若目錄已存在，可改用另一個新目錄，或在沒有開啟其他專案的情況下執行：

```tcl
open_project {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/CIM_CHIP/build/dcim_master_chip/dcim_master_chip_pynq_z2.xpr}
```

開啟舊專案不代表自動更新來源；若之前選擇Copy sources into project，須檢查副本是否為最新版。

未指定`dcim_project_dir`或`-tclargs`時，專案會建立於：

```text
CIM_CHIP/build/dcim_master_chip/dcim_master_chip_pynq_z2.xpr
```

腳本會完成以下設定後停止：

1. 選擇PYNQ-Z2使用的`xc7z020clg400-1`。
2. 掃描`cell/`、`segment/`、`peripheral/`、`array/`、`chip/`及`fpga/`的`.sv`。
3. 將來源檔指定為SystemVerilog，不加入`tb/`與舊的合成輸出資料夾。
4. 加入`constraints/dcim_master_chip_top_pynq_z2.xdc`。
5. 將`dcim_master_chip_top`設為Top並更新compile order。
6. 設定 synthesis 與 route 完成後的報告 hooks，包含 Macro 與 Controller 個別報告。

之後開啟`.xpr`，在Vivado Flow Navigator依序手動執行：

1. **Run Synthesis**
2. **Run Implementation**
3. 確認時序與DRC後 **Generate Bitstream**

這是一般板級top，不使用 `-mode out_of_context`。不要加入舊PE OOC約束或
`dcim_chip_pin_top_pynq_z2.xdc`；本專案只使用master/chip專用XDC。
GUI若手動匯入，只選上述六個RTL來源目錄，不要遞迴匯入整個CIM_CHIP，
避免納入tb、build、synth_1、impl_1或舊Vivado專案中的重複模組。

原本的`build_dcim_master_chip_pynq_z2.tcl`仍可使用，但現在只是相容入口，
其行為同樣只有建立與匯入專案，不會自動合成。

燒錄前至少確認：

```text
50 MHz generated clock存在
WNS >= 0
TNS = 0
WHS >= 0
THS = 0
Unrouted nets = 0
Critical DRC = 0
```

手動產生的Bitstream通常位於：

```text
<project_dir>/dcim_master_chip_pynq_z2.runs/impl_1/
dcim_master_chip_top.bit
```

## 6. 為何implementation通過仍可能板上失敗

Static timing只分析RTL/netlist與XDC描述的條件，不能證明下列真實條件：

- XDC package pin是否選對板上元件。
- 實體clock頻率、MMCM lock與reset release是否正確。
- 按鍵bounce、非同步輸入metastability與外部I/O電壓是否安全。
- 電源、溫度、線材、level shifter與signal integrity是否符合假設。
- XDC是否漏掉或錯誤描述external input/output delay。
- 真實外部CIM是否符合數位模型假設。

本自測將command source與DCIM model都放在FPGA內，可先排除外部資料輸入，
驗證clock、reset、Pin Master FSM、完整記憶體與CIM datapath。如果此版本Pass，
再逐步用ILA觀察或替換成AXI/外部CIM介面，錯誤範圍會小很多。

## 7. 建議的板上除錯順序

1. LED0不亮：先檢查H16、MMCM設定、reset與`report_clocks`。
2. LED0亮、LED3亮：使用ILA擷取Self-test state、Master state、row/bank、
   `done`、read data與even/odd result。
3. LED0和LED2亮：FPGA內數位DCIM及Pin Master基本路徑通過。
4. 再加入AXI或外部命令，保留原本Self-test作為開機診斷模式。
5. 最後才把內部`dcim_chip_pin_top`換成外部實體CIM pins。

## 8. 自動保存與分別量測 Macro／Controller

新建專案已設定 `STEPS.SYNTH_DESIGN.TCL.POST` 與 `STEPS.ROUTE_DESIGN.TCL.POST`。
你在GUI執行合成/實作後，報告自動產生；不必再手動貼下面的量測命令。
每次依時間建立新目錄，不覆蓋舊報告。未完成該階段就不會有該階段的報告。

```text
CIM_CHIP/build/
├── sim/                                      make測試產物
└── dcim_master_chip/
    ├── dcim_master_chip_pynq_z2.xpr
    ├── dcim_master_chip_pynq_z2.runs/
    │   ├── synth_1/
    │   └── impl_1/                           含完成後的.bit
    └── reports/
        ├── post_synth/<時間>/
        └── post_route/<時間>/
            ├── total_utilization.rpt
            ├── hierarchy.rpt
            ├── macro_utilization.rpt
            ├── controller_utilization.rpt
            ├── timing_summary.rpt
            ├── route_status.rpt              僅post_route
            └── drc.rpt                       僅post_route
```

`make clean` 預設只清除 `build/sim`，不清除 Vivado 專案或報告。舊目錄與舊報告不搬移、不刪除。
以前建立的專案不會自動更新：建議使用本次腳本建立新專案。若Windows遇到長路徑限制，
仍可透過 `dcim_project_dir` 選擇較短位置；報告會跟隨實際project directory。

下面保留手動匯出方法，適用於舊專案或額外檢查：

此文件是「master＋chip＋自測」板級流程，不是 macro-only 專案。若目的是量測大小，
先在同一份 Open Implemented Design 分別匯出階層資源：

```tcl
set macro_cell [get_cells -quiet {u_chip/u_dcim_macro_core}]
set controller_cell [get_cells -quiet {u_pin_master}]
if {[llength $macro_cell] != 1 || [llength $controller_cell] != 1} {
    error "Expected dcim_master_chip_top hierarchy not found. Check the opened design."
}
set output_dir [file normalize [file join [pwd] "dcim_resources_[clock seconds]"]]
file mkdir $output_dir
report_utilization -hierarchical -file [file join $output_dir hierarchy.rpt]
report_utilization -cells $macro_cell -file [file join $output_dir macro.rpt]
report_utilization -cells $controller_cell -file [file join $output_dir controller.rpt]
puts "Resource reports: $output_dir"
```

Macro含內部array與周邊；controller指dcim_pin_master，包含命令/資料暫存與序列接收，
不是純FSM。不要以top總資源當macro資源；u_chip還包含SRAM serializer等額外電路。
數值是FPGA模型成本，不是實體FeFET/NVM晶片面積。

本次只修改路徑、匯入安全檢查與文件，未修改CIM運算RTL或XDC；未在此環境執行Vivado，
因此不能宣稱路徑修改後一定通過時序。
