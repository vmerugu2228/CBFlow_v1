#!/usr/bin/env python3
"""Before / after DRC comparison of two drc_summary.py JSONs — the drc-fix gate.

    compare_drc.py <before.json> <after.json> [-o out.json]

Gated on the block's own geometry (totals.by_rule): ACCEPT when the total fell
(or is 0) and no rule got worse; REJECT when the total rose, any rule's count
rose, or a rule appears that was not there before. Violations inside child
blocks / macros are listed, not gated — the ECO cannot change them.
Exit 0 = ACCEPT, 2 = REJECT. (Timing and LVS are separate gates: timing-eco's
compare_qor.py and the PV run's LVS result.)
"""
import argparse
import json
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('before')
    ap.add_argument('after')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    with open(a.before) as f:
        b = json.load(f)
    with open(a.after) as f:
        n = json.load(f)
    br, nr = b['totals']['by_rule'], n['totals']['by_rule']
    rows, reasons = [], []
    for r in sorted(set(br) | set(nr)):
        x, y = br.get(r, 0), nr.get(r, 0)
        rows.append({'rule': r, 'before': x, 'after': y})
        if y > x:
            reasons.append(f'{r}: {x} -> {y}' + (' (new rule)' if x == 0 else ''))
    tb, tn = b['totals']['total'], n['totals']['total']
    if tn > tb:
        reasons.append(f'total {tb} -> {tn}')
    elif tn == tb and tn > 0:
        reasons.append(f'total unchanged ({tn})')
    # child-block violations: reported, not gated (an ECO cannot change them;
    # a difference means the child's library-tag view changed between streams)
    cb, cn = b['totals'].get('child_by_rule', {}), n['totals'].get('child_by_rule', {})
    child = [{'cell_rule': k, 'before': cb.get(k, 0), 'after': cn.get(k, 0)} for k in sorted(set(cb) | set(cn))]
    verdict = 'REJECT' if reasons else 'ACCEPT'
    doc = {'verdict': verdict, 'reasons': reasons, 'total': {'before': tb, 'after': tn}, 'rules': rows,
           'child_cells': child,
           'before': b['source'], 'after': n['source']}
    print(f'verdict: {verdict}   total {tb} -> {tn}', file=sys.stderr)
    for r in rows:
        print(f"  {r['rule']:<14} {r['before']:>6} -> {r['after']}", file=sys.stderr)
    for c in child:
        note = '' if c['before'] == c['after'] else '   (child view changed — fix in that child)'
        print(f"  child {c['cell_rule']:<16} {c['before']:>4} -> {c['after']}{note}", file=sys.stderr)
    for x in reasons:
        print(f'  reject: {x}', file=sys.stderr)
    out = json.dumps(doc, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(out + '\n')
    else:
        print(out)
    sys.exit(0 if verdict == 'ACCEPT' else 2)


if __name__ == '__main__':
    main()
