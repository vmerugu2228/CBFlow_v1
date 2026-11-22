#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Workspace Command Handler
# Description: Handles workspace initialization, run management commands
# Usage: cbflow workspace <subcommand> [options]
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import os
import re
import sys
import json
import subprocess
import logging
from datetime import datetime
from pathlib import Path

# Configure unified logging
from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.workspace')

import sys as _sys
_sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
_sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import CBFLOW_VERSION as VERSION, get_cbflow_core_dir, get_flow_config_version

# PD-only command modules (validation_cmd, library_manager_cmd, …) live
# under PD/utils/commands/ after the cbflow_global utils-refactor. Add
# that location to sys.path so `from validation_cmd import …` resolves
# below without env setup. Silently no-op when PD/ is sparse-checked-out.
try:
    _pd_cmds_bootstrap = os.path.join(get_cbflow_core_dir(), 'utils', 'commands')
    if os.path.isdir(_pd_cmds_bootstrap) and _pd_cmds_bootstrap not in _sys.path:
        _sys.path.insert(0, _pd_cmds_bootstrap)
except Exception:
    pass

# Valid flow types - loaded lazily via module `__getattr__` (PEP 562).
# The resolver requires CBFLOW_CORE_DIR/FLOW_DIR/CONFIG_ROOT env vars
# set by cbflow's launcher; a bare `import workspace_cmd` from tooling
# (healthcheck, IDE, autodocs, tests) without that environment would
# otherwise crash at import time. Deferring to first attribute access
# keeps `import` side-effect-free while preserving the
# `workspace_cmd.FLOW_TYPES` API for real callers.
from tcl_config_parser import get_flow_types as _get_flow_types

_FLOW_TYPES_CACHE = None


def __getattr__(name):
    if name == 'FLOW_TYPES':
        global _FLOW_TYPES_CACHE
        if _FLOW_TYPES_CACHE is None:
            _FLOW_TYPES_CACHE = _get_flow_types()
        return _FLOW_TYPES_CACHE
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")




def get_cbflow_root() -> str:
    """Get CBFlow root directory."""
    if 'CBFLOW_ROOT' in os.environ:
        return os.environ['CBFLOW_ROOT']
    core_dir = get_cbflow_core_dir()
    return os.path.dirname(os.path.dirname(core_dir))


def get_available_releases() -> list:
    """Get available release versions from releases/ directory."""
    core_dir = get_cbflow_core_dir()
    releases_dir = Path(core_dir) / "releases"
    versions = []
    if releases_dir.exists():
        for item in sorted(releases_dir.iterdir()):
            if item.is_dir() and item.name.startswith('v') and item.name != 'current':
                versions.append(item.name)
    return sorted(versions, reverse=True)


def get_current_release() -> str:
    """Get the current release version."""
    core_dir = get_cbflow_core_dir()
    current_link = Path(core_dir) / "releases" / "current"
    if current_link.is_symlink():
        return os.readlink(current_link)
    return None


def load_release_manifest(version: str) -> dict:
    """Load release MANIFEST.json."""
    core_dir = get_cbflow_core_dir()
    manifest_file = Path(core_dir) / "releases" / version / "MANIFEST.json"
    if manifest_file.exists():
        with open(manifest_file, 'r') as f:
            return json.load(f)
    return {}


def get_available_projects() -> list:
    """Get available projects — walks global/ and PD/config/project."""
    from core.paths import list_available_projects
    return [p for p in list_available_projects() if p != 'workspace']


def _flow_discipline(flow_type: str) -> str:
    """Discipline owning `flow_type` from flow(discipline,<FLOW>). A merged
    flow spec (e.g. SYNTH_FP) belongs to the one discipline all of its
    sub-flows share. Raises (no PD default) when unmapped or mixed."""
    from tcl_config_parser import get_flow_discipline, parse_merged_flow
    ft = flow_type.upper()
    discs = {get_flow_discipline(f).upper() for f in (parse_merged_flow(ft) or [ft])}
    if len(discs) != 1:
        raise ValueError(f"merged flow {ft} spans disciplines {sorted(discs)}")
    return discs.pop()


def is_workspace_initialized() -> bool:
    """Check if current directory is a valid workspace.

    A workspace is valid if it contains any run directory (named
    <PHASE>_run_<FLOW>_<RUN_NAME>) or a .cbflow.env. Phase naming is
    free-form — P0/P1/… for pre-tapeout cadence, LC1/LC2/… for the
    long-cycle cadence used by some SoC teams — so we accept any
    directory whose name matches the <PHASE>_run_<...> shape rather
    than hardcoding a prefix letter.
    """
    cwd = os.getcwd()
    if os.path.exists(os.path.join(cwd, '.cbflow.env')):
        return True
    for d in os.listdir(cwd):
        full = os.path.join(cwd, d)
        if not os.path.isdir(full):
            continue
        if _is_run_dir(d):
            return True
    return False


# Match <PHASE>_run_<FLOW>_<RUN_NAME> where PHASE is one of the known
# shape forms. Previous `[A-Za-z0-9]+_run_[A-Za-z0-9_]+` accepted stray
# dirs like old_run_notes, pre_run_check, backup_run_sim because any
# alnum prefix with any alnum/underscore suffix passed. The anchored
# phase pattern below rejects those while still accepting production
# conventions (P0..Pn, LC1..LCn, LC_1 style, MTO/BTO milestone, custom
# site prefixes R\d+). Flow token after _run_ is required (uppercase)
# so bare P0_run_ or P0_run_foo (lowercase flow) is also rejected.
import re as _re_mod
# Phase token: any project-defined phase name (project(phases)) — not a
# fixed list of phase schemes.
_PHASE_PREFIX_RE = r'(?:[A-Za-z0-9]+(?:_[0-9]+)?)'
_FLOW_TOKEN_RE   = r'[A-Z][A-Z0-9_]*'
_RUN_DIR_RE = _re_mod.compile(
    r'^' + _PHASE_PREFIX_RE + r'_run_' + _FLOW_TOKEN_RE + r'(?:_|$)')


def _is_run_dir(name: str) -> bool:
    """Match <PHASE>_run_<FLOW>_<RUN_NAME> dirs. Phase prefix must be one
    of the known cadences; flow token must be uppercase to reject lower-
    case strays. Previous permissive form matched old_run_notes/,
    backup_run_sim/ etc. — `cbflow workspace clean --confirm` would then
    rm -rf non-CBflow user data.
    """
    return bool(_RUN_DIR_RE.match(name))


def load_cbflow_env() -> dict:
    """Load .cbflow.env as dictionary."""
    env_file = os.path.join(os.getcwd(), '.cbflow.env')
    env_vars = {}
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    if line.startswith('export '):
                        line = line[7:]
                    key, value = line.split('=', 1)
                    env_vars[key] = value.strip('"').strip("'")
    return env_vars


def _get_flow_specific_config(flow_type: str) -> str:
    """Return the flow-specific user_config.tcl input section, derived from
    the flow's resolved node config (default tool):

      * `<flow>(mandatory_user_inputs)`  → `set <var> ""` lines (required)
      * other `<flow>(input,*)` members of `<flow>(mandatory_input_groups)`
        → commented alternatives (any one per group satisfies the group)
      * when `flow_input_handshake(<FLOW>,*)` entries exist, the generic
        release-tag / from_run handshake knobs, commented.

    No per-flow template text lives in code.
    """
    import cbflow_config as _c
    ft = flow_type.upper()
    arr = ft.lower()
    cfg = _c.load_resolved_config(ft)
    required = (_c.optional(cfg, 'mandatory_user_inputs') or '').split()
    groups_raw = _c.optional(cfg, 'mandatory_input_groups') or ''
    alternatives = []
    for v in re.findall(r'\w+\([^()\s]*\)', groups_raw):
        if v.startswith(f'{arr}(input,') and v not in required and v not in alternatives:
            alternatives.append(v)
    has_handshake = any(k.startswith(f'flow_input_handshake({ft},') for k in cfg)

    rule = '# ' + '\u2500' * 81
    out = [rule, f'# {ft} Design Inputs (from {ft} node config)', rule]
    if not required and not alternatives:
        out.append(f'# {arr}(mandatory_user_inputs) / {arr}(mandatory_input_groups) '
                   f'declare no user inputs for {ft}.')
    for v in required:
        out.append(f'set {v:<32} ""           ;# required')
    if alternatives:
        out += ['', '# Alternatives — any ONE input of a mandatory input group satisfies it:']
        out += [f'# set {v:<30} ""' for v in alternatives]
    if has_handshake:
        out += ['', '# Upstream handshake (resolves inputs from a release tag or a sibling run):',
                f'# set {arr + "(input,release_tag)":<30} ""',
                f'# set {arr + "(input,from_run)":<30} ""']
    return '\n'.join(out) + '\n'

# ─────────────────────────────────────────────────────────────────────────────────
# Workspace Commands
# ─────────────────────────────────────────────��───────────────────────────────────

# cmd_init removed — workspace init is no longer needed.
# cbflow workspace create auto-detects from project config + release manifest.


