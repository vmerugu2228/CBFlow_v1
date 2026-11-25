#!/usr/bin/env python3
"""Candidate floorplans with analytic area / routing-track estimates.

    fp_estimate.py <fp_inputs.json> [--util 30,45,60] [--aspect 0.5,1,2]
                   [--k 1.5] [--min-band-rows 20] [-o out.json]

For every utilization x aspect x macro arrangement:
  * core / die size on the grids: core origin = core margin rounded up to the
    site (x) and row (y) pitch; core width / height in whole sites / rows;
    die = core + the same margins, on the manufacturing grid
  * explicit macro placement (fp(oss,macro,placement) syntax): macros abut the
    core edge — "bottom_row" (row along the bottom, pins up) or "left_column"
    (stack along the left, pins right) — orientation chosen so the macro pins
    face the logic (R0 / MX / MY; DL2 children R0 only: oss_bridge_rails);
    channel fp(oss,fp,macro_channel) between macros; DL2 children's y on the
    rail pitch; blockage sides = the macro sides away from the logic
  * routing estimate in the logic area (macro footprints + halo excluded):
      demand  std-cell nets: k * cells * sqrt(logic_area / cells)   (Donath-
              style local wirelength; k calibrated from probe runs)
              + macro-pin nets: pins * (halo + band/2) vertical
                                + pins * span/4 horizontal
      supply  per direction: sum over the signal layers of
              area / pitch * usable (met1 0.5 — rails + cell-internal use;
              strap layers minus strap width / pitch; others 0.9)
    -> H / V track utilization %; verdict ok <= 50 < tight <= 70 < over
  * IO: perimeter needed for the port bits at 2 tracks per pin vs available
Analytic and first-order — the probe step (fp(oss,probe,enable)) on the
shortlisted candidates gives the real global-route overflow.
"""
import argparse
import json
import math
import sys


def up(v, g):
    return math.ceil(round(v / g, 6)) * g


def grid(v, g):
    return round(round(v / g) * g, 4)


def macro_orient(sides, want, dl2):
    """Orientation so the macro's pin side faces `want` (top|right)."""
    dom = max(sides, key=sides.get) if sides else want
    if dl2:
        return 'R0', dom == want or not sides
    table = {'top': {'top': 'R0', 'bottom': 'MX'}, 'right': {'right': 'R0', 'left': 'MY'}}
    o = table[want].get(dom)
    return (o, True) if o else ('R0', False)


def layer_supply(t, area, straps):
    """(H, V) usable track length per um2 * area."""
    H = V = 0.0
    strap_layers = {v[0]: float(v[1]) / float(v[2]) for v in straps.values() if len(v) >= 3}
    for l in t['routing_layers']:
        if not l['pitch_um']:
            continue
        use = 0.5 if l['layer'] == 'met1' else (1 - strap_layers[l['layer']]) * 0.9 if l['layer'] in strap_layers else 0.9
        s = area / l['pitch_um'] * use
        if l['dir'] == 'H':
            H += s
        elif l['dir'] == 'V':
            V += s
    return H, V


def routing(d, t, a, cells, free, macro_pins, halo, band, span, arrangement, insts):
    wl_std = a.k * cells * math.sqrt(free / cells)
    across, along = macro_pins * (halo + band / 2), macro_pins * span / 4
    dem_h, dem_v = wl_std / 2 + along, wl_std / 2 + across
    if arrangement == 'left_column' and insts:
        dem_h, dem_v = wl_std / 2 + across, wl_std / 2 + along
    sup_h, sup_v = layer_supply(t, free, t.get('pdn_straps', {}))
    uh = 100 * dem_h / sup_h if sup_h else 999
    uv = 100 * dem_v / sup_v if sup_v else 999
    return wl_std, dem_h, dem_v, sup_h, sup_v, uh, uv


