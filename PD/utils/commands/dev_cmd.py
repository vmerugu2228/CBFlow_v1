#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Development Workflow Command Handler
# Description: Manages dev versions, local sandboxes, and promotion to release
# Usage: cbflow flow dev <subcommand> [options]
#
# Workflow:
#   1. cbflow flow dev start --component config/flow --from v1.0.0
#      Creates v1.0.1-dev (writable copy from locked release)
#   2. Edit files in the -dev version freely
#   3. cbflow flow dev promote --component config/flow
#      Renames v1.0.1-dev → v1.0.1 (ready for release)
#   4. cbflow flow release create --type patch
#      Locks v1.0.1 permanently
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

import logging

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir

logger = logging.getLogger('cbflow.dev')
if not logger.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter('%(message)s'))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)



def _is_locked(version_dir: str) -> bool:
    """Check if a version directory is locked (released)."""
    return os.path.exists(os.path.join(version_dir, '.locked'))


def _next_dev_version(base_dir: str, from_version: str) -> str:
    """Compute next dev version name. e.g., v1.0.0 → v1.0.3-dev
    Skips versions that already exist (both released and dev)."""
    m = re.match(r'v(\d+)\.(\d+)\.(\d+)', from_version)
    if not m:
        return f"{from_version}-dev"
    major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
    while True:
        patch += 1
        candidate = f"v{major}.{minor}.{patch}-dev"
        promoted = f"v{major}.{minor}.{patch}"
        # Skip if either dev or promoted version exists
        if not os.path.exists(os.path.join(base_dir, candidate)) and \
           not os.path.exists(os.path.join(base_dir, promoted)):
            return candidate


def _find_dev_versions(core_dir: str) -> list:
    """Find all -dev version directories across the codebase."""
    devs = []
    for root, dirs, files in os.walk(core_dir):
        # Skip deep nesting (max 6 levels from core)
        depth = root.replace(core_dir, '').count(os.sep)
        if depth > 6:
            dirs.clear()
            continue
        for d in dirs:
            if d.endswith('-dev'):
                full = os.path.join(root, d)
                rel = os.path.relpath(full, core_dir)
                component = os.path.dirname(rel)
                devs.append({
                    'component': component,
                    'version': d,
                    'path': full,
                    'rel_path': rel,
                })
        # Don't recurse into version dirs
        dirs[:] = [d for d in dirs if not re.match(r'v\d+', d) and d != 'current'
                   and not d.startswith('.')]
    return devs


# ═══════════════════════════════════════════════════════════════════════════════
# COMMANDS
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_start(args: argparse.Namespace) -> int:
    """Start development: create a writable -dev copy from a released version."""
    core_dir = get_cbflow_core_dir()
    component = args.component
    from_version = args.from_version

    comp_dir = os.path.join(core_dir, component)
    if not os.path.isdir(comp_dir):
        logger.error(f"Component directory not found: {component}")
        return 1

    from_path = os.path.join(comp_dir, from_version)
    if not os.path.isdir(from_path):
        logger.error(f"Version {from_version} not found in {component}")
        return 1

    # Compute dev version name
    dev_version = _next_dev_version(comp_dir, from_version)
    dev_path = os.path.join(comp_dir, dev_version)

    logger.info("")
    logger.info("═" * 60)
    logger.info("  Starting Development")
    logger.info("═" * 60)
    logger.info(f"  Component:    {component}")
    logger.info(f"  Base version: {from_version}" +
                (" (LOCKED)" if _is_locked(from_path) else " (WARNING: not locked)"))
    logger.info(f"  Dev version:  {dev_version}")
    logger.info("")

    try:
        shutil.copytree(from_path, dev_path)

        # Remove .locked marker from dev copy and restore write permissions
        locked_marker = os.path.join(dev_path, '.locked')
        if os.path.exists(locked_marker):
            os.chmod(locked_marker, 0o644)
            os.remove(locked_marker)

        # Restore write permissions on all files
        for root, dirs, files in os.walk(dev_path):
            for f in files:
                os.chmod(os.path.join(root, f), 0o644)
            for d in dirs:
                os.chmod(os.path.join(root, d), 0o755)
        os.chmod(dev_path, 0o755)

        # Write dev metadata
        meta_file = os.path.join(dev_path, '.dev_info')
        with open(meta_file, 'w') as f:
            f.write(f"base_version: {from_version}\n")
            f.write(f"created: {datetime.now().isoformat()}\n")
            f.write(f"user: {os.environ.get('USER', 'unknown')}\n")
            f.write(f"component: {component}\n")

        logger.info(f"  Created: {component}/{dev_version}")
        logger.info(f"  Edit files in: {dev_path}")
        logger.info("")
        logger.info("  When done:")
        logger.info(f"    cbflow flow dev promote --component {component}")
        logger.info("")

        return 0

    except Exception as e:
        logger.error(f"Failed to create dev version: {e}")
        if os.path.exists(dev_path):
            shutil.rmtree(dev_path)
        return 1


