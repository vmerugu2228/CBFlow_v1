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
import shutil

_VALID = ('PD', 'DFT')
_current = None


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


def _root_base():
    return os.path.join(os.path.expanduser('~'), '.cbflow', 'dashboard')


def root(discipline=None):
    """~/.cbflow/dashboard/<DISC>/ — created with mode 0700 if missing.

    On first access, migrates legacy single-daemon state
    (~/.cbflow/dashboard/{runs/,*.pid,*.port,...}) into PD/."""
    base = _root_base()
    os.makedirs(base, mode=0o700, exist_ok=True)
    _migrate_legacy_to_pd(base)
    p = os.path.join(base, _disc(discipline))
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


def pidfile(discipline=None):
    return os.path.join(root(discipline), 'dashboard.pid')


def portfile(discipline=None):
    return os.path.join(root(discipline), 'dashboard.port')


def start_ts_file(discipline=None):
    return os.path.join(root(discipline), 'dashboard.start_ts')


def logfile(discipline=None):
    return os.path.join(root(discipline), 'dashboard.log')


def control_sock(discipline=None):
    return os.path.join(root(discipline), 'control.sock')


def runs_dir(discipline=None):
    p = os.path.join(root(discipline), 'runs')
    os.makedirs(p, mode=0o700, exist_ok=True)
    return p


def last_open_file(discipline=None):
    return os.path.join(root(discipline), 'last_open.json')


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
