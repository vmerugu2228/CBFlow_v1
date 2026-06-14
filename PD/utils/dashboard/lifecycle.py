"""Client-side helpers for talking to the dashboard daemon.

Used by `cbflow run gui --daemon` and the new `cbflow dashboard ...` commands.
"""

import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import daemon as _daemon
import registry
import state_paths


# ── Daemon lifecycle ────────────────────────────────────────────────────────

def status():
    """Return the daemon status dict (state/pid/port/reason)."""
    return _daemon.existing_daemon_status()


def is_running():
    return status()['state'] == 'running'


def ensure_daemon(port=0, wait_s=4.0):
    """Make sure the daemon is up. Spawn it in the background if not.
    Returns the port the daemon is listening on.

    Raises RuntimeError on bring-up failure (e.g. port collision).
    """
    st = status()
    if st['state'] == 'running':
        return st['port']

    if st['state'] == 'stale':
        _daemon.cleanup_stale_state()

    chosen = port or _daemon.deterministic_port()

    daemon_py = os.path.join(SCRIPT_DIR, 'daemon.py')
    log_fd = open(state_paths.logfile(), 'ab', buffering=0)
    proc = subprocess.Popen(
        [sys.executable, daemon_py, 'serve', '--port', str(chosen)],
        stdin=subprocess.DEVNULL,
        stdout=log_fd,
        stderr=log_fd,
        start_new_session=True,
        close_fds=True,
    )

    deadline = time.time() + wait_s
    sock_path = state_paths.control_sock()
    while time.time() < deadline:
        time.sleep(0.1)
        if proc.poll() is not None:
            log_fd.close()
            tail = _tail_log(20)
            raise RuntimeError(
                f'dashboard daemon exited immediately (rc={proc.returncode}). '
                f'Recent log:\n{tail}')
        # Daemon is ready when BOTH the pidfile says running AND the control
        # socket exists. Otherwise the first send_register() races and fails
        # with "no such file or directory".
        st = status()
        if st['state'] == 'running' and os.path.exists(sock_path):
            log_fd.close()
            return st['port']

    log_fd.close()
    raise RuntimeError(
        f'dashboard daemon did not come up within {wait_s}s. '
        f'Recent log:\n{_tail_log(20)}')


def stop(wait_s=5.0):
    """Stop the running daemon (SIGTERM, then SIGKILL after wait_s).
    Returns True if a daemon was stopped, False if none was running."""
    st = status()
    if st['state'] != 'running':
        if st['state'] == 'stale':
            _daemon.cleanup_stale_state()
        return False

    # Prefer graceful shutdown via control socket — it cleans state files.
    try:
        send_control({'op': 'shutdown'}, timeout=2.0)
    except OSError:
        pass

    deadline = time.time() + wait_s
    while time.time() < deadline:
        time.sleep(0.1)
        if status()['state'] != 'running':
            return True

    # Force.
    try:
        os.kill(st['pid'], signal.SIGTERM)
    except OSError:
        pass
    time.sleep(0.5)
    if status()['state'] == 'running':
        try:
            os.kill(st['pid'], signal.SIGKILL)
        except OSError:
            pass
        time.sleep(0.3)
    _daemon.cleanup_stale_state()
    return True


# ── Control-socket IPC ──────────────────────────────────────────────────────

def send_control(msg, timeout=3.0):
    """Send one JSON message to the daemon's control socket and return its
    JSON reply. Raises OSError on connect/IO failure."""
    sock_path = state_paths.control_sock()
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(sock_path)
        s.sendall((json.dumps(msg) + '\n').encode('utf-8'))
        chunks = []
        while True:
            try:
                buf = s.recv(4096)
            except socket.timeout:
                break
            if not buf:
                break
            chunks.append(buf)
            if b'\n' in buf:
                break
        data = b''.join(chunks).split(b'\n', 1)[0]
        return json.loads(data.decode('utf-8'))
    finally:
        try:
            s.close()
        except OSError:
            pass


def send_register(run_dir):
    return send_control({'op': 'register',
                         'run_dir': os.path.realpath(os.path.abspath(run_dir))})


def send_deregister(run_or_id):
    if os.sep in run_or_id:
        return send_control({'op': 'deregister', 'run_dir': run_or_id})
    return send_control({'op': 'deregister', 'run_id': run_or_id})


def send_list():
    return send_control({'op': 'list'})


# ── Browser launch (reuses race_dashboard's ladder, adds SSH guard) ─────────

def is_ssh_session():
    return bool(os.environ.get('SSH_CLIENT')
                or os.environ.get('SSH_TTY')
                or os.environ.get('SSH_CONNECTION'))


def open_browser(url):
    """Best-effort browser launch. No-op under SSH (returns False).

    Idempotency: a small JSON file at ~/.cbflow/dashboard/last_open.json
    suppresses re-launches of the same URL within 5 seconds. Stable URLs from
    the daemon already make this rare, but the dedup catches racing shells.
    """
    if is_ssh_session():
        return False

    if _recently_opened(url):
        return True

    ladder = [
        ('google-chrome', [url]),
        ('chromium-browser', [url]),
        ('firefox', ['-new-tab', url]),
        ('xdg-open', [url]),
        ('open', [url]),  # macOS
    ]
    for browser, args in ladder:
        exe = shutil.which(browser)
        if not exe:
            continue
        try:
            subprocess.Popen([exe] + args,
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL,
                             start_new_session=True)
            _record_open(url)
            return True
        except OSError:
            continue

    import webbrowser
    try:
        webbrowser.open_new_tab(url)
        _record_open(url)
        return True
    except Exception:
        return False


def _recently_opened(url, window_s=5):
    path = state_paths.last_open_file()
    if not os.path.exists(path):
        return False
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return False
    ts = data.get(url, 0)
    return (time.time() - ts) < window_s


def _record_open(url):
    path = state_paths.last_open_file()
    try:
        data = {}
        if os.path.exists(path):
            with open(path) as f:
                data = json.load(f)
        data[url] = time.time()
        with open(path, 'w') as f:
            json.dump(data, f)
        os.chmod(path, 0o600)
    except (OSError, ValueError):
        pass


# ── Misc ────────────────────────────────────────────────────────────────────

def _tail_log(n=20):
    path = state_paths.logfile()
    if not os.path.exists(path):
        return '(no log)'
    try:
        with open(path) as f:
            lines = f.readlines()[-n:]
        return ''.join(lines)
    except OSError:
        return '(log unreadable)'


def url_for_run(run_dir):
    """Compute the deep-link URL for a registered run, given the daemon port.
    Raises RuntimeError if the daemon isn't running."""
    st = status()
    if st['state'] != 'running' or not st['port']:
        raise RuntimeError('dashboard daemon is not running')
    rid = registry.run_id_for(run_dir)
    return f'http://127.0.0.1:{st["port"]}/run/{rid}/'


def url_for_index():
    st = status()
    if st['state'] != 'running' or not st['port']:
        raise RuntimeError('dashboard daemon is not running')
    return f'http://127.0.0.1:{st["port"]}/'
