#!/usr/bin/env python3
"""`cbflow project-dashboard ...` — CBflow-ProjectDashboard CLI.

Project-scoped tracking daemon that serves a rollup of published runs
across (block × phase × exit milestone). Every verb requires `--project`.

Subcommands:
  start   [--port N] [--foreground] [--public] [--bind-addr X]
  stop
  restart
  status
  open
  logs    [--follow]
  list
  publish   (used internally by `cbflow run release --publish`)
  unpublish --block B --phase P --milestone M
"""

import argparse
import os
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PACKAGE_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), 'project_dashboard')
for p in (PACKAGE_DIR, SCRIPT_DIR):
    if p not in sys.path:
        sys.path.insert(0, p)

import daemon as _daemon
import lifecycle
import state_paths


def _apply_project(args):
    if not getattr(args, 'project', None):
        print('error: --project <name> is required', file=sys.stderr)
        sys.exit(2)
    state_paths.set_project(args.project)


# ── start / stop / restart / status ─────────────────────────────────────────

def cmd_start(args):
    _apply_project(args)
    port = args.port or _daemon.deterministic_port(args.project)
    bind_addr = _daemon.resolve_bind_addr(
        '0.0.0.0' if getattr(args, 'public', False)
        else getattr(args, 'bind_addr', None))

    if getattr(args, 'foreground', False):
        try:
            _daemon.serve_foreground(args.project, port, bind_addr=bind_addr)
        except RuntimeError as e:
            print(f'error: {e}', file=sys.stderr)
            return 1
        return 0

    st = lifecycle.status(args.project)
    if st['state'] == 'running':
        print(f'CBflow-ProjectDashboard already running for {args.project!r} '
              f'(pid={st["pid"]}, port={st["port"]})')
        print(f'url: {lifecycle.url_for_index(args.project)}')
        return 0
    try:
        lifecycle.ensure_daemon(args.project, port=port, bind_addr=bind_addr)
    except RuntimeError as e:
        print(f'error: {e}', file=sys.stderr)
        return 1
    st = lifecycle.status(args.project)
    print(f'CBflow-ProjectDashboard started (background) on '
          f'{lifecycle.url_for_index(args.project)}')
    print(f'  pid: {st.get("pid", "?")}  — terminal is free; stop with '
          f'`cbflow project-dashboard stop --project {args.project}`')
    if bind_addr == '0.0.0.0':
        print('  ⚠  bound to 0.0.0.0 — reachable from any host on the LAN.')
    return 0


def cmd_stop(args):
    _apply_project(args)
    stopped = lifecycle.stop(args.project)
    if stopped:
        print(f'CBflow-ProjectDashboard ({args.project}) stopped')
    else:
        print(f'no CBflow-ProjectDashboard was running ({args.project})')
    return 0


def cmd_restart(args):
    _apply_project(args)
    lifecycle.stop(args.project)
    time.sleep(0.2)
    return cmd_start(args)


def cmd_status(args):
    _apply_project(args)
    st = lifecycle.status(args.project)
    print(f'state:  {st["state"]}')
    if st.get('reason'):
        print(f'reason: {st["reason"]}')
    if st.get('pid'):
        print(f'pid:    {st["pid"]}')
    if st.get('port'):
        print(f'port:   {st["port"]}')
        print(f'url:    {lifecycle.url_for_index(args.project)}')
    if st.get('bind_addr'):
        note = '' if st['bind_addr'] == '127.0.0.1' else '  (LAN)'
        print(f'bind:   {st["bind_addr"]}{note}')
    if st['state'] == 'running':
        try:
            reply = lifecycle.send_list(args.project)
            n = len(reply.get('published', []))
            print(f'published: {n} rows')
        except Exception as e:
            print(f'published: (unavailable — {e})')
    return 0


