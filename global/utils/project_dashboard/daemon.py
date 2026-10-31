"""CBflow-ProjectDashboard daemon.

Long-running HTTP server per (user, project). Serves a project-scope rollup
of published runs across (block × phase × exit-milestone). Data is written
via the AF_UNIX control socket only — no automatic polling, no filesystem
watch. The publish flow is the sole ingress:

    cbflow run release --tag <TAG> --publish [--override]

Run modes:
  python3 daemon.py serve --project <p> [--port N]        (foreground)
  python3 daemon.py serve --project <p> --background      (detach)
"""

import argparse
import errno
import hashlib
import http.server
import json
import os
import socket
import socketserver
import subprocess
import sys
import threading
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
COMMANDS_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), 'commands')
for p in (SCRIPT_DIR, COMMANDS_DIR):
    if p not in sys.path:
        sys.path.insert(0, p)

import router
import state_paths
import tracker_db


# ── Port selection ──────────────────────────────────────────────────────────

def deterministic_port(project):
    """Per-user × per-project port in [25000, 27499]. Stays clear of the
    run-dashboard bands (9000-9999 shared, 20000-24999 per-project)."""
    key = f'{os.getuid()}:{project}'.encode()
    h = int(hashlib.md5(key).hexdigest()[:6], 16)
    return 25000 + (h % 2500)


# ── PID liveness + identity ─────────────────────────────────────────────────

