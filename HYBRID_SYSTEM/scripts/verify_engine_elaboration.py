"""Inspect elaborated instance trees; this is not a synthesis/PPA estimate."""
import sys
import xml.etree.ElementTree as ET


def check(path, pe8, pipelined=False, zp=127):
    root = ET.parse(path).getroot()
    names = {m.get("name"): m.get("origName", m.get("name"))
             for m in root.findall(".//netlist/module")}
    counts = {}
    for cell in root.findall(".//cells//cell"):
        name = names.get(cell.get("submodname"), cell.get("submodname"))
        counts[name] = counts.get(name, 0) + 1
    need_sum = pe8 and zp == 127
    correction_pipeline = need_sum and pipelined
    expected = {
        "pe8_array_12": int(pe8), "pe_array_12": int(not pe8),
        "pe_channel_sum_memory": int(need_sum),
        "pe_weight_sum_builder": int(need_sum),
        "pe8_result_correction": int(need_sum),
        "pe_weight_buffer_12": 1, "pe_group_controller": 1,
        "pe_result_controller": int(not correction_pipeline),
        "pe8_result_controller_pipeline": int(correction_pipeline),
    }
    for name, count in expected.items():
        if counts.get(name, 0) != count:
            raise SystemExit(f"FAIL {path}: {name} count={counts.get(name, 0)}, expected={count}")
    print(f"PASS engine elaboration zp={zp} PE8_MODE={int(pe8)} RESULT_PIPELINED={int(pipelined)}: one array; sum path={need_sum}")


if __name__ == "__main__":
    if len(sys.argv) not in (4,5):
        raise SystemExit("Usage: verify_engine_elaboration.py pe8.xml pe9.xml pe8_pipe.xml [127|128]")
    zp = int(sys.argv[4]) if len(sys.argv)==5 else 127
    check(sys.argv[1], True, zp=zp)
    check(sys.argv[2], False, zp=zp)
    check(sys.argv[3], True, True, zp=zp)
