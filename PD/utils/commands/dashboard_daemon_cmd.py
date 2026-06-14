#!/usr/bin/env python3
"""`cbflow dashboard ...` — per-user dashboard daemon CLI.

This is a sibling of dashboard_cmd.py (which still serves `cbflow flow dashboard
start|stop` against the legacy app.py). All daemon-related verbs live here.

Subcommands:
  start [--port N] [--foreground]
  stop
  restart
  status
  open [<run>]                  run = a run_dir or a run_id (omit for index)
  logs [--follow]
  list
  register <run_dir>
  deregister <run_dir-or-run_id>
"""

import argparse
import os
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DASHBOARD_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), 'dashboard')
for p in (DASHBOARD_DIR, SCRIPT_DIR):
    if p not in sys.path:
        sys.path.insert(0, p)

import daemon as _daemon
import lifecycle
import registry
import state_paths


# ── start / stop / restart / status ─────────────────────────────────────────

def cmd_start(args):
    port = args.port or _daemon.deterministic_port()

    if args.foreground:
        try:
            _daemon.serve_foreground(port)
        except RuntimeError as e:
            print(f'error: {e}', file=sys.stderr)
            return 1
        return 0

    st = lifecycle.status()
    if st['state'] == 'running':
        print(f'dashboard daemon already running (pid={st["pid"]}, port={st["port"]})')
        print(f'url: http://127.0.0.1:{st["port"]}/')
        return 0

    try:
        actual_port = lifecycle.ensure_daemon(port=port)
    except RuntimeError as e:
        print(f'error: {e}', file=sys.stderr)
        return 1
    print(f'dashboard daemon started on http://127.0.0.1:{actual_port}/')
    return 0


def cmd_stop(args):
    stopped = lifecycle.stop()
    if stopped:
        print('dashboard daemon stopped')
        return 0
    print('no dashboard daemon was running')
    return 0


def cmd_restart(args):
    lifecycle.stop()
    return cmd_start(args)


def cmd_status(args):
    st = lifecycle.status()
    print(f'state:  {st["state"]}')
    if st['pid']:
        print(f'pid:    {st["pid"]}')
    if st['port']:
        print(f'port:   {st["port"]}')
    if st['reason']:
        print(f'reason: {st["reason"]}')
    if st['state'] == 'running':
        print(f'url:    http://127.0.0.1:{st["port"]}/')
        active = registry.list_active()
        archived = [r for r in registry.list_all() if r.get('archived')]
        print(f'runs:   {len(active)} active, {len(archived)} archived')
    return {'running': 0, 'stopped': 3, 'stale': 4}.get(st['state'], 1)


# ── open / logs ─────────────────────────────────────────────────────────────

def cmd_open(args):
    try:
        st = lifecycle.status()
        if st['state'] != 'running':
            print('starting dashboard daemon...')
            lifecycle.ensure_daemon()
        if args.run:
            run = args.run
            if os.path.isdir(run):
                url = lifecycle.url_for_run(run)
            else:
                # treat as run_id
                rec = registry.get(run)
                if not rec:
                    print(f'error: no such run_id: {run}', file=sys.stderr)
                    return 1
                url = lifecycle.url_for_run(rec['run_dir'])
        else:
            url = lifecycle.url_for_index()
    except RuntimeError as e:
        print(f'error: {e}', file=sys.stderr)
        return 1

    if lifecycle.is_ssh_session():
        st = lifecycle.status()
        port = st['port']
        import socket
        hostname = socket.gethostname()
        print(f'SSH session detected — not opening browser.')
        print(f'Tunnel:  ssh -L {port}:localhost:{port} $USER@{hostname}')
        print(f'Then open: {url}')
        return 0

    opened = lifecycle.open_browser(url)
    if opened:
        print(f'opened: {url}')
        return 0
    print(f'browser launch failed; open this manually: {url}')
    return 1


def cmd_logs(args):
    log = state_paths.logfile()
    if not os.path.exists(log):
        print('(no log file yet)')
        return 0
    if args.follow:
        try:
            subprocess.run(['tail', '-F', log])
        except KeyboardInterrupt:
            pass
        return 0
    try:
        with open(log) as f:
            sys.stdout.write(f.read())
    except OSError as e:
        print(f'error: {e}', file=sys.stderr)
        return 1
    return 0


# ── list / register / deregister ────────────────────────────────────────────

def cmd_list(args):
    runs = registry.list_all()
    if not runs:
        print('(no runs registered)')
        return 0
    print(f'{"run_id":<14}{"flow":<12}{"state":<10}{"last_seen":<22}run_dir')
    for r in runs:
        run_dir = r.get('run_dir', '')
        dir_exists = bool(run_dir) and os.path.isdir(run_dir)
        if not dir_exists:
            state = 'deleted'
        elif r.get('archived'):
            state = 'archived'
        else:
            state = 'active'
        print(f'{r["run_id"]:<14}{r.get("flow_type", ""):<12}{state:<10}'
              f'{r.get("last_seen_at", ""):<22}{run_dir}')
    return 0


