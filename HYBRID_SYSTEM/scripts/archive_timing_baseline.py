"""Local evidence archive; current sources are not claimed to be build-time sources."""
import hashlib
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HYBRID = ROOT / "HYBRID_SYSTEM"
DEST = HYBRID / "build/baselines/kws_125m_53m_pass_20261021"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if DEST.exists():
        raise SystemExit(f"Refusing existing archive: {DEST}")
    run = HYBRID / "build/kws_postroute_run02"
    dcp = run / "after/routed.dcp"
    if not dcp.is_file():
        raise SystemExit("Missing passing DCP")
    if "All user specified timing constraints are met." not in (run / "after/timing_summary.rpt").read_text():
        raise SystemExit("Input timing report is not passing")
    DEST.mkdir(parents=True)
    # Preserve before/after reports, DCP, input-route status and experiment record.
    shutil.copytree(run, DEST / "postroute")
    strategy = HYBRID / "build/kws_strategy_run01"
    shutil.copytree(strategy / "reports/aggressive", DEST / "parent_aggressive")
    shutil.copy2(strategy / "kws_board.xpr", DEST / "parent_project.xpr")
    for name in ("summary.csv", "experiment.txt"):
        shutil.copy2(strategy / "reports" / name, DEST / ("strategies_" + name))
    shutil.copytree(HYBRID / "build/kws_board_vectors", DEST / "vectors_current")
    head = git("rev-parse", "HEAD").decode().strip()
    # Tracked base plus binary-safe tracked working-tree diff; never publish dirty files.
    subprocess.run(["git", "archive", "--format=tar", "-o", str(DEST / "git_head.tar"), head], cwd=ROOT, check=True)
    (DEST / "working_tree.patch").write_bytes(git("diff", "--binary", "HEAD"))
    (DEST / "git_status.txt").write_bytes(git("status", "--short"))
    # Directly usable current RTL/constraints/scripts copy, including listed untracked sources.
    sources = {(HYBRID / line.strip()).resolve() for line in
               (HYBRID / "build/kws_board_vectors/sources.txt").read_text().splitlines() if line.strip()}
    sources.update((HYBRID / "board/kws").glob("*.tcl"))
    sources.update((HYBRID / "board/kws").glob("*.xdc"))
    for src in sorted(sources):
        rel = src.relative_to(ROOT)
        target = DEST / "sources_current" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, target)
        if sha(src) != sha(target):
            raise RuntimeError(f"Copy mismatch: {src}")
    provenance = {
        "archive_time_utc": datetime.now(timezone.utc).isoformat(),
        "snapshot_head": head,
        "branch": git("branch", "--show-current").decode().strip(),
        "source_provenance": "Current working tree and vectors captured at archival time. Build-time source hashes were not recorded; exact correspondence cannot be independently proved.",
        "authoritative_implemented_artifact": "postroute/after/routed.dcp",
        "constraints": "Implemented constraints embedded in DCP, with clocks/exceptions reports; sources_current XDC/hooks are current snapshots, not independently proven build-time copies.",
        "validation_scope": "Reported setup/hold/pulse width pass under existing exceptions; CDC/reset/DRC warnings remain; no bitstream or board test claimed.",
    }
    (DEST / "PROVENANCE.json").write_text(json.dumps(provenance, indent=2) + "\n")
    entries = {str(p.relative_to(DEST)): {"bytes": p.stat().st_size, "sha256": sha(p)}
               for p in sorted(DEST.rglob("*")) if p.is_file()}
    (DEST / "MANIFEST.json").write_text(json.dumps(entries, indent=2) + "\n")
    for name, entry in entries.items():
        if sha(DEST / name) != entry["sha256"]:
            raise RuntimeError(f"Archive verification failed: {name}")
    if sha(dcp) != entries["postroute/after/routed.dcp"]["sha256"]:
        raise RuntimeError("Passing DCP copy mismatch")
    print(json.dumps({"archive": str(DEST), "head": head, "files_verified": len(entries),
                      "manifest_sha256": sha(DEST / "MANIFEST.json"),
                      "passing_dcp_sha256": sha(dcp)}, indent=2))


if __name__ == "__main__":
    main()
