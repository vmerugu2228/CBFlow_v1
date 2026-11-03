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
        # Discipline defaults to empty string, not 'PD'. The old default
        # silently mislabeled DFT/DV flows as PD in any environment where
        # the resolver's flow(discipline,*) map wasn't populated — which
        # was easy to hit from a bare import of flow_cmd. Callers that
        # need a hard answer should route through get_flow_discipline().
        result[flow_type] = {
            'description': info.get('description', flow_type),
            'vendor': tool.get('vendor', ''),
            'tool': tool.get('name', ''),
            'shell': tool.get('name', ''),
            'nodes': info.get('stages', []),
            'discipline': info.get('discipline', ''),
        }
    return result

# FLOW_TYPES is loaded lazily via module `__getattr__` (PEP 562). See
# workspace_cmd.py for the rationale — bare `import flow_cmd` (healthcheck,
# IDE, tests) shouldn't require CBFLOW_CORE_DIR/FLOW_DIR/CONFIG_ROOT env
# vars, only real command execution under cbflow's launcher should.
_FLOW_TYPES_CACHE = None
# Lock around the check-then-set so two threads don't both run
# _build_flow_types_dict() (which spawns tclsh) and overwrite each other.
import threading as _threading
_FLOW_TYPES_LOCK = _threading.Lock()


def _flow_types():
    """Return the cached FLOW_TYPES dict, building it on first access.

    Use this from any function in this module — PEP 562's __getattr__
    fires only on external `module.NAME` access, not on bare `NAME`
    lookups inside the module's own functions, so we need an explicit
    accessor for in-module callers.
    """
    global _FLOW_TYPES_CACHE
    with _FLOW_TYPES_LOCK:
        if _FLOW_TYPES_CACHE is None:
            _FLOW_TYPES_CACHE = _build_flow_types_dict()
        return _FLOW_TYPES_CACHE


def __getattr__(name):
    if name == 'FLOW_TYPES':
        return _flow_types()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")



def cmd_types(args: argparse.Namespace) -> int:
    """List all flow types, grouped by discipline.

    --domain <PD|DFT|DV>  filter to one discipline
    """
    domain_filter = (getattr(args, 'domain', None) or '').upper() or None

    ft = _flow_types()

    from tcl_config_parser import (
        get_disciplines, is_discipline_available, get_flows_by_discipline,
    )
    absent = [d for d in get_disciplines()
              if not is_discipline_available(d)]
    if absent:
        hidden = sum(len(flows) for d, flows in get_flows_by_discipline().items()
                     if d in absent)
        logger.info(f"[INFO] sparse checkout: hiding {hidden} flow(s) "
                    f"from absent discipline(s): {', '.join(absent)}")
    if domain_filter:
        ft = {k: v for k, v in ft.items()
              if v.get('discipline', 'PD').upper() == domain_filter}
        if not ft:
            logger.error(f"No flows found for domain: {domain_filter}")
            logger.info("Known domains: PD, DFT, DV")
            return 1

    # Group by discipline for a cleaner display
    from collections import OrderedDict
    grouped: 'OrderedDict[str, list]' = OrderedDict()
    for flow_type, info in ft.items():
        disc = info.get('discipline', 'PD')
        grouped.setdefault(disc, []).append((flow_type, info))

    logger.info("")
    logger.info("═" * 98)
    title = "  Available Flow Types"
    if domain_filter:
        title += f"  (domain = {domain_filter})"
    logger.info(title)
    logger.info("═" * 98)

    header = f"  {'Flow':<16} {'Description':<42} {'Vendor':<10} {'Tool':<14} {'Shell':<10}"
    for disc, rows in grouped.items():
        logger.info("")
        logger.info(f"  ── {disc} " + "─" * (94 - len(disc)))
        logger.info(header)
        logger.info("  " + "─" * 94)
        for flow_type, info in rows:
            logger.info(f"  {flow_type:<16} {info['description']:<42} "
                        f"{info['vendor']:<10} {info['tool']:<14} {info['shell']:<10}")

    logger.info("")
    if domain_filter:
        logger.info(f"  Total: {len(ft)} flow types in domain {domain_filter}")
    else:
        breakdown = ", ".join(f"{d}={len(rows)}" for d, rows in grouped.items())
        logger.info(f"  Total: {len(ft)} flow types  ({breakdown})")
    logger.info("")
    return 0


