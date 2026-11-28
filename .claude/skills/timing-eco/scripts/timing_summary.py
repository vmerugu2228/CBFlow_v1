#!/usr/bin/env python3
"""Timing summary of an open-source STA run (or STA release) for the timing-eco skill.

    timing_summary.py <sta_run_dir | sta_release_dir> [--paths N] [-o out.json]

Reads, per MMMC scenario:
  run:     work/STA/<timing node>/<scenario>/reports/{qor.tcl,setup.rpt,hold.rpt,drv.rpt}
  release: reports/sta/<scenario>/{setup.rpt,hold.rpt,drv.rpt} (+ sta_summary.rpt)
and, for a run, its input binding from setup/user_config.tcl and
setup/resolved_inputs.tcl — the release the STA timed, which the ECO must
start from.

Writes one JSON document (stdout or -o):
  source     {kind, dir, design, phase, lib_tag, release_tag, release_dir}
  scenarios  [{name, wns_setup, tns_setup, nvp_setup, wns_hold, ..., drv}]
  worst      {setup: {wns, scenario}, hold: {...}}
  paths      [{scenario, check, slack, startpoint, endpoint, group,
               launch_clock, capture_clock, arrival, required,
               stages: [{inst, pin, cell, delay, time, edge}]}]
             the N worst violating paths per scenario and check
  cells      {inst: {cell, family, drive, paths, worst_slack, max_delay}}
Read-only: never writes anything but the JSON.
"""
import argparse
import glob
import json
import os
import re
import sys

STAGE_RE = re.compile(r'^\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+([v^])\s+(\S+)\s+\((\S+)\)\s*$')
SLACK_RE = re.compile(r'^\s*(-?\d+\.\d+)\s+slack\s+\((MET|VIOLATED)\)')
TIME_RE = re.compile(r'^\s*(-?\d+\.\d+)\s+data (arrival|required) time')
CLOCK_RE = re.compile(r'clocked by (\S+?)\)')
QOR_RE = re.compile(r'^set qor\((\w+)\)\s+"?([^"]*)"?\s*$')
SET_RE = re.compile(r'^\s*set\s+(\S+)\s+(?:"([^"]*)"|(\S+))')
CELL_RE = re.compile(r'^(.*__)?(.+?)_(\d+)$')


