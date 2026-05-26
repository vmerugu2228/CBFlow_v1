#!/usr/bin/env python3
"""
CBFlow State — Lightweight Version Control System (No Git Required)
====================================================================
Tracks file changes across standalone bundles using SQLite.
Ships with the bundle — works completely offline.

Commands:
  cbflow state init                    Initialize state tracking for this bundle
  cbflow state status                  Show modified/added/deleted files since last commit
  cbflow state diff                    Show detailed diff of modified files
  cbflow state commit -m "message"     Commit current state (snapshot all files)
  cbflow state log                     Show commit history
  cbflow state show <commit_id>        Show files changed in a commit
  cbflow state rollback <commit_id>    Restore files to a specific commit
  cbflow state snapshot --tag "name"   Create a named snapshot (alias for commit)
  cbflow state compare --with /path    Compare this bundle against another
  cbflow state export --commit <id>    Export a commit's changed files as patch
"""

import argparse
import difflib
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path

from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.state')


def get_cbflow_root() -> str:
    """Get CBflow root (parent of PD/)."""
    core = os.environ.get('CBFLOW_CORE_DIR', '')
    if core:
        return os.path.dirname(core) if os.path.basename(core) == 'PD' else core
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(os.path.dirname(script_dir)))


def get_db_path() -> str:
    """Get state DB path."""
    return os.path.join(get_cbflow_root(), 'PD', '.cbflow_state.db')


def file_md5(filepath: str) -> str:
    """Compute MD5 checksum."""
    h = hashlib.md5()
    try:
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                h.update(chunk)
    except (OSError, IOError):
        return ''
    return h.hexdigest()


# Skip patterns — don't track these
SKIP_PATTERNS = {
    '.cbflow_state.db', '.cbflow_state.db-journal', '.cbflow_state.db-wal',
    '.DS_Store', '__pycache__', '.pyc', '.git', '.claude',
    'MANIFEST.checksums',
}

SKIP_DIRS = {
    '__pycache__', '.git', '.claude', 'ai', '.knowledge_db',
    '.central_knowledge_db',
}


def should_track(rel_path: str) -> bool:
    """Check if a file should be tracked."""
    parts = rel_path.split('/')
    for d in SKIP_DIRS:
        if d in parts:
            return False
    basename = os.path.basename(rel_path)
    for skip in SKIP_PATTERNS:
        if basename == skip or basename.endswith('.pyc'):
            return False
    return True


def scan_files(pd_dir: str) -> dict:
    """Scan all trackable files. Returns {relative_path: md5}."""
    files = {}
    for root, dirs, filenames in os.walk(pd_dir):
        # Prune skip dirs
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fname in filenames:
            full_path = os.path.join(root, fname)
            rel_path = os.path.relpath(full_path, os.path.dirname(pd_dir))
            if should_track(rel_path):
                files[rel_path] = file_md5(full_path)
    return files


# ═══════════════════════════════════════════════════════════════════════════════
# DATABASE
# ═══════════════════════════════════════════════════════════════════════════════

def init_db(db_path: str):
    """Initialize the state database."""
    conn = sqlite3.connect(db_path)
    conn.execute('''CREATE TABLE IF NOT EXISTS commits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        message TEXT,
        tag TEXT,
        user TEXT,
        file_count INTEGER,
        added INTEGER DEFAULT 0,
        modified INTEGER DEFAULT 0,
        deleted INTEGER DEFAULT 0
    )''')
    conn.execute('''CREATE TABLE IF NOT EXISTS file_state (
        commit_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        md5 TEXT NOT NULL,
        size INTEGER,
        status TEXT DEFAULT 'A',
        FOREIGN KEY (commit_id) REFERENCES commits(id)
    )''')
    conn.execute('''CREATE INDEX IF NOT EXISTS idx_file_state_commit
        ON file_state(commit_id)''')
    conn.execute('''CREATE INDEX IF NOT EXISTS idx_file_state_path
        ON file_state(file_path)''')
    conn.commit()
    conn.close()


