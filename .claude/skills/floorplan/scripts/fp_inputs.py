#!/usr/bin/env python3
"""Floorplan inputs of a CBflow block (open-source flow) for the floorplan skill.

    fp_inputs.py <block> [--phase P1] [--uc <uc_FP_*.tcl>] [--fp-run <FP run dir>] [-o out.json]

Collects (read-only):
  uc        the block's FP user_config (workarea/<block>/uc_FP_openroad_<phase>.tcl,
            else uc_FP_openroad.tcl): SYNTH release tag, lib tag, current FP keys
  synth     the SYNTH release's synthesis_stat.rpt: std-cell area / cells /
            ports / port bits, child-module and memory instances (area unknown
            in yosys -> sized from LEFs), register arrays (synthesis_memory.rpt)
  netlist   instance names of each child block / memory macro
  macros    every hard macro: master, instance(s), size (LEF SIZE), pin sides
            (which edges its signal pins sit on), whether it is a DL2 block
            (has children -> rail-pitch snapping)
  hier      project(design_hierarchy) entry: level, parent, children
  tech      site width, row height, manufacturing grid, routing layers with
            direction + pitch (tracks file + tech LEF), PDN straps, rail pitch,
            FP defaults (core margin, halo, macro channel) — the resolved
            config of an FP run of the project (tclsh under its run env)
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
SET_RE = re.compile(r'^\s*set\s+(\S+)\s+(?:"([^"]*)"|\{([^}]*)\}|(\S+))')


def tcl_sets(path):
    out = {}
    if path and os.path.isfile(path):
        with open(path, errors='replace') as f:
            for ln in f:
                m = SET_RE.match(ln)
                if m:
                    out[m.group(1)] = next(g for g in m.groups()[1:] if g is not None)
    return out


def resolved(run_dir, node, arrays=('tech', 'project', 'fp')):
    """Arrays of an FP node config, evaluated by tclsh under the run's env."""
    cfg = os.path.join(run_dir, 'work', 'FP', node, 'run', 'config.tcl')
    dump = (f'source {{{cfg}}}\n'
            f'foreach a {{{" ".join(arrays)}}} {{ if {{[array exists $a]}} {{ foreach k [array names $a] '
            '{ puts "$a\\($k\\)\\t[string map [list \\n { }] [set ${a}($k)]]" } } }\n')
    r = subprocess.run(['bash', '-c', f'set -a; source "{run_dir}/.run.cbflow.env"; set +a; cd "{run_dir}"; tclsh'],
                       input=dump, capture_output=True, text=True)
    out = {}
    for ln in r.stdout.splitlines():
        k, sep, v = ln.partition('\t')
        if sep:
            out[k] = v
    if not out:
        sys.exit(f'fp_inputs: could not evaluate {cfg}: {r.stderr.strip()[-300:]}')
    return out


def tcl_list(s):
    """Parse a Tcl list (braces / quotes) into Python strings, one level."""
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
        elif s[i] == '"':
            j = s.index('"', i + 1); out.append(s[i + 1:j]); i = j + 1
        else:
            j = i
            while j < n and not s[j].isspace():
                j += 1
            out.append(s[i:j]); i = j
    return out


def tcl_dict(s):
    l = tcl_list(s)
    return dict(zip(l[0::2], l[1::2]))


def lef_macro(path, name=None):
    """{name, size:[w,h], pin_sides:{side: n}, pins:[...]} of a LEF macro."""
    out = {'lef': path, 'size': None, 'pin_sides': {}, 'pins': 0}
    if not path or not os.path.isfile(path):
        return out
    with open(path, errors='replace') as f:
        t = f.read()
    blocks = re.findall(r'^MACRO\s+(\S+)(.*?)^END\s+\1', t, re.S | re.M)
    for mname, body in blocks:
        if name and mname != name:
            continue
        out['name'] = mname
        m = re.search(r'^\s*SIZE\s+([\d.]+)\s+BY\s+([\d.]+)', body, re.M)
        if m:
            out['size'] = [float(m.group(1)), float(m.group(2))]
        w, h = out['size'] or (0, 0)
        for pname, pbody in re.findall(r'^\s*PIN\s+(\S+)(.*?)^\s*END\s+\1', body, re.S | re.M):
            if re.search(r'USE\s+(POWER|GROUND)', pbody):
                continue
            r = re.search(r'RECT\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)', pbody)
            if not r or not w:
                continue
            x0, y0, x1, y1 = (float(v) for v in r.groups())
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            d = {'left': cx, 'right': w - cx, 'bottom': cy, 'top': h - cy}
            side = min(d, key=d.get)
            out['pin_sides'][side] = out['pin_sides'].get(side, 0) + 1
            out['pins'] += 1
        break
    return out


