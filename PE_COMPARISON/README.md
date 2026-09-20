# PE_COMPARISON

比較兩個相鄰資料夾的 raw 12-lane array，原版RTL不修改。

Windows Vivado 工作目錄：
`C:\Windows\System32\aoc-workspace\projects\KWS\KWS_DNN_Hybrid\PE_COMPARISON`

在 Windows Vivado Tcl Console 關閉既有專案後，擇一執行：

```tcl
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/PE_COMPARISON/vivado/create_pe9_project.tcl}
# 新版請在另一視窗或關閉原專案後執行：
source {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/PE_COMPARISON/vivado/create_pe8_project.tcl}
```

腳本依自身位置尋找相鄰 RTL，不需將內部路徑硬編碼；Docker 內 Makefile 仍使用相對路徑。Windows 主機須能實際讀取此目錄，本次未驗證主機掛載。

完整 Tcl 解說、純 GUI 匯入替代步驟、來源檔案清單與比較限制見 [操作指南](docs/PE_COMPARISON_GUIDE.md)。

`make test lint check-tools` 執行本地驗證。Vivado 腳本只建立專案，不自動合成。
