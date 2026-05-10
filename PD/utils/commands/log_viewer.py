#!/usr/bin/env python3
"""
CBFlow Log Viewer

Provides log viewing, tailing, and searching capabilities.
Usage: cbflow run logs [--tail N] [--search PATTERN] [--level LEVEL]
"""

import argparse
import os
import re
import sys
from pathlib import Path
from datetime import datetime


def get_log_files(run_dir: Path) -> list:
    """Find all log files in run directory — checks work/<flow>/<node>/run/*.log and logs/."""
    log_files = []

    # Primary: work/<flow>/<node>/run/<node>.log (EDA tool output)
    work_dir = run_dir / 'work'
    if work_dir.exists():
        for log in work_dir.rglob('*.log'):
            if '/run/' in str(log):
                log_files.append(log)

    # Secondary: logs/ directory (legacy or LSF logs)
    logs_dir = run_dir / 'logs'
    if logs_dir.exists():
        for log in logs_dir.glob('*.log'):
            log_files.append(log)

    # Also pick up .err files (LSF stderr)
    if work_dir.exists():
        for err in work_dir.rglob('*.err'):
            if '/run/' in str(err):
                log_files.append(err)
    if logs_dir.exists():
        for err in logs_dir.glob('*.err'):
            log_files.append(err)

    # Sort by modification time (newest first), filter empty files
    log_files = [f for f in log_files if f.stat().st_size > 0]
    log_files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
    return log_files


def cmd_logs(args: argparse.Namespace) -> int:
    """View logs from current run directory."""
    run_dir = Path(os.getcwd())

    # Find log files across work/ and logs/
    log_files = get_log_files(run_dir)

    if getattr(args, 'list_logs', False):
        # List mode — show all log files including empty ones
        all_logs = []
        work_dir = run_dir / 'work'
        if work_dir.exists():
            all_logs.extend(f for f in work_dir.rglob('*.log') if '/run/' in str(f))
            all_logs.extend(f for f in work_dir.rglob('*.err') if '/run/' in str(f))
        logs_dir = run_dir / 'logs'
        if logs_dir.exists():
            all_logs.extend(logs_dir.glob('*.log'))
            all_logs.extend(logs_dir.glob('*.err'))
        all_logs.sort(key=lambda f: f.stat().st_mtime, reverse=True)

        if not all_logs:
            print("No log files found")
            print(f"  Log files are created when stages run (not in test_mode)")
            print(f"  Expected location: work/<flow>/<node>/run/<node>.log")
            return 0

        print(f"\nLog files in {run_dir}:")
        print(f"{'='*70}")
        for lf in all_logs:
            size = lf.stat().st_size
            mtime = datetime.fromtimestamp(lf.stat().st_mtime).strftime('%Y-%m-%d %H:%M:%S')
            size_str = f"{size/1024:.1f}KB" if size > 1024 else f"{size}B"
            rel = lf.relative_to(run_dir)
            print(f"  {str(rel):<50} {size_str:>8}  {mtime}")
        return 0

    if not log_files:
        print("No log files found (with content)")
        print(f"  EDA tool logs:  work/<flow>/<node>/run/<node>.log")
        print(f"  LSF logs:       work/<flow>/<node>/run/lsf_<node>_<jobid>.log")
        print(f"  Run creation:   logs/")
        print(f"  Logs are created when stages execute (not in test_mode)")
        return 0

    # Search mode
    search_pattern = getattr(args, 'search', None)
    level_filter = getattr(args, 'level', None)
    tail_count = getattr(args, 'tail', None)
    target_file = getattr(args, 'file', None)

    # Select target file(s)
    if target_file:
        # Try exact path first, then search in work/ and logs/
        target_path = run_dir / target_file
        if not target_path.exists():
            # Try finding by name in log files
            matches = [f for f in log_files if f.name == target_file or str(f.relative_to(run_dir)) == target_file]
            if matches:
                target_path = matches[0]
            else:
                print(f"Error: Log file not found: {target_file}")
                return 1
        files_to_read = [target_path]
    else:
        files_to_read = log_files[:1]  # most recent by default

    for log_file in files_to_read:
        if len(files_to_read) > 1:
            print(f"\n{'═'*60}")
            print(f"  {log_file.name}")
            print(f"{'═'*60}")

        try:
            with open(log_file, 'r') as f:
                lines = f.readlines()
        except Exception as e:
            print(f"Error: Failed to read {log_file}: {e}")
            continue

        # Apply filters
        filtered_lines = lines

        if level_filter:
            level_upper = level_filter.upper()
            # Match EDA tool log patterns + cbflow bracket format
            level_patterns = {
                'ERROR': [
                    r'\[ERROR\]', r'^Error:', r'^ERROR:', r'\*\*ERROR',
                    r'^Error ', r'Error: ', r'FATAL:', r'^E-',
                ],
                'WARNING': [
                    r'\[WARNING\]', r'\[WARN\]', r'^Warning:', r'^WARNING:',
                    r'\*\*WARN', r'^Warning ', r'Warning: ', r'^W-',
                ],
                'INFO': [
                    r'\[INFO\]', r'^Information:', r'^INFO:', r'^I-',
                ],
                'DEBUG': [
                    r'\[DEBUG\]', r'^Debug:', r'^DEBUG:',
                ],
            }
            patterns = level_patterns.get(level_upper, [f'[{level_upper}]'])
            combined = '|'.join(patterns)
            level_re = re.compile(combined, re.IGNORECASE)
            filtered_lines = [l for l in filtered_lines if level_re.search(l)]

        if search_pattern:
            try:
                pattern = re.compile(search_pattern, re.IGNORECASE)
                filtered_lines = [l for l in filtered_lines if pattern.search(l)]
            except re.error:
                filtered_lines = [l for l in filtered_lines if search_pattern in l]

        if tail_count:
            filtered_lines = filtered_lines[-tail_count:]

        # Output
        for line in filtered_lines:
            sys.stdout.write(line)

    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create argument parser for log viewer."""
    parser = argparse.ArgumentParser(
        prog='cbflow run logs',
        description='CBFlow Log Viewer'
    )

    parser.add_argument('--list', '-l', dest='list_logs', action='store_true',
                       help='List all log files')
    parser.add_argument('--tail', '-t', type=int, default=None,
                       help='Show last N lines')
    parser.add_argument('--search', '-s', help='Search pattern (regex supported)')
    parser.add_argument('--level', choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                       help='Filter by log level')
    parser.add_argument('--file', '-f', help='Specific log file to view')

    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()
    return cmd_logs(args)


if __name__ == '__main__':
    sys.exit(main())