def cmd_info(args: argparse.Namespace) -> int:
    """Show information about a specific flow type."""
    flow = args.flow.upper()

    _ft = _flow_types()
    if flow not in _ft:
        logger.error(f"Unknown flow type: {flow}")
        logger.info(f"Valid flow types: {', '.join(_ft.keys())}")
        return 1

    info = _flow_types()[flow]
    discipline = info.get('discipline', 'PD')

    logger.info("")
    logger.info("═" * 60)
    logger.info(f"  Flow Type: {flow}  ·  discipline = {discipline}")
    logger.info("═" * 60)
    logger.info("")
    logger.info(f"  Discipline:    {discipline}")
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

    _ft = _flow_types()
    if flow not in _ft:
        logger.error(f"Unknown flow type: {flow}")
        return 1

    info = _ft[flow]
    discipline = info.get('discipline', 'PD')
    logger.info(f"Stages for {flow}  [{discipline}]  ({info['description']}):")
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

    # Post 2026-10-11 refactor: tech lives in global/config/tech (not
    # PD/config/tech). Check both locations so the health check still
    # passes against the current layout.
    pd_dirs = [
        'bin', 'cmds', 'config', 'config/flow', 'config/setup',
        'config/project', 'utils', 'docs',
    ]
    global_dirs = ['config/tech', 'config/project', 'config/flow']
    global_root = os.path.join(os.path.dirname(core_dir), 'global')

    for d in pd_dirs:
        path = os.path.join(core_dir, d)
        total += 1
        if os.path.exists(path):
            passed += 1
        else:
            all_ok = False
            failed += 1
            logger.error(f"  [FAIL] PD/{d}/ — missing")
    for d in global_dirs:
        path = os.path.join(global_root, d)
        total += 1
        if os.path.exists(path):
            passed += 1
        else:
            all_ok = False
            failed += 1
            logger.error(f"  [FAIL] global/{d}/ — missing")

    logger.info(f"  [PASS] {len(pd_dirs) + len(global_dirs)} directories checked")

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
                with open(fpath, encoding='utf-8') as fh:
                    content = fh.read()
            except (OSError, UnicodeDecodeError) as _read_err:
                logger.debug(f'handler read skipped ({fpath}): {_read_err}')
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

                # Tool-specific config may override stages / node_types — read
                # it and prefer its definitions if present. This lets a tool
                # declare its own stage list when the base flow's FC-shaped
                # list doesn't match (e.g. FCFP/innovus implements 5 floorplan
                # stages, not FC's 10 hierarchical-planning stages).
                tool_cfg_path = os.path.join(node_cfg_dir, f'{flow_name}_{tool}_config.tcl')
                stages_for_tool = stages
                node_types_for_tool = node_types
                if os.path.isfile(tool_cfg_path):
                    try:
                        with open(tool_cfg_path) as fh:
                            tool_content = fh.read()
                    except Exception:
                        tool_content = ''
                    tm = _re.search(r'stages\s+\{([^}]+)\}', tool_content)
                    if tm:
                        stages_for_tool = tm.group(1).split()
                        # When the tool overrides stages, also rebuild node_types
                        # from the tool config (the inherited base entries no
                        # longer apply — they referenced removed stages).
                        node_types_for_tool = {}
                        for nt_m in _re.finditer(r'node_types,(\w+)\s+"(\w+)"', tool_content):
                            node_types_for_tool[nt_m.group(1)] = nt_m.group(2)

                for stage in stages_for_tool:
                    node_type = node_types_for_tool.get(stage, stage.rstrip('0123456789'))
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
    # Post-split (Phase 3): identity lives in global/config/project/<p>/v1.0.0/
    # project_config.tcl; PD overlay in <core>/config/project/<p>/v1.0.0/
    # project_pd_config.tcl. A project is considered installed when BOTH sides
    # exist. The global side is the identity anchor — if it's missing, the
    # project is unusable regardless of the PD overlay.
    logger.info("")
    logger.info("  5. Project Configs")
    logger.info("  " + "─" * 57)

    from core.paths import get_cbflow_global_dir as _get_gdir
    _gdir = _get_gdir()
    global_proj_dir = os.path.join(_gdir, 'config', 'project') if _gdir else None
    pd_proj_dir = os.path.join(core_dir, 'config', 'project')

    # Union of project names across global + PD sides (each may have its own).
    proj_names = set()
    for _d in (global_proj_dir, pd_proj_dir):
        if _d and os.path.isdir(_d):
            proj_names.update(
                d for d in os.listdir(_d) if os.path.isdir(os.path.join(_d, d))
            )
    for proj in sorted(proj_names):
        g_cfg = os.path.join(global_proj_dir, proj, 'v1.0.0', 'project_config.tcl') \
                if global_proj_dir else ''
        p_cfg = os.path.join(pd_proj_dir, proj, 'v1.0.0', 'project_pd_config.tcl')
        total += 1
        missing = []
        if not (g_cfg and os.path.exists(g_cfg)):
            missing.append('global project_config.tcl')
        if not os.path.exists(p_cfg):
            missing.append('PD project_pd_config.tcl')
        if not missing:
            passed += 1
            logger.info(f"  [PASS] {proj}")
        else:
            failed += 1
            all_ok = False
            logger.error(f"  [FAIL] {proj} — missing: {', '.join(missing)}")

    # ── 6. Tech Configs ─────────────────────────────────────────────────
    # Post 2026-10-11: tech is a SINGLE file in global/config/tech/<tech>/.
    # PD/config/tech/ no longer exists. Lib tags live under
    # global/config/tech/<tech>/<ver>/<TAG>/ (new tag-dir layout).
    logger.info("")
    logger.info("  6. Tech Configs")
    logger.info("  " + "─" * 57)

    global_tech_dir = os.path.join(_gdir, 'config', 'tech') if _gdir else None
    tech_names = set()
    if global_tech_dir and os.path.isdir(global_tech_dir):
        tech_names.update(
            d for d in os.listdir(global_tech_dir)
            if os.path.isdir(os.path.join(global_tech_dir, d))
        )
    for tech in sorted(tech_names):
        g_cfg = os.path.join(global_tech_dir, tech, 'v1.0.0', 'tech_config.tcl')
        total += 1
        if not os.path.exists(g_cfg):
            failed += 1
            all_ok = False
            logger.error(f"  [FAIL] {tech} — missing: global tech_config.tcl")
            continue
        passed += 1
        # Discover lib tags under <tech>/v1.0.0/<TAG>/lib_config.tcl.
        tech_ver_dir = os.path.join(global_tech_dir, tech, 'v1.0.0')
        lib_tags = []
        for entry in sorted(os.listdir(tech_ver_dir)):
            if os.path.isfile(os.path.join(tech_ver_dir, entry, 'lib_config.tcl')):
                lib_tags.append(entry)
        tag_str = (f" (lib tags: {', '.join(lib_tags)})"
                   if lib_tags else " (no lib_config)")
        logger.info(f"  [PASS] {tech}{tag_str}")

    # ── 7. Project Config Key Parity ────────────────────────────────────
    logger.info("")
    logger.info("  7. Project Config Key Parity")
    logger.info("  " + "─" * 57)

    project_keys  = {}  # project_name -> set of project(...) keys
    project_lines = {}  # project_name -> { key: line_number }
    SET_KEY_LINE = _re.compile(r'^\s*set\s+(project\([^\)]+\))')

    # Post-split: each project's key set is the union of global project_config.tcl
    # + PD project_pd_config.tcl. Both halves contribute to `project(...)` in the
    # cascade — the parity check must see both.
    def _collect_project_keys(proj: str) -> tuple:
        seen_lines = {}
        for _p in (
            os.path.join(global_proj_dir, proj, 'v1.0.0', 'project_config.tcl')
            if global_proj_dir else None,
            os.path.join(pd_proj_dir, proj, 'v1.0.0', 'project_pd_config.tcl'),
        ):
            if not (_p and os.path.isfile(_p)):
                continue
            with open(_p) as fh:
                for i, line in enumerate(fh, start=1):
                    m = SET_KEY_LINE.match(line)
                    if m and m.group(1) not in seen_lines:
                        seen_lines[m.group(1)] = (os.path.basename(_p), i)
        return seen_lines

    for proj in sorted(proj_names):
        lines_by_key = _collect_project_keys(proj)
        if not lines_by_key:
            continue
        project_keys[proj] = set(lines_by_key.keys())
        # For parity display: keep just the line number, prefixed with a source
        # tag ('G' = global, 'P' = pd) so drift within one half vs across halves
        # is at-a-glance visible.
        project_lines[proj] = {
            k: f"{'G' if v[0].endswith('project_config.tcl') else 'P'}:{v[1]}"
            for k, v in lines_by_key.items()
        }

    if len(project_keys) < 2:
        logger.info(f"  [SKIP] need >= 2 projects to compare key parity "
                    f"(found {len(project_keys)})")
    else:
        # Canonical = union of all keys across all projects. Any project missing
        # one is flagged.
        union = set().union(*project_keys.values())
        intersection = set.intersection(*project_keys.values())
        proj_names = sorted(project_keys)

        total += 1
        if len(union) == len(intersection):
            passed += 1
            logger.info(f"  [PASS] {len(intersection)} keys identical across "
                        f"{len(project_keys)} projects: {', '.join(proj_names)}")
        else:
            warnings += 1
            drift = union - intersection
            logger.warning(
                f"  [WARN] {len(drift)} key(s) drift across projects "
                f"({len(intersection)} common / {len(union)} union) — "
                f"projects: {', '.join(proj_names)}"
            )
            for key in sorted(drift):
                present_in = [p for p in proj_names if key in project_keys[p]]
                missing_in = [p for p in proj_names if key not in project_keys[p]]
                logger.warning(
                    f"           {key}  →  in: {','.join(present_in)}  "
                    f"missing: {','.join(missing_in)}"
                )

        # Line-position parity: for each key common to all projects, every
        # project should put it on the same line number. Two classes of
        # keys legitimately drift and are exempted:
        #   (a) multi-line braced value blocks (default_tools,
        #       design_hierarchy, validation,*) — their content sizes
        #       differ per project, so they live at the bottom of the file
        #   (b) derived keys whose RHS references another array element
        #       (e.g. [dict keys $project(design_hierarchy)]) — must sit
        #       after their dependency, so their line follows whatever the
        #       size of that dependency was for each project
        def _exempt_keys(path):
            """Return the set of project(KEY)s allowed to have different
            line numbers across projects: multi-line value blocks +
            derived keys (RHS has `[...]` or `$project(...)`)."""
            out = set()
            with open(path) as fh:
                lines = fh.read().splitlines(keepends=True)
            j = 0
            while j < len(lines):
                m = _re.match(r'^\s*set\s+(project\([^\)]+\))\s+(.*)$', lines[j])
                if not m:
                    j += 1
                    continue
                key, val = m.group(1), m.group(2)
                if val.lstrip().startswith('{') and val.count('{') > val.count('}'):
                    out.add(key)
                    depth = val.count('{') - val.count('}')
                    j += 1
                    while j < len(lines) and depth > 0:
                        depth += lines[j].count('{') - lines[j].count('}')
                        j += 1
                    continue
                # Derived value — has command substitution `[...]` or
                # variable substitution against another project(...) entry.
                if '[' in val or '$project(' in val:
                    out.add(key)
                j += 1
            return out

        # Union of exempt keys across all projects. Post-split each project
        # contributes two files (global identity + PD overlay); an exempt
        # (multi-line/derived) key on either side should suppress line-parity
        # checking for that key.
        exempt = set()
        for proj in proj_names:
            for _p in (
                os.path.join(global_proj_dir, proj, 'v1.0.0', 'project_config.tcl')
                if global_proj_dir else None,
                os.path.join(pd_proj_dir, proj, 'v1.0.0', 'project_pd_config.tcl'),
            ):
                if _p and os.path.isfile(_p):
                    exempt |= _exempt_keys(_p)

        checkable = intersection - exempt
        misaligned = []
        for key in sorted(checkable):
            lns = [project_lines[p].get(key) for p in proj_names]
            if len(set(lns)) > 1:
                misaligned.append((key, lns))

        total += 1
        if not misaligned:
            passed += 1
            logger.info(f"  [PASS] {len(checkable)} single-line keys at identical "
                        f"line numbers across {len(proj_names)} projects "
                        f"({len(exempt)} multi-line blocks exempt)")
        else:
            warnings += 1
            logger.warning(
                f"  [WARN] {len(misaligned)} key(s) at different line numbers "
                f"across projects — keys should be aligned line-for-line to "
                f"ease diff/merge across project configs"
            )
            for key, lns in misaligned[:15]:
                pairs = ', '.join(f'{p}:L{l}' for p, l in zip(proj_names, lns))
                logger.warning(f"           {key}  →  {pairs}")
            if len(misaligned) > 15:
                logger.warning(f"           ... and {len(misaligned)-15} more")

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
    logger.info(f"  Flow types:   {len(_flow_types())}")

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
    types_parser = subparsers.add_parser('types', help='List all flow types (grouped by discipline)')
    types_parser.add_argument('--domain', '-d', default=None,
                              help='Filter to one discipline (PD | DFT | DV)')

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
