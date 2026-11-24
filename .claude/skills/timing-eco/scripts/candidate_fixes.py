#!/usr/bin/env python3
"""Legal timing-ECO candidates for the violating paths of a timing_summary.py JSON.

    candidate_fixes.py <summary.json> [--max-per-path N] [-o out.json]

Context it reads (all from the summary's source; nothing is written but the JSON):
  * the STA run's resolved node config (work/STA/<timing node>/run/config.tcl):
    the liberty files (cell names, areas, dont_use), the tech dont_use lists
    (tech(<track>,dont_use_pnr)), delay / hold-buffer cells
    (tech(<track>,delay_cells|hold_buffers)), buffers (tech(<track>,clock_buffers)
    are excluded from data-path fixes) and the Vt patterns (tech(vt_pattern,*),
    project(vt_flavors));
  * the released netlist (<release_dir>/netlist/<design>.v): the net on every
    instance pin and each net's fanout.

Candidates per violating path (ECO change-file syntax of the open-source ECO
flow, eco(oss,changes,allowed)):
  setup  upsize   replace_cell <inst> <same family, next drive>   (largest stage delay first)
         vt_swap  replace_cell <inst> <same function, faster Vt>  (when several Vts are allowed)
         buffer   eco_insert_buffer <buffer> <net>                (driver net with fanout >= --fanout)
  hold   delay    eco_insert_buffer <delay cell> <net> <endpoint pin>
Each candidate carries the stage delay / fanout that motivated it; the skill
(Claude) picks a minimal set under the caps.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
from fnmatch import fnmatch

LIB_CELL_RE = re.compile(r'^\s*cell\s*\(\s*"?([^")\s]+)"?\s*\)')
DONT_USE_RE = re.compile(r'^\s*dont_use\s*:\s*true', re.I)
AREA_RE = re.compile(r'^\s*area\s*:\s*([\d.]+)')
SET_RE = re.compile(r'^\s*set\s+(\S+)\s+(?:"([^"]*)"|\{([^}]*)\}|(\S+))')
INST_RE = re.compile(r'^\s*(\S+)\s+(\\\S+\s|\S+)\s*\((.*?)\);', re.S)
CONN_RE = re.compile(r'\.(\w+)\s*\(\s*([^()]*?)\s*\)')
CELL_RE = re.compile(r'^(.*__)?(.+?)_(\d+)$')


def resolved_config(run_dir, cfg_path):
    """{'tech(<key>)': value, 'project(<key>)': value} of a node config,
    evaluated by tclsh under the run's environment (.run.cbflow.env) — the
    node config sources the whole config cascade."""
    dump = (f'source {{{cfg_path}}}\n'
            'foreach a {tech project} { if {[array exists $a]} { foreach k [array names $a] '
            '{ puts "$a\\($k\\)\\t[string map [list \\n { }] [set ${a}($k)]]" } } }\n')
    env = os.path.join(run_dir, '.run.cbflow.env')
    r = subprocess.run(['bash', '-c', f'set -a; source "{env}"; set +a; cd "{run_dir}"; tclsh'],
                       input=dump, capture_output=True, text=True)
    out = {}
    for ln in r.stdout.splitlines():
        k, sep, v = ln.partition('\t')
        if sep and (k.startswith('tech(') or k.startswith('project(')):
            out[k] = v
    if not out:
        sys.exit(f'candidate_fixes: could not evaluate {cfg_path}: {r.stderr.strip()[-400:]}')
    return out


def liberty_cells(paths):
    """{cell: {'area', 'dont_use'}} over the liberty files."""
    cells = {}
    for p in paths:
        cur = None
        with open(p, errors='replace') as f:
            for ln in f:
                m = LIB_CELL_RE.match(ln)
                if m:
                    cur = m.group(1)
                    cells.setdefault(cur, {'area': None, 'dont_use': False})
                    continue
                if cur is None:
                    continue
                if DONT_USE_RE.match(ln):
                    cells[cur]['dont_use'] = True
                else:
                    a = AREA_RE.match(ln)
                    if a and cells[cur]['area'] is None:
                        cells[cur]['area'] = float(a.group(1))
    return cells


def netlist_pins(path):
    """({inst: {pin: net}}, {net: fanout}) from a structural Verilog netlist."""
    pins, fanout = {}, {}
    if not os.path.isfile(path):
        return pins, fanout
    with open(path, errors='replace') as f:
        text = f.read()
    for stmt in text.split(';'):
        stmt = stmt.strip()
        if '(' not in stmt or stmt.startswith(('module', 'input', 'output', 'wire', 'inout', 'assign', '//')):
            continue
        head, _, body = stmt.partition('(')
        parts = head.split()
        if len(parts) < 2:
            continue
        inst = parts[1].lstrip('\\').strip()
        conns = {pn: nt.strip().lstrip('\\').strip() for pn, nt in CONN_RE.findall('(' + body)}
        if not conns:
            continue
        pins[inst] = conns
        for pn, nt in conns.items():
            if nt:
                fanout[nt] = fanout.get(nt, 0) + 1
    # fanout counted every pin on the net, the driver included
    return pins, {n: c - 1 for n, c in fanout.items()}


def parts(cell):
    m = CELL_RE.match(cell)
    return ((m.group(1) or '') + m.group(2), int(m.group(3))) if m else (cell, None)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('summary', help='timing_summary.py JSON')
    ap.add_argument('--max-per-path', type=int, default=4)
    ap.add_argument('--fanout', type=int, default=8, help='buffer candidates for driver nets with at least this fanout')
    ap.add_argument('--slow-stage', type=float, default=0.5,
                    help='buffer candidates for a driver stage at least this slow (ns) that cannot be upsized')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    with open(a.summary) as f:
        s = json.load(f)
    src = s['source']
    if src.get('kind') != 'run':
        sys.exit('candidate_fixes: needs a summary of an STA run (its config gives the libraries)')
    cfgs = sorted(glob.glob(os.path.join(src['dir'], 'work', 'STA', '*', 'run', 'config.tcl')))
    cfg_path = next((c for c in cfgs if '/timing' in c), cfgs[0] if cfgs else '')
    if not cfg_path:
        sys.exit(f"candidate_fixes: no node config under {src['dir']}/work/STA/*/run/")
    cfg = resolved_config(src['dir'], cfg_path)
    # standard-cell timing libraries: tech(<track>,lib,<lib_set>,timing)
    libs = sorted({v for k, v in cfg.items()
                   if re.match(r'tech\(\w+,lib,[^,]+,timing\)$', k) and os.path.isfile(v)})
    cells = liberty_cells(libs)
    # post-route dont_use (the PNR list: the synthesis list bans the clock /
    # delay cells CTS and hold fixing use)
    dont = [p for k, v in cfg.items() if re.match(r'tech\(\w+,dont_use_pnr\)$', k) for p in v.split()]
    clock_cells = {c for k, v in cfg.items() if re.match(r'tech\(\w+,clock_(buffers|inverters)\)$', k) for c in v.split()}
    delay_cells = [c for k, v in cfg.items() if re.match(r'tech\(\w+,(delay_cells|hold_buffers)\)$', k) for c in v.split()]
    vt_pat = {k[len('tech(vt_pattern,'):-1]: v for k, v in cfg.items() if k.startswith('tech(vt_pattern,')}
    vt_ok = cfg.get('project(vt_flavors)', '').split()

    def legal(c):
        return c in cells and not cells[c]['dont_use'] and not any(fnmatch(c, p) for p in dont)

    def vt_of(c):
        return next((v for v, p in vt_pat.items() if fnmatch(c, p)), '')

    families = {}
    for c in cells:
        fam, drv = parts(c)
        if drv is not None and legal(c):
            families.setdefault(fam, []).append((drv, c))
    for fam in families:
        families[fam].sort()
    buffers = [c for d, c in families.get(next((f for f in families if f.endswith('__buf')), ''), [])]
    delay_cells = [c for c in delay_cells if legal(c)] or \
        [c for f, l in families.items() if 'dlygate' in f or 'dlymetal' in f for d, c in l]

    netlist = os.path.join(src.get('release_dir', ''), 'netlist', f"{src.get('design', '')}.v")
    pins, fanout = netlist_pins(netlist)

    out = {'source': src, 'context': {'config': cfg_path, 'liberty': libs, 'netlist': netlist,
                                      'dont_use': dont, 'buffers': buffers, 'delay_cells': delay_cells,
                                      'vt_flavors': vt_ok}, 'paths': []}
    for i, p in enumerate(s['paths']):
        if p['slack'] >= 0:
            continue
        cands = []
        if p['check'] == 'setup':
            seen = set()
            for st in sorted(p['stages'], key=lambda x: -x['delay']):
                inst, cell = st['inst'], st['cell']
                if inst in seen or cell not in cells or cell in clock_cells or st['delay'] <= 0:
                    continue
                seen.add(inst)
                fam, drv = parts(cell)
                bigger = [c for d, c in families.get(fam, []) if drv is not None and d > drv]
                if bigger:
                    cands.append({'fix': 'upsize', 'inst': inst, 'from': cell, 'to': bigger[0],
                                  'stage_delay': st['delay'], 'cmd': f'replace_cell {inst} {bigger[0]}'})
                if len(vt_ok) > 1 and vt_pat:
                    cur = vt_of(cell)
                    for v in vt_ok:
                        if v == cur:
                            continue
                        alt = [c for c in cells if legal(c) and vt_of(c) == v and parts(c)[1] == drv
                               and parts(c)[0].split('__')[-1] == fam.split('__')[-1]]
                        if alt:
                            cands.append({'fix': 'vt_swap', 'inst': inst, 'from': cell, 'to': alt[0],
                                          'stage_delay': st['delay'], 'cmd': f'replace_cell {inst} {alt[0]}'})
                outs = [n for pn, n in pins.get(inst, {}).items() if pn in ('X', 'Y', 'Q', 'Q_N', 'Z')]
                if st['pin'] in pins.get(inst, {}):
                    outs = [pins[inst][st['pin']]]       # the output pin on this path
                for net in outs:
                    slow = st['delay'] >= a.slow_stage and not bigger
                    if (fanout.get(net, 0) >= a.fanout or slow) and buffers:
                        cands.append({'fix': 'buffer', 'inst': inst, 'net': net, 'fanout': fanout.get(net, 0),
                                      'reason': 'high fanout' if fanout.get(net, 0) >= a.fanout else 'slow stage, no larger drive',
                                      'stage_delay': st['delay'],
                                      'cmd': f'eco_insert_buffer {buffers[len(buffers) // 2]} {net}'})
        else:
            end = p['stages'][-1] if p['stages'] else None
            if end and delay_cells:
                net = pins.get(end['inst'], {}).get(end['pin'], '')
                if net:
                    cands.append({'fix': 'delay', 'inst': end['inst'], 'pin': end['pin'], 'net': net,
                                  'cell': delay_cells[0],
                                  'cmd': f"eco_insert_buffer {delay_cells[0]} {net} {end['inst']}/{end['pin']}"})
        out['paths'].append({'index': i, 'scenario': p['scenario'], 'check': p['check'], 'slack': p['slack'],
                             'startpoint': p.get('startpoint'), 'endpoint': p.get('endpoint'),
                             'candidates': cands[:a.max_per_path]})
    doc = json.dumps(out, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(doc + '\n')
    else:
        print(doc)


if __name__ == '__main__':
    main()