def get_latest_commit(db_path: str) -> dict:
    """Get the latest commit. Returns {id, timestamp, message, tag, ...} or None."""
    conn = sqlite3.connect(db_path)
    row = conn.execute(
        "SELECT id, timestamp, message, tag, user, file_count FROM commits "
        "ORDER BY id DESC LIMIT 1"
    ).fetchone()
    conn.close()
    if not row:
        return None
    return {'id': row[0], 'timestamp': row[1], 'message': row[2],
            'tag': row[3], 'user': row[4], 'file_count': row[5]}


def get_commit_files(db_path: str, commit_id: int) -> dict:
    """Get all file states for a commit. Returns {path: md5}."""
    conn = sqlite3.connect(db_path)
    rows = conn.execute(
        "SELECT file_path, md5 FROM file_state WHERE commit_id = ?",
        (commit_id,)
    ).fetchall()
    conn.close()
    return dict(rows)


def compute_changes(old_files: dict, new_files: dict) -> tuple:
    """Compare two file states. Returns (added, modified, deleted, unchanged)."""
    added = {p: new_files[p] for p in new_files if p not in old_files}
    deleted = {p: old_files[p] for p in old_files if p not in new_files}
    modified = {p: new_files[p] for p in new_files
                if p in old_files and new_files[p] != old_files[p]}
    unchanged = {p: new_files[p] for p in new_files
                 if p in old_files and new_files[p] == old_files[p]}
    return added, modified, deleted, unchanged


# ═══════════════════════════════════════════════════════════════════════════════
# COMMANDS
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_init(args) -> int:
    """Initialize state tracking — first commit with all current files."""
    db_path = get_db_path()
    pd_dir = os.path.join(get_cbflow_root(), 'PD')

    if os.path.exists(db_path):
        existing = get_latest_commit(db_path)
        if existing:
            logger.info(f"State DB already exists with {existing['file_count']} files "
                       f"({existing['id']} commits)")
            logger.info(f"Use 'cbflow state commit' to record new changes")
            return 0

    init_db(db_path)

    # Scan all files
    print(f'  Scanning {pd_dir}...')
    files = scan_files(pd_dir)

    # Create initial commit
    user = os.environ.get('USER', 'unknown')
    conn = sqlite3.connect(db_path)
    conn.execute(
        "INSERT INTO commits (timestamp, message, tag, user, file_count, added) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        (datetime.now().isoformat(), 'Initial release state', 'release',
         user, len(files), len(files))
    )
    commit_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]

    for path, md5 in files.items():
        full = os.path.join(get_cbflow_root(), path)
        size = os.path.getsize(full) if os.path.exists(full) else 0
        conn.execute(
            "INSERT INTO file_state (commit_id, file_path, md5, size, status) "
            "VALUES (?, ?, ?, ?, 'A')",
            (commit_id, path, md5, size)
        )
    conn.commit()
    conn.close()

    print(f'\n  {"═" * 60}')
    print(f'  State Initialized')
    print(f'  {"═" * 60}')
    print(f'  Files tracked: {len(files)}')
    print(f'  Commit #1:     Initial release state')
    print(f'  DB:            {os.path.basename(db_path)}')
    print(f'  {"═" * 60}\n')
    return 0