def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _process_start_time(pid):
    """Stable identity string for the process, used to detect PID recycling."""
    try:
        if os.path.exists(f'/proc/{pid}/stat'):
            with open(f'/proc/{pid}/stat') as f:
                fields = f.read().rsplit(')', 1)[1].split()
            return fields[19]
        out = subprocess.run(['ps', '-o', 'lstart=', '-p', str(pid)],
                             capture_output=True, text=True, timeout=2)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def _read_text(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ''


def _port_open(port):
    """True if `port` accepts a TCP connect (i.e., something is listening)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.settimeout(0.3)
        s.connect(('127.0.0.1', port))
        return True
    except (OSError, socket.timeout):
        return False
    finally:
        s.close()


def existing_daemon_status(project):
    """Returns dict describing the daemon's current state."""
    pidfile = state_paths.pidfile(project)
    portfile = state_paths.portfile(project)
    tsfile = state_paths.start_ts_file(project)
    bind_file = state_paths.bind_addr_file(project)
    pid_str = _read_text(pidfile)
    if not pid_str:
        return {'state': 'stopped', 'reason': 'no pidfile'}
    try:
        pid = int(pid_str)
    except ValueError:
        return {'state': 'stopped', 'reason': 'bad pidfile'}
    if not _pid_alive(pid):
        return {'state': 'stopped', 'reason': f'pid {pid} dead',
                'stale_pid': pid}
    stored_ts = _read_text(tsfile)
    live_ts = _process_start_time(pid)
    if stored_ts and live_ts and stored_ts != live_ts:
        return {'state': 'stopped', 'reason': f'pid {pid} recycled',
                'stale_pid': pid}
    port_str = _read_text(portfile)
    port = int(port_str) if port_str.isdigit() else 0
    bind_addr = _read_text(bind_file) or '127.0.0.1'
    return {'state': 'running', 'pid': pid, 'port': port,
            'bind_addr': bind_addr}


def cleanup_stale_state(project):
    for f in (state_paths.pidfile(project), state_paths.portfile(project),
              state_paths.start_ts_file(project),
              state_paths.bind_addr_file(project)):
        try:
            os.unlink(f)
        except OSError:
            pass


class _ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class _Server:
    def __init__(self, project, port, bind_addr='127.0.0.1'):
        self.project = project
        self.port = port
        self.bind_addr = bind_addr
        self.handler_cls = router.make_handler(project)
        self.http = None
        self.stop_event = threading.Event()
        # Ensure the tracker DB exists / schema up-to-date before serving.
        tracker_db.init_db(state_paths.tracker_db(project))

    def serve(self):
        self.http = _ThreadingHTTPServer((self.bind_addr, self.port),
                                          self.handler_cls)
        threading.Thread(target=self._control_loop, daemon=True).start()
        self.http.serve_forever()

    def shutdown(self):
        self.stop_event.set()
        if self.http:
            self.http.shutdown()

    # ── AF_UNIX control socket ──────────────────────────────────────────────

    def _control_loop(self):
        sock_path = state_paths.validate_socket_path(self.project)
        try:
            os.unlink(sock_path)
        except OSError:
            pass
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(sock_path)
        os.chmod(sock_path, 0o600)
        srv.listen(8)
        while not self.stop_event.is_set():
            try:
                srv.settimeout(0.5)
                try:
                    conn, _ = srv.accept()
                except socket.timeout:
                    continue
                threading.Thread(target=self._handle_control,
                                 args=(conn,), daemon=True).start()
            except Exception as e:
                print(f'control: {e!r}', flush=True)
        try:
            srv.close()
            os.unlink(sock_path)
        except OSError:
            pass

    def _handle_control(self, conn):
        try:
            conn.settimeout(120.0)  # publish payload can be big + take a moment
            data = b''
            # Cap generous — a 5M-cell density grid + 200k-cell interactive
            # layer + macros can be tens of megabytes serialized. Anything
            # runaway would still hit this cap before killing memory.
            while b'\n' not in data and len(data) < 256 * 1024 * 1024:
                chunk = conn.recv(1 << 20)   # 1 MiB reads to move fast
                if not chunk:
                    break
                data += chunk
            line = data.split(b'\n', 1)[0]
            try:
                msg = json.loads(line.decode('utf-8'))
            except (ValueError, UnicodeDecodeError) as e:
                conn.sendall(json.dumps({'ok': False,
                                         'error': f'bad request: {e}'}).encode()
                             + b'\n')
                return
            reply = self._dispatch(msg)
            conn.sendall(json.dumps(reply).encode() + b'\n')
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def _dispatch(self, msg):
        op = msg.get('op')
        db_path = state_paths.tracker_db(self.project)
        if op == 'ping':
            return {'ok': True, 'port': self.port, 'pid': os.getpid(),
                    'project': self.project}
        if op == 'publish':
            # Full snapshot payload — tracker_db.publish handles the txn.
            try:
                pid = tracker_db.publish(db_path, msg, self.project)
                return {'ok': True, 'published_run_id': pid,
                        'url': self._url_for_published(pid)}
            except tracker_db.ConflictError as e:
                return {'ok': False, 'error': str(e), 'conflict': True}
            except Exception as e:
                return {'ok': False, 'error': f'publish failed: {e}'}
        if op == 'unpublish':
            try:
                n = tracker_db.unpublish(
                    db_path,
                    project=self.project,
                    block=msg.get('block'), phase=msg.get('phase'),
                    milestone=msg.get('milestone'))
                return {'ok': True, 'removed': n}
            except Exception as e:
                return {'ok': False, 'error': f'unpublish failed: {e}'}
        if op == 'list':
            rows = tracker_db.list_published(db_path, self.project)
            return {'ok': True, 'published': rows,
                    'port': self.port, 'pid': os.getpid()}
        if op == 'shutdown':
            threading.Thread(target=self._delayed_shutdown, daemon=True).start()
            return {'ok': True}
        return {'ok': False, 'error': f'unknown op: {op!r}'}

    def _url_for_published(self, pid):
        host = ('127.0.0.1' if self.bind_addr in ('127.0.0.1', 'localhost', '::1')
                else socket.gethostname())
        return f'http://{host}:{self.port}/published/{pid}'

    def _delayed_shutdown(self):
        time.sleep(0.1)
        self.shutdown()


# ── Foreground entry ────────────────────────────────────────────────────────

def claim_state(project, port, bind_addr='127.0.0.1'):
    """Atomically take ownership of on-disk state; raise if already owned."""
    status = existing_daemon_status(project)
    if status['state'] == 'running':
        raise RuntimeError(
            f'project-dashboard daemon already running for {project!r} '
            f'(pid={status.get("pid")}, port={status.get("port")}).')
    if status.get('stale_pid'):
        cleanup_stale_state(project)
    # O_EXCL create ensures only one writer wins the race.
    pidfile = state_paths.pidfile(project)
    try:
        fd = os.open(pidfile, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except OSError as e:
        if e.errno == errno.EEXIST:
            raise RuntimeError(f'lost race for pidfile {pidfile}')
        raise
    with os.fdopen(fd, 'w') as f:
        f.write(str(os.getpid()))
    ts = _process_start_time(os.getpid()) or datetime.now().isoformat()
    with open(state_paths.start_ts_file(project), 'w') as f:
        f.write(ts)
    with open(state_paths.portfile(project), 'w') as f:
        f.write(str(port))
    with open(state_paths.bind_addr_file(project), 'w') as f:
        f.write(bind_addr)
    for p in (pidfile, state_paths.start_ts_file(project),
              state_paths.portfile(project),
              state_paths.bind_addr_file(project)):
        os.chmod(p, 0o600)


def release_state(project):
    cleanup_stale_state(project)


def resolve_bind_addr(arg_value=None):
    if arg_value in (None, '', '127.0.0.1', 'localhost'):
        return '127.0.0.1'
    if arg_value == '0.0.0.0':
        return '0.0.0.0'
    return arg_value


def serve_foreground(project, port, bind_addr='127.0.0.1'):
    state_paths.set_project(project)
    try:
        claim_state(project, port, bind_addr)
    except RuntimeError as e:
        raise
    srv = _Server(project, port, bind_addr)
    try:
        print(f'CBflow-ProjectDashboard listening on '
              f'http://{bind_addr}:{port}/  (project={project}, pid={os.getpid()})',
              flush=True)
        srv.serve()
    finally:
        release_state(project)


# ── CLI ─────────────────────────────────────────────────────────────────────

def main(argv=None):
    p = argparse.ArgumentParser(prog='project-dashboard-daemon')
    sub = p.add_subparsers(dest='cmd', required=True)
    serve_p = sub.add_parser('serve', help='Run the daemon (foreground)')
    serve_p.add_argument('--project', required=True)
    serve_p.add_argument('--port', type=int, default=0)
    serve_p.add_argument('--bind-addr', default=None,
                         help='127.0.0.1 (default) or 0.0.0.0 for LAN')
    args = p.parse_args(argv)
    if args.cmd == 'serve':
        state_paths.set_project(args.project)
        port = args.port or deterministic_port(args.project)
        bind_addr = resolve_bind_addr(args.bind_addr)
        serve_foreground(args.project, port, bind_addr)
        return 0
    return 2


if __name__ == '__main__':
    sys.exit(main())
