"""Reconstruct INT64 MACs from existing PoT exports; never run/retrain a model.

Golden output bytes come from the software export, NOT from an RTL replica.
Generated vectors/manifest go to build/, not Git. Requires numpy.
"""
import argparse
import ast
import json
from pathlib import Path

import numpy as np


def metadata(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)


def activation(root, layer):
    folder = root / layer
    meta = metadata(folder / "metadata.txt")
    values = np.loadtxt(folder / "activation_uint8.txt", dtype=np.int64)
    assert np.all((values >= 0) & (values <= 255)), layer
    return values.reshape(ast.literal_eval(meta["shape"])), meta


def main():
    kws = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weights", type=Path, default=kws / "layer_weights_int8_pot_ceil_zp128")
    parser.add_argument("--activations", type=Path, default=kws / "layer_activation_uint8_pot_ceil_zp128")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "build/requantizer_pot/software_vectors.txt")
    args = parser.parse_args()
    blocks, records = [], []
    checkpoint_hash = None
    dataset_index = None
    for layer, input_layer in [("conv1", "pool1"), ("conv2", "pool2"), ("conv3", "pool3"), ("fc1", "flatten"), ("fc2", "relu4")]:
        folder = args.weights / layer
        meta = metadata(folder / "metadata.txt")
        x, im = activation(args.activations, input_layer)
        y, om = activation(args.activations, layer)
        sha = meta["source_checkpoint_sha256"]
        if checkpoint_hash is None:
            checkpoint_hash = sha
            dataset_index = om["dataset_index"]
        assert sha == checkpoint_hash == im["source_checkpoint_sha256"] == om["source_checkpoint_sha256"]
        assert im["dataset_index"] == om["dataset_index"] == dataset_index
        assert meta["source_model_bias"].lower() == "false"
        assert meta["converted_bias_none_or_all_zero"].lower() == "true"
        assert np.all(np.loadtxt(folder / "weight_zero_points.txt") == 0)
        assert int(meta["input_activation_zero_point"]) == int(im["activation_zero_point"]) == 128
        assert int(meta["output_activation_zero_point"]) == int(om["activation_zero_point"]) == 128
        assert float(meta["input_activation_scale"]) == float(im["activation_scale"])
        assert float(meta["output_activation_scale"]) == float(om["activation_scale"])
        w = np.loadtxt(folder / "weights_int8.txt", dtype=np.int64).reshape(ast.literal_eval(meta["shape"]))
        assert np.all((w >= -128) & (w <= 127))
        x = x - 128
        if layer.startswith("conv"):
            windows = np.lib.stride_tricks.sliding_window_view(x, (3, 3), axis=(-2, -1))
            acc = np.einsum("bihwkl,oikl->bohw", windows, w, dtype=np.int64)
            broadcast_shape = (1, -1, 1, 1)
        else:
            acc = x.reshape(1, -1) @ w.T
            broadcast_shape = (1, -1)
        assert acc.shape == y.shape
        assert np.all((acc >= -(2**31)) & (acc <= 2**31 - 1))
        scales = np.atleast_1d(np.loadtxt(folder / "weight_scales.txt"))
        multiplier = float(meta["input_activation_scale"]) * scales / float(meta["output_activation_scale"])
        assert np.all(multiplier > 0)
        shift = np.rint(-np.log2(multiplier)).astype(np.int64)
        assert np.all((shift >= 0) & (shift <= 31)), "model requires unsupported left/large shift"
        assert np.array_equal(multiplier, np.exp2(-shift.astype(float))), "not exact PoT"
        k = np.broadcast_to(shift.reshape(broadcast_shape), acc.shape)
        denominator = np.left_shift(np.int64(1), k)
        # Independent sign/magnitude integer nearest-even reference.
        magnitude = np.abs(acc)
        q, remainder = magnitude // denominator, magnitude % denominator
        q += ((2 * remainder > denominator) | ((2 * remainder == denominator) & (q % 2 == 1)))
        predicted = np.clip(np.sign(acc) * q + 128, 0, 255)
        mismatches = int(np.count_nonzero(predicted != y))
        assert mismatches == 0, (layer, mismatches)
        blocks.append(np.column_stack((acc.ravel(), k.ravel(), y.ravel())))
        records.append({"layer": layer, "input_layer": input_layer, "count": int(y.size),
                        "shift_by_channel": shift.tolist(), "mismatches": mismatches})
        print(f"PASS {layer}: {y.size} software bytes; k={sorted(set(shift.tolist()))}")
    vectors = np.concatenate(blocks)
    assert len(vectors) == 26944
    args.output.parent.mkdir(parents=True, exist_ok=True)
    np.savetxt(args.output, vectors, fmt="%d")
    args.output.with_suffix(".json").write_text(json.dumps({
        "scope": "per-layer exported-input comparison, not end-to-end RTL inference",
        "checkpoint_sha256": checkpoint_hash, "dataset_index": dataset_index,
        "weights": str(args.weights), "activations": str(args.activations),
        "rounding": "nearest-even", "zero_point": 128, "layers": records,
        "total_vectors": len(vectors)}, indent=2) + "\n")
    print(f"Wrote {len(vectors)} vectors to {args.output}")


if __name__ == "__main__":
    main()