def cmd_status(args) -> int:
    """Show what changed since last commit."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        logger.error("State not initialized. Run: cbflow state init")
        return 1

    pd_dir = os.path.join(get_cbflow_root(), 'PD')
    latest = get_latest_commit(db_path)
    if not latest:
        logger.error("No commits found. Run: cbflow state init")
        return 1

    # Get committed state and current state
    committed = get_commit_files(db_path, latest['id'])
    current = scan_files(pd_dir)
    added, modified, deleted, unchanged = compute_changes(committed, current)

    print(f'\n  {"═" * 60}')
    print(f'  CBflow State Status')
    print(f'  {"═" * 60}')
    print(f'  Last commit: #{latest["id"]} — {latest["message"]}')
    print(f'  Timestamp:   {latest["timestamp"]}')
    print(f'  Tag:         {latest["tag"] or "-"}')
    print(f'  {"─" * 60}')

    if not added and not modified and not deleted:
        print(f'  No changes since last commit (clean)')
    else:
        print(f'  Added:    {len(added)}')
        print(f'  Modified: {len(modified)}')
        print(f'  Deleted:  {len(deleted)}')
        print(f'  {"─" * 60}')

        if modified:
            print(f'\n  Modified:')
            for p in sorted(modified)[:20]:
                print(f'    M  {p}')
            if len(modified) > 20:
                print(f'    ... and {len(modified) - 20} more')

        if added:
            print(f'\n  Added:')
            for p in sorted(added)[:20]:
                print(f'    A  {p}')
            if len(added) > 20:
                print(f'    ... and {len(added) - 20} more')

        if deleted:
            print(f'\n  Deleted:')
            for p in sorted(deleted)[:20]:
                print(f'    D  {p}')
            if len(deleted) > 20:
                print(f'    ... and {len(deleted) - 20} more')

    print(f'\n  Total tracked: {len(current)} files')
    print(f'  {"═" * 60}\n')
    return 0


def cmd_diff(args) -> int:
    """Show detailed diff of modified files."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        logger.error("State not initialized. Run: cbflow state init")
        return 1

    cbflow_root = get_cbflow_root()
    pd_dir = os.path.join(cbflow_root, 'PD')
    latest = get_latest_commit(db_path)
    committed = get_commit_files(db_path, latest['id'])
    current = scan_files(pd_dir)
    added, modified, deleted, _ = compute_changes(committed, current)

    if not modified:
        print("  No modified files.")
        return 0

    # For text files, show unified diff
    for rel_path in sorted(modified):
        full_path = os.path.join(cbflow_root, rel_path)
        if not os.path.exists(full_path):
            continue
        try:
            with open(full_path, 'r', errors='replace') as f:
                current_lines = f.readlines()
        except Exception:
            continue

        # We don't store old content (only md5), so show as "changed file"
        print(f'\n  {"─" * 60}')
        print(f'  Modified: {rel_path}')
        print(f'  Old MD5:  {committed.get(rel_path, "?")}')
        print(f'  New MD5:  {current.get(rel_path, "?")}')
        print(f'  Size:     {os.path.getsize(full_path)} bytes')
    return 0


def cmd_commit(args) -> int:
    """Record current state as a new commit."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        logger.error("State not initialized. Run: cbflow state init")
        return 1

    message = args.message or 'Manual commit'
    tag = getattr(args, 'tag', '') or ''
    pd_dir = os.path.join(get_cbflow_root(), 'PD')

    latest = get_latest_commit(db_path)
    committed = get_commit_files(db_path, latest['id']) if latest else {}
    current = scan_files(pd_dir)
    added, modified, deleted, unchanged = compute_changes(committed, current)

    if not added and not modified and not deleted:
        print("  Nothing to commit (clean state)")
        return 0

    user = os.environ.get('USER', 'unknown')
    conn = sqlite3.connect(db_path)
    conn.execute(
        "INSERT INTO commits (timestamp, message, tag, user, file_count, added, modified, deleted) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (datetime.now().isoformat(), message, tag, user,
         len(current), len(added), len(modified), len(deleted))
    )
    commit_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]

    cbflow_root = get_cbflow_root()
    for path, md5 in current.items():
        full = os.path.join(cbflow_root, path)
        size = os.path.getsize(full) if os.path.exists(full) else 0
        status = 'A' if path in added else ('M' if path in modified else 'U')
        conn.execute(
            "INSERT INTO file_state (commit_id, file_path, md5, size, status) "
            "VALUES (?, ?, ?, ?, ?)",
            (commit_id, path, md5, size, status)
        )
    # Record deletions
    for path in deleted:
        conn.execute(
            "INSERT INTO file_state (commit_id, file_path, md5, size, status) "
            "VALUES (?, ?, '', 0, 'D')",
            (commit_id, path)
        )
    conn.commit()
    conn.close()

    print(f'\n  {"═" * 60}')
    print(f'  Commit #{commit_id}: {message}')
    if tag:
        print(f'  Tag: {tag}')
    print(f'  {"─" * 60}')
    print(f'  Added:    {len(added)}')
    print(f'  Modified: {len(modified)}')
    print(f'  Deleted:  {len(deleted)}')
    print(f'  Total:    {len(current)} files tracked')
    print(f'  {"═" * 60}\n')
    return 0


def cmd_log(args) -> int:
    """Show commit history."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        logger.error("State not initialized. Run: cbflow state init")
        return 1

    conn = sqlite3.connect(db_path)
    rows = conn.execute(
        "SELECT id, timestamp, message, tag, user, file_count, added, modified, deleted "
        "FROM commits ORDER BY id DESC"
    ).fetchall()
    conn.close()

    print(f'\n  {"═" * 70}')
    print(f'  CBflow State History ({len(rows)} commits)')
    print(f'  {"═" * 70}')

    for row in rows:
        cid, ts, msg, tag, user, fc, a, m, d = row
        tag_str = f' [{tag}]' if tag else ''
        changes = f'+{a} ~{m} -{d}' if (a or m or d) else 'initial'
        print(f'\n  #{cid}{tag_str}  {ts}  by {user}')
        print(f'    {msg}')
        print(f'    {changes} ({fc} files)')

    print(f'\n  {"═" * 70}\n')
    return 0


