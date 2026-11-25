#!/usr/bin/env python3
"""Partitioning advice for a block (advisory only — never edits the hierarchy).

    fp_partition.py <fp_inputs.json> [--rtl <filelist .f>] [-o out.json]

Reports:
  hierarchy   this block's level / parent / children; each hard child's share
              of the block (child area / (child area + std area / 0.5))
  children    flatten candidates: a child under ~5 % of the parent with few pins
              (a hard boundary costs halo, channel, pin access and a PV / STA
              loop for little area); keep-hard: large, reused or memory-bearing
  rtl         (with --rtl) modules defined in the RTL filelist with how often
              they are instantiated and their register count — repeated modules
              (reuse) and register-heavy modules are hardening candidates; the
              synthesized netlist is flat, so per-module area comes from the
              register count, not yosys
Partition changes are the user's: project(design_hierarchy) is never edited.
"""
import argparse
import collections
import json
import os
import re
import sys


def rtl_modules(flist):
    files = []
    base = os.path.dirname(os.path.abspath(flist))
    for ln in open(flist, errors='replace'):
        ln = ln.strip()
        if not ln or ln.startswith(('//', '#', '+', '-')):
            continue
        p = ln if os.path.isabs(ln) else os.path.join(base, ln)
        if os.path.isfile(p):
            files.append(p)
    defs, inst, regs = {}, collections.Counter(), {}
    for f in files:
        t = re.sub(r'//.*', '', open(f, errors='replace').read())
        for m in re.finditer(r'^\s*module\s+(\w+)(.*?)^\s*endmodule', t, re.S | re.M):
            name, body = m.group(1), m.group(2)
            defs[name] = f
            regs[name] = len(re.findall(r'\b(always_ff|always\s*@\s*\(\s*(pos|neg)edge)', body))
            for im in re.finditer(r'^\s*(\w+)\s*(#\s*\(.*?\))?\s+(\w+)\s*\(', body, re.S | re.M):
                if im.group(1) not in ('module', 'if', 'for', 'case', 'always', 'assign', 'begin', 'end', 'wire', 'reg', 'logic', 'input', 'output'):
                    inst[im.group(1)] += 1
    return [{'module': n, 'file': os.path.basename(f), 'instances': inst.get(n, 0), 'sequential_blocks': regs.get(n, 0)}
            for n, f in defs.items()]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('inputs')
    ap.add_argument('--rtl', help='RTL filelist (.f), e.g. inputs/opensky/<b>/<PHASE>/<b>.f')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    d = json.load(open(a.inputs))
    std = d['synth'].get('std_area_um2', 0.0)
    kids = []
    tot_macro = sum(m['size'][0] * m['size'][1] * len(m['instances']) for m in d['macros'] if m.get('size'))
    whole = tot_macro + std / 0.5
    for m in d['macros']:
        if not m.get('size'):
            continue
        area = m['size'][0] * m['size'][1]
        share = 100 * area * len(m['instances']) / whole if whole else 0
        adv = []
        if m['kind'] == 'block' and share < 5 and m.get('pins', 0) < 200:
            adv.append('flatten candidate: small hard boundary (halo / channel / pin-access / extra PV+STA loop for little area)')
        if len(m['instances']) > 1:
            adv.append(f"keep hard: reused {len(m['instances'])}x")
        if m['kind'] == 'memory':
            adv.append('hard macro (memory)')
        if share >= 50:
            adv.append('dominates the block: floorplan around it (corner / edge, pins toward the logic)')
        kids.append({'master': m['master'], 'kind': m['kind'], 'instances': m['instances'], 'size_um': m['size'],
                     'area_um2': round(area, 1), 'share_pct': round(share, 1), 'pins': m.get('pins', 0), 'advice': adv})
    rtl = rtl_modules(a.rtl) if a.rtl and os.path.isfile(a.rtl) else []
    cands = [r for r in rtl if r['instances'] > 1 or r['sequential_blocks'] >= 8]
    doc = {'block': d['block'], 'hier': d['hier'], 'std_area_um2': std, 'children': kids, 'rtl_modules': rtl,
           'rtl_hardening_candidates': cands,
           'note': 'advisory — project(design_hierarchy) and the block structure are the user\'s decision'}
    print(f"fp_partition: {d['block']} ({d['hier'].get('level', '')}): {len(kids)} hard child(ren), "
          f"{len(rtl)} RTL modules, {len(cands)} hardening candidate(s)", file=sys.stderr)
    for k in kids:
        print(f"  {k['master']:<34} {k['share_pct']:>5}%  {'; '.join(k['advice'])}", file=sys.stderr)
    s = json.dumps(doc, indent=1)
    if a.output:
        open(a.output, 'w').write(s + '\n')
    else:
        print(s)


if __name__ == '__main__':
    main()