def synth_stat(path, design):
    s = {'report': path}
    if not os.path.isfile(path):
        return s
    with open(path, errors='replace') as f:
        t = f.read()
    sec = t.split(f'=== {design} ===', 1)[-1]
    for key, pat in (('ports', r'(\d+)\s+-\s+ports'), ('port_bits', r'(\d+)\s+-\s+port bits'),
                     ('wires', r'(\d+)\s+-\s+wires')):
        m = re.search(pat, sec)
        if m:
            s[key] = int(m.group(1))
    m = re.search(r'(\d+)\s+([\d.E+]+)\s+cells', sec)
    if m:
        s['cells'] = int(m.group(1))
    m = re.search(r"Chip area for module '\\?%s':\s*([\d.]+)" % re.escape(design), sec)
    if m:
        s['std_area_um2'] = float(m.group(1))
    # cell list (after the "cells" line): "<count> <area> <type>", or
    # "<count> - <child module>" for a child block (area unknown to yosys)
    s['children'] = {}
    s['macro_cells'] = {}
    cl = sec.split(' cells', 1)[-1].split('Chip area', 1)[0]
    for cnt, area, ctype in re.findall(r'^\s+(\d+)\s+(\S+)\s+(\S+)\s*$', cl, re.M):
        if area == '-':
            s['children'][ctype] = int(cnt)
        elif 'sram' in ctype or 'macro' in ctype:
            s['macro_cells'][ctype] = int(cnt)
    return s


def netlist_insts(path, masters):
    """{master: [instance names]} for the given masters in a Verilog netlist."""
    out = {m: [] for m in masters}
    if not masters or not os.path.isfile(path):
        return out
    with open(path, errors='replace') as f:
        t = f.read()
    for m in masters:
        out[m] = [i.lstrip('\\') for i in re.findall(r'^\s*\\?%s\s+(\\?\S+)\s*\(' % re.escape(m), t, re.M)]
    return out


def tracks(path):
    """{layer: {dir_axis: (offset, pitch)}} from a tracks file (layer X|Y offset pitch)."""
    out = {}
    if path and os.path.isfile(path):
        with open(path) as f:
            for ln in f:
                p = ln.split()
                if len(p) >= 4:
                    out.setdefault(p[0], {})[p[1]] = [float(p[2]), float(p[3])]
    return out


