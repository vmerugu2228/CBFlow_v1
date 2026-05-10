#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Version Command Handler
# Description: Handles version control operations
# Usage: cbflow version <subcommand> [options]
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import logging
import os
import subprocess
import sys

# Configure unified logging
from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.version')


def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory from environment or determine from script location."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


def run_version_manager(args: list) -> int:
    """Run the version manager Python script."""
    core_dir = get_cbflow_core_dir()

    # Use directory-based version manager (no git dependency)
    manager_script = os.path.join(core_dir, 'utils', 'version', 'current', 'flow_version_manager.py')

    if not os.path.exists(manager_script):
        # Fallback to v1.0.0 if current symlink doesn't exist
        manager_script = os.path.join(core_dir, 'utils', 'version', os.environ.get('UTILITIES_VERSION', 'v1.0.0'), 'flow_version_manager.py')

    if not os.path.exists(manager_script):
        logger.error("Version manager not found")
        return 1

    try:
        # Set working directory to core for proper path resolution
        result = subprocess.run(
            ['python3', manager_script] + args,
            cwd=core_dir
        )
        return result.returncode
    except Exception as e:
        logger.error(f"Version manager failed: {e}")
        return 1


# ─────────────────────────────────────────────────────────────────────────────────
# Version Commands
# ─────────────────────────────────────────────────────────────────────────────────

def cmd_list(args: argparse.Namespace) -> int:
    """List versions for a directory."""
    core_dir = get_cbflow_core_dir()

    # List versions for specific directory
    dir_path = os.path.join(core_dir, args.dir)
    if not os.path.exists(dir_path):
        logger.error(f"Directory not found: {args.dir}")
        return 1

    logger.info(f"Versions for: {args.dir}")
    logger.info("═" * 50)

    # Find version directories (vX.Y.Z pattern)
    versions = []
    for item in os.listdir(dir_path):
        item_path = os.path.join(dir_path, item)
        if os.path.isdir(item_path) and item.startswith('v') and item != 'current':
            versions.append(item)

    # Check for current symlink
    current_link = os.path.join(dir_path, 'current')
    current_version = None
    if os.path.islink(current_link):
        current_version = os.readlink(current_link)

    if not versions:
        logger.info("No versions found")
        return 0

    versions.sort()
    for v in versions:
        marker = " <- CURRENT" if v == current_version else ""
        logger.info(f"  {v}{marker}")

    logger.info("")
    logger.info(f"Total: {len(versions)} version(s)")
    return 0


def cmd_create(args: argparse.Namespace) -> int:
    """Create a new version."""
    desc = args.desc if args.desc else f"Version {args.version}"
    cmd_args = ['create_version', args.dir, args.version, desc]

    return run_version_manager(cmd_args)


def cmd_set_current(args: argparse.Namespace) -> int:
    """Set the current version."""
    core_dir = get_cbflow_core_dir()
    dir_path = os.path.join(core_dir, args.dir)
    version_path = os.path.join(dir_path, args.version)
    current_link = os.path.join(dir_path, 'current')

    if not os.path.exists(version_path):
        logger.error(f"Version {args.version} does not exist in {args.dir}")
        return 1

    # Update symlink
    try:
        if os.path.islink(current_link):
            os.unlink(current_link)
        elif os.path.exists(current_link):
            logger.error(f"'current' exists but is not a symlink: {current_link}")
            return 1

        os.symlink(args.version, current_link)
        logger.info(f"Set current version to {args.version} for {args.dir}")
        return 0
    except Exception as e:
        logger.error(f"Failed to update symlink: {e}")
        return 1


def cmd_get_current(args: argparse.Namespace) -> int:
    """Get the current version."""
    core_dir = get_cbflow_core_dir()
    dir_path = os.path.join(core_dir, args.dir)
    current_link = os.path.join(dir_path, 'current')

    if not os.path.exists(dir_path):
        logger.error(f"Directory not found: {args.dir}")
        return 1

    if os.path.islink(current_link):
        current_version = os.readlink(current_link)
        logger.info(f"Current version for {args.dir}: {current_version}")
        return 0
    else:
        logger.info(f"No current version set for {args.dir}")
        return 0


