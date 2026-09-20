# PE Core Verification Plan

## 1. Golden equation

Every test compares RTL with the signed integer reference:

```text
reference[lane] = sum_k ((activation_u8[k] - 127) * weight_i8[lane][k])
```

Weights are decoded from 8-bit two's-complement.  Reference accumulation uses
at least signed 64-bit in the testbench or Python and is checked against the
signed INT32 RTL result.

## 2. Unit-test order

```text
1. tb_activation_center_127
2. tb_pe_multiplier_s9xs8
3. tb_pe_accumulator_s32
4. tb_pe_mac_lane
5. tb_pe_array_12
6. tb_pe_core_controller
7. tb_pe_core_12
8. tb_pe_kws_layers
```

Current implementation status:

```text
[PASS] tb_activation_center_127: seven named boundary cases and all 256 codes
[PASS] tb_pe_multiplier_s9xs8: twelve named cases and all 65,536 legal combinations
[PASS] tb_pe_accumulator_s32: reset, clear priority, enable/hold, signed boundaries and K=144
[PASS] tb_pe_mac_lane: signed MAC, clear/enable/reset, boundaries, K=9 and K=32
[TODO] tb_pe_array_12
[TODO] tb_pe_core_controller
[TODO] tb_pe_core_12
[TODO] tb_pe_kws_layers
```

Required checks:

| Test | Required coverage |
|---|---|
| Centering | UINT8 codes 0, 1, 126, 127, 128, 254 and 255. |
| Multiplier | Zero, both signs and extrema `-127`, `128`, `-128`, `127`. |
| Accumulator | Clear, enable, hold, alternating signs and long accumulation. |
| MAC lane | Back-to-back products and disabled-lane hold behavior. |
| Array | Twelve independent weights, broadcast activation and every mask bit. |
| Controller | K=1, 9, 32, 144, stalls, zero-length error and result backpressure. |
| Core | Accepted-beat counting, final pipeline drain and stable result output. |

## 3. KWS artifact tests

Use only:

```text
/home/LAB505/projects/KWS/layer_activation_uint8
/home/LAB505/projects/KWS/layer_weights_int8
```

Layer-shaped tests are performed in this order:

1. Conv1: one real 3-by-3 patch, K=9, twelve active lanes.
2. FC2: one real 32-element vector, K=32, eight active lanes.
3. FC1: one real 144-element vector in 12/12/8 output batches.

The first comparison stops at raw signed INT32 accumulation.  Requantized
UINT8 comparison belongs to HYBRID_SYSTEM because PE_CHIP intentionally does
not contain scale, rounding, output zero-point, saturation or ReLU.

## 4. Handshake assertions

The testbench must confirm:

- Inputs change the computation only on `sample_valid && sample_ready`.
- Activation and the twelve weights are accepted as one coherent beat.
- Exactly K accepted beats contribute to one result.
- The final beat is included before `result_valid` rises.
- `result_vector_s32` remains unchanged while `result_valid=1` and
  `result_ready=0`.
- Masked lanes remain zero after clear and never accumulate.
- A new start is not accepted while busy.

## 5. Synthesis checks

The standalone Vivado run must report:

- the actual DSP48E1 count, expected to be twelve;
- LUT, FF and CARRY utilization;
- WNS/TNS at 125 MHz;
- the critical path and route-delay percentage;
- no inferred latch, unconstrained clock or multi-driven net.

Functional equivalence is required before comparing PE and DCIM performance.
