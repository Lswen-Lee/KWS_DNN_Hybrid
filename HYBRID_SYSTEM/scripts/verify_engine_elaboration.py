"""Inspect elaborated instance trees; this is not a synthesis/PPA estimate."""
import sys
import xml.etree.ElementTree as ET


def check(path, pe8, pipelined=False):
    root = ET.parse(path).getroot()
    names = {m.get("name"): m.get("origName", m.get("name"))
             for m in root.findall(".//netlist/module")}
    counts = {}
    for cell in root.findall(".//cells//cell"):
        name = names.get(cell.get("submodname"), cell.get("submodname"))
        counts[name] = counts.get(name, 0) + 1
    expected = {
        "pe8_array_12": int(pe8), "pe_array_12": int(not pe8),
        "pe_channel_sum_memory": int(pe8),
        "pe_weight_sum_builder": int(pe8),
        "pe8_result_correction": int(pe8),
        "pe_weight_buffer_12": 1, "pe_group_controller": 1,
        "pe_result_controller": int(not pipelined),
        "pe8_result_controller_pipeline": int(pipelined),
    }
    for name, count in expected.items():
        if counts.get(name, 0) != count:
            raise SystemExit(f"FAIL {path}: {name} count={counts.get(name, 0)}, expected={count}")
    print(f"PASS engine elaboration PE8_MODE={int(pe8)} RESULT_PIPELINED={int(pipelined)}: one array and one selected result controller")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: verify_engine_elaboration.py pe8.xml pe9.xml pe8_pipe.xml")
    check(sys.argv[1], True)
    check(sys.argv[2], False)
    check(sys.argv[3], True, True)
