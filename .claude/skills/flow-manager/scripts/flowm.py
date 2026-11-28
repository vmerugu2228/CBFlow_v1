#!/usr/bin/env python3
"""flow-manager helper (flow-manager skill): CBflow framework (flow) releases —
what each project runs, what changed, patching a component, retagging projects,
watching new releases and flow issues.

    flowm.py status                                    releases, current, project pins
    flowm.py drift  [--release vX]                     released components edited since (hash + git)
    flowm.py stale  [--release vX]                     on disk vs the release: new / changed versions
    flowm.py patch  --component cmds.PNR.opensource.openroad [--from v1.0.0] --to v1.0.1 [--apply]
    flowm.py pin    --project P --release vX --reason TEXT [--apply]
    flowm.py edit   --component C | --file <path>  [--apply]      copy-on-write: a released version
                                                                  is never edited; the next one is made
    flowm.py cut    --version vX --desc TEXT [--components cmds|all|<name,...>] [--apply]
                                                                  freeze components as vX + cut release vX
    flowm.py watch  --project P                        newer releases + framework commits since its release
    flowm.py issues [--project P] [--days 7] [--audit]  failing jobs by flow / stage / error (+ cmd audit)

Release store: global/releases/<v>/ (MANIFEST.json components with path / version /
hash, release_versions.tcl, CHANGELOG.md) — `cbflow flow release create|list|info|
diff|set-current`. A project runs the release named by project(cbflow_release);
workspace create pins the run's command tree to the release's
CMDS_<FLOW>_<VENDOR>_<TOOL>_VERSION (appended to the run's user_config as
<arr>(tool,version)).
"""
import argparse
import datetime
import glob
import json
import os
import re
import sqlite3
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
CB = os.path.join(ROOT, 'bin', 'cbflow')
REL = os.path.join(ROOT, 'global', 'releases')
sys.path.insert(0, os.path.join(ROOT, 'global', 'utils', 'commands'))
sys.path.insert(0, os.path.join(ROOT, 'global', 'utils'))
os.environ.setdefault('CBFLOW_ROOT', ROOT)


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def rc():
    import release_cmd
    return release_cmd


def releases():
    if not os.path.isdir(REL):
        return []
    vs = [d for d in os.listdir(REL) if d.startswith('v') and os.path.isfile(os.path.join(REL, d, 'MANIFEST.json'))]
    return sorted(vs, key=lambda v: [int(x) if x.isdigit() else x for x in re.split(r'[.\-]', v[1:])])


def manifest(v):
    return json.load(open(os.path.join(REL, v, 'MANIFEST.json')))


def current_release():
    c = os.path.join(REL, 'current')
    return os.path.basename(os.readlink(c)) if os.path.islink(c) else ''


def project_pins():
    reg = json.load(open(os.path.join(ROOT, 'global', 'config', 'master_projects.json')))
    out = {}
    for p in reg.get('projects', {}):
        v = ''
        for f in glob.glob(os.path.join(ROOT, '*', 'config', 'project', p, 'v1.0.0', '*.tcl')):
            m = re.search(r'^\s*set\s+project\(cbflow_release\)\s+"?([^"\s]+)', open(f, errors='replace').read(), re.M)
            if m:
                v, src = m.group(1), f
        out[p] = v
    return out


def released_versions():
    """{(component, version)} present in any release manifest."""
    out = set()
    for v in releases():
        for name, c in manifest(v)['components'].items():
            out.add((name, c['version']))
    return out


def vkey(v):
    return [int(x) if x.isdigit() else x for x in re.split(r'[.\-]', v.lstrip('v'))]


def bump(v):
    p = v.lstrip('v').split('.')
    p[-1] = str(int(p[-1]) + 1) if p[-1].isdigit() else p[-1] + '.1'
    return 'v' + '.'.join(p)


def newest(base):
    vs = [d for d in os.listdir(base) if re.match(r'^v\d', d) and os.path.isdir(os.path.join(base, d))]
    return max(vs, key=vkey) if vs else ''


def copy_version(base, frm, to):
    import shutil
    src, dst = os.path.join(base, frm), os.path.join(base, to)
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns('.locked', '__pycache__', '*.swp', '.retired'))
    for dp, dn, fn in os.walk(dst):
        os.chmod(dp, 0o755)
        for f in fn:
            fp = os.path.join(dp, f)
            os.chmod(fp, 0o644 | (os.stat(fp).st_mode & 0o111))
    return dst


