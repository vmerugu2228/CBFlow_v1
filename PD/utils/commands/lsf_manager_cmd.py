#!/usr/bin/env python3
"""
CBFlow LSF Manager — Manage LSF queue configuration and flow-stage mappings.

Commands:
  show       — Display current LSF config (queues, mappings)
  validate   — Check LSF config consistency
  map        — Show stage-to-queue mappings for a flow

All data comes from: config/flow/<version>/lsf_config.tcl
"""

import argparse
import os
import re
import sys
from collections import OrderedDict

from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.lsf_manager')


def get_cbflow_core_dir() -> str:
    if 'FLOW_DIR' in os.environ:
        return os.environ['FLOW_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


def _get_lsf_config_path() -> str:
    core_dir = get_cbflow_core_dir()
    version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    return os.path.join(core_dir, 'config', 'flow', version, 'lsf_config.tcl')


class LsfConfigParser:
    """Parse lsf_config.tcl to extract queue definitions and flow mappings."""

    def __init__(self, config_path: str):
        self.config_path = config_path
        self.queues = OrderedDict()
        self.flow_mappings = {}
        self.settings = {}

    def parse(self) -> bool:
        if not os.path.exists(self.config_path):
            logger.error(f"LSF config not found: {self.config_path}")
            return False

        with open(self.config_path, 'r') as f:
            content = f.read()

        # Parse array set lsf { ... }
        # Extract key-value pairs from the lsf array
        pattern = r'(\w[\w,]+)\s+"([^"]*)"'
        for m in re.finditer(pattern, content):
            key = m.group(1)
            val = m.group(2)

            if key.startswith('queue_types,'):
                parts = key.split(',')
                if len(parts) >= 3:
                    queue_name = parts[1]
                    prop = parts[2]
                    if queue_name not in self.queues:
                        self.queues[queue_name] = {}
                    self.queues[queue_name][prop] = val

            elif key.startswith('flow_mapping,'):
                parts = key.split(',')
                if len(parts) >= 3:
                    flow = parts[1]
                    stage = parts[2]
                    if flow not in self.flow_mappings:
                        self.flow_mappings[flow] = {}
                    self.flow_mappings[flow][stage] = val

            else:
                self.settings[key] = val

        # Parse list values (available_queues, etc.)
        list_pattern = r'(\w+)\s+\{([^}]*)\}'
        for m in re.finditer(list_pattern, content):
            key = m.group(1)
            val = m.group(2).strip()
            if key not in self.settings:
                self.settings[key] = val

        return True

    def get_queue_for_stage(self, flow_type: str, stage: str) -> str:
        """Get queue for a flow/stage, stripping numeric suffix."""
        flow_map = self.flow_mappings.get(flow_type, {})
        # Try exact match first, then strip suffix
        if stage in flow_map:
            return flow_map[stage]
        base = re.sub(r'\d+$', '', stage)
        if base in flow_map:
            return flow_map[base]
        return self.settings.get('default_queue', 'M')


def cmd_show(args: argparse.Namespace) -> int:
    """Display current LSF configuration."""
    config_path = _get_lsf_config_path()
    parser = LsfConfigParser(config_path)
    if not parser.parse():
        return 1

    logger.info("")
    logger.info("=" * 70)
    logger.info("  LSF Configuration")
    logger.info(f"  Source: {config_path}")
    logger.info("=" * 70)
    logger.info("")

    # Queue definitions
    logger.info("  Queue Definitions:")
    logger.info("  " + "-" * 66)
    logger.info(f"  {'Queue':<8} {'Memory':<10} {'CPU':<6} {'Time':<8} {'Cost':<6} {'Description'}")
    logger.info("  " + "-" * 66)
    for qname, qinfo in parser.queues.items():
        mem = qinfo.get('memory', '?')
        cpu = qinfo.get('cpu', '?')
        time = qinfo.get('runtime_limit', '?')
        cost = qinfo.get('cost_factor', '?')
        desc = qinfo.get('description', '')[:40]
        logger.info(f"  {qname:<8} {mem:<10} {cpu:<6} {time:<8} {cost:<6} {desc}")
    logger.info("")

    # Settings
    default_q = parser.settings.get('default_queue', 'M')
    strategy = parser.settings.get('selection_strategy', 'static')
    logger.info(f"  Default Queue:       {default_q}")
    logger.info(f"  Selection Strategy:  {strategy}")
    logger.info("")

    # Flow mappings summary
    logger.info("  Flow-Stage Mappings:")
    logger.info("  " + "-" * 66)
    for flow in sorted(parser.flow_mappings.keys()):
        stages = parser.flow_mappings[flow]
        # Deduplicate (config has both 'inputs' and 'inputs1')
        unique = {}
        for stage, queue in stages.items():
            base = re.sub(r'\d+$', '', stage)
            unique[base] = queue
        stage_list = ', '.join(f"{s}={q}" for s, q in sorted(unique.items()))
        logger.info(f"  {flow:<12} {stage_list}")
    logger.info("")
    logger.info("=" * 70)

    return 0


def cmd_map(args: argparse.Namespace) -> int:
    """Show stage-to-queue mappings for a specific flow."""
    flow_type = getattr(args, 'flow', '').upper()
    if not flow_type:
        logger.error("  --flow is required")
        return 1

    config_path = _get_lsf_config_path()
    parser = LsfConfigParser(config_path)
    if not parser.parse():
        return 1

    # Get stages from flow config
    from tcl_config_parser import get_flow_stages
    stages = get_flow_stages(flow_type)
    if not stages:
        logger.error(f"  Unknown flow type: {flow_type}")
        return 1

    logger.info("")
    logger.info(f"  LSF Queue Mapping: {flow_type}")
    logger.info("  " + "-" * 55)
    logger.info(f"  {'Stage':<25} {'Queue':<8} {'Memory':<10} {'CPU':<6} {'Time'}")
    logger.info("  " + "-" * 55)
    for stage in stages:
        queue = parser.get_queue_for_stage(flow_type, stage)
        qinfo = parser.queues.get(queue, {})
        mem = qinfo.get('memory', '?')
        cpu = qinfo.get('cpu', '?')
        time = qinfo.get('runtime_limit', '?')
        logger.info(f"  {stage:<25} {queue:<8} {mem:<10} {cpu:<6} {time}")
    logger.info("")

    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    """Validate LSF configuration consistency."""
    config_path = _get_lsf_config_path()
    parser = LsfConfigParser(config_path)
    if not parser.parse():
        return 1

    errors = []
    warnings = []

    # Check all flow mappings reference valid queues
    valid_queues = set(parser.queues.keys())
    for flow, stages in parser.flow_mappings.items():
        for stage, queue in stages.items():
            if queue not in valid_queues:
                errors.append(f"Flow {flow}, stage {stage}: queue '{queue}' not defined")

    # Check default queue exists
    default_q = parser.settings.get('default_queue', '')
    if default_q and default_q not in valid_queues:
        errors.append(f"Default queue '{default_q}' not defined")

    # Check all flows have mappings
    from tcl_config_parser import get_flow_types
    for flow in get_flow_types():
        if flow not in parser.flow_mappings:
            warnings.append(f"Flow '{flow}' has no LSF queue mappings")

    logger.info("")
    logger.info("  LSF Configuration Validation")
    logger.info("  " + "-" * 50)
    if errors:
        for e in errors:
            logger.error(f"  ERROR: {e}")
    if warnings:
        for w in warnings:
            logger.warning(f"  WARNING: {w}")
    if not errors and not warnings:
        logger.info("  All checks passed")
    logger.info("")

    return 1 if errors else 0


# ── CLI ───────────────────────────────────────────────────────────────────────

def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='cbflow flow lsf-manager',
        description='CBFlow LSF Manager — queue configuration and flow-stage mappings')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    subparsers.add_parser('show', help='Display LSF configuration')

    map_parser = subparsers.add_parser('map', help='Show stage-to-queue mappings for a flow')
    map_parser.add_argument('--flow', '-t', required=True, help='Flow type')

    subparsers.add_parser('validate', help='Validate LSF configuration')

    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return 0
    commands = {
        'show': cmd_show,
        'map': cmd_map,
        'validate': cmd_validate,
    }
    if args.command in commands:
        return commands[args.command](args)
    parser.print_help()
    return 1


if __name__ == '__main__':
    sys.exit(main())
