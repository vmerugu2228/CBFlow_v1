#!/usr/bin/env python3
"""config-manager helper (config-manager skill): find, explain and edit CBflow configs
with ownership and safety checks.

    cfgm.py files   --project P [--disc PD DFT DV RTL global] [--flow F]
    cfgm.py where   --project P --key 'pnr(oss,place,density)' [--disc ...] [--flow F]
    cfgm.py grep    --project P --text <regex> [--disc ...]
    cfgm.py show    --project P --key K --flow F [--tool T]       effective value + who set it
    cfgm.py owners  --project P                                    owner per scope, may I edit?
    cfgm.py set     --file <config.tcl> --key K --value V --reason TEXT [--project P] [--apply]
    cfgm.py history --project P [--file F]

Scopes (who may --apply):
  project-global  global/config/project/<p>/**            chip lead
  project-<DISC>  <DISC>/config/project/<p>/**            PD / DFT: backend owner, RTL: frontend owner,
                                                          DV: verification owner (unset / NA -> chip lead)
  framework / tech / exit / registry                      affects every project: allowed only with
                                                          --framework (the user's explicit go-ahead)
  run             <run>/setup/*.tcl                       the run owner (RACE run_info owner)
Owners may be overridden per project in master_projects.json: "config_owners":
{"global": [logins], "PD": [...], ...}. Restricted variables
(PD/config/flow/v1.0.0/edit_restricted_config.tcl) are refused unless --restricted.
--apply: backup <dir>/backup/<file>.<YYYYmmdd-HHMMSS>.bak, rewrite the one statement,
Tcl-source the file (and, for project configs, the whole project cascade), append
<dir>/backup/CHANGELOG.jsonl; on a failed check the backup is restored.
"""
import argparse
import datetime
import fnmatch
import getpass
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
DISCS = ('PD', 'DFT', 'DV', 'RTL')
OWNER_FIELD = {'PD': 'backend', 'DFT': 'backend', 'RTL': 'frontend', 'DV': 'verification'}


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def registry():
    return json.load(open(os.path.join(ROOT, 'global', 'config', 'master_projects.json')))


def tcl(script):
    return subprocess.run(['tclsh'], input=script, capture_output=True, text=True)


def project_tech(p):
    g = os.path.join(ROOT, 'global', 'config', 'project', p, 'v1.0.0', f'{p}_config.tcl')
    if not os.path.exists(g):
        die(f'project {p}: no {g}')
    m = re.search(r'set\s+project\(technology\)\s+"?([^"\s]+)', open(g).read())
    return m.group(1) if m else ''


def flow_disc(flow):
    t = open(os.path.join(ROOT, 'global', 'config', 'flow', 'v1.0.0', 'flow_registry.tcl')).read()
    m = re.search(rf'set\s+flow\(discipline,{re.escape(flow)}\)\s+"?(\w+)', t)
    return m.group(1) if m else ''


def cascade(p, discs=None, flow=None, tool=None):
    """Config files in cascade order (project -> overlays -> tech -> registry ->
    flow config -> node config (+ tool overlay) -> mmmc), limited to discs."""
    discs = set(discs or DISCS + ('global',))
    if flow:
        discs |= {flow_disc(flow), 'global'}
    v = 'v1.0.0'
    out = []
    g = os.path.join(ROOT, 'global', 'config', 'project', p, v)
    if 'global' in discs:
        out.append(os.path.join(g, f'{p}_config.tcl'))
    for d in DISCS:
        if d in discs:
            out.append(os.path.join(ROOT, d, 'config', 'project', p, v, f'{p}_{d.lower()}_config.tcl'))
    tech = project_tech(p)
    out.append(os.path.join(ROOT, 'global', 'config', 'tech', tech, v, 'tech_config.tcl'))
    out.append(os.path.join(ROOT, 'global', 'config', 'flow', v, 'flow_registry.tcl'))
    for d in DISCS:
        if d in discs:
            out.append(os.path.join(ROOT, d, 'config', 'flow', v, 'flow_config.tcl'))
            nc = os.path.join(ROOT, d, 'config', 'flow', v, 'node_configs')
            if flow:
                out.append(os.path.join(nc, f'{flow}_config.tcl'))
                if tool:
                    out.append(os.path.join(nc, f'{flow}_{tool}_config.tcl'))
            else:
                out += sorted(glob.glob(os.path.join(nc, '*.tcl')))
            if d == 'PD':
                out += sorted(f for f in glob.glob(os.path.join(ROOT, d, 'config', 'flow', v, '*.tcl'))
                              if not f.endswith('flow_config.tcl'))
    if 'global' in discs:
        out += [os.path.join(g, 'mmmc_config.tcl'), os.path.join(g, 'mmmc_node_scenarios.tcl')]
        out += sorted(glob.glob(os.path.join(ROOT, 'global', 'config', 'exit', v, '*.tcl')))
    return [f for f in out if os.path.exists(f)]