def cmd_template(args: argparse.Namespace) -> int:
    """Dump a user_config.tcl template for a specific flow type.

    --project and --flow come from the CLI. Phase is intentionally NOT
    templated — it's read from the project's `project(current_phase)`
    setting so switching phase happens in the project config, not per-run.
    """
    flow_type = getattr(args, 'flow', '').upper()
    output = getattr(args, 'output', None)
    project_name = getattr(args, 'project', None) or 'my_project'

    from tcl_config_parser import get_flow_types
    valid_flows = get_flow_types()

    if not flow_type:
        # Interactive: enumerate and prompt. Batch: hard-error with usage.
        if sys.stdin.isatty() and valid_flows:
            print('  Available flow types:')
            flows_sorted = sorted(valid_flows)
            for i, f in enumerate(flows_sorted, 1):
                print(f'    {i:2}. {f}')
            choice = input(f'  Select flow [1-{len(flows_sorted)}] or name: ').strip()
            try:
                idx = int(choice) - 1
                if 0 <= idx < len(flows_sorted):
                    flow_type = flows_sorted[idx]
            except ValueError:
                if choice.upper() in valid_flows:
                    flow_type = choice.upper()
            if not flow_type:
                logger.error("  Invalid selection.")
                return 1
        else:
            logger.error("  Error: --flow is required")
            logger.error("  Usage: cbflow workspace template --project bumblebee --flow SYNTH_PNR")
            logger.error(f"  Available: {', '.join(sorted(valid_flows))}")
            return 1
    if flow_type not in valid_flows:
        logger.error(f"  Unknown flow type: {flow_type}")
        logger.error(f"  Available: {', '.join(sorted(valid_flows))}")
        return 1

    # Validate project exists (unless caller left it as the default sentinel).
    # Walk global/ then PD/ — projects may live in either overlay.
    if project_name != 'my_project':
        from core.paths import list_available_projects
        available = list_available_projects()
        if project_name not in available:
            logger.error(f"  Unknown project: {project_name}")
            logger.error(f"  Available: {', '.join(available)}")
            return 1

    design_name = "my_design"

    flow_inputs = _get_flow_specific_config(flow_type)
    # Launch-mode default comes from the registry (flow_registry.tcl), not
    # a second copy here.
    import cbflow_config as _c
    test_mode = _c.require(_c.load_resolved_config(flow_type), 'flow(test_mode)')

    template = f"""#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow User Configuration - {flow_type}
# Generated: project={project_name}  flow={flow_type}
# Phase is taken from project(current_phase) in the {project_name} config —
# override there, not here.
# Usage: cbflow workspace create --config <this_file>
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Flow [MANDATORY]
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "{project_name}"
set flow(type)           "{flow_type}"
set flow(design_name)    "{design_name}"      ;# Your design/block name
set flow(run_name)       "run1"               ;# Unique run identifier
set flow(test_mode)      "{test_mode}"              ;# Set "true" to skip EDA tool execution

{flow_inputs}"""

    if output:
        with open(output, 'w') as f:
            f.write(template)
        logger.info(f"  Template written to: {output}")
        logger.info(f"  Flow type: {flow_type}")
        logger.info(f"")
        logger.info(f"  Next steps:")
        logger.info(f"    1. Edit {output} with your design paths")
        logger.info(f"    2. cbflow workspace create --config {output}")
    else:
        # Print to stdout
        print(template)

    return 0


def _build_env_from_user_config(config_file: str) -> dict:
    """Auto-detect all environment variables from user_config.tcl + FLOW_DIR.

    No workspace init needed — everything is derived from:
    - FLOW_DIR (auto-detected from cbflow binary location)
    - user_config.tcl (project name, flow type, design name)
    - release_versions.tcl (component versions)
    """
    from start_run import _parse_user_config

    user_config = _parse_user_config(config_file)

    # Extract from user_config
    project_name = user_config.get('project(name)', '')
    flow_type = user_config.get('flow(type)', '').upper()
    design_name = user_config.get('flow(design_name)', '')
    technology = user_config.get('project(technology)', '')

    if not project_name:
        logger.error("  Error: project(name) not set in user_config.tcl")
        return {}
    if not flow_type:
        logger.error("  Error: flow(type) not set in user_config.tcl")
        return {}
    if not design_name:
        logger.error("  Error: flow(design_name) not set in user_config.tcl")
        return {}

    # Resolve the discipline that owns this flow — in a sparse DFT/DV
    # clone PD/ isn't on disk, so core_dir has to come from the owning
    # discipline's root, not the hardcoded PD one.
    from core.paths import get_cbflow_discipline_root
    try:
        core_dir = get_cbflow_discipline_root(_flow_discipline(flow_type))
    except (ValueError, KeyError) as e:
        logger.error(f"  Error: {e}")
        return {}

    # Auto-detect all paths from the discipline root
    config_root = os.path.join(core_dir, 'config')
    # SCRIPTS_ROOT points at the SHARED utils tree (global/utils/) because
    # every DFT/DV/PD handler sources utilities (handler_common, launch_utils,
    # utils, resolve_inputs, error_utils) that moved to global/utils/
    # under the cbflow_global refactor. PD-specific utilities still live
    # under PD/utils/ and are addressed via $CBFLOW_CORE_DIR/utils.
    from core.paths import get_cbflow_global_dir as _get_gdir_sr
    _global_dir_sr = _get_gdir_sr()
    scripts_root = os.path.join(_global_dir_sr, 'utils') if _global_dir_sr else os.path.join(core_dir, 'utils')
    project_root = os.path.join(config_root, 'project', project_name)

    # project(cbflow_release) from the project config files (global
    # identity + every discipline overlay, PROJECT_CONFIG_VERSION) via the
    # shared registry helper — no version-directory guessing.
    from core import registry
    try:
        _proj_cfg_files = registry.project_config_paths(project_name)
        release_version = registry.project_value(project_name, 'cbflow_release') or ''
    except registry.RegistryError as e:
        logger.error(f"  Error: {e}")
        return None
    proj_config_file = ' '.join(_proj_cfg_files)

    # Releases moved from PD/releases → global/releases on 2026-11-01
    # (cross-discipline toolchain pin). get_cbflow_releases_dir() prefers
    # the global location; falls back to the legacy PD/releases/ for
    # back-compat with older installs.
    from core.paths import get_cbflow_releases_dir
    releases_dir = get_cbflow_releases_dir()

    # project(cbflow_release) is mandatory — no silent fallback
    if not release_version:
        logger.error("")
        logger.error("  project(cbflow_release) not found in project config.")
        logger.error(f"  Checked: {proj_config_file}")
        logger.error("")
        logger.error("  Add to your project config:")
        logger.error(f'    set project(cbflow_release) "v1.0.0"')
        logger.error("")
        if releases_dir and os.path.isdir(releases_dir):
            avail = sorted([d for d in os.listdir(releases_dir)
                           if d.startswith('v') and os.path.isdir(os.path.join(releases_dir, d))])
            if avail:
                logger.error(f"  Available releases: {', '.join(avail)}")
                logger.error("")
        return None

    # Validate release exists
    if not releases_dir:
        from core.paths import get_cbflow_global_dir as _get_gdir
        _gdir = _get_gdir() or '<global/ not set up>'
        logger.error("")
        logger.error("  No releases/ directory found. Expected at:")
        logger.error(f"    {_gdir}/releases/  (preferred)")
        logger.error(f"    {core_dir}/releases/                 (legacy)")
        logger.error("")
        return None
    release_dir = os.path.join(releases_dir, release_version)
    if not os.path.isdir(release_dir):
        logger.error("")
        logger.error(f"  Release '{release_version}' not found at: {release_dir}")
        avail = sorted([d for d in os.listdir(releases_dir)
                       if d.startswith('v') and os.path.isdir(os.path.join(releases_dir, d))])
        if avail:
            logger.error(f"  Available releases: {', '.join(avail)}")
        logger.error("")
        return None

    # Load component versions from release
    versions = {}
    release_file = os.path.join(releases_dir, release_version, 'release_versions.tcl')
    if os.path.exists(release_file):
        with open(release_file, 'r') as f:
            for line in f:
                m = re.match(r'set\s+(\w+)\s+"([^"]*)"', line.strip())
                if m:
                    versions[m.group(1)] = m.group(2)

    # Resolve technology from project config if not in user_config.
    if not technology:
        technology = registry.project_value(project_name, 'technology') or ''

    tech_parts = technology.split('_', 1) if technology else ['', '']
    tech_vendor = tech_parts[0] if tech_parts[0] else ''
    tech_node = tech_parts[1] if len(tech_parts) > 1 else ''

    # Build the complete env dict
    from core.paths import get_cbflow_global_dir as _get_gdir_env
    _gdir_env = _get_gdir_env()
    _root_env = os.path.dirname(core_dir) if core_dir else ''
    env = {
        # FLOW_DIR = umbrella root (sibling of PD/, DFT/, DV/, global/).
        # Handlers resolve shared utilities via $FLOW_DIR/global/utils/...
        # and discipline cmds via $FLOW_DIR/<DISC>/cmds/... after the
        # global-utils refactor. Pre-refactor FLOW_DIR = PD/, which made
        # $FLOW_DIR/global/utils/... resolve to PD/global/... (broken).
        'FLOW_DIR': _root_env,
        'CONFIG_ROOT': config_root,
        'SCRIPTS_ROOT': scripts_root,
        'PROJECT_ROOT': project_root,
        # cbflow_global cascade — resolvers inside the run need these.
        'CBFLOW_ROOT': _root_env,
        # Only export CBFLOW_CORE_DIR when PD/ actually exists. In a sparse
        # DFT/DV clone the directory isn't on disk; writing a dead path
        # into .run.cbflow.env causes get_cbflow_core_dir() to raise, and
        # the previous silent fallback to <repo>/global corrupted
        # downstream node_config lookups in generate_setup.tcl.
        'CBFLOW_CORE_DIR': (core_dir if core_dir and os.path.isdir(core_dir)
                            else ''),
        'CBFLOW_GLOBAL_DIR': _gdir_env,
        'PROJECT_NAME': project_name,
        'PROJECT_VERSION': versions.get('CBFLOW_RELEASE_VERSION', release_version),
        'CBFLOW_FLOW_TYPE': flow_type,
        'CBFLOW_DESIGN_NAME': design_name,
        'CBFLOW_PROJECT_NAME': project_name,
        'CBFLOW_RELEASE_VERSION': release_version,
        'TECHNOLOGY_VENDOR': tech_vendor,
        'TECHNOLOGY_NODE': tech_node,
        'TECHNOLOGY_VERSION': versions.get('CONFIG_TECH_VERSION', release_version),
        'TECH_NAME': technology,
        'TECH_VERSION': versions.get('CONFIG_TECH_VERSION', release_version),
        'SETUP_VERSION': versions.get('CONFIG_SETUP_COMMON_VERSION', release_version),
        # Component versions from release manifest
        'FLOW_CONFIG_VERSION': versions.get('CONFIG_FLOW_VERSION', release_version),
        'GENERATION_VERSION': versions.get('UTILS_GENERATION_VERSION', release_version),
        'MAKEFILE_COMMANDS_VERSION': versions.get('UTILS_MAKEFILE_COMMANDS_VERSION', release_version),
        'NODE_MANAGEMENT_VERSION': versions.get('UTILS_NODE_MANAGEMENT_VERSION', release_version),
        'UTILITIES_VERSION': versions.get('UTILS_UTILITIES_VERSION', release_version),
        'VALIDATION_VERSION': versions.get('UTILS_VALIDATION_VERSION', release_version),
    }
    # Sibling discipline roots (every discipline of flow(disciplines) other
    # than PD, whose CBFLOW_CORE_DIR is set above) — exported only when the
    # directory is on disk (sparse clones).
    for _d in registry.flow_disciplines():
        _ev = registry.discipline_env_var(_d)
        if _ev in env:
            continue
        _dd = registry.discipline_dir(_d)
        env[_ev] = _dd if os.path.isdir(_dd) else ''

    # Extract tool vendor/name overrides from user_config
    # e.g., pnr(tool,vendor) "cadence", pnr(tool,name) "innovus"
    from start_run import _parse_user_config
    uc = _parse_user_config(config_file)
    arr = flow_type.lower().replace('_', '_')  # pnr, synth_pnr, sta, etc.
    tool_vendor = uc.get(f'{arr}(tool,vendor)', '')
    tool_name = uc.get(f'{arr}(tool,name)', '')
    # Auto-resolve vendor from tool-specific config: <FLOW>_<tool>_config.tcl
    if not tool_vendor and tool_name:
        import re as _re
        # The flow's discipline root (resolved above), not PD.
        cfg_ver = registry.config_version('FLOW_CONFIG_VERSION')
        tool_cfg = os.path.join(core_dir, 'config', 'flow', cfg_ver,
                                'node_configs', '{}_{}_config.tcl'.format(flow_type, tool_name))
        if os.path.isfile(tool_cfg):
            with open(tool_cfg, 'r') as _tcf:
                for _line in _tcf:
                    _m = _re.search(r'tool,vendor["\s]+["\s]*([^"}\s]+)', _line)
                    if _m:
                        tool_vendor = _m.group(1)
                        break
    if tool_vendor:
        env['CBFLOW_TOOL_VENDOR'] = tool_vendor
    if tool_name:
        env['CBFLOW_TOOL_NAME'] = tool_name

    return env


