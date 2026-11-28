#!/usr/bin/env python3
"""cbflow flow release candidate / disks / cleanup — release versions and storage.

Every release of <phase>/<block>/<FLOW>/<tag> (first release, re-release,
--override, clone) is a new version:

  <release>/<phase>/<block>/<FLOW>/.versions/<tag>/v<n>/      the data (or a
                                                              symlink to it on a
                                                              release disk)
  <release>/<phase>/<block>/<FLOW>/<tag> -> .versions/<tag>/v<n>   CURRENT version
  <release>/<phase>/<block>/<FLOW>/.versions/<tag>/HISTORY.log     releases + candidate moves

The current version is the candidate every reader uses. A release that passes
becomes current (the latest release is the candidate); `candidate set` moves
current to another version, `candidate clear` back to the latest passing one.

candidate list    --project P [--phase PH] [--block B] [--all]   tags with >1 version or pinned (--all: every tag)
candidate show    --project P --phase PH --block B --flow F --tag T
candidate set     --project P --phase PH --block B --flow F --tag T --version vN [--reason TEXT]
candidate clear   --project P --phase PH --block B --flow F --tag T [--reason TEXT]
candidate history --project P --phase PH --block B --flow F --tag T
disks             --project P                                   release disks: size / free / versions held
lock              --project P --phase PH --block B --exit X [--flows F1,F2] --reason TEXT
unlock            --project P --phase PH --block B --exit X --reason TEXT   (locker or chip lead)
locks             --project P [--phase PH] [--block B]          current locks
waive             --project P --phase PH --block B --exit X --check STA|PV|LEC|CHECKLIST|<FLOW>
                  --reason TEXT --expires YYYY-MM-DD [--defer-to PARENT]   request a gate waiver
waive             --project P --phase PH --block B --approve ID            approve it (chip lead)
unwaive           --project P --phase PH --block B --id ID --reason TEXT   revoke / close
waivers           --project P [--phase PH] [--block B] [--exit X --check C --active] [--deferred-to B] [--json]

Gate waivers let a known, accepted issue (a signoff verdict FAIL, a BLOCKED
checklist) through the hierarchy gates (rtl2gds lock / library roll-up) without
being fixed at this block. Policy from global/config/exit/v1.0.0/waiver_config.tcl
(approval, expiry, max duration; BTO / MTO waivers only when allowed — otherwise
they must be deferred to a parent, whose own exit then carries them as open items
until its lead closes them with unwaive).
cleanup           --project P [--phase PH] [--block B] [--apply] dry run unless --apply
"""
import argparse
import getpass
import glob
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time

ROOT = os.environ.get('CBFLOW_ROOT') or os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
REGISTRY = os.path.join(ROOT, 'global', 'config', 'flow', 'v1.0.0', 'flow_registry.tcl')


