import tempfile
from pathlib import Path
import unittest
from summarize_pe_equivalent import compare


class EquivalentSummaryTest(unittest.TestCase):
    def test_table_and_rejection(self):
        with tempfile.TemporaryDirectory() as temp:
            paths = []
            for variant, lut in [('pe8', 1800), ('pe9', 2000)]:
                p = Path(temp) / variant
                p.mkdir()
                paths.append(p)
                (p / 'comparison_config.txt').write_text(
                    f'variant={variant}\nscope=test\nstage=post_route\n'
                    'part=xc7z020clg400-1\nperiod_ns=8.000\ntool=2023.2\n')
                (p / 'total_utilization.rpt').write_text(
                    f'| Design : {variant}_equivalent_top\n| Design State : Fully Routed\n'
                    f'| Slice LUTs | {lut} | 0 |\n| Slice Registers | 700 | 0 |\n| DSPs | 0 | 0 |\n')
            self.assertIn('10.00%', compare(*paths))
            p = paths[0] / 'total_utilization.rpt'
            p.write_text(p.read_text().replace('| DSPs | 0', '| DSPs | 12'))
            with self.assertRaises(ValueError):
                compare(*paths)


if __name__ == '__main__':
    unittest.main()
