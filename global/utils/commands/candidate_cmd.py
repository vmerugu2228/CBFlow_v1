#!/usr/bin/env python3
"""cbflow flow release candidate — the release version of an exit for a phase.

An exit can be released many times in a phase (BTO, BTO_ECO1, BTO_ECO2, from
PNR or ECO; P3_SYNTH_v1 / _v2 …). The candidate is the one version the phase
signs off with: by default the LATEST release of the exit (newest version a
flow produced — releases that only verified the exit, i.e. whose own tag is
among their MANIFEST upstream_tags: STA / PV / LEC / GLS BTO, are not
versions); `set` pins another version, `clear` returns to the latest.
Downstream runs read it with `<arr>(input,release_tag) "<EXIT>@candidate"`
(cbflow_candidate_tag in utils.tcl resolves it to the real tag before the
inputs are staged); the checklist skill's tag_audit flags runs built on
another version.

Storage (one file per phase / block, next to the flow dirs):
  <project(release,path)>/<phase>/<block>/CANDIDATES      current: one line per exit
      EXIT <tab> FLOW <tab> TAG <tab> USER <tab> ISO-TIME <tab> RELEASE_COMPLETE-mtime <tab> REASON
  <project(release,path)>/<phase>/<block>/CANDIDATES.log  history (JSON lines)

Commands:
  set     --project P --phase PH --block B --exit X --flow F --tag T [--reason TEXT]   pin
  show    --project P --phase PH --block B [--exit X]   candidate + every version of the exit
  list    --project P [--phase PH]                      blocks x exits: candidate (latest / pinned)
  clear   --project P --phase PH --block B --exit X [--reason TEXT]                    unpin
  history --project P --phase PH --block B [--exit X]
"""
import argparse
import getpass
import glob
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.environ.get('CBFLOW_ROOT') or os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
RELEASE_CFG = os.path.join(ROOT, 'PD', 'config', 'flow', 'v1.0.0', 'release_config.tcl')
FIELDS = ['exit', 'flow', 'tag', 'user', 'at', 'rc_mtime', 'reason']


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def project_values(project):
    g = os.path.join(ROOT, 'global', 'config', 'project', project, 'v1.0.0', f'{project}_config.tcl')
    if not os.path.exists(g):
        die(f'project {project}: no {g}')
    overlays = sorted(glob.glob(os.path.join(ROOT, '*', 'config', 'project', project, 'v1.0.0',
                                             f'{project}_*_config.tcl')))
    files = ' '.join('{%s}' % f for f in [g] + overlays)
    script = f'''
foreach f {{{files}}} {{ catch {{ source $f }} }}
set MILESTONE_ORDER {{}}
set fh [open {{{RELEASE_CFG}}}]; set t [read $fh]; close $fh
regexp {{set MILESTONE_ORDER \\{{([^}}]*)\\}}}} $t -> MILESTONE_ORDER
if {{![info exists project(release,path)]}} {{ puts stderr "project(release,path) is not set"; exit 1 }}
puts "release\\t$project(release,path)"
puts "phases\\t$project(phases)"
puts "order\\t$MILESTONE_ORDER"
foreach k [array names project phase_exits*] {{
    dict for {{ph ex}} $project($k) {{ puts "exits\\t$ph\\t$ex" }}
}}
dict for {{b d}} $project(design_hierarchy) {{ puts "block\\t$b" }}
'''
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if r.returncode:
        die(f'cannot read the {project} config: {r.stderr.strip()}')
    cfg = {'blocks': [], 'exits': {}}
    for line in r.stdout.splitlines():
        f = line.split('\t')
        if f[0] == 'block':
            cfg['blocks'].append(f[1])
        elif f[0] == 'exits':
            cfg['exits'].setdefault(f[1], set()).update(f[2].split())
        elif f[0] in ('phases', 'order'):
            cfg[f[0]] = f[1].split()
        else:
            cfg[f[0]] = f[1]
    return cfg


