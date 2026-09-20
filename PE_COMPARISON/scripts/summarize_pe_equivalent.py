"""Read two explicit report directories; never substitute historical reports."""
import argparse
from pathlib import Path
import re


def load(folder, variant):
    folder = Path(folder)
    meta = dict(line.split('=', 1) for line in
                (folder / 'comparison_config.txt').read_text().splitlines() if '=' in line)
    if meta.get('variant') != variant:
        raise ValueError(f'{folder}: expected {variant}')
    report = (folder / 'total_utilization.rpt').read_text()
    if not re.search(rf'\|\s*Design\s*:\s*{variant}_equivalent_top\s*$', report, re.M):
        raise ValueError('Unexpected design in utilization report')
    state = re.search(r'\|\s*Design State\s*:\s*(.+)', report)
    meta['design_state'] = state.group(1).strip() if state else 'unknown'
    if meta.get('stage') == 'post_route' and meta['design_state'] != 'Fully Routed':
        raise ValueError('Post-route report is not Fully Routed')
    values = {}
    for label, key in [('Slice LUTs', 'LUT'), ('Slice Registers', 'FF'), ('DSPs', 'DSP')]:
        match = re.search(r'\|\s*' + label + r'\s*\|\s*([\d,]+)\s*\|', report)
        if not match:
            raise ValueError(f'Missing {label}')
        values[key] = int(match.group(1).replace(',', ''))
    if values['DSP'] != 0:
        raise ValueError('DSP is not zero; not a LUT/FF comparison')
    return meta, values


def compare(pe8_dir, pe9_dir):
    m8, v8 = load(pe8_dir, 'pe8')
    m9, v9 = load(pe9_dir, 'pe9')
    for field in ['scope', 'stage', 'period_ns', 'part', 'tool', 'design_state']:
        if not m8.get(field) or m8[field] != m9.get(field):
            raise ValueError(f'Comparison mismatch: {field}')
    rate = f"{(v9['LUT']-v8['LUT'])/v9['LUT']*100:.2f}%" if v9['LUT'] else 'N/A'
    return '\n'.join([
        '# PE8 / PE9 LUT–FF comparison', '',
        f"Stage: {m8['stage']}; part: {m8['part']}; clock: {m8['period_ns']} ns", '',
        '| Resource | PE8 (includes sum-W storage/correction) | PE9 |',
        '|---|---:|---:|',
        f"| LUT | {v8['LUT']:,} | {v9['LUT']:,} |",
        f"| FF | {v8['FF']:,} | {v9['FF']:,} |", '',
        f'LUT saving = (LUT_PE9 - LUT_PE8) / LUT_PE9 × 100% = **{rate}**', '',
        f'PE8 source: {Path(pe8_dir).resolve()}',
        f'PE9 source: {Path(pe9_dir).resolve()}', '',
        'Area only. Review both timing/route reports, identical XDC/strategies, and OOC boundary limitations.',
        'Excludes sum-W builder, weight/feature RAM and layer scheduler. Not full backend area.',
    ])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('pe8_reports')
    parser.add_argument('pe9_reports')
    args = parser.parse_args()
    try:
        print(compare(args.pe8_reports, args.pe9_reports))
    except (ValueError, OSError) as exc:
        parser.exit(1, f'Cannot compare: {exc}\n')