def read_tcl_sets(path):
    """{var: value} of the simple `set var value` lines of a Tcl file."""
    out = {}
    if not os.path.isfile(path):
        return out
    with open(path, errors='replace') as f:
        for line in f:
            m = SET_RE.match(line)
            if m:
                out[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
    return out


def cell_parts(cell):
    """(family, drive) of a std cell: sky130_fd_sc_hd__maj3_1 -> (sky130_fd_sc_hd__maj3, 1)."""
    m = CELL_RE.match(cell)
    if not m:
        return cell, None
    return (m.group(1) or '') + m.group(2), int(m.group(3))


def parse_paths(rpt, scenario, check):
    """Paths of a report_checks -format full_clock_expanded report."""
    paths = []
    if not os.path.isfile(rpt):
        return paths
    with open(rpt, errors='replace') as f:
        text = f.read()
    for block in re.split(r'\n(?=Startpoint:)', text):
        if not block.startswith('Startpoint:'):
            continue
        p = {'scenario': scenario, 'check': check, 'stages': []}
        lines = block.splitlines()
        for ln in lines[:6]:
            if ln.startswith('Startpoint:'):
                p['startpoint'] = ln.split()[1]
                m = CLOCK_RE.search(ln)
                p['launch_clock'] = m.group(1) if m else ''
            elif ln.startswith('Endpoint:'):
                p['endpoint'] = ln.split()[1]
                m = CLOCK_RE.search(ln)
                p['capture_clock'] = m.group(1) if m else ''
            elif ln.startswith('Path Group:'):
                p['group'] = ln.split(':', 1)[1].strip()
        # data path: from the startpoint's output pin to the data arrival line
        in_data = False
        for ln in lines:
            t = TIME_RE.match(ln)
            if t:
                p['arrival' if t.group(2) == 'arrival' else 'required'] = float(t.group(1))
                if t.group(2) == 'arrival':
                    in_data = False
                continue
            s = SLACK_RE.match(ln)
            if s:
                p['slack'] = float(s.group(1))
                continue
            m = STAGE_RE.match(ln)
            if not m or 'required' in p:
                continue
            delay, time, edge, pinpath, cell = m.groups()
            inst, _, pin = pinpath.rpartition('/')
            if not in_data and inst == p.get('startpoint'):
                in_data = True            # launch flop (CLK and Q / output pin)
            if in_data and inst:
                p['stages'].append({'inst': inst, 'pin': pin, 'cell': cell,
                                    'delay': float(delay), 'time': float(time), 'edge': edge})
        if 'slack' in p:
            paths.append(p)
    return paths


def drv_counts(rpt):
    """Violation counts per DRV section of a report_check_types -violators report."""
    out = {}
    if not os.path.isfile(rpt):
        return out
    sec = None
    with open(rpt, errors='replace') as f:
        for ln in f:
            low = ln.strip().lower()
            if low.startswith('max slew') or low.startswith('max transition'):
                sec = 'max_tran'
            elif low.startswith('max capacitance'):
                sec = 'max_cap'
            elif low.startswith('max fanout'):
                sec = 'max_fanout'
            elif sec and '(violated)' in low:
                out[sec] = out.get(sec, 0) + 1
    return out


def locate(target):
    """(kind, {scenario: reports dir}, qor files available)."""
    target = os.path.abspath(target)
    runs = sorted(glob.glob(os.path.join(target, 'work', 'STA', '*', '*', 'reports', 'setup.rpt')))
    if runs:
        return 'run', {os.path.basename(os.path.dirname(os.path.dirname(r))): os.path.dirname(r) for r in runs}
    rel = sorted(glob.glob(os.path.join(target, 'reports', 'sta', '*', 'setup.rpt')))
    if rel:
        return 'release', {os.path.basename(os.path.dirname(r)): os.path.dirname(r) for r in rel}
    sys.exit(f'timing_summary: no STA reports under {target} '
             '(expected work/STA/<node>/<scenario>/reports/ or reports/sta/<scenario>/)')


def source_info(target, kind):
    info = {'kind': kind, 'dir': os.path.abspath(target)}
    if kind == 'run':
        uc = read_tcl_sets(os.path.join(target, 'setup', 'user_config.tcl'))
        ri = read_tcl_sets(os.path.join(target, 'setup', 'resolved_inputs.tcl'))
        info.update({'design': uc.get('flow(design_name)', ''), 'phase': uc.get('project(phase)', ''),
                     'lib_tag': uc.get('project(lib_config_tag)', ''),
                     'release_tag': uc.get('sta(input,release_tag)', '')})
        anyp = next((v for k, v in ri.items() if k.startswith('sta(input,') and v), '')
        if anyp:   # <release_dir>/<category>/<file>
            info['release_dir'] = os.path.dirname(os.path.dirname(anyp))
        info['resolved_inputs'] = {k: v for k, v in ri.items() if k.startswith('sta(input,')}
    else:
        parts = os.path.abspath(target).rstrip('/').split(os.sep)
        info.update({'release_tag': parts[-1], 'design': parts[-3], 'phase': parts[-4]})
    return info


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('target', help='STA run directory or STA release directory')
    ap.add_argument('--paths', type=int, default=10, help='worst violating paths kept per scenario and check (0 = all; use 0 for the ECO gate)')
    ap.add_argument('--all-paths', action='store_true', help='keep met paths too (default: violating only)')
    ap.add_argument('-o', '--output', help='write the JSON here (default stdout)')
    a = ap.parse_args()

    kind, scen_dirs = locate(a.target)
    doc = {'source': source_info(a.target, kind), 'scenarios': [], 'paths': [], 'cells': {}}
    worst = {'setup': {'wns': None, 'scenario': ''}, 'hold': {'wns': None, 'scenario': ''}}
    for scen, d in sorted(scen_dirs.items()):
        q = {}
        if os.path.isfile(os.path.join(d, 'qor.tcl')):
            with open(os.path.join(d, 'qor.tcl'), errors='replace') as f:
                for ln in f:
                    m = QOR_RE.match(ln)
                    if m:
                        q[m.group(1)] = m.group(2)
        row = {'name': scen}
        for k in ('wns_setup', 'tns_setup', 'nvp_setup', 'wns_hold', 'tns_hold', 'nvp_hold',
                  'max_tran_violations', 'max_cap_violations', 'max_fanout_violations'):
            if k in q:
                try:
                    row[k] = float(q[k]) if '.' in q[k] or 'e' in q[k].lower() else int(q[k])
                except ValueError:
                    row[k] = q[k]
        row['drv'] = drv_counts(os.path.join(d, 'drv.rpt'))
        for check, rpt in (('setup', 'setup.rpt'), ('hold', 'hold.rpt')):
            ps = parse_paths(os.path.join(d, rpt), scen, check)
            if ps and f'wns_{check}' not in row:
                row[f'wns_{check}'] = min(p['slack'] for p in ps)
            w = row.get(f'wns_{check}')
            if w is not None and (worst[check]['wns'] is None or w < worst[check]['wns']):
                worst[check] = {'wns': w, 'scenario': scen}
            keep = [p for p in ps if a.all_paths or p['slack'] < 0]
            keep.sort(key=lambda p: p['slack'])
            doc['paths'].extend(keep[:a.paths] if a.paths > 0 else keep)
        doc['scenarios'].append(row)
    doc['worst'] = worst
    for p in doc['paths']:
        for s in p['stages']:
            fam, drv = cell_parts(s['cell'])
            c = doc['cells'].setdefault(s['inst'], {'cell': s['cell'], 'family': fam, 'drive': drv,
                                                   'paths': 0, 'worst_slack': p['slack'], 'max_delay': 0.0})
            c['paths'] += 1
            c['worst_slack'] = min(c['worst_slack'], p['slack'])
            c['max_delay'] = max(c['max_delay'], s['delay'])
    out = json.dumps(doc, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(out + '\n')
    else:
        print(out)


if __name__ == '__main__':
    main()
