#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Flow Command Handler
# Description: Handles flow types, stages, and node information
# Usage: cbflow flow <subcommand> [options]
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import os
import sys
import json
import logging

# Configure unified logging
from logging_config import configure_logging, get_logger

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir

logger = configure_logging('cbflow.flow')

# Version
from core.paths import CBFLOW_VERSION as VERSION

# Flow type definitions - loaded from existing Tcl config files
def _build_flow_types_dict():
    """Build FLOW_TYPES dict from Tcl configs (flow_config.tcl + node_configs/)."""
    from tcl_config_parser import get_all_flow_info
    result = {}
    for flow_type, info in get_all_flow_info().items():
        tool = info.get('tool', {})
        result[flow_type] = {
            'description': info.get('description', flow_type),
            'vendor': tool.get('vendor', ''),
            'tool': tool.get('name', ''),
            'shell': tool.get('name', ''),
            'nodes': info.get('stages', []),
        }
    return result

FLOW_TYPES = _build_flow_types_dict()



def cmd_types(args: argparse.Namespace) -> int:
    """List all flow types."""
    logger.info("")
    logger.info("═" * 90)
    logger.info("  Available Flow Types")
    logger.info("═" * 90)
    logger.info("")
    logger.info(f"  {'Flow':<8} {'Description':<42} {'Vendor':<10} {'Tool':<18} {'Shell':<12}")
    logger.info("  " + "─" * 86)

    for flow_type, info in FLOW_TYPES.items():
        logger.info(f"  {flow_type:<8} {info['description']:<42} {info['vendor']:<10} {info['tool']:<18} {info['shell']:<12}")

    logger.info("")
    logger.info(f"  Total: {len(FLOW_TYPES)} flow types")
    logger.info("")
    return 0


def cmd_info(args: argparse.Namespace) -> int:
    """Show information about a specific flow type."""
    flow = args.flow.upper()

    if flow not in FLOW_TYPES:
        logger.error(f"Unknown flow type: {flow}")
        logger.info(f"Valid flow types: {', '.join(FLOW_TYPES.keys())}")
        return 1

    info = FLOW_TYPES[flow]

    logger.info("")
    logger.info("═" * 60)
    logger.info(f"  Flow Type: {flow}")
    logger.info("═" * 60)
    logger.info("")
    logger.info(f"  Description:   {info['description']}")
    logger.info(f"  Vendor:        {info['vendor']}")
    logger.info(f"  Tool:          {info['tool']}")
    logger.info(f"  Shell:         {info['shell']}")
    logger.info(f"  Nodes:         {' -> '.join(info['nodes'])}")
    logger.info("")

    return 0


def cmd_stages(args: argparse.Namespace) -> int:
    """Show stages for a flow type."""
    flow = args.flow.upper()

    if flow not in FLOW_TYPES:
        logger.error(f"Unknown flow type: {flow}")
        return 1

    info = FLOW_TYPES[flow]
    logger.info(f"Stages for {flow} ({info['description']}):")
    logger.info("")
    for i, node in enumerate(info['nodes'], 1):
        logger.info(f"  {i}. {node}")

    return 0


def cmd_nodes(args: argparse.Namespace) -> int:
    """Show nodes for a flow type."""
    return cmd_stages(args)


def cmd_check(args: argparse.Namespace) -> int:
    """Check CBFlow installation."""
    core_dir = get_cbflow_core_dir()

    logger.info("")
    logger.info("  CBFlow Installation Check")
    logger.info("  " + "═" * 57)
    logger.info("")
    logger.info(f"  CBFLOW_CORE_DIR: {core_dir}")
    logger.info("")

    # Check directories (updated for new structure)
    dirs_to_check = [
        'bin',
        'cmds',
        'config',
        'config/flow',
        'config/setup',
        'config/project',
        'config/tech',
        'utils',
        'docs',
    ]

    logger.info(f"  {'Directory':<20} Status")
    logger.info("  " + "─" * 57)

    all_ok = True
    passed = 0
    total = 0
    for d in dirs_to_check:
        path = os.path.join(core_dir, d)
        exists = os.path.exists(path)
        total += 1
        if exists:
            passed += 1
            logger.info(f"  [PASS] {d + '/':<18} Found")
        else:
            all_ok = False
            logger.info(f"  [FAIL] {d + '/':<18} Missing")

    # Check config files
    config_files = [
        'config/flow/v1.0.0/flow_config.tcl',
        'config/project/phoenix/v1.0.0/phoenix_config.tcl',
    ]

    logger.info("")
    logger.info(f"  {'Config File':<20} Status")
    logger.info("  " + "─" * 57)

    for f in config_files:
        path = os.path.join(core_dir, f)
        exists = os.path.exists(path)
        total += 1
        if exists:
            passed += 1
            logger.info(f"  [PASS] {f}")
        else:
            all_ok = False
            logger.info(f"  [FAIL] {f}")

    logger.info("")
    logger.info(f"  Result: {passed}/{total} checks passed")
    logger.info("")

    if not all_ok:
        logger.warning("  Some checks failed - installation may be incomplete")
        logger.info("")

    return 0 if all_ok else 1


def cmd_version(args: argparse.Namespace) -> int:
    """Show version information."""
    core_dir = get_cbflow_core_dir()

    logger.info(f"CBFlow v{VERSION}")
    logger.info(f"  Installation: {core_dir}")
    logger.info(f"  Flow types:   {len(FLOW_TYPES)}")

    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow',
        description='CBFlow - Flow Types, Stages, and Node Information',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow types
  cbflow flow info --flow PNR
  cbflow flow stages --flow PNR
  cbflow flow nodes --flow SYNTH
  cbflow flow check
  cbflow flow version
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # types command
    subparsers.add_parser('types', help='List all flow types')

    # info command
    info_parser = subparsers.add_parser('info', help='Show flow type info')
    info_parser.add_argument('--flow', '-f', required=True, help='Flow type')

    # stages command
    stages_parser = subparsers.add_parser('stages', help='Show flow stages')
    stages_parser.add_argument('--flow', '-f', required=True, help='Flow type')

    # nodes command
    nodes_parser = subparsers.add_parser('nodes', help='Show flow nodes')
    nodes_parser.add_argument('--flow', '-f', required=True, help='Flow type')

    # check command
    subparsers.add_parser('check', help='Check CBFlow installation')

    # version command
    subparsers.add_parser('version', help='Show version information')

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
        'types': cmd_types,
        'info': cmd_info,
        'stages': cmd_stages,
        'nodes': cmd_nodes,
        'check': cmd_check,
        'version': cmd_version,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