def cmd_status(args: argparse.Namespace) -> int:
    """Show all active development versions."""
    core_dir = get_cbflow_core_dir()
    devs = _find_dev_versions(core_dir)

    logger.info("")
    logger.info("═" * 60)
    logger.info("  Development Versions")
    logger.info("═" * 60)
    logger.info("")

    if not devs:
        logger.info("  No active development versions found.")
        logger.info("")
        logger.info("  Start development with:")
        logger.info("    cbflow flow dev start --component <path> --from <version>")
        logger.info("")
        return 0

    for dev in devs:
        # Read metadata
        meta_file = os.path.join(dev['path'], '.dev_info')
        base = '?'
        user = '?'
        created = '?'
        if os.path.exists(meta_file):
            with open(meta_file) as f:
                for line in f:
                    if line.startswith('base_version:'):
                        base = line.split(':', 1)[1].strip()
                    elif line.startswith('user:'):
                        user = line.split(':', 1)[1].strip()
                    elif line.startswith('created:'):
                        created = line.split(':', 1)[1].strip()[:10]

        # Count modified files
        file_count = sum(1 for _, _, fs in os.walk(dev['path']) for _ in fs)

        logger.info(f"  {dev['component']}/{dev['version']}")
        logger.info(f"    Base: {base}  |  User: {user}  |  Created: {created}  |  Files: {file_count}")

    logger.info("")
    logger.info(f"  Total: {len(devs)} dev version(s)")
    logger.info("")
    return 0


def cmd_diff(args: argparse.Namespace) -> int:
    """Show diff between dev version and its base."""
    core_dir = get_cbflow_core_dir()
    component = args.component
    comp_dir = os.path.join(core_dir, component)

    # Find the -dev version
    dev_version = None
    for d in sorted(os.listdir(comp_dir)):
        if d.endswith('-dev') and os.path.isdir(os.path.join(comp_dir, d)):
            dev_version = d
    if not dev_version:
        logger.error(f"No dev version found in {component}")
        return 1

    dev_path = os.path.join(comp_dir, dev_version)

    # Read base version from metadata
    base_version = None
    meta_file = os.path.join(dev_path, '.dev_info')
    if os.path.exists(meta_file):
        with open(meta_file) as f:
            for line in f:
                if line.startswith('base_version:'):
                    base_version = line.split(':', 1)[1].strip()
    if not base_version:
        logger.error("Cannot determine base version (no .dev_info)")
        return 1

    base_path = os.path.join(comp_dir, base_version)
    if not os.path.isdir(base_path):
        logger.error(f"Base version {base_version} not found")
        return 1

    logger.info("")
    logger.info(f"  Diff: {component}/{base_version} → {dev_version}")
    logger.info("═" * 60)

    # Compare file trees
    import filecmp
    dcmp = filecmp.dircmp(base_path, dev_path)

    def report_diff(dcmp, prefix=''):
        changed = []
        for f in sorted(dcmp.diff_files):
            if f in ('.locked', '.dev_info'):
                continue
            changed.append(f"  MODIFIED: {prefix}{f}")
        for f in sorted(dcmp.right_only):
            if f in ('.dev_info',):
                continue
            changed.append(f"  ADDED:    {prefix}{f}")
        for f in sorted(dcmp.left_only):
            if f in ('.locked',):
                continue
            changed.append(f"  REMOVED:  {prefix}{f}")
        for sub_name, sub_dcmp in dcmp.subdirs.items():
            changed.extend(report_diff(sub_dcmp, prefix=f"{sub_name}/"))
        return changed

    changes = report_diff(dcmp)
    if changes:
        for c in changes:
            logger.info(c)
        logger.info("")
        logger.info(f"  {len(changes)} file(s) changed")
    else:
        logger.info("  No differences found")
    logger.info("")
    return 0