def lef_dirs(path):
    out = {}
    if path and os.path.isfile(path):
        with open(path, errors='replace') as f:
            t = f.read()
        for lname, body in re.findall(r'^LAYER\s+(\S+)(.*?)^END\s+\1', t, re.S | re.M):
            m = re.search(r'DIRECTION\s+(HORIZONTAL|VERTICAL)', body)
            if m and 'TYPE ROUTING' in body:
                out[lname] = m.group(1)[0]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('block')
    ap.add_argument('--phase', default='')
    ap.add_argument('--uc')
    ap.add_argument('--fp-run', help='FP run whose resolved config gives the tech values (default: newest FP run of the project)')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    wa = os.path.join(ROOT, 'workarea', a.block)
    uc_path = a.uc or next((p for p in (os.path.join(wa, f'uc_FP_openroad_{a.phase}.tcl'), os.path.join(wa, 'uc_FP_openroad.tcl'))
                            if a.phase and os.path.isfile(p) or os.path.isfile(p)), '')
    uc = tcl_sets(uc_path)
    phase = a.phase or uc.get('project(phase)', '')
    # tech / project / fp from a resolved FP run (same tech for every block)
    runs = [a.fp_run] if a.fp_run else sorted(
        glob.glob(os.path.join(ROOT, 'workarea', a.block, f'{phase}_run_FP_*')) +
        glob.glob(os.path.join(ROOT, 'workarea', '*', '*_run_FP_*')), key=os.path.getmtime, reverse=True)
    run = next((r for r in runs if os.path.isfile(os.path.join(r, 'work', 'FP', 'floorplan1', 'run', 'config.tcl'))), '')
    if not run:
        sys.exit('fp_inputs: no FP run with a resolved floorplan1 config found (create one FP run of the project first)')
    cfg = resolved(run, 'floorplan1')
    g = lambda k, d='': cfg.get(k, d)
    stack = g('project(metal_stack)')
    trk = g('tech(track)')
    if not stack or not trk:
        sys.exit('fp_inputs: project(metal_stack) / tech(track) not in the resolved config')
    tfile = g(f'tech({stack},tracks_file)')
    tlef = g(f'tech({stack},{trk},lef_tech)') or g('tech(lef_tech)')
    layers = g(f'tech({stack},metal_layers)').split()
    lo, hi = g(f'tech({stack},min_routing_layer)'), g(f'tech({stack},max_routing_layer)')
    tk, dirs = tracks(tfile), lef_dirs(tlef)
    route = []
    if lo in layers and hi in layers:
        for l in layers[layers.index(lo):layers.index(hi) + 1]:
            d = dirs.get(l, '')
            axis = 'Y' if d == 'H' else 'X'          # horizontal wires stack along Y
            pitch = tk.get(l, {}).get(axis, [0, 0])[1]
            route.append({'layer': l, 'dir': d, 'pitch_um': pitch})
    straps = {k.split(',')[1].rstrip(')'): g(k).split() for k in cfg if re.match(rf'tech\({stack},pdn_strap_[hv]\)', k)}
    rails = g('project(power,rail_nets)').split()
    sh = straps.get('pdn_strap_h', [])
    rail_pitch = (float(sh[2]) / 2) * len(rails) if len(sh) >= 3 and rails else None
    tech = {'site_width': float(g(f'tech({trk},site_width)', 0) or 0), 'row_height': float(g(f'tech({trk},cell_height)', 0) or 0),
            'manufacturing_grid': float(g('tech(manufacturing_grid)', 0) or 0), 'metal_stack': stack,
            'routing_layers': route, 'pdn_straps': straps, 'rail_nets': rails, 'rail_pitch': rail_pitch,
            'pdn_enable': g('project(pdn,enable)'), 'resolved_from': run}
    # FP defaults: the node config itself (not a run's overrides)
    ncfg = os.path.join(ROOT, 'PD', 'config', 'flow', 'v1.0.0', 'node_configs', 'FP_openroad_config.tcl')
    rr = subprocess.run(['tclsh'], input=f'source {{{ncfg}}}\nforeach k [array names fp oss,*] {{ puts "$k\t$fp($k)" }}\n',
                        capture_output=True, text=True)
    fpdef = dict(l.split('\t', 1) for l in rr.stdout.splitlines() if '\t' in l and
                 re.match(r'oss,(fp|macro|pins|probe),', l))
    # hierarchy
    hd = tcl_dict(g('project(design_hierarchy)'))
    he = tcl_dict(hd.get(a.block, ''))
    hier = {'level': he.get('level', ''), 'parent': he.get('parent', ''), 'children': tcl_list(he.get('children', ''))}
    dl2 = {b for b, e in hd.items() if tcl_list(tcl_dict(e).get('children', ''))}
    # SYNTH release
    stag = uc.get('fp(input,release_tag)', '')
    rel = os.path.join(ROOT, 'test_releases', phase, a.block, 'SYNTH', stag)
    synth = synth_stat(os.path.join(rel, 'reports', 'synthesis_stat.rpt'), a.block)
    mem = os.path.join(rel, 'reports', 'synthesis_memory.rpt')
    if os.path.isfile(mem):
        mm = re.search(r'Memories inferred[^:]*:\s*(\d+)', open(mem).read())
        synth['register_arrays'] = int(mm.group(1)) if mm else 0
    netlist = os.path.join(rel, 'netlist', f'{a.block}.v')
    # hard macros: children (lib tag LEF) + memory macros (tech memory LEFs)
    macros = []
    children = list(synth.get('children', {})) or hier.get('children', [])
    insts = netlist_insts(netlist, children + list(synth.get('macro_cells', {})))
    # child views from this block's library tag (its user_config's lib_config_tag)
    tag = uc.get('project(lib_config_tag)', '') or g('project(lib_config_tag)')
    bc = next(iter(glob.glob(os.path.join(g('project(lib_tag_root)'), '*', tag, 'blocks_config.tcl'))), '')
    tagdir = os.path.dirname(bc)
    sub = lambda v: v.replace('$_lib_tag_dir', tagdir).replace('${_lib_tag_dir}', tagdir)
    blk = {k: sub(v) for k, v in tcl_sets(bc).items()}
    libc = {k: sub(v) for k, v in tcl_sets(os.path.join(tagdir, 'lib_config.tcl')).items()}
    _lt = sub(open(os.path.join(tagdir, 'lib_config.tcl')).read()) if os.path.isfile(os.path.join(tagdir, 'lib_config.tcl')) else ''
    _ml = re.search(r'^\s*set\s+tech\(lef,memory\)\s+(.*)$', _lt, re.M)
    mem_lefs = re.findall(r'(/[^\s"\]]+?\.lef)', _ml.group(1)) if _ml else []
    # yosys lists memory macros like child blocks (area unknown): split them
    mem_masters = {os.path.splitext(os.path.basename(l))[0] for l in mem_lefs}
    for mc in [c for c in children if c in mem_masters]:
        synth['macro_cells'][mc] = synth['children'].pop(mc, 1)
        children.remove(mc)
    for c in children:
        lef = blk.get(f'tech(block,{c},lef)', '')
        if not lef:
            print(f'fp_inputs: WARNING: no LEF for child {c} in library tag {tag} ({bc})', file=sys.stderr)
        info = lef_macro(lef, c)
        macros.append({'master': c, 'kind': 'block', 'instances': insts.get(c, []), 'dl2': c in dl2, **info})
    for mc in synth.get('macro_cells', {}):
        lef = next((l for l in mem_lefs if mc in os.path.basename(l)), mem_lefs[0] if mem_lefs else '')
        macros.append({'master': mc, 'kind': 'memory', 'instances': insts.get(mc, []), 'dl2': False, **lef_macro(lef, mc)})
    doc = {'block': a.block, 'phase': phase, 'uc': uc_path, 'lib_tag': tag, 'blocks_config': bc,
           'uc_fp': {k: v for k, v in uc.items() if k.startswith('fp(oss,') or k.startswith('project(pdn')},
           'synth_release': rel, 'synth': synth, 'netlist': netlist, 'hier': hier,
           'macros': macros, 'tech': tech, 'fp_defaults': fpdef}
    out = json.dumps(doc, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(out + '\n')
    else:
        print(out)


if __name__ == '__main__':
    main()