def cmd_show(args) -> int:
    """Show files changed in a specific commit."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        logger.error("State not initialized")
        return 1

    commit_id = args.commit_id
    conn = sqlite3.connect(db_path)

    # Get commit info
    row = conn.execute(
        "SELECT id, timestamp, message, tag, user FROM commits WHERE id = ?",
        (commit_id,)
    ).fetchone()
    if not row:
        logger.error(f"Commit #{commit_id} not found")
        conn.close()
        return 1

    print(f'\n  Commit #{row[0]}: {row[2]}')
    print(f'  Date: {row[1]}  User: {row[4]}  Tag: {row[3] or "-"}')
    print(f'  {"─" * 60}')

    # Show changed files
    files = conn.execute(
        "SELECT file_path, status, size FROM file_state WHERE commit_id = ? "
        "AND status != 'U' ORDER BY status, file_path",
        (commit_id,)
    ).fetchall()
    conn.close()

    status_map = {'A': 'Added', 'M': 'Modified', 'D': 'Deleted'}
    for path, status, size in files:
        label = status_map.get(status, status)
        print(f'  {status}  {path}')

    if not files:
        print(f'  (initial commit — all files added)')

    print(f'\n  Total: {len(files)} changed files\n')
    return 0


def cmd_rollback(args) -> int:
    """Restore files to a specific commit state."""
    db_path = get_db_path()
    if not os.path.exists(db_path):
        logger.error("State not initialized")
        return 1

    commit_id = args.commit_id
    cbflow_root = get_cbflow_root()

    # Get target commit's file state
    target_files = get_commit_files(db_path, commit_id)
    if not target_files:
        logger.error(f"Commit #{commit_id} not found or empty")
        return 1

    # Get current state
    current = scan_files(os.path.join(cbflow_root, 'PD'))
    _, modified, _, _ = compute_changes(target_files, current)

    if not modified:
        print(f"  Already at commit #{commit_id} state (no changes needed)")
        return 0

    print(f'\n  Rollback to commit #{commit_id}')
    print(f'  Files to restore: {len(modified)}')

    if not getattr(args, 'force', False):
        try:
            confirm = input('  Proceed? [y/N]: ').strip().lower()
        except (EOFError, KeyboardInterrupt):
            confirm = 'n'
        if confirm != 'y':
            print('  Cancelled.')
            return 0

    # We can't restore file content (we only store md5), but we can
    # identify what changed. For actual rollback, we'd need content storage.
    print(f'\n  NOTE: State tracking stores checksums, not file content.')
    print(f'  Files that differ from commit #{commit_id}:')
    for p in sorted(modified)[:20]:
        print(f'    {p}')
    print(f'\n  To restore, use: cbflow migrate --from <backup_bundle> --to .')
    return 0


def cmd_compare(args) -> int:
    """Compare this bundle against another bundle's state."""
    db_path = get_db_path()
    other_root = args.with_path

    other_db = os.path.join(other_root, 'PD', '.cbflow_state.db')
    if not os.path.exists(other_db):
        # No state DB — scan files directly
        print(f'  Other bundle has no state DB — scanning files...')
        other_files = scan_files(os.path.join(other_root, 'PD'))
    else:
        other_latest = get_latest_commit(other_db)
        if other_latest:
            other_files = get_commit_files(other_db, other_latest['id'])
        else:
            other_files = scan_files(os.path.join(other_root, 'PD'))

    # Get our current state
    if os.path.exists(db_path):
        our_latest = get_latest_commit(db_path)
        our_files = get_commit_files(db_path, our_latest['id']) if our_latest else {}
    else:
        our_files = scan_files(os.path.join(get_cbflow_root(), 'PD'))

    added, modified, deleted, unchanged = compute_changes(our_files, other_files)

    print(f'\n  {"═" * 70}')
    print(f'  Bundle Comparison')
    print(f'  {"═" * 70}')
    print(f'  Ours:   {get_cbflow_root()} ({len(our_files)} files)')
    print(f'  Other:  {other_root} ({len(other_files)} files)')
    print(f'  {"─" * 70}')
    print(f'  Only in other (new):     {len(added)}')
    print(f'  Different (modified):    {len(modified)}')
    print(f'  Only in ours (removed):  {len(deleted)}')
    print(f'  Identical:               {len(unchanged)}')

    if added:
        print(f'\n  NEW in other ({len(added)}):')
        for p in sorted(added)[:15]:
            print(f'    + {p}')
        if len(added) > 15:
            print(f'    ... and {len(added) - 15} more')

    if modified:
        print(f'\n  DIFFERENT ({len(modified)}):')
        for p in sorted(modified)[:15]:
            print(f'    ~ {p}')
        if len(modified) > 15:
            print(f'    ... and {len(modified) - 15} more')

    if deleted:
        print(f'\n  ONLY IN OURS ({len(deleted)}):')
        for p in sorted(deleted)[:15]:
            print(f'    - {p}')
        if len(deleted) > 15:
            print(f'    ... and {len(deleted) - 15} more')

    print(f'\n  {"═" * 70}\n')
    return 0


