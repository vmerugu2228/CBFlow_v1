#!/usr/bin/env python3
"""Port compatibility of a library tag's hard blocks with their parents
(read-only).

    python3 port_compat.py --lib-config <lib_tag_root>/<tech>/<TAG>/lib_config.tcl
                           [--parent-netlist <parent>=<netlist.v> ...]

For every block of the tag (tech(blocks)) and every parent netlist that
instantiates it — the tag's own parent blocks (tech(block,<p>,netlist)) plus
any --parent-netlist (e.g. a parent's newest SYNTH / PNR netlist) — the pins the
parent connects (.pin(net)) are compared with the block's ports (its netlist's
module header). A pin the block lacks, or a block port the parent leaves
unconnected, means the block and the parent were built against different
interfaces: the parent must be rebuilt (or the tag must carry the matching
block release). Classes:
  ERROR  the parent connects a pin the block lacks
  ERROR  a block functional input the parent leaves unconnected (floats)
  WARN   a block scan input left unconnected — with --project, ports matching
         its project(dft,scan_in_pattern|scan_enable_pattern): hierarchical scan
         not stitched (DFT), the functional interface agrees
  (unconnected block outputs are fine)
Exit 1 when any ERROR is found.
"""
import argparse
import os
import re
import subprocess
import sys


def tag_values(lib_cfg):
    script = ('source {%s}\nforeach k [lsort [array names tech block,*,netlist]] '
              '{ puts "$k\\t$tech($k)" }\nputs "blocks\\t$tech(blocks)"\n' % lib_cfg)
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f'port_compat: cannot source {lib_cfg}: {r.stderr.strip()}')
    nets, blocks = {}, []
    for line in r.stdout.splitlines():
        k, _, v = line.partition('\t')
        if k == 'blocks':
            blocks = v.split()
        else:
            nets[k.split(',')[1]] = v
    return blocks, nets


def strip(t):
    return re.sub(r'//[^\n]*', '', re.sub(r'/\*.*?\*/', ' ', t, flags=re.S))


def module_ports(netlist, module):
    t = strip(open(netlist, errors='replace').read())
    m = re.search(r'\bmodule\s+' + re.escape(module) + r'\s*(?:#\s*\(.*?\)\s*)?\((.*?)\)\s*;', t, re.S)
    if not m:
        return None
    hdr = m.group(1)
    if re.search(r'\b(input|output|inout)\b', hdr):           # ANSI header
        return set(re.findall(r'([A-Za-z_\\][\w$\\]*)\s*(?:,|$)', re.sub(r'\[[^\]]*\]', '', hdr)))
    return {p.strip() for p in hdr.split(',') if p.strip()}


def instance_pins(netlist, module):
    """{instance: set(pins)} of every instance of module in the netlist."""
    t = strip(open(netlist, errors='replace').read())
    out = {}
    for m in re.finditer(r'(?:^|;)\s*' + re.escape(module) + r'\s+([A-Za-z_\\][^\s(]*)\s*\(', t, re.M):
        depth, i = 1, m.end()
        while depth and i < len(t):
            depth += {'(': 1, ')': -1}.get(t[i], 0)
            i += 1
        conns = re.findall(r'\.\s*([A-Za-z_\\][\w$\\]*)\s*\(\s*([^)]*?)\s*\)', t[m.end():i - 1])
        out[m.group(1)] = {p for p, n in conns}, {p for p, n in conns if n == ''}
    return out


def scan_patterns(project):
    """project(dft,scan_in_pattern|scan_enable_pattern) as regexes (global
    project config + DFT overlay), or [] without a project."""
    if not project:
        return []
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
    files = [os.path.join(root, d, 'config', 'project', project, 'v1.0.0', f)
             for d, f in (('global', f'{project}_config.tcl'), ('DFT', f'{project}_dft_config.tcl'))]
    script = ''.join('if {[file exists {%s}]} { source {%s} }\n' % (f, f) for f in files) + \
        'foreach k {scan_in_pattern scan_enable_pattern} { if {[info exists project(dft,$k)]} { puts $project(dft,$k) } }\n'
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    pats = [w for line in r.stdout.splitlines() for w in line.split()]
    return [re.compile('^' + re.escape(g).replace('\\*', '.*').replace('\\?', '.') + '$') for g in pats]


def port_dirs(netlist, module):
    """{port: input|output|inout} from the module's declarations."""
    t = strip(open(netlist, errors='replace').read())
    m = re.search(r'\bmodule\s+' + re.escape(module) + r'\b(.*?)\bendmodule\b', t, re.S)
    out = {}
    for d, names in re.findall(r'\b(input|output|inout)\b\s*(?:wire|reg|logic)?\s*(?:\[[^\]]*\])?\s*([^;)]*)',
                               m.group(1) if m else ''):
        for n in re.split(r'\s*,\s*', names):
            n = n.strip().split()[-1] if n.strip() else ''
            if n and not n.startswith(('input', 'output', 'inout')):
                out[n] = d
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--lib-config', required=True)
    ap.add_argument('--parent-netlist', nargs='*', default=[], help='<parent>=<netlist.v>')
    ap.add_argument('--project', help='project whose DFT scan-port patterns classify unconnected scan inputs')
    a = ap.parse_args()
    scan = scan_patterns(a.project)
    blocks, nets = tag_values(a.lib_config)
    parents = {b: nets[b] for b in blocks if b in nets}
    for pn in a.parent_netlist:
        p, _, f = pn.partition('=')
        parents[p + ' (given)'] = f
    bad = warn = 0
    print(f"{'block':<14} {'parent':<24} {'instance':<14} result")
    for b in blocks:
        bports = module_ports(nets[b], b) if b in nets else None
        if bports is None:
            print(f"{b:<14} {'-':<24} {'-':<14} block netlist has no module {b}")
            bad += 1
            continue
        dirs = port_dirs(nets[b], b)
        for p, f in parents.items():
            if p.split()[0] == b or not os.path.isfile(f):
                continue
            for inst, (pins, open_pins) in instance_pins(f, b).items():
                missing = sorted(pins - bports)
                floating = sorted(q for q in bports - pins if dirs.get(q, 'input') != 'output')
                scan_open = [q for q in floating if any(r.match(q) for r in scan)]
                func_open = [q for q in floating if q not in scan_open]
                short = lambda l: ' '.join(l[:12]) + (f' … (+{len(l) - 12})' if len(l) > 12 else '')
                if missing or func_open:
                    bad += 1
                    print(f"{b:<14} {p:<24} {inst:<14} ERROR — interface differs")
                    if missing:
                        print(f"    parent connects pins the block lacks : {short(missing)}")
                    if func_open:
                        print(f"    block inputs the parent leaves floating: {short(func_open)}")
                if scan_open:
                    warn += 1
                    print(f"{b:<14} {p:<24} {inst:<14} WARN — {len(scan_open)} scan input(s) unconnected "
                          f"(hierarchical scan not stitched)")
                if not (missing or func_open or scan_open):
                    print(f"{b:<14} {p:<24} {inst:<14} OK ({len(bports)} ports)")
    print(f"\nerrors: {bad}   warnings: {warn}")
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
