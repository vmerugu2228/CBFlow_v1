"""Single source of truth for the per-user dashboard daemon's state paths.

All paths live under ~/.cbflow/dashboard/. The directory and its subdirectories
are created with mode 0700 (owner-only) so other users on a shared host can't
peek at the run registry.
"""

import os


def root():
    """~/.cbflow/dashboard/ — created with mode 0700 if missing."""
    p = os.path.join(os.path.expanduser('~'), '.cbflow', 'dashboard')
    os.makedirs(p, mode=0o700, exist_ok=True)
    return p


def pidfile():
    return os.path.join(root(), 'dashboard.pid')


def portfile():
    return os.path.join(root(), 'dashboard.port')


def start_ts_file():
    return os.path.join(root(), 'dashboard.start_ts')


def logfile():
    return os.path.join(root(), 'dashboard.log')


def control_sock():
    return os.path.join(root(), 'control.sock')


def runs_dir():
    p = os.path.join(root(), 'runs')
    os.makedirs(p, mode=0o700, exist_ok=True)
    return p


def last_open_file():
    return os.path.join(root(), 'last_open.json')


def validate_socket_path():
    """AF_UNIX has a ~104-char path cap on macOS, 108 on Linux. Error loudly
    if our path overflows so the user sees a clear message instead of a cryptic
    bind() failure."""
    path = control_sock()
    if len(path.encode('utf-8')) > 100:
        raise RuntimeError(
            f'AF_UNIX socket path too long ({len(path)} bytes): {path}\n'
            f'  Override $HOME or move ~/.cbflow to a shorter path.')
    return path