def scope_of(path, project=None):
    rp = os.path.relpath(os.path.realpath(path), ROOT)
    parts = rp.split(os.sep)
    if rp.startswith('..'):
        if os.path.exists(os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(path))), '.run.cbflow.tcl')) \
                or '/setup/' in path:
            return 'run', None
        return 'external', None
    if parts[:3] == ['global', 'config', 'project']:
        return 'project-global', parts[3]
    if len(parts) > 3 and parts[0] in DISCS and parts[1:3] == ['config', 'project']:
        return f'project-{parts[0]}', parts[3]
    if parts[:3] == ['global', 'config', 'tech']:
        return 'tech', None
    if parts[:3] == ['global', 'config', 'exit']:
        return 'exit', None
    if parts[:3] == ['global', 'config', 'flow'] or parts[:2] == ['global', 'config']:
        return 'registry', None
    if parts[0] in DISCS and parts[1] == 'config':
        return 'framework', None
    if '/setup/' in rp:
        return 'run', None
    return 'other', None


def owners(p):
    e = registry().get('projects', {}).get(p)
    if e is None:
        die(f'project {p} not in master_projects.json')
    lead = e.get('chip_lead', '')
    co = e.get('config_owners', {})
    out = {'global': co.get('global') or [lead]}
    for d in DISCS:
        o = e.get('flow_owners', {}).get(OWNER_FIELD[d], '')
        out[d] = co.get(d) or ([o] if o and o not in ('NA', 'Not specified') else []) + ([lead] if lead else [])
    out['_lead'] = lead
    return out


def may_edit(scope, project, user):
    if scope.startswith('project-'):
        o = owners(project)
        key = 'global' if scope == 'project-global' else scope.split('-', 1)[1]
        allowed = o[key] + ([o['_lead']] if o['_lead'] else [])
        return user in allowed, f'{scope} of {project}: owners {", ".join(sorted(set(allowed))) or "none"}'
    return True, scope


def find_sets(path, key_pat):
    """[(line, var, value text)] of `set <var> ...` and of the keys inside
    `array set <arr> { key value ... }` blocks, whose var matches key_pat (glob)."""
    out = []
    arr = None
    for i, line in enumerate(open(path, errors='replace'), 1):
        if arr:
            if re.match(r'\s*\}', line):
                arr = None
                continue
            m = re.match(r'\s*([^#\s]\S*)\s+(.*?)\s*$', line)
            if m and fnmatch.fnmatchcase(f'{arr}({m.group(1)})', key_pat):
                out.append((i, f'{arr}({m.group(1)})', m.group(2)))
            continue
        m = re.match(r'\s*array\s+set\s+(\w+)\s+\{\s*$', line)
        if m:
            arr = m.group(1)
            continue
        m = re.match(r'\s*set\s+(\S+)\s+(.*)$', line)
        if m and fnmatch.fnmatchcase(m.group(1), key_pat):
            out.append((i, m.group(1), m.group(2).strip()))
    return out


def restricted(var):
    p = os.path.join(ROOT, 'PD', 'config', 'flow', 'v1.0.0', 'edit_restricted_config.tcl')
    if not os.path.exists(p):
        return False
    pats = re.findall(r'"([^"]+)"', open(p).read())
    return any(fnmatch.fnmatchcase(var, x) for x in pats)


# ── commands ────────────────────────────────────────────────────────────────
def cmd_files(a):
    for f in cascade(a.project, a.disc, a.flow, a.tool):
        print(f'{scope_of(f, a.project)[0]:16s} {os.path.relpath(f, ROOT)}')
    return 0


def cmd_where(a):
    files = cascade(a.project, a.disc, a.flow, a.tool)
    hits = []
    for f in files:
        for ln, var, val in find_sets(f, a.key):
            hits.append((f, ln, var, val))
    if not hits:
        print(f'{a.key}: not set in the {", ".join(a.disc or ["all"])} cascade of {a.project}'
              + (f' ({a.flow})' if a.flow else ''))
        return 1
    last = {}
    for f, ln, var, val in hits:
        last[var] = (f, ln)
    print(f'{a.key} — in cascade order (the last setter wins unless guarded by info exists):')
    for f, ln, var, val in hits:
        mark = '  <- effective' if last[var] == (f, ln) else ''
        print(f'  {scope_of(f)[0]:15s} {os.path.relpath(f, ROOT)}:{ln}  {var} = {val[:90]}{mark}')
    return 0


