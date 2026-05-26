#!/usr/bin/env python3
"""
CBFlow Migrate Command
Safely migrates CBflow installation paths and upgrades files when
customers receive a new bundle.

Usage:
  cbflow migrate --old-root /opt/cbflow_v1 --new-root /opt/cbflow_v2
  cbflow migrate --new-root /opt/cbflow_v2 --workarea /proj/workarea
  cbflow migrate --new-root /opt/cbflow_v2 --run-dir /proj/workarea/P0_run_test1
  cbflow migrate --validate --workarea /proj/workarea
  cbflow migrate --rollback --workarea /proj/workarea
  cbflow migrate --upgrade --old-root /opt/cbflow_v1 --new-root /opt/cbflow_v2
  cbflow migrate --diff --old-root /opt/cbflow_v1 --new-root /opt/cbflow_v2
"""

import argparse
import glob
import hashlib
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.migrate')

# Files that are always user-owned — never auto-upgrade
USER_OWNED_PATTERNS = [
    '*/config/project/*',
    '*/setup/user_config.tcl',
    '*/setup/override_config*.tcl',
    '*/setup/runtime_flow_config.tcl',
]


# ═══════════════════════════════════════════════════════════════════════════════
# PATH MIGRATION
# ═══════════════════════════════════════════════════════════════════════════════

def detect_old_root(run_dir: str) -> str:
    """Auto-detect old CBflow root from a run's .run.cbflow.env."""
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if not os.path.exists(env_file):
        return ''
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line.startswith('export '):
                line = line[7:]
            if line.startswith('FLOW_DIR='):
                flow_dir = line.split('=', 1)[1].strip('"').strip("'")
                # FLOW_DIR points to PD/ — parent is the root
                return os.path.dirname(flow_dir)
    return ''


def scan_run_dir(run_dir: str, old_root: str) -> list:
    """Scan a run directory for files containing old_root paths."""
    files_with_paths = []
    patterns = [
        os.path.join(run_dir, '.run.cbflow.env'),
        os.path.join(run_dir, '.run.cbflow.tcl'),
    ]
    # Add all config.tcl and setup.tcl in work dirs
    for f in Path(run_dir).rglob('work/*/run/config.tcl'):
        patterns.append(str(f))
    for f in Path(run_dir).rglob('work/*/run/setup.tcl'):
        patterns.append(str(f))
    # Add launch scripts
    for f in Path(run_dir).rglob('work/*/run/launch_*.csh'):
        patterns.append(str(f))

    for filepath in patterns:
        if os.path.exists(filepath) and os.path.isfile(filepath):
            try:
                with open(filepath, 'r', errors='replace') as f:
                    content = f.read()
                if old_root in content:
                    count = content.count(old_root)
                    files_with_paths.append((filepath, count))
            except (OSError, IOError):
                pass
    return files_with_paths


def scan_workarea(workarea_path: str) -> list:
    """Find all run directories in a workarea."""
    runs = []
    if not os.path.isdir(workarea_path):
        return runs
    for entry in os.listdir(workarea_path):
        full = os.path.join(workarea_path, entry)
        if os.path.isdir(full) and re.match(r'P\d_run_', entry):
            runs.append(full)
    # Also check subdirectories (workarea/<design>/<runs>)
    for subdir in os.listdir(workarea_path):
        sub_full = os.path.join(workarea_path, subdir)
        if os.path.isdir(sub_full) and not subdir.startswith('P'):
            for entry in os.listdir(sub_full):
                full = os.path.join(sub_full, entry)
                if os.path.isdir(full) and re.match(r'P\d_run_', entry):
                    runs.append(full)
    return sorted(runs)