def family(tag):
    """BTO_ECO2 -> BTO; P3_SYNTH_v2 -> P3_SYNTH; BTO -> BTO."""
    m = re.match(r'^(.*)_ECO\d+$', tag) or re.match(r'^(.*)_v\d+$', tag)
    return m.group(1) if m else tag


def block_dir(cfg, phase, block):
    return os.path.join(cfg['release'], phase, block)


def read_candidates(cfg, phase, block):
    path = os.path.join(block_dir(cfg, phase, block), 'CANDIDATES')
    out = {}
    if os.path.exists(path):
        for line in open(path):
            f = line.rstrip('\n').split('\t')
            if len(f) >= 6 and not line.startswith('#'):
                out[f[0]] = dict(zip(FIELDS, f + [''] * (len(FIELDS) - len(f))))
    return out


def write_candidates(cfg, phase, block, cands):
    d = block_dir(cfg, phase, block)
    path = os.path.join(d, 'CANDIDATES')
    tmp = path + f'.tmp{os.getpid()}'
    with open(tmp, 'w') as fh:
        fh.write('# ' + '\t'.join(f.upper() for f in FIELDS) + '   (cbflow flow release candidate)\n')
        for x in sorted(cands):
            c = cands[x]
            fh.write('\t'.join(str(c.get(k, '')).replace('\t', ' ').replace('\n', ' ') for k in FIELDS) + '\n')
    os.replace(tmp, path)


def log(cfg, phase, block, action, entry):
    rec = dict(entry, action=action, phase=phase, block=block)
    with open(os.path.join(block_dir(cfg, phase, block), 'CANDIDATES.log'), 'a') as fh:
        fh.write(json.dumps(rec) + '\n')


def verifies(rel_dir):
    """A release that verified the exit it is tagged with (its own tag among
    its MANIFEST upstream_tags — STA / PV / LEC / GLS BTO), not a version."""
    try:
        m = json.load(open(os.path.join(rel_dir, 'MANIFEST.json')))
    except (OSError, ValueError):
        return False
    return os.path.basename(rel_dir) in m.get('signoff_status', {}).get('upstream_tags', [])


def versions(cfg, phase, block, exit_name=None):
    """Versions of an exit (or of every exit) in the phase: [(flow, tag, rc_mtime)] newest first."""
    out = []
    for rc in glob.glob(os.path.join(block_dir(cfg, phase, block), '*', '*', 'RELEASE_COMPLETE')):
        d = os.path.dirname(rc)
        tag = os.path.basename(d)
        if (exit_name is None or family(tag) == exit_name) and not verifies(d):
            out.append((os.path.basename(os.path.dirname(d)), tag, os.path.getmtime(rc)))
    return sorted(out, key=lambda v: -v[2])


def candidate(cfg, phase, block, exit_name, cands=None):
    """(flow, tag, how) — pinned entry, else the latest version; None without a release."""
    cands = read_candidates(cfg, phase, block) if cands is None else cands
    if exit_name in cands:
        return cands[exit_name]['flow'], cands[exit_name]['tag'], 'pinned'
    vs = versions(cfg, phase, block, exit_name)
    return (vs[0][0], vs[0][1], 'latest') if vs else None


def state(cfg, phase, block, c):
    rc = os.path.join(block_dir(cfg, phase, block), c['flow'], c['tag'], 'RELEASE_COMPLETE')
    if not os.path.exists(rc):
        return 'MISSING (release removed)'
    try:
        if os.path.getmtime(rc) > float(c['rc_mtime']) + 1:
            return f're-released {time.strftime("%Y-%m-%d %H:%M", time.localtime(os.path.getmtime(rc)))} after nomination'
    except ValueError:
        pass
    return 'OK'


def check_scope(cfg, a, need_block=True):
    if a.phase and a.phase not in cfg['phases']:
        die(f'phase {a.phase} not in project(phases) {cfg["phases"]}')
    if need_block and a.block not in cfg['blocks']:
        die(f'block {a.block} not in project(design_hierarchy) {cfg["blocks"]}')


