#!/usr/bin/env python3
"""user-manager helper (user-manager skill): people and roles on top of
`cbflow flow access` (global/config/access/roles.json, core/access.py).

    um.py report    [--project P]                 users x projects x roles; problems
    um.py onboard   --user U --project P --role R [--disc D] [--block B] --reason T [--apply]
    um.py offboard  --user U [--project P] --reason T [--apply]     every role the user holds
    um.py readiness --project P [--days 30]      who enforcement would block (audit would-deny)

Writes go through `cbflow flow access grant|revoke` (its permission checks,
backup and CHANGELOG apply); this script only plans and calls it.
"""
import argparse
import collections
import datetime
import glob
import json
import os
import pwd
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'global', 'utils'))
from core import access  # noqa: E402

ACCESS = os.path.join(ROOT, 'global', 'utils', 'commands', 'access_cmd.py')


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def data():
    d = access.load_roles()
    if d is None:
        die('access not configured — cbflow flow access seed --apply (cad_admin)')
    return d


def entries(d):
    """[(user, role, project, qualifier)] of every assignment."""
    out = []
    for u in d.get('cad_admin', []):
        out.append((u, 'cad_admin', '', ''))
    for disc, names in (d.get('flow_owner') or {}).items():
        out += [(u, 'flow_owner', '', disc) for u in names]
    for proj, pr in (d.get('projects') or {}).items():
        for role, v in pr.items():
            if isinstance(v, dict):
                for q, names in v.items():
                    out += [(u, role, proj, q) for u in names]
            elif isinstance(v, list):
                out += [(u, role, proj, '') for u in v]
    return out


def login_exists(u):
    if u.startswith('group:'):
        return True
    try:
        pwd.getpwnam(u)
        return True
    except KeyError:
        return False


def cmd_report(a):
    d = data()
    ents = [e for e in entries(d) if not a.project or e[2] in ('', a.project)]
    by_user = collections.defaultdict(list)
    for u, role, proj, q in ents:
        by_user[u].append(f'{role}{"." + q if q else ""}{"@" + proj if proj else ""}')
    print(f'{len(by_user)} user(s){" on " + a.project if a.project else ""}:')
    for u in sorted(by_user):
        print(f'  {u:14s} {", ".join(sorted(by_user[u]))}')
    problems = []
    for u in sorted(by_user):
        if not login_exists(u):
            problems.append(f'{u}: no such login on this host (typo, left, or another host\'s account)')
    for proj, pr in sorted((d.get('projects') or {}).items()):
        if a.project and proj != a.project:
            continue
        if not pr.get('chip_lead'):
            problems.append(f'{proj}: no chip lead')
        for disc, names in (pr.get('discipline_lead') or {}).items():
            if not names:
                problems.append(f'{proj}: no {disc} discipline lead (only chip lead / cad_admin can release BTO / MTO for {disc})')
    if len(d.get('cad_admin', [])) < 2:
        problems.append('only one cad_admin — add a second for continuity')
    print('\nproblems:' if problems else '\nno problems')
    for p in problems:
        print(f'  - {p}')
    return 0


def run_access(args):
    r = subprocess.run([ACCESS] + args, capture_output=True, text=True)
    print((r.stdout + r.stderr).strip())
    return r.returncode


def cmd_onboard(a):
    if not login_exists(a.user):
        print(f'WARN  {a.user} is not a login on this host')
    args = ['grant', '--role', a.role, '--user', a.user, '--reason', a.reason or '']
    if a.project:
        args += ['--project', a.project]
    if a.disc:
        args += ['--disc', a.disc]
    if a.block:
        args += ['--block', a.block]
    print('plan: cbflow flow access ' + ' '.join(args))
    if not a.apply:
        print('dry run — --apply to grant (needs cad_admin, or the chip lead for their project\'s roles)')
        return 0
    return run_access(args)


def cmd_offboard(a):
    d = data()
    ents = [e for e in entries(d) if e[0] == a.user and (not a.project or e[2] == a.project)]
    if not ents:
        print(f'{a.user} holds no role' + (f' on {a.project}' if a.project else ''))
        return 0
    plans = []
    for u, role, proj, q in ents:
        args = ['revoke', '--role', role, '--user', u, '--reason', a.reason or '']
        if proj:
            args += ['--project', proj]
        if role in ('discipline_lead', 'flow_owner') and q:
            args += ['--disc', q]
        if role == 'block_owner':
            args += ['--block', q]
        plans.append(args)
    for p in plans:
        print('plan: cbflow flow access ' + ' '.join(p))
    if not a.apply:
        print(f'dry run — --apply to revoke {len(plans)} role(s)')
        return 0
    rc = 0
    for p in plans:
        rc |= run_access(p)
    return rc


def cmd_readiness(a):
    since = datetime.datetime.now() - datetime.timedelta(days=a.days)
    blocked = collections.defaultdict(collections.Counter)
    total = 0
    for f in [f for f in glob.glob(os.path.join(ROOT, '.access_audit', '*.jsonl')) if not os.path.basename(f).startswith('test-')]:
        for l in open(f):
            try:
                r = json.loads(l)
            except ValueError:
                continue
            if r.get('project') != a.project or datetime.datetime.fromisoformat(r['at']) < since:
                continue
            total += 1
            if r['decision'] in ('would-deny', 'deny'):
                blocked[r['user']][r['action']] += 1
    d = access.load_roles() or {}
    state = 'ON' if access.enforced(a.project, d) else 'OFF (audit only)'
    print(f'{a.project}: enforcement {state}; {total} access decision(s) in {a.days} day(s)')
    if not blocked:
        print('nobody would be blocked by enforcement — ready: cbflow flow access enforce on --project '
              f'{a.project} --reason "..." (cad_admin)')
        return 0
    print('would be blocked if enforcement were on:')
    for u, acts in sorted(blocked.items()):
        print(f'  {u:14s} ' + ', '.join(f'{k} x{v}' for k, v in acts.most_common()))
    print('grant the missing roles (um.py onboard) or confirm these users should be blocked, then enforce.')
    return 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('report').add_argument('--project')
    p = sub.add_parser('onboard')
    p.add_argument('--user', required=True)
    p.add_argument('--project')
    p.add_argument('--role', required=True)
    p.add_argument('--disc')
    p.add_argument('--block')
    p.add_argument('--reason')
    p.add_argument('--apply', action='store_true')
    p = sub.add_parser('offboard')
    p.add_argument('--user', required=True)
    p.add_argument('--project')
    p.add_argument('--reason')
    p.add_argument('--apply', action='store_true')
    p = sub.add_parser('readiness')
    p.add_argument('--project', required=True)
    p.add_argument('--days', type=int, default=30)
    a = ap.parse_args()
    return {'report': cmd_report, 'onboard': cmd_onboard, 'offboard': cmd_offboard,
            'readiness': cmd_readiness}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
