#!/usr/bin/env python3
"""cbflow flow access — roles and access (global/config/access/roles.json).

    cbflow flow access show    [--project P] [--user U]            roles per project / of a user
    cbflow flow access whoami  [--project P]                       my roles
    cbflow flow access check   --action A [--project P] [--disc D] [--block B] [--user U]
                                                                   exit 0 allowed / 1 denied (scripts, Tcl)
    cbflow flow access seed    [--apply]                           roles.json from master_projects.json
    cbflow flow access grant   --role R --user U [--project P] [--disc D] [--block B] [--for P2] --reason T
    cbflow flow access revoke  --role R --user U [--project P] [--disc D] [--block B] --reason T
    cbflow flow access enforce on|off [--project P | --framework] --reason T
    cbflow flow access audit   [--tail N] [--user U] [--project P] [--decision deny|would-deny|allow]

Roles: cad_admin, flow_owner (--disc), chip_lead, discipline_lead (--disc),
block_owner (--block), engineer, viewer, grant_read (read-only for a non-member).
grant / revoke: cad_admin for every role; a chip lead for the roles of their own
project (not chip_lead itself). enforce: cad_admin. Every change: backup +
global/config/access/CHANGELOG.jsonl.
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core import access  # noqa: E402

PROJECT_ROLES = ('chip_lead', 'discipline_lead', 'block_owner', 'engineer', 'viewer', 'grant_read')
GLOBAL_ROLES = ('cad_admin', 'flow_owner')
SENTINELS = {'', 'na', 'n/a', 'not specified', 'none', 'tbd'}


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def master():
    from core.paths import get_master_projects_path
    return json.load(open(get_master_projects_path()))


def login_like(v):
    return isinstance(v, str) and v.strip().lower() not in SENTINELS and \
        re.fullmatch(r'[a-z_][a-z0-9_.-]{0,31}', v.strip()) is not None


def save(data, reason, change):
    p = access.roles_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if os.path.exists(p):
        bdir = os.path.join(os.path.dirname(p), 'backup')
        os.makedirs(bdir, exist_ok=True)
        shutil.copy2(p, os.path.join(bdir, f'roles.json.{datetime.datetime.now():%Y%m%d-%H%M%S}.bak'))
    tmp = p + '.tmp'
    with open(tmp, 'w') as fh:
        json.dump(data, fh, indent=2)
        fh.write('\n')
    os.replace(tmp, p)
    with open(os.path.join(os.path.dirname(p), 'CHANGELOG.jsonl'), 'a') as fh:
        fh.write(json.dumps(dict(change, at=datetime.datetime.now().isoformat(timespec='seconds'),
                                 by=access.whoami(), reason=reason)) + '\n')


def need_data():
    d = access.load_roles()
    if d is None:
        die(f'access not configured: {access.roles_path()} missing — cbflow flow access seed')
    return d


# ── commands ────────────────────────────────────────────────────────────────
def cmd_seed(a):
    p = access.roles_path()
    if os.path.exists(p):
        die(f'{p} exists — use grant / revoke')
    m = master()
    me = access.whoami()
    data = {'enforce': {'default': False, 'framework': False, 'projects': {}},
            'cad_admin': [me], 'flow_owner': {d: [] for d in access.DISCIPLINES}, 'projects': {}}
    dropped = []
    for proj, e in sorted(m.get('projects', {}).items()):
        lead = e.get('chip_lead', '')
        fo = e.get('flow_owners', {}) or {}
        pr = {'chip_lead': [lead] if login_like(lead) else [], 'discipline_lead': {d: [] for d in access.DISCIPLINES},
              'block_owner': {}, 'engineer': [], 'viewer': [], 'grant_read': []}
        if not login_like(lead):
            dropped.append(f'{proj}: chip_lead "{lead}" is not a login')
        for field, discs in (('backend', ('PD', 'DFT')), ('frontend', ('RTL',)), ('verification', ('DV',))):
            v = fo.get(field, '')
            if login_like(v):
                for dd in discs:
                    pr['discipline_lead'][dd].append(v.strip())
            elif v and v.strip().lower() not in SENTINELS:
                dropped.append(f'{proj}: flow_owners.{field} "{v}" is not a login')
        data['projects'][proj] = pr
    print(f'seed: cad_admin {me}; {len(data["projects"])} project(s); enforcement OFF (audit only)')
    for proj, pr in data['projects'].items():
        dl = ', '.join(f'{d}:{"/".join(v)}' for d, v in pr['discipline_lead'].items() if v)
        print(f'  {proj:12s} chip_lead {"/".join(pr["chip_lead"]) or "-":10s} discipline_lead {dl or "-"}')
    for x in dropped:
        print(f'  DROPPED  {x} — grant the login explicitly')
    if not a.apply:
        print(f'dry run — --apply writes {p}')
        return 0
    save(data, 'seed from master_projects.json', {'op': 'seed'})
    print(f'wrote {p}')
    return 0


def cmd_show(a):
    d = need_data()
    print(f'cad_admin: {", ".join(d.get("cad_admin", [])) or "-"}')
    for disc, v in (d.get('flow_owner') or {}).items():
        if v:
            print(f'flow_owner.{disc}: {", ".join(v)}')
    e = d.get('enforce', {})
    print(f'enforce: default {e.get("default")}, framework {e.get("framework")}, '
          f'projects {", ".join(f"{k}={v}" for k, v in (e.get("projects") or {}).items()) or "-"}')
    for proj, pr in sorted((d.get('projects') or {}).items()):
        if a.project and proj != a.project:
            continue
        if a.user and not access.roles_of(a.user, proj, d) - {'cad_admin'} - {r for r in access.roles_of(a.user, None, d)}:
            continue
        print(f'\n{proj}' + (f'  (enforced)' if access.enforced(proj, d) else '  (audit only)'))
        for role in PROJECT_ROLES:
            v = pr.get(role)
            if isinstance(v, dict):
                for k, names in v.items():
                    if names:
                        print(f'  {role}.{k:10s} {", ".join(names)}')
            elif v:
                print(f'  {role:21s} {", ".join(v)}')
    if a.user:
        print(f'\n{a.user}: ' + '; '.join(f'{p}: {", ".join(sorted(access.roles_of(a.user, p, d)))}'
                                         for p in (d.get('projects') or {}) if access.roles_of(a.user, p, d)))
    return 0


def cmd_whoami(a):
    d = access.load_roles()
    me = access.whoami()
    if d is None:
        print(f'{me}: access not configured (audit only)')
        return 0
    projs = [a.project] if a.project else list((d.get('projects') or {}))
    print(f'{me}: global {", ".join(sorted(access.roles_of(me, None, d))) or "-"}')
    for p in projs:
        r = access.roles_of(me, p, d) - access.roles_of(me, None, d)
        if r or a.project:
            print(f'  {p:12s} {", ".join(sorted(r)) or "no role"}' + ('  (enforced)' if access.enforced(p, d) else ''))
    return 0


def cmd_check(a):
    ok, why = access.can(a.action, a.project, a.disc, a.block, a.user)
    enf = access.enforced(a.project)
    print(f'{"ALLOW" if ok else ("DENY" if enf else "WOULD-DENY")}: {why}')
    return 0 if ok or not enf else 1


def _target(d, a):
    if a.role in GLOBAL_ROLES:
        if a.role == 'cad_admin':
            return d.setdefault('cad_admin', [])
        if not a.disc:
            die('flow_owner needs --disc')
        return d.setdefault('flow_owner', {}).setdefault(a.disc, [])
    if not a.project:
        die(f'{a.role} needs --project')
    pr = d.setdefault('projects', {}).setdefault(a.project, {})
    if a.role == 'discipline_lead':
        if a.disc not in access.DISCIPLINES:
            die(f'discipline_lead needs --disc {"|".join(access.DISCIPLINES)}')
        return pr.setdefault('discipline_lead', {}).setdefault(a.disc, [])
    if a.role == 'block_owner':
        if not a.block:
            die('block_owner needs --block')
        return pr.setdefault('block_owner', {}).setdefault(a.block, [])
    return pr.setdefault(a.role, [])


def _may_grant(d, a):
    me = access.whoami()
    have = access.roles_of(me, a.project, d)
    if 'cad_admin' in have:
        return True
    if a.role in GLOBAL_ROLES or a.role == 'chip_lead':
        return False
    return 'chip_lead' in have


def cmd_grant(a, revoke=False):
    d = need_data()
    if not a.reason:
        die('--reason is required')
    if not (a.user.startswith('group:') or login_like(a.user)):
        die(f'{a.user}: not a login (or group:<unix group>)')
    if not _may_grant(d, a):
        die(f'{access.whoami()} may not {"revoke" if revoke else "grant"} {a.role}'
            + (f' on {a.project}' if a.project else '') + ' — cad_admin, or the project\'s chip lead for its roles')
    lst = _target(d, a)
    if revoke:
        if a.user not in lst:
            die(f'{a.user} does not hold {a.role}')
        if a.role == 'cad_admin' and len(lst) == 1:
            die('refusing to remove the last cad_admin')
        lst.remove(a.user)
    else:
        if a.user in lst:
            print(f'{a.user} already holds {a.role}')
            return 0
        lst.append(a.user)
    save(d, a.reason, {'op': 'revoke' if revoke else 'grant', 'role': a.role, 'user': a.user,
                       'project': a.project or '', 'disc': a.disc or '', 'block': a.block or ''})
    print(f'{"revoked" if revoke else "granted"} {a.role}' + (f'.{a.disc}' if a.disc and a.role in
          ('discipline_lead', 'flow_owner') else '') + (f'.{a.block}' if a.block else '')
          + f' {"from" if revoke else "to"} {a.user}' + (f' on {a.project}' if a.project else ''))
    return 0


def cmd_enforce(a):
    d = need_data()
    if 'cad_admin' not in access.roles_of(access.whoami(), None, d):
        die('only a cad_admin turns enforcement on / off')
    if not a.reason:
        die('--reason is required')
    on = a.state == 'on'
    e = d.setdefault('enforce', {})
    if a.framework:
        e['framework'] = on
        scope = 'framework'
    elif a.project:
        if a.project not in (d.get('projects') or {}):
            die(f'{a.project} not in roles.json')
        e.setdefault('projects', {})[a.project] = on
        scope = a.project
    else:
        e['default'] = on
        scope = 'default'
    save(d, a.reason, {'op': 'enforce', 'scope': scope, 'state': a.state})
    print(f'enforcement {a.state} for {scope}')
    return 0


def cmd_audit(a):
    from core.paths import get_cbflow_global_dir
    d = os.path.join(os.path.dirname(get_cbflow_global_dir()), '.access_audit')
    rows = []
    for f in sorted([f for f in glob.glob(os.path.join(d, '*.jsonl')) if not os.path.basename(f).startswith('test-')]):
        for l in open(f):
            try:
                r = json.loads(l)
            except ValueError:
                continue
            if (a.user and r['user'] != a.user) or (a.project and r['project'] != a.project) or \
                    (a.decision and r['decision'] != a.decision):
                continue
            rows.append(r)
    for r in rows[-a.tail:]:
        print(f'{r["at"]} {r["decision"]:10s} {r["user"]:10s} {r["action"]:24s} {r["project"]:10s} {r["why"][:90]}')
    print(f'{len(rows)} record(s)' + (f', showing last {min(a.tail, len(rows))}' if len(rows) > a.tail else ''))
    return 0


def main():
    ap = argparse.ArgumentParser(prog='cbflow flow access', description=__doc__.split('\n')[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__.split('\n\n')[1])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('show')
    p.add_argument('--project')
    p.add_argument('--user')
    sub.add_parser('whoami').add_argument('--project')
    p = sub.add_parser('check')
    p.add_argument('--action', required=True)
    p.add_argument('--project')
    p.add_argument('--disc')
    p.add_argument('--block')
    p.add_argument('--user')
    sub.add_parser('seed').add_argument('--apply', action='store_true')
    for n in ('grant', 'revoke'):
        p = sub.add_parser(n)
        p.add_argument('--role', required=True, choices=GLOBAL_ROLES + PROJECT_ROLES)
        p.add_argument('--user', required=True)
        p.add_argument('--project')
        p.add_argument('--disc', choices=access.DISCIPLINES)
        p.add_argument('--block')
        p.add_argument('--reason')
    p = sub.add_parser('enforce')
    p.add_argument('state', choices=['on', 'off'])
    p.add_argument('--project')
    p.add_argument('--framework', action='store_true')
    p.add_argument('--reason')
    p = sub.add_parser('audit')
    p.add_argument('--tail', type=int, default=30)
    p.add_argument('--user')
    p.add_argument('--project')
    p.add_argument('--decision', choices=['allow', 'deny', 'would-deny'])
    a = ap.parse_args()
    return {'show': cmd_show, 'whoami': cmd_whoami, 'check': cmd_check, 'seed': cmd_seed,
            'grant': cmd_grant, 'revoke': lambda x: cmd_grant(x, revoke=True), 'enforce': cmd_enforce,
            'audit': cmd_audit}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