def migrate_file(filepath: str, old_root: str, new_root: str,
                 dry_run: bool = False, backup: bool = True) -> int:
    """Replace old_root with new_root in a file. Returns replacement count."""
    try:
        with open(filepath, 'r', errors='replace') as f:
            content = f.read()
    except (OSError, IOError):
        return 0

    count = content.count(old_root)
    if count == 0:
        return 0

    new_content = content.replace(old_root, new_root)

    if dry_run:
        return count

    # Backup
    if backup:
        bak = filepath + '.migrate_bak'
        if not os.path.exists(bak):
            shutil.copy2(filepath, bak)

    # Atomic write
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(filepath))
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(new_content)
        os.replace(tmp, filepath)
    except Exception:
        os.unlink(tmp)
        raise

    return count


def migrate_project_configs(cbflow_root: str, old_root: str, new_root: str,
                            dry_run: bool = False) -> tuple:
    """Migrate project config files. Returns (files_updated, paths_replaced)."""
    files_updated = 0
    paths_replaced = 0
    config_dir = os.path.join(cbflow_root, 'PD', 'config', 'project')
    if not os.path.isdir(config_dir):
        return 0, 0
    for f in Path(config_dir).rglob('*.tcl'):
        count = migrate_file(str(f), old_root, new_root, dry_run=dry_run)
        if count > 0:
            files_updated += 1
            paths_replaced += count
            if dry_run:
                logger.info(f"    [DRY] {f} — {count} replacements")
    return files_updated, paths_replaced


def validate_run(run_dir: str) -> list:
    """Validate a run directory — check all referenced paths exist."""
    issues = []
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if not os.path.exists(env_file):
        issues.append(f"Missing .run.cbflow.env")
        return issues

    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line.startswith('export '):
                line = line[7:]
            if '=' in line and not line.startswith('#'):
                key, val = line.split('=', 1)
                val = val.strip('"').strip("'")
                if val.startswith('/') and key in ('FLOW_DIR', 'CONFIG_ROOT',
                                                    'SCRIPTS_ROOT', 'PROJECT_ROOT'):
                    if not os.path.exists(val):
                        issues.append(f"{key}={val} — path does not exist")
    return issues


# ═══════════════════════════════════════════════════════════════════════════════
# FILE UPGRADE (3-way merge)
# ═══════════════════════════════════════════════════════════════════════════════

