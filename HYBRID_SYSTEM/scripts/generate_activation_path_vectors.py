"""Validate existing zp128 exports and stage S3 files for SV $readmemh.

No training, checkpoint execution or RTL-derived golden. Original software bytes
remain authoritative. Fixed model geometry is checked before generating files.
"""
import argparse
import ast
import hashlib
import json
import re
from pathlib import Path

import numpy as np

ACT_SHAPES = {
    "quant_input": (1, 1, 64, 126), "pool1": (1, 1, 32, 63),
    "conv1": (1, 12, 30, 61), "relu1": (1, 12, 30, 61), "pool2": (1, 12, 15, 30),
    "flatten": (1, 144), "fc1": (1, 32), "relu4": (1, 32), "fc2": (1, 8),
}
WEIGHT_SHAPES = {"conv1": (12, 1, 3, 3), "fc1": (32, 144), "fc2": (8, 32)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def metadata(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)


def binary_values(path, count, signed=False):
    tokens = path.read_text().split()
    require(len(tokens) == count, f"{path}: expected {count} values, got {len(tokens)}")
    require(all(re.fullmatch("[01]{8}", t) for t in tokens), f"{path}: invalid binary byte")
    values = np.array([int(t, 2) for t in tokens], dtype=np.int64)
    return np.where(values >= 128, values - 256, values) if signed else values


def maxpool(x):
    h, w = x.shape[-2:]
    return np.maximum.reduce([x[..., u:2*(h//2):2, v:2*(w//2):2]
                              for u in range(2) for v in range(2)])


def validate(activations, weights, rom):
    arrays, ameta, wmeta, sources, shifts = {}, {}, {}, [], {}
    sha = None
    sample = None
    for name, shape in ACT_SHAPES.items():
        folder = activations / name
        meta = metadata(folder / "metadata.txt")
        require(ast.literal_eval(meta["shape"]) == shape, f"{name}: shape")
        require(int(meta["element_count"]) == int(np.prod(shape)), f"{name}: metadata count")
        require(meta["stored_dtype"] == "unsigned_uint8", f"{name}: dtype")
        require(int(meta["activation_zero_point"]) == 128, f"{name}: zero point")
        require(meta["flatten_order"] == "C row-major; last index changes fastest", f"{name}: order")
        require(float(meta["activation_scale"]) > 0, f"{name}: scale")
        sha = sha or meta["source_checkpoint_sha256"]
        sample = sample or meta["dataset_index"]
        require(meta["source_checkpoint_sha256"] == sha, f"{name}: checkpoint mismatch")
        require(meta["dataset_index"] == sample, f"{name}: sample mismatch")
        binary = folder / "activation_uint8_binary.txt"
        decimal = folder / "activation_uint8.txt"
        values = binary_values(binary, int(np.prod(shape)))
        require(np.array_equal(values, np.loadtxt(decimal, dtype=np.int64).reshape(-1)), f"{name}: binary/decimal mismatch")
        arrays[name] = values.reshape(shape)
        ameta[name] = meta
        sources.extend([folder / "metadata.txt", binary, decimal])
    for before, after in [("quant_input", "pool1"), ("relu1", "pool2")]:
        require(ameta[before]["activation_scale"] == ameta[after]["activation_scale"], f"{after}: pool scale")
        require(np.array_equal(maxpool(arrays[before]), arrays[after]), f"{after}: software pool mismatch")
    for before, after in [("conv1", "relu1"), ("fc1", "relu4")]:
        require(ameta[before]["activation_scale"] == ameta[after]["activation_scale"], f"{after}: relu scale")
        require(np.array_equal(np.maximum(arrays[before], 128), arrays[after]), f"{after}: software ReLU mismatch")
    rom_text = rom.read_text()
    require(sha in rom_text, "PoT ROM checkpoint mismatch")
    pairs = re.findall(r"8'd(\d+): shift_amount=5'd(\d+);", rom_text)
    entries = {int(a): int(k) for a, k in pairs}
    require(len(entries) == len(pairs), "Duplicate PoT ROM address")
    for name, input_name, layer_id in [("conv1", "pool1", 0), ("fc1", "flatten", 3), ("fc2", "relu4", 4)]:
        folder = weights / name
        meta = metadata(folder / "metadata.txt")
        shape = WEIGHT_SHAPES[name]
        require(ast.literal_eval(meta["shape"]) == shape, f"{name}: weight shape")
        require(int(meta["element_count"]) == int(np.prod(shape)), f"{name}: weight count")
        require(meta["weight_dtype"] == "signed_int8" and meta["binary_encoding"] == "8-bit_two_complement", f"{name}: weight encoding")
        require(meta["flatten_order"] == "C row-major; last index changes fastest", f"{name}: weight order")
        layout = "[out_channel, in_channel, kernel_y, kernel_x]" if name == "conv1" else "[out_feature, in_feature]"
        require(meta["weight_layout"] == layout and int(meta["per_channel_axis"]) == 0, f"{name}: weight layout")
        require(meta["source_checkpoint_sha256"] == sha, f"{name}: weight checkpoint")
        require(meta["source_model_bias"].lower() == "false" and meta["converted_bias_none_or_all_zero"].lower() == "true", f"{name}: bias")
        require(np.all(np.loadtxt(folder / "weight_zero_points.txt") == 0), f"{name}: weight zp")
        for prefix, a_name in [("input", input_name), ("output", name)]:
            require(int(meta[f"{prefix}_activation_zero_point"]) == 128, f"{name}: activation zp")
            require(float(meta[f"{prefix}_activation_scale"]) == float(ameta[a_name]["activation_scale"]), f"{name}: scale mismatch")
        binary = folder / "weights_int8_binary.txt"
        decimal = folder / "weights_int8.txt"
        w = binary_values(binary, int(np.prod(shape)), signed=True)
        require(np.array_equal(w, np.loadtxt(decimal, dtype=np.int64).reshape(-1)), f"{name}: weight binary/decimal mismatch")
        w = w.reshape(shape)
        x = arrays[input_name] - 128
        if name == "conv1":
            windows = np.lib.stride_tricks.sliding_window_view(x, (3, 3), axis=(-2, -1))
            acc = np.einsum("bihwuv,oiuv->bohw", windows, w, dtype=np.int64)
            broadcast = (1, -1, 1, 1)
        else:
            acc = x @ w.T
            broadcast = (1, -1)
        require(np.all((acc >= -(2**31)) & (acc < 2**31)), f"{name}: INT32 overflow")
        scales = np.atleast_1d(np.loadtxt(folder / "weight_scales.txt"))
        require(scales.size == shape[0] and np.all(scales > 0), f"{name}: weight scales")
        multiplier = float(meta["input_activation_scale"]) * scales / float(meta["output_activation_scale"])
        ks = np.rint(-np.log2(multiplier)).astype(np.int64)
        require(np.all((ks >= 0) & (ks <= 31)), f"{name}: unsupported shift")
        require(np.array_equal(multiplier, np.exp2(-ks.astype(float))), f"{name}: not exact PoT")
        require(all(entries.get(layer_id*32+c) == int(k) for c, k in enumerate(ks)), f"{name}: ROM shift mismatch")
        divisor = np.left_shift(np.int64(1), ks.reshape(broadcast))
        mag = np.abs(acc)
        q, remainder = mag // divisor, mag % divisor
        q += (2*remainder > divisor) | ((2*remainder == divisor) & (q%2 != 0))
        prediction = np.clip(np.sign(acc)*q+128, 0, 255)
        require(np.array_equal(prediction, arrays[name]), f"{name}: independent MAC/PoT differs from export")
        arrays[name+"_weights"] = w
        shifts[name] = ks.tolist()
        wmeta[name] = meta
        sources.extend([folder / n for n in ["metadata.txt", "weights_int8_binary.txt", "weights_int8.txt", "weight_scales.txt", "weight_zero_points.txt"]])
    manifest = {
        "scope": "S3 Conv1/Pool chain; FC checks use exported intermediate inputs, not full CNN",
        "checkpoint_sha256": sha, "dataset_index": sample,
        "zero_point": 128, "rounding": "nearest-even", "bias": False,
        "activation_order": "CHW, x fastest", "weight_order": "output channel, then k",
        "shift_by_channel": shifts,
        "memory_map": {"quant_input": [0,8064], "pool1": [8064,2016], "relu1": [10080,21960], "pool2": [0,5400], "flatten": [0,144], "relu4": [144,32], "fc2": [0,8]},
        "sources": [{"path": str(p.resolve()), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources+[rom]],
        "activations": ameta, "weights": wmeta,
    }
    return arrays, manifest


def main():
    root = Path(__file__).resolve().parents[1]
    kws = root.parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--activations", type=Path, default=kws / "layer_activation_uint8_pot_ceil_zp128")
    parser.add_argument("--weights", type=Path, default=kws / "layer_weights_int8_pot_ceil_zp128")
    parser.add_argument("--output", type=Path, default=root / "build/activation_path_vectors")
    args = parser.parse_args()
    arrays, manifest = validate(args.activations, args.weights, root / "rtl/datapath/kws_pot_shift_rom.sv")
    # Validate everything before updating any vectors. Golden bytes stay unchanged.
    args.output.mkdir(parents=True, exist_ok=True)
    manifest["generated_files"] = {}
    for name, values in arrays.items():
        output = args.output / (name+".mem")
        output.write_text("".join(f"{int(v)&255:02x}\n" for v in values.ravel()))
        manifest["generated_files"][output.name] = {"count": int(values.size), "shape": list(values.shape),
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest()}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    print(f"PASS S3 vectors: sample={manifest['dataset_index']}, {len(arrays)} files; software MAC/PoT/ReLU/Pool and ROM match")
    print(f"Output: {args.output.resolve()}")


if __name__ == "__main__":
    main()