def cmd_prune(args):
    """Bulk-deregister entries whose run_dir is gone OR are archived."""
    runs = registry.list_all()
    targets = []
    for r in runs:
        run_dir = r.get('run_dir', '')
        dir_exists = bool(run_dir) and os.path.isdir(run_dir)
        if not dir_exists:
            targets.append((r['run_id'], run_dir, 'deleted'))
        elif args.include_archived and r.get('archived'):
            targets.append((r['run_id'], run_dir, 'archived'))

    if not targets:
        print('Nothing to prune.')
        return 0

    print(f'Pruning {len(targets)} registry entries:')
    for rid, run_dir, reason in targets:
        print(f'  - {rid}  ({reason})  {run_dir}')
    if not args.yes:
        ans = input('\nProceed? [y/N] ').strip().lower()
        if ans not in ('y', 'yes'):
            print('Aborted.')
            return 1

    removed = 0
    for rid, _, _ in targets:
        if registry.deregister(rid):
            removed += 1
    print(f'Removed {removed} registry entries.')
    return 0


def cmd_register(args):
    run_dir = os.path.abspath(args.run_dir)
    if not os.path.isdir(run_dir):
        print(f'error: not a directory: {run_dir}', file=sys.stderr)
        return 1
    try:
        lifecycle.ensure_daemon()
        reply = lifecycle.send_register(run_dir)
    except (RuntimeError, OSError) as e:
        print(f'error: {e}', file=sys.stderr)
        return 1
    if not reply.get('ok'):
        print(f'error: {reply.get("error", "register failed")}', file=sys.stderr)
        return 1
    print(f'registered: {reply["url"]}')
    return 0


def cmd_deregister(args):
    target = args.run
    try:
        if lifecycle.status()['state'] == 'running':
            reply = lifecycle.send_deregister(target)
            if not reply.get('ok'):
                print(f'error: {reply.get("error", "deregister failed")}',
                      file=sys.stderr)
                return 1
            print(f'deregistered: {target}')
            return 0
    except OSError:
        pass
    # Daemon not running — operate on registry files directly.
    if registry.deregister(target):
        print(f'deregistered (offline): {target}')
        return 0
    print(f'not registered: {target}', file=sys.stderr)
    return 1


# ── argparse ────────────────────────────────────────────────────────────────

def create_parser():
    parser = argparse.ArgumentParser(
        prog='cbflow dashboard',
        description='Per-user dashboard daemon. One process serves all '
                    'registered runs at deterministic per-user port '
                    '(9000 + uid %% 1000).')
    sub = parser.add_subparsers(dest='cmd', required=False)

    p = sub.add_parser('start', help='Start the daemon')
    p.add_argument('--port', type=int, default=0,
                   help='Override the deterministic port')
    p.add_argument('--foreground', action='store_true',
                   help="Don't detach; useful for debugging")
    p.set_defaults(func=cmd_start)

    sub.add_parser('stop', help='Stop the daemon').set_defaults(func=cmd_stop)

    p = sub.add_parser('restart', help='Restart the daemon')
    p.add_argument('--port', type=int, default=0)
    p.add_argument('--foreground', action='store_true')
    p.set_defaults(func=cmd_restart)

    sub.add_parser('status', help='Show daemon status').set_defaults(func=cmd_status)

    p = sub.add_parser('open', help='Open browser to daemon / a registered run')
    p.add_argument('run', nargs='?',
                   help='Run dir or run_id (omit for the index page)')
    p.set_defaults(func=cmd_open)

    p = sub.add_parser('logs', help='Show the daemon log')
    p.add_argument('--follow', '-f', action='store_true')
    p.set_defaults(func=cmd_logs)

    sub.add_parser('list', help='List registered runs').set_defaults(func=cmd_list)

    p = sub.add_parser('prune', help='Remove registry entries whose run_dir is gone (or are archived)')
    p.add_argument('-y', '--yes', action='store_true', help='Skip confirmation prompt')
    p.add_argument('--include-archived', action='store_true',
                   help='Also remove archived (not just deleted) entries')
    p.set_defaults(func=cmd_prune)

    p = sub.add_parser('register', help='Register a run with the daemon')
    p.add_argument('run_dir')
    p.set_defaults(func=cmd_register)

    p = sub.add_parser('deregister', help='Deregister a run')
    p.add_argument('run', help='run_dir or run_id')
    p.set_defaults(func=cmd_deregister)

    return parser


def main(argv=None):
    parser = create_parser()
    args = parser.parse_args(argv)
    if not getattr(args, 'cmd', None):
        parser.print_help()
        return 0
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())
