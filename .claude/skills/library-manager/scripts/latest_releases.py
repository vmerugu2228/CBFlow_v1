#!/usr/bin/env python3
"""Latest implementation release of every block of a project's hierarchy
(read-only) — what `library-manager add --category block` should take.

    python3 latest_releases.py --project opensky [--blocks gcd ctrl_subsys] [--json out.json]

A block's candidates are <release,path>/<phase>/<block>/<FLOW>/<tag>/RELEASE_COMPLETE
for the implementation flows (PNR, ECO, SYNTH_PNR). The latest is the newest
phase (project(phases) order), then the latest exit of MILESTONE_ORDER, an ECO of
an exit (<EXIT>_ECO<n>) above the exit itself (higher n first). Reported per
block: the release, its PV sibling (<phase>/<block>/PV/<tag> — gds / cdl come
from it; absent -> add --pv-pending), the SPEF corners it carries, and the
`add` command. The top of the hierarchy (no parent) is not a library block.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
IMPL_FLOWS = ['PNR', 'ECO', 'SYNTH_PNR']


def project_values(project):
    """phases, release path, hierarchy {block: {parent, children, level}} and
    MILESTONE_ORDER, read by tclsh from the project configs."""
    g = os.path.join(ROOT, 'global', 'config', 'project', project, 'v1.0.0', f'{project}_config.tcl')
    pd = os.path.join(ROOT, 'PD', 'config', 'project', project, 'v1.0.0', f'{project}_pd_config.tcl')
    rc = os.path.join(ROOT, 'PD', 'config', 'flow', 'v1.0.0', 'release_config.tcl')
    script = f'''
foreach f {{{g} {pd}}} {{ if {{[file exists $f]}} {{ source $f }} }}
set MILESTONE_ORDER {{}}
set fh [open {{{rc}}}]; set t [read $fh]; close $fh
regexp {{set MILESTONE_ORDER \\{{([^}}]*)\\}}}} $t -> MILESTONE_ORDER
puts "phases\\t$project(phases)"
puts "release\\t$project(release,path)"
puts "order\\t$MILESTONE_ORDER"
dict for {{b d}} $project(design_hierarchy) {{
    puts "block\\t$b\\t[dict get $d parent]\\t[dict get $d children]\\t[dict get $d level]"
}}
'''
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f'latest_releases: cannot read the {project} config: {r.stderr.strip()}')
    out = {'blocks': {}}
    for line in r.stdout.splitlines():
        f = line.split('\t')
        if f[0] == 'block':
            out['blocks'][f[1]] = {'parent': f[2], 'children': f[3].split(), 'level': f[4]}
        else:
            out[f[0]] = f[1].split() if f[0] in ('phases', 'order') else f[1]
    return out


def rank(tag, order):
    """Sort key of a release tag within a phase: exit index, ECO number."""
    m = re.match(r'^(.*?)(?:_ECO(\d+))?$', tag)
    base, eco = m.group(1), int(m.group(2) or 0)
    return (order.index(base) if base in order else -1, eco)


def latest(cfg, block):
    rel = cfg['release']
    best = None
    for pi, ph in enumerate(cfg['phases']):
        for fl in IMPL_FLOWS:
            for d in glob.glob(os.path.join(rel, ph, block, fl, '*', 'RELEASE_COMPLETE')):
                tag = os.path.basename(os.path.dirname(d))
                key = (pi, rank(tag, cfg['order']), os.path.getmtime(d))
                if best is None or key > best[0]:
                    best = (key, ph, fl, tag, os.path.dirname(d))
    if not best:
        return None
    _, ph, fl, tag, path = best
    pv = os.path.join(rel, ph, block, 'PV', tag)
    spefs = sorted(os.path.basename(f)[len(block) + 1:-5]
                   for f in glob.glob(os.path.join(path, 'spef', f'{block}_*.spef')))
    return {'phase': ph, 'flow': fl, 'tag': tag, 'path': path,
            'pv': os.path.isfile(os.path.join(pv, 'RELEASE_COMPLETE')), 'pv_path': pv,
            'spef_corners': spefs}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--project', required=True)
    ap.add_argument('--blocks', nargs='*')
    ap.add_argument('--json')
    a = ap.parse_args()
    cfg = project_values(a.project)
    blocks = a.blocks or [b for b, d in cfg['blocks'].items() if d['parent']]
    res = {}
    print(f"{'block':<14} {'level':<5} {'latest release':<34} {'PV':<4} spef")
    for b in blocks:
        if b not in cfg['blocks']:
            sys.exit(f'latest_releases: {b} is not in project(design_hierarchy)')
        r = latest(cfg, b)
        res[b] = r
        if not r:
            print(f"{b:<14} {cfg['blocks'][b]['level']:<5} {'(no implementation release)':<34}")
            continue
        print(f"{b:<14} {cfg['blocks'][b]['level']:<5} {r['phase'] + '/' + r['flow'] + '/' + r['tag']:<34} "
              f"{'yes' if r['pv'] else 'no':<4} {' '.join(r['spef_corners']) or '-'}")
    with_pv = [r['path'] for r in res.values() if r and r['pv']]
    no_pv = [r['path'] for r in res.values() if r and not r['pv']]
    print('\nadd commands (tag <TAG>):')
    if with_pv:
        print('  cbflow flow library-manager add --tech <tech> --tag <TAG> --project %s --category block --path %s'
              % (a.project, ' '.join(with_pv)))
    if no_pv:
        print('  cbflow flow library-manager add --tech <tech> --tag <TAG> --project %s --category block --pv-pending --path %s'
              % (a.project, ' '.join(no_pv)))
    if a.json:
        json.dump({'project': a.project, 'blocks': res}, open(a.json, 'w'), indent=1)


if __name__ == '__main__':
    main()
