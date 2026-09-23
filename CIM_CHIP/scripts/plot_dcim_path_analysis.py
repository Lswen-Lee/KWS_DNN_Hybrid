"""Plot measured worst setup paths; no timing simulation or invented values."""
import argparse
import csv
from pathlib import Path
import re

from summarize_dcim_sweep import collect


def read_path(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    def field(label):
        match = re.search(re.escape(label) + r"\s*([^\n]+)", text)
        if not match:
            raise ValueError(f"Missing {label} in {path}")
        return match[1].strip()
    delay = field("Data Path Delay:")
    match = re.match(r"([\d.]+)ns\s+\(logic ([\d.]+)ns.*?route ([\d.]+)ns", delay)
    if not match:
        raise ValueError(f"Unsupported delay format in {path}: {delay}")
    total, logic, route = map(float, match.groups())
    if total <= 0 or abs(total - logic - route) > .003:
        raise ValueError(f"Inconsistent delay components: {path}")
    return dict(source=field("Source:"), destination=field("Destination:"),
                data_ns=total, logic_ns=logic, route_ns=route,
                route_percent=100 * route / total,
                levels=int(field("Logic Levels:").split()[0]))


def plot(root):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    rows = []
    for row in collect(root):
        if row["stage"] != "post_route":
            continue
        path = root / f'f{row["frequency_mhz"]}' / "post_route/setup_paths.rpt"
        if not path.exists():
            print(f"Skipping absent path report: {path}")
            continue
        rows.append({**row, **read_path(path)})
    if not rows:
        raise ValueError("No measured paths available")
    keys = ("frequency_mhz", "wns_ns", "whs_ns", "data_ns", "logic_ns", "route_ns", "route_percent", "levels", "source", "destination")
    with (root / "critical_path_analysis.csv").open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore")
        writer.writeheader(); writer.writerows(rows)
    fig, (ax, bx) = plt.subplots(1, 2, figsize=(16, 7), layout="constrained")
    # Categorical positions give every measured experiment equal label space.
    x = list(range(len(rows)))
    ax.bar(x, [r["logic_ns"] for r in rows], label="Logic", color="#2563eb")
    ax.bar(x, [r["route_ns"] for r in rows], bottom=[r["logic_ns"] for r in rows], label="Routing", color="#f59e0b")
    for i, row in enumerate(rows):
        ax.text(i, row["data_ns"] + .25, f'{row["data_ns"]:.3f} ns\nroute {row["route_percent"]:.1f}%', ha="center", fontsize=9)
    ax.set_ylim(0, max(r["data_ns"] for r in rows) * 1.2)
    ax.set(title="Worst setup path: logic vs routing", ylabel="Data path delay (ns)")
    ax.legend(loc="lower left")
    bx.plot(x, [r["wns_ns"] for r in rows], color="#64748b")
    for i, row in enumerate(rows):
        ok = row["run_status"] == "COMPLETE" and row["setup_hold_status"] == "PASS"
        bx.scatter(i, row["wns_ns"], marker="o" if ok else "x", color="#15803d" if ok else "#dc2626", s=70)
        bx.annotate(f'{row["wns_ns"]:+.3f}', (i, row["wns_ns"]), xytext=(0, 13), textcoords="offset points", ha="center")
    bx.axhline(0, linestyle="--", color="black", linewidth=1)
    bx.margins(y=.25)
    bx.set(title="Setup margin: positive = met, negative = violated", ylabel="WNS (ns)")
    for axis in (ax, bx):
        axis.set_xticks(x, [str(r["frequency_mhz"]) for r in rows])
        axis.set_xlabel("Core frequency (MHz); individual implementation runs")
        axis.grid(axis="y", alpha=.2)
    fig.suptitle("DCIM routed critical-path analysis\nDifferent runs may have different worst paths; data delay is not clock period.", fontsize=17)
    for suffix in ("png", "svg"):
        fig.savefig(root / f"critical_path_analysis.{suffix}", dpi=160)
    plt.close(fig)
    print(f"Saved critical_path_analysis.csv/png/svg: {root}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    plot(parser.parse_args().root.resolve())
