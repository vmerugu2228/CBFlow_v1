#!/usr/bin/env python3
"""DRC summary of a CBflow run for the drc-fix skill: violations by rule / layer,
clustered into hotspots, each mapped to the nets and instances under it.

    drc_summary.py <run_dir> [--def <file.def>] [--window UM] [-o out.json]

Sources (whichever the run has):
  PV run   work/PV/<drc node>/reports/drc_klayout.lyrdb  (KLayout sky130 deck: rule, polygon / box)
           work/PV/<drc node>/outputs/drc.rpt             (engine, gds, total)
  PNR/ECO  work/{PNR,ECO}/<node>/reports/{route_drc,eco_route_drc}.rpt
                                                  (OpenROAD detailed-route markers: type, layer, nets, box)
Mapping: the layout DEF (--def, else the one the run read: a PV run's
gds/def input from setup/resolved_inputs.tcl, a PNR/ECO run's outputs/final.def)
— routed segments and component boxes near each hotspot. Read-only.

JSON:
  source     {kind, run, design, phase, release_tag, release_dir, def}
  totals     {total, by_rule, by_layer}: the block's own geometry (what an ECO
             can change); {child_total, child_by_rule{"cell:rule": n}}: inside
             child blocks / macros (fix in the child's release)
  hotspots   [{rule, layer, count, bbox[um], nets[], insts[{name, cell}], samples[]}]
"""
import argparse
import glob
import json
import math
import os
import re
import sys

LYR_ITEM = re.compile(r'<item>(.*?)</item>', re.S)
LYR_CAT = re.compile(r"<category>'?([^<']+)'?</category>")
LYR_CELL = re.compile(r"<cell>([^<]+)</cell>")
LYR_VAL = re.compile(r'<value>(polygon|box|edge|edge-pair)[^:]*:\s*\(([^<]*)\)</value>')
NUM = re.compile(r'-?\d+(?:\.\d+)?')
TR_TYPE = re.compile(r'violation type:\s*(.+?)\s*$')
TR_SRCS = re.compile(r'srcs:\s*(.*)$')
TR_BOX = re.compile(r'bbox\s*=\s*\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)\s*-\s*\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)\s*on Layer\s+(\S+)')
SET_RE = re.compile(r'^\s*set\s+(\S+)\s+(?:"([^"]*)"|(\S+))')
# sky130 KLayout rule prefix -> layer
RULE_LAYER = {'li': 'li1', 'ct': 'licon', 'licon': 'licon', 'mcon': 'mcon', 'm1': 'met1', 'via': 'via',
              'm2': 'met2', 'via2': 'via2', 'm3': 'met3', 'via3': 'via3', 'm4': 'met4', 'via4': 'via4',
              'm5': 'met5', 'poly': 'poly', 'difftap': 'diff', 'nwell': 'nwell', 'hvi': 'hvi', 'pad': 'pad'}


