"""
CBflow Core — roles and access.

Who may do what, per project. Roles live in global/config/access/roles.json
(data only, edited through `cbflow flow access`); the action -> roles rules
live here. Every write path calls require(); it raises AccessDenied (a
PermissionError, so dashboards answer 403) when the user's roles do not allow
the action and enforcement is on for that scope. With enforcement off the
decision is only audited ("would deny") — the rollout mode.

Roles
  cad_admin                 everything (CAD / CSD)
  flow_owner.<DISC>         framework code / config of one discipline
  chip_lead                 one project: everything in it, waiver approval, flow
                            release pin, read grants
  discipline_lead.<DISC>    one project x discipline: overlay edits, every exit
                            incl. BTO / MTO, waiver requests, project library tags (PD)
  block_owner.<block>       one project x block: runs, exits before BTO / MTO
  engineer                  one project: runs, read
  viewer                    one project: read
  grant_read                read-only access to a project for named non-members

Identity: the login of the process uid (pwd), never $USER / $LOGNAME.
"""

import datetime
import grp
import json
import os
import pwd

from core.errors import AccessDenied

TAPEOUT_EXITS = ('BTO', 'MTO')
DISCIPLINES = ('PD', 'DFT', 'DV', 'RTL')


# ── identity / data ─────────────────────────────────────────────────────────
def whoami():
    """Login of the process uid. The test suite may impersonate with
    CBFLOW_ACCESS_TEST=1 + CBFLOW_ACCESS_TEST_USER (never honoured otherwise)."""
    if os.environ.get('CBFLOW_ACCESS_TEST') == '1' and os.environ.get('CBFLOW_ACCESS_TEST_USER'):
        return os.environ['CBFLOW_ACCESS_TEST_USER']
    return pwd.getpwuid(os.getuid()).pw_name


def roles_path():
    from core.paths import get_cbflow_global_dir
    return os.path.join(get_cbflow_global_dir(), 'config', 'access', 'roles.json')


def load_roles(path=None):
    """roles.json, or None when access is not configured yet (audit-only mode)."""
    p = path or os.environ.get('CBFLOW_ACCESS_ROLES') or roles_path()
    if not os.path.exists(p):
        return None
    with open(p) as fh:
        return json.load(fh)


def _members(names):
    """Expand a list of logins / 'group:<unix group>' entries to logins."""
    out = set()
    for n in names or []:
        if isinstance(n, str) and n.startswith('group:'):
            try:
                out.update(grp.getgrnam(n[6:]).gr_mem)
            except KeyError:
                pass
        elif n:
            out.add(n)
    return out


def roles_of(user, project=None, data=None):
    """{role[.qualifier]} the user holds (globally, and on project when given)."""
    d = data if data is not None else load_roles()
    if not d:
        return set()
    out = set()
    if user in _members(d.get('cad_admin')):
        out.add('cad_admin')
    for disc, names in (d.get('flow_owner') or {}).items():
        if user in _members(names):
            out.add(f'flow_owner.{disc}')
    if project:
        p = (d.get('projects') or {}).get(project) or {}
        for role in ('chip_lead', 'engineer', 'viewer'):
            if user in _members(p.get(role)):
                out.add(role)
        for disc, names in (p.get('discipline_lead') or {}).items():
            if user in _members(names):
                out.add(f'discipline_lead.{disc}')
        for blk, names in (p.get('block_owner') or {}).items():
            if user in _members(names):
                out.add(f'block_owner.{blk}')
        if user in _members(p.get('grant_read')):
            out.add('grant_read')
    return out


def holders(project=None, data=None):
    """{role: [logins]} for messages ('who can do this')."""
    d = data if data is not None else load_roles()
    out = {}
    if not d:
        return out
    out['cad_admin'] = sorted(_members(d.get('cad_admin')))
    if project:
        p = (d.get('projects') or {}).get(project) or {}
        out['chip_lead'] = sorted(_members(p.get('chip_lead')))
        for disc, names in (p.get('discipline_lead') or {}).items():
            out[f'discipline_lead.{disc}'] = sorted(_members(names))
    return out


# ── rules ───────────────────────────────────────────────────────────────────
def _exit_family(tag):
    import re
    return re.sub(r'_(ECO|v)\d+$', '', tag or '')


