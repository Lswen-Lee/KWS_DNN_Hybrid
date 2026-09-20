#!/usr/bin/env python3
"""Exhaustively check the RTL post-process arithmetic against one KWS export."""

from pathlib import Path

import numpy as np


KWS_ROOT = Path(__file__).resolve().parents[3]
ACTIVATION_ROOT = KWS_ROOT / "layer_activation_uint8"
WEIGHT_ROOT = KWS_ROOT / "layer_weights_int8"
ZERO_POINT = 127
Q31_HALF = 1 << 30
Q31_ONE = 1 << 31


def read_metadata(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


def read_activation(layer: str, shape: tuple[int, ...]) -> np.ndarray:
    values = np.loadtxt(
        ACTIVATION_ROOT / layer / "activation_uint8.txt", dtype=np.int64
    )
    return values.reshape(shape)


def requantize_q31(accumulator: np.ndarray, multiplier: int) -> np.ndarray:
    product = accumulator.astype(np.int64) * np.int64(multiplier)
    magnitude = np.abs(product)
    rounded = (magnitude + Q31_HALF) // Q31_ONE
    scaled = np.where(product < 0, -rounded, rounded)
    return np.clip(scaled + ZERO_POINT, 0, 255).astype(np.int64)


def verify_conv(
    layer: str,
    input_layer: str,
    input_shape: tuple[int, int, int, int],
    weight_shape: tuple[int, int, int, int],
    output_shape: tuple[int, int, int, int],
) -> int:
    activation = read_activation(input_layer, input_shape)
    expected = read_activation(layer, output_shape)
    weights = np.loadtxt(
        WEIGHT_ROOT / layer / "weights_int8.txt", dtype=np.int64
    ).reshape(weight_shape)
    scales = np.loadtxt(WEIGHT_ROOT / layer / "weight_scales.txt")
    metadata = read_metadata(WEIGHT_ROOT / layer / "metadata.txt")
    input_scale = float(metadata["input_activation_scale"])
    output_scale = float(metadata["output_activation_scale"])

    actual = np.zeros(output_shape, dtype=np.int64)
    for output_channel in range(output_shape[1]):
        multiplier = round(
            input_scale * float(scales[output_channel])
            / output_scale * Q31_ONE
        )
        for output_y in range(output_shape[2]):
            for output_x in range(output_shape[3]):
                patch = activation[
                    0,
                    :,
                    output_y : output_y + 3,
                    output_x : output_x + 3,
                ]
                accumulator = np.sum(
                    (patch - ZERO_POINT) * weights[output_channel],
                    dtype=np.int64,
                )
                actual[0, output_channel, output_y, output_x] = (
                    requantize_q31(np.asarray(accumulator), multiplier)
                )

    if not np.array_equal(actual, expected):
        mismatch = np.argwhere(actual != expected)[0]
        index = tuple(int(value) for value in mismatch)
        raise AssertionError(
            f"{layer} mismatch at {index}: actual={actual[index]}, "
            f"expected={expected[index]}"
        )
    print(f"PASS {layer:5s}: {actual.size:5d} requantized outputs")
    return int(actual.size)


def verify_fc(
    layer: str,
    input_layer: str,
    input_size: int,
    output_size: int,
) -> int:
    activation = read_activation(input_layer, (input_size,))
    expected = read_activation(layer, (output_size,))
    weights = np.loadtxt(
        WEIGHT_ROOT / layer / "weights_int8.txt", dtype=np.int64
    ).reshape(output_size, input_size)
    scales = np.loadtxt(WEIGHT_ROOT / layer / "weight_scales.txt")
    metadata = read_metadata(WEIGHT_ROOT / layer / "metadata.txt")
    input_scale = float(metadata["input_activation_scale"])
    output_scale = float(metadata["output_activation_scale"])

    actual = np.zeros(output_size, dtype=np.int64)
    for output_feature in range(output_size):
        accumulator = np.sum(
            (activation - ZERO_POINT) * weights[output_feature], dtype=np.int64
        )
        multiplier = round(
            input_scale * float(scales[output_feature])
            / output_scale * Q31_ONE
        )
        actual[output_feature] = requantize_q31(
            np.asarray(accumulator), multiplier
        )

    if not np.array_equal(actual, expected):
        mismatch = int(np.argwhere(actual != expected)[0, 0])
        raise AssertionError(
            f"{layer} mismatch at {mismatch}: actual={actual[mismatch]}, "
            f"expected={expected[mismatch]}"
        )
    print(f"PASS {layer:5s}: {actual.size:5d} requantized outputs")
    return int(actual.size)


def maxpool2x2(values: np.ndarray) -> np.ndarray:
    _, channels, height, width = values.shape
    output = np.empty((1, channels, height // 2, width // 2), dtype=np.int64)
    for channel in range(channels):
        for output_y in range(height // 2):
            for output_x in range(width // 2):
                window = values[
                    0,
                    channel,
                    output_y * 2 : output_y * 2 + 2,
                    output_x * 2 : output_x * 2 + 2,
                ]
                output[0, channel, output_y, output_x] = np.max(window)
    return output


def verify_relu_and_pool() -> int:
    comparisons = 0
    relu_specs = [
        ("conv1", "relu1", (1, 12, 30, 61)),
        ("conv2", "relu2", (1, 12, 13, 28)),
        ("conv3", "relu3", (1, 12, 4, 12)),
        ("fc1", "relu4", (1, 32)),
    ]
    for source, destination, shape in relu_specs:
        source_values = read_activation(source, shape)
        expected = read_activation(destination, shape)
        actual = np.maximum(source_values, ZERO_POINT)
        if not np.array_equal(actual, expected):
            raise AssertionError(f"{destination} does not equal max(input, 127)")
        comparisons += int(actual.size)
        print(f"PASS {destination:5s}: {actual.size:5d} ReLU outputs")

    pool_specs = [
        ("quant_input", "pool1", (1, 1, 64, 126), (1, 1, 32, 63)),
        ("relu1", "pool2", (1, 12, 30, 61), (1, 12, 15, 30)),
        ("relu2", "pool3", (1, 12, 13, 28), (1, 12, 6, 14)),
        ("relu3", "pool4", (1, 12, 4, 12), (1, 12, 2, 6)),
    ]
    for source, destination, input_shape, output_shape in pool_specs:
        source_values = read_activation(source, input_shape)
        expected = read_activation(destination, output_shape)
        actual = maxpool2x2(source_values)
        if not np.array_equal(actual, expected):
            raise AssertionError(f"{destination} max-pool mismatch")
        comparisons += int(actual.size)
        print(f"PASS {destination:5s}: {actual.size:5d} max-pool outputs")
    return comparisons


def main() -> None:
    total = 0
    total += verify_conv(
        "conv1", "pool1", (1, 1, 32, 63), (12, 1, 3, 3), (1, 12, 30, 61)
    )
    total += verify_conv(
        "conv2", "pool2", (1, 12, 15, 30), (12, 12, 3, 3), (1, 12, 13, 28)
    )
    total += verify_conv(
        "conv3", "pool3", (1, 12, 6, 14), (12, 12, 3, 3), (1, 12, 4, 12)
    )
    total += verify_fc("fc1", "flatten", 144, 32)
    total += verify_fc("fc2", "relu4", 32, 8)
    total += verify_relu_and_pool()

    fc2 = read_activation("fc2", (8,))
    prediction = int(np.argmax(fc2))
    if prediction != 1:
        raise AssertionError(f"FC2 argmax expected class 1, got {prediction}")
    print(f"PASS argmax: class={prediction}, value={int(fc2[prediction])}")
    print(f"ALL SOFTWARE-GOLDEN CHECKS PASSED ({total} compared values)")


if __name__ == "__main__":
    main()
