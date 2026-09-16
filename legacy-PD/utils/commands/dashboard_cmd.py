#!/usr/bin/env python3
"""
CBFlow Dashboard Command Handler

Start and manage the web dashboard.
"""

import argparse
import os
import sys
import subprocess
import signal

from logging_config import configure_logging, get_logger

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir

logger = configure_logging('cbflow.dashboard')



def cmd_start(args: argparse.Namespace) -> int:
    """Start the dashboard server."""
    port = getattr(args, 'port', 0) or 0

    dashboard_app = os.path.join(get_cbflow_core_dir(), 'utils', 'dashboard', 'app.py')

    if not os.path.exists(dashboard_app):
        logger.error(f"Dashboard app not found: {dashboard_app}")
        return 1

    if port == 0:
        logger.info("Starting CBFlow Dashboard (auto-selecting free port)...")
    else:
        logger.info(f"Starting CBFlow Dashboard on port {port}...")
        logger.info(f"Open http://localhost:{port} in your browser")

    try:
        os.execvp('python3', ['python3', dashboard_app, str(port)])
    except Exception as e:
        logger.error(f"Failed to start dashboard: {e}")
        return 1


def cmd_stop(args: argparse.Namespace) -> int:
    """Stop the dashboard server."""
    logger.info("To stop the dashboard, press Ctrl+C in the terminal where it's running")
    return 0


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='cbflow flow dashboard',
        description='CBFlow Web Dashboard'
    )

    subparsers = parser.add_subparsers(dest='command')

    start_parser = subparsers.add_parser('start', help='Start dashboard')
    start_parser.add_argument('--port', '-p', type=int, default=0, help='Port number (0 = auto-select free port)')

    subparsers.add_parser('stop', help='Stop dashboard')

    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    commands = {'start': cmd_start, 'stop': cmd_stop}
    if args.command in commands:
        return commands[args.command](args)
    return 1


if __name__ == '__main__':
    sys.exit(main())
