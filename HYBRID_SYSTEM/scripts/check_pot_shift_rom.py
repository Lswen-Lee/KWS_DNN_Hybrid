"""Compare every RTL ROM entry with independently reconstructed software metadata.

Run export_pot_requant_vectors.py first. This is a model-constant check, not STA.
"""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "build/requantizer_pot/software_vectors.json").read_text())
rtl = (root / "rtl/datapath/kws_pot_shift_rom.sv").read_text()
assert manifest["checkpoint_sha256"] in rtl
assert manifest["zero_point"] == 128
pairs = re.findall(r"8'd(\d+): shift_amount=5'd(\d+);", rtl)
actual = {int(address): int(value) for address, value in pairs}
assert len(actual) == len(pairs), "duplicate ROM address"
expected = {}
for layer_id, layer in enumerate(manifest["layers"]):
    assert layer["layer"] == ("conv1", "conv2", "conv3", "fc1", "fc2")[layer_id]
    expected.update({layer_id * 32 + c: k for c, k in enumerate(layer["shift_by_channel"])})
assert actual == expected, (actual, expected)
print(f"PASS PoT ROM: all {len(actual)} entries match checkpoint/export scales")
