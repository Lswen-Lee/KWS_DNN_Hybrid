"""Conservative Vivado text report summary: missing data is never zero."""
import argparse
import csv
import re
from pathlib import Path

ALIASES = {
    "LUT": ("Slice LUTs", "CLB LUTs"),
    "FF": ("Slice Registers", "CLB Registers"),
    "DSP": ("DSPs", "DSP48E1 only", "DSP48E2 only"),
    "BRAM_tiles": ("Block RAM Tile",),
}
def parse_util(text):
    result = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 4:
            continue
        label = cells[1].rstrip("*").strip()
        for name, aliases in ALIASES.items():
            if label in aliases and name not in result:
                value = cells[2].replace(",", "")
                if re.fullmatch(r"\d+(?:\.\d+)?", value):
                    result[name] = float(value)
    return result

def parse_timing(text):
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if "WNS(ns)" in line and "WHS(ns)" in line and "TNS(ns)" in line:
            for row in lines[i+1:i+8]:
                tokens = row.split()
                if len(tokens) >= 8 and all(re.fullmatch(r"-?\d+(?:\.\d+)?", x) for x in tokens[:8]):
                    return {"WNS_ns": float(tokens[0]), "TNS_ns": float(tokens[1]),
                            "setup_failing_endpoints": float(tokens[2]),
                            "WHS_ns": float(tokens[4]), "THS_ns": float(tokens[5]),
                            "hold_failing_endpoints": float(tokens[6])}
    return {}

def read_text(path):
    return path.read_text(errors="replace") if path.is_file() else ""

def collect(directory):
    data = parse_util(read_text(directory / "utilization.rpt"))
    data.update(parse_timing(read_text(directory / "timing_summary.rpt")))
    return data

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pe9_report", type=Path)
    parser.add_argument("pe8_report", type=Path)
    parser.add_argument("--output", type=Path, default=Path("reports"))
    args = parser.parse_args()
    for directory in (args.pe9_report, args.pe8_report):
        if not directory.is_dir():
            parser.error(f"Report directory missing: {directory}")
    a,b = collect(args.pe9_report), collect(args.pe8_report)
    keys = list(ALIASES) + ["WNS_ns","TNS_ns","setup_failing_endpoints",
                            "WHS_ns","THS_ns","hold_failing_endpoints"]
    rows=[]
    for key in keys:
        va,vb=a.get(key),b.get(key)
        rows.append([key, "NOT_AVAILABLE" if va is None else f"{va:g}",
                     "NOT_AVAILABLE" if vb is None else f"{vb:g}",
                     "NOT_AVAILABLE" if va is None or vb is None else f"{vb-va:g}"])
    args.output.mkdir(parents=True, exist_ok=True)
    with (args.output/"comparison.csv").open("w", newline="") as stream:
        writer=csv.writer(stream)
        writer.writerow(["Metric","PE9","PE8","PE8_minus_PE9"])
        writer.writerows(rows)
    note = ("# Raw array comparison\n\n"
            f"PE9 source: {args.pe9_report}\n\nPE8 source: {args.pe8_report}\n\n"
            "Stage NOT automatically certified: inspect route_status.rpt and metadata.txt.\n"
            "Unconstrained endpoints, DRC and methodology require manual inspection of check_timing.rpt, timing_summary.rpt, drc.rpt and methodology.rpt.\n"
            "Do not interpret missing data as zero, WNS as Fmax, or this table as a timing-closure verdict.\n"
            "No power or energy measurement. Input conversion and correction excluded.\n\n"
            "| Metric | PE9 | PE8 | PE8 minus PE9 |\n|---|---:|---:|---:|\n")
    note += "\n".join("| "+" | ".join(row)+" |" for row in rows)+"\n"
    (args.output/"comparison.md").write_text(note)
    print(f"Summary written to {args.output}; manually verify stage, constraints and tool settings.")

if __name__ == "__main__":
    main()