def cmd_grep(a):
    rx = re.compile(a.text)
    n = 0
    for f in cascade(a.project, a.disc, a.flow, a.tool):
        for i, line in enumerate(open(f, errors='replace'), 1):
            if rx.search(line):
                print(f'{os.path.relpath(f, ROOT)}:{i}: {line.rstrip()[:140]}')
                n += 1
    print(f'{n} match(es)')
    return 0 if n else 1


def cmd_show(a):
    files = cascade(a.project, None, a.flow, a.tool)
    arr, _, idx = a.key.partition('(')
    idx = idx.rstrip(')')
    script = ['set __last ""', 'set __hist {}']
    for f in files:
        script.append(f'catch {{ source {{{f}}} }}')
        script.append(f'if {{[info exists {arr}({idx})]}} {{ set __v ${arr}({idx}); '
                      f'if {{$__v ne $__last}} {{ lappend __hist [list {{{os.path.relpath(f, ROOT)}}} $__v]; set __last $__v }} }}')
    script.append('foreach h $__hist { puts "[lindex $h 0]\\t[lindex $h 1]" }')
    # as a run: flow(type) set (flow configs exit without it); an `exit` in a
    # config becomes an error the per-file catch reports instead of ending the trace
    pre = (f'array set project {{}}\narray set flow {{}}\nset flow(type) {a.flow}\n'
           f'set flow(design_name) {{}}\nrename exit __exit\nproc exit {{args}} {{ error "exit $args" }}\n')
    r = tcl(pre + '\n'.join(script) + '\n')
    rows = [l.split('\t', 1) for l in r.stdout.splitlines() if '\t' in l]
    if not rows:
        print(f'{a.key}: not set for {a.project} {a.flow} (cascade of {len(files)} files)')
        return 1
    print(f'{a.key} for {a.project} {a.flow}' + (f' ({a.tool})' if a.tool else '') + ':')
    for f, v in rows:
        print(f'  {f:70s} {v[:80]}')
    print(f'effective: {rows[-1][1]}   (set last by {rows[-1][0]}; run user_config / overrides may still change it)')
    return 0


def cmd_owners(a):
    o = owners(a.project)
    me = getpass.getuser()
    print(f'{a.project}: chip lead {o["_lead"] or "unset"}   (you: {me})')
    for k in ('global',) + DISCS:
        scope = 'project-global' if k == 'global' else f'project-{k}'
        ok, _ = may_edit(scope, a.project, me)
        print(f'  {scope:16s} owners {", ".join(sorted(set(o[k]))) or "-":30s} {"you may edit" if ok else "read-only for you"}')
    print('  framework / tech / exit / registry: every project — only with the user\'s explicit go-ahead (--framework)')
    return 0


def replace_stmt(text, var, value):
    m = re.search(r'^(\s*)set\s+' + re.escape(var) + r'(\s+)', text, re.M)
    if not m:
        return None, None
    i = m.end()
    if text[i] == '{':
        depth, j = 0, i
        while j < len(text):
            depth += {'{': 1, '}': -1}.get(text[j], 0)
            if depth == 0:
                break
            j += 1
        end = j + 1
    elif text[i] == '"':
        end = text.index('"', i + 1) + 1
    else:
        end = i + len(re.match(r'\S+', text[i:]).group(0))
    old = text[i:end]
    return text[:i] + value + text[end:], old


