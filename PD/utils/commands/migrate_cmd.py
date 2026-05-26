#!/usr/bin/env python3
"""
CBFlow Migrate Command
Safely migrates user customizations from an old CBflow bundle to a new one.

Existing runs are NOT touched — they are standalone with embedded configs.
Migration only applies to the CBflow installation (PD/ directory) so that
NEW runs created from the new bundle inherit the user's customizations.

Usage:
  cbflow migrate --from /opt/cbflow_v1 --to /opt/cbflow_v2
  cbflow migrate --from /opt/cbflow_v1 --to /opt/cbflow_v2 --dry-run
  cbflow migrate --diff --from /opt/cbflow_v1 --to /opt/cbflow_v2
  cbflow migrate --validate
"""

import argparse
import hashlib
import os
import re
import shutil
import sys
from pathlib import Path

from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.migrate')

# Files that contain user customizations — these get migrated
USER_CONFIG_PATTERNS = [
    'PD/config/project/**/v*/*_config.tcl',     # Project configs (workarea_path, race_db_path, etc.)
    'PD/config/tech/**/v*/*_config.tcl',         # Tech configs (lib_root, library paths)
    'PD/config/tech/**/v*/metal_stack/*.tcl',     # Metal stack customizations
    'PD/config/exit/v*/threshold_overrides.tcl',  # Threshold overrides per project
    'PD/config/exit/v*/waiver_config.tcl',        # Waivers
]

# Files that are NEVER migrated (always use new version)
NEVER_MIGRATE = [
    'PD/MANIFEST.checksums',
    'PD/bin/*',
    'PD/utils/commands/*.py',
    'PD/utils/dashboard/*.py',
    'PD/utils/validation/**/*.py',
]


def file_md5(filepath: str) -> str:
    """Compute MD5 of a file."""
    h = hashlib.md5()
    try:
        with open(filepath, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b''):
                h.update(chunk)
    except (OSError, IOError):
        return ''
    return h.hexdigest()


def load_manifest(bundle_root: str) -> dict:
    """Load MANIFEST.checksums. Returns {relative_path: md5}."""
    manifest = {}
    mf_path = os.path.join(bundle_root, 'PD', 'MANIFEST.checksums')
    if not os.path.exists(mf_path):
        return manifest
    with open(mf_path) as f:
        for line in f:
            parts = line.strip().split(None, 1)
            if len(parts) == 2:
                manifest[parts[1]] = parts[0]
    return manifest


def find_user_modified_files(old_root: str) -> list:
    """Find files the user modified in the old bundle.

    Compares actual file MD5 against MANIFEST.checksums (original release state).
    Returns list of (relative_path, reason) tuples.
    """
    manifest = load_manifest(old_root)
    modified = []

    if not manifest:
        # No manifest — scan known user config locations
        for pattern in USER_CONFIG_PATTERNS:
            for f in Path(old_root).glob(pattern):
                rel = str(f.relative_to(old_root))
                modified.append((rel, 'no manifest — assumed modified'))
        return modified

    # Compare actual files against manifest
    for rel_path, orig_md5 in manifest.items():
        actual_path = os.path.join(old_root, rel_path)
        if not os.path.exists(actual_path):
            continue
        actual_md5 = file_md5(actual_path)
        if actual_md5 != orig_md5:
            modified.append((rel_path, 'modified'))

    return modified


def find_new_release_changes(old_root: str, new_root: str) -> dict:
    """Compare old and new manifests to find what changed in the new release.

    Returns {rel_path: 'added'|'changed'|'removed'}
    """
    old_m = load_manifest(old_root)
    new_m = load_manifest(new_root)
    changes = {}

    for path, md5 in new_m.items():
        if path not in old_m:
            changes[path] = 'added'
        elif old_m[path] != md5:
            changes[path] = 'changed'

    for path in old_m:
        if path not in new_m:
            changes[path] = 'removed'

    return changes


