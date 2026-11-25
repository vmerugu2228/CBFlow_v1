#!/usr/bin/env python3
"""Floorplan rule check of a finished FP run (open-source flow).

    fp_check.py <FP run dir> --inputs <fp_inputs.json> [-o out.json]

Reads the run's floorplan DEF (work/FP/export_data1/outputs/final.def, else
powerplan / floorplan outputs), its user_config (fp(oss,*) keys) and the macro
sizes / pin sides from fp_inputs.json. Checks:
  macros   inside the core; x on the site grid and y on the row grid from the
           core origin; DL2 children's y on the rail pitch; no overlaps;
           facing-macro channel >= fp(oss,fp,macro_channel); macro pins face
           the logic (pin side after orientation points into the core, not at
           the die edge); only R0 / R180 / MX / MY
  blockages each fp(oss,macro,blockage_sides) side has a placement blockage
           touching the macro
  pins     every signal pin placed on the die edge; pins of each
           fp(oss,pins,constraints) group on that group's side
  reports  the flow's own check_floorplan_rules.rpt (violations : 0) and
           report_design.rpt Min Macro Channel Width
Exit 0 = all pass, 2 = violations (listed).
"""
import argparse
import fnmatch
import glob
import json
import os
import re
import sys

SET_RE = re.compile(r'^\s*set\s+(\S+)\s+(?:"([^"]*)"|\{(.*)\}|(\S+))')


def tcl_sets(path):
    out = {}
    if os.path.isfile(path):
        with open(path, errors='replace') as f:
            for ln in f:
                m = SET_RE.match(ln)
                if m:
                    out[m.group(1)] = next(g for g in m.groups()[1:] if g is not None)
    return out


def tcl_list(s):
    out, i, n = [], 0, len(s)
    while i < n:
        while i < n and s[i].isspace():
            i += 1
        if i >= n:
            break
        if s[i] == '{':
            d, j = 1, i + 1
            while j < n and d:
                d += {'{': 1, '}': -1}.get(s[j], 0)
                j += 1
            out.append(s[i + 1:j - 1]); i = j
        else:
            j = i
            while j < n and not s[j].isspace():
                j += 1
            out.append(s[i:j]); i = j
    return out


def read_def(path):
    d = {'dbu': 1000.0, 'die': None, 'comps': {}, 'pins': {}, 'blockages': [], 'rows': []}
    with open(path, errors='replace') as f:
        t = f.read()
    m = re.search(r'UNITS DISTANCE MICRONS (\d+)', t)
    if m:
        d['dbu'] = float(m.group(1))
    u = d['dbu']
    m = re.search(r'DIEAREA\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)', t)
    if m:
        d['die'] = [int(v) / u for v in m.groups()]
    for r in re.finditer(r'^ROW\s+\S+\s+\S+\s+(-?\d+)\s+(-?\d+)', t, re.M):
        d['rows'].append((int(r.group(1)) / u, int(r.group(2)) / u))
    comp = t.split('COMPONENTS', 1)[1].split('END COMPONENTS', 1)[0] if 'COMPONENTS' in t else ''
    for c in re.finditer(r'-\s+(\S+)\s+(\S+)[^;]*?(PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)', comp):
        d['comps'][c.group(1).lstrip('\\')] = {'master': c.group(2), 'x': int(c.group(4)) / u, 'y': int(c.group(5)) / u,
                                                'orient': c.group(6)}
    pins = t.split('\nPINS', 1)[1].split('END PINS', 1)[0] if '\nPINS' in t else ''
    for p in re.finditer(r'-\s+(\S+)\s+\+\s+NET.*?;', pins, re.S):
        body = p.group(0)
        if re.search(r'USE\s+(POWER|GROUND)', body):
            continue
        m = re.search(r'(PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)', body)
        d['pins'][p.group(1)] = (int(m.group(2)) / u, int(m.group(3)) / u) if m else None
    blk = t.split('BLOCKAGES', 1)[1].split('END BLOCKAGES', 1)[0] if 'BLOCKAGES' in t else ''
    for b in re.finditer(r'-\s+PLACEMENT[^;]*?RECT\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)', blk, re.S):
        d['blockages'].append([int(v) / u for v in b.groups()])
    return d