def cmd_set(a):
    path = os.path.abspath(a.file)
    if not os.path.isfile(path):
        die(f'{path}: no such file')
    scope, proj = scope_of(path)
    project = a.project or proj
    me = getpass.getuser()
    text = open(path).read()
    new, old = replace_stmt(text, a.key, a.value)
    if new is None:
        if not a.add:
            die(f'{a.key} is not set in {os.path.relpath(path, ROOT)} (use --add to append it)')
        new, old = text.rstrip('\n') + f'\nset {a.key} {a.value}\n', '(unset)'
    print(f'{os.path.relpath(path, ROOT)}  [{scope}{" " + project if project else ""}]')
    print(f'  {a.key}: {old}  ->  {a.value}')
    problems = []
    if scope.startswith('project-'):
        ok, why = may_edit(scope, project, me)
        if not ok:
            problems.append(f'{me} may not edit {why}')
    if scope in ('framework', 'tech', 'exit', 'registry') and not a.framework:
        problems.append(f'{scope} config affects every project — needs --framework (the user\'s explicit go-ahead)')
    if scope == 'run':
        ow = owner_of_run(path)
        if ow and ow != me:
            problems.append(f'run owned by {ow}')
    if restricted(a.key) and not a.restricted:
        problems.append(f'{a.key} is edit-restricted (edit_restricted_config.tcl) — needs --restricted')
    if not a.reason:
        problems.append('--reason is required')
    for p_ in problems:
        print(f'  REFUSED: {p_}')
    if problems:
        return 1
    if not a.apply:
        print('  dry run — re-run with --apply to write it')
        return 0
    bdir = os.path.join(os.path.dirname(path), 'backup')
    os.makedirs(bdir, exist_ok=True)
    ts = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    bak = os.path.join(bdir, f'{os.path.basename(path)}.{ts}.bak')
    shutil.copy2(path, bak)
    with open(path, 'w') as fh:
        fh.write(new)
    # checks: the file sources; a project config: the project cascade sources
    r = tcl(f'array set project {{}}\narray set tech {{}}\narray set flow {{}}\n'
            f'if {{[catch {{source {{{path}}}}} e]}} {{ puts stderr $e; exit 1 }}\n')
    err = r.stderr.strip() if r.returncode else ''
    if not err and project:
        files = cascade(project)[:3]
        r = tcl('\n'.join(f'if {{[catch {{source {{{f}}}}} e]}} {{ puts stderr "{os.path.basename(f)}: $e"; exit 1 }}'
                          for f in files) + '\n')
        err = r.stderr.strip() if r.returncode else ''
    if err:
        shutil.copy2(bak, path)
        die(f'check failed, change reverted: {err[:300]}')
    with open(os.path.join(bdir, 'CHANGELOG.jsonl'), 'a') as fh:
        fh.write(json.dumps({'at': ts, 'user': me, 'file': os.path.relpath(path, ROOT), 'key': a.key,
                             'old': old, 'new': a.value, 'reason': a.reason, 'backup': os.path.basename(bak)}) + '\n')
    print(f'  applied; backup {os.path.relpath(bak, ROOT)}; logged in {os.path.relpath(bdir, ROOT)}/CHANGELOG.jsonl')
    return 0


def owner_of_run(path):
    d = os.path.dirname(os.path.dirname(os.path.abspath(path)))
    ptr = os.path.join(d, '.race_db_pointer')
    if not os.path.exists(ptr):
        return ''
    try:
        import sqlite3
        db = open(ptr).read().strip()
        con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
        row = con.execute("SELECT value FROM run_info WHERE key='owner'").fetchone()
        con.close()
        return row[0] if row else ''
    except Exception:  # noqa: BLE001
        return ''


def cmd_history(a):
    logs = glob.glob(os.path.join(ROOT, '*', 'config', 'project', a.project, 'v1.0.0', 'backup', 'CHANGELOG.jsonl')) + \
        glob.glob(os.path.join(ROOT, '*', 'config', '**', 'backup', 'CHANGELOG.jsonl'), recursive=True)
    rows = []
    for lp in sorted(set(logs)):
        for l in open(lp):
            try:
                r = json.loads(l)
            except ValueError:
                continue
            if a.file and a.file not in r['file']:
                continue
            rows.append(r)
    for r in sorted(rows, key=lambda r: r['at']):
        print(f'{r["at"]} {r["user"]:10s} {r["file"]}  {r["key"]}: {r["old"]} -> {r["new"]}  "{r["reason"]}"')
    if not rows:
        print('no config-manager changes recorded')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)

    def common(p, key=False):
        p.add_argument('--project', required=True)
        p.add_argument('--disc', nargs='*', choices=list(DISCS) + ['global'])
        p.add_argument('--flow')
        p.add_argument('--tool')
        if key:
            p.add_argument('--key', required=True, help="array(key), glob allowed in where: 'pnr(oss,*)'")
    common(sub.add_parser('files'))
    common(sub.add_parser('where'), key=True)
    p = sub.add_parser('grep')
    common(p)
    p.add_argument('--text', required=True)
    p = sub.add_parser('show')
    p.add_argument('--project', required=True)
    p.add_argument('--key', required=True)
    p.add_argument('--flow', required=True)
    p.add_argument('--tool')
    p = sub.add_parser('owners')
    p.add_argument('--project', required=True)
    p = sub.add_parser('set')
    p.add_argument('--file', required=True)
    p.add_argument('--key', required=True)
    p.add_argument('--value', required=True, help='Tcl value as written: "text", {list}, 0.25')
    p.add_argument('--reason')
    p.add_argument('--project')
    p.add_argument('--add', action='store_true', help='append when the key is not set in the file')
    p.add_argument('--framework', action='store_true', help='allow framework / tech / exit / registry files')
    p.add_argument('--restricted', action='store_true', help='allow an edit-restricted variable')
    p.add_argument('--apply', action='store_true')
    p = sub.add_parser('history')
    p.add_argument('--project', required=True)
    p.add_argument('--file')
    a = ap.parse_args()
    return {'files': cmd_files, 'where': cmd_where, 'grep': cmd_grep, 'show': cmd_show, 'owners': cmd_owners,
            'set': cmd_set, 'history': cmd_history}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
