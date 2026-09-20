"""Check generate selection in Verilator XML (not a Vivado area report)."""
import sys
import xml.etree.ElementTree as ET


def check(path, expected):
    root = ET.parse(path).getroot()
    instances = [
        cell for cell in root.findall(".//cells//cell")
        if cell.get("submodname") == "pe8_result_correction"
    ]
    if len(instances) != expected:
        raise SystemExit(f"FAIL {path}: correction instances={len(instances)}, expected={expected}")
    print(f"PASS elaboration: {path}: correction instances={len(instances)}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: verify_result_elaboration.py pe8.xml pe9.xml")
    check(sys.argv[1], 1)
    check(sys.argv[2], 0)