def _get_mandatory_inputs_from_config(core_dir: str, flow_type: str,
                                      tool_name: str = '') -> list:
    """Read mandatory_user_inputs from <FLOW>_config.tcl if defined.

    Users can add this to any flow config to control which user_config variables are required:
        array set <arr> {
            mandatory_user_inputs {
                <arr>(input,rtl_filelist)
                <arr>(input,sdc_func_file)
                <arr>(input,upf_file)
            }
        }

    Returns list of variable keys, or empty list if not defined.
    """
    import re as _re
    flow_config_ver = get_flow_config_version()
    node_dir = os.path.join(core_dir, 'config', 'flow', flow_config_ver, 'node_configs')
    # The selected tool's overlay (<FLOW>_<tool>_config.tcl) may redefine the
    # list — e.g. the open-source PNR builds its own floorplan, so no DEF.
    candidates = []
    if tool_name:
        candidates.append(os.path.join(node_dir, f'{flow_type}_{tool_name}_config.tcl'))
    candidates.append(os.path.join(node_dir, f'{flow_type}_config.tcl'))
    for config_file in candidates:
        if not os.path.exists(config_file):
            continue
        with open(config_file, 'r') as f:
            content = f.read()
        # Match: mandatory_user_inputs { var1 var2 var3 }
        m = _re.search(r'mandatory_user_inputs\s*\{([^}]*)\}', content)
        if m:
            raw = m.group(1).strip()
            return [v.strip() for v in raw.split() if v.strip()]
    return []


def _handshake_entries(flow_type: str) -> list:
    """[(input, source_flow, category)] from the release_config handshake
    map flow_input_handshake(<FLOW>,<input>) of the resolved config."""
    import cbflow_config as _c
    cfg = _c.load_resolved_config(flow_type)
    prefix = f'flow_input_handshake({flow_type},'
    out = []
    for k, v in cfg.items():
        if k.startswith(prefix) and k.endswith(')'):
            parts = v.split()
            if len(parts) >= 2:
                out.append((k[len(prefix):-1], parts[0], parts[1]))
    return out