def orient_side(side, o):
    """Side a LEF pin side ends up on after the DEF orientation."""
    flip = {'R0': {}, 'MX': {'top': 'bottom', 'bottom': 'top'}, 'MY': {'left': 'right', 'right': 'left'},
            'R180': {'top': 'bottom', 'bottom': 'top', 'left': 'right', 'right': 'left'}}
    return flip.get(o, {}).get(side, side)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('run')
    ap.add_argument('--inputs', required=True)
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    run = os.path.abspath(a.run)
    with open(a.inputs) as f:
        inp = json.load(f)
    deff = next((p for p in [os.path.join(run, 'work', 'FP', n, 'outputs', f) for n, f in
                             (('export_data1', 'final.def'), ('powerplan1', 'powerplan.def'), ('floorplan1', 'floorplan.def'))]
                 if os.path.isfile(p)), '')
    if not deff:
        sys.exit(f'fp_check: no floorplan DEF under {run}/work/FP/')
    d = read_def(deff)
    uc = tcl_sets(os.path.join(run, 'setup', 'user_config.tcl'))
    fpd = inp['fp_defaults']
    key = lambda k: uc.get(f'fp({k})', fpd.get(k, ''))
    t = inp['tech']
    sw, rh = t['site_width'], t['row_height']
    halo, chan = float(key('oss,macro,halo') or 10), float(key('oss,fp,macro_channel') or 60)
    die = d['die']
    xs = sorted({x for x, y in d['rows']}); ys = sorted({y for x, y in d['rows']})
    core = [min(xs), min(ys), die[2] - min(xs), max(ys) + rh] if d['rows'] else die
    viol, info = [], []
    macros = {m['master']: m for m in inp['macros'] if m.get('size')}
    placed = []
    for name, c in d['comps'].items():
        m = macros.get(c['master'])
        if not m:
            continue
        w, h = m['size']
        x0, y0, x1, y1 = c['x'], c['y'], c['x'] + w, c['y'] + h
        placed.append((name, m, c, [x0, y0, x1, y1]))
        if c['orient'] not in ('N', 'S', 'FN', 'FS', 'R0', 'R180', 'MX', 'MY'):
            viol.append(f'{name}: orientation {c["orient"]}')
        if x0 < core[0] - 1e-3 or y0 < core[1] - 1e-3 or x1 > core[2] + 1e-3 or y1 > core[3] + 1e-3:
            viol.append(f'{name}: outside the core {core}')
        if abs(round((x0 - core[0]) / sw) * sw - (x0 - core[0])) > 1e-3:
            viol.append(f'{name}: x {x0} off the site grid ({sw})')
        if abs(round((y0 - core[1]) / rh) * rh - (y0 - core[1])) > 1e-3 and not m.get('dl2'):
            viol.append(f'{name}: y {y0} off the row grid ({rh})')
        if m.get('dl2') and t.get('rail_pitch') and abs(round(y0 / t['rail_pitch']) * t['rail_pitch'] - y0) > 1e-3:
            viol.append(f'{name}: DL2 y {y0} not on the rail pitch {t["rail_pitch"]}')
        # pins face the logic: the side carrying most signal pins must not lie on the die edge
        if m.get('pin_sides'):
            o = {'N': 'R0', 'S': 'R180', 'FN': 'MY', 'FS': 'MX'}.get(c['orient'], c['orient'])
            side = orient_side(max(m['pin_sides'], key=m['pin_sides'].get), o)
            edge = {'left': x0 - core[0], 'right': core[2] - x1, 'bottom': y0 - core[1], 'top': core[3] - y1}[side]
            if edge < halo:
                viol.append(f'{name}: pins ({side}) face the core edge ({edge:.1f} um) — they must face the logic')
            else:
                info.append(f'{name}: pins face {side}, {edge:.1f} um of logic beyond')
    for i in range(len(placed)):
        for j in range(i + 1, len(placed)):
            a_, b_ = placed[i][3], placed[j][3]
            gx = max(b_[0] - a_[2], a_[0] - b_[2]); gy = max(b_[1] - a_[3], a_[1] - b_[3])
            if gx < 0 and gy < 0:
                viol.append(f'{placed[i][0]} overlaps {placed[j][0]}')
            elif max(gx, gy) < chan and min(gx, gy) < 0:
                viol.append(f'{placed[i][0]} / {placed[j][0]}: channel {max(gx, gy):.1f} um < {chan}')
    sides = tcl_list(key('oss,macro,blockage_sides'))
    for name, m, c, bb in placed:
        for s in sides:
            touch = [b for b in d['blockages'] if
                     (s == 'left' and abs(b[2] - bb[0]) <= halo + 3 and b[0] < bb[0]) or
                     (s == 'right' and abs(b[0] - bb[2]) <= halo + 3 and b[2] > bb[2]) or
                     (s == 'bottom' and abs(b[3] - bb[1]) <= halo + 3 and b[1] < bb[1]) or
                     (s == 'top' and abs(b[1] - bb[3]) <= halo + 3 and b[3] > bb[3])]
            room = {'left': bb[0] - core[0], 'right': core[2] - bb[2], 'bottom': bb[1] - core[1], 'top': core[3] - bb[3]}[s]
            if not touch and room > 1:
                viol.append(f'{name}: no placement blockage on its {s} side')
    # pins
    groups = [(tcl_list(g)[0].split(':')[0], tcl_list(g)[1:]) for g in tcl_list(key('oss,pins,constraints'))]
    region = (key('oss,pins,region') or '').split(':')[0]
    edge_of = lambda x, y: min((('left', x - die[0]), ('right', die[2] - x), ('bottom', y - die[1]), ('top', die[3] - y)),
                                key=lambda e: e[1])
    for p, xy in d['pins'].items():
        if xy is None:
            viol.append(f'pin {p}: not placed'); continue
        side, dist = edge_of(*xy)
        if dist > 1.0:
            viol.append(f'pin {p}: not on the die edge ({dist:.2f} um)'); continue
        want = next((s for s, gl in groups if any(fnmatch.fnmatchcase(p, g) for g in gl)), region)
        if want and want != side:
            viol.append(f'pin {p}: on {side}, constraint wants {want}')
    # flow reports
    for rpt, pat, okv in (('check_floorplan_rules.rpt', r'Floorplan rule violations\s*:\s*(\d+)', '0'),):
        f = glob.glob(os.path.join(run, 'work', 'FP', '*', 'reports', rpt))
        if f:
            m = re.search(pat, open(f[0]).read())
            if m and m.group(1) != okv:
                viol.append(f'{rpt}: {m.group(0)}')
    ch = glob.glob(os.path.join(run, 'work', 'FP', '*', 'reports', 'report_design.rpt'))
    if ch:
        m = re.search(r'Min Macro Channel Width\s*:\s*(\S+)', open(ch[0]).read())
        if m:
            info.append(f'flow Min Macro Channel Width : {m.group(1)}')
    npins = len(d['pins'])
    if len(viol) > 40:
        viol = viol[:40] + [f'... {len(viol) - 40} more']
    doc = {'run': run, 'def': deff, 'die': die, 'core': core, 'macros': len(placed), 'pins': npins,
           'verdict': 'PASS' if not viol else 'FAIL', 'violations': viol, 'info': info}
    print(f"fp_check: {doc['verdict']} — {len(placed)} macro(s), {npins} pins, {len(viol)} violation(s)", file=sys.stderr)
    for v in viol[:15]:
        print(f'  x {v}', file=sys.stderr)
    for i in info:
        print(f'  - {i}', file=sys.stderr)
    out = json.dumps(doc, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(out + '\n')
    else:
        print(out)
    sys.exit(0 if not viol else 2)


if __name__ == '__main__':
    main()
