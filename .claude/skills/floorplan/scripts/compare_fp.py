#!/usr/bin/env python3
"""Compare FP probe runs of floorplan candidates and recommend one.

    compare_fp.py <FP run dir> [<FP run dir> ...] [--inputs fp_inputs.json] [-o out.json]

Per run: die area (DEF), probe.rpt (total routing usage, total overflow, per-
layer usage, placement overflow, wirelength), and — with --inputs — the
fp_check.py verdict. Recommendation: the smallest die whose probe overflow is
0 and whose rules pass; if none has 0 overflow, the one with the least
overflow per um2 (and say the floorplan needs to grow).
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def probe(run):
    f = os.path.join(run, 'work', 'FP', 'probe1', 'reports', 'probe.rpt')
    out = {'probe': None}
    if not os.path.isfile(f):
        return out
    t = open(f).read()
    if 'disabled' in t:
        return out
    g = lambda pat, cast=float: (cast(m.group(1)) if (m := re.search(pat, t)) else None)
    out['probe'] = {'total_usage_pct': g(r'Total routing usage\s*:\s*([\d.]+)'),
                    'total_overflow': g(r'Total overflow\s*:\s*(\d+)', int),
                    'placement_overflow': g(r'Placement overflow\s*:\s*([\d.]+)'),
                    'wirelength_um': g(r'Estimated wirelength um\s*:\s*([\d.]+)'),
                    'runtime_s': g(r'Probe runtime s\s*:\s*(\d+)', int),
                    'layers': {m.group(1): float(m.group(2)) for m in re.finditer(r'Layer (\S+)\s*:.*?usage\s+([\d.]+) %', t)}}
    return out


def die(run):
    for f in glob.glob(os.path.join(run, 'work', 'FP', '*', 'outputs', '*.def')):
        m = re.search(r'DIEAREA\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+\(\s*(-?\d+)\s+(-?\d+)', open(f, errors='replace').read(4_000_000))
        if m:
            x0, y0, x1, y1 = (int(v) / 1000 for v in m.groups())
            return [x0, y0, x1, y1]
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('runs', nargs='+')
    ap.add_argument('--inputs')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    rows = []
    for r in a.runs:
        r = os.path.abspath(r)
        row = {'run': os.path.basename(r), 'path': r, 'die': die(r), **probe(r)}
        row['die_area_um2'] = round((row['die'][2] - row['die'][0]) * (row['die'][3] - row['die'][1]), 1) if row['die'] else None
        if a.inputs:
            p = subprocess.run([sys.executable, os.path.join(HERE, 'fp_check.py'), r, '--inputs', a.inputs],
                               capture_output=True, text=True)
            row['rules'] = 'PASS' if p.returncode == 0 else 'FAIL'
            row['rule_violations'] = json.loads(p.stdout).get('violations', []) if p.stdout.strip().startswith('{') else []
        rows.append(row)
    ok = [x for x in rows if x['probe'] and x['probe']['total_overflow'] == 0 and x.get('rules', 'PASS') == 'PASS' and x['die_area_um2']]
    if ok:
        best = min(ok, key=lambda x: x['die_area_um2'])
        why = 'smallest die with 0 global-route overflow and all floorplan rules passing'
    else:
        cand = [x for x in rows if x['probe'] and x['die_area_um2']]
        best = min(cand, key=lambda x: x['probe']['total_overflow'] / x['die_area_um2']) if cand else None
        why = 'no candidate has 0 overflow — grow the floorplan (least overflow per um2 shown)' if best else 'no probe results'
    doc = {'runs': rows, 'recommended': best['run'] if best else None, 'why': why}
    print(f"{'run':<34} {'die um':>20} {'area um2':>12} {'usage%':>7} {'overflow':>9} {'rules':>6}", file=sys.stderr)
    for x in rows:
        p = x['probe'] or {}
        d = x['die'] or [0, 0, 0, 0]
        print(f"{x['run']:<34} {d[2]:>9g}x{d[3]:<10g} {x['die_area_um2'] or 0:>12} {p.get('total_usage_pct', '-'):>7} "
              f"{p.get('total_overflow', '-'):>9} {x.get('rules', '-'):>6}", file=sys.stderr)
    print(f"recommended: {doc['recommended']} — {why}", file=sys.stderr)
    s = json.dumps(doc, indent=1)
    if a.output:
        open(a.output, 'w').write(s + '\n')
    else:
        print(s)


if __name__ == '__main__':
    main()
