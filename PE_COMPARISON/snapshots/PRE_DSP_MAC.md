# DSP MAC 修改前版本

備份：`pre_dsp_mac_20260911.tar.gz`

SHA256：`dca5e47e1d6e712d6ea84bfcd9b1416ef2bf5d6a181b4e23bd857c0a5596cc71`

包含修改前 PE_CHIP、PE_CHIP_8x8、PE_COMPARISON 的來源、測試、文件與腳本；排除 build、reports、snapshots。既有合成報告留在原位，未刪除或覆寫。備份以 tar 保存原檔，不是重新產生的近似版本。

舊架構：乘法器有 `use_dsp=yes`，但無 Product pipeline；外部 32-bit accumulator 在接受輸入的同一個上升緣更新。新架構會改變此時序契約。

要查看舊版，請解壓到新目錄，不要直接覆蓋目前工作目錄：

```bash
mkdir -p /tmp/pe_before_dsp_mac_review
tar -xzf pre_dsp_mac_20260911.tar.gz -C /tmp/pe_before_dsp_mac_review
```