def cmd_edit(a):
    disk = rc().scan_versioned_components()
    comp, rel_in = a.component, ''
    if a.file:
        fp = os.path.realpath(a.file)
        for name, info in disk.items():
            base = str(rc().resolve_component_path(info['path']))
            if fp.startswith(base + os.sep):
                comp, rest = name, fp[len(base) + 1:]
                ver, rel_in = rest.split(os.sep, 1) if os.sep in rest else (rest, '')
                break
        if not comp:
            die(f'{a.file} is not inside a versioned component')
    if comp not in disk:
        die(f'{comp}: no such versioned component')
    base = str(rc().resolve_component_path(disk[comp]['path']))
    top = newest(base)
    rel = released_versions()
    locked = os.path.exists(os.path.join(base, top, '.locked'))
    if (comp, top) not in rel and not locked:
        target = os.path.join(base, top, rel_in)
        print(f'{comp} {top} is not in any release — edit in place: {os.path.relpath(target, ROOT)}')
        return 0
    nxt = bump(top)
    while os.path.exists(os.path.join(base, nxt)):
        nxt = bump(nxt)
    inrel = ', '.join(v for v in releases() if manifest(v)['components'].get(comp, {}).get('version') == top)
    print(f'{comp} {top} is {"frozen (read-only)" if locked else "released"}{" in " + inrel if inrel else ""}'
          f' — editing needs a new version: {top} -> {nxt}, then a new release')
    if not a.apply:
        print('dry run — --apply to create it (the user\'s go-ahead)')
        return 0
    copy_version(base, top, nxt)
    print(f'created {os.path.relpath(os.path.join(base, nxt), ROOT)}; edit {os.path.relpath(os.path.join(base, nxt, rel_in), ROOT)}')
    print(f'projects on releases pinning {top} keep {top}; to use {nxt}: cut a release (flowm.py cut / cbflow flow '
          f'release create) and pin the project (flowm.py pin).')
    return 0


def cmd_cut(a):
    if a.version in releases():
        die(f'release {a.version} exists')
    disk = rc().scan_versioned_components()
    if a.components == 'all':
        sel = sorted(disk)
    elif a.components == 'cmds':
        sel = sorted(k for k in disk if k.startswith('cmds.'))
    else:
        sel = [x.strip() for x in a.components.split(',')]
        bad = [x for x in sel if x not in disk]
        if bad:
            die(f'unknown component(s): {", ".join(bad)}')
    plan = []
    for name in sel:
        base = str(rc().resolve_component_path(disk[name]['path']))
        top = newest(base)
        if top != a.version and not os.path.exists(os.path.join(base, a.version)):
            plan.append((name, base, top))
    print(f'release {a.version}: freeze {len(plan)} component(s) as {a.version} '
          f'({a.components}); the rest are captured at their newest version')
    for name, base, top in plan[:8]:
        print(f'  {name:46s} {top} -> {a.version}')
    if len(plan) > 8:
        print(f'  … {len(plan) - 8} more')
    if not a.apply:
        print('dry run — --apply to copy and cut the release (the user\'s go-ahead)')
        return 0
    for name, base, top in plan:
        copy_version(base, top, a.version)
    # explicit component versions (release create would otherwise prefer a
    # component's `current` symlink): selected -> a.version, the rest -> newest
    comps = {}
    for name, info in disk.items():
        base = str(rc().resolve_component_path(info['path']))
        ver = a.version if (name in sel and os.path.isdir(os.path.join(base, a.version))) else newest(base)
        comps[name] = {'version': ver, 'path': info['path']}
    cfg_file = os.path.join(REL, f'.cut_{a.version}.json')
    with open(cfg_file, 'w') as fh:
        json.dump({'release': {'version': a.version, 'description': a.desc, 'milestone': ''},
                   'components': comps}, fh, indent=1)
    r = subprocess.run([CB, 'flow', 'release', 'create', '--config', cfg_file], capture_output=True, text=True)
    os.remove(cfg_file)
    out = r.stdout + r.stderr
    for l in out.splitlines():
        if re.search(r'Components linked|created|ERROR|Failed|already exists', l):
            print(l)
    if r.returncode or not os.path.exists(os.path.join(REL, a.version, 'MANIFEST.json')):
        die(f'release create failed — the {len(plan)} copied version dirs are kept for inspection')
    # freeze: the released versions of the selected components become read-only
    # (release_cmd._lock_version: .locked + 444 / 555); the manifest records which
    # components are frozen (the others are captured at their current, still
    # editable, version — not selected by version at run time yet)
    mf = os.path.join(REL, a.version, 'MANIFEST.json')
    m = manifest(a.version)
    frozen = []
    for name, c in m['components'].items():
        c['frozen'] = name in sel and c['version'] == a.version
        if c['frozen']:
            frozen.append(name)
    m['frozen_scope'] = a.components
    with open(mf, 'w') as fh:
        json.dump(m, fh, indent=2)
    for name in frozen:
        vd = rc().resolve_component_path(m['components'][name]['path']) / a.version
        rc()._lock_version(str(vd), a.version)
    rc()._lock_version(os.path.join(REL, a.version), a.version)
    print(f'release {a.version}: {len(m["components"])} components; {len(frozen)} frozen read-only at {a.version}; '
          f'{len(m["components"]) - len(frozen)} captured unfrozen. Pin a project: flowm.py pin --project <p> '
          f'--release {a.version} (or kickoff spec cbflow_release).')
    return 0


