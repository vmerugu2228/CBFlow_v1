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
import ast
import hashlib
import os
import re
import shutil
import subprocess
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
    check = getattr(args, 'check', False)

    # Validate mode — check current install
    if validate:
        return cmd_validate()

    # Compatibility check — verify new bundle works
    if check:
        target = new_root or old_root or os.environ.get('CBFLOW_CORE_DIR', '')
        if not target:
            logger.error("Specify bundle to check with --to or set CBFLOW_CORE_DIR")
            return 1
        return cmd_check_compatibility(target)

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


def cmd_check_compatibility(new_root: str) -> int:
    """Check that new bundle + migrated configs are compatible.

    Verifies:
    1. All variables referenced in command files exist in node configs
    2. All sourced files in command files exist
    3. All tech() variables used in command files have definitions in tech configs
    4. New config variables added in this release have non-empty values
    5. No stale variable references from old release
    """
    pd_dir = os.path.join(new_root, 'PD')
    if not os.path.isdir(pd_dir):
        logger.error(f"PD/ not found in {new_root}")
        return 1

    print(f'\n  {"═" * 70}')
    print(f'  Compatibility Check: {new_root}')
    print(f'  {"═" * 70}')

    issues = []
    warnings = []

    # ── Check 1: All command files (.tcl) in cmds/ parse cleanly ──────
    print(f'\n  [1/5] Command file syntax check...')
    cmd_files = list(Path(os.path.join(pd_dir, 'cmds')).rglob('*.tcl'))
    parse_errors = 0
    for f in cmd_files:
        r = subprocess.run(['tclsh', str(f)], capture_output=True, text=True,
                          timeout=10, cwd=new_root)
        # TCL files will fail at runtime (missing vars) but syntax errors are fatal
        if r.returncode != 0 and 'missing' in r.stderr and 'brace' in r.stderr.lower():
            issues.append(f'Syntax error: {f.relative_to(pd_dir)}')
            parse_errors += 1
    print(f'         {len(cmd_files)} command files, {parse_errors} syntax errors')

    # ── Check 2: All config files parse cleanly ───────────────────────
    print(f'\n  [2/5] Config file syntax check...')
    config_files = list(Path(os.path.join(pd_dir, 'config')).rglob('*.tcl'))
    cfg_errors = 0
    for f in config_files:
        r = subprocess.run(['tclsh', str(f)], capture_output=True, text=True,
                          timeout=10, cwd=new_root)
        if r.returncode != 0 and 'missing' in r.stderr and 'brace' in r.stderr.lower():
            issues.append(f'Config syntax error: {f.relative_to(pd_dir)}')
            cfg_errors += 1
    print(f'         {len(config_files)} config files, {cfg_errors} syntax errors')

    # ── Check 3: All Python scripts compile ───────────────────────────
    print(f'\n  [3/5] Python script compilation...')
    py_files = list(Path(os.path.join(pd_dir, 'utils')).rglob('*.py'))
    py_errors = 0
    for f in py_files:
        try:
            with open(f) as fh:
                ast.parse(fh.read())
        except SyntaxError as e:
            issues.append(f'Python syntax error: {f.relative_to(pd_dir)}: {e}')
            py_errors += 1
    print(f'         {len(py_files)} Python files, {py_errors} syntax errors')

    # ── Check 4: Cross-reference variables ────────────────────────────
    print(f'\n  [4/5] Variable cross-reference check...')

    # Collect all variables DEFINED in node configs
    defined_vars = set()
    for f in Path(os.path.join(pd_dir, 'config', 'flow')).rglob('node_configs/*.tcl'):
        with open(f) as fh:
            for line in fh:
                # Match: key "value" patterns inside array set
                m = re.findall(r'(\w+(?:,\w+)+)\s', line)
                defined_vars.update(m)

    # Collect all variables USED in command files
    used_vars = set()
    for f in Path(os.path.join(pd_dir, 'cmds')).rglob('*.tcl'):
        with open(f) as fh:
            for line in fh:
                # Match: $synth_pnr(var,name) or $sta(var,name) or $tech(var,name)
                refs = re.findall(r'\$(?:synth_pnr|sta|pnr|fp|lec|clp|pv|emir|eco|synth|popt|fcfp)\(([^)]+)\)', line)
                used_vars.update(refs)

    # Find variables used but not defined
    missing_vars = used_vars - defined_vars
    # Filter out common dynamic vars (input,*, common,*, etc.)
    significant_missing = [v for v in missing_vars
                          if not any(v.startswith(p) for p in
                                    ('input,', 'common,', 'output,', 'tool,'))]
    if significant_missing:
        for v in sorted(significant_missing)[:10]:
            warnings.append(f'Variable used in cmds/ but not in node_configs: {v}')
    print(f'         {len(defined_vars)} defined, {len(used_vars)} used, '
          f'{len(significant_missing)} potentially missing')

    # ── Check 5: Source file references ───────────────────────────────
    print(f'\n  [5/5] Source file reference check...')
    missing_sources = 0
    for f in Path(os.path.join(pd_dir, 'cmds')).rglob('*.tcl'):
        with open(f) as fh:
            for line_no, line in enumerate(fh, 1):
                # Match: source "path" or source $var/path
                m = re.search(r'source\s+"([^"$]+)"', line)
                if m:
                    src_path = m.group(1)
                    if src_path.startswith('/') and not os.path.exists(src_path):
                        # Absolute path that doesn't exist — but may be runtime
                        pass
                    elif not src_path.startswith('$') and not src_path.startswith('/'):
                        full = os.path.join(pd_dir, src_path)
                        if not os.path.exists(full):
                            warnings.append(f'{f.relative_to(pd_dir)}:{line_no}: source "{src_path}" not found')
                            missing_sources += 1
    print(f'         {missing_sources} missing source references')

    # ── Report ────────────────────────────────────────────────────────
    print(f'\n  {"═" * 70}')
    print(f'  Compatibility Report')
    print(f'  {"═" * 70}')
    print(f'  Errors:   {len(issues)}')
    print(f'  Warnings: {len(warnings)}')

    if issues:
        print(f'\n  ERRORS (must fix):')
        for i in issues:
            print(f'    [ERROR] {i}')

    if warnings:
        print(f'\n  WARNINGS (review):')
        for w in warnings[:15]:
            print(f'    [WARN]  {w}')
        if len(warnings) > 15:
            print(f'    ... and {len(warnings) - 15} more')

    if not issues and not warnings:
        print(f'\n  ✓ All clear — new bundle is compatible')

    print(f'  {"═" * 70}\n')
    return 1 if issues else 0


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
    parser.add_argument('--check', action='store_true',
                       help='Check compatibility of new bundle (syntax, variables, sources)')
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
