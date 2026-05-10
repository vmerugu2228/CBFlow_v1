#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Config Command Handler
# Description: Handles configuration management (flow, node, tech management)
# Usage: cbflow config <subcommand> [options]
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import os
import sys
import subprocess
import logging

# Configure unified logging
from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.config')


def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory from environment or determine from script location."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


def run_tcl_config_manager(action: str) -> int:
    """Run the TCL interactive config manager."""
    core_dir = get_cbflow_core_dir()
    tcl_script = os.path.join(core_dir, 'utils', 'utilities', os.environ.get('UTILITIES_VERSION', 'v1.0.0'), 'interactive_config_manager.tcl')

    if not os.path.exists(tcl_script):
        logger.error(f"Config manager not found: {tcl_script}")
        return 1

    # Set environment variables
    env = os.environ.copy()
    env['CONFIG_ROOT'] = os.path.join(core_dir, 'config')
    env['SCRIPTS_ROOT'] = os.path.join(core_dir, 'utils')
    env['FLOW_DIR'] = core_dir
    env['UTILITIES_VERSION'] = os.environ.get('UTILITIES_VERSION', 'v1.0.0')

    try:
        result = subprocess.run(['tclsh', tcl_script, action], env=env)
        return result.returncode
    except FileNotFoundError:
        logger.error("tclsh not found. Please install TCL.")
        return 1
    except Exception as e:
        logger.error(f"Config manager failed: {e}")
        return 1


# ─────────────────────────────────────────────────────────────────────────────────
# Config Commands
# ─────────────────────────────────────────────────────────────────────────────────

def cmd_manage_flow(args: argparse.Namespace) -> int:
    """Launch interactive flow management."""
    logger.info("Starting Interactive Flow Management...")
    logger.info("═" * 50)
    return run_tcl_config_manager('manage_flow')


def cmd_manage_node(args: argparse.Namespace) -> int:
    """Launch interactive node management."""
    logger.info("Starting Interactive Node & Subnode Management...")
    logger.info("═" * 50)
    return run_tcl_config_manager('manage_node')


def cmd_manage_tech(args: argparse.Namespace) -> int:
    """Launch interactive technology management."""
    logger.info("Starting Interactive Technology Management...")
    logger.info("═" * 50)
    return run_tcl_config_manager('manage_tech')


def cmd_validate(args: argparse.Namespace) -> int:
    """Validate CBFlow configuration."""
    logger.info("Starting CBFlow Validation...")
    logger.info("═" * 50)
    return run_tcl_config_manager('validate_flow')


def cmd_status(args: argparse.Namespace) -> int:
    """Show configuration status."""
    core_dir = get_cbflow_core_dir()
    config_dir = os.path.join(core_dir, 'config')

    logger.info("CBFlow Configuration Status")
    logger.info("═" * 50)
    logger.info(f"Core Directory:   {core_dir}")
    logger.info(f"Config Directory: {config_dir}")
    logger.info("")

    # Check key config directories
    config_subdirs = ['flow', 'project', 'tech', 'setup', 'exit']

    logger.info("  Configuration Directories:")
    logger.info("  " + "─" * 40)
    for subdir in config_subdirs:
        path = os.path.join(config_dir, subdir)
        exists = os.path.exists(path)
        status = "[PASS]" if exists else "[FAIL]"
        logger.info(f"  {status} {subdir:<15} {'Found' if exists else 'Missing'}")

    # List flow versions
    flow_dir = os.path.join(config_dir, 'flow')
    if os.path.exists(flow_dir):
        versions = [d for d in os.listdir(flow_dir)
                   if os.path.isdir(os.path.join(flow_dir, d)) and d.startswith('v')]
        if versions:
            logger.info("")
            logger.info(f"Flow Versions: {', '.join(sorted(versions))}")

    # Check master_projects.json
    projects_file = os.path.join(config_dir, 'master_projects.json')
    if os.path.exists(projects_file):
        import json
        with open(projects_file, 'r') as f:
            projects = json.load(f)
        project_count = len(projects.get('projects', {}))
        active = projects.get('active_project', 'None')
        logger.info("")
        logger.info(f"Projects:       {project_count}")
        logger.info(f"Active Project: {active}")

    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow config',
        description='CBFlow - Configuration Management',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow config manage-flow
  cbflow config manage-node
  cbflow config manage-tech
  cbflow config validate
  cbflow config status
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # manage-flow command
    subparsers.add_parser('manage-flow', help='Interactive flow management')

    # manage-node command
    subparsers.add_parser('manage-node', help='Interactive node management')

    # manage-tech command
    subparsers.add_parser('manage-tech', help='Interactive technology management')

    # validate command
    subparsers.add_parser('validate', help='Validate CBFlow configuration')

    # status command
    subparsers.add_parser('status', help='Show configuration status')

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
        'manage-flow': cmd_manage_flow,
        'manage-node': cmd_manage_node,
        'manage-tech': cmd_manage_tech,
        'validate': cmd_validate,
        'status': cmd_status,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