def cmd_diff(args: argparse.Namespace) -> int:
    """Diff two versions."""
    core_dir = get_cbflow_core_dir()
    dir_path = os.path.join(core_dir, args.dir)
    v1_path = os.path.join(dir_path, args.v1)
    v2_path = os.path.join(dir_path, args.v2)

    if not os.path.exists(v1_path):
        logger.error(f"Version {args.v1} not found in {args.dir}")
        return 1
    if not os.path.exists(v2_path):
        logger.error(f"Version {args.v2} not found in {args.dir}")
        return 1

    logger.info(f"Comparing {args.v1} vs {args.v2} in {args.dir}")
    logger.info("═" * 50)

    # Get file lists for both versions
    def get_files(path):
        files = set()
        for root, _, filenames in os.walk(path):
            rel_root = os.path.relpath(root, path)
            for f in filenames:
                if rel_root == '.':
                    files.add(f)
                else:
                    files.add(os.path.join(rel_root, f))
        return files

    v1_files = get_files(v1_path)
    v2_files = get_files(v2_path)

    # Find differences
    only_v1 = v1_files - v2_files
    only_v2 = v2_files - v1_files
    common = v1_files & v2_files

    if only_v1:
        logger.info(f"\nOnly in {args.v1}:")
        for f in sorted(only_v1):
            logger.info(f"  - {f}")

    if only_v2:
        logger.info(f"\nOnly in {args.v2}:")
        for f in sorted(only_v2):
            logger.info(f"  + {f}")

    if not only_v1 and not only_v2:
        logger.info("Both versions have the same files")

    logger.info(f"\nSummary: {len(common)} common, {len(only_v1)} only in {args.v1}, {len(only_v2)} only in {args.v2}")
    return 0


def cmd_copy(args: argparse.Namespace) -> int:
    """Copy an existing version to create a new one."""
    core_dir = get_cbflow_core_dir()
    dir_path = os.path.join(core_dir, args.dir)
    from_path = os.path.join(dir_path, args.from_version)
    to_path = os.path.join(dir_path, args.to_version)

    if not os.path.exists(from_path):
        logger.error(f"Source version {args.from_version} not found in {args.dir}")
        return 1

    if os.path.exists(to_path):
        logger.error(f"Target version {args.to_version} already exists in {args.dir}")
        return 1

    try:
        import shutil
        shutil.copytree(from_path, to_path)
        logger.info(f"Created {args.to_version} from {args.from_version} in {args.dir}")
        logger.info(f"Edit files in: {args.dir}/{args.to_version}/")
        logger.info(f"When ready:    cbflow flow version set-current --dir {args.dir} --version {args.to_version}")
        return 0
    except Exception as e:
        logger.error(f"Failed to copy version: {e}")
        return 1


def cmd_status(args: argparse.Namespace) -> int:
    """Show version control status."""
    core_dir = get_cbflow_core_dir()
    logger.info("CBFlow Version Control Status")
    logger.info("═" * 50)
    logger.info(f"Core Directory: {core_dir}")
    logger.info("")

    # List managed directories using directory-based version manager
    return run_version_manager(['list_managed_directories'])


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow version',
        description='CBFlow - Version Control Operations',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow version list --dir config/flow
  cbflow flow version copy --dir config/flow --from v1.0.0 --to v1.0.2
  cbflow flow version create --dir config --version v2.0.0 --desc "New features"
  cbflow flow version set-current --dir config/flow --version v1.0.2
  cbflow flow version get-current --dir config/flow
  cbflow flow version diff --dir config/flow --v1 v1.0.0 --v2 v1.0.2
  cbflow flow version status
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # list command
    list_parser = subparsers.add_parser('list', help='List versions for a directory')
    list_parser.add_argument('--dir', '-d', required=True, help='Directory to list versions for')

    # create command
    create_cmd_parser = subparsers.add_parser('create', help='Create a new version')
    create_cmd_parser.add_argument('--dir', '-d', required=True, help='Directory')
    create_cmd_parser.add_argument('--version', '-v', required=True, help='Version (e.g., v2.0.0)')
    create_cmd_parser.add_argument('--desc', help='Description')

    # set-current command
    set_parser = subparsers.add_parser('set-current', help='Set current version')
    set_parser.add_argument('--dir', '-d', required=True, help='Directory')
    set_parser.add_argument('--version', '-v', required=True, help='Version')

    # get-current command
    get_parser = subparsers.add_parser('get-current', help='Get current version')
    get_parser.add_argument('--dir', '-d', required=True, help='Directory')

    # copy command
    copy_parser = subparsers.add_parser('copy', help='Copy a version to create a new one')
    copy_parser.add_argument('--dir', '-d', required=True, help='Directory')
    copy_parser.add_argument('--from', dest='from_version', required=True, help='Source version (e.g., v1.0.0)')
    copy_parser.add_argument('--to', dest='to_version', required=True, help='Target version (e.g., v1.0.2)')

    # diff command
    diff_parser = subparsers.add_parser('diff', help='Diff two versions')
    diff_parser.add_argument('--dir', '-d', required=True, help='Directory')
    diff_parser.add_argument('--v1', required=True, help='First version')
    diff_parser.add_argument('--v2', required=True, help='Second version')

    # status command
    subparsers.add_parser('status', help='Show version control status')

    return parser


def main() -> int:
    """Main entry point."""
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    # Command dispatch
    commands = {
        'list': cmd_list,
        'copy': cmd_copy,
        'create': cmd_create,
        'set-current': cmd_set_current,
        'get-current': cmd_get_current,
        'diff': cmd_diff,
        'status': cmd_status,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
