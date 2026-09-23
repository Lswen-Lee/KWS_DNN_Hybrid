"""Read actual Vivado reports; retain missing/failed runs instead of inventing data."""
import argparse
import csv
from pathlib import Path
import re

SCOPES = ("top", "chip", "macro", "controller", "self_test")


def utilization(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    values = {}
    for key, labels in {
        "lut": ("Slice LUTs", "CLB LUTs"),
        "ff": ("Slice Registers", "CLB Registers"),
    }.items():
        for label in labels:
            match = re.search(r"^\s*\|\s*" + re.escape(label) + r"\s*\*?\s*\|\s*([\d,]+)\s*\|", text, re.M)
            if match:
                values[key] = int(match[1].replace(",", ""))
                break
        else:
            raise ValueError(f"Cannot find {key} total in {path}")
    return values


def collect(root):
    rows = []
    runs = sorted((p for p in root.glob("f*") if p.is_dir() and re.fullmatch(r"f\d+", p.name)), key=lambda p: int(p.name[1:]))
    if not runs:
        raise ValueError(f"No fNN run folders in {root}")
    for run in runs:
        for stage in ("post_synth", "post_route"):
            row = {"frequency_mhz": int(run.name[1:]), "stage": stage}
            status = run / "status.txt"
            row["run_status"] = status.read_text().splitlines()[0] if status.exists() else "INCOMPLETE"
            errors = []
            try:
                with (run / stage / "metrics.tsv").open() as f:
                    metrics = list(csv.DictReader(f, delimiter="\t"))
                if len(metrics) != 1 or int(metrics[0]["frequency_mhz"]) != row["frequency_mhz"]:
                    raise ValueError("Wrong frequency/row count in metrics.tsv")
                row.update({key: float(metrics[0][key]) for key in ("period_ns", "wns_ns", "whs_ns")})
                if abs(row["period_ns"] - 1000 / row["frequency_mhz"]) > .002:
                    raise ValueError("Wrong generated clock period")
            except (OSError, ValueError, KeyError) as exc:
                errors.append(str(exc))
            for scope in SCOPES:
                try:
                    row.update({f"{scope}_{key}": value for key, value in utilization(run / stage / f"{scope}_utilization.rpt").items()})
                except (OSError, ValueError) as exc:
                    errors.append(str(exc))
            row["setup_hold_status"] = "UNKNOWN" if errors else ("PASS" if row["wns_ns"] >= 0 and row["whs_ns"] >= 0 else "FAIL")
            row["notes"] = "; ".join(errors)
            rows.append(row)
    return rows


def summarize(root, plot=True):
    rows = collect(root)
    fields = ["frequency_mhz", "stage", "run_status", "period_ns", "wns_ns", "whs_ns", "setup_hold_status"]
    fields += [f"{scope}_{resource}" for scope in SCOPES for resource in ("lut", "ff")]
    fields += ["notes"]
    with (root / "summary.csv").open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    lines = ["# DCIM frequency sweep", "", "Post-route results only. PASS means setup/hold slack >= 0, NOT full sign-off.",
             "Review check_timing, unconstrained paths, pulse width, DRC and methodology separately.", "",
             "| MHz | Run | Setup/hold | WNS ns | WHS ns | Top LUT | Top FF | Macro LUT | Macro FF | Controller LUT | Controller FF |",
             "|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
    columns = ("frequency_mhz", "run_status", "setup_hold_status", "wns_ns", "whs_ns", "top_lut", "top_ff", "macro_lut", "macro_ff", "controller_lut", "controller_ff")
    routed = [row for row in rows if row["stage"] == "post_route"]
    for row in routed:
        lines.append("| " + " | ".join(str(row.get(key, "N/A")) for key in columns) + " |")
    (root / "SUMMARY.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    if plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        for resource in ("lut", "ff"):
            fig, ax = plt.subplots(figsize=(10, 5.625), layout="constrained")
            for scope in ("top", "macro", "controller"):
                available = [r for r in routed if f"{scope}_{resource}" in r]
                if not available:
                    continue
                line, = ax.plot([r["frequency_mhz"] for r in available], [r[f"{scope}_{resource}"] for r in available], label=scope)
                for row in available:
                    passed = row["run_status"] == "COMPLETE" and row["setup_hold_status"] == "PASS"
                    ax.scatter(row["frequency_mhz"], row[f"{scope}_{resource}"], marker="o" if passed else "x", color=line.get_color(), s=55)
            ax.set(xlabel="Core frequency (MHz)", ylabel=f"{resource.upper()} count", title=f"DCIM post-route {resource.upper()} vs frequency\nCircle: setup/hold pass; cross: fail/incomplete (review reports)")
            ax.set_xticks([r["frequency_mhz"] for r in routed])
            ax.grid(alpha=.25)
            handles, labels = ax.get_legend_handles_labels()
            if handles:
                ax.legend()
            else:
                ax.text(.5, .5, "No measured resource data", transform=ax.transAxes, ha="center")
            for suffix in ("png", "svg"):
                fig.savefig(root / f"{resource}_vs_mhz.{suffix}", dpi=180)
            plt.close(fig)
    print(f"Saved summary.csv, SUMMARY.md{' and LUT/FF plots' if plot else ''}: {root}")
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--no-plot", action="store_true", help="CSV/Markdown only; no matplotlib needed")
    args = parser.parse_args()
    summarize(args.root.resolve(), not args.no_plot)
