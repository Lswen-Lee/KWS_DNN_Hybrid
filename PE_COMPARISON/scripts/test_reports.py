import unittest
from summarize_reports import parse_util, parse_timing
class Reports(unittest.TestCase):
    def test_util(self):
        data=parse_util("| Slice LUTs* | 1,234 | 0 | 53200 | 2.32 |\n"
                        "| Slice Registers | 384 | 0 | 106400 | 0.36 |\n"
                        "| Block RAM Tile | 0.5 | 0 | 140 | 0.3 |\n"
                        "| DSPs | 12 | 0 | 220 | 5 |")
        self.assertEqual(data, {"LUT":1234,"FF":384,"BRAM_tiles":0.5,"DSP":12})
    def test_timing(self):
        data=parse_timing("WNS(ns) TNS(ns) TNS Failing Endpoints TNS Total Endpoints WHS(ns) THS(ns)\n"
                          "-----\n-0.12 -2.3 4 100 0.03 0.0 0 100\n")
        self.assertEqual(data["WNS_ns"],-0.12)
        self.assertEqual(data["hold_failing_endpoints"],0)
    def test_missing(self):
        self.assertEqual(parse_util(""),{})
        self.assertEqual(parse_timing("not routed"),{})
    def test_unrelated(self):
        self.assertEqual(parse_util("| LUT as Memory | 3 | 0 | 10 |"),{})
    def test_tcl_and_xdc_syntax(self):
        # Tcl parser only: no claims about Vivado command/property validity.
        import ctypes
        import ctypes.util
        from pathlib import Path
        library=ctypes.util.find_library("tcl8.6")
        if library is None:
            self.skipTest("Tcl library unavailable; syntax completeness not checked")
        interp=ctypes.CDLL(library)
        interp.Tcl_CommandComplete.argtypes=[ctypes.c_char_p]
        interp.Tcl_CommandComplete.restype=ctypes.c_int
        root=Path(__file__).resolve().parents[1]
        for path in list((root/"vivado").glob("*.tcl"))+list((root/"constraints").glob("*.xdc")):
            self.assertEqual(interp.Tcl_CommandComplete(path.read_bytes()),1,str(path))

    def test_summary_cli(self):
        import subprocess
        import sys
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            a=root/"pe9"; b=root/"pe8"
            a.mkdir(); b.mkdir()
            (a/"utilization.rpt").write_text("| Slice LUTs | 40 | 0 | 53200 |\n")
            (b/"utilization.rpt").write_text("| Slice LUTs | 30 | 0 | 53200 |\n")
            script=Path(__file__).with_name("summarize_reports.py")
            result=subprocess.run([sys.executable,str(script),str(a),str(b),"--output",str(root/"out")],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            output=(root/"out"/"comparison.csv").read_text()
            self.assertIn("LUT,40,30,-10",output)
            self.assertIn("WNS_ns,NOT_AVAILABLE,NOT_AVAILABLE,NOT_AVAILABLE",output)
