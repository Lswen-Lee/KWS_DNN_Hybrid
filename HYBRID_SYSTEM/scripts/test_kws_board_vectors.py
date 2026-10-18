"""Board packer tests. Requires generated activation vectors, never edits originals."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from generate_kws_board_vectors import pack, LAYOUT

ROOT = Path(__file__).resolve().parents[1]


class BoardVectorsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.vectors = self.base / "vectors"
        shutil.copytree(ROOT / "build/activation_path_vectors", self.vectors)
        self.output = self.base / "output"

    def tearDown(self):
        self.temp.cleanup()

    def test_layout(self):
        pack(self.vectors, self.output, ROOT)
        result = (self.output / "kws_demo.mem").read_text().split()
        self.assertEqual(len(result), 16384)
        for name, base, count in LAYOUT:
            self.assertEqual(result[base:base+count], (self.vectors/(name+".mem")).read_text().split())
        self.assertTrue(all(b == "00" for b in result[15628:]))
        manifest = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual((manifest["expected_class"], manifest["expected_score"]), (6, 183))

    def test_corrupt_byte(self):
        p = self.vectors / "conv2_weights.mem"
        original = p.read_text()
        p.write_text(("01" if original[:2] != "01" else "00") + original[2:])
        with self.assertRaisesRegex(ValueError, "Manifest mismatch"):
            pack(self.vectors, self.output, ROOT)
        self.assertFalse(self.output.exists())

    def test_wrong_sample(self):
        p = self.vectors / "manifest.json"
        manifest = json.loads(p.read_text()); manifest["dataset_index"] = "0"
        p.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "fixed to validated"):
            pack(self.vectors, self.output, ROOT)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