def _confirm_restricted_vars(config_file: str, args: argparse.Namespace) -> bool:
    """Scan user_config for edit-restricted variables.

    If any restricted variable is set, print a warning and require the user
    to type 'yes' to proceed. Returns True if creation should continue,
    False to abort. --force / --yes flag or non-tty stdin bypasses the
    prompt (warning is still printed and recorded).
    """
    try:
        import restricted_vars
    except ImportError:
        return True
    hits = restricted_vars.scan_file(config_file)
    if not hits:
        return True

    sep = '\033[33m' + ('─' * 60) + '\033[0m'
    print()
    print(sep)
    print('\033[33;1m  WARNING: edit-restricted variables in user_config\033[0m')
    print(sep)
    print(f"  File: {config_file}")
    print(f"  Found {len(hits)} restricted variable(s) that are normally")
    print(f"  controlled by the CAD team or project lead:")
    print()
    for lineno, var_name, raw in hits:
        print(f"    line {lineno:>4}: \033[33m{var_name}\033[0m")
    print()
    print("  These variables affect tech identity, tool selection, RC corners,")
    print("  MMMC, or release milestones. Overriding them in user_config bypasses")
    print("  the CAD team's intended configuration.")
    print(sep)
    print()

    # --accept-restricted (new) is the batch/CI-safe skip. --force is
    # ALSO honored for backward compatibility, but --force additionally
    # rmtrees any existing run dir — document the trade-off so operators
    # pick the right flag.
    accept = bool(getattr(args, 'accept_restricted', False)
                  or getattr(args, 'force', False)
                  or getattr(args, 'yes', False))
    if accept:
        if getattr(args, 'accept_restricted', False):
            print("  --accept-restricted set: proceeding without confirmation.")
        else:
            print("  --force set: proceeding without confirmation.")
        print()
        return True
    if not sys.stdin.isatty():
        logger.error("  Non-interactive stdin and restricted-vars prompt pending.")
        logger.error("  Re-run with --accept-restricted (safe) or --force (also recreates run).")
        return False

    try:
        ans = input("  Type 'yes' to create the run anyway: ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        logger.error("  Aborted.")
        return False
    if ans != 'yes':
        logger.error("  Run creation aborted by user.")
        return False
    print()
    return True


def _validate_mandatory_inputs(user_config: dict, flow_type: str) -> list:
    """Validate mandatory design inputs are set (non-empty) in user_config.

    Returns list of error messages. Empty list = all good.
    """
    errors = []
    ft = flow_type.upper()

    # Resolve core_dir from the OWNING discipline, not hardcoded PD. In a
    # sparse DFT/DV clone PD/ isn't on disk; get_cbflow_core_dir() now
    # raises on missing PD/ instead of silently falling back to global/.
    from core.paths import get_cbflow_discipline_root
    try:
        _flow_disc = _flow_discipline(ft)
    except (ValueError, KeyError) as e:
        # Unmapped / invalid flow — no PD default.
        errors.append(f"flow(type) '{ft}' has no discipline: {e}")
        return errors
    try:
        core_dir = get_cbflow_discipline_root(_flow_disc)
    except ValueError:
        # Owning discipline isn't on disk — skip the mandatory-inputs check
        # that depends on node_configs. Return early with no errors; the
        # workspace resolver will fail later with a clearer message if
        # anything is actually missing.
        return errors

    # Common mandatory fields for all flows
    project_name = user_config.get('project(name)', '')
    if not project_name:
        errors.append("project(name) is empty")
    else:
        # Validate project exists — walk global/ then PD/.
        from core.paths import list_available_projects
        available = list_available_projects()
        if project_name not in available:
            errors.append(f"project '{project_name}' not found in global/config/project/ or PD/config/project/. Available: {', '.join(available)}")

    # Validate flow type (from flow_config.tcl)
    config_flow = user_config.get('flow(type)', '')
    if not config_flow:
        errors.append("flow(type) is empty")
    else:
        from tcl_config_parser import get_flow_types, is_merged_flow
        valid_flows = get_flow_types()
        if config_flow.upper() not in valid_flows and not is_merged_flow(config_flow.upper()):
            errors.append(f"flow(type) '{config_flow}' is invalid. Valid: {', '.join(valid_flows)}")

    # Validate phase (from flow_config.tcl)
    phase = user_config.get('project(phase)', '')
    if phase:
        from tcl_config_parser import get_phases
        valid_phases = get_phases()
        if valid_phases and phase not in valid_phases:
            errors.append(f"project(phase) '{phase}' is invalid. Valid: {', '.join(valid_phases)}")

    if not user_config.get('flow(run_name)', ''):
        errors.append("flow(run_name) is empty")

    # Validate design name exists in project config
    design_name = user_config.get('flow(design_name)', '')
    if not design_name:
        errors.append("flow(design_name) is empty")
    elif project_name and not errors:
        # Read block_list from project config via shared cascade helper
        # (global/project_config → PD/project_pd_config → legacy monolith).
        # Pre-fix only the legacy monolith was checked, so block_list
        # validation silently skipped on migrated installs and typos
        # like `design_name "typo-name"` passed through to run-time.
        from core.paths import read_project_cfg_key
        from core import registry
        _bl = read_project_cfg_key(project_name, 'block_list',
                                   registry.config_version('PROJECT_CONFIG_VERSION'))
        if _bl:
            valid_designs = _bl.split()
            if design_name not in valid_designs:
                errors.append(f"design '{design_name}' not found in project '{project_name}'. "
                              f"Available designs: {', '.join(valid_designs)}")

    # Flow-specific mandatory inputs — driven entirely by node_config
    _arr = ft.lower()
    mandatory_from_config = _get_mandatory_inputs_from_config(
        core_dir, ft, user_config.get(f'{_arr}(tool,name)', ''))

    if mandatory_from_config:
        # Check if handshake mechanism is active (from_run or release_tag)
        from_run_path = ''
        for k in user_config:
            if 'input,from_run' in k and user_config[k]:
                from_run_path = user_config[k]
                break

        release_tags = {}
        for k in user_config:
            if 'release_tag' in k and 'input,' in k and user_config[k]:
                release_tags[k] = user_config[k]

        if from_run_path:
            # ── Validate from_run: upstream run dir + output_manifest ──
            logger.info(f"  Handshake: from_run → {from_run_path}")
            if not os.path.isdir(from_run_path):
                errors.append(f"from_run directory not found: {from_run_path}")
            else:
                # Check for output_manifest.tcl
                import glob as _glob
                manifests = _glob.glob(os.path.join(from_run_path, 'work', '*', 'export_data*', 'outputs', 'output_manifest.tcl'))
                manifests += _glob.glob(os.path.join(from_run_path, 'work', '*', 'release_data*', 'results', 'output_manifest.tcl'))
                if not manifests:
                    errors.append(f"No output_manifest.tcl found in from_run: {from_run_path}")
                    errors.append(f"  Run the upstream flow to completion first, or use explicit input paths")
                else:
                    # Parse manifest and check required files exist
                    manifest_file = sorted(manifests)[-1]
                    logger.info(f"  Validating upstream manifest: {os.path.basename(manifest_file)}")
                    manifest_data = {}
                    try:
                        with open(manifest_file) as mf:
                            import re as _re
                            for line in mf:
                                m = _re.match(r'\s*(\w+)\s+"([^"]*)"', line)
                                if m:
                                    manifest_data[m.group(1)] = m.group(2)
                    except Exception:
                        pass

                    # Check the files of every category this flow consumes
                    # per the handshake map (flow_input_handshake(<FLOW>,*)).
                    missing_files = []
                    for key in sorted({cat for _i, _src, cat in _handshake_entries(ft)}):
                        if key in manifest_data:
                            fpath = manifest_data[key]
                            if fpath and not os.path.exists(fpath):
                                missing_files.append(f"{key}: {fpath}")
                            elif fpath:
                                logger.info(f"    {key}: {os.path.basename(fpath)}")
                    if missing_files:
                        for mf in missing_files:
                            errors.append(f"from_run missing file — {mf}")

        elif release_tags:
            # ── Validate release_tag: release directory + required files ──
            project_name = user_config.get('project(name)', '')
            design_name = user_config.get('flow(design_name)', '')
            # the run's phase: project(phase) in user_config, else project(current_phase)
            from core import registry
            phase = user_config.get('project(phase)', '') or \
                (registry.project_value(project_name, 'current_phase') or '')
            tag = list(release_tags.values())[0]

            # Resolve the release dir: <release,path>/<phase>/<design>/<FLOW>/<tag>
            # (registry.release_dir) for each upstream flow the handshake map
            # names for this flow (source ANY → any flow in flow(types)).
            from core import registry
            try:
                release_base = registry.require_project_value(project_name, 'release,path')
                # the run's phase (project(phase) / project(current_phase))
                rel_phase = phase
                if not rel_phase:
                    raise registry.RegistryError('run phase unresolved (project(phase) / project(current_phase))')
            except registry.RegistryError as e:
                errors.append(str(e))
                return errors
            _hs = _handshake_entries(ft)
            _srcs = sorted({src for _i, src, _c in _hs})
            _up_flows = registry.flow_types() if (not _srcs or 'ANY' in _srcs) else \
                [f for f in _srcs if f in registry.flow_types()]
            _cands = [registry.release_dir(release_base, rel_phase, design_name, f, tag)
                      for f in _up_flows]
            release_dir = next((c for c in _cands if os.path.isdir(c)),
                               _cands[0] if _cands else os.path.join(release_base, rel_phase))

            logger.info(f"  Handshake: release_tag → {tag}")
            if not os.path.isdir(release_dir):
                errors.append(f"Release directory not found: {release_dir}")
                errors.append(f"  Run 'cbflow run release --tag {tag}' from workspace first")
            else:
                logger.info(f"  Release dir: {release_dir}")
                # Check MANIFEST.json exists
                manifest_json = os.path.join(release_dir, 'MANIFEST.json')
                if not os.path.exists(manifest_json):
                    errors.append(f"MANIFEST.json not found in release: {release_dir}")
                else:
                    # Check the categories this flow consumes per the
                    # handshake map (flow_input_handshake(<FLOW>,*)).
                    _cats = sorted({cat for _i, _s, cat in _hs})
                    found = [cat for cat in _cats
                             if os.path.isdir(os.path.join(release_dir, cat))
                             and os.listdir(os.path.join(release_dir, cat))]
                    if found:
                        logger.info(f"    Available: {', '.join(found)}")
                    else:
                        logger.warning(f"  None of {'/'.join(_cats) or '<no handshake categories>'} "
                                       f"found in release — runtime resolution may fail")
        else:
            # No handshake — enforce mandatory inputs
            for var_key in mandatory_from_config:
                if not user_config.get(var_key, ''):
                    errors.append(f"{var_key} is empty — required by {ft} flow config")
    else:
        # If config-driven validation found nothing, warn but don't block
        logger.warning(f"No mandatory_user_inputs defined in node_config for {ft}")
        logger.warning(f"Skipping mandatory input validation")

    return errors


def cmd_create(args: argparse.Namespace) -> int:
    """Create a new run from user_config.tcl. No workspace init required."""
    config_file = getattr(args, 'config', None)
    if not config_file:
        # Interactive: scan cwd for *.tcl files that look like user_config
        # candidates (contain project(name) and flow(type)) and prompt.
        _candidates = []
        if sys.stdin.isatty():
            for f in sorted(os.listdir('.')):
                if not f.endswith('.tcl') or not os.path.isfile(f):
                    continue
                try:
                    with open(f) as fh:
                        head = fh.read(2048)
                    if 'project(name)' in head and 'flow(type)' in head:
                        _candidates.append(f)
                except OSError:
                    continue
        if sys.stdin.isatty() and _candidates:
            print('  Candidate user_config.tcl files in this directory:')
            for i, f in enumerate(_candidates, 1):
                print(f'    {i}. {f}')
            choice = input(f'  Select config [1-{len(_candidates)}] or path: ').strip()
            try:
                idx = int(choice) - 1
                if 0 <= idx < len(_candidates):
                    config_file = _candidates[idx]
            except ValueError:
                if choice and os.path.exists(choice):
                    config_file = choice
            if not config_file:
                logger.error("  Invalid selection.")
                return 1
        else:
            logger.error("")
            logger.error("  Error: --config is required")
            logger.error("")
            logger.error("  Usage:")
            logger.error("    cbflow workspace create --config user_config.tcl")
            logger.error("")
            return 1

    if not os.path.exists(config_file):
        logger.error(f"Error: Config file not found: {config_file}")
        tcl_files = sorted([f for f in os.listdir('.')
                           if f.endswith('.tcl') and 'config' in f.lower() and os.path.isfile(f)])
        if tcl_files:
            logger.error(f"  Available config files:")
            for f in tcl_files:
                logger.error(f"    - {f}")
        return 1

    # Auto-detect everything from user_config + FLOW_DIR
    env_vars = _build_env_from_user_config(config_file)
    if not env_vars:
        return 1

    # Validate mandatory design inputs before creating run
    from start_run import _parse_user_config
    user_config = _parse_user_config(config_file)
    flow_type = env_vars.get('CBFLOW_FLOW_TYPE', '').upper()

    errors = _validate_mandatory_inputs(user_config, flow_type)
    if errors:
        logger.error("")
        logger.error("  Mandatory input validation failed:")
        for err in errors:
            logger.error(f"    - {err}")
        logger.error("")
        logger.error(f"  Edit {config_file} and set the required values before creating a run.")
        return 1

    # ── Edit-restricted variable check ──
    # Scan user_config.tcl for variables marked as protected in
    # edit_restricted_config.tcl. If any are set, warn and require explicit
    # "yes" confirmation before creating the run. --force or --yes bypasses
    # the prompt but the warning is still printed.
    if not _confirm_restricted_vars(config_file, args):
        return 1

    project = env_vars.get('PROJECT_NAME', '')
    flow_type = env_vars.get('CBFLOW_FLOW_TYPE', '')
    design = env_vars.get('CBFLOW_DESIGN_NAME', '')
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')
    release = env_vars.get('CBFLOW_RELEASE_VERSION', '')

    print(f"  \033[1m{'=' * 60}\033[0m")
    print(f"  \033[1mCBflow Run Creation\033[0m")
    print(f"  {'=' * 60}")
    print(f"  Config:   {config_file}")
    print(f"  Project:  {project}")
    print(f"  Design:   {design}")
    print(f"  Flow:     {flow_type}")
    print(f"  Phase:    {phase}")
    print(f"  Release:  {release}")
    print(f"  {'─' * 60}")
    print()

    # Progress bar with creation steps
    import time as _time
    import threading

    steps = [
        ("Validating configuration", 1.0),
        ("Resolving release components", 0.8),
        ("Building environment", 0.8),
        ("Creating directory structure", 1.0),
        ("Verifying engine DAG", 1.2),
        ("Generating stage makefiles", 1.5),
        ("Writing run environment", 0.8),
        ("Copying user configuration", 0.5),
        ("Finalizing run setup", 0.9),
    ]
    total_steps = len(steps)
    bar_width = 40

    # Run the actual creation in a background thread
    result_holder = {'success': False, 'run_dir': None, 'error': None}

    def do_create():
        try:
            from start_run import create_run
            s, r = create_run(
                config_file=config_file,
                env_vars=env_vars,
                force=getattr(args, 'force', False),
            )
            result_holder['success'] = s
            result_holder['run_dir'] = r
        except Exception as e:
            result_holder['error'] = str(e)

    create_thread = threading.Thread(target=do_create)
    create_thread.start()

    # Show progress while thread runs — stop early on error
    for i, (step_name, step_time) in enumerate(steps):
        if result_holder['error']:
            break
        pct = int((i / total_steps) * 100)
        filled = int(bar_width * i / total_steps)
        bar = '\033[32m' + '#' * filled + '\033[0m' + '-' * (bar_width - filled)
        sys.stdout.write(f"\r  [{bar}] {pct:3d}%  {step_name}...")
        sys.stdout.flush()
        _time.sleep(step_time)

    # Wait for creation to finish
    create_thread.join()

    if not result_holder['error']:
        bar = '\033[32m' + '#' * bar_width + '\033[0m'
        sys.stdout.write(f"\r  [{bar}] 100%  Complete.{' ' * 30}\n")
        sys.stdout.flush()
    print()

    success = result_holder['success']
    run_dir = result_holder['run_dir']

    if result_holder['error']:
        logger.error(f"  Run creation failed: {result_holder['error']}")
        return 1

    if success and run_dir:
        # Write workspace creation log to $run_dir/logs/
        _write_creation_log(run_dir, flow_type, design, phase,
                            config_file, release, env_vars)

        print(f"  \033[32m{'=' * 60}\033[0m")
        print(f"  \033[32;1mRun Created Successfully\033[0m")
        # Show the new run in its discipline dashboard (if that daemon runs);
        # isolated subprocess — see run_cmd._dashboard_autoregister.
        try:
            import subprocess as _sp, sys as _sys
            _u = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            _code = ("import sys; sys.path[:0] = [%r, %r, %r]; import lifecycle; "
                     "lifecycle.autoregister(%r, %r)"
                     % (os.path.join(_u, 'dashboard'), os.path.join(_u, 'commands'), _u,
                        run_dir, flow_type))
            _sp.run([_sys.executable, '-c', _code], capture_output=True, timeout=10)
        except Exception:
            pass
        print(f"  \033[32m{'=' * 60}\033[0m")
        print()
        print(f"  Run Directory:  \033[1m{run_dir}\033[0m")
        print(f"  Flow Type:      {flow_type}")
        print(f"  Design:         {design}")
        print(f"  Phase:          {phase}")
        print()
        print(f"  Next steps:")
        print(f"    \033[36mcd {run_dir}\033[0m")
        print(f"    \033[36mcbflow run all\033[0m")
        print(f"    \033[36mcbflow run status\033[0m")
        print()
        return 0
    else:
        logger.error("  Run creation failed.")
        return 1


def _write_creation_log(run_dir: str, flow_type: str, design: str, phase: str,
                         config_file: str, release_version: str, env_vars: dict):
    """Write workspace creation log to $run_dir/logs/workspace_create.log."""
    from datetime import datetime
    import socket

    logs_dir = os.path.join(run_dir, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    log_file = os.path.join(logs_dir, 'workspace_create.log')

    try:
        with open(log_file, 'w') as f:
            f.write(f"{'=' * 70}\n")
            f.write(f"  CBflow Workspace Creation Log\n")
            f.write(f"{'=' * 70}\n\n")
            f.write(f"  Timestamp:      {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"  User:           {os.environ.get('USER', 'unknown')}\n")
            f.write(f"  Hostname:       {socket.gethostname()}\n")
            f.write(f"  Run Directory:  {os.path.abspath(run_dir)}\n")
            f.write(f"  Flow Type:      {flow_type}\n")
            f.write(f"  Design:         {design}\n")
            f.write(f"  Phase:          {phase}\n")
            f.write(f"  Release:        {release_version}\n")
            f.write(f"  Config File:    {config_file}\n")
            f.write(f"  Dispatcher:     RACE (Run Automation & Control Engine)\n")
            f.write(f"\n{'─' * 70}\n")
            f.write(f"  User Config Variables\n")
            f.write(f"{'─' * 70}\n\n")

            # Write user_config contents
            user_config = os.path.join(run_dir, 'setup', 'user_config.tcl')
            if os.path.exists(user_config):
                with open(user_config) as uc:
                    for line in uc:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            f.write(f"  {line}\n")

            f.write(f"\n{'─' * 70}\n")
            f.write(f"  Environment Variables\n")
            f.write(f"{'─' * 70}\n\n")

            # Write key env vars
            for key in sorted(env_vars.keys()):
                if key.startswith('CBFLOW_') or key in ('FLOW_DIR', 'CONFIG_ROOT', 'SCRIPTS_ROOT'):
                    f.write(f"  {key} = {env_vars[key]}\n")

            f.write(f"\n{'─' * 70}\n")
            f.write(f"  RACE DAG Summary\n")
            f.write(f"{'─' * 70}\n\n")

            # Build DAG summary
            try:
                import sys
                sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
                from race_engine import DagBuilder
                builder = DagBuilder(run_dir, flow_type, env_vars)
                jobs, stages = builder.build()
                f.write(f"  Stages:  {len(stages)}\n")
                f.write(f"  Jobs:    {len(jobs)}\n")
                f.write(f"  Order:   {' → '.join(stages)}\n")
            except Exception as e:
                f.write(f"  DAG build: {e}\n")

            f.write(f"\n{'=' * 70}\n")
            f.write(f"  End of Workspace Creation Log\n")
            f.write(f"{'=' * 70}\n")

    except Exception as e:
        logger.debug(f"Could not write creation log: {e}")


def _get_run_info(run_dir: str) -> dict:
    """Parse a run directory and return structured info."""
    info = {
        'name': run_dir,
        'flow_type': 'unknown',
        'design': '',
        'phase': '',
        'release': '',
        'stages_completed': 0,
        'stages_total': 0,
        'subnodes_completed': 0,
        'status': 'not started',
        'last_activity': '',
    }

    # Parse run name: P0_run_PNR_run1 -> phase=P0, flow=PNR, run_name=run1
    parts = run_dir.split('_run_')
    if len(parts) > 1:
        info['phase'] = parts[0]
        rest = parts[1].split('_', 1)
        info['flow_type'] = rest[0]

    # Parse environment file
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('export ') and '=' in line:
                    kv = line[7:]
                    k, v = kv.split('=', 1)
                    v = v.strip('"').strip("'")
                    if k == 'CBFLOW_FLOW_TYPE': info['flow_type'] = v
                    elif k == 'CBFLOW_DESIGN_NAME': info['design'] = v
                    elif k == 'CBFLOW_PROJECT_PHASE': info['phase'] = v
                    elif k == 'CBFLOW_RELEASE_VERSION': info['release'] = v
                    elif k == 'CBFLOW_RUN_NAME': info['run_name'] = v

    # Parse status from RACE DB
    try:
        from status_provider import StatusProvider
        provider = StatusProvider(run_dir)
        all_status = provider.get_all_status()
        completed = [s for s, v in all_status.items()
                     if v.get('status') in ('DONE', 'BYPASSED', 'FORCE_VALIDATED')]
        info['subnodes_completed'] = len(completed)
        info['completed_list'] = completed
        info['stages_completed'] = len(completed)

        # Last activity from latest timestamp
        latest_ts = ''
        for s, v in all_status.items():
            ts = v.get('timestamp', '')
            if ts > latest_ts:
                latest_ts = ts
        if latest_ts:
            info['last_activity'] = latest_ts[:19].replace('T', ' ')
    except Exception:
        pass

    try:
        from tcl_config_parser import get_flow_stages
        stages = get_flow_stages(info['flow_type'])
        info['stages_total'] = len(stages)
    except Exception:
        pass

    # Determine status
    if info['stages_total'] > 0 and info['stages_completed'] >= info['stages_total']:
        info['status'] = 'completed'
    elif info['stages_completed'] > 0:
        info['status'] = 'in progress'

    # Check for Makefile
    info['has_makefile'] = False  # Makefile no longer generated — engine is default

    return info


def cmd_list_runs(args: argparse.Namespace) -> int:
    """List all existing runs in workspace."""
    if not is_workspace_initialized():
        logger.error(f"Not inside a workspace. Change to a workarea directory first (one containing a .cbflow.env or any <PHASE>_run_<FLOW>_<name>/ dirs), or create a run with 'cbflow workspace create --config user_config.tcl'.")
        return 1

    logger.info("")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info(f"  CBFlow Runs in Workspace")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info("")

    runs = sorted([d for d in os.listdir('.') if os.path.isdir(d) and _is_run_dir(d)])

    if not runs:
        logger.info("No runs found in workspace")
        logger.info("")
        logger.info("Create a run with:")
        logger.info("  cbflow workspace create --config <config_file>")
        return 0

    logger.info(f"  {'Run Directory':<40} {'Flow':<7} {'Phase':<5} {'Progress':<15} {'Status':<12} {'Last Activity'}")
    logger.info(f"  {'─'*110}")

    for run in runs:
        info = _get_run_info(run)
        progress = f"{info['stages_completed']}/{info['stages_total']}" if info['stages_total'] > 0 else "0/?"

        status_icon = {'completed': '[DONE]', 'in progress': '[RUN ]', 'not started': '[    ]'}.get(info['status'], '[????]')

        logger.info(f"  {run:<40} {info['flow_type']:<7} {info['phase']:<5} "
                   f"{progress:<15} {status_icon} {info['status']:<10} {info['last_activity']}")

    logger.info("")
    logger.info(f"  Total: {len(runs)} run(s)")
    logger.info("")
    logger.info(f"  View details: cbflow workspace status --run <run_directory>")
    return 0


def _scan_stage_reports(run_dir: str, flow_type: str, stage: str) -> dict:
    """Scan a stage's work directory for reports, logs, errors, warnings, and metrics."""
    import re
    result = {
        'errors': 0,
        'warnings': 0,
        'log_files': [],
        'report_files': [],
        'metrics': {},
    }

    # Search paths for this stage's outputs
    stage_base = stage.rstrip('0123456789')
    search_dirs = [
        os.path.join(run_dir, 'work', flow_type, stage_base),
        os.path.join(run_dir, 'work', flow_type, stage),
        os.path.join(run_dir, 'logs'),
    ]

    for search_dir in search_dirs:
        if not os.path.isdir(search_dir):
            continue

        for root, dirs, files in os.walk(search_dir):
            for fname in files:
                fpath = os.path.join(root, fname)
                rel_path = os.path.relpath(fpath, run_dir)

                # Collect report and log files
                if fname.endswith(('.rpt', '.report', '.txt', '.summary')):
                    result['report_files'].append(rel_path)
                if fname.endswith('.log'):
                    result['log_files'].append(rel_path)

                # Scan text files for errors/warnings and metrics
                if fname.endswith(('.log', '.rpt', '.txt', '.report', '.tcl')):
                    try:
                        with open(fpath, 'r', errors='ignore') as f:
                            content = f.read()

                        # Count errors and warnings
                        result['errors'] += len(re.findall(r'\bERROR\b', content, re.IGNORECASE))
                        result['warnings'] += len(re.findall(r'\bWARNING\b', content, re.IGNORECASE))

                        # Extract timing metrics (common EDA report patterns)
                        # WNS (Worst Negative Slack)
                        m = re.search(r'(?:WNS|worst.negative.slack|worst.slack)\s*[=:]\s*([-\d.]+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['WNS'] = m.group(1)

                        # TNS (Total Negative Slack)
                        m = re.search(r'(?:TNS|total.negative.slack)\s*[=:]\s*([-\d.]+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['TNS'] = m.group(1)

                        # Setup/Hold violations
                        m = re.search(r'(?:setup).+?violation[s]?\s*[=:]\s*(\d+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Setup Violations'] = m.group(1)
                        m = re.search(r'(?:hold).+?violation[s]?\s*[=:]\s*(\d+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Hold Violations'] = m.group(1)

                        # Area / Utilization
                        m = re.search(r'(?:total.area|cell.area|design.area)\s*[=:]\s*([\d.]+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Area'] = m.group(1)
                        m = re.search(r'(?:utilization|util)\s*[=:]\s*([\d.]+)\s*%?', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Utilization'] = m.group(1) + '%'

                        # DRC violations
                        m = re.search(r'(?:DRC).+?violation[s]?\s*[=:]\s*(\d+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['DRC Violations'] = m.group(1)

                        # Cell count
                        m = re.search(r'(?:total.cells?|instance.count|cell.count)\s*[=:]\s*([\d,]+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Cell Count'] = m.group(1)

                        # Net count
                        m = re.search(r'(?:total.nets?|net.count)\s*[=:]\s*([\d,]+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Net Count'] = m.group(1)

                        # Power
                        m = re.search(r'(?:total.power|dynamic.power)\s*[=:]\s*([\d.]+\s*\w*W)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Power'] = m.group(1)

                        # Clock period / frequency
                        m = re.search(r'(?:clock.period)\s*[=:]\s*([\d.]+)', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Clock Period'] = m.group(1) + 'ns'

                        # Congestion
                        m = re.search(r'(?:congestion)\s*[=:]\s*([\d.]+)\s*%?', content, re.IGNORECASE)
                        if m:
                            result['metrics']['Congestion'] = m.group(1) + '%'

                    except Exception:
                        pass

    return result


def _generate_run_summary(run_dir: str, info: dict) -> str:
    """Generate a comprehensive summary report for a run."""
    import re
    lines = []
    flow_type = info['flow_type']

    lines.append(f"")
    lines.append(f"{'═'*75}")
    lines.append(f"  CBFlow Run Summary Report")
    lines.append(f"{'═'*75}")
    lines.append(f"")
    lines.append(f"  Run:           {run_dir}")
    lines.append(f"  Flow Type:     {flow_type}")
    lines.append(f"  Design:        {info.get('design', 'N/A')}")
    lines.append(f"  Phase:         {info['phase']}")
    lines.append(f"  Release:       {info.get('release', 'N/A')}")
    lines.append(f"  Status:        {info['status']}")
    lines.append(f"  Generated:     {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"")

    # Get stages and stamps
    try:
        from tcl_config_parser import get_flow_stages
        stages = get_flow_stages(flow_type)
    except Exception:
        stages = []

    # Get stage completion times from RACE DB
    stamp_times = {}
    try:
        from status_provider import StatusProvider
        provider = StatusProvider(run_dir)
        all_status = provider.get_all_status()
        for stage, sinfo in all_status.items():
            if sinfo.get('status') in ('DONE', 'BYPASSED', 'FORCE_VALIDATED'):
                ts = sinfo.get('timestamp', '')
                if ts:
                    try:
                        stamp_times[stage] = datetime.fromisoformat(ts).timestamp()
                    except (ValueError, TypeError):
                        pass
    except Exception:
        pass

    # ── Per-Stage Summary Table ──
    lines.append(f"  {'─'*70}")
    lines.append(f"  STAGE EXECUTION SUMMARY")
    lines.append(f"  {'─'*70}")
    lines.append(f"  {'Stage':<20} {'Status':<12} {'Duration':<12} {'Errors':<8} {'Warnings':<8} {'Reports'}")
    lines.append(f"  {'─'*70}")

    total_errors = 0
    total_warnings = 0
    total_reports = 0
    all_metrics = {}
    prev_time = None

    for stage in stages:
        stage_key = stage   # config stage names are the node keys
        done = stage_key in stamp_times

        # Calculate duration from sequential stamps
        duration_str = "-"
        if done and prev_time is not None:
            duration = stamp_times[stage_key] - prev_time
            if duration >= 3600:
                duration_str = f"{duration/3600:.1f}h"
            elif duration >= 60:
                duration_str = f"{duration/60:.1f}m"
            else:
                duration_str = f"{duration:.0f}s"

        if done:
            prev_time = stamp_times[stage_key]

        # Scan reports for this stage
        stage_report = _scan_stage_reports(run_dir, flow_type, stage_key)
        errors = stage_report['errors']
        warnings = stage_report['warnings']
        reports_count = len(stage_report['report_files']) + len(stage_report['log_files'])
        total_errors += errors
        total_warnings += warnings
        total_reports += reports_count

        # Collect metrics
        for k, v in stage_report['metrics'].items():
            all_metrics[f"{stage}/{k}"] = v
            # Keep last value per metric type for overall summary
            all_metrics[k] = v

        status = "completed" if done else "pending"
        icon = "[DONE]" if done else "[    ]"
        err_str = str(errors) if errors > 0 else "-"
        warn_str = str(warnings) if warnings > 0 else "-"
        rep_str = str(reports_count) if reports_count > 0 else "-"

        lines.append(f"  {icon}{stage:<19} {status:<12} {duration_str:<12} {err_str:<8} {warn_str:<8} {rep_str}")

    lines.append(f"  {'─'*70}")

    # Total duration
    if stamp_times:
        sorted_times = sorted(stamp_times.values())
        total_duration = sorted_times[-1] - sorted_times[0]
        if total_duration >= 3600:
            total_dur_str = f"{total_duration/3600:.1f}h"
        elif total_duration >= 60:
            total_dur_str = f"{total_duration/60:.1f}m"
        else:
            total_dur_str = f"{total_duration:.0f}s"
    else:
        total_dur_str = "-"

    lines.append(f"  {'TOTAL':<21} {info['stages_completed']}/{info['stages_total']:<10} {total_dur_str:<12} {total_errors:<8} {total_warnings:<8} {total_reports}")
    lines.append(f"")

    # ── Physical Design Metrics ──
    # Filter to show only the latest value per metric type (not per-stage)
    metric_keys = ['WNS', 'TNS', 'Setup Violations', 'Hold Violations',
                   'Area', 'Utilization', 'Cell Count', 'Net Count',
                   'DRC Violations', 'Power', 'Clock Period', 'Congestion']
    found_metrics = {k: all_metrics[k] for k in metric_keys if k in all_metrics}

    if found_metrics:
        lines.append(f"  {'─'*70}")
        lines.append(f"  PHYSICAL DESIGN METRICS")
        lines.append(f"  {'─'*70}")

        # Timing
        timing_metrics = {k: v for k, v in found_metrics.items()
                         if k in ('WNS', 'TNS', 'Setup Violations', 'Hold Violations', 'Clock Period')}
        if timing_metrics:
            lines.append(f"  Timing:")
            for k, v in timing_metrics.items():
                lines.append(f"    {k:<25} {v}")

        # Area & Utilization
        area_metrics = {k: v for k, v in found_metrics.items()
                       if k in ('Area', 'Utilization', 'Cell Count', 'Net Count')}
        if area_metrics:
            lines.append(f"  Area/Utilization:")
            for k, v in area_metrics.items():
                lines.append(f"    {k:<25} {v}")

        # Power
        power_metrics = {k: v for k, v in found_metrics.items()
                        if k in ('Power',)}
        if power_metrics:
            lines.append(f"  Power:")
            for k, v in power_metrics.items():
                lines.append(f"    {k:<25} {v}")

        # Physical
        phys_metrics = {k: v for k, v in found_metrics.items()
                       if k in ('DRC Violations', 'Congestion')}
        if phys_metrics:
            lines.append(f"  Physical:")
            for k, v in phys_metrics.items():
                lines.append(f"    {k:<25} {v}")

        lines.append(f"")
    else:
        lines.append(f"  {'─'*70}")
        lines.append(f"  PHYSICAL DESIGN METRICS")
        lines.append(f"  {'─'*70}")
        lines.append(f"  No metrics found in report files.")
        lines.append(f"  (Metrics are extracted from .rpt, .log, .txt files in work/<flow>/<stage>/)")
        lines.append(f"")

    # ── Report Files Found ──
    all_report_files = []
    for stage in stages:
        stage_key = stage   # config stage names are the node keys
        sr = _scan_stage_reports(run_dir, flow_type, stage_key)
        for rf in sr['report_files']:
            all_report_files.append((stage, rf))

    if all_report_files:
        lines.append(f"  {'─'*70}")
        lines.append(f"  REPORT FILES")
        lines.append(f"  {'─'*70}")
        for stage, rf in all_report_files:
            lines.append(f"    [{stage}] {rf}")
        lines.append(f"")

    # ── Validation Reports ──
    validation_files = []
    work_dir = os.path.join(run_dir, 'work')
    if os.path.exists(work_dir):
        for root, dirs, files in os.walk(work_dir):
            for f in files:
                if 'validation' in f.lower() and f.endswith(('.txt', '.rpt', '.tcl')):
                    validation_files.append(os.path.relpath(os.path.join(root, f), run_dir))

    if validation_files:
        lines.append(f"  {'─'*70}")
        lines.append(f"  VALIDATION REPORTS")
        lines.append(f"  {'─'*70}")
        for vf in validation_files:
            lines.append(f"    {vf}")
        lines.append(f"")

    lines.append(f"{'═'*75}")
    lines.append(f"")

    return '\n'.join(lines)


def cmd_run_status(args: argparse.Namespace) -> int:
    """Show detailed status of a specific run."""
    if not is_workspace_initialized():
        logger.error("Not inside a workspace. Change to a workarea directory first (one containing a .cbflow.env or any <PHASE>_run_<FLOW>_<name>/ dirs), or create a run with 'cbflow workspace create --config user_config.tcl'.")
        return 1

    run_dir = args.run
    if not os.path.isdir(run_dir):
        logger.error(f"Run directory not found: {run_dir}")
        logger.info("")
        logger.info("Available runs:")
        runs = [d for d in os.listdir('.') if os.path.isdir(d) and _is_run_dir(d)]
        for r in runs[:10]:
            logger.info(f"  {r}")
        return 1

    info = _get_run_info(run_dir)

    # Summary report mode
    if getattr(args, 'summary', False):
        report = _generate_run_summary(run_dir, info)
        print(report)

        # Save report to file
        report_dir = os.path.join(run_dir, 'logs')
        os.makedirs(report_dir, exist_ok=True)
        report_file = os.path.join(report_dir, f'summary_report_{datetime.now().strftime("%Y%m%d_%H%M%S")}.txt')
        with open(report_file, 'w') as f:
            f.write(report)
        logger.info(f"  Report saved: {report_file}")
        return 0

    logger.info("")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info(f"  Run Status: {run_dir}")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info("")
    logger.info(f"  Flow Type:      {info['flow_type']}")
    logger.info(f"  Design:         {info.get('design', 'N/A')}")
    logger.info(f"  Phase:          {info['phase']}")
    logger.info(f"  Release:        {info.get('release', 'N/A')}")
    logger.info(f"  Status:         {info['status']}")
    logger.info(f"  Last Activity:  {info['last_activity'] or 'N/A'}")
    logger.info(f"  Has Makefile:   {'Yes' if info['has_makefile'] else 'No'}")
    logger.info("")

    # Stage progress
    logger.info(f"  Stage Progress: {info['stages_completed']}/{info['stages_total']}")
    logger.info(f"  {'─'*55}")

    # Get stages from config
    try:
        from tcl_config_parser import get_flow_stages, get_subnodes
        stages = get_flow_stages(info['flow_type'])
    except Exception:
        stages = []

    # Get stage completion from RACE DB
    completed_stamps = set()
    stamp_times = {}
    try:
        from status_provider import StatusProvider
        provider = StatusProvider(run_dir)
        all_status = provider.get_all_status()
        for stage, sinfo in all_status.items():
            if sinfo.get('status') in ('DONE', 'BYPASSED', 'FORCE_VALIDATED'):
                completed_stamps.add(stage)
                ts = sinfo.get('timestamp', '')
                if ts:
                    try:
                        stamp_times[stage] = datetime.fromisoformat(ts).timestamp()
                    except (ValueError, TypeError):
                        pass
    except Exception:
        pass

    if stages:
        for stage in stages:
            # Config stage names are the node keys (e.g. synthesis1)
            stage_done = stage in completed_stamps
            stage_key = stage
            icon = "[DONE]" if stage_done else "[    ]"
            time_str = ""
            if stage_key in stamp_times:
                time_str = datetime.fromtimestamp(stamp_times[stage_key]).strftime('%Y-%m-%d %H:%M:%S')

            logger.info(f"  {icon} {stage:<25} {time_str}")

            # Show subnodes if --details
            if getattr(args, 'details', False):
                try:
                    subnodes = get_subnodes(info['flow_type'], stage)
                    for sub in subnodes:
                        sub_key = f"{stage_key}_{sub}"
                        sub_done = sub_key in completed_stamps
                        sub_icon = "[DONE]" if sub_done else "[    ]"
                        sub_time = ""
                        if sub_key in stamp_times:
                            sub_time = datetime.fromtimestamp(stamp_times[sub_key]).strftime('%H:%M:%S')
                        logger.info(f"       {sub_icon} {sub:<20} {sub_time}")
                except Exception:
                    pass
    else:
        # Fallback: just show stamps
        for stamp in sorted(completed_stamps):
            logger.info(f"  [DONE] {stamp}")

    # Log files summary
    logs_dir = os.path.join(run_dir, 'logs')
    if os.path.exists(logs_dir):
        log_files = [f for f in os.listdir(logs_dir) if f.endswith('.log')]
        if log_files:
            logger.info("")
            logger.info(f"  Log Files: {len(log_files)}")
            for lf in sorted(log_files)[-5:]:
                size = os.path.getsize(os.path.join(logs_dir, lf))
                size_str = f"{size/1024:.1f}KB" if size > 1024 else f"{size}B"
                logger.info(f"    {lf:<40} {size_str}")

    # Work directory contents - show stage subdirs under the flow's work dir
    flow_work_dir = os.path.join(run_dir, 'work', info['flow_type'])
    if os.path.exists(flow_work_dir):
        stage_dirs = [d for d in os.listdir(flow_work_dir) if os.path.isdir(os.path.join(flow_work_dir, d))]
        if stage_dirs:
            logger.info("")
            logger.info(f"  Work Directory: work/{info['flow_type']}/")
            for sd in sorted(stage_dirs):
                logger.info(f"    {sd}/")

    logger.info("")
    logger.info(f"  For full summary report: cbflow workspace status --run {run_dir} --summary")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info("")
    return 0


def cmd_clean(args: argparse.Namespace) -> int:
    """Clean all run directories."""
    if not is_workspace_initialized():
        logger.error("Not inside a workspace. Change to a workarea directory first (one containing a .cbflow.env or any <PHASE>_run_<FLOW>_<name>/ dirs), or create a run with 'cbflow workspace create --config user_config.tcl'.")
        return 1

    runs = [d for d in os.listdir('.') if os.path.isdir(d) and _is_run_dir(d)]

    if not runs:
        logger.info("No run directories found")
        return 0

    logger.warning(f"WARNING: This will permanently delete ALL run directories!")
    logger.info("")
    logger.info("The following directories will be deleted:")
    for r in runs:
        logger.info(f"  {r}")

    if not getattr(args, 'confirm', False):
        logger.info("")
        logger.info("Use --confirm to proceed with deletion")
        return 1

    import shutil
    for r in runs:
        shutil.rmtree(r)
        logger.info(f"Deleted: {r}")

    logger.info(f"All run directories cleaned")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    """Show workspace status, or detailed status of a specific run."""
    selected_run = getattr(args, 'run', None)

    # Resolve run selection (by number or name)
    if selected_run:
        runs = sorted([d for d in os.listdir('.') if os.path.isdir(d) and _is_run_dir(d)])
        # Check if user passed a number
        if selected_run.isdigit():
            idx = int(selected_run)
            if 1 <= idx <= len(runs):
                args.run = runs[idx - 1]
            else:
                logger.error(f"Invalid run number: {idx}. Valid range: 1-{len(runs)}")
                return 1
        else:
            args.run = selected_run
        if not hasattr(args, 'details'):
            args.details = True
        if not hasattr(args, 'summary'):
            args.summary = False
        return cmd_run_status(args)

    logger.info("")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info(f"  CBFlow Workspace Status")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info("")

    if is_workspace_initialized():
        env_vars = load_cbflow_env()
        project = env_vars.get('CBFLOW_PROJECT', env_vars.get('CBFLOW_PROJECT_NAME', 'unknown'))
        flow_type = env_vars.get('CBFLOW_FLOW_TYPE', 'unknown')
        block = env_vars.get('CBFLOW_BLOCK_NAME', 'unknown')
        release = env_vars.get('CBFLOW_RELEASE_VERSION', 'unknown')

        logger.info(f"  Workspace:  Initialized")
        logger.info(f"  Project:    {project}")
        logger.info(f"  Flow Type:  {flow_type}")
        logger.info(f"  Block:      {block}")
        logger.info(f"  Release:    {release}")
        logger.info(f"  Directory:  {os.getcwd()}")
        logger.info("")

        # List runs with numbered index
        runs = sorted([d for d in os.listdir('.') if os.path.isdir(d) and _is_run_dir(d)])

        if runs:
            logger.info(f"  Runs ({len(runs)}):")
            logger.info(f"  {'─'*65}")
            logger.info(f"  {'#':<4} {'Run':<35} {'Flow':<7} {'Progress':<12} {'Status'}")
            logger.info(f"  {'─'*65}")

            for i, run in enumerate(runs, 1):
                info = _get_run_info(run)
                progress = f"{info['stages_completed']}/{info['stages_total']}" if info['stages_total'] > 0 else "0/?"
                status_icon = {'completed': '[DONE]', 'in progress': '[RUN ]', 'not started': '[    ]'}.get(info['status'], '[????]')
                logger.info(f"  {i:<4} {run:<35} {info['flow_type']:<7} {progress:<12} {status_icon} {info['status']}")

            logger.info("")
            logger.info(f"  View run details:")
            logger.info(f"    cbflow workspace status --run 1")
            logger.info(f"    cbflow workspace status --run P0_run_PNR_run1")
        else:
            logger.info(f"  No runs found. Create one with:")
            logger.info(f"    cbflow workspace create --config <config_file>")
    else:
        logger.info(f"  Workspace: Not initialized")
        logger.info("")
        logger.info("  Create your first run with:")
        logger.info("    cbflow workspace create --config user_config.tcl")

    logger.info("")
    return 0


def cmd_update(args: argparse.Namespace) -> int:
    """Update workspace to new release."""
    if not is_workspace_initialized():
        logger.error("Not inside a workspace. Change to a workarea directory first (one containing a .cbflow.env or any <PHASE>_run_<FLOW>_<name>/ dirs), or create a run with 'cbflow workspace create --config user_config.tcl'.")
        return 1

    new_release = getattr(args, 'release', None)
    if not new_release:
        logger.error("Usage: cbflow workspace update --release <version>")
        available = get_available_versions()
        if available:
            logger.info(f"Available versions: {', '.join(available)}")
        return 1

    core_dir = get_cbflow_core_dir()
    flow_config_dir = os.path.join(core_dir, 'config', 'flow', new_release)

    if not os.path.exists(flow_config_dir):
        logger.error(f"Release {new_release} not found")
        available = get_available_versions()
        if available:
            logger.info(f"Available versions: {', '.join(available)}")
        return 1

    # Update .cbflow.env with new release
    env_vars = load_cbflow_env()
    old_release = env_vars.get('CBFLOW_RELEASE_VERSION', 'unknown')

    logger.info(f"Updating workspace from {old_release} to {new_release}")

    # Backup current env
    backup_dir = '.backup'
    os.makedirs(backup_dir, exist_ok=True)
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_file = os.path.join(backup_dir, f'.cbflow.env.backup.{timestamp}')

    import shutil
    shutil.copy('.cbflow.env', backup_file)
    logger.info(f"Backed up to {backup_file}")

    # Update version in env file
    with open('.cbflow.env', 'r') as f:
        content = f.read()

    content = content.replace(f'CBFLOW_RELEASE_VERSION="{old_release}"', f'CBFLOW_RELEASE_VERSION="{new_release}"')
    content = content.replace(f'FLOW_CONFIG_VERSION="{old_release}"', f'FLOW_CONFIG_VERSION="{new_release}"')
    content = content.replace(f'/flow/{old_release}/', f'/flow/{new_release}/')

    with open('.cbflow.env', 'w') as f:
        f.write(content)

    logger.info(f"Workspace updated to {new_release}")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    """Validate workspace configuration."""
    from validation_cmd import cmd_validate_workspace
    return cmd_validate_workspace(args)


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow workspace',
        description='CBFlow - Workspace Management',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Quick Reference:

  Create Runs:
    cbflow workspace template --flow SYNTH_PNR > user_config.tcl
    cbflow workspace create --config user_config.tcl
    cbflow workspace create --config user_config.tcl --force

  Monitor:
    cbflow workspace status                          Overview with all runs
    cbflow workspace status --run 1                  Detailed status of run #1
    cbflow workspace status --run 2 --summary        Full report with metrics
    cbflow workspace list-runs                       List runs with progress
    cbflow workspace validate                        Check workspace config

  Manage:
    cbflow workspace update --release v2.0.0         Update to new release
    cbflow workspace clean --confirm                 Delete all runs
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # create command (create a new run)
    _fmt = argparse.RawDescriptionHelpFormatter
    create_parser = subparsers.add_parser('create', help='Create a new run',
        formatter_class=_fmt,
        description="""Create a new run from a user configuration file.

Usage:
  cbflow workspace create --config <config_file> [--force]

Arguments:
  --config, -c    Path to user configuration TCL file (required)
  --force,  -f    Recreate if run directory already exists

Examples:
  cbflow workspace create --config user_config.tcl
  cbflow workspace create --config user_config_fp.tcl
  cbflow workspace create --config user_config_synth.tcl --force

The config file defines flow type, design name, run name, and phase.
Generate a template with: cbflow workspace template --flow <FLOW>""")
    create_parser.add_argument('--config', '-c',
                              help='User configuration TCL file (e.g., user_config.tcl)')
    create_parser.add_argument('--force', '-f', action='store_true',
                              help='Force recreate if run directory already exists '
                                   '(DESTRUCTIVE: rmtree the existing run)')
    # Separate flag for restricted-vars confirmation so batch/CI jobs
    # can accept the restricted-overrides prompt WITHOUT also enabling
    # the --force rmtree of an existing run dir. Pre-fix: the prompt
    # error message told users to re-run with --force, which conflated
    # 'accept restricted overrides' with 'destroy the existing run'.
    create_parser.add_argument('--accept-restricted', '--yes', dest='accept_restricted',
                              action='store_true',
                              help='Accept restricted-variable overrides in user_config '
                                   'without the interactive prompt (safe for CI/batch; '
                                   'does NOT recreate existing run — use --force for that)')

    # template command
    template_parser = subparsers.add_parser('template', help='Generate user_config.tcl template',
        formatter_class=_fmt,
        description="""Generate a user_config.tcl template for a specific flow type.

Usage:
  cbflow workspace template --flow SYNTH_PNR
  cbflow workspace template --flow FP --output user_config_fp.tcl

Examples:
  cbflow workspace template --flow SYNTH_PNR > user_config.tcl
  cbflow workspace template --flow ECO --output user_config_eco.tcl
  cbflow workspace template --flow FP""")
    template_parser.add_argument('--flow', '-t', required=True,
                                help='Flow type (use cbflow workspace template --flow <TAB> for available types)')
    template_parser.add_argument('--project', '-p', default=None,
                                help='Project name — must match config/project/<name>/. '
                                     'Phase is taken from that project config.')
    template_parser.add_argument('--output', '-o', default=None,
                                help='Output file (default: print to stdout)')

    # list-runs command
    subparsers.add_parser('list-runs', help='List all runs')

    # run-status command
    status_parser = subparsers.add_parser('run-status', help='Show run status')
    status_parser.add_argument('--run', '-r', required=True, help='Run directory name')
    status_parser.add_argument('--details', '-d', action='store_true', help='Show detailed status')
    status_parser.add_argument('--summary', action='store_true',
                              help='Generate full summary report')

    # status command
    ws_status_parser = subparsers.add_parser('status', help='Show workspace status')
    ws_status_parser.add_argument('--run', '-r', help='Show detailed status of a specific run (name or number)')
    ws_status_parser.add_argument('--summary', action='store_true',
                                 help='Generate full summary report (timing, errors, metrics)')

    # update command
    update_parser = subparsers.add_parser('update', help='Update workspace to new release')
    update_parser.add_argument('--release', '-r', required=True, help='New release version')

    # clean command
    clean_parser = subparsers.add_parser('clean', help='Clean all run directories')
    clean_parser.add_argument('--confirm', action='store_true', help='Confirm deletion')

    # validate command
    subparsers.add_parser('validate', help='Validate workspace configuration')

    # Backward compatibility aliases
    subparsers.add_parser('list', help='Alias for list-runs')

    return parser


def main() -> int:
    """Main entry point."""
    from logging_config import print_logo
    print_logo()

    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    # Command dispatch (with aliases)
    commands = {
        'create': cmd_create,
        'template': cmd_template,
        'list-runs': cmd_list_runs,
        'list': cmd_list_runs,  # alias
        'run-status': cmd_run_status,
        'status': cmd_status,
        'update': cmd_update,
        'clean': cmd_clean,
        'validate': cmd_validate,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
