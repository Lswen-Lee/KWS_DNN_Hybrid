"""Read-only checks of source exports plus mutations in isolated temp copies."""
import shutil
import tempfile
import unittest
from pathlib import Path

from generate_activation_path_vectors import binary_values, validate

ROOT = Path(__file__).resolve().parents[1]
KWS = ROOT.parent.parent


class VectorValidationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.activations = KWS / "layer_activation_uint8_pot_ceil_zp128"
        cls.weights = KWS / "layer_weights_int8_pot_ceil_zp128"
        cls.rom = ROOT / "rtl/datapath/kws_pot_shift_rom.sv"

    def test_source_exports(self):
        arrays, manifest = validate(self.activations, self.weights, self.rom)
        self.assertEqual(len(arrays), 24)
        for name, count in [("conv2",4368),("conv3",576)]:
            self.assertEqual(arrays[name+"_weights"].size,1296)
            self.assertEqual(arrays[name+"_acc"].size,count)
        self.assertEqual(arrays["conv1_weights"].size, 108)
        self.assertEqual(manifest["zero_point"], 128)

    def test_binary_rejection_and_signedness(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "bytes.txt"
            p.write_text("10000000\n11111111\n")
            self.assertEqual(binary_values(p, 2, signed=True).tolist(), [-128, -1])
            self.assertEqual(binary_values(p, 2).tolist(), [128, 255])
            for text in ["10000000\n", "10000000\n11111111\n00000000\n", "1000000x\n11111111\n", "100000000\n11111111\n"]:
                p.write_text(text)
                with self.assertRaises(ValueError):
                    binary_values(p, 2)

    def test_metadata_and_numeric_mismatches(self):
        with tempfile.TemporaryDirectory() as tmp:
            a, w = Path(tmp) / "a", Path(tmp) / "w"
            shutil.copytree(self.activations, a)
            shutil.copytree(self.weights, w)
            edits = [
                (a/"pool1/metadata.txt", "activation_zero_point=128", "activation_zero_point=127"),
                (a/"pool1/metadata.txt", "dataset_index=6988", "dataset_index=6989"),
                (a/"pool1/metadata.txt", "shape=(1, 1, 32, 63)", "shape=(1, 1, 63, 32)"),
                (w/"conv1/metadata.txt", "source_model_bias=false", "source_model_bias=true"),
                (w/"conv1/metadata.txt", "source_checkpoint_sha256=f", "source_checkpoint_sha256=0"),
                (w/"conv1/metadata.txt", "per_channel_axis=0", "per_channel_axis=1"),
                (w/"conv2/metadata.txt", "per_channel_axis=0", "per_channel_axis=1"),
                (w/"conv3/metadata.txt", "weight_dtype=signed_int8", "weight_dtype=unsigned_uint8"),
                (a/"conv2/metadata.txt", "activation_zero_point=128", "activation_zero_point=127"),
            ]
            for path, old, new in edits:
                original = path.read_text()
                self.assertIn(old, original)
                path.write_text(original.replace(old, new))
                with self.subTest(path=path, change=new), self.assertRaises(ValueError):
                    validate(a, w, self.rom)
                path.write_text(original)
            p = a/"relu1/activation_uint8_binary.txt"
            original = p.read_text()
            p.write_text(("1" if original[0] == "0" else "0")+original[1:])
            with self.assertRaisesRegex(ValueError, "binary/decimal"):
                validate(a, w, self.rom)
            p.write_text(original)
            p.unlink()
            with self.assertRaises(FileNotFoundError):
                validate(a, w, self.rom)


if __name__ == "__main__":
    unittest.main(verbosity=2)
