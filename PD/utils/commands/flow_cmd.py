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
    """Check CBFlow installation and flow integrity."""
    import re as _re
    import glob as _glob

    core_dir = get_cbflow_core_dir()

    logger.info("")
    logger.info("  CBFlow Health Check")
    logger.info("  " + "═" * 57)
    logger.info("")
    logger.info(f"  CBFLOW_CORE_DIR: {core_dir}")
    logger.info("")

    all_ok = True
    passed = 0
    failed = 0
    warnings = 0
    total = 0

    # ── 1. Directory Structure ──────────────────────────────────────────
    logger.info("  1. Directory Structure")
    logger.info("  " + "─" * 57)

    dirs_to_check = [
        'bin', 'cmds', 'config', 'config/flow', 'config/setup',
        'config/project', 'config/tech', 'utils', 'docs',
    ]

    for d in dirs_to_check:
        path = os.path.join(core_dir, d)
        total += 1
        if os.path.exists(path):
            passed += 1
        else:
            all_ok = False
            failed += 1
            logger.error(f"  [FAIL] {d}/ — missing")

    logger.info(f"  [PASS] {len(dirs_to_check)} directories checked")

    # ── 2. Config Files ─────────────────────────────────────────────────
    logger.info("")
    logger.info("  2. Config Files")
    logger.info("  " + "─" * 57)

    config_files = [
        'config/flow/v1.0.0/flow_config.tcl',
        'config/flow/v1.0.0/release_config.tcl',
        'config/flow/v1.0.0/lsf_config.tcl',
    ]
    # Add all node configs
    nc_dir = os.path.join(core_dir, 'config', 'flow', 'v1.0.0', 'node_configs')
    if os.path.isdir(nc_dir):
        for f in sorted(os.listdir(nc_dir)):
            if f.endswith('_config.tcl'):
                config_files.append(f'config/flow/v1.0.0/node_configs/{f}')

    cfg_pass = 0
    for f in config_files:
        path = os.path.join(core_dir, f)
        total += 1
        if os.path.exists(path):
            passed += 1
            cfg_pass += 1
        else:
            all_ok = False
            failed += 1
            logger.error(f"  [FAIL] {f} — missing")

    logger.info(f"  [PASS] {cfg_pass}/{len(config_files)} config files found")

    # ── 3. Handler Integrity ────────────────────────────────────────────
    logger.info("")
    logger.info("  3. Handler → Command File Integrity")
    logger.info("  " + "─" * 57)

    cmds_dir = os.path.join(core_dir, 'cmds')
    broken_refs = []
    duplicate_handlers = []
    handler_count = 0

    for root, dirs, files in os.walk(cmds_dir):
        if 'current' in root:
            continue
        for f in files:
            if not f.endswith('_subnode_handler.tcl'):
                continue
            handler_count += 1
            fpath = os.path.join(root, f)

            # Check for duplicate numbered handlers
            if _re.match(r'.*\d+_subnode_handler\.tcl$', f):
                base = _re.sub(r'\d+_subnode_handler', '_subnode_handler', f)
                base_path = os.path.join(root, base)
                if os.path.exists(base_path):
                    duplicate_handlers.append(fpath)

            # Check cmd_file reference
            try:
                with open(fpath) as fh:
                    content = fh.read()
            except Exception:
                continue

            m = _re.search(r'set cmd_file .*\$_tool_ver/([^"]+)"', content)
            if not m:
                continue  # inputs handlers — no cmd_file by design

            ref_file = m.group(1)
            ref_path = os.path.join(root, ref_file)
            total += 1
            if os.path.exists(ref_path):
                passed += 1
            else:
                all_ok = False
                failed += 1
                rel_handler = os.path.relpath(fpath, core_dir)
                broken_refs.append((rel_handler, ref_file))

    if broken_refs:
        for h, ref in broken_refs:
            logger.error(f"  [FAIL] {h}")
            logger.error(f"         → {ref} (NOT FOUND)")
    else:
        logger.info(f"  [PASS] {handler_count} handlers checked — all cmd_file references valid")

    if duplicate_handlers:
        for h in duplicate_handlers:
            rel = os.path.relpath(h, core_dir)
            logger.warning(f"  [WARN] Duplicate handler: {rel}")
            warnings += 1
    else:
        logger.info(f"  [PASS] No duplicate numbered handlers")

    # ── 4. Stage ↔ Handler Coverage ─────────────────────────────────────
    logger.info("")
    logger.info("  4. Stage ↔ Handler Coverage")
    logger.info("  " + "─" * 57)

    node_cfg_dir = os.path.join(core_dir, 'config', 'flow', 'v1.0.0', 'node_configs')
    coverage_issues = []

    if os.path.isdir(node_cfg_dir):
        for cfg_file in sorted(os.listdir(node_cfg_dir)):
            if not cfg_file.endswith('_config.tcl'):
                continue
            # Only check base flow configs (not tool-specific)
            if cfg_file.count('_') > 1:
                continue

            flow_name = cfg_file.replace('_config.tcl', '')
            cfg_path = os.path.join(node_cfg_dir, cfg_file)

            # Parse stages and node_types
            try:
                with open(cfg_path) as fh:
                    content = fh.read()
            except Exception:
                continue

            m = _re.search(r'stages\s+\{([^}]+)\}', content)
            if not m:
                continue
            stages = m.group(1).split()

            # Parse node_types
            node_types = {}
            for nt_m in _re.finditer(r'node_types,(\w+)\s+"(\w+)"', content):
                node_types[nt_m.group(1)] = nt_m.group(2)

            # Check tool-specific configs to find supported tools
            tool_configs = _glob.glob(os.path.join(node_cfg_dir, f'{flow_name}_*_config.tcl'))
            tools = []
            for tc in tool_configs:
                tc_name = os.path.basename(tc)
                tool = tc_name.replace(f'{flow_name}_', '').replace('_config.tcl', '')
                tools.append(tool)

            if not tools:
                # Read supported_tools from config
                st_m = _re.search(r'supported_tools\s+\{([^}]+)\}', content)
                if st_m:
                    tools = st_m.group(1).split()

            # For each tool, check handler exists for each execution stage
            for tool in tools:
                # Determine vendor from tool
                vendor_map = {
                    'fc': 'synopsys', 'pt': 'synopsys', 'formality': 'synopsys',
                    'vc_lp': 'synopsys', 'icv': 'synopsys', 'redhawk': 'synopsys',
                    'power_compiler': 'synopsys', 'icc2': 'synopsys',
                    'genus': 'cadence', 'innovus': 'cadence', 'tempus': 'cadence',
                    'conformal': 'cadence', 'conformal_lp': 'cadence', 'voltus': 'cadence',
                    'calibre': 'mentor',
                }
                vendor = vendor_map.get(tool, 'synopsys')
                handler_dir = os.path.join(cmds_dir, flow_name, vendor, tool, 'v1.0.0')

                if not os.path.isdir(handler_dir):
                    continue

                for stage in stages:
                    node_type = node_types.get(stage, stage.rstrip('0123456789'))
                    # Skip input stages — they use a shared inputs_subnode_handler
                    if node_type == 'inputs':
                        continue
                    handler_file = os.path.join(handler_dir, f'{node_type}_subnode_handler.tcl')
                    total += 1
                    if os.path.exists(handler_file):
                        passed += 1
                    else:
                        coverage_issues.append(f"{flow_name}/{tool}: missing {node_type}_subnode_handler.tcl for stage {stage}")
                        warnings += 1

    if coverage_issues:
        for issue in coverage_issues:
            logger.warning(f"  [WARN] {issue}")
    else:
        logger.info(f"  [PASS] All execution stages have handlers")

    # ── 5. Project Configs ──────────────────────────────────────────────
    logger.info("")
    logger.info("  5. Project Configs")
    logger.info("  " + "─" * 57)

    proj_dir = os.path.join(core_dir, 'config', 'project')
    if os.path.isdir(proj_dir):
        projects = [d for d in os.listdir(proj_dir) if os.path.isdir(os.path.join(proj_dir, d))]
        for proj in sorted(projects):
            proj_cfg = os.path.join(proj_dir, proj, 'v1.0.0', f'{proj}_config.tcl')
            total += 1
            if os.path.exists(proj_cfg):
                passed += 1
                logger.info(f"  [PASS] {proj}")
            else:
                failed += 1
                all_ok = False
                logger.error(f"  [FAIL] {proj} — {proj}_config.tcl missing")

    # ── 6. Tech Configs ─────────────────────────────────────────────────
    logger.info("")
    logger.info("  6. Tech Configs")
    logger.info("  " + "─" * 57)

    tech_dir = os.path.join(core_dir, 'config', 'tech')
    if os.path.isdir(tech_dir):
        techs = [d for d in os.listdir(tech_dir) if os.path.isdir(os.path.join(tech_dir, d))]
        for tech in sorted(techs):
            tech_cfg = os.path.join(tech_dir, tech, 'v1.0.0', 'tech_config.tcl')
            total += 1
            if os.path.exists(tech_cfg):
                passed += 1
                # Check for lib_config files
                lib_cfgs = _glob.glob(os.path.join(tech_dir, tech, 'v1.0.0', 'lib_config_*.tcl'))
                lib_tags = [os.path.basename(f).replace('lib_config_', '').replace('.tcl', '') for f in lib_cfgs]
                tag_str = f" (lib tags: {', '.join(lib_tags)})" if lib_tags else " (no lib_config)"
                logger.info(f"  [PASS] {tech}{tag_str}")
            else:
                failed += 1
                all_ok = False
                logger.error(f"  [FAIL] {tech} — tech_config.tcl missing")

    # ── Summary ─────────────────────────────────────────────────────────
    logger.info("")
    logger.info("  " + "═" * 57)
    logger.info(f"  RESULT: {passed} passed, {failed} failed, {warnings} warnings")
    logger.info("  " + "═" * 57)
    logger.info("")

    if not all_ok:
        logger.error("  HEALTH CHECK FAILED — fix errors above before production use")
    else:
        logger.info("  HEALTH CHECK PASSED")

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
