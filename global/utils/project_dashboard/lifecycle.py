"""Lifecycle helpers for CBflow-ProjectDashboard.

Public API mirrors dashboard/lifecycle.py so callers get a familiar shape:
  status(project)            → dict describing daemon state
  is_running(project)        → bool
  ensure_daemon(project, ...) → int port (starts detached if not running)
  stop(project)              → bool
  send_control(project, msg) → dict reply
  send_publish(project, payload)     → convenience
  send_unpublish(project, ...)       → convenience
  send_list(project)                 → convenience
  url_for_index(project)             → str
"""

import json
import os
import socket
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import daemon as _daemon
import state_paths


def status(project):
    return _daemon.existing_daemon_status(project)


def is_running(project):
    return status(project).get('state') == 'running'


def ensure_daemon(project, port=0, wait_s=4.0, bind_addr=None):
    """Start the daemon in the background if not already running.

    Returns the port the daemon is listening on. Raises RuntimeError with
    the recent log tail if the daemon exits before it starts listening.
    """
    st = status(project)
    if st['state'] == 'running':
        return st['port']
    if not port:
        port = _daemon.deterministic_port(project)
    bind_addr = _daemon.resolve_bind_addr(bind_addr)
    # Detach from the CLI so the parent returns immediately.
    log_path = state_paths.logfile(project)
    log_fd = open(log_path, 'ab', buffering=0)
    cmd = [sys.executable, os.path.join(SCRIPT_DIR, 'daemon.py'),
           'serve', '--project', project, '--port', str(port),
           '--bind-addr', bind_addr]
    env = dict(os.environ)
    env['CBFLOW_PROJECT_DASHBOARD_PROJECT'] = project
    proc = subprocess.Popen(
        cmd, stdin=subprocess.DEVNULL, stdout=log_fd, stderr=log_fd,
        start_new_session=True, close_fds=True, env=env)

    deadline = time.time() + wait_s
    sock_path = state_paths.control_sock(project)
    while time.time() < deadline:
        time.sleep(0.1)
        if proc.poll() is not None:
            log_fd.close()
            raise RuntimeError(
                f'project-dashboard daemon exited immediately (rc={proc.returncode}). '
                f'Recent log:\n{_tail_log(project, 20)}')
        st = status(project)
        if st['state'] == 'running' and os.path.exists(sock_path):
            log_fd.close()
            return st['port']
    log_fd.close()
    raise RuntimeError(
        f'project-dashboard daemon did not start within {wait_s}s. '
        f'Recent log:\n{_tail_log(project, 20)}')


def stop(project, wait_s=5.0):
    st = status(project)
    if st['state'] != 'running':
        return False
    try:
        send_control(project, {'op': 'shutdown'})
    except Exception:
        pass
    deadline = time.time() + wait_s
    while time.time() < deadline:
        if status(project).get('state') != 'running':
            _daemon.release_state(project)
            return True
        time.sleep(0.1)
    # Fall through: hard-kill by PID
    pid = st.get('pid')
    if pid:
        try:
            os.kill(pid, 15)
        except OSError:
            pass
    _daemon.release_state(project)
    return True


def send_control(project, msg, timeout=30.0):
    sock_path = state_paths.control_sock(project)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(timeout)
        s.connect(sock_path)
        s.sendall((json.dumps(msg) + '\n').encode())
        data = b''
        while b'\n' not in data:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        line = data.split(b'\n', 1)[0]
        return json.loads(line.decode('utf-8'))
    finally:
        try:
            s.close()
        except OSError:
            pass


def send_publish(project, payload):
    """Payload is the full snapshot dict — see tracker_db.publish."""
    return send_control(project, dict(payload, op='publish'))


def send_unpublish(project, block, phase, milestone):
    return send_control(project, {
        'op': 'unpublish', 'block': block, 'phase': phase,
        'milestone': milestone})


def send_list(project):
    return send_control(project, {'op': 'list'})


def url_for_index(project):
    st = status(project)
    port = st.get('port') or _daemon.deterministic_port(project)
    bind_addr = st.get('bind_addr') or '127.0.0.1'
    host = ('127.0.0.1' if bind_addr in ('127.0.0.1', 'localhost', '::1')
            else socket.gethostname())
    return f'http://{host}:{port}/'


def _tail_log(project, n=20):
    path = state_paths.logfile(project)
    try:
        with open(path) as f:
            lines = f.readlines()
        return ''.join(lines[-n:])
    except OSError:
        return '(no log)'
