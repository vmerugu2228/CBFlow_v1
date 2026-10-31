"""State paths for CBflow-ProjectDashboard.

State layout under `~/.cbflow/project-dashboard/<project>/`:

  dashboard.pid           Owner PID (O_EXCL create for lifecycle atomicity)
  dashboard.port          HTTP port the daemon bound to
  dashboard.start_ts      Process start-timestamp — pairs with pid to detect PID recycling
  dashboard.bind_addr     "127.0.0.1" or "0.0.0.0" — decides the URL scheme
  dashboard.log           stderr/stdout of the daemon
  control.sock            AF_UNIX socket for JSON-RPC (publish/unpublish/list/ping)
  tracker.db              SQLite: snapshot rows keyed by (project, block, phase, milestone)

The daemon is intrinsically project-scoped — every verb requires a
`--project <name>` flag. Multiple projects can run their own daemons
under the same user; each gets its own directory and port via
deterministic hash.
"""

import os
import re

_PROJECT_RE = re.compile(r'^[A-Za-z0-9_\-]+$')
_current_project = None


def set_project(p):
    """Set the process-wide project scope. All subsequent path lookups use this
    project unless overridden with an explicit `project=` arg."""
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
    if _current_project:
        return _current_project
    env = os.environ.get('CBFLOW_PROJECT_DASHBOARD_PROJECT', '').strip()
    if env and _PROJECT_RE.match(env):
        return env
    return ''


def _proj(p):
    if p is None:
        return get_project()
    p = str(p).strip()
    if not p:
        return ''
    if not _PROJECT_RE.match(p):
        raise ValueError(f'invalid project name: {p!r}')
    return p


def _root_base():
    return os.path.join(os.path.expanduser('~'), '.cbflow', 'project-dashboard')


def root(project=None):
    """Per-project state dir. Errors if no project is set — the project
    dashboard is intrinsically project-scoped, unlike the run dashboard."""
    proj = _proj(project)
    if not proj:
        raise RuntimeError(
            'project scope is required for CBflow-ProjectDashboard. '
            'Pass --project <name> or set state_paths.set_project(<name>).')
    base = _root_base()
    os.makedirs(base, mode=0o700, exist_ok=True)
    p = os.path.join(base, proj)
    os.makedirs(p, mode=0o700, exist_ok=True)
    return p


def pidfile(project=None):
    return os.path.join(root(project), 'dashboard.pid')


def portfile(project=None):
    return os.path.join(root(project), 'dashboard.port')


def bind_addr_file(project=None):
    return os.path.join(root(project), 'dashboard.bind_addr')


def start_ts_file(project=None):
    return os.path.join(root(project), 'dashboard.start_ts')


def logfile(project=None):
    return os.path.join(root(project), 'dashboard.log')


def control_sock(project=None):
    return os.path.join(root(project), 'control.sock')


def tracker_db(project=None):
    return os.path.join(root(project), 'tracker.db')


def validate_socket_path(project=None):
    """AF_UNIX has a ~104-char path cap on macOS, 108 on Linux."""
    path = control_sock(project)
    if len(path.encode('utf-8')) > 100:
        raise RuntimeError(
            f'AF_UNIX socket path too long ({len(path)} bytes): {path}\n'
            f'  Override $HOME or move ~/.cbflow to a shorter path.')
    return path