def cmd_status(a):
    vs = releases()
    cur = current_release()
    print(f'Flow releases ({os.path.relpath(REL, ROOT)}): {len(vs)}; current {cur or "-"}')
    for v in vs:
        m = manifest(v)
        hashed = sum(1 for c in m['components'].values() if c.get('hash'))
        print(f'  {v:10s} {m.get("created", "")[:10]}  {len(m["components"]):4d} components '
              f'({hashed} hashed)  {m.get("description", "")[:60]}' + ('   <- current' if v == cur else ''))
    latest = vs[-1] if vs else ''
    print('\nProjects:')
    for p, v in sorted(project_pins().items()):
        st = 'unset' if not v else ('missing release' if v not in vs else ('latest' if v == latest else f'behind {latest}'))
        print(f'  {p:14s} project(cbflow_release) {v or "-":10s} {st}')
    n_disk = len(rc().scan_versioned_components())
    if latest:
        n_rel = len(manifest(latest)['components'])
        if n_disk != n_rel:
            print(f'\nNOTE  {n_disk} versioned components on disk, {n_rel} in {latest} — `stale` lists the difference')
    return 0


def cmd_drift(a):
    v = a.release or current_release() or (releases() or [''])[-1]
    if not v:
        die('no release')
    m = manifest(v)
    created = m.get('created', '')[:19]
    changed, nohash = [], 0
    for name, c in sorted(m['components'].items()):
        vd = rc().resolve_component_path(c['path']) / c['version']
        if not vd.exists():
            changed.append((name, 'MISSING', str(vd)))
            continue
        if c.get('hash'):
            h = rc().component_hash(vd)
            if h != c['hash']:
                changed.append((name, 'EDITED', f'hash {c["hash"]} -> {h}'))
        else:
            nohash += 1
            r = subprocess.run(['git', 'log', '--oneline', f'--since={created}', '--', str(vd)], cwd=ROOT,
                               capture_output=True, text=True)
            n = len([l for l in r.stdout.splitlines() if l.strip()])
            if n:
                changed.append((name, 'COMMITS', f'{n} commit(s) since {created[:10]} (pre-hash release: git history)'))
    print(f'Drift of {v} (created {created[:10]}): {len(changed)} of {len(m["components"])} component(s) changed'
          + (f'; {nohash} without hash (git history used)' if nohash else ''))
    for name, kind, why in changed:
        print(f'  {kind:8s} {name:44s} {why}')
    if changed:
        print('\nProjects pinned to this release run the edited files — cut a new release (cbflow flow release '
              'create), or patch into a new version (flowm.py patch) so released content stays as released.')
    return 1 if changed else 0


