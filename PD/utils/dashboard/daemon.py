"""CBflow per-user dashboard daemon.

A single long-running HTTP server that hosts all of a user's registered runs.
Replaces the per-run foreground server model for `cbflow run gui --daemon`.

Run modes:
  python3 daemon.py serve [--port N]        # foreground (logs to stdout)
  python3 daemon.py serve --background      # detach (parent returns)

State (~/.cbflow/dashboard/):
  dashboard.pid       atomic O_EXCL on start
  dashboard.port      written after bind
  dashboard.start_ts  process start time, for PID-recycling check
  dashboard.log       output log (in --background mode)
  control.sock        AF_UNIX, mode 0600, owner-only IPC
  runs/<id>.json      run registry
"""

import argparse
import errno
import http.server
import json
import os
import signal
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

import race_dashboard
import registry
import router
import state_paths


# ── Port selection ──────────────────────────────────────────────────────────

def deterministic_port(discipline=None):
    """Per-user deterministic port, scoped by discipline so PD and DFT daemons
    coexist:
      PD:  9000 + (uid % 500)   →  9000..9499
      DFT: 9500 + (uid % 500)   →  9500..9999

    Clear of app.py (8080-8180) and race_dashboard.py hash range
    (10000-60000)."""
    d = state_paths._disc(discipline)
    base = 9000 if d == 'PD' else 9500
    return base + (os.getuid() % 500)


# ── PID liveness + identity ─────────────────────────────────────────────────

def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _process_start_time(pid):
    """Returns a stable identity string for the process. Used to detect PID
    recycling. None on failure (caller falls back to PID-only liveness)."""
    try:
        if os.path.exists(f'/proc/{pid}/stat'):
            with open(f'/proc/{pid}/stat') as f:
                fields = f.read().rsplit(')', 1)[1].split()
            # field 22 (post-comm) is starttime (clock ticks since boot)
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
    except (OSError, IOError):
        return ''


