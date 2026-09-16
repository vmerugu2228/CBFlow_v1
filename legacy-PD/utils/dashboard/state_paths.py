"""Single source of truth for the per-user dashboard daemon's state paths.

State is scoped by discipline ("PD" or "DFT") so the two engineering teams can
run independent daemons under the same user account:

  ~/.cbflow/dashboard/PD/      — PD daemon: pidfile, port, runs/, control.sock
  ~/.cbflow/dashboard/DFT/     — DFT daemon: same shape, separate listener

All paths are mode 0700 (owner-only) so other users on a shared host can't peek
at the run registry.

Discipline resolution order (lowest wins):
  1. explicit `discipline=` arg
  2. `state_paths.set_discipline()` (process-level)
  3. `CBFLOW_DASHBOARD_DISCIPLINE` env var
  4. "PD" (back-compat default)
"""

import os
import re
import shutil

_VALID = ('PD', 'DFT')
_current = None
_current_project = None
_PROJECT_RE = re.compile(r'^[A-Za-z0-9_\-]+$')


def set_discipline(d):
    """Set the process-wide default discipline. Subsequent calls without an
    explicit `discipline=` arg use this."""
    global _current
    if d is None:
        _current = None
        return
    d = str(d).upper()
    if d not in _VALID:
        raise ValueError(f'unknown discipline: {d!r} (valid: {_VALID})')
    _current = d


def get_discipline():
    if _current:
        return _current
    env = os.environ.get('CBFLOW_DASHBOARD_DISCIPLINE', '').upper()
    if env in _VALID:
        return env
    return 'PD'


def _disc(d):
    if d is None:
        return get_discipline()
    d = str(d).upper()
    if d not in _VALID:
        raise ValueError(f'unknown discipline: {d!r} (valid: {_VALID})')
    return d


def set_project(p):
    """Set the process-wide project scope. When a project is active, state
    paths get a project sub-dir and the daemon gets its own port band, so
    each project's daemon is fully isolated. Pass None / empty to clear
    (back-compat unscoped shared-discipline daemon)."""
    global _current_project
    if p is None or p == '':
        _current_project = None
        return
    p = str(p).strip()
    if not _PROJECT_RE.match(p):
        raise ValueError(
            f'invalid project name: {p!r} (must match [A-Za-z0-9_-]+)')
    _current_project = p


def get_project():
    """Return the active project scope, or '' if unscoped."""
    if _current_project:
        return _current_project
    env = os.environ.get('CBFLOW_DASHBOARD_PROJECT', '').strip()
    if env and _PROJECT_RE.match(env):
        return env
    return ''


def _proj(p):
    """Normalize a project arg the same way _disc normalizes discipline."""
    if p is None:
        return get_project()
    p = str(p).strip()
    if not p:
        return ''
    if not _PROJECT_RE.match(p):
        raise ValueError(f'invalid project name: {p!r}')
    return p


def _root_base():
    return os.path.join(os.path.expanduser('~'), '.cbflow', 'dashboard')


def root(discipline=None, project=None):
    """State dir for the (discipline, project) daemon.

      Unscoped (no project):  ~/.cbflow/dashboard/<DISC>/
      Project-scoped:         ~/.cbflow/dashboard/<DISC>/projects/<NAME>/

    Created with mode 0700 if missing. On first access, migrates legacy
    single-daemon state into PD/. The project sub-tree lives under
    `projects/` (not directly under the discipline) so it never collides
    with the discipline-level files (dashboard.pid, runs/, …)."""
    base = _root_base()
    os.makedirs(base, mode=0o700, exist_ok=True)
    _migrate_legacy_to_pd(base)
    p = os.path.join(base, _disc(discipline))
    os.makedirs(p, mode=0o700, exist_ok=True)
    proj = _proj(project)
    if proj:
        p = os.path.join(p, 'projects', proj)
        os.makedirs(p, mode=0o700, exist_ok=True)
    return p


def _migrate_legacy_to_pd(base):
    """Move pre-discipline files into PD/ subdir if PD/ doesn't exist yet."""
    pd = os.path.join(base, 'PD')
    if os.path.isdir(pd):
        return  # already migrated
    legacy_items = ('runs', 'dashboard.pid', 'dashboard.port',
                    'dashboard.start_ts', 'dashboard.log',
                    'control.sock', 'last_open.json')
    legacy_present = any(os.path.exists(os.path.join(base, n)) for n in legacy_items)
    if not legacy_present:
        return
    os.makedirs(pd, mode=0o700, exist_ok=True)
    for n in legacy_items:
        src = os.path.join(base, n)
        if os.path.exists(src):
            try:
                shutil.move(src, os.path.join(pd, n))
            except OSError:
                pass


def pidfile(discipline=None, project=None):
    return os.path.join(root(discipline, project), 'dashboard.pid')


def portfile(discipline=None, project=None):
    return os.path.join(root(discipline, project), 'dashboard.port')


def bind_addr_file(discipline=None, project=None):
    """Records the bind address the daemon used. Read by lifecycle to
    pick the right hostname for the URL (127.0.0.1 stays as-is; anything
    else uses gethostname() so remote browsers can reach it)."""
    return os.path.join(root(discipline, project), 'dashboard.bind_addr')


def start_ts_file(discipline=None, project=None):
    return os.path.join(root(discipline, project), 'dashboard.start_ts')


def logfile(discipline=None, project=None):
    return os.path.join(root(discipline, project), 'dashboard.log')


def control_sock(discipline=None, project=None):
    return os.path.join(root(discipline, project), 'control.sock')


def runs_dir(discipline=None, project=None):
    p = os.path.join(root(discipline, project), 'runs')
    os.makedirs(p, mode=0o700, exist_ok=True)
    return p


def last_open_file(discipline=None, project=None):
    return os.path.join(root(discipline, project), 'last_open.json')


def validate_socket_path(discipline=None):
    """AF_UNIX has a ~104-char path cap on macOS, 108 on Linux. Error loudly
    if our path overflows so the user sees a clear message instead of a cryptic
    bind() failure."""
    path = control_sock(discipline)
    if len(path.encode('utf-8')) > 100:
        raise RuntimeError(
            f'AF_UNIX socket path too long ({len(path)} bytes): {path}\n'
            f'  Override $HOME or move ~/.cbflow to a shorter path.')
    return path