def cmd_snapshot(args) -> int:
    """Create a named snapshot (wrapper around commit with tag)."""
    args.message = args.message or f'Snapshot: {args.tag}'
    return cmd_commit(args)


# ═══════════════════════════════════════════════════════════════════════════════
# PARSER
# ═══════════════════════════════════════════════════════════════════════════════

def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='cbflow state',
        description='CBflow State — Lightweight VCS for standalone bundles (no git required)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow state init                          Initialize tracking (first time)
  cbflow state status                        Show changes since last commit
  cbflow state commit -m "Updated tech config for 7T track"
  cbflow state snapshot --tag "pre_migration" -m "Before v2.0.1 migration"
  cbflow state log                           View commit history
  cbflow state show 3                        Show changes in commit #3
  cbflow state compare --with /opt/cbflow_v2 Compare against another bundle
  cbflow state diff                          Show modified file details
""")
    sub = parser.add_subparsers(dest='command')

    sub.add_parser('init', help='Initialize state tracking')

    sub.add_parser('status', help='Show changes since last commit')

    sub.add_parser('diff', help='Show detailed diff of modifications')

    c = sub.add_parser('commit', help='Record current state')
    c.add_argument('-m', '--message', default='', help='Commit message')
    c.add_argument('--tag', default='', help='Tag this commit')

    sub.add_parser('log', help='Show commit history')

    s = sub.add_parser('show', help='Show files in a commit')
    s.add_argument('commit_id', type=int, help='Commit number')

    r = sub.add_parser('rollback', help='Show what to restore for a commit')
    r.add_argument('commit_id', type=int, help='Target commit number')
    r.add_argument('-f', '--force', action='store_true')

    cp = sub.add_parser('compare', help='Compare against another bundle')
    cp.add_argument('--with', dest='with_path', required=True, help='Other bundle path')

    sn = sub.add_parser('snapshot', help='Create named snapshot')
    sn.add_argument('--tag', required=True, help='Snapshot name')
    sn.add_argument('-m', '--message', default='', help='Description')

    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    commands = {
        'init': cmd_init,
        'status': cmd_status,
        'diff': cmd_diff,
        'commit': cmd_commit,
        'log': cmd_log,
        'show': cmd_show,
        'rollback': cmd_rollback,
        'compare': cmd_compare,
        'snapshot': cmd_snapshot,
    }
    return commands[args.command](args)


if __name__ == '__main__':
    sys.exit(main())