def _port_open(port):
    """Is something accepting connections on 127.0.0.1:port?"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.5)
    try:
        s.connect(('127.0.0.1', port))
        s.close()
        return True
    except (OSError, socket.timeout):
        return False


def existing_daemon_status():
    """Inspect on-disk state and decide what's there.

    Returns a dict with:
      state: 'running' | 'stopped' | 'stale'
      pid:   int or None
      port:  int or None
      reason: short human-readable string
    """
    pid_path = state_paths.pidfile()
    port_path = state_paths.portfile()
    ts_path = state_paths.start_ts_file()

    if not os.path.exists(pid_path):
        return {'state': 'stopped', 'pid': None, 'port': None, 'reason': 'no pidfile'}

    pid_text = _read_text(pid_path)
    try:
        pid = int(pid_text)
    except ValueError:
        return {'state': 'stale', 'pid': None, 'port': None,
                'reason': f'pidfile not an int: {pid_text!r}'}

    port_text = _read_text(port_path)
    port = int(port_text) if port_text.isdigit() else None

    if not _pid_alive(pid):
        return {'state': 'stale', 'pid': pid, 'port': port, 'reason': 'pid not alive'}

    expected_ts = _read_text(ts_path)
    actual_ts = _process_start_time(pid)
    if expected_ts and actual_ts and expected_ts != actual_ts:
        return {'state': 'stale', 'pid': pid, 'port': port,
                'reason': 'pid recycled (start_ts mismatch)'}

    if port and not _port_open(port):
        return {'state': 'stale', 'pid': pid, 'port': port,
                'reason': f'pid alive but port {port} not listening'}

    return {'state': 'running', 'pid': pid, 'port': port, 'reason': ''}


def cleanup_stale_state():
    for p in (state_paths.pidfile(), state_paths.portfile(),
              state_paths.start_ts_file(), state_paths.control_sock()):
        try:
            os.unlink(p)
        except OSError:
            pass


# ── HTTP server with control-thread shutdown ────────────────────────────────

class _ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    # SO_REUSEADDR — makes restart-after-stop work despite TCP TIME_WAIT.
    # Duplicate-daemon protection comes from the O_EXCL pidfile in claim_state(),
    # not from the bind itself.
    allow_reuse_address = True


class _Server:
    def __init__(self, port):
        self.port = port
        self.pool = router.DashboardPool()
        self.handler_cls = router.make_daemon_handler(self.pool)
        self.http = None
        self.watcher_stop = threading.Event()

    def serve(self):
        self.http = _ThreadingHTTPServer(('127.0.0.1', self.port), self.handler_cls)
        threading.Thread(target=self._watcher, daemon=True).start()
        threading.Thread(target=self._registry_sweeper, daemon=True).start()
        threading.Thread(target=self._control_loop, daemon=True).start()
        self.http.serve_forever()

    def shutdown(self):
        self.watcher_stop.set()
        if self.http:
            self.http.shutdown()

    # ── global file watcher ─────────────────────────────────────────────────

    def _watcher(self):
        """Walk active registry every second, poke each cached dashboard so it
        notices DB changes. Cheap: a few stat() per run."""
        while not self.watcher_stop.is_set():
            try:
                for rid in self.pool.cached_ids():
                    dash = self.pool.get(rid)
                    if not dash:
                        self.pool.evict(rid)
                        continue
                    # Cheap probe — anything to keep cached objects warm.
                    try:
                        dash._connect()
                    except Exception:
                        pass
            except Exception as e:
                print(f'watcher: {e!r}', flush=True)
            self.watcher_stop.wait(1.0)

    def _registry_sweeper(self):
        """Periodically walk the WHOLE registry (not just cached entries) and
        mark records whose run_dir was deleted from disk as `archived=True`.

        Triggers immediately on first wake (so the UI reflects deletions
        within ~30 s), then every 30 s. Unarchives entries whose run_dir
        comes back (rare, but happens if a user restores from backup).
        """
        while not self.watcher_stop.is_set():
            try:
                for rec in registry.list_all():
                    rid = rec.get('run_id')
                    run_dir = rec.get('run_dir', '')
                    dir_exists = bool(run_dir) and os.path.isdir(run_dir)
                    archived_now = bool(rec.get('archived'))
                    if not dir_exists and not archived_now:
                        registry.mark_archived(rid, True)
                        # Drop the cached RaceDashboard so the next request
                        # doesn't hold a stale reference.
                        self.pool.evict(rid)
                        print(f'[sweeper] archived {rid}: run_dir deleted ({run_dir})',
                              flush=True)
                    elif dir_exists and archived_now:
                        # Restored
                        registry.mark_archived(rid, False)
                        print(f'[sweeper] unarchived {rid}: run_dir restored ({run_dir})',
                              flush=True)
            except Exception as e:
                print(f'sweeper: {e!r}', flush=True)
            self.watcher_stop.wait(30.0)

    # ── AF_UNIX control socket ──────────────────────────────────────────────

    def _control_loop(self):
        sock_path = state_paths.validate_socket_path()
        try:
            os.unlink(sock_path)
        except OSError:
            pass
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(sock_path)
        os.chmod(sock_path, 0o600)
        srv.listen(8)

        while not self.watcher_stop.is_set():
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
            conn.settimeout(5.0)
            data = b''
            while b'\n' not in data and len(data) < 65536:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            line = data.split(b'\n', 1)[0]
            try:
                msg = json.loads(line.decode('utf-8'))
            except (ValueError, UnicodeDecodeError) as e:
                conn.sendall(json.dumps({'ok': False, 'error': f'bad request: {e}'}).encode() + b'\n')
                return
            reply = self._control_dispatch(msg)
            conn.sendall(json.dumps(reply).encode() + b'\n')
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def _control_dispatch(self, msg):
        op = msg.get('op')
        if op == 'register':
            run_dir = msg.get('run_dir', '')
            if not run_dir:
                return {'ok': False, 'error': 'register requires run_dir'}
            rec = registry.register(run_dir)
            return {'ok': True, 'run_id': rec['run_id'],
                    'url': f'http://127.0.0.1:{self.port}/run/{rec["run_id"]}/'}
        if op == 'deregister':
            target = msg.get('run_dir') or msg.get('run_id')
            if not target:
                return {'ok': False, 'error': 'deregister requires run_dir or run_id'}
            ok = registry.deregister(target)
            return {'ok': ok}
        if op == 'list':
            return {'ok': True, 'runs': registry.list_all(),
                    'port': self.port, 'pid': os.getpid()}
        if op == 'ping':
            return {'ok': True, 'port': self.port, 'pid': os.getpid()}
        if op == 'shutdown':
            threading.Thread(target=self._delayed_shutdown, daemon=True).start()
            return {'ok': True}
        return {'ok': False, 'error': f'unknown op: {op!r}'}

    def _delayed_shutdown(self):
        time.sleep(0.1)
        self.shutdown()


# ── Foreground entry ────────────────────────────────────────────────────────

def claim_state(port):
    """Atomically take ownership of the on-disk state files. Raises
    RuntimeError if another daemon already owns them."""
    status = existing_daemon_status()
    if status['state'] == 'running':
        raise RuntimeError(
            f'Another dashboard daemon is already running '
            f'(pid={status["pid"]}, port={status["port"]}).')
    if status['state'] == 'stale':
        print(f'[daemon] stale state detected ({status["reason"]}); cleaning up',
              flush=True)
        cleanup_stale_state()

    fd = os.open(state_paths.pidfile(),
                 os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(fd, f'{os.getpid()}\n'.encode())
    finally:
        os.close(fd)

    ts = _process_start_time(os.getpid()) or str(time.time())
    with open(state_paths.start_ts_file(), 'w') as f:
        f.write(ts + '\n')
    os.chmod(state_paths.start_ts_file(), 0o600)

    with open(state_paths.portfile(), 'w') as f:
        f.write(f'{port}\n')
    os.chmod(state_paths.portfile(), 0o600)


def release_state():
    cleanup_stale_state()


def serve_foreground(port):
    try:
        sock_check = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock_check.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock_check.bind(('127.0.0.1', port))
        sock_check.close()
    except OSError as e:
        if e.errno == errno.EADDRINUSE:
            raise RuntimeError(
                f'Port {port} already in use. Pass --port to override, '
                f'or stop the conflicting process.')
        raise

    claim_state(port)

    server = _Server(port)

    def _signal_handler(signum, frame):
        print(f'[daemon] received signal {signum}; shutting down', flush=True)
        # serve_forever runs on the main thread; shutdown() must come from
        # a different thread or it deadlocks.
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)

    print(f'[daemon] cbflow dashboard daemon listening on 127.0.0.1:{port} '
          f'(pid={os.getpid()})', flush=True)
    try:
        server.serve()
    finally:
        release_state()
        print('[daemon] stopped', flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(prog='cbflow-dashboard-daemon')
    sub = parser.add_subparsers(dest='cmd', required=True)
    serve_p = sub.add_parser('serve', help='Run the daemon in foreground')
    serve_p.add_argument('--port', type=int, default=0,
                         help='Port (default: per-discipline deterministic)')
    serve_p.add_argument('--discipline', choices=('PD', 'DFT'), default=None,
                         help='Discipline this daemon serves (default: $CBFLOW_DASHBOARD_DISCIPLINE or PD)')
    args = parser.parse_args(argv)
    if args.cmd == 'serve':
        if args.discipline:
            state_paths.set_discipline(args.discipline)
            os.environ['CBFLOW_DASHBOARD_DISCIPLINE'] = args.discipline
        port = args.port or deterministic_port()
        serve_foreground(port)
        return 0
    return 1


if __name__ == '__main__':
    sys.exit(main())