def _me():
    """Authenticated login (uid; core.access.whoami) — never $USER."""
    sys.path.insert(0, os.path.join(ROOT, 'global', 'utils'))
    from core import access
    return access.whoami()


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
set _i [interp create]
$_i eval [list source {{{REGISTRY}}}]
foreach k {{size_margin disk_min_free_gb disk_policy cleanup,keep_versions cleanup,min_age_days cleanup,incomplete_age_hours}} {{
    if {{[catch {{$_i eval [list set flow(release,$k)]}} v]}} {{ puts stderr "flow(release,$k) is not set ({REGISTRY})"; exit 1 }}
    puts "key\\t$k\\t$v"
}}
if {{![info exists project(release,path)]}} {{ puts stderr "project(release,path) is not set"; exit 1 }}
puts "release\\t$project(release,path)"
puts "disks\\t[expr {{[info exists project(release,disks)] ? $project(release,disks) : ""}}]"
puts "phases\\t$project(phases)"
puts "tech\\t[expr {{[info exists project(technology)] ? $project(technology) : ""}}]"
puts "libroot\\t[expr {{[info exists project(lib_tag_root)] ? $project(lib_tag_root) : ""}}]"
dict for {{b d}} $project(design_hierarchy) {{ puts "block\\t$b\\t[expr {{[dict exists $d parent] ? [dict get $d parent] : ""}}]" }}
'''
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if r.returncode:
        die(f'cannot read the {project} config: {r.stderr.strip()}')
    cfg = {'blocks': [], 'parent': {}, 'key': {}, 'project': project}
    for line in r.stdout.splitlines():
        f = line.split('\t')
        if f[0] == 'block':
            cfg['blocks'].append(f[1])
            cfg['parent'][f[1]] = f[2] if len(f) > 2 else ''
        elif f[0] == 'key':
            cfg['key'][f[1]] = f[2]
        elif f[0] in ('phases', 'disks'):
            cfg[f[0]] = f[1].split() if len(f) > 1 else []
        else:
            cfg[f[0]] = f[1] if len(f) > 1 else ''
    return cfg


# ── versions ────────────────────────────────────────────────────────────────
def vnum(v):
    m = re.match(r'^v(\d+)$', v)
    return int(m.group(1)) if m else -1


def tag_paths(cfg, phase, block, flow, tag):
    fdir = os.path.join(cfg['release'], phase, block, flow)
    return os.path.join(fdir, tag), os.path.join(fdir, '.versions', tag)


def stamp_status(vdir):
    p = os.path.join(vdir, 'RELEASE_COMPLETE')
    if not os.path.exists(p):
        return 'INCOMPLETE'
    m = re.search(r'^STATUS=(\S+)', open(p).read(), re.M)
    return m.group(1) if m else 'PASS'


def versions(cfg, phase, block, flow, tag):
    """[{v, dir, status, time, storage, user, run}] oldest first."""
    logical, vroot = tag_paths(cfg, phase, block, flow, tag)
    out = []
    if os.path.isdir(vroot):
        for v in sorted((d for d in os.listdir(vroot) if vnum(d) > 0), key=vnum):
            d = os.path.join(vroot, v)
            m = {}
            try:
                m = json.load(open(os.path.join(d, 'MANIFEST.json')))
            except (OSError, ValueError):
                pass
            rc = os.path.join(d, 'RELEASE_COMPLETE')
            out.append({'v': v, 'dir': d, 'status': stamp_status(d),
                        'time': os.path.getmtime(rc) if os.path.exists(rc) else
                        (os.path.getmtime(d) if os.path.exists(d) else 0),
                        'storage': os.path.realpath(d), 'dangling': not os.path.exists(d),
                        'user': m.get('user', ''), 'run': os.path.basename(m.get('run_dir', ''))})
    return out


def current(cfg, phase, block, flow, tag):
    """(version, 'versioned'|'legacy'|None)."""
    logical, _ = tag_paths(cfg, phase, block, flow, tag)
    if os.path.islink(logical):
        return os.path.basename(os.readlink(logical)), 'versioned'
    if os.path.isdir(logical):
        return None, 'legacy'
    return None, None


def all_tags(cfg, phases=None, blocks=None):
    """[(phase, block, flow, tag)] — versioned tags and legacy dirs."""
    out = set()
    for ph in phases or cfg['phases']:
        for b in blocks or cfg['blocks']:
            bdir = os.path.join(cfg['release'], ph, b)
            for fdir in glob.glob(os.path.join(bdir, '*')):
                if not os.path.isdir(fdir):
                    continue
                fl = os.path.basename(fdir)
                for t in os.listdir(fdir):
                    if not t.startswith('.') and os.path.isdir(os.path.join(fdir, t)):
                        out.add((ph, b, fl, t))
                for t in glob.glob(os.path.join(fdir, '.versions', '*')):
                    out.add((ph, b, fl, os.path.basename(t)))
    return sorted(out)


def set_current(logical, vdir):
    tmp = f'{logical}.tmp{os.getpid()}'
    os.symlink(os.path.relpath(vdir, os.path.dirname(logical)), tmp)
    os.replace(tmp, logical)


def hist(vroot, *fields):
    with open(os.path.join(vroot, 'HISTORY.log'), 'a') as fh:
        fh.write('\t'.join([time.strftime('%Y-%m-%dT%H:%M:%S'), _me()] + [str(f) for f in fields]) + '\n')


def ts(t):
    return time.strftime('%Y-%m-%d %H:%M', time.localtime(t)) if t else '-'


def latest_pass(vs):
    ok = [v for v in vs if v['status'] == 'PASS' and not v['dangling']]
    return ok[-1] if ok else None


def check_scope(cfg, a):
    if a.phase and a.phase not in cfg['phases']:
        die(f'phase {a.phase} not in project(phases) {cfg["phases"]}')
    if getattr(a, 'block', None) and a.block not in cfg['blocks']:
        die(f'block {a.block} not in project(design_hierarchy) {cfg["blocks"]}')


def need_versioned(cfg, a):
    cur, kind = current(cfg, a.phase, a.block, a.flow, a.tag)
    logical, vroot = tag_paths(cfg, a.phase, a.block, a.flow, a.tag)
    if kind is None:
        die(f'{logical}: not released')
    if kind == 'legacy':
        die(f'{logical} is an unversioned release (before versioning) — its next release makes it v1')
    return cur, logical, vroot


# ── release locks ───────────────────────────────────────────────────────────
LOCK_FIELDS = ['exit', 'flows', 'user', 'at', 'reason']


def family(tag):
    m = re.match(r'^(.*)_(?:ECO|v)\d+$', tag)
    return m.group(1) if m else tag


def read_locks(cfg, phase, block):
    p = os.path.join(cfg['release'], phase, block, 'RELEASE_LOCKS')
    out = {}
    if os.path.exists(p):
        for line in open(p):
            if line.strip() and not line.startswith('#'):
                f = line.rstrip('\n').split('\t')
                out[f[0]] = dict(zip(LOCK_FIELDS, f + [''] * (len(LOCK_FIELDS) - len(f))))
    return out


def write_locks(cfg, phase, block, locks):
    d = os.path.join(cfg['release'], phase, block)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, 'RELEASE_LOCKS')
    tmp = f'{p}.tmp{os.getpid()}'
    with open(tmp, 'w') as fh:
        fh.write('# ' + '\t'.join(f.upper() for f in LOCK_FIELDS) + '   (cbflow flow release lock)\n')
        for x in sorted(locks):
            fh.write('\t'.join(str(locks[x].get(k, '')).replace('\t', ' ').replace('\n', ' ')
                               for k in LOCK_FIELDS) + '\n')
    os.replace(tmp, p)


def lock_log(cfg, phase, block, rec):
    with open(os.path.join(cfg['release'], phase, block, 'RELEASE_LOCKS.log'), 'a') as fh:
        fh.write(json.dumps(rec) + '\n')


def locked(cfg, phase, block, flow, tag):
    """The lock that covers releasing / moving <flow>/<tag>, or None."""
    lk = read_locks(cfg, phase, block).get(family(tag))
    if lk and (lk['flows'] == '*' or flow in lk['flows'].split(',')):
        return lk
    return None


def refuse_if_locked(cfg, phase, block, flow, tag, what):
    lk = locked(cfg, phase, block, flow, tag)
    if lk:
        die(f'{what} {phase}/{block} {flow}/{tag} refused — exit {lk["exit"]} is LOCKED by {lk["user"]} '
            f'({lk["at"]}): {lk["reason"]}\n       unlock: cbflow flow release unlock --project {cfg["project"]} '
            f'--phase {phase} --block {block} --exit {lk["exit"]} --reason <why>')


def cmd_lock(cfg, a):
    check_scope(cfg, a)
    if not a.reason:
        die('--reason is required (who depends on this exit)')
    locks = read_locks(cfg, a.phase, a.block)
    if a.exit in locks:
        lk = locks[a.exit]
        die(f'{a.phase}/{a.block} {a.exit} already locked by {lk["user"]} ({lk["at"]}): {lk["reason"]}')
    flows = '*' if a.flows in (None, '', 'all') else ','.join(x.strip() for x in a.flows.split(','))
    rel = glob.glob(os.path.join(cfg['release'], a.phase, a.block, '*', a.exit, 'RELEASE_COMPLETE'))
    if not rel:
        print(f'WARN  {a.phase}/{a.block} has no {a.exit} release yet — locking prevents the first one too')
    entry = {'exit': a.exit, 'flows': flows, 'user': _me(),
             'at': time.strftime('%Y-%m-%dT%H:%M:%S'), 'reason': a.reason}
    locks[a.exit] = entry
    write_locks(cfg, a.phase, a.block, locks)
    cur = {os.path.basename(os.path.dirname(os.path.dirname(r))):
           current(cfg, a.phase, a.block, os.path.basename(os.path.dirname(os.path.dirname(r))), a.exit)[0]
           for r in rel}
    lock_log(cfg, a.phase, a.block, dict(entry, action='lock', current=cur))
    print(f'LOCKED {a.phase}/{a.block} {a.exit} ({"all flows" if flows == "*" else flows})'
          + (f' — current: {", ".join(f"{f} {v or chr(45)}" for f, v in sorted(cur.items()))}' if cur else ''))
    print(f'  releases of {a.exit} / {a.exit}_ECO<n>, clones into it and candidate moves are refused until unlock')
    return 0


def cmd_unlock(cfg, a):
    check_scope(cfg, a)
    if not a.reason:
        die('--reason is required')
    locks = read_locks(cfg, a.phase, a.block)
    if a.exit not in locks:
        die(f'{a.phase}/{a.block} {a.exit} is not locked')
    lk = locks[a.exit]
    me = _me()
    lead = registry().get('projects', {}).get(cfg['project'], {}).get('chip_lead', '')
    if me not in (lk['user'], lead):
        die(f'{a.exit} was locked by {lk["user"]}; only they or the chip lead ({lead or "unset"}) can unlock it')
    del locks[a.exit]
    write_locks(cfg, a.phase, a.block, locks)
    lock_log(cfg, a.phase, a.block, {'exit': a.exit, 'action': 'unlock', 'user': me,
                                    'at': time.strftime('%Y-%m-%dT%H:%M:%S'), 'reason': a.reason,
                                    'was': f'{lk["user"]} {lk["at"]}: {lk["reason"]}'})
    print(f'UNLOCKED {a.phase}/{a.block} {a.exit} (was locked by {lk["user"]} {lk["at"]})')
    return 0


def cmd_locks(cfg, a):
    check_scope(cfg, a)
    rows = []
    for ph in [a.phase] if a.phase else cfg['phases']:
        for b in [a.block] if a.block else cfg['blocks']:
            for x, lk in sorted(read_locks(cfg, ph, b).items()):
                rows.append((ph, b, x, lk['flows'], lk['user'], lk['at'], lk['reason']))
    if not rows:
        print('No release locks.')
        return 0
    print(f'{"PHASE":6s} {"BLOCK":14s} {"EXIT":16s} {"FLOWS":10s} {"BY":10s} {"AT":20s} REASON')
    for r in rows:
        print(f'{r[0]:6s} {r[1]:14s} {r[2]:16s} {r[3]:10s} {r[4]:10s} {r[5]:20s} {r[6]}')
    return 0


# ── gate waivers ─────────────────────────────────────────────────────────────
WAIVER_POLICY = os.path.join(ROOT, 'global', 'config', 'exit', 'v1.0.0', 'waiver_config.tcl')


def waiver_policy():
    script = f'''source {{{WAIVER_POLICY}}}