def cmd_promote(args: argparse.Namespace) -> int:
    """Promote dev version: rename v1.0.1-dev → v1.0.1 (ready for release)."""
    core_dir = get_cbflow_core_dir()
    component = args.component
    comp_dir = os.path.join(core_dir, component)

    # Find the -dev version
    dev_version = None
    for d in sorted(os.listdir(comp_dir)):
        if d.endswith('-dev') and os.path.isdir(os.path.join(comp_dir, d)):
            dev_version = d
    if not dev_version:
        logger.error(f"No dev version found in {component}")
        return 1

    dev_path = os.path.join(comp_dir, dev_version)
    promoted_version = dev_version.replace('-dev', '')
    promoted_path = os.path.join(comp_dir, promoted_version)

    if os.path.exists(promoted_path):
        logger.error(f"Target version {promoted_version} already exists in {component}")
        return 1

    logger.info("")
    logger.info("═" * 60)
    logger.info("  Promoting Dev Version")
    logger.info("═" * 60)
    logger.info(f"  Component: {component}")
    logger.info(f"  From:      {dev_version}")
    logger.info(f"  To:        {promoted_version}")
    logger.info("")

    try:
        # Remove dev metadata
        meta_file = os.path.join(dev_path, '.dev_info')
        if os.path.exists(meta_file):
            os.remove(meta_file)

        # Rename directory
        os.rename(dev_path, promoted_path)

        logger.info(f"  Promoted: {component}/{promoted_version}")
        logger.info("")
        logger.info("  Next steps:")
        logger.info(f"    1. Set as current: cbflow flow version set-current --dir {component} --version {promoted_version}")
        logger.info(f"    2. Release:        cbflow flow release create --type patch --desc 'Description'")
        logger.info("       (This will lock {promoted_version} permanently)")
        logger.info("")
        return 0

    except Exception as e:
        logger.error(f"Failed to promote: {e}")
        return 1


def cmd_sandbox_create(args: argparse.Namespace) -> int:
    """Create a local development sandbox."""
    base_path = args.base or get_cbflow_core_dir()
    sandbox_dir = args.dir or os.path.join(os.path.expanduser('~'), 'cbflow_dev')

    if os.path.exists(sandbox_dir):
        logger.error(f"Sandbox already exists: {sandbox_dir}")
        logger.info(f"Remove it first: rm -rf {sandbox_dir}")
        return 1

    logger.info("")
    logger.info("═" * 60)
    logger.info("  Creating Local Sandbox")
    logger.info("═" * 60)
    logger.info(f"  Base:    {base_path}")
    logger.info(f"  Sandbox: {sandbox_dir}")
    logger.info("")

    os.makedirs(sandbox_dir, exist_ok=True)

    # Find current release
    current_release = 'v1.0.0'
    releases_dir = os.path.join(base_path, 'releases')
    current_link = os.path.join(releases_dir, 'current')
    if os.path.islink(current_link):
        current_release = os.readlink(current_link)

    # Write sandbox metadata
    meta = {
        'base_path': os.path.abspath(base_path),
        'base_release': current_release,
        'created': datetime.now().isoformat(),
        'user': os.environ.get('USER', 'unknown'),
        'components': {}
    }

    meta_file = os.path.join(sandbox_dir, '.sandbox.json')
    with open(meta_file, 'w') as f:
        json.dump(meta, f, indent=2)

    logger.info(f"  Sandbox created: {sandbox_dir}")
    logger.info(f"  Base release:    {current_release}")
    logger.info("")
    logger.info("  Add components to develop:")
    logger.info(f"    cbflow flow dev start --component config/flow --from {current_release}")
    logger.info("")
    logger.info("  Test with sandbox:")
    logger.info(f"    export CBFLOW_DEV_DIR={sandbox_dir}")
    logger.info("    cbflow run all")
    logger.info("")
    return 0