def allowed_roles(action, discipline=None, block=None):
    """Roles (besides cad_admin) that may perform action."""
    kind, _, arg = action.partition(':')
    lead = {'chip_lead'} | ({f'discipline_lead.{discipline}'} if discipline else
                            {f'discipline_lead.{d}' for d in DISCIPLINES})
    member = lead | {'engineer'} | ({f'block_owner.{block}'} if block else set())
    if kind == 'read':
        return member | {'viewer', 'grant_read'}
    if kind in ('run.create', 'run.mutate'):
        return member
    if kind in ('release.exit', 'release.lock', 'release.candidate'):
        if _exit_family(arg) in TAPEOUT_EXITS:
            return lead
        return lead | ({f'block_owner.{block}'} if block else set())
    if kind in ('release.publish', 'release.override', 'checklist.signoff', 'waiver.request'):
        return lead
    if kind in ('waiver.approve', 'release.cleanup', 'config.project.global', 'flow.release.pin',
                'project.manage', 'access.grant'):
        return {'chip_lead'}
    if kind == 'config.project':
        return {'chip_lead', f'discipline_lead.{arg or discipline}'}
    if kind == 'libtag.project':
        return {'chip_lead', 'discipline_lead.PD'}
    if kind == 'libtag.base':
        return {'flow_owner.PD'}
    if kind == 'config.framework':
        return {f'flow_owner.{arg or discipline}'}
    if kind in ('flow.release.cut', 'project.create', 'project.lead_change', 'access.admin',
                'framework.lock'):
        return set()
    raise ValueError(f'unknown access action: {action}')


def enforced(project=None, data=None):
    d = data if data is not None else load_roles()
    if not d:
        return False
    e = d.get('enforce') or {}
    if project:
        return bool((e.get('projects') or {}).get(project, e.get('default', False)))
    return bool(e.get('framework', e.get('default', False)))


def can(action, project=None, discipline=None, block=None, user=None, data=None):
    """(allowed, why) for the user's roles — independent of enforcement."""
    d = data if data is not None else load_roles()
    user = user or whoami()
    if d is None:
        return True, 'access not configured (global/config/access/roles.json missing) — audit only'
    have = roles_of(user, project, d)
    if 'cad_admin' in have:
        return True, f'{user}: cad_admin'
    need = allowed_roles(action, discipline, block)
    got = sorted(have & need)
    if got:
        return True, f'{user}: {", ".join(got)}'
    scope = f' on {project}' if project else ''
    who = holders(project, d)
    hint = '; '.join(f'{r}: {", ".join(v)}' for r, v in who.items() if v and (r in need or r == 'cad_admin'))
    return False, (f'{user} has {", ".join(sorted(have)) or "no role"}{scope}; needs '
                   f'{" or ".join(sorted(need | {"cad_admin"}))}' + (f' ({hint})' if hint else ''))


def audit(user, action, project, decision, why, target=''):
    try:
        from core.paths import get_cbflow_global_dir
        root = os.path.dirname(get_cbflow_global_dir())
        d = os.path.join(root, '.access_audit')
        os.makedirs(d, exist_ok=True)
        rec = {'at': datetime.datetime.now().isoformat(timespec='seconds'), 'user': user, 'action': action,
               'project': project or '', 'target': target, 'decision': decision, 'why': why}
        name = datetime.date.today().strftime('%Y-%m') + '.jsonl'
        if os.environ.get('CBFLOW_ACCESS_TEST') == '1':
            name = 'test-' + name          # impersonated test decisions stay out of reports
        with open(os.path.join(d, name), 'a') as fh:
            fh.write(json.dumps(rec) + '\n')
    except OSError:
        pass


def require(action, project=None, discipline=None, block=None, target='', data=None):
    """Raise AccessDenied unless allowed (or enforcement is off for the scope —
    then the denial is audited as 'would-deny' and the action proceeds)."""
    d = data if data is not None else load_roles()
    user = whoami()
    ok, why = can(action, project, discipline, block, user, d)
    if ok:
        audit(user, action, project, 'allow', why, target)
        return True
    if not enforced(project, d):
        audit(user, action, project, 'would-deny', why, target)
        return True
    audit(user, action, project, 'deny', why, target)
    raise AccessDenied(action, why)


def require_cli(action, project=None, discipline=None, block=None, target=''):
    """require() for command-line entry points: print the reason and exit 1."""
    try:
        return require(action, project, discipline, block, target)
    except AccessDenied as e:
        import sys
        print(f'ERROR: {e}', file=sys.stderr)
        print('       roles: cbflow flow access show --project <p>; ask a cad_admin / chip lead for access',
              file=sys.stderr)
        sys.exit(1)