# ── commands ────────────────────────────────────────────────────────────────
def cmd_set(cfg, a):
    check_scope(cfg, a)
    if family(a.tag) != a.exit:
        die(f'tag {a.tag} is not a version of {a.exit} (versions are {a.exit}, {a.exit}_ECO<n>, {a.exit}_v<n>)')
    rel = os.path.join(block_dir(cfg, a.phase, a.block), a.flow, a.tag)
    rc = os.path.join(rel, 'RELEASE_COMPLETE')
    if verifies(rel):
        die(f'{a.flow}/{a.tag} verified {a.exit} (signoff release), it is not a version of it — pin the release it verified')
    if not os.path.exists(rc):
        vs = versions(cfg, a.phase, a.block, a.exit)
        die(f'{rel} is not released (no RELEASE_COMPLETE)'
            + ('; released versions: ' + ', '.join(f'{f}/{t}' for f, t, _ in vs) if vs else ''))
    if a.exit in cfg['order'] and a.exit not in cfg['exits'].get(a.phase, set()):
        die(f'{a.exit} is not an exit of phase {a.phase} (project(phase_exits): '
            f'{" ".join(sorted(cfg["exits"].get(a.phase, [])))})')
    cands = read_candidates(cfg, a.phase, a.block)
    prev = cands.get(a.exit)
    entry = {'exit': a.exit, 'flow': a.flow, 'tag': a.tag, 'user': getpass.getuser(),
             'at': time.strftime('%Y-%m-%dT%H:%M:%S'), 'rc_mtime': f'{os.path.getmtime(rc):.0f}',
             'reason': a.reason or ''}
    cands[a.exit] = entry
    write_candidates(cfg, a.phase, a.block, cands)
    log(cfg, a.phase, a.block, 'set', dict(entry, previous=f'{prev["flow"]}/{prev["tag"]}' if prev else ''))
    print(f'{a.phase} {a.block} {a.exit} candidate: {a.flow}/{a.tag}'
          + (f'  (was {prev["flow"]}/{prev["tag"]})' if prev else ''))
    print(f'Consumers: set <arr>(input,release_tag) "{a.exit}@candidate"')
    return 0


def cmd_clear(cfg, a):
    check_scope(cfg, a)
    cands = read_candidates(cfg, a.phase, a.block)
    if a.exit not in cands:
        die(f'{a.phase} {a.block} has no {a.exit} candidate')
    prev = cands.pop(a.exit)
    write_candidates(cfg, a.phase, a.block, cands)
    log(cfg, a.phase, a.block, 'clear', dict(prev, user=getpass.getuser(),
                                              at=time.strftime('%Y-%m-%dT%H:%M:%S'), reason=a.reason or ''))
    cur = candidate(cfg, a.phase, a.block, a.exit, cands)
    print(f'{a.phase} {a.block} {a.exit}: unpinned {prev["flow"]}/{prev["tag"]}; candidate is now the latest '
          f'release' + (f' {cur[0]}/{cur[1]}' if cur else ' (none)'))
    return 0


def cmd_show(cfg, a):
    check_scope(cfg, a)
    cands = read_candidates(cfg, a.phase, a.block)
    exits = [a.exit] if a.exit else sorted(
        set(cands) | {family(t) for _, t, _ in versions(cfg, a.phase, a.block)},
        key=lambda x: (cfg['order'].index(x) if x in cfg['order'] else 99, x))
    for x in exits:
        c = cands.get(x)
        vs = versions(cfg, a.phase, a.block, x)
        cur = candidate(cfg, a.phase, a.block, x, cands)
        head = f'{a.phase} {a.block} {x}: '
        if c:
            head += f'candidate {c["flow"]}/{c["tag"]} (pinned by {c["user"]} {c["at"]}) [{state(cfg, a.phase, a.block, c)}]'
            if c.get('reason'):
                head += f'  "{c["reason"]}"'
        elif cur:
            head += f'candidate {cur[0]}/{cur[1]} (latest release)'
        else:
            head += 'no release'
        print(head)
        for i, (f, t, m) in enumerate(vs):
            mark = '*' if cur and (cur[0], cur[1]) == (f, t) else ' '
            print(f'   {mark} {f + "/" + t:30s} {time.strftime("%Y-%m-%d %H:%M", time.localtime(m))}'
                  + ('  newest' if i == 0 and len(vs) > 1 else ''))
    return 0


