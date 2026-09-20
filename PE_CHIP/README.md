# PE_CHIP

`PE_CHIP`是目前KWS模型專用、可獨立驗證與合成的12-lane
output-stationary processing-element core。

固定數值格式：

```text
activation : QUInt8 stored code, centered by fixed zero-point 127
weight     : signed QInt8 two's-complement, zero-point 0
bias       : disabled/zero
product    : signed 17-bit
accumulator: signed INT32
```

核心公式：

```text
acc[lane] += (activation_uint8 - 127) * weight_int8[lane]
```

它負責共享activation centering、12組signed MAC、output-stationary
accumulation、lane mask、K次數控制及valid/ready握手。不負責feature-map
address、整層weight memory、pooling、ReLU、requantization或DCIM控制；這些
功能屬於`../HYBRID_SYSTEM`。

完整架構與驗證規格：

- [`docs/PE_CORE_ARCHITECTURE.md`](docs/PE_CORE_ARCHITECTURE.md)
- [`docs/PE_VERIFICATION_GUIDE.md`](docs/PE_VERIFICATION_GUIDE.md)

## Planned RTL

```text
rtl/
├── pe_pkg.sv
├── arithmetic/
│   ├── activation_center_127.sv
│   ├── pe_multiplier_s9xs8.sv
│   ├── pe_accumulator_s32.sv
│   └── pe_mac_lane.sv
├── array/
│   └── pe_array_12.sv
├── control/
│   └── pe_core_controller.sv
└── core/
    ├── pe_core_12.sv
    └── pe_standalone_top.sv
```

## Planned Testbenches

```text
tb/
├── arithmetic/
│   ├── tb_activation_center_127.sv
│   ├── tb_pe_multiplier_s9xs8.sv
│   ├── tb_pe_accumulator_s32.sv
│   └── tb_pe_mac_lane.sv
├── array/
│   └── tb_pe_array_12.sv
├── control/
│   └── tb_pe_core_controller.sv
├── core/
│   ├── tb_pe_core_12.sv
│   └── tb_pe_kws_layers.sv
└── data/
```

## Implemented RTL

目前已完成四個底層算術元件：

```text
rtl/arithmetic/activation_center_127.sv
tb/arithmetic/tb_activation_center_127.sv

rtl/arithmetic/pe_multiplier_s9xs8.sv
tb/arithmetic/tb_pe_multiplier_s9xs8.sv

rtl/arithmetic/pe_accumulator_s32.sv
tb/arithmetic/tb_pe_accumulator_s32.sv

rtl/arithmetic/pe_mac_lane.sv
tb/arithmetic/tb_pe_mac_lane.sv
```

第一個元件將UINT8 activation轉換為`activation_u8 - 127`的signed 9-bit值；
第二個元件將此signed 9-bit activation與signed INT8 weight相乘並保留完整
17-bit product；第三個元件將product做sign extension後累加為signed INT32，
並提供同步active-high reset、clear、enable與hold；第四個元件將Multiplier與
Accumulator組成一條完整的output-stationary MAC lane。執行方式：

```bash
make test-activation-center
make test-multiplier
make test-accumulator
make test-mac-lane
make test
```

其餘RTL會依架構文件由小到大逐一建立並保留每一層testbench。