def cmd_stale(a):
    v = a.release or (releases() or [''])[-1]
    rel = manifest(v)['components'] if v else {}
    disk = rc().scan_versioned_components()
    new = sorted(k for k in disk if k not in rel)
    moved = sorted(k for k in disk if k in rel and disk[k]['current'] != rel[k]['version'])
    gone = sorted(k for k in rel if k not in disk and not os.path.exists(
        str(rc().resolve_component_path(rel[k]['path']) / rel[k]['version'])))
    print(f'On disk vs {v or "(no release)"}: {len(new)} new, {len(moved)} newer version, {len(gone)} gone')
    for k in new:
        print(f'  NEW    {k:46s} {disk[k]["path"]} {disk[k]["current"]}')
    for k in moved:
        print(f'  NEWER  {k:46s} {rel[k]["version"]} -> {disk[k]["current"]}')
    for k in gone:
        print(f'  GONE   {k}')
    if new or moved:
        print(f'\nA new release would capture these: cbflow flow release create --type patch --desc "<what changed>"')
    return 0


def cmd_patch(a):
    disk = rc().scan_versioned_components()
    if a.component not in disk:
        die(f'{a.component}: no such versioned component (flowm.py stale lists them)')
    base = rc().resolve_component_path(disk[a.component]['path'])
    frm = a.from_version or disk[a.component]['current']
    src, dst = base / frm, base / a.to
    if not src.exists():
        die(f'{src} does not exist')
    if dst.exists():
        die(f'{dst} exists — edit it, or pick another version')
    print(f'{"copy" if a.apply else "would copy"} {os.path.relpath(src, ROOT)} -> {os.path.relpath(dst, ROOT)}')
    if not a.apply:
        print('dry run — --apply to create the new version (framework change: the user\'s explicit go-ahead)')
        return 0
    import shutil
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns('.locked', '__pycache__'))
    for dp, dn, fn in os.walk(dst):
        os.chmod(dp, 0o755)
        for f in fn:
            os.chmod(os.path.join(dp, f), 0o644 | (os.stat(os.path.join(dp, f)).st_mode & 0o111))
    print(f'created {os.path.relpath(dst, ROOT)} (writable; {frm} untouched)')
    print('next: edit the files in the new version (cmd-manager skill for command files) -> '
          f'cbflow flow release create --version <vX.Y.Z> --desc "..." (captures {a.to} as the newest) -> '
          f'flowm.py pin --project <p> --release <vX.Y.Z>. Projects not pinned to it keep {frm}.')
    return 0