def cmd_migrate(args) -> int:
    """Migrate user customizations from old bundle to new bundle."""
    old_root = args.from_root
    new_root = args.to_root
    dry_run = getattr(args, 'dry_run', False)
    do_diff = getattr(args, 'diff', False)
    validate = getattr(args, 'validate', False)

    # Validate mode — check current install
    if validate:
        return cmd_validate()

    if not old_root or not new_root:
        logger.error("Both --from and --to are required")
        return 1

    # Normalize paths
    old_root = os.path.abspath(old_root)
    new_root = os.path.abspath(new_root)

    # Validate directories exist
    for d, label in [(old_root, 'old'), (new_root, 'new')]:
        if not os.path.isdir(os.path.join(d, 'PD')):
            logger.error(f"{label} root does not contain PD/ directory: {d}")
            return 1

    # ── Diff mode ─────────────────────────────────────────────────────
    if do_diff:
        return cmd_diff(old_root, new_root)

    # ── Migration ─────────────────────────────────────────────────────
    print(f'\n  {"═" * 70}')
    print(f'  CBflow Bundle Migration')
    print(f'  {"═" * 70}')
    print(f'  From (old): {old_root}')
    print(f'  To (new):   {new_root}')
    if dry_run:
        print(f'  Mode:       DRY RUN')
    print(f'  {"─" * 70}')

    # Step 1: Find user modifications in old bundle
    print(f'\n  Step 1: Detecting user modifications in old bundle...')
    user_mods = find_user_modified_files(old_root)
    print(f'          Found {len(user_mods)} modified file(s)')

    # Step 2: Find what changed in new release
    print(f'\n  Step 2: Detecting release changes...')
    release_changes = find_new_release_changes(old_root, new_root)
    added = sum(1 for v in release_changes.values() if v == 'added')
    changed = sum(1 for v in release_changes.values() if v == 'changed')
    removed = sum(1 for v in release_changes.values() if v == 'removed')
    print(f'          {added} added, {changed} changed, {removed} removed')

    # Step 3: Migrate user modifications
    print(f'\n  Step 3: Migrating user customizations...')
    stats = {'migrated': 0, 'conflict_kept_user': 0, 'conflict_kept_new': 0,
             'skipped': 0, 'backed_up': 0}

    for rel_path, reason in user_mods:
        old_file = os.path.join(old_root, rel_path)
        new_file = os.path.join(new_root, rel_path)

        if not os.path.exists(old_file):
            continue

        # Check if this file also changed in new release
        is_conflict = rel_path in release_changes and release_changes[rel_path] == 'changed'

        if is_conflict:
            # Both user and release changed — prompt
            print(f'\n    CONFLICT: {rel_path}')
            print(f'    Your version differs from original release.')
            print(f'    New release also updated this file.')
            print(f'    [K]eep your version  [N]ew release version  [S]kip')
            try:
                choice = input('    > ').strip().lower()
            except (EOFError, KeyboardInterrupt):
                choice = 's'

            if choice == 'k':
                if not dry_run:
                    # Backup new version, copy user's
                    if os.path.exists(new_file):
                        shutil.copy2(new_file, new_file + '.release_backup')
                        stats['backed_up'] += 1
                    shutil.copy2(old_file, new_file)
                stats['conflict_kept_user'] += 1
                print(f'    → Kept your version (new backed up as .release_backup)')
            elif choice == 'n':
                stats['conflict_kept_new'] += 1
                print(f'    → Kept new release version')
            else:
                stats['skipped'] += 1
        else:
            # User modified, release didn't change — safe to copy
            if not dry_run:
                os.makedirs(os.path.dirname(new_file), exist_ok=True)
                if os.path.exists(new_file):
                    shutil.copy2(new_file, new_file + '.release_backup')
                    stats['backed_up'] += 1
                shutil.copy2(old_file, new_file)
            stats['migrated'] += 1
            tag = '[DRY]' if dry_run else '[OK]'
            print(f'    {tag} {rel_path}')

    # Step 4: Report
    print(f'\n  {"═" * 70}')
    print(f'  Migration {"(DRY RUN) " if dry_run else ""}Complete')
    print(f'  {"═" * 70}')
    print(f'  Files migrated (safe):    {stats["migrated"]}')
    print(f'  Conflicts (kept yours):   {stats["conflict_kept_user"]}')
    print(f'  Conflicts (kept new):     {stats["conflict_kept_new"]}')
    print(f'  Skipped:                  {stats["skipped"]}')
    print(f'  Backed up:                {stats["backed_up"]}')
    print(f'  {"─" * 70}')
    print(f'  New release additions:    {added} new files')
    print(f'  New release updates:      {changed} files')
    print(f'  {"═" * 70}')

    if not dry_run:
        print(f'\n  Next steps:')
        print(f'  1. Set environment: export CBFLOW_HOME={new_root}/PD')
        print(f'  2. Verify: cbflow --version')
        print(f'  3. Create new runs: cbflow workspace create --config user_config.tcl')
        print(f'  Note: Existing runs are standalone — they continue to work as-is.')
    print()
    return 0