def cmd_list(cfg, a):
    if a.phase:
        check_scope(cfg, a, need_block=False)
    phases = [a.phase] if a.phase else cfg['phases']
    rows = []
    for ph in phases:
        for b in cfg['blocks']:
            if not os.path.isdir(block_dir(cfg, ph, b)):
                continue
            cands = read_candidates(cfg, ph, b)
            vs = versions(cfg, ph, b)
            fams = {}
            for f, t, _ in vs:
                fams.setdefault(family(t), []).append(f'{f}/{t}')
            for x in sorted(set(fams) | set(cands), key=lambda x: (cfg['order'].index(x) if x in cfg['order'] else 99, x)):
                cur = candidate(cfg, ph, b, x, cands)
                if not cur:
                    rows.append((ph, b, x, '-', 'pinned release removed', 0))
                    continue
                how = cur[2] + (f' — {state(cfg, ph, b, cands[x])}' if x in cands else '')
                rows.append((ph, b, x, f'{cur[0]}/{cur[1]}', how, len(fams.get(x, []))))
    if not rows:
        print('No releases.')
        return 0
    print(f'{"PHASE":6s} {"BLOCK":14s} {"EXIT":18s} {"CANDIDATE":30s} {"VERSIONS":8s} HOW')
    for ph, b, x, c, st, n in rows:
        print(f'{ph:6s} {b:14s} {x:18s} {c:30s} {n:<8d} {st}')
    return 0


def cmd_history(cfg, a):
    check_scope(cfg, a)
    p = os.path.join(block_dir(cfg, a.phase, a.block), 'CANDIDATES.log')
    if not os.path.exists(p):
        print('No candidate history.')
        return 0
    for line in open(p):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if a.exit and r.get('exit') != a.exit:
            continue
        print(f'{r.get("at", ""):20s} {r.get("user", ""):10s} {r.get("action", ""):5s} {r.get("exit", ""):16s} '
              f'{r.get("flow", "")}/{r.get("tag", "")}'
              + (f'  (was {r["previous"]})' if r.get('previous') else '')
              + (f'  "{r["reason"]}"' if r.get('reason') else ''))
    return 0


def main():
    ap = argparse.ArgumentParser(prog='cbflow flow release candidate', description=__doc__.split('\n')[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog='Examples:\n'
                                        '  cbflow flow release candidate list --project opensky --phase P3\n'
                                        '  cbflow flow release candidate show --project opensky --phase P3 --block gcd --exit BTO\n'
                                        '  cbflow flow release candidate set --project opensky --phase P3 --block gcd --exit BTO \\\n'
                                        '      --flow ECO --tag BTO_ECO2 --reason "setup closed at ss m40c"\n'
                                        '  then in a downstream user config:  set sta(input,release_tag) "BTO@candidate"')
    sub = ap.add_subparsers(dest='cmd', required=True)
    for name in ('set', 'show', 'clear', 'history', 'list'):
        p = sub.add_parser(name)
        p.add_argument('--project', required=True)
        p.add_argument('--phase', required=name != 'list')
        if name != 'list':
            p.add_argument('--block', required=True)
            p.add_argument('--exit', required=name in ('set', 'clear'))
        if name == 'set':
            p.add_argument('--flow', required=True)
            p.add_argument('--tag', required=True)
        if name in ('set', 'clear'):
            p.add_argument('--reason')
    a = ap.parse_args()
    cfg = project_values(a.project)
    return {'set': cmd_set, 'show': cmd_show, 'clear': cmd_clear, 'history': cmd_history,
            'list': cmd_list}[a.cmd](cfg, a)


if __name__ == '__main__':
    sys.exit(main())