def cmd_pin(a):
    if a.release not in releases():
        die(f'{a.release}: no such release ({", ".join(releases())})')
    files = glob.glob(os.path.join(ROOT, '*', 'config', 'project', a.project, 'v1.0.0', '*.tcl'))
    holder = [f for f in files if re.search(r'^\s*set\s+project\(cbflow_release\)', open(f, errors='replace').read(), re.M)]
    if not holder:
        die(f'project(cbflow_release) not set in any {a.project} project config')
    cfgm = os.path.join(ROOT, '.claude', 'skills', 'config-manager', 'scripts', 'cfgm.py')
    cmd = [cfgm, 'set', '--file', holder[-1], '--key', 'project(cbflow_release)', '--value', f'"{a.release}"',
           '--project', a.project, '--reason', a.reason or ''] + (['--apply'] if a.apply else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    print(r.stdout + r.stderr, end='')
    if r.returncode == 0 and a.apply:
        print(f'{a.project} now runs flow release {a.release} for new runs (workspace create); existing runs keep '
              f'their environment.')
    return r.returncode


def cmd_watch(a):
    pin = project_pins().get(a.project, '')
    vs = releases()
    if pin not in vs:
        print(f'{a.project}: project(cbflow_release) {pin or "unset"} is not a release ({", ".join(vs)})')
        return 1
    newer = vs[vs.index(pin) + 1:]
    created = manifest(pin).get('created', '')[:19]
    print(f'{a.project} runs {pin} (created {created[:10]}); newer releases: {", ".join(newer) or "none"}')
    for v in newer:
        print(f'  {v}: {manifest(v).get("description", "")}')
    trees = [d for d in ('PD/cmds', 'PD/config/flow', 'DFT/cmds', 'DV/cmds', 'RTL/cmds', 'global/utils',
                         'global/config/flow', 'global/config/exit') if os.path.exists(os.path.join(ROOT, d))]
    r = subprocess.run(['git', 'log', '--oneline', f'--since={created}', '--'] + trees, cwd=ROOT,
                       capture_output=True, text=True)
    commits = [l for l in r.stdout.splitlines() if l.strip()]
    print(f'framework commits since {pin}: {len(commits)}')
    for l in commits[:12]:
        print(f'  {l}')
    if len(commits) > 12:
        print(f'  … {len(commits) - 12} more')
    return 0


def cmd_issues(a):
    since = datetime.datetime.now() - datetime.timedelta(days=a.days)
    dbs = glob.glob(os.path.join(ROOT, '.race_area', '**', '*.db'), recursive=True)
    if a.project:
        dbs = [d for d in dbs if f'{os.sep}{a.project}{os.sep}' in d]
    groups = {}
    for db in dbs:
        if os.path.getmtime(db) < since.timestamp():
            continue
        try:
            con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
            cols = [r[1] for r in con.execute('PRAGMA table_info(jobs)')]
            if 'status' not in cols:
                continue
            q = 'SELECT job_name, status, ' + ('error_msg' if 'error_msg' in cols else "''") + ' FROM jobs WHERE status LIKE ?'
            rows = con.execute(q, ('%FAIL%',)).fetchall()
            info = dict(con.execute('SELECT key, value FROM run_info').fetchall()) if \
                con.execute("SELECT name FROM sqlite_master WHERE name='run_info'").fetchone() else {}
            con.close()
        except sqlite3.Error:
            continue
        flow = info.get('flow_type') or os.path.basename(os.path.dirname(db))
        for job, st, err in rows:
            stage = re.sub(r'_(setup|run|validate|finish)$', '', job)
            stage = re.sub(r'\d+(_.*)?$', '', stage)
            lines = [l.strip() for l in (err or '').splitlines() if l.strip() and l.strip() != 'ERRORS:']
            first = next((l for l in lines if 'ERROR' in l), lines[0] if lines else '')
            key = (flow, stage, first[:100])
            groups.setdefault(key, []).append(os.path.basename(db).split('_vmerugu')[0])
    print(f'Failed jobs in the last {a.days} day(s){" for " + a.project if a.project else ""}: '
          f'{sum(len(v) for v in groups.values())} in {len(groups)} group(s)')
    for (flow, stage, err), runs in sorted(groups.items(), key=lambda kv: -len(kv[1]))[:25]:
        print(f'  {len(runs):3d}x {flow:12s} {stage:16s} {err or "(no error text)"}')
    if a.audit:
        cmdm = os.path.join(ROOT, '.claude', 'skills', 'cmd-manager', 'scripts', 'cmdm.py')
        r = subprocess.run([cmdm, 'audit'], capture_output=True, text=True)
        tail = [l for l in r.stdout.splitlines() if l.startswith('[MISS')] + r.stdout.splitlines()[-1:]
        print('\ncommand-file audit:')
        for l in tail:
            print(f'  {l}')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('status')
    for n in ('drift', 'stale'):
        sub.add_parser(n).add_argument('--release')
    p = sub.add_parser('patch')
    p.add_argument('--component', required=True)
    p.add_argument('--from', dest='from_version')
    p.add_argument('--to', required=True)
    p.add_argument('--apply', action='store_true')
    p = sub.add_parser('pin')
    p.add_argument('--project', required=True)
    p.add_argument('--release', required=True)
    p.add_argument('--reason')
    p.add_argument('--apply', action='store_true')
    sub.add_parser('watch').add_argument('--project', required=True)
    p = sub.add_parser('edit')
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument('--component')
    g.add_argument('--file')
    p.add_argument('--apply', action='store_true')
    p = sub.add_parser('cut')
    p.add_argument('--version', required=True)
    p.add_argument('--desc', required=True)
    p.add_argument('--components', default='cmds', help='cmds (default) | all | comma list')
    p.add_argument('--apply', action='store_true')
    p = sub.add_parser('issues')
    p.add_argument('--project')
    p.add_argument('--days', type=int, default=7)
    p.add_argument('--audit', action='store_true')
    a = ap.parse_args()
    return {'status': cmd_status, 'drift': cmd_drift, 'stale': cmd_stale, 'patch': cmd_patch, 'pin': cmd_pin,
            'watch': cmd_watch, 'issues': cmd_issues, 'edit': cmd_edit, 'cut': cmd_cut}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
