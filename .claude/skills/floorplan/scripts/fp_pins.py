#!/usr/bin/env python3
"""Port placement for a floorplan candidate -> fp(oss,pins,constraints).

    fp_pins.py <fp_inputs.json> --die "x0 y0 x1 y1" [--side top|bottom|left|right]
               [--parent-def <parent FP/PNR DEF>] [-o out.json]

Side (first that applies):
  --side                given explicitly
  --parent-def          the side of this block's instance that faces the
                        parent's core centre (where the parent's logic is) —
                        a child macro keeps its pins toward its parent's logic
  own macros            the side opposite the macro row / column (pins next to
                        the logic band, not behind the macros)
  default               top
Port groups: the module's ports (SYNTH release netlist header) grouped by
bus / name prefix; each group gets a contiguous span on the side, in netlist
order, sized for its bits at 2 tracks (met2/met3 pitch) per pin, spans spread
over the edge with the clock / reset / scan pins in the middle.
Output: groups with their spans and the Tcl value for fp(oss,pins,constraints).
"""
import argparse
import json
import os
import re
import sys


def ports(netlist, module):
    """[(name, bits)] of the module's ports in declaration order."""
    if not os.path.isfile(netlist):
        return []
    t = open(netlist, errors='replace').read()
    m = re.search(r'^module\s+%s\b.*?;(.*?)^endmodule' % re.escape(module), t, re.S | re.M)
    body = m.group(1) if m else ''
    out = []
    for kind, rng, names in re.findall(r'^\s*(input|output|inout)\s+(\[\s*\d+\s*:\s*\d+\s*\])?\s*([^;]+);', body, re.M):
        bits = 1
        if rng:
            a, b = (int(v) for v in re.findall(r'\d+', rng))
            bits = abs(a - b) + 1
        for n in names.split(','):
            out.append((n.strip().lstrip('\\'), bits))
    return out


def side_from_parent(defpath, block, design):
    t = open(defpath, errors='replace').read()
    die = [int(v) for v in re.search(r'DIEAREA\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+\(\s*(-?\d+)\s+(-?\d+)', t).groups()]
    m = re.search(r'-\s+\S+\s+%s\s+\+\s+(?:PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)' % re.escape(block), t)
    if not m:
        return None
    x, y = int(m.group(1)), int(m.group(2))
    cx, cy = (die[0] + die[2]) / 2, (die[1] + die[3]) / 2
    dx, dy = cx - x, cy - y
    return ('right' if dx > 0 else 'left') if abs(dx) > abs(dy) else ('top' if dy > 0 else 'bottom')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('inputs')
    ap.add_argument('--die', required=True, help='"x0 y0 x1 y1" um (the chosen candidate)')
    ap.add_argument('--side')
    ap.add_argument('--parent-def')
    ap.add_argument('--arrangement', default='', help='the candidate arrangement (bottom_row | left_column | none)')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    d = json.load(open(a.inputs))
    x0, y0, x1, y1 = (float(v) for v in a.die.split())
    side, why = a.side, 'given'
    if not side and a.parent_def:
        side = side_from_parent(a.parent_def, d['block'], d['block'])
        why = f'faces the parent core centre ({a.parent_def})'
    if not side and a.arrangement in ('bottom_row', 'left_column'):
        side, why = {'bottom_row': 'top', 'left_column': 'right'}[a.arrangement], 'opposite the macros (next to the logic band)'
    if not side:
        side, why = 'top', 'default'
    pl = ports(d['netlist'], d['block'])
    if not pl:
        sys.exit(f"fp_pins: no ports of module {d['block']} in {d['netlist']}")
    groups = {}
    for n, bits in pl:
        base = re.sub(r'(_\d+|\d+)$', '', n) if bits == 1 else n
        groups.setdefault(base, []).append((n, bits))
    pitch = 2 * max((l['pitch_um'] for l in d['tech']['routing_layers'] if l['layer'] in ('met2', 'met3')), default=0.68)
    length = (x1 - x0) if side in ('top', 'bottom') else (y1 - y0)
    special = [g for g in groups if re.search(r'clk|clock|rst|reset|scan|test', g, re.I)]
    order = [g for g in groups if g not in special]
    order = order[:len(order) // 2] + special + order[len(order) // 2:]
    need = sum(sum(b for _, b in groups[g]) * pitch for g in order)
    if need > length:
        print(f'fp_pins: WARNING: {need:.0f} um of pins on a {length:.0f} um {side} edge — use two sides or a wider die', file=sys.stderr)
    gap = max((length - need) / (len(order) + 1), 0)
    pos, out = gap, []
    for g in order:
        span = sum(b for _, b in groups[g]) * pitch
        a0, a1 = int(pos), int(pos + span + 1)
        names = [n if b == 1 else f'{n}*' for n, b in groups[g]]
        out.append({'group': g, 'pins': names, 'bits': sum(b for _, b in groups[g]), 'region': f'{side}:{a0}-{a1}'})
        pos += span + gap
    tcl = ' '.join('{%s %s}' % (o['region'], ' '.join(o['pins'])) for o in out)
    doc = {'block': d['block'], 'side': side, 'why': why, 'edge_um': round(length, 2), 'pins_um': round(need, 1),
           'groups': out, 'uc': {'fp(oss,pins,constraints)': '{%s}' % tcl}}
    print(f"fp_pins: {len(out)} groups, {sum(o['bits'] for o in out)} bits on {side} ({why})", file=sys.stderr)
    s = json.dumps(doc, indent=1)
    if a.output:
        open(a.output, 'w').write(s + '\n')
    else:
        print(s)


if __name__ == '__main__':
    main()
