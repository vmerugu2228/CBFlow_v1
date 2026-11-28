#!/usr/bin/env python3
"""MMMC inventory of a CBflow project (+ library tag, + a run) for the mmmc-manager skill.

    mmmc_inventory.py --project <p> [--design <block>] [--run <run_dir>]
                      [--lib-tag <TAG>] [-o inventory.json]

Evaluates (tclsh, read-only) what the project declares and what the library
tag can actually time:
  global/config/project/<p>/v1.0.0/mmmc_config.tcl     PVT points, RC corners,
        operating modes, analysis views, mmmc_scenario_sets
  global/config/project/<p>/v1.0.0/mmmc_node_scenarios.tcl  per-node setup / hold
  global/config/tech/<tech>/v1.0.0/tech_config.tcl      rc_corners_available,
        memory lib_set_map, OpenRCX decks per RC corner
  <lib_tag_root>/<tech>/<TAG>/lib_config.tcl            tech(<trk>,lib,<c>,timing),
        memory corners, hard blocks (lib_sets, spef_corners)
  <run>/setup/user_config.tcl + override_config*.tcl    the run's tag, scenario
        overrides (sta(mmmc,setup|hold_scenarios), mmmc(<node>) dicts)
The tag is --lib-tag, else the run's project(lib_config_tag), else the PD overlay's.

Writes one JSON document (stdout or -o) with the declarations and a `checks`
list of {level: ERROR|WARN|INFO, check, msg}: view lib sets missing from the tag,
memory map gaps, child-block libs / SPEF corners missing for the design,
modes without setup or hold signoff views, process corners never signed off,
no / non-typical power set, node views outside the signoff set, run overrides
that nothing reads. Never writes anything but the JSON.
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

TCL_MMMC = r'''
set design_name {%(design)s}
source {%(mmmc)s}
if {[file exists {%(ns)s}]} { source {%(ns)s} }
foreach c $mmmc(process_corners) {
    if {[info exists mmmc(pvt,$c)]} { foreach p $mmmc(pvt,$c) { puts "PVT\t$c\t[lindex $p 0]\t[lindex $p 1]" } }
}
foreach r [lsort [array names rc_corners]] {
    set t [expr {[dict exists $rc_corners($r) temperature] ? [dict get $rc_corners($r) temperature] : ""}]
    puts "RC\t$r\t$t"
}
foreach m [lsort [array names operating_modes]] { puts "MODE\t$m\t[dict get $operating_modes($m) constraint_file]" }
foreach v [lsort [array names analysis_views]] {
    set d $analysis_views($v)
    puts "VIEW\t$v\t[dict get $d mode]\t[dict get $d corner]\t[dict get $d voltage]\t[dict get $d temperature]\t[dict get $d rc_corner]\t[dict get $d lib_set_ref]"
}
foreach s [lsort [array names mmmc_scenario_sets]] { foreach v $mmmc_scenario_sets($s) { puts "SET\t$s\t$v" } }
foreach n [lsort [array names mmmc]] {
    if {[string match "*,*" $n]} continue
    if {[catch {dict size $mmmc($n)}]} continue
    foreach role {setup hold} {
        if {[dict exists $mmmc($n) $role]} { foreach v [dict get $mmmc($n) $role] { puts "NODE\t$n\t$role\t$v" } }
    }
}
'''

TCL_LIB = r'''
source {%(lib)s}
foreach k [lsort [array names tech]] {
    if {[regexp {^([^,]+),lib,([^,]+),timing$} $k -> trk c] && $trk ne "lib" && [llength $tech($k)]} { puts "LIB\t$trk\t$c" }
    if {[regexp {^lib,([^,]+),timing,(memory|io|ip|analog)$} $k -> c cat] && [llength $tech($k)]} { puts "MACROLIB\t$cat\t$c" }
}
if {[info exists tech(blocks)]} {
    foreach b $tech(blocks) {
        foreach key {lib_sets spef_corners} {
            if {[info exists tech(block,$b,$key)]} { foreach x $tech(block,$b,$key) { puts "BLOCK\t$b\t$key\t$x" } }
        }
        if {[info exists tech(block,$b,release)]} { puts "BLOCK\t$b\trelease\t$tech(block,$b,release)" }
    }
}
if {[info exists tech(lef,memory)] && [llength $tech(lef,memory)]} { puts "HASMEM\t1" }
'''


def tcl_sets(path):
    """{var: value} of the simple `set var value` lines of a Tcl file (last wins)."""
    out = {}
    if not os.path.isfile(path):
        return out
    with open(path, errors='replace') as f:
        for line in f:
            m = SET_RE.match(line)
            if m:
                out[m.group(1)] = next(g for g in m.groups()[1:] if g is not None)
    return out


def run_tcl(script):
    p = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f'mmmc_inventory: tclsh failed:\n{p.stderr.strip()}')
    return [ln.split('\t') for ln in p.stdout.splitlines() if '\t' in ln]


def tcl_block(text, var):
    """Body of `set <var> { ... }` (brace-balanced) or None."""
    m = re.search(r'set\s+' + re.escape(var) + r'\s+\{', text)
    if not m:
        return None
    i, depth = m.end(), 1
    while i < len(text) and depth:
        depth += {'{': 1, '}': -1}.get(text[i], 0)
        i += 1
    return text[m.end():i - 1]


def hierarchy_entry(proj_cfg, design):
    """{level, parent, children} of <design> in project(design_hierarchy) (text parse), or None."""
    with open(proj_cfg, errors='replace') as f:
        body = tcl_block(f.read(), 'project(design_hierarchy)') or ''
    m = re.search(r'(?m)^\s*' + re.escape(design) + r'\s*\{(.*?)^\s*\}', body, re.S)
    if not m:
        return None
    e = m.group(1)
    c = re.search(r'children\s+\{([^}]*)\}', e)
    p = re.search(r'parent\s+"([^"]*)"', e)
    lv = re.search(r'level\s+"([^"]*)"', e)
    return {'children': c.group(1).split() if c else [], 'parent': p.group(1) if p else '',
            'level': lv.group(1) if lv else ''}


def run_overrides(run_dir):
    """Scenario keys in the run's setup/{user,override}_config*.tcl."""
    out = []
    files = [os.path.join(run_dir, 'setup', 'user_config.tcl')] + \
        sorted(glob.glob(os.path.join(run_dir, 'setup', 'override_config*.tcl')))
    for f in files:
        if not os.path.isfile(f):
            continue
        txt = open(f, errors='replace').read()
        for m in re.finditer(r'(?m)^\s*set\s+(\w+)\(mmmc,(setup|hold)_scenarios\)\s+"([^"]*)"', txt):
            out.append({'file': os.path.basename(f), 'key': f'{m.group(1)}(mmmc,{m.group(2)}_scenarios)',
                        'role': m.group(2), 'views': m.group(3).split(), 'effective': True})
        for m in re.finditer(r'(?m)^\s*set\s+(\w+)\(mmmc,scenario_set\)\s+"?(\w+)"?', txt):
            out.append({'file': os.path.basename(f), 'key': f'{m.group(1)}(mmmc,scenario_set)',
                        'role': 'set', 'views': [m.group(2)], 'effective': True})
        # mmmc(<node>,setup_scenarios): written by the run dashboard's MMMC dialog for
        # non-dynamic (PNR) nodes, but get_node_scenarios reads only the mmmc(<node>) dict.
        for m in re.finditer(r'(?m)^\s*set\s+mmmc\(([^,)]+),(setup|hold)_scenarios\)\s+"([^"]*)"', txt):
            out.append({'file': os.path.basename(f), 'key': f'mmmc({m.group(1)},{m.group(2)}_scenarios)',
                        'role': m.group(2), 'views': m.group(3).split(), 'effective': False})
        for m in re.finditer(r'(?m)^\s*set\s+mmmc\(([^,)]+)\)\s', txt):
            out.append({'file': os.path.basename(f), 'key': f'mmmc({m.group(1)})', 'role': 'dict',
                        'views': [], 'effective': True})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--project', required=True)
    ap.add_argument('--design', help='block — enables the child-block lib / SPEF checks')
    ap.add_argument('--run', help='a run dir: its lib tag and scenario overrides')
    ap.add_argument('--lib-tag', help='library tag (default: run user_config, else PD overlay)')
    ap.add_argument('-o', '--output')
    a = ap.parse_args()

    pdir = os.path.join(ROOT, 'global', 'config', 'project', a.project, 'v1.0.0')
    proj_cfg = os.path.join(pdir, f'{a.project}_config.tcl')
    pd_cfg = os.path.join(ROOT, 'PD', 'config', 'project', a.project, 'v1.0.0', f'{a.project}_pd_config.tcl')
    mmmc_cfg = os.path.join(pdir, 'mmmc_config.tcl')
    if not os.path.isfile(mmmc_cfg):
        sys.exit(f'mmmc_inventory: {mmmc_cfg} not found')
    proj, pd = tcl_sets(proj_cfg), tcl_sets(pd_cfg)
    uc = tcl_sets(os.path.join(a.run, 'setup', 'user_config.tcl')) if a.run else {}
    design = a.design or uc.get('flow(design_name)')
    tech = proj.get('project(technology)', '')
    track = pd.get('project(track_variant)', '')
    tag = a.lib_tag or uc.get('project(lib_config_tag)') or pd.get('project(lib_config_tag)', '')
    tag_cfg = os.path.join(pd.get('project(lib_tag_root)', ''), tech, tag, 'lib_config.tcl')

    doc = {'project': a.project, 'design': design, 'tech': tech, 'track': track,
           'lib_tag': tag, 'lib_config': tag_cfg, 'mmmc_config': mmmc_cfg,
           'pvt': [], 'rc_corners': {}, 'modes': {}, 'views': {}, 'sets': {}, 'nodes': {},
           'tag': {'stdcell_lib_sets': [], 'macro_libs': {}, 'blocks': {}, 'has_memory': False},
           'tech_cfg': {}, 'run': None, 'checks': []}

    for row in run_tcl(TCL_MMMC % {'design': design or 'DESIGN', 'mmmc': mmmc_cfg,
                                   'ns': os.path.join(pdir, 'mmmc_node_scenarios.tcl')}):
        k = row[0]
        if k == 'PVT':
            doc['pvt'].append({'corner': row[1], 'voltage': row[2], 'temperature': row[3]})
        elif k == 'RC':
            doc['rc_corners'][row[1]] = row[2]
        elif k == 'MODE':
            doc['modes'][row[1]] = row[2]
        elif k == 'VIEW':
            doc['views'][row[1]] = dict(zip(('mode', 'corner', 'voltage', 'temperature', 'rc_corner', 'lib_set'), row[2:]))
        elif k == 'SET':
            doc['sets'].setdefault(row[1], []).append(row[2])
        elif k == 'NODE':
            doc['nodes'].setdefault(row[1], {'setup': [], 'hold': []})[row[2]].append(row[3])

    if os.path.isfile(tag_cfg):
        for row in run_tcl(TCL_LIB % {'lib': tag_cfg}):
            if row[0] == 'LIB' and row[1] == track:
                doc['tag']['stdcell_lib_sets'].append(row[2])
            elif row[0] == 'MACROLIB':
                doc['tag']['macro_libs'].setdefault(row[1], []).append(row[2])
            elif row[0] == 'BLOCK':
                b = doc['tag']['blocks'].setdefault(row[1], {'lib_sets': [], 'spef_corners': []})
                if row[2] == 'release':
                    b['release'] = row[3]
                else:
                    b[row[2]].append(row[3])
            elif row[0] == 'HASMEM':
                doc['tag']['has_memory'] = True
    else:
        doc['checks'].append({'level': 'ERROR', 'check': 'lib_tag', 'msg': f'library tag config not found: {tag_cfg}'})

    tcfg = os.path.join(ROOT, 'global', 'config', 'tech', tech, 'v1.0.0', 'tech_config.tcl')
    if os.path.isfile(tcfg):
        txt = open(tcfg, errors='replace').read()
        m = re.search(r'set\s+tech\(rc_corners_available\)\s+\{([^}]*)\}', txt)
        lsm = (tcl_block(txt, 'tech(memory,lib_set_map)') or '').split()
        doc['tech_cfg'] = {'file': tcfg, 'rc_corners_available': m.group(1).split() if m else [],
                           'memory_lib_set_map': dict(zip(lsm[0::2], lsm[1::2])),
                           'rcx_decks': sorted(set(re.findall(r'set\s+tech\(rcx,(?:[^,)]+,)?(rc_\w+),\w+\)', txt)))}

    if a.run:
        doc['run'] = {'dir': os.path.abspath(a.run), 'flow': uc.get('flow(type)'), 'lib_tag': uc.get('project(lib_config_tag)'),
                      'overrides': run_overrides(a.run)}

    # ── checks ──
    C = doc['checks']
    def add(level, check, msg):
        C.append({'level': level, 'check': check, 'msg': msg})

    views, sets = doc['views'], doc['sets']
    signoff = sets.get('signoff') or sets.get('sta_signoff') or []
    used = set(signoff) | set(sets.get('setup', [])) | set(sets.get('hold', [])) | set(sets.get('power', []))
    for n in doc['nodes'].values():
        used |= set(n['setup']) | set(n['hold'])
    tag_ls = set(doc['tag']['stdcell_lib_sets'])
    for v in sorted(used):
        if v not in views:
            add('ERROR', 'view', f'{v} is used by a set / node but is not an analysis view')
            continue
        ls = views[v]['lib_set']
        if tag_ls and ls not in tag_ls:
            add('ERROR', 'tag_lib', f'{v}: lib set {ls} missing from tag {tag} (tech({track},lib,{ls},timing))')
        lsm = doc['tech_cfg'].get('memory_lib_set_map', {})
        if doc['tag']['has_memory'] and ls not in lsm:
            add('ERROR', 'memory_map', f'{v}: tech(memory,lib_set_map) has no entry for {ls}')
        rc = views[v]['rc_corner']
        if doc['tech_cfg'].get('rcx_decks') and rc not in doc['tech_cfg']['rcx_decks']:
            add('ERROR', 'rcx', f'{v}: no OpenRCX deck tech(rcx,…,{rc},openrcx) in the tech config')
    if doc['tag']['has_memory']:
        mc = set(doc['tag']['macro_libs'].get('memory', []))
        for ls, c in sorted(doc['tech_cfg'].get('memory_lib_set_map', {}).items()):
            if mc and c not in mc:
                add('ERROR', 'memory_map', f'lib_set_map {ls} -> {c}: tag has no memory lib at {c}')
        if len(mc) == 1:
            add('INFO', 'memory_corner', f'memory macros characterized at one corner only ({", ".join(mc)}): '
                'every scenario times them there — macro paths do not track PVT')

    hier = hierarchy_entry(proj_cfg, design) if design else None
    doc['hierarchy'] = hier
    children = hier['children'] if hier else None
    timed = set(signoff) | set(sets.get('setup', [])) | set(sets.get('hold', []))
    if design and children is None:
        add('WARN', 'hierarchy', f'{design} not in project(design_hierarchy)')
    for ch in children or []:
        b = doc['tag']['blocks'].get(ch)
        if not b:
            add('ERROR', 'block', f'child {ch} of {design} is not a block in tag {tag}')
            continue
        for v in sorted(used & set(views)):
            if views[v]['lib_set'] not in b['lib_sets']:
                lvl = 'ERROR' if v in timed else 'WARN'
                add(lvl, 'block_lib', f'{v}: child {ch} has no timing model at {views[v]["lib_set"]} '
                    f'(tag lib_sets {" ".join(b["lib_sets"])}) — {design} cannot time this view until '
                    f'{ch}\'s PNR signoff covers it and the tag is refreshed')
            if views[v]['rc_corner'] not in b['spef_corners']:
                add('WARN', 'block_spef', f'{v}: child {ch} has no SPEF at {views[v]["rc_corner"]} '
                    f'(spef_corners {" ".join(b["spef_corners"])})')

    for m in doc['modes']:
        for role in ('setup', 'hold'):
            if not [v for v in sets.get(role, []) if views.get(v, {}).get('mode') == m]:
                add('WARN', 'mode_role', f'mode {m} has no {role} view in mmmc_scenario_sets({role})')
    so_corners = {views[v]['corner'] for v in signoff if v in views}
    for pc in sorted({p['corner'] for p in doc['pvt']} - so_corners):
        add('INFO', 'corner_coverage', f'process corner {pc} is declared but never in the signoff set')
    pw = sets.get('power', [])
    if not pw:
        add('WARN', 'power', 'no mmmc_scenario_sets(power)')
    for v in pw:
        if views.get(v, {}).get('corner') != 'tt' or views.get(v, {}).get('rc_corner') != 'rc_typ':
            add('INFO', 'power', f'power view {v} is not a typical (tt / rc_typ) view')
    for n, r in sorted(doc['nodes'].items()):
        extra = [v for v in r['setup'] + r['hold'] if v not in signoff]
        if extra and signoff:
            add('INFO', 'node_vs_signoff', f'node {n} uses views outside the signoff set: {" ".join(sorted(set(extra)))}')
    for rc, t in sorted(doc['rc_corners'].items()):
        temps = sorted({views[v]['temperature'] for v in used & set(views) if views[v]['rc_corner'] == rc})
        if temps and t and any(x.rstrip('c').replace('m', '-') != str(t) for x in temps):
            add('INFO', 'rc_temp', f'rc_corners({rc}) temperature {t} but its views run at {" ".join(temps)} '
                '(OpenRCX does not use the temperature; Cadence view-def creates one rc corner per view temperature)')
    declared_ls = {views[v]['lib_set'] for v in views}
    spare = sorted(tag_ls - declared_ls)
    if spare:
        add('INFO', 'tag_spare', f'tag {tag} has lib sets no view uses: {" ".join(spare)}')
    if doc['run']:
        for o in doc['run']['overrides']:
            if not o['effective']:
                add('WARN', 'override_ignored', f'{o["file"]}: {o["key"]} is not read by the flow '
                    '(get_node_scenarios reads the mmmc(<node>) dict) — those views are NOT used')
            for v in o['views']:
                if o['role'] in ('setup', 'hold') and v not in views:
                    add('ERROR', 'override_view', f'{o["file"]}: {v} is not an analysis view')

    out = json.dumps(doc, indent=1)
    if a.output:
        with open(a.output, 'w') as f:
            f.write(out + '\n')
    else:
        print(out)


if __name__ == '__main__':
    main()
