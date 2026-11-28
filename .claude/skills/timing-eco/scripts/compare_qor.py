#!/usr/bin/env python3
"""Before / after comparison of two timing_summary.py JSONs — the ECO acceptance gate.

    compare_qor.py <before.json> <after.json> [--tolerance NS] [-o out.json]

Per scenario (matched by name): setup / hold WNS, TNS, NVP and DRV counts,
before -> after. Verdict:
  REJECT  any scenario's setup or hold WNS or TNS got worse (beyond
          --tolerance), NVP rose, a DRV count rose, a scenario disappeared,
          or a path endpoint violates after that did not before
  ACCEPT  otherwise (improved or unchanged)
  ACCEPT_UNVERIFIED  no regression found, but the after JSON lists fewer
          violating paths than a scenario's NVP, so an endpoint that newly fails
          while another is fixed (same NVP) could hide — rebuild both JSONs with
          timing_summary.py --paths 0, or have a person review
Exit status 0 = ACCEPT, 2 = REJECT, 3 = ACCEPT_UNVERIFIED, so the skill can gate on it.
"""
import argparse
import json
import sys

METRICS = ('wns_setup', 'tns_setup', 'nvp_setup', 'wns_hold', 'tns_hold', 'nvp_hold')


def load(p):
    with open(p) as f:
        return json.load(f)


def violators(doc):
    return {(p['scenario'], p['check'], p.get('endpoint')) for p in doc['paths'] if p['slack'] < 0}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('before')
    ap.add_argument('after')
    ap.add_argument('--tolerance', type=float, default=0.005, help='ns of WNS/TNS noise ignored (default 0.005)')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    b, n = load(a.before), load(a.after)
    bs = {s['name']: s for s in b['scenarios']}
    ns = {s['name']: s for s in n['scenarios']}
    rows, reasons = [], []
    for name in sorted(set(bs) | set(ns)):
        if name not in ns:
            reasons.append(f'{name}: scenario missing after the ECO')
            continue
        if name not in bs:
            continue
        r = {'scenario': name}
        for m in METRICS:
            x, y = bs[name].get(m), ns[name].get(m)
            r[m] = {'before': x, 'after': y}
            if x is None or y is None:
                continue
            worse = (y > x) if m.startswith('nvp') else (y < x - a.tolerance)
            if worse:
                reasons.append(f'{name}: {m} {x} -> {y}')
        for k in sorted(set(bs[name].get('drv', {})) | set(ns[name].get('drv', {}))):
            x, y = bs[name].get('drv', {}).get(k, 0), ns[name].get('drv', {}).get(k, 0)
            r[f'drv_{k}'] = {'before': x, 'after': y}
            if y > x:
                reasons.append(f'{name}: {k} violations {x} -> {y}')
        rows.append(r)
    new = sorted(violators(n) - violators(b))
    for sc, ck, ep in new:
        reasons.append(f'{sc}: new {ck} violation at {ep}')
    # the endpoint check only sees the listed paths: say so when the lists are cut
    incomplete = []
    for doc_, tag in ((b, 'before'), (n, 'after')):
        listed = {}
        for p in doc_['paths']:
            if p['slack'] < 0:
                listed[(p['scenario'], p['check'])] = listed.get((p['scenario'], p['check']), 0) + 1
        for sc in doc_['scenarios']:
            for ck in ('setup', 'hold'):
                nvp = sc.get(f'nvp_{ck}') or 0
                if nvp > listed.get((sc['name'], ck), 0):
                    incomplete.append(f'{tag} {sc["name"]} {ck}: {listed.get((sc["name"], ck), 0)} of {nvp} violating paths listed')
    verdict = 'REJECT' if reasons else ('ACCEPT_UNVERIFIED' if incomplete else 'ACCEPT')
    doc = {'verdict': verdict, 'reasons': reasons, 'incomplete': incomplete, 'scenarios': rows,
           'worst': {'before': b.get('worst'), 'after': n.get('worst')},
           'before': b['source'], 'after': n['source']}
    out = json.dumps(doc, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(out + '\n')
    # human summary on stderr, JSON on stdout / -o
    print(f'verdict: {verdict}', file=sys.stderr)
    for r in rows:
        ws, wh = r['wns_setup'], r['wns_hold']
        print(f"  {r['scenario']:<32} setup WNS {ws['before']} -> {ws['after']}   hold WNS {wh['before']} -> {wh['after']}",
              file=sys.stderr)
    for x in reasons:
        print(f'  reject: {x}', file=sys.stderr)
    for x in incomplete[:10]:
        print(f'  unverified: {x}', file=sys.stderr)
    if not a.output:
        print(out)
    sys.exit({'ACCEPT': 0, 'REJECT': 2}.get(verdict, 3))


if __name__ == '__main__':
    main()