def load_manifest(bundle_path: str) -> dict:
    """Load MANIFEST.checksums from a bundle. Returns {relative_path: md5}."""
    manifest = {}
    mf_path = os.path.join(bundle_path, 'PD', 'MANIFEST.checksums')
    if not os.path.exists(mf_path):
        return manifest
    with open(mf_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                md5, path = parts[0], parts[1]
                # Handle both md5sum and md5 -r output formats
                if path.startswith('PD/'):
                    manifest[path] = md5
    return manifest


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


def is_user_owned(rel_path: str) -> bool:
    """Check if a file is user-owned (never auto-upgrade)."""
    from fnmatch import fnmatch
    for pattern in USER_OWNED_PATTERNS:
        if fnmatch(rel_path, pattern):
            return True
    return False


def cmd_upgrade(old_root: str, new_root: str, auto: bool = False,
                dry_run: bool = False) -> int:
    """Upgrade files from old bundle to new bundle with conflict detection."""
    old_manifest = load_manifest(old_root)
    new_manifest = load_manifest(new_root)

    if not old_manifest:
        logger.error(f"No MANIFEST.checksums in old bundle: {old_root}/PD/")
        logger.error(f"Bundle was created without manifest. Cannot detect modifications.")
        return 1
    if not new_manifest:
        logger.error(f"No MANIFEST.checksums in new bundle: {new_root}/PD/")
        return 1

    stats = {'added': 0, 'auto_upgraded': 0, 'kept': 0, 'upgraded': 0,
             'skipped': 0, 'removed_warning': 0, 'backed_up': 0}

    # Files in new release
    for rel_path, new_md5 in sorted(new_manifest.items()):
        old_md5 = old_manifest.get(rel_path, '')
        actual_path = os.path.join(old_root, rel_path)
        new_path = os.path.join(new_root, rel_path)

        # Skip user-owned files
        if is_user_owned(rel_path):
            continue

        if not old_md5:
            # New file — auto-add
            if not dry_run:
                os.makedirs(os.path.dirname(actual_path), exist_ok=True)
                shutil.copy2(new_path, actual_path)
            stats['added'] += 1
            logger.info(f"  [NEW]  {rel_path}")
            continue

        # File existed in old release
        actual_md5 = file_md5(actual_path) if os.path.exists(actual_path) else ''
        user_modified = actual_md5 != old_md5 and actual_md5 != ''
        release_changed = new_md5 != old_md5

        if not release_changed:
            # Release didn't change this file — skip
            continue

        if not user_modified:
            # User didn't modify — safe to auto-upgrade
            if not dry_run:
                shutil.copy2(new_path, actual_path)
            stats['auto_upgraded'] += 1
            continue

        # CONFLICT: both user and release changed
        if auto:
            # Auto mode: show conflict, skip (user decides later)
            logger.warning(f"  [CONFLICT] {rel_path} — modified by user AND release")
            stats['skipped'] += 1
            continue

        # Interactive: prompt user
        print(f'\n  CONFLICT: {rel_path}')
        print(f'  User modified: YES (md5 differs from original release)')
        print(f'  Release changed: YES (new version available)')
        print(f'  [K]eep yours  [U]pgrade (backup yours)  [S]kip')
        try:
            choice = input('  > ').strip().lower()
        except (EOFError, KeyboardInterrupt):
            choice = 's'

        if choice == 'u':
            if not dry_run:
                # Backup user's version
                bak = actual_path + '.user_backup'
                shutil.copy2(actual_path, bak)
                stats['backed_up'] += 1
                # Copy new version
                shutil.copy2(new_path, actual_path)
            stats['upgraded'] += 1
            logger.info(f"  [UPGRADED] {rel_path} (yours backed up as .user_backup)")
        elif choice == 'k':
            stats['kept'] += 1
            logger.info(f"  [KEPT]     {rel_path}")
        else:
            stats['skipped'] += 1

    # Files removed in new release
    for rel_path in sorted(old_manifest.keys()):
        if rel_path not in new_manifest:
            actual_path = os.path.join(old_root, rel_path)
            if os.path.exists(actual_path):
                stats['removed_warning'] += 1
                logger.warning(f"  [REMOVED in new release] {rel_path} — kept (not deleted)")

    # Report
    print(f'\n  {"═" * 60}')
    print(f'  Upgrade Report')
    print(f'  {"═" * 60}')
    print(f'  New/added files:           {stats["added"]}')
    print(f'  Auto-upgraded (unchanged): {stats["auto_upgraded"]}')
    print(f'  User-modified (upgraded):  {stats["upgraded"]}')
    print(f'  User-modified (kept):      {stats["kept"]}')
    print(f'  Skipped (decide later):    {stats["skipped"]}')
    print(f'  Removed in new release:    {stats["removed_warning"]} (kept)')
    print(f'  Backed up:                 {stats["backed_up"]} files')
    print(f'  {"═" * 60}\n')
    return 0


def cmd_diff(old_root: str, new_root: str) -> int:
    """Show what changed between old and new release."""
    old_manifest = load_manifest(old_root)
    new_manifest = load_manifest(new_root)

    if not old_manifest or not new_manifest:
        logger.error("Both bundles must have MANIFEST.checksums")
        return 1

    added = sorted(set(new_manifest.keys()) - set(old_manifest.keys()))
    removed = sorted(set(old_manifest.keys()) - set(new_manifest.keys()))
    changed = sorted(k for k in old_manifest if k in new_manifest and old_manifest[k] != new_manifest[k])

    print(f'\n  {"═" * 60}')
    print(f'  Release Diff: {os.path.basename(old_root)} → {os.path.basename(new_root)}')
    print(f'  {"═" * 60}')
    print(f'  Added:   {len(added)}')
    print(f'  Changed: {len(changed)}')
    print(f'  Removed: {len(removed)}')
    print(f'  {"─" * 60}')

    if added:
        print(f'\n  ADDED ({len(added)}):')
        for f in added[:20]:
            print(f'    + {f}')
        if len(added) > 20:
            print(f'    ... and {len(added) - 20} more')

    if changed:
        print(f'\n  CHANGED ({len(changed)}):')
        for f in changed[:20]:
            print(f'    ~ {f}')
        if len(changed) > 20:
            print(f'    ... and {len(changed) - 20} more')

    if removed:
        print(f'\n  REMOVED ({len(removed)}):')
        for f in removed[:20]:
            print(f'    - {f}')
        if len(removed) > 20:
            print(f'    ... and {len(removed) - 20} more')

    print(f'\n  {"═" * 60}\n')
    return 0


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN COMMANDS
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_migrate(args) -> int:
    """Main migration command."""
    new_root = args.new_root
    old_root = getattr(args, 'old_root', '') or ''
    workarea = getattr(args, 'workarea', '') or ''
    run_dir = getattr(args, 'run_dir', '') or ''
    dry_run = getattr(args, 'dry_run', False)
    validate_only = getattr(args, 'validate', False)
    rollback = getattr(args, 'rollback', False)
    do_upgrade = getattr(args, 'upgrade', False)
    do_diff = getattr(args, 'diff', False)
    auto = getattr(args, 'auto', False)

    # Diff mode
    if do_diff:
        if not old_root or not new_root:
            logger.error("--diff requires both --old-root and --new-root")
            return 1
        return cmd_diff(old_root, new_root)

    # Upgrade mode
    if do_upgrade:
        if not old_root or not new_root:
            logger.error("--upgrade requires both --old-root and --new-root")
            return 1
        return cmd_upgrade(old_root, new_root, auto=auto, dry_run=dry_run)

    # Find run directories
    runs = []
    if run_dir:
        runs = [run_dir]
    elif workarea:
        runs = scan_workarea(workarea)
    else:
        # Try current directory as workarea
        runs = scan_workarea(os.getcwd())
        if not runs:
            logger.error("No run directories found. Use --workarea or --run-dir")
            return 1

    # Auto-detect old root
    if not old_root and runs:
        old_root = detect_old_root(runs[0])
        if old_root:
            logger.info(f"Auto-detected old root: {old_root}")

    if not old_root:
        logger.error("Cannot detect old root. Use --old-root explicitly.")
        return 1

    # Validate mode
    if validate_only:
        print(f'\n  {"═" * 60}')
        print(f'  Migration Validation')
        print(f'  {"═" * 60}')
        all_ok = True
        for rd in runs:
            issues = validate_run(rd)
            name = os.path.basename(rd)
            if issues:
                print(f'  [FAIL] {name}')
                for issue in issues:
                    print(f'         {issue}')
                all_ok = False
            else:
                print(f'  [PASS] {name}')
        print(f'  {"═" * 60}\n')
        return 0 if all_ok else 1

    # Rollback mode
    if rollback:
        restored = 0
        for rd in runs:
            for bak in Path(rd).rglob('*.migrate_bak'):
                original = str(bak)[:-len('.migrate_bak')]
                shutil.copy2(str(bak), original)
                os.remove(str(bak))
                restored += 1
        logger.info(f"Restored {restored} files from backup")
        return 0

    if not new_root:
        logger.error("--new-root required for migration")
        return 1

    # Migrate
    print(f'\n  {"═" * 60}')
    print(f'  CBflow Path Migration')
    print(f'  {"═" * 60}')
    print(f'  Old root: {old_root}')
    print(f'  New root: {new_root}')
    print(f'  Runs:     {len(runs)}')
    if dry_run:
        print(f'  Mode:     DRY RUN (no changes)')
    print(f'  {"─" * 60}')

    total_files = 0
    total_paths = 0

    for rd in runs:
        name = os.path.basename(rd)
        files = scan_run_dir(rd, old_root)
        run_paths = 0
        for filepath, count in files:
            replaced = migrate_file(filepath, old_root, new_root, dry_run=dry_run)
            run_paths += replaced
            total_files += 1
        total_paths += run_paths
        tag = '[DRY]' if dry_run else '[OK]'
        print(f'  {tag} {name}: {len(files)} files, {run_paths} paths')

    # Migrate project configs (in the new root)
    pf, pp = migrate_project_configs(new_root, old_root, new_root, dry_run=dry_run)
    total_files += pf
    total_paths += pp

    print(f'\n  {"═" * 60}')
    print(f'  Migration {"(DRY RUN) " if dry_run else ""}Complete')
    print(f'  {"═" * 60}')
    print(f'  Runs migrated:    {len(runs)}')
    print(f'  Files updated:    {total_files}')
    print(f'  Paths replaced:   {total_paths}')

    if not dry_run:
        # Validate
        all_ok = True
        for rd in runs:
            issues = validate_run(rd)
            if issues:
                all_ok = False
                for issue in issues:
                    logger.warning(f"  Validation: {os.path.basename(rd)}: {issue}")
        print(f'  Validation:       {"PASS" if all_ok else "ISSUES FOUND"}')

    print(f'  {"═" * 60}\n')
    return 0


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='cbflow migrate',
        description='CBFlow Bundle Migration — safely update paths and upgrade files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Migrate paths after moving bundle:
  cbflow migrate --old-root /opt/cbflow_v1 --new-root /opt/cbflow_v2 --workarea /proj/workarea

  # Auto-detect old root, migrate specific run:
  cbflow migrate --new-root /opt/cbflow_v2 --run-dir /proj/workarea/P0_run_test1

  # Dry run (preview changes):
  cbflow migrate --new-root /opt/cbflow_v2 --workarea /proj/workarea --dry-run

  # Validate all paths resolve:
  cbflow migrate --validate --workarea /proj/workarea

  # Rollback migration:
  cbflow migrate --rollback --workarea /proj/workarea

  # Show diff between releases:
  cbflow migrate --diff --old-root /opt/cbflow_v1 --new-root /opt/cbflow_v2

  # Upgrade files (3-way merge with conflict detection):
  cbflow migrate --upgrade --old-root /opt/cbflow_v1 --new-root /opt/cbflow_v2

  # Auto-upgrade unchanged files, skip conflicts:
  cbflow migrate --upgrade --auto --old-root /opt/cbflow_v1 --new-root /opt/cbflow_v2
""")
    parser.add_argument('--old-root', dest='old_root', default='',
                       help='Old CBflow installation root (auto-detected if omitted)')
    parser.add_argument('--new-root', dest='new_root', default='',
                       help='New CBflow installation root')
    parser.add_argument('--workarea', default='',
                       help='Workarea path (scans for all run dirs)')
    parser.add_argument('--run-dir', dest='run_dir', default='',
                       help='Specific run directory to migrate')
    parser.add_argument('--dry-run', action='store_true', dest='dry_run',
                       help='Preview changes without modifying files')
    parser.add_argument('--validate', action='store_true',
                       help='Validate all paths resolve after migration')
    parser.add_argument('--rollback', action='store_true',
                       help='Restore files from .migrate_bak backups')
    parser.add_argument('--upgrade', action='store_true',
                       help='Upgrade files from old to new release (3-way merge)')
    parser.add_argument('--diff', action='store_true',
                       help='Show diff between old and new release')
    parser.add_argument('--auto', action='store_true',
                       help='Auto-upgrade unchanged files, skip conflicts (with --upgrade)')
    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()
    return cmd_migrate(args)


if __name__ == '__main__':
    sys.exit(main())
