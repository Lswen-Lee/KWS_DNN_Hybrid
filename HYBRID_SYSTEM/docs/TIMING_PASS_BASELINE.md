# 125 MHz／53 MHz 時序通過基準

基準ID：`kws_125m_53m_pass_20261021`。

本機封存：`HYBRID_SYSTEM/build/baselines/kws_125m_53m_pass_20261021/`。
原始結果：`build/kws_postroute_run02/after/`。封存不覆寫原結果，也不作為後續實驗的輸出目錄。

封存HEAD：`82949f098e47c223d42b4fa9243ab9575745f1cb`（非合成時來源版本的獨立證明）。128個資料檔案已完成SHA256驗證，通過DCP的副本與原檔hash相同。

```text
postroute/after/routed.dcp SHA256:
cbdf80c8693208d4601be594cf8508b48b9ddcf21528c4a0c4d9403cba17f9f3
MANIFEST.json SHA256:
372411bfe55aac3464639372860af200ac3110de43f797bf009b6cc6f83478d4
```

## 通過範圍

Vivado 2023.2，kws_board_top、xc7z020clg400-1、PIPE=1／POST=1／CHECK_RESULT_ORDER=1；aggressive routed DCP後執行Explore phys_opt及NoTimingRelaxation route。

| 指標 | 基準 |
|---|---:|
| 系統／CIM頻率 | 125／53 MHz |
| WNS／TNS | +0.040／0.000 ns |
| WHS／THS | +0.070／0.000 ns |
| Setup／hold／pulse-width失敗端點 | 0／0／0 |
| Routing errors | 0 |
| LUT／FF | 27064／21611 |
| BRAM tiles／DSP | 18／10 |

保留目前例外約束下的STA證據，不代表CDC/reset簽核或板測通過。CDC-7=23、CDC-10=1、CDC-15=327，DRC警告52、methodology警告16仍待審核；沒有bitstream。

## 封存內容與來源限制

- `postroute/after/routed.dcp`：權威的通過時序網表／布局繞線及內嵌約束。
- `postroute/before/`、`postroute/after/`：時序、資源、CDC、DRC、methodology、clock、exceptions等報告。
- `parent_aggressive/`、`parent_project.xpr`、`strategies_*`：上一階段DCP、報告、策略記錄；XPR僅作紀錄，其原路徑不保證可直接移機開啟。
- `git_head.tar`：封存當下HEAD的已追蹤版本。
- `working_tree.patch`：相對HEAD的binary-safe未提交差異（僅本機保存，不提交使用者修改）。
- `sources_current/`：從sources.txt取得的目前RTL，及目前板級Tcl/XDC。
- `vectors_current/`：目前板級ROM、manifest與來源清單。
- `PROVENANCE.json`：封存時間、HEAD、來源可信度與驗證範圍。
- `MANIFEST.json`：所有封存資料檔案的SHA256與bytes（不包含manifest自己）。

**來源可信度限制：** 當時synthesis使用live RTL且未保存逐檔來源hash。因此目前來源與測資快照不能被宣稱是經證明完全相同的build-time來源；未提交的cell等修改也可能影響來源對應。DCP及報告才是本次物理結果的直接證據。重建工作樹時先解開git_head.tar，再於獨立目錄套用working_tree.patch；不要套用到現有工作樹。未追蹤檔不在patch中；sources_current補存實際來源清單列出的檔案。

## 開啟基準（唯讀分析用途）

在沒有其他設計開啟的Vivado Tcl Console：

```tcl
open_checkpoint {C:/Windows/System32/aoc-workspace/projects/KWS/KWS_DNN_Hybrid/HYBRID_SYSTEM/build/baselines/kws_125m_53m_pass_20261021/postroute/after/routed.dcp}
report_timing_summary -report_unconstrained
```

不要將新DCP或報告寫回封存路徑。後續實驗另建目錄，若RTL改變需重新驗證。保存工具`scripts/archive_timing_baseline.py`拒絕已有封存目錄，避免重跑覆寫。大型封存由.gitignore保留於本機，不會隨git push上傳；需要另行備份到第二個儲存裝置才能防止本機資料遺失。