def candidate(d, util, ar, arrangement, a):
    t, fp = d['tech'], d['fp_defaults']
    sw, rh, mg = t['site_width'], t['row_height'], t['manufacturing_grid'] or 0.005
    margin = float(fp.get('oss,fp,core_margin', 10))
    halo = float(fp.get('oss,macro,halo', 10))
    chan = float(fp.get('oss,fp,macro_channel', 60))
    cx0, cy0 = up(margin, sw), up(margin, rh)
    std = d['synth'].get('std_area_um2', 0.0)
    cells = max(d['synth'].get('cells', 1), 1)
    logic_area = std / (util / 100.0)
    insts = [(m, i) for m in d['macros'] for i in m['instances'] if m.get('size')]
    notes = []
    place, sides_block = [], []
    macro_pins = sum(m.get('pins', 0) * len(m['instances']) for m in d['macros'])
    if not insts:
        W = math.sqrt(logic_area / ar)
        H = logic_area / W
        W, H = up(W, sw), up(H, rh)
        band = H
        span = W
    elif arrangement == 'bottom_row':
        # width: the macro row + a strip of rows beside the last macro outside
        # its halo (global placement's core comes from the rows: it must span
        # the macro height); the aspect target only widens it
        Wm = sum(up(m['size'][0], sw) for m, _ in insts) + chan * (len(insts) - 1)
        Hm = max(m['size'][1] for m, _ in insts)
        hb = Hm + halo
        W = up(max(Wm + 2 * halo, math.sqrt(logic_area / ar) if ar else 0), sw)
        band = up(max(logic_area / W, a.min_band_rows * rh), rh)
        H = up(hb + band, rh)
        x = cx0
        for m, i in insts:
            o, ok = macro_orient(m.get('pin_sides', {}), 'top', m.get('dl2'))
            if not ok:
                notes.append(f"{i}: pins on {max(m['pin_sides'], key=m['pin_sides'].get)} do not face the logic")
            y = cy0
            if m.get('dl2') and t.get('rail_pitch'):
                y = up(cy0, t['rail_pitch'])
            place.append([i, grid(x, sw), grid(y, mg), o])
            x += m['size'][0] + chan
        sides_block = ['left', 'right', 'bottom'] if W - Wm > 2 * halo else ['bottom']
        span = W
    else:                                                     # left_column
        Hm = sum(up(m['size'][1], rh) for m, _ in insts) + chan * (len(insts) - 1)
        Wm = max(m['size'][0] for m, _ in insts)
        wb = Wm + halo
        H = up(max(Hm + 2 * halo, math.sqrt(logic_area * ar) if ar else 0), rh)
        band = up(max(logic_area / H, a.min_band_rows * rh), sw)
        W = up(wb + band, sw)
        y = cy0
        for m, i in insts:
            o, ok = macro_orient(m.get('pin_sides', {}), 'right', m.get('dl2'))
            if not ok:
                notes.append(f"{i}: pins on {max(m['pin_sides'], key=m['pin_sides'].get)} do not face the logic")
            yy = up(y, t['rail_pitch']) if m.get('dl2') and t.get('rail_pitch') else y
            place.append([i, grid(cx0, sw), grid(yy, mg), o])
            y = yy + m['size'][1] + chan
        sides_block = ['left', 'top', 'bottom'] if H - Hm > 2 * halo else ['left']
        span = H
    macro_area = sum((m['size'][0] + 2 * halo) * (m['size'][1] + 2 * halo) for m, _ in insts)
    free = max(W * H - macro_area, 1.0)
    rt = routing(d, t, a, cells, free, macro_pins, halo, band, span, arrangement, insts)
    # macro designs: grow the logic band (rows for bottom_row, sites for
    # left_column) until both directions are within the target utilization
    step = rh if arrangement == 'bottom_row' else sw
    grew = 0
    while insts and max(rt[5], rt[6]) > a.target and grew < 20000:
        band += step * max(1, int(band / step * 0.05))
        if arrangement == 'bottom_row':
            H = up(hb + band, rh)
        else:
            W = up(wb + band, sw)
        free = max(W * H - macro_area, 1.0)
        rt = routing(d, t, a, cells, free, macro_pins, halo, band, span, arrangement, insts)
        grew += 1
    if grew:
        notes.append(f'logic band grown to {band:.1f} um for routing (target {a.target:g} %)')
    wl_std, dem_h, dem_v, sup_h, sup_v, uh, uv = rt
    die = [0, 0, grid(cx0 + W + cx0, mg), grid(cy0 + H + cy0, mg)]
    worst = max(uh, uv)
    verdict = 'ok' if worst <= 50 else 'tight' if worst <= 70 else 'over'
    # IO: port bits at 2 tracks (met2 / met3) each around the die
    pbits = d['synth'].get('port_bits', 0)
    pitch_io = 2 * max((l['pitch_um'] for l in t['routing_layers'] if l['layer'] in ('met2', 'met3')), default=0.68)
    io_need = pbits * pitch_io
    io_have = 2 * (die[2] + die[3])
    if io_need > io_have:
        notes.append(f'IO: {pbits} port bits need {io_need:.0f} um of edge, die perimeter {io_have:.0f} um')
    eff_util = 100 * std / free
    return {'util_target': util, 'aspect': ar, 'arrangement': arrangement if insts else 'none',
            'core_um': [round(W, 3), round(H, 3)], 'die_area': die, 'die_area_um2': round(die[2] * die[3], 1),
            'logic_band_um': round(band, 2), 'effective_util_pct': round(eff_util, 2),
            'macro_placement': place, 'blockage_sides': sides_block if insts else [],
            'routing': {'wl_std_um': round(wl_std), 'macro_pin_nets': macro_pins,
                        'demand_h_um': round(dem_h), 'demand_v_um': round(dem_v),
                        'supply_h_um': round(sup_h), 'supply_v_um': round(sup_v),
                        'util_h_pct': round(uh, 1), 'util_v_pct': round(uv, 1)},
            'io': {'port_bits': pbits, 'edge_needed_um': round(io_need), 'perimeter_um': round(io_have)},
            'verdict': verdict, 'notes': notes,
            'uc': {'fp(oss,fp,die_area)': '{%s}' % ' '.join(f'{v:g}' for v in die),
                   'fp(oss,macro,placement)': '{%s}' % ' '.join(f'{i} {x:g} {y:g} {o}' for i, x, y, o in place) if place else '',
                   'fp(oss,macro,blockage_sides)': '{%s}' % ' '.join(sides_block) if insts else '{}'}}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('inputs')
    ap.add_argument('--util', default='30,45,60', help='std-cell utilization targets %% of the logic area')
    ap.add_argument('--aspect', default='0.5,1,2', help='core H/W targets')
    ap.add_argument('--k', type=float, default=1.5, help='wirelength factor (calibrate from probe runs)')
    ap.add_argument('--min-band-rows', type=int, default=20, help='minimum logic band height in rows')
    ap.add_argument('--target', type=float, default=50.0, help='routing utilization %% the logic band is sized for')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    with open(a.inputs) as f:
        d = json.load(f)
    arrs = ['bottom_row', 'left_column'] if any(m.get('size') for m in d['macros']) else ['none']
    cands = [candidate(d, float(u), float(r), arr, a) for u in a.util.split(',') for r in a.aspect.split(',') for arr in arrs]
    order = {'ok': 0, 'tight': 1, 'over': 2}
    pin_bad = lambda c: sum('do not face' in n for n in c['notes'])
    cands.sort(key=lambda c: (order[c['verdict']], pin_bad(c), c['die_area_um2']))
    doc = {'block': d['block'], 'phase': d['phase'], 'model': {'k': a.k, 'min_band_rows': a.min_band_rows},
           'candidates': cands}
    out = json.dumps(doc, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(out + '\n')
    else:
        print(out)
    print(f"{'#':>2} {'arrangement':<12} {'util':>5} {'ar':>4} {'die um':>20} {'band':>7} {'H%':>6} {'V%':>6} verdict notes", file=sys.stderr)
    for n, c in enumerate(cands[:12]):
        print(f"{n:>2} {c['arrangement']:<12} {c['util_target']:>5g} {c['aspect']:>4g} {c['die_area'][2]:>9g}x{c['die_area'][3]:<10g} "
              f"{c['logic_band_um']:>7g} {c['routing']['util_h_pct']:>6} {c['routing']['util_v_pct']:>6} {c['verdict']} {'; '.join(c['notes'])[:60]}",
              file=sys.stderr)


if __name__ == '__main__':
    main()
