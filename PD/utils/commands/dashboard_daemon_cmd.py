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


# DFT discipline is identified by the run's flow_type. Keep in sync with
# PD/config/flow/v1.0.0/flow_config.tcl's flow(types) DFT entries.
_DFT_FLOWS = {'DFT_INSERT', 'SCAN_INSERT', 'ATPG', 'GLS_FUNC', 'GLS_SCAN_MBIST'}


def _discipline_for_run_dir(run_dir):
    """Read flow_type from .run.cbflow.env and map to PD/DFT. Returns 'PD'
    if anything fails — registration without a discoverable env file falls
    through to the default daemon."""
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if not os.path.exists(env_file):
        return 'PD'
    try:
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line.startswith('export CBFLOW_FLOW_TYPE='):
                    val = line.split('=', 1)[1].strip().strip('"').strip("'")
                    return 'DFT' if val in _DFT_FLOWS else 'PD'
    except OSError:
        pass
    return 'PD'


def _apply_discipline(args):
    """Apply --discipline flag from args to module state (for non-register verbs)."""
    if getattr(args, 'discipline', None):
        state_paths.set_discipline(args.discipline)


# ── start / stop / restart / status ─────────────────────────────────────────

def cmd_start(args):
    _apply_discipline(args)
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
    _apply_discipline(args)
    stopped = lifecycle.stop()
    if stopped:
        print(f'dashboard daemon ({state_paths.get_discipline()}) stopped')
        return 0
    print(f'no dashboard daemon was running ({state_paths.get_discipline()})')
    return 0


def cmd_restart(args):
    _apply_discipline(args)
    lifecycle.stop()
    return cmd_start(args)


def cmd_status(args):
    _apply_discipline(args)
    if args.all:
        rc_any = 0
        for d in ('PD', 'DFT'):
            state_paths.set_discipline(d)
            print(f'── {d} ──')
            rc = _show_one_status()
            rc_any = rc_any or rc
            print()
        return rc_any
    return _show_one_status()


def _show_one_status():
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
    # If a run was passed, the discipline is the run's discipline (unless
    # explicitly overridden via --discipline).
    if args.run and os.path.isdir(args.run) and not args.discipline:
        state_paths.set_discipline(_discipline_for_run_dir(os.path.abspath(args.run)))
    else:
        _apply_discipline(args)
    try:
        st = lifecycle.status()
        if st['state'] != 'running':
            print(f'starting dashboard daemon ({state_paths.get_discipline()})...')
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
    _apply_discipline(args)
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
    _apply_discipline(args)
    if args.all:
        rc = 0
        for d in ('PD', 'DFT'):
            state_paths.set_discipline(d)
            print(f'── {d} ──')
            rc = rc or _list_one()
            print()
        return rc
    return _list_one()


def _list_one():
    runs = registry.list_all()
    if not runs:
        print('(no runs registered)')
        return 0
    print(f'{"run_id":<14}{"flow":<16}{"state":<10}{"last_seen":<22}run_dir')
    for r in runs:
        run_dir = r.get('run_dir', '')
        dir_exists = bool(run_dir) and os.path.isdir(run_dir)
        if not dir_exists:
            state = 'deleted'
        elif r.get('archived'):
            state = 'archived'
        else:
            state = 'active'
        print(f'{r["run_id"]:<14}{r.get("flow_type", ""):<16}{state:<10}'
              f'{r.get("last_seen_at", ""):<22}{run_dir}')
    return 0


def cmd_prune(args):
    """Bulk-deregister entries whose run_dir is gone OR are archived."""
    _apply_discipline(args)
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
    # Auto-route by flow_type unless caller forced --discipline.
    disc = args.discipline or _discipline_for_run_dir(run_dir)
    state_paths.set_discipline(disc)
    try:
        lifecycle.ensure_daemon(discipline=disc)
        reply = lifecycle.send_register(run_dir)
    except (RuntimeError, OSError) as e:
        print(f'error: {e}', file=sys.stderr)
        return 1
    if not reply.get('ok'):
        print(f'error: {reply.get("error", "register failed")}', file=sys.stderr)
        return 1
    print(f'registered ({disc}): {reply["url"]}')
    return 0


def cmd_deregister(args):
    _apply_discipline(args)
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

def _add_disc(p):
    p.add_argument('--discipline', choices=('PD', 'DFT'), default=None,
                   help='Discipline (PD or DFT). Defaults: register auto-detects '
                        'from the run\'s flow_type; other verbs default to PD.')


def create_parser():
    parser = argparse.ArgumentParser(
        prog='cbflow dashboard',
        description='Per-discipline, per-user dashboard daemon. PD and DFT '
                    'each get their own daemon and port — PD on 9000 + uid%%500, '
                    'DFT on 9500 + uid%%500. Pass --discipline {PD,DFT} to any '
                    'verb (register auto-detects from the run\'s flow_type).')
    sub = parser.add_subparsers(dest='cmd', required=False)

    p = sub.add_parser('start', help='Start the daemon')
    p.add_argument('--port', type=int, default=0,
                   help='Override the deterministic port')
    p.add_argument('--foreground', action='store_true',
                   help="Don't detach; useful for debugging")
    _add_disc(p)
    p.set_defaults(func=cmd_start)

    p = sub.add_parser('stop', help='Stop the daemon')
    _add_disc(p)
    p.set_defaults(func=cmd_stop)

    p = sub.add_parser('restart', help='Restart the daemon')
    p.add_argument('--port', type=int, default=0)
    p.add_argument('--foreground', action='store_true')
    _add_disc(p)
    p.set_defaults(func=cmd_restart)

    p = sub.add_parser('status', help='Show daemon status')
    p.add_argument('--all', action='store_true', help='Show status for both PD and DFT')
    _add_disc(p)
    p.set_defaults(func=cmd_status)

    p = sub.add_parser('open', help='Open browser to daemon / a registered run')
    p.add_argument('run', nargs='?',
                   help='Run dir or run_id (omit for the index page)')
    _add_disc(p)
    p.set_defaults(func=cmd_open)

    p = sub.add_parser('logs', help='Show the daemon log')
    p.add_argument('--follow', '-f', action='store_true')
    _add_disc(p)
    p.set_defaults(func=cmd_logs)

    p = sub.add_parser('list', help='List registered runs')
    p.add_argument('--all', action='store_true', help='List runs from both PD and DFT')
    _add_disc(p)
    p.set_defaults(func=cmd_list)

    p = sub.add_parser('prune', help='Remove registry entries whose run_dir is gone (or are archived)')
    p.add_argument('-y', '--yes', action='store_true', help='Skip confirmation prompt')
    p.add_argument('--include-archived', action='store_true',
                   help='Also remove archived (not just deleted) entries')
    _add_disc(p)
    p.set_defaults(func=cmd_prune)

    p = sub.add_parser('register', help='Register a run with the daemon')
    p.add_argument('run_dir')
    _add_disc(p)
    p.set_defaults(func=cmd_register)

    p = sub.add_parser('deregister', help='Deregister a run')
    p.add_argument('run', help='run_dir or run_id')
    _add_disc(p)
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
