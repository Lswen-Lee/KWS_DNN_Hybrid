"""Pack validated software exports into a fixed S6 board demo ROM (not CIM init)."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

CHECKPOINT = "f5d5b047773f9efc2af9e80945927eba7d4edd7c66e8a88ee3e4d6fcff82b407"
LAYOUT = [("quant_input", 0, 8064), ("conv1_weights", 8064, 108),
          ("conv2_weights", 8172, 1296), ("conv3_weights", 9468, 1296),
          ("fc1_weights", 10764, 4608), ("fc2_weights", 15372, 256)]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def pack(vectors, output, root):
    manifest = json.loads((vectors / "manifest.json").read_text())
    if (manifest["checkpoint_sha256"] != CHECKPOINT or str(manifest["dataset_index"]) != "6988"
            or manifest["zero_point"] != 128 or manifest["bias"] is not False):
        raise ValueError("This board harness is fixed to validated checkpoint/sample 6988, zp128, no bias")
    image = [0] * 16384
    inputs = {}
    for name, base, count in LAYOUT + [("fc2", 0, 8)]:
        path = vectors / (name + ".mem")
        data = path.read_bytes()
        record = manifest["generated_files"][path.name]
        if sha(data) != record["sha256"] or record["bits"] != 8 or record["count"] != count:
            raise ValueError(f"Manifest mismatch: {path}")
        tokens = data.decode("ascii").split()
        if len(tokens) != count or any(len(t) != 2 or any(c not in "0123456789abcdefABCDEF" for c in t) for t in tokens):
            raise ValueError(f"Invalid byte image: {path}")
        values = [int(t, 16) for t in tokens]
        inputs[name] = {"base": base, "count": count, "sha256": sha(data)}
        if name == "fc2":
            best = max(range(8), key=lambda i: values[i])
            if (best, values[best]) != (6, 183):
                raise ValueError("Board supervisor expected class/score must be reviewed")
            expected = values
        else:
            image[base:base+count] = values
    # Ensure the checked software scales belong to the current hardware shift ROM.
    shift_rom = root / "rtl/datapath/kws_pot_shift_rom.sv"
    rom_records = [s for s in manifest["sources"] if Path(s["path"]).name == shift_rom.name]
    if len(rom_records) != 1 or sha(shift_rom.read_bytes()) != rom_records[0]["sha256"]:
        raise ValueError("PoT shift ROM changed; regenerate/validate activation vectors first")
    sources = subprocess.check_output(["make", "--no-print-directory", "-s", "print-kws-board-sources"], cwd=root, text=True).splitlines()
    if not sources or any(not (root / p).is_file() for p in sources):
        raise ValueError("Missing source in board source list")
    report = {"sample": 6988, "checkpoint_sha256": CHECKPOINT, "useful_bytes": 15628,
              "rom_bytes": 16384, "layout": inputs, "expected_fc2": expected,
              "expected_class": 6, "expected_score": 183,
              "source_files": [{"path": p, "sha256": sha((root/p).read_bytes())} for p in sources]}
    text = "".join(f"{v:02x}\n" for v in image)
    report["rom_sha256"] = sha(text.encode())
    # All checks above precede any writes. Generated folder is disposable, not RTL.
    output.mkdir(parents=True, exist_ok=True)
    (output / "kws_demo.mem").write_text(text)
    (output / "sources.txt").write_text("\n".join(sources) + "\n")
    (output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Prepared board ROM: {output}; useful=15628 padded=16384 class=6 score=183")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vectors", type=Path, default=root/"build/activation_path_vectors")
    parser.add_argument("--output", type=Path, default=root/"build/kws_board_vectors")
    args = parser.parse_args()
    pack(args.vectors, args.output, root)