def cmd_open(args):
    _apply_project(args)
    st = lifecycle.status(args.project)
    if st['state'] != 'running':
        print(f'error: no CBflow-ProjectDashboard is running for {args.project!r}. '
              f'Start it first:\n  cbflow project-dashboard start '
              f'--project {args.project}', file=sys.stderr)
        return 1
    url = lifecycle.url_for_index(args.project)
    print(url)
    try:
        if sys.platform == 'darwin':
            subprocess.Popen(['open', url])
        elif sys.platform.startswith('linux'):
            subprocess.Popen(['xdg-open', url],
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    except OSError:
        pass
    return 0


def cmd_logs(args):
    _apply_project(args)
    path = state_paths.logfile(args.project)
    if not os.path.exists(path):
        print(f'(no log at {path})')
        return 0
    if getattr(args, 'follow', False):
        try:
            subprocess.run(['tail', '-F', path])
        except KeyboardInterrupt:
            pass
        return 0
    with open(path) as f:
        for line in f.readlines()[-200:]:
            print(line.rstrip())
    return 0


def cmd_list(args):
    _apply_project(args)
    st = lifecycle.status(args.project)
    if st['state'] != 'running':
        print(f'error: daemon not running for {args.project!r}', file=sys.stderr)
        return 1
    try:
        reply = lifecycle.send_list(args.project)
    except Exception as e:
        print(f'error: {e}', file=sys.stderr)
        return 1
    rows = reply.get('published', [])
    if not rows:
        print('(no published runs)')
        return 0
    print(f'{"block":<24} {"phase":<8} {"milestone":<14} '
          f'{"verdict":<12} {"closability":<12} published_at')
    for r in rows:
        cls = r.get('closability_pct')
        cls_s = f'{cls}%' if cls is not None else '—'
        print(f'{r["block"]:<24} {r["phase"]:<8} {r["milestone"]:<14} '
              f'{r.get("verdict", "—"):<12} {cls_s:<12} '
              f'{r.get("published_at", "—")}')
    return 0


def cmd_unpublish(args):
    _apply_project(args)
    st = lifecycle.status(args.project)
    if st['state'] != 'running':
        print(f'error: daemon not running for {args.project!r}', file=sys.stderr)
        return 1
    reply = lifecycle.send_unpublish(
        args.project, args.block, args.phase, args.milestone)
    if not reply.get('ok'):
        print(f'error: {reply.get("error", "unpublish failed")}', file=sys.stderr)
        return 1
    n = reply.get('removed', 0)
    print(f'removed {n} row(s) from ({args.project}, {args.block}, '
          f'{args.phase}, {args.milestone})')
    return 0


# ── argparse ────────────────────────────────────────────────────────────────

def _build_parser():
    p = argparse.ArgumentParser(prog='cbflow project-dashboard',
                                description='CBflow-ProjectDashboard CLI')
    sub = p.add_subparsers(dest='cmd', required=True)

    def _common(ap):
        ap.add_argument('--project', required=True,
                        help='Project name (must match config/project/<name>)')

    ap = sub.add_parser('start', help='Start the daemon (background)')
    _common(ap)
    ap.add_argument('--port', type=int, default=0,
                    help='Override deterministic port')
    ap.add_argument('--foreground', action='store_true',
                    help="Don't detach; useful for debugging")
    ap.add_argument('--public', action='store_true',
                    help='Bind to 0.0.0.0 (LAN-reachable)')
    ap.add_argument('--bind-addr', default=None)

    ap = sub.add_parser('stop', help='Stop the daemon')
    _common(ap)

    ap = sub.add_parser('restart', help='Restart the daemon')
    _common(ap)
    ap.add_argument('--port', type=int, default=0)
    ap.add_argument('--foreground', action='store_true')
    ap.add_argument('--public', action='store_true')
    ap.add_argument('--bind-addr', default=None)

    ap = sub.add_parser('status', help='Show pid/port/published count')
    _common(ap)

    ap = sub.add_parser('open', help='Open the project view in browser')
    _common(ap)

    ap = sub.add_parser('logs', help='Show daemon log')
    _common(ap)
    ap.add_argument('--follow', '-f', action='store_true')

    ap = sub.add_parser('list', help='List published rows')
    _common(ap)

    ap = sub.add_parser('unpublish', help='Remove a published (block,phase,milestone)')
    _common(ap)
    ap.add_argument('--block', required=True)
    ap.add_argument('--phase', required=True)
    ap.add_argument('--milestone', required=True)

    return p


def main(argv=None):
    parser = _build_parser()
    args = parser.parse_args(argv)
    return {
        'start':     cmd_start,
        'stop':      cmd_stop,
        'restart':   cmd_restart,
        'status':    cmd_status,
        'open':      cmd_open,
        'logs':      cmd_logs,
        'list':      cmd_list,
        'unpublish': cmd_unpublish,
    }[args.cmd](args)


if __name__ == '__main__':
    sys.exit(main())