def cmd_diff(old_root: str, new_root: str) -> int:
    """Show what changed between two releases."""
    changes = find_new_release_changes(old_root, new_root)
    user_mods = find_user_modified_files(old_root)
    user_mod_paths = {r for r, _ in user_mods}

    added = sorted(k for k, v in changes.items() if v == 'added')
    changed = sorted(k for k, v in changes.items() if v == 'changed')
    removed = sorted(k for k, v in changes.items() if v == 'removed')

    print(f'\n  {"═" * 70}')
    print(f'  Release Diff')
    print(f'  {"═" * 70}')
    print(f'  Old: {old_root}')
    print(f'  New: {new_root}')
    print(f'  {"─" * 70}')
    print(f'  Added:   {len(added)}')
    print(f'  Changed: {len(changed)}')
    print(f'  Removed: {len(removed)}')
    print(f'  Your modifications: {len(user_mods)}')
    print(f'  Potential conflicts: {len([c for c in changed if c in user_mod_paths])}')

    if added:
        print(f'\n  NEW FILES ({len(added)}):')
        for f in added[:15]:
            print(f'    + {f}')
        if len(added) > 15:
            print(f'    ... and {len(added) - 15} more')

    if changed:
        print(f'\n  CHANGED FILES ({len(changed)}):')
        for f in changed[:15]:
            conflict = ' ← CONFLICT (you also modified)' if f in user_mod_paths else ''
            print(f'    ~ {f}{conflict}')
        if len(changed) > 15:
            print(f'    ... and {len(changed) - 15} more')

    if removed:
        print(f'\n  REMOVED FILES ({len(removed)}):')
        for f in removed[:10]:
            print(f'    - {f}')
        if len(removed) > 10:
            print(f'    ... and {len(removed) - 10} more')

    print(f'\n  {"═" * 70}\n')
    return 0


def cmd_validate() -> int:
    """Validate current CBflow installation."""
    core_dir = os.environ.get('CBFLOW_CORE_DIR', '')
    if not core_dir:
        logger.error("CBFLOW_CORE_DIR not set")
        return 1

    print(f'\n  {"═" * 60}')
    print(f'  CBflow Installation Validation')
    print(f'  {"═" * 60}')
    print(f'  CBFLOW_CORE_DIR: {core_dir}')

    issues = []

    # Check critical directories
    for d in ['bin', 'config/flow', 'config/exit', 'config/project',
              'cmds', 'utils/commands', 'utils/dashboard', 'utils/validation']:
        full = os.path.join(core_dir, d)
        if os.path.isdir(full):
            print(f'  [OK]   {d}/')
        else:
            print(f'  [MISS] {d}/')
            issues.append(f'Missing directory: {d}')

    # Check critical files
    for f in ['bin/cbflow', 'config/flow/v1.0.0/flow_config.tcl',
              'config/flow/v1.0.0/mmmc_config.tcl',
              'utils/commands/race_engine.py',
              'utils/commands/checklist_cmd.py']:
        full = os.path.join(core_dir, f)
        if os.path.exists(full):
            print(f'  [OK]   {f}')
        else:
            print(f'  [MISS] {f}')
            issues.append(f'Missing file: {f}')

    # Check manifest
    mf = os.path.join(core_dir, 'MANIFEST.checksums')
    if os.path.exists(mf):
        with open(mf) as fh:
            count = sum(1 for _ in fh)
        print(f'  [OK]   MANIFEST.checksums ({count} files)')
    else:
        print(f'  [WARN] MANIFEST.checksums not found (bundle without manifest)')

    # Check project configs have required paths
    for cfg in Path(os.path.join(core_dir, 'config', 'project')).rglob('*_config.tcl'):
        with open(cfg) as fh:
            content = fh.read()
        name = cfg.relative_to(core_dir)
        for var in ['workarea_path', 'race,db_path']:
            if f'project({var})' in content:
                m = re.search(rf'project\({re.escape(var)}\)\s+"([^"]+)"', content)
                if m:
                    path = m.group(1)
                    if path.startswith('/') and not os.path.exists(path):
                        print(f'  [WARN] {name}: project({var}) = {path} — does not exist')
                        issues.append(f'{name}: {var} path missing')

    print(f'\n  Result: {len(issues)} issue(s)')
    print(f'  {"═" * 60}\n')
    return 0 if not issues else 1


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='cbflow migrate',
        description='Migrate user customizations between CBflow bundles',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Migrate customizations from old bundle to new:
  cbflow migrate --from /opt/cbflow_v1 --to /opt/cbflow_v2

  # Preview changes (no modifications):
  cbflow migrate --from /opt/cbflow_v1 --to /opt/cbflow_v2 --dry-run

  # See what changed between releases:
  cbflow migrate --diff --from /opt/cbflow_v1 --to /opt/cbflow_v2

  # Validate current installation:
  cbflow migrate --validate

Note: Existing runs are standalone — they are NOT modified.
      Only the CBflow installation (PD/) is updated so new runs
      inherit your customizations.
""")
    parser.add_argument('--from', dest='from_root', default='',
                       help='Old CBflow bundle root')
    parser.add_argument('--to', dest='to_root', default='',
                       help='New CBflow bundle root')
    parser.add_argument('--dry-run', action='store_true', dest='dry_run',
                       help='Preview changes without modifying files')
    parser.add_argument('--diff', action='store_true',
                       help='Show diff between old and new release')
    parser.add_argument('--validate', action='store_true',
                       help='Validate current CBflow installation')
    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()

    if not args.from_root and not args.to_root and not args.validate and not args.diff:
        parser.print_help()
        return 0

    return cmd_migrate(args)


if __name__ == '__main__':
    sys.exit(main())
