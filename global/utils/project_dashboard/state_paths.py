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


def sibling_daemon_url(project):
    """Return the smartgrid daemon's URL for `project`, or '' if not running.

    Used by the Tier 1 all-projects grid in router._render_tier1_projects
    and by the cross-project 302 redirect in _route. Looks only at the
    filesystem under `~/.cbflow/project-dashboard/<project>/` — does NOT
    call root() (which creates the dir as a side effect; we must stay
    read-only for projects we don't own).

    Liveness: the recorded pid must still exist. A stale portfile from
    a crashed daemon returns ''.

    Mirrors global/utils/dashboard/state_paths.py::daemon_url_for.
    """
    proj = (project or '').strip()
    if not proj or not _PROJECT_RE.match(proj):
        return ''

    base_dir = os.path.join(_root_base(), proj)
    portf = os.path.join(base_dir, 'dashboard.port')
    pidf = os.path.join(base_dir, 'dashboard.pid')
    if not (os.path.isfile(portf) and os.path.isfile(pidf)):
        return ''
    try:
        with open(portf) as f:
            port = f.read().strip()
        with open(pidf) as f:
            pid = int(f.read().strip())
        if not port or not pid:
            return ''
        # Liveness check — stale portfile from a crashed daemon returns ''.
        try:
            os.kill(pid, 0)
        except OSError:
            return ''
    except (OSError, ValueError):
        return ''

    bind = '127.0.0.1'
    bind_file = os.path.join(base_dir, 'dashboard.bind_addr')
    if os.path.isfile(bind_file):
        try:
            with open(bind_file) as f:
                recorded = f.read().strip()
            if recorded and recorded not in ('127.0.0.1', '0.0.0.0'):
                bind = recorded
            elif recorded == '0.0.0.0':
                # Public bind — rewrite to the hostname so remote browsers
                # can reach the URL.
                import socket
                bind = socket.gethostname()
        except OSError:
            pass
    return f'http://{bind}:{port}/'


def sibling_tracker_db(project):
    """Return the on-disk tracker.db path for `project` without creating
    anything. Returns '' if the file doesn't exist.

    Used by Tier 1 to read sibling projects' published-run counts without
    side-effecting their state directories.
    """
    proj = (project or '').strip()
    if not proj or not _PROJECT_RE.match(proj):
        return ''
    p = os.path.join(_root_base(), proj, 'tracker.db')
    return p if os.path.isfile(p) else ''
