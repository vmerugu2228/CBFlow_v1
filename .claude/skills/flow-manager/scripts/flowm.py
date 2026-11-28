#!/usr/bin/env python3
"""flow-manager helper (flow-manager skill): CBflow framework (flow) releases —
what each project runs, what changed, patching a component, retagging projects,
watching new releases and flow issues.

    flowm.py status                                    releases, current, project pins
    flowm.py drift  [--release vX]                     released components edited since (hash + git)
    flowm.py stale  [--release vX]                     on disk vs the release: new / changed versions
    flowm.py patch  --component cmds.PNR.opensource.openroad [--from v1.0.0] --to v1.0.1 [--apply]
    flowm.py pin    --project P --release vX --reason TEXT [--apply]
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
    p = sub.add_parser('issues')
    p.add_argument('--project')
    p.add_argument('--days', type=int, default=7)
    p.add_argument('--audit', action='store_true')
    a = ap.parse_args()
    return {'status': cmd_status, 'drift': cmd_drift, 'stale': cmd_stale, 'patch': cmd_patch, 'pin': cmd_pin,
            'watch': cmd_watch, 'issues': cmd_issues}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