def tcl_sets(path):
    out = {}
    if os.path.isfile(path):
        with open(path, errors='replace') as f:
            for ln in f:
                m = SET_RE.match(ln)
                if m:
                    out[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
    return out


def rule_layer(rule):
    base = rule.split('.')[0].lower()
    return RULE_LAYER.get(base, base)


def bbox_of(nums):
    xs, ys = nums[0::2], nums[1::2]
    return [min(xs), min(ys), max(xs), max(ys)]


def klayout_violations(lyrdb):
    out = []
    with open(lyrdb, errors='replace') as f:
        text = f.read()
    for it in LYR_ITEM.findall(text):
        cm = LYR_CAT.search(it)
        rule = cm.group(1).strip() if cm else '?'
        ce = LYR_CELL.search(it)
        cell = ce.group(1).strip() if ce else ''
        for kind, coords in LYR_VAL.findall(it):
            nums = [float(x) for x in NUM.findall(coords)]
            if len(nums) >= 4:
                # bbox is in the coordinates of `cell` (KLayout deep mode reports
                # a violation inside a child block in that child's coordinates)
                out.append({'rule': rule, 'layer': rule_layer(rule), 'bbox': bbox_of(nums), 'nets': [],
                            'source': 'pv', 'cell': cell})
    return out


def router_violations(rpt):
    out, cur = [], None
    with open(rpt, errors='replace') as f:
        for ln in f:
            m = TR_TYPE.search(ln)
            if m:
                cur = {'rule': m.group(1), 'nets': [], 'source': 'router'}
                continue
            if cur is None:
                continue
            s = TR_SRCS.search(ln)
            if s:
                cur['nets'] = [x.split(':', 1)[1] for x in s.group(1).split() if x.startswith('net:')]
                continue
            b = TR_BOX.search(ln)
            if b:
                x0, y0, x1, y1 = (float(b.group(i)) for i in range(1, 5))
                cur.update({'layer': b.group(5), 'bbox': [x0, y0, x1, y1]})
                out.append(cur)
                cur = None
    return out


class Def:
    """Routed segments and component boxes of a DEF (um)."""
    def __init__(self, path):
        self.segs, self.comps, self.dbu = [], [], 1000.0
        self.macros = {}
        if not path or not os.path.isfile(path):
            return
        sec, net, last = None, None, None
        with open(path, errors='replace') as f:
            for ln in f:
                t = ln.strip()
                if t.startswith('UNITS DISTANCE MICRONS'):
                    self.dbu = float(t.split()[3])
                elif t.startswith('COMPONENTS'):
                    sec = 'C'
                elif t.startswith('END COMPONENTS') or t.startswith('END NETS'):
                    sec = None
                elif t.startswith('NETS') or t.startswith('SPECIALNETS'):
                    sec = 'N' if t.startswith('NETS') else 'S'
                elif sec == 'C' and t.startswith('-'):
                    p = t.split()
                    m = re.search(r'(PLACED|FIXED)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)', t)
                    if m and len(p) > 2:
                        self.comps.append((p[1], p[2], float(m.group(2)) / self.dbu, float(m.group(3)) / self.dbu))
                elif sec == 'N':
                    if t.startswith('-'):
                        net = t.split()[1].lstrip('\\')
                    for lay, pts in re.findall(r'(?:ROUTED|NEW)\s+(\S+)(?:\s+\d+)?\s+((?:\(\s*[-\d*]+\s+[-\d*]+(?:\s+-?\d+)?\s*\)\s*)+)', t):
                        coords, px, py = [], None, None
                        for x, y in re.findall(r'\(\s*([-\d*]+)\s+([-\d*]+)', pts):
                            px = px if x == '*' else float(x) / self.dbu
                            py = py if y == '*' else float(y) / self.dbu
                            coords.append((px, py))
                        for (ax, ay), (bx, by) in zip(coords, coords[1:]):
                            self.segs.append((net, lay, min(ax, bx), min(ay, by), max(ax, bx), max(ay, by)))
                        if len(coords) == 1:
                            ax, ay = coords[0]
                            self.segs.append((net, lay, ax, ay, ax, ay))

    def near(self, box, layer, win):
        x0, y0, x1, y1 = box[0] - win, box[1] - win, box[2] + win, box[3] + win
        # a metal-layer violation also matches vias written on the metal below /
        # above (DEF puts an M2M3 via on the met2 line); via layers match any
        stack = ['li1', 'met1', 'met2', 'met3', 'met4', 'met5']
        ok = None
        if layer in stack:
            i = stack.index(layer)
            ok = set(stack[max(0, i - 1):i + 2])
        nets = sorted({s[0] for s in self.segs if (ok is None or s[1] in ok)
                       and s[2] <= x1 and s[4] >= x0 and s[3] <= y1 and s[5] >= y0})
        insts = [{'name': n, 'cell': c} for n, c, x, y in self.comps
                 if x0 - 10 <= x <= x1 and y0 - 3 <= y <= y1 and 'fill' not in c and 'tap' not in c]
        return nets, insts[:12]


def cluster(viols, radius):
    """Greedy clustering per rule: violations within radius um join a hotspot."""
    spots = []
    for v in sorted(viols, key=lambda v: (v['rule'], v['bbox'][0], v['bbox'][1])):
        cx, cy = (v['bbox'][0] + v['bbox'][2]) / 2, (v['bbox'][1] + v['bbox'][3]) / 2
        for h in spots:
            if h['rule'] == v['rule'] and math.hypot(cx - h['_c'][0], cy - h['_c'][1]) <= radius:
                h['members'].append(v)
                b = h['bbox']
                h['bbox'] = [min(b[0], v['bbox'][0]), min(b[1], v['bbox'][1]), max(b[2], v['bbox'][2]), max(b[3], v['bbox'][3])]
                break
        else:
            spots.append({'rule': v['rule'], 'layer': v.get('layer', ''), 'bbox': list(v['bbox']), '_c': (cx, cy), 'members': [v]})
    return spots


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('run_dir')
    ap.add_argument('--def', dest='def_file')
    ap.add_argument('--window', type=float, default=1.0, help='um around a violation searched for nets / instances')
    ap.add_argument('--cluster', type=float, default=20.0, help='um: violations of a rule this close form one hotspot')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    run = os.path.abspath(a.run_dir)
    uc = tcl_sets(os.path.join(run, 'setup', 'user_config.tcl'))
    ri = tcl_sets(os.path.join(run, 'setup', 'resolved_inputs.tcl'))
    src = {'run': run, 'design': uc.get('flow(design_name)', ''), 'phase': uc.get('project(phase)', ''),
           'lib_tag': uc.get('project(lib_config_tag)', ''), 'flow': uc.get('flow(type)', '')}
    viols = []
    lyr = sorted(glob.glob(os.path.join(run, 'work', 'PV', '*', 'reports', 'drc_klayout.lyrdb')))
    rrp = sorted(glob.glob(os.path.join(run, 'work', '*', '*', 'reports', '*route_drc.rpt')))
    if lyr:
        src['kind'] = 'pv'
        for f in lyr:
            viols += klayout_violations(f)
        src['release_tag'] = next((v for k, v in uc.items() if k.startswith('pv(input,') and k.endswith('release_tag)')), '')
        anyp = next((v for k, v in ri.items() if k.startswith('pv(input,') and v), '')
        if anyp:
            src['release_dir'] = os.path.dirname(os.path.dirname(anyp))
        rep = sorted(glob.glob(os.path.join(run, 'work', 'PV', '*', 'outputs', 'drc.rpt')))
        if rep:
            src['drc_report'] = rep[0]
    elif rrp:
        src['kind'] = 'router'
        for f in rrp:
            viols += router_violations(f)
        src['reports'] = rrp
    else:
        sys.exit(f'drc_summary: no DRC report under {run} (PV drc_klayout.lyrdb or *route_drc.rpt)')
    deff = a.def_file
    if not deff and src.get('release_dir'):
        cand = os.path.join(src['release_dir'], 'def', f"{src['design']}.def")
        deff = cand if os.path.isfile(cand) else ''
    if not deff:
        cand = sorted(glob.glob(os.path.join(run, 'work', '*', '*', 'outputs', 'final.def')))
        deff = cand[-1] if cand else ''
    src['def'] = deff
    d = Def(deff)
    # own = in this block's top cell (or router markers); child = inside a
    # child block / macro cell — not fixable here (fix the child's release)
    top = src['design']
    for v in viols:
        v['scope'] = 'child' if v.get('cell') and v['cell'] != top else 'own'
    by_rule, by_layer, child_rule = {}, {}, {}
    for v in viols:
        if v['scope'] == 'child':
            k = f"{v['cell']}:{v['rule']}"
            child_rule[k] = child_rule.get(k, 0) + 1
            continue
        by_rule[v['rule']] = by_rule.get(v['rule'], 0) + 1
        by_layer[v.get('layer', '?')] = by_layer.get(v.get('layer', '?'), 0) + 1
    spots = []
    for v in viols:
        v['rule_key'] = v['rule'] if v['scope'] == 'own' else f"{v['cell']}:{v['rule']}"
    for h in cluster([dict(v, rule=v['rule_key']) for v in viols], a.cluster):
        if ':' in h['rule']:          # child-cell violation: no parent-net mapping
            cell, rule = h['rule'].split(':', 1)
            spots.append({'rule': rule, 'cell': cell, 'scope': 'child', 'layer': h['layer'], 'count': len(h['members']),
                          'bbox': [round(x, 3) for x in h['bbox']], 'nets': [], 'insts': [],
                          'note': f'inside child cell {cell} ({cell} coordinates) — fix in {cell}\'s release, then re-stream',
                          'samples': [[round(x, 3) for x in m['bbox']] for m in h['members'][:5]]})
            continue
        nets, insts = d.near(h['bbox'], h['layer'], a.window)
        nets = sorted(set(nets) | {n for m in h['members'] for n in m.get('nets', [])})
        spots.append({'rule': h['rule'], 'scope': 'own', 'layer': h['layer'], 'count': len(h['members']),
                      'bbox': [round(x, 3) for x in h['bbox']], 'nets': nets[:30], 'insts': insts,
                      'samples': [[round(x, 3) for x in m['bbox']] for m in h['members'][:5]]})
    spots.sort(key=lambda h: -h['count'])
    doc = {'source': src,
           'totals': {'total': sum(by_rule.values()), 'by_rule': by_rule, 'by_layer': by_layer,
                      'child_total': sum(child_rule.values()), 'child_by_rule': child_rule},
           'hotspots': spots}
    out = json.dumps(doc, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(out + '\n')
    else:
        print(out)


if __name__ == '__main__':
    main()