def cmd_sandbox_push(args: argparse.Namespace) -> int:
    """Push local sandbox changes to central PD area."""
    sandbox_dir = args.dir or os.path.join(os.path.expanduser('~'), 'cbflow_dev')

    meta_file = os.path.join(sandbox_dir, '.sandbox.json')
    if not os.path.exists(meta_file):
        logger.error(f"Not a sandbox: {sandbox_dir} (no .sandbox.json)")
        return 1

    with open(meta_file) as f:
        meta = json.load(f)

    base_path = meta.get('base_path', '')
    if not os.path.isdir(base_path):
        logger.error(f"Central PD area not found: {base_path}")
        return 1

    logger.info("")
    logger.info("═" * 60)
    logger.info("  Pushing Sandbox to Central")
    logger.info("═" * 60)
    logger.info(f"  Sandbox: {sandbox_dir}")
    logger.info(f"  Central: {base_path}")
    logger.info("")

    pushed = 0
    for component, info in meta.get('components', {}).items():
        dev_version = info.get('dev', '')
        if not dev_version:
            continue
        src = os.path.join(sandbox_dir, component, dev_version)
        dst = os.path.join(base_path, component, dev_version)
        if os.path.isdir(src):
            if os.path.exists(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
            logger.info(f"  Pushed: {component}/{dev_version}")
            pushed += 1

    logger.info("")
    logger.info(f"  {pushed} component(s) pushed to central")
    logger.info("")
    return 0


# ═══════════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSER
# ═══════════════════════════════════════════════════════════════════════════════

def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='CBFlow Development Workflow')
    subparsers = parser.add_subparsers(dest='command', help='Dev commands')

    # start
    p = subparsers.add_parser('start', help='Start dev version from released base')
    p.add_argument('--component', required=True, help='Component path (e.g., config/flow)')
    p.add_argument('--from', dest='from_version', required=True, help='Base version (e.g., v1.0.0)')

    # status
    subparsers.add_parser('status', help='Show all active dev versions')

    # diff
    p = subparsers.add_parser('diff', help='Diff dev version against base')
    p.add_argument('--component', required=True, help='Component path')

    # promote
    p = subparsers.add_parser('promote', help='Promote dev version (remove -dev suffix)')
    p.add_argument('--component', required=True, help='Component path')

    # sandbox create
    p = subparsers.add_parser('sandbox-create', help='Create local development sandbox')
    p.add_argument('--base', help='Central PD directory (default: FLOW_DIR)')
    p.add_argument('--dir', help='Sandbox directory (default: ~/cbflow_dev)')

    # sandbox push
    p = subparsers.add_parser('sandbox-push', help='Push sandbox changes to central')
    p.add_argument('--dir', help='Sandbox directory (default: ~/cbflow_dev)')

    return parser


def main():
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    commands = {
        'start': cmd_start,
        'status': cmd_status,
        'diff': cmd_diff,
        'promote': cmd_promote,
        'sandbox-create': cmd_sandbox_create,
        'sandbox-push': cmd_sandbox_push,
    }

    cmd_func = commands.get(args.command)
    if cmd_func:
        return cmd_func(args)
    else:
        parser.print_help()
        return 1


if __name__ == '__main__':
    sys.exit(main() or 0)