foreach k {{require_approval require_expiry_date max_waiver_duration_days allow_bto_waivers allow_mto_waivers}} {{
    if {{![info exists waiver_policy($k)]}} {{ puts stderr "waiver_policy($k) is not set ({WAIVER_POLICY})"; exit 1 }}
    puts "$k=$waiver_policy($k)"
}}'''
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if r.returncode:
        die(f'waiver policy: {r.stderr.strip()}')
    return dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)


def _true(v):
    return str(v).strip().lower() in ('1', 'true', 'yes', 'on')


def waivers_path(cfg, phase, block):
    return os.path.join(cfg['release'], phase, block, 'GATE_WAIVERS.json')


def read_waivers(cfg, phase, block):
    p = waivers_path(cfg, phase, block)
    return json.load(open(p)) if os.path.exists(p) else []


def write_waivers(cfg, phase, block, ws, rec):
    d = os.path.join(cfg['release'], phase, block)
    os.makedirs(d, exist_ok=True)
    p = waivers_path(cfg, phase, block)
    tmp = f'{p}.tmp{os.getpid()}'
    json.dump(ws, open(tmp, 'w'), indent=1)
    os.replace(tmp, p)
    with open(os.path.join(d, 'GATE_WAIVERS.log'), 'a') as fh:
        fh.write(json.dumps(rec) + '\n')


def waiver_state(w, today=None):
    """pending | active | expired | revoked | closed"""
    if w.get('state') in ('revoked', 'closed'):
        return w['state']
    if w.get('expires') and (today or time.strftime('%Y-%m-%d')) > w['expires']:
        return 'expired'
    return w.get('state', 'pending')


def ancestors(cfg, block):
    out, b = [], cfg['parent'].get(block, '')
    while b and b not in out:
        out.append(b)
        b = cfg['parent'].get(b, '')
    return out


def cmd_waive(cfg, a):
    check_scope(cfg, a)
    ws = read_waivers(cfg, a.phase, a.block)
    me, now = _me(), time.strftime('%Y-%m-%dT%H:%M:%S')
    pol = waiver_policy()
    if a.approve:
        w = next((x for x in ws if x['id'] == a.approve), None)
        if not w:
            die(f'{a.phase}/{a.block}: no waiver {a.approve}')
        if waiver_state(w) != 'pending':
            die(f'{a.approve} is {waiver_state(w)}, not pending')
        sys.path.insert(0, os.path.join(ROOT, 'global', 'utils'))
        from core import access
        if me == w['requested_by'] and 'chip_lead' not in access.roles_of(me, cfg['project']):
            die(f'{a.approve} was requested by {me}: another person (the chip lead) approves it')
        w.update(state='active', approved_by=me, approved_at=now)
        write_waivers(cfg, a.phase, a.block, ws, {'action': 'approve', 'id': w['id'], 'user': me, 'at': now})
        print(f'APPROVED {w["id"]} {a.phase}/{a.block} {w["exit"]} {w["check"]} (until {w["expires"]})'
              + (f' — deferred to {w["defer_to"]}' if w.get('defer_to') else ''))
        return 0
    for k in ('exit', 'check', 'reason'):
        if not getattr(a, k):
            die(f'--{k} is required')
    ex, check = family(a.exit), a.check.upper()
    if _true(pol['require_expiry_date']) and not a.expires:
        die('--expires YYYY-MM-DD is required (waiver policy)')
    if a.expires:
        try:
            days = (time.mktime(time.strptime(a.expires, '%Y-%m-%d')) - time.time()) / 86400
        except ValueError:
            die(f'--expires {a.expires}: YYYY-MM-DD')
        if days < -1:
            die(f'--expires {a.expires} is in the past')
        if days > float(pol['max_waiver_duration_days']):
            die(f'--expires {a.expires}: more than {pol["max_waiver_duration_days"]} days (waiver policy)')
    up = ancestors(cfg, a.block)
    if a.defer_to:
        if a.defer_to not in up:
            die(f'--defer-to {a.defer_to}: not a parent of {a.block} (ancestors: {", ".join(up) or "none — top level"})')
    elif (ex == 'BTO' and not _true(pol['allow_bto_waivers'])) or (ex == 'MTO' and not _true(pol['allow_mto_waivers'])):
        die(f'{ex} waivers are not allowed (waiver policy) — defer the issue to a parent '
            f'(--defer-to {up[0] if up else "<none: top level>"}), whose own {ex} then carries it until closed')
    for x in ws:
        if x['exit'] == ex and x['check'] == check and waiver_state(x) in ('pending', 'active'):
            die(f'{x["id"]} already covers {a.phase}/{a.block} {ex} {check} ({waiver_state(x)})')
    wid = f'W{len(ws) + 1}'
    w = {'id': wid, 'exit': ex, 'check': check, 'reason': a.reason, 'defer_to': a.defer_to or '',
         'expires': a.expires or '', 'requested_by': me, 'requested_at': now,
         'state': 'pending' if _true(pol['require_approval']) else 'active'}
    ws.append(w)
    write_waivers(cfg, a.phase, a.block, ws, dict(w, action='request', user=me, at=now))
    print(f'{"REQUESTED" if w["state"] == "pending" else "ACTIVE"} {wid} {a.phase}/{a.block} {ex} {check}'
          + (f' — deferred to {w["defer_to"]}' if w['defer_to'] else '') + f' (until {w["expires"] or "-"})')
    if w['state'] == 'pending':
        print(f'  approve (chip lead): cbflow flow release waive --project {cfg["project"]} --phase {a.phase} '
              f'--block {a.block} --approve {wid}')
    return 0


def cmd_unwaive(cfg, a):
    check_scope(cfg, a)
    if not a.reason:
        die('--reason is required')
    ws = read_waivers(cfg, a.phase, a.block)
    w = next((x for x in ws if x['id'] == a.id), None)
    if not w:
        die(f'{a.phase}/{a.block}: no waiver {a.id}')
    me, now = _me(), time.strftime('%Y-%m-%dT%H:%M:%S')
    # an active deferral is closed (the parent verified / fixed it); anything else revoked
    st = 'closed' if w.get('defer_to') and waiver_state(w) == 'active' else 'revoked'
    w.update(state=st, closed_by=me, closed_at=now, close_reason=a.reason)
    write_waivers(cfg, a.phase, a.block, ws, {'action': st, 'id': a.id, 'user': me, 'at': now, 'reason': a.reason})
    print(f'{st.upper()} {a.id} {a.phase}/{a.block} {w["exit"]} {w["check"]}')
    return 0


def cmd_waivers(cfg, a):
    check_scope(cfg, a)
    rows = []
    for ph in [a.phase] if a.phase else cfg['phases']:
        for b in [a.block] if a.block else cfg['blocks']:
            for w in read_waivers(cfg, ph, b):
                st = waiver_state(w)
                if a.exit and w['exit'] != family(a.exit):
                    continue
                if a.check and w['check'] != a.check.upper():
                    continue
                if a.active and st != 'active':
                    continue
                if a.deferred_to and (w.get('defer_to') != a.deferred_to or st != 'active'):
                    continue
                rows.append(dict(w, phase=ph, block=b, status=st))
    if a.json:
        print(json.dumps(rows))
        return 0
    if not rows:
        print('No gate waivers.')
        return 0
    print(f'{"ID":4s} {"PHASE":6s} {"BLOCK":14s} {"EXIT":12s} {"CHECK":10s} {"STATUS":8s} {"DEFER_TO":14s} '
          f'{"EXPIRES":10s} {"BY":10s} REASON')
    for r in rows:
        print(f'{r["id"]:4s} {r["phase"]:6s} {r["block"]:14s} {r["exit"]:12s} {r["check"]:10s} {r["status"]:8s} '
              f'{r.get("defer_to") or "-":14s} {r.get("expires") or "-":10s} '
              f'{r.get("approved_by") or r["requested_by"]:10s} {r["reason"]}')
    return 0


def registry():
    return json.load(open(os.path.join(ROOT, 'global', 'config', 'master_projects.json')))


# ── candidate ───────────────────────────────────────────────────────────────
def cmd_list(cfg, a):
    check_scope(cfg, a)
    rows = []
    for ph, b, fl, t in all_tags(cfg, [a.phase] if a.phase else None, [a.block] if a.block else None):
        cur, kind = current(cfg, ph, b, fl, t)
        vs = versions(cfg, ph, b, fl, t)
        lp = latest_pass(vs)
        if kind == 'legacy':
            state = 'unversioned'
        elif kind is None:
            state = 'no current (never passed)'
        elif lp and cur != lp['v']:
            state = f'pinned (latest {lp["v"]})'
        else:
            state = 'latest'
        if a.all or len(vs) > 1 or state.startswith('pinned') or kind is None:
            rows.append((ph, b, fl, t, cur or '-', len(vs), state))
    if not rows:
        print('No tag with more than one version or a pinned candidate (--all lists every tag).')
        return 0
    print(f'{"PHASE":6s} {"BLOCK":14s} {"FLOW":14s} {"TAG":20s} {"CURRENT":8s} {"VERS":5s} STATE')
    for ph, b, fl, t, c, n, st in rows:
        print(f'{ph:6s} {b:14s} {fl:14s} {t:20s} {c:8s} {n:<5d} {st}')
    return 0


def cmd_show(cfg, a):
    check_scope(cfg, a)
    cur, kind = current(cfg, a.phase, a.block, a.flow, a.tag)
    vs = versions(cfg, a.phase, a.block, a.flow, a.tag)
    logical, _ = tag_paths(cfg, a.phase, a.block, a.flow, a.tag)
    if kind is None and not vs:
        die(f'{logical}: not released')
    lp = latest_pass(vs)
    how = 'unversioned release' if kind == 'legacy' else \
        ('latest' if lp and cur == lp['v'] else f'pinned (latest passing: {lp["v"] if lp else "-"})')
    print(f'{a.phase} {a.block} {a.flow}/{a.tag}: current {cur or "-"} — {how}')
    for v in reversed(vs):
        mark = '*' if v['v'] == cur else ' '
        where = '' if v['storage'].startswith(os.path.realpath(cfg['release'])) else f'  [{v["storage"]}]'
        print(f'  {mark} {v["v"]:5s} {v["status"]:10s} {ts(v["time"])}  {v["user"]:10s} {v["run"]}{where}'
              + ('  DANGLING' if v['dangling'] else ''))
    return 0


def cmd_set(cfg, a):
    check_scope(cfg, a)
    refuse_if_locked(cfg, a.phase, a.block, a.flow, a.tag, 'candidate set')
    cur, logical, vroot = need_versioned(cfg, a)
    vs = {v['v']: v for v in versions(cfg, a.phase, a.block, a.flow, a.tag)}
    if a.version not in vs:
        die(f'{a.flow}/{a.tag} has no {a.version} (versions: {", ".join(vs) or "-"})')
    v = vs[a.version]
    if v['dangling'] or v['status'] != 'PASS':
        die(f'{a.flow}/{a.tag} {a.version} is {"missing" if v["dangling"] else v["status"]} — only a PASS version can be current')
    if a.version == cur:
        print(f'{a.flow}/{a.tag}: {a.version} is already current')
        return 0
    set_current(logical, v['dir'])
    hist(vroot, 'candidate', a.version, f'was {cur}', a.reason or '')
    print(f'{a.phase} {a.block} {a.flow}/{a.tag}: current {cur} -> {a.version}'
          + ('' if v is latest_pass(list(vs.values())) else '  (pinned; the next release moves current to it)'))
    return 0


def cmd_clear(cfg, a):
    check_scope(cfg, a)
    refuse_if_locked(cfg, a.phase, a.block, a.flow, a.tag, 'candidate clear')
    cur, logical, vroot = need_versioned(cfg, a)
    lp = latest_pass(versions(cfg, a.phase, a.block, a.flow, a.tag))
    if not lp:
        die(f'{a.flow}/{a.tag}: no PASS version')
    if lp['v'] == cur:
        print(f'{a.flow}/{a.tag}: current {cur} is already the latest')
        return 0
    set_current(logical, lp['dir'])
    hist(vroot, 'candidate', lp['v'], f'was {cur} (clear -> latest)', a.reason or '')
    print(f'{a.phase} {a.block} {a.flow}/{a.tag}: current {cur} -> {lp["v"]} (latest)')
    return 0


def cmd_history(cfg, a):
    check_scope(cfg, a)
    _, vroot = tag_paths(cfg, a.phase, a.block, a.flow, a.tag)
    p = os.path.join(vroot, 'HISTORY.log')
    if not os.path.exists(p):
        print('No history.')
        return 0
    for line in open(p):
        print('  ' + line.rstrip('\n').replace('\t', '  '))
    return 0


# ── disks ───────────────────────────────────────────────────────────────────
def du_kb(path):
    try:
        return int(subprocess.run(['du', '-sk', path], capture_output=True, text=True).stdout.split()[0])
    except (IndexError, ValueError, OSError):
        return 0


def gb(kb):
    return f'{kb / 1048576:.1f}'


def cmd_disks(cfg, a):
    disks = cfg['disks'] or [cfg['release']]
    print(f'Release tree {cfg["release"]}  (policy {cfg["key"]["disk_policy"]}, reserve '
          f'{cfg["key"]["disk_min_free_gb"]} GB, size margin {cfg["key"]["size_margin"]})')
    if not cfg['disks']:
        print('project(release,disks) not set: releases are stored in the release tree itself.')
    print(f'{"DISK":50s} {"SIZE GB":>8s} {"FREE GB":>8s} {"USED%":>6s} {"VERSIONS":>8s} {"HELD GB":>8s}')
    for d in disks:
        if not os.path.isdir(d):
            print(f'{d:50s}  not a directory')
            continue
        u = shutil.disk_usage(d)
        vs = glob.glob(os.path.join(d, '*', '*', '*', '.versions', '*', 'v*')) if d == cfg['release'] and not cfg['disks'] \
            else glob.glob(os.path.join(d, '*', '*', '*', '*', 'v*'))
        held = du_kb(d) if a.sizes else 0
        print(f'{d:50s} {gb(u.total // 1024):>8s} {gb(u.free // 1024):>8s} {100 * u.used / u.total:>5.0f}% '
              f'{len(vs):>8d} {gb(held) if a.sizes else "-":>8s}')
    return 0


# ── cleanup ─────────────────────────────────────────────────────────────────
def published_dirs(cfg):
    """realpaths of release dirs published to SmartGrid (None: unknown)."""
    sys.path.insert(0, os.path.join(ROOT, 'global', 'utils', 'project_dashboard'))
    try:
        import state_paths
        db = state_paths.tracker_db(cfg['project'])
    except Exception:  # noqa: BLE001 — no SmartGrid state
        return None
    if not os.path.exists(db):
        return set()
    con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
    rows = con.execute('SELECT release_dir FROM published_runs WHERE project=?', (cfg['project'],)).fetchall()
    con.close()
    return {os.path.realpath(r[0]) for r in rows if r[0]}


def libtag_sources(cfg):
    out = set()
    if cfg.get('libroot') and cfg.get('tech'):
        for bc in glob.glob(os.path.join(cfg['libroot'], cfg['tech'], '*', 'blocks_config.tcl')):
            for p in re.findall(r'set tech\(block,\w+,(?:pv_)?release\)\s+"([^"]+)"', open(bc).read()):
                if p != 'PENDING':
                    out.add(os.path.realpath(p))
    return out


def consumed_versions(cfg, keep):
    """realpaths of versions a kept version's run read (MANIFEST upstream_tags
    resolved at the kept version's release time: the version current then)."""
    out = set()
    for vdir in keep:
        try:
            m = json.load(open(os.path.join(vdir, 'MANIFEST.json')))
        except (OSError, ValueError):
            continue
        bdir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(vdir))))  # <phase>/<block>
        if os.path.basename(os.path.dirname(os.path.dirname(vdir))) != '.versions':
            continue
        t_rel = os.path.getmtime(os.path.join(vdir, 'RELEASE_COMPLETE')) \
            if os.path.exists(os.path.join(vdir, 'RELEASE_COMPLETE')) else time.time()
        for t in m.get('signoff_status', {}).get('upstream_tags', []):
            for vroot in glob.glob(os.path.join(bdir, '*', '.versions', t)):
                older = [d for d in glob.glob(os.path.join(vroot, 'v*'))
                         if os.path.exists(os.path.join(d, 'RELEASE_COMPLETE'))
                         and os.path.getmtime(os.path.join(d, 'RELEASE_COMPLETE')) <= t_rel + 1]
                if older:
                    out.add(os.path.realpath(max(older, key=lambda d: os.path.getmtime(os.path.join(d, 'RELEASE_COMPLETE')))))
    return out


def cmd_cleanup(cfg, a):
    check_scope(cfg, a)
    k = cfg['key']
    keep_n, min_age = int(k['cleanup,keep_versions']), float(k['cleanup,min_age_days']) * 86400
    inc_age = float(k['cleanup,incomplete_age_hours']) * 3600
    now = time.time()
    pub = published_dirs(cfg)
    if pub is None:
        print('WARNING: SmartGrid state not readable — published versions cannot be identified; '
              'nothing published-looking is removed (all superseded versions kept).')
    libsrc = libtag_sources(cfg)
    remove, keep_all = [], []
    tags = all_tags(cfg, [a.phase] if a.phase else None, [a.block] if a.block else None)
    for ph, b, fl, t in tags:
        cur, kind = current(cfg, ph, b, fl, t)
        logical, vroot = tag_paths(cfg, ph, b, fl, t)
        vs = versions(cfg, ph, b, fl, t)
        for v in vs:
            if v['dangling']:
                remove.append((v['dir'], 0, 'dangling version link (disk data gone)', 'link'))
        good = [v for v in vs if not v['dangling']]
        passed = [v for v in good if v['status'] == 'PASS']
        kept_newest = {v['v'] for v in [x for x in passed[::-1] if x['v'] != cur][:keep_n]}
        for v in good:
            real = v['storage']
            why_keep = []
            if v['v'] == cur:
                why_keep.append('current')
            if v['v'] in kept_newest:
                why_keep.append(f'newest {keep_n} superseded')
            if pub is None or real in pub:
                why_keep.append('published' if pub is not None else 'publish state unknown')
            if real in libsrc:
                why_keep.append('library-tag source')
            if v['status'] == 'INCOMPLETE':
                if v['v'] != cur and now - os.path.getmtime(v['dir']) > inc_age:
                    remove.append((v['dir'], du_kb(real), f'incomplete (no RELEASE_COMPLETE, '
                                   f'{(now - os.path.getmtime(v["dir"])) / 3600:.0f} h old)', 'version'))
                continue
            if why_keep:
                keep_all.append(v['dir'])
                continue
            if now - v['time'] < min_age:
                keep_all.append(v['dir'])
                continue
            remove.append((v['dir'], None, f'superseded {v["status"]} version (current {cur}, '
                           f'{(now - v["time"]) / 86400:.0f} d old)', 'version'))
    # never remove what a kept version was built from
    protect = consumed_versions(cfg, keep_all)
    remove = [r for r in remove if r[3] == 'link' or os.path.realpath(r[0]) not in protect]
    # orphan data on release disks: v<n> dirs no version link points to
    if cfg['disks']:
        linked = {os.path.realpath(v['dir']) for ph, b, fl, t in all_tags(cfg) for v in versions(cfg, ph, b, fl, t)}
        for d in cfg['disks']:
            for vd in glob.glob(os.path.join(d, a.phase or '*', a.block or '*', '*', '*', 'v*')):
                if os.path.realpath(vd) not in linked and now - os.path.getmtime(vd) > inc_age:
                    remove.append((vd, du_kb(vd), 'orphan disk data (no version link)', 'orphan'))
    if not remove:
        print('Nothing to clean up.')
        return 0
    total = 0
    print(f'{"ACTION":7s} {"SIZE GB":>8s}  PATH — REASON')
    for path, kb, why, kind in remove:
        kb = du_kb(os.path.realpath(path)) if kb is None else kb
        total += kb
        print(f'{"remove" if a.apply else "would":7s} {gb(kb):>8s}  {os.path.relpath(path, cfg["release"]) if path.startswith(cfg["release"]) else path} — {why}')
    print(f'\n{len(remove)} item(s), {gb(total)} GB'
          + ('' if a.apply else ' — dry run; rerun with --apply to delete (permanent)'))
    if not a.apply:
        return 0
    log = open(os.path.join(cfg['release'], 'CLEANUP.log'), 'a')
    for path, kb, why, kind in remove:
        real = os.path.realpath(path)
        if kind == 'version' and os.path.islink(path):
            if os.path.isdir(real):
                shutil.rmtree(real)
            os.unlink(path)
        elif os.path.islink(path):
            os.unlink(path)
        elif os.path.isdir(path):
            shutil.rmtree(path)
        log.write(json.dumps({'at': time.strftime('%Y-%m-%dT%H:%M:%S'), 'user': _me(),
                              'path': path, 'storage': real, 'reason': why}) + '\n')
        vroot = os.path.dirname(path)
        if os.path.basename(os.path.dirname(vroot)) == '.versions':
            hist(vroot, 'cleanup', os.path.basename(path), why)
    log.close()
    print(f'Removed {len(remove)} item(s); log {os.path.join(cfg["release"], "CLEANUP.log")}')
    return 0


def _access_gate(a):
    """roles / access (core.access) for the release-management verbs."""
    sys.path.insert(0, os.path.join(ROOT, 'global', 'utils'))
    from core import access
    disc = ''
    if getattr(a, 'flow', None):
        try:
            from core import registry
            disc = registry.flow_discipline(a.flow)
        except Exception:  # noqa: BLE001
            disc = ''
    blk = getattr(a, 'block', None)
    tgt = '/'.join(x for x in (getattr(a, 'phase', None), blk, getattr(a, 'flow', None), getattr(a, 'tag', None)) if x)
    if a.cmd in ('set', 'clear'):
        access.require_cli(f'release.candidate:{a.tag}', a.project, disc, blk, tgt)
    elif a.cmd in ('lock', 'unlock'):
        access.require_cli(f'release.lock:{a.exit}', a.project, disc, blk, f'{tgt} {a.exit}')
    elif a.cmd == 'waive':
        if a.approve:
            access.require_cli('waiver.approve', a.project, disc, blk, f'{tgt} gate {a.approve}')
        else:
            access.require_cli('waiver.request', a.project, disc, blk, f'{tgt} gate {a.exit} {a.check}')
    elif a.cmd == 'unwaive':
        access.require_cli('waiver.approve', a.project, disc, blk, f'{tgt} gate {a.id}')
    elif a.cmd == 'cleanup' and getattr(a, 'apply', False):
        access.require_cli('release.cleanup', a.project, target=tgt or 'cleanup')
    else:
        access.require_cli('read', a.project, disc, blk, tgt or a.cmd)


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ('disks', 'cleanup', 'lock', 'unlock', 'locks',
                                             'waive', 'unwaive', 'waivers'):
        group, argv = sys.argv[1], sys.argv[2:]
    else:
        group, argv = 'candidate', sys.argv[1:]
    ap = argparse.ArgumentParser(prog=f'cbflow flow release {group}', description=__doc__.split('\n')[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=__doc__.split('\n\n', 1)[1])
    if group == 'candidate':
        sub = ap.add_subparsers(dest='cmd', required=True)
        for name in ('list', 'show', 'set', 'clear', 'history'):
            p = sub.add_parser(name)
            p.add_argument('--project', required=True)
            p.add_argument('--release-path', help='release tree (default project(release,path))')
            p.add_argument('--phase', required=name != 'list')
            p.add_argument('--block', required=name != 'list')
            if name == 'list':
                p.add_argument('--all', action='store_true')
            else:
                p.add_argument('--flow', required=True)
                p.add_argument('--tag', required=True)
            if name == 'set':
                p.add_argument('--version', required=True)
            if name in ('set', 'clear'):
                p.add_argument('--reason')
        a = ap.parse_args(argv)
    elif group in ('lock', 'unlock', 'locks'):
        ap.add_argument('--project', required=True)
        ap.add_argument('--release-path', help='release tree (default project(release,path))')
        ap.add_argument('--phase', required=group != 'locks')
        ap.add_argument('--block', required=group != 'locks')
        if group != 'locks':
            ap.add_argument('--exit', required=True)
            ap.add_argument('--reason')
        if group == 'lock':
            ap.add_argument('--flows', help='comma list of flows (default: all)')
        a = ap.parse_args(argv)
        a.cmd = group
    elif group in ('waive', 'unwaive', 'waivers'):
        ap.add_argument('--project', required=True)
        ap.add_argument('--release-path', help='release tree (default project(release,path))')
        ap.add_argument('--phase', required=group != 'waivers')
        ap.add_argument('--block', required=group != 'waivers')
        if group == 'waive':
            ap.add_argument('--exit')
            ap.add_argument('--check', help='STA | PV | LEC | CHECKLIST | <FLOW>')
            ap.add_argument('--reason')
            ap.add_argument('--expires', help='YYYY-MM-DD')
            ap.add_argument('--defer-to', help='parent block that takes the issue over')
            ap.add_argument('--approve', metavar='ID', help='approve a pending waiver (chip lead)')
        elif group == 'unwaive':
            ap.add_argument('--id', required=True)
            ap.add_argument('--reason')
        else:
            ap.add_argument('--exit')
            ap.add_argument('--check')
            ap.add_argument('--active', action='store_true')
            ap.add_argument('--deferred-to')
            ap.add_argument('--json', action='store_true')
        a = ap.parse_args(argv)
        a.cmd = group
    elif group == 'disks':
        ap.add_argument('--project', required=True)
        ap.add_argument('--release-path', help='release tree (default project(release,path))')
        ap.add_argument('--sizes', action='store_true', help='du each disk (slow on large disks)')
        a = ap.parse_args(argv)
        a.cmd = 'disks'
    else:
        ap.add_argument('--project', required=True)
        ap.add_argument('--release-path', help='release tree (default project(release,path))')
        ap.add_argument('--phase')
        ap.add_argument('--block')
        ap.add_argument('--apply', action='store_true', help='delete (permanent); default is a dry run')
        a = ap.parse_args(argv)
        a.cmd = 'cleanup'
    cfg = project_values(a.project)
    _access_gate(a)
    if getattr(a, 'release_path', None):
        # a sandbox / alternate release tree (as a user config's project(release,path))
        cfg['release'] = os.path.abspath(a.release_path)
    return {'list': cmd_list, 'show': cmd_show, 'set': cmd_set, 'clear': cmd_clear, 'history': cmd_history,
            'disks': cmd_disks, 'cleanup': cmd_cleanup, 'lock': cmd_lock, 'unlock': cmd_unlock,
            'locks': cmd_locks, 'waive': cmd_waive, 'unwaive': cmd_unwaive,
            'waivers': cmd_waivers}[a.cmd](cfg, a)


if __name__ == '__main__':
    sys.exit(main())
