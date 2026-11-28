#!/usr/bin/env python3
"""
CBFlow Start Run - Python Implementation

Creates a new run directory with environment files, configuration,
and Makefile. Replaces the TCL start_run.tcl script.

Reuses tcl_config_parser.py for all TCL file parsing.
"""

import os
import re
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from logging_config import get_logger
from tcl_config_parser import (
    _parse_tcl_string, _parse_tcl_list,
    get_flow_types, get_phases, _get_config_root, _get_flow_config_version,
    is_merged_flow, parse_merged_flow
)
from cbflow_config import preview_user_config

logger = get_logger('cbflow.start_run')

# Required environment variables (set by workspace init)
REQUIRED_ENV_VARS = [
    'CONFIG_ROOT', 'SCRIPTS_ROOT', 'PROJECT_ROOT',
    'PROJECT_NAME', 'PROJECT_VERSION',
    'UTILITIES_VERSION',
]

# Technology vars are resolved from project config, not required in env
OPTIONAL_TECH_VARS = [
    'TECHNOLOGY_VENDOR', 'TECHNOLOGY_NODE', 'TECHNOLOGY_VERSION',
]

WORKSPACE_VARS = [
    'CBFLOW_FLOW_TYPE', 'CBFLOW_PROJECT_NAME',
]

# Version vars to include in run environment files
VERSION_VARS = [
    'FLOW_CONFIG_VERSION', 'GENERATION_VERSION',
    'MAKEFILE_COMMANDS_VERSION', 'NODE_MANAGEMENT_VERSION',
    'PROJECT_CONFIG_VERSION', 'PROJECT_VERSION',
    'TECH_CONFIG_VERSION', 'TECHNOLOGY_VERSION', 'UTILITIES_VERSION',
    'VALIDATION_VERSION',
]


# ── TCL Environment Parsing ─────────────────────────────────────────────────

def load_tcl_env_vars(tcl_file: str) -> Dict[str, str]:
    """Parse .cbflow.tcl to extract environment variables.

    Handles both formats:
      set ::env(VAR) "value"     -> env vars
      set CBFLOW_FLOW_TYPE "FP"  -> plain TCL vars (treated as env-like)
    """
    env_vars = {}
    if not os.path.exists(tcl_file):
        return env_vars

    with open(tcl_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            # Match: set ::env(VAR) "value"
            m = re.match(r'set\s+::env\((\w+)\)\s+"([^"]*)"', line)
            if m:
                env_vars[m.group(1)] = m.group(2)
                continue

            # Match: set CBFLOW_VAR "value" (plain TCL vars)
            m = re.match(r'set\s+(CBFLOW_\w+)\s+"([^"]*)"', line)
            if m:
                env_vars[m.group(1)] = m.group(2)

    return env_vars


# ── Validation ───────────────────────────────────────────────────────────────

def _validate_env_vars(env: Dict[str, str]) -> List[str]:
    """Check required environment variables are present."""
    missing = []
    for var in REQUIRED_ENV_VARS:
        if not env.get(var):
            missing.append(var)
    for var in WORKSPACE_VARS:
        if not env.get(var):
            missing.append(var)
    return missing


# ── User Config Parsing ──────────────────────────────────────────────────────

def _parse_user_config(config_file: str) -> Dict[str, str]:
    """Read flow(...) / project(...) atoms from a user-supplied user_config.tcl.

    Used at workspace-create time, before a run directory exists — at that
    point the cascade resolver can't run. `preview_user_config` shells out to
    tclsh to evaluate the file in isolation so escapes and `set` semantics
    behave exactly as they will inside the cascade later.
    """
    return preview_user_config(config_file)


def _validate_user_config(user_config: Dict[str, str], env: Dict[str, str]
                          ) -> Tuple[bool, str, str, str, str]:
    """Validate user config.

    Returns: (valid, flow_type, run_name, design_name, phase)
    Flow type comes from user_config.tcl (no workspace locking).
    """
    # Flow type from user_config (primary) or env (fallback)
    flow_type = user_config.get('flow(type)', '').upper()
    if not flow_type:
        flow_type = env.get('CBFLOW_FLOW_TYPE', '').upper()

    # Validate flow type (single or merged)
    valid_flows = get_flow_types()
    if flow_type not in valid_flows and not is_merged_flow(flow_type):
        logger.error(f"  Error: Invalid flow type '{flow_type}'")
        logger.error(f"  Valid types: {', '.join(valid_flows)}")
        logger.error(f"  Merged flows: e.g., SYNTH_FP, SYNTH_FP_PNR")
        return False, '', '', '', ''

    # Run name (required)
    run_name = user_config.get('flow(run_name)', '')
    if not run_name:
        logger.error("  Error: flow(run_name) not set in user config")
        return False, '', '', '', ''

    # Reject run_name values that would escape the workarea when
    # composed as `<phase>_run_<flow>_<run_name>` and fed to
    # shutil.rmtree(--force). A copy-pasted template with
    # run_name="../../home/user/important" would otherwise wipe an
    # unrelated directory. Keep the allowlist tight: ASCII identifier
    # chars + dash/dot. Same posture applied to phase just below.
    import re as _re_name
    _NAME_RE = _re_name.compile(r'^[A-Za-z0-9_.-]+$')
    if not _NAME_RE.match(run_name):
        logger.error(
            f"  Error: flow(run_name) {run_name!r} contains characters "
            f"outside [A-Za-z0-9_.-]. Rename to a plain identifier "
            f"(no slashes, no '..', no whitespace).")
        return False, '', '', '', ''

    # Design name from user_config (primary source), else the workspace's
    # block. No project-name / literal default — a run needs a real block.
    design_name = user_config.get('flow(design_name)', '') or env.get('CBFLOW_BLOCK_NAME', '')
    if not design_name:
        logger.error("  Error: flow(design_name) not set in user config "
                     "(and no CBFLOW_BLOCK_NAME in the workspace env)")
        return False, '', '', '', ''

    # Phase resolution — three-tier fallback:
    #   1. user config: project(phase) or flow(phase) (explicit override)
    #   2. project config: project(current_phase) (single source of truth)
    #   (unresolved -> error; phases are project-defined, no default)
    # Templates deliberately drop project(phase) so the project-level
    # current_phase is authoritative. Reading it here honors bumblebee's
    # non-P0 phase scheme (LC1/LC2/...) instead of silently mis-tagging runs.
    phase = user_config.get('project(phase)', user_config.get('flow(phase)', ''))
    if not phase:
        project_name = user_config.get('project(name)', '')
        if project_name:
            # Walk the project config files (global identity, then every
            # discipline overlay — later wins) via the shared registry
            # helper; PROJECT_CONFIG_VERSION is required.
            from core import registry
            try:
                phase = registry.project_value(project_name, 'current_phase') or ''
            except registry.RegistryError as e:
                logger.error(f"  Error: {e}")
                return False, '', '', '', ''
    if not phase:
        # No user_config phase, no project(current_phase), no readable
        # project config: phases are project-defined, so there is no
        # built-in default to fall back to.
        logger.error(
            "project(current_phase) could not be resolved from user_config, "
            "project config, or env. Set project(current_phase) in the "
            "project config or project(phase) in user_config.tcl.")
        return False, '', '', '', ''

    # Same path-traversal defense for phase — composed into the run
    # directory name below.
    if not _NAME_RE.match(phase):
        logger.error(
            f"  Error: phase {phase!r} contains characters outside "
            f"[A-Za-z0-9_.-]. Fix project(current_phase) in project_config.tcl.")
        return False, '', '', '', ''

    return True, flow_type, run_name, design_name, phase


# ── Directory Config Parsing ─────────────────────────────────────────────────

def _parse_dir_config(dir_config_path: str) -> Dict[str, List[str]]:
    """Parse dir_config.tcl for directory structures per flow type.

    Handles multi-line blocks like:
        set directory(FP) {
            ".stamps"
            "logs"
            "work/FP"
        }
    """
    if not os.path.exists(dir_config_path):
        return {}

    with open(dir_config_path, 'r') as f:
        content = f.read()

    result = {}
    # Match: set directory(FLOW_TYPE) { ... } across multiple lines
    pattern = r'set\s+directory\((\w+)\)\s*\{([^}]*)\}'
    for match in re.finditer(pattern, content, re.DOTALL):
        flow_type = match.group(1)
        block = match.group(2)
        # Extract quoted strings from the block
        dirs = re.findall(r'"([^"]+)"', block)
        result[flow_type] = dirs

    return result


# ── Directory Creation ───────────────────────────────────────────────────────

def _create_directory_structure(run_dir: str, flow_type: str,
                                dir_config: Dict[str, List[str]]) -> bool:
    """Create the run directory with flow-specific subdirectories."""
    # Handle merged flows (e.g., SYNTH_FP → create work/SYNTH/ + work/FP/)
    sub_flows = parse_merged_flow(flow_type)
    if sub_flows:
        # Base dirs (common to all)
        for d in ['logs', 'setup', 'work']:
            os.makedirs(os.path.join(run_dir, d), exist_ok=True)
        # Per-flow work dirs
        for sf in sub_flows:
            os.makedirs(os.path.join(run_dir, 'work', sf), exist_ok=True)
        return True

    # Single flow — layout must be declared in the discipline's dir_config.tcl
    dirs = dir_config.get(flow_type)
    if not dirs:
        logger.error(f"  Error: directory({flow_type}) is not set in dir_config.tcl "
                     f"({flow_type}'s discipline <DISC>/config/flow/<ver>/dir_config.tcl)")
        return False

    for d in dirs:
        full_path = os.path.join(run_dir, d)
        os.makedirs(full_path, exist_ok=True)

    return True


# ── Environment File Generation ──────────────────────────────────────────────

def _cbflow_root_env_vars() -> List[str]:
    """Framework root env vars persisted per run: CBFLOW_ROOT,
    CBFLOW_GLOBAL_DIR and one root var per discipline in flow(disciplines)
    (CBFLOW_CORE_DIR for PD, CBFLOW_<DISC>_DIR otherwise)."""
    from core import registry
    return ['CBFLOW_ROOT', 'CBFLOW_GLOBAL_DIR'] + \
        [registry.discipline_env_var(d) for d in registry.flow_disciplines()]


def _generate_run_tcl_env(run_dir: str, env: Dict[str, str],
                          flow_type: str, design_name: str,
                          run_name: str, phase: str) -> bool:
    """Generate .run.cbflow.tcl and .run.cnflow.tcl (identical TCL env files)."""
    run_dir_abs = os.path.abspath(run_dir)
    timestamp = datetime.now().strftime('%a %b %d %H:%M:%S %Z %Y')

    flow_dir = env.get('FLOW_DIR', '')
    if not flow_dir:
        config_root = env.get('CONFIG_ROOT', '')
        flow_dir = os.path.dirname(config_root) if config_root else ''

    lines = []
    lines.append('#!/usr/bin/env tclsh')
    lines.append(f'# CBFlow Native TCL Run-Specific Environment')
    lines.append(f'# Generated: {timestamp}')
    lines.append('')
    lines.append('# Run-Specific Information')
    lines.append(f'set ::env(CBFLOW_RUN_DIR) "{run_dir_abs}"')
    lines.append(f'set ::env(CBFLOW_FLOW_TYPE) "{flow_type}"')
    lines.append(f'set ::env(CBFLOW_DESIGN_NAME) "{design_name}"')
    lines.append(f'set ::env(CBFLOW_RUN_NAME) "{run_name}"')
    lines.append(f'set ::env(CBFLOW_PROJECT_PHASE) "{phase}"')
    lines.append('')
    lines.append('# Workspace-Locked Variables (from init_workspace)')
    lines.append(f'set ::env(CBFLOW_PROJECT_NAME) "{env.get("CBFLOW_PROJECT_NAME", env.get("PROJECT_NAME", ""))}"')
    lines.append(f'set ::env(CBFLOW_BLOCK_NAME) "{env.get("CBFLOW_BLOCK_NAME", design_name)}"')
    lines.append('')
    lines.append('# Core Configuration Paths')
    lines.append(f'set ::env(CONFIG_ROOT) "{env.get("CONFIG_ROOT", "")}"')
    lines.append(f'set ::env(SCRIPTS_ROOT) "{env.get("SCRIPTS_ROOT", "")}"')
    lines.append(f'set ::env(PROJECT_ROOT) "{env.get("PROJECT_ROOT", "")}"')
    lines.append(f'set ::env(FLOW_DIR) "{flow_dir}"')
    # cbflow_global cascade — resolvers use these to find the global
    # config layer + sibling disciplines. Persisted per-run so the run's
    # shell + subprocesses see the same view the launcher had.
    for k in _cbflow_root_env_vars():
        v = env.get(k, '')
        if v:
            lines.append(f'set ::env({k}) "{v}"')
    lines.append('')
    lines.append('# Project Configuration')
    lines.append(f'set ::env(PROJECT_NAME) "{env.get("PROJECT_NAME", "")}"')
    lines.append(f'set ::env(PROJECT_VERSION) "{env.get("PROJECT_VERSION", "")}"')
    lines.append('')
    lines.append('# Technology Configuration')
    lines.append(f'set ::env(TECHNOLOGY_VENDOR) "{env.get("TECHNOLOGY_VENDOR", "")}"')
    lines.append(f'set ::env(TECHNOLOGY_NODE) "{env.get("TECHNOLOGY_NODE", "")}"')
    lines.append(f'set ::env(TECHNOLOGY_VERSION) "{env.get("TECHNOLOGY_VERSION", "")}"')
    lines.append(f'set ::env(TECH_NAME) "{env.get("TECH_NAME", "")}"')
    lines.append(f'set ::env(TECH_VERSION) "{env.get("TECH_VERSION", "")}"')
    lines.append(f'set ::env(SETUP_VERSION) "{env.get("SETUP_VERSION", "")}"')
    lines.append('')
    lines.append('# Release Information')
    lines.append(f'set ::env(CBFLOW_RELEASE_VERSION) "{env.get("CBFLOW_RELEASE_VERSION", "")}"')
    lines.append('')
    lines.append('# Component Versions (from release)')
    for var in VERSION_VARS:
        val = env.get(var, '')
        if val:
            lines.append(f'set ::env({var}) "{val}"')
    lines.append('')
    lines.append('# Utilities Path Configuration')
    utils_version = env.get('UTILITIES_VERSION', '')
    utils_tcl = os.path.join(flow_dir, 'utils', 'utilities', utils_version, 'utils.tcl')
    lines.append(f'set ::env(UTILS_TCL) "{utils_tcl}"')
    lines.append('')
    lines.append('# Run-specific variables from user configuration')
    lines.append('# Additional run-specific variables can be added here')
    lines.append('')

    content = '\n'.join(lines)

    # Write both files (identical content)
    for filename in ['.run.cnflow.tcl', '.run.cbflow.tcl']:
        with open(os.path.join(run_dir, filename), 'w') as f:
            f.write(content)

    return True


def _generate_run_shell_env(run_dir: str, env: Dict[str, str],
                            flow_type: str, design_name: str,
                            run_name: str, phase: str) -> bool:
    """Generate .run.cbflow.env (shell format)."""
    run_dir_abs = os.path.abspath(run_dir)
    timestamp = datetime.now().strftime('%a %b %d %H:%M:%S %Z %Y')

    flow_dir = env.get('FLOW_DIR', '')
    if not flow_dir:
        config_root = env.get('CONFIG_ROOT', '')
        flow_dir = os.path.dirname(config_root) if config_root else ''

    lines = []
    lines.append(f'# CBFlow Run Environment')
    lines.append(f'# Generated: {timestamp}')
    lines.append('')
    lines.append('# Run Information')
    lines.append(f'export CBFLOW_RUN_DIR="{run_dir_abs}"')
    lines.append(f'export CBFLOW_FLOW_TYPE="{flow_type}"')
    lines.append(f'export CBFLOW_DESIGN_NAME="{design_name}"')
    lines.append(f'export CBFLOW_RUN_NAME="{run_name}"')
    lines.append(f'export CBFLOW_PROJECT_PHASE="{phase}"')
    lines.append('')
    lines.append('# Workspace-Locked Variables (from init_workspace)')
    lines.append(f'export CBFLOW_PROJECT_NAME="{env.get("CBFLOW_PROJECT_NAME", env.get("PROJECT_NAME", ""))}"')
    lines.append(f'export CBFLOW_BLOCK_NAME="{env.get("CBFLOW_BLOCK_NAME", design_name)}"')
    lines.append('')
    lines.append('# Core Configuration Paths')
    lines.append(f'export CONFIG_ROOT="{env.get("CONFIG_ROOT", "")}"')
    lines.append(f'export SCRIPTS_ROOT="{env.get("SCRIPTS_ROOT", "")}"')
    lines.append(f'export PROJECT_ROOT="{env.get("PROJECT_ROOT", "")}"')
    lines.append(f'export FLOW_DIR="{flow_dir}"')
    # cbflow_global utils-refactor: discipline-aware resolvers (race_engine,
    # workspace_cmd, handlers) read CBFLOW_<DISC>_DIR to find per-discipline
    # cmds + configs. Persist them per-run so the handler shell sees the
    # same view the launcher had.
    for _k in _cbflow_root_env_vars():
        _v = env.get(_k, '')
        if _v:
            lines.append(f'export {_k}="{_v}"')
    lines.append('')
    lines.append('# Project Configuration')
    lines.append(f'export PROJECT_NAME="{env.get("PROJECT_NAME", "")}"')
    lines.append(f'export PROJECT_VERSION="{env.get("PROJECT_VERSION", "")}"')
    lines.append('')
    lines.append('# Technology Configuration')
    lines.append(f'export TECHNOLOGY_VENDOR="{env.get("TECHNOLOGY_VENDOR", "")}"')
    lines.append(f'export TECHNOLOGY_NODE="{env.get("TECHNOLOGY_NODE", "")}"')
    lines.append(f'export TECHNOLOGY_VERSION="{env.get("TECHNOLOGY_VERSION", "")}"')
    lines.append(f'export TECH_NAME="{env.get("TECH_NAME", "")}"')
    lines.append(f'export TECH_VERSION="{env.get("TECH_VERSION", "")}"')
    lines.append(f'export SETUP_VERSION="{env.get("SETUP_VERSION", "")}"')
    lines.append('')
    lines.append('# Release Information')
    lines.append(f'export CBFLOW_RELEASE_VERSION="{env.get("CBFLOW_RELEASE_VERSION", "")}"')
    lines.append('')
    lines.append('# Component Versions (from release)')
    for var in VERSION_VARS:
        val = env.get(var, '')
        if val:
            lines.append(f'export {var}="{val}"')
    lines.append('')

    with open(os.path.join(run_dir, '.run.cbflow.env'), 'w') as f:
        f.write('\n'.join(lines))

    return True


# ── Makefile Generation ──────────────────────────────────────────────────────

def _verify_engine_dag(run_dir: str, flow_type: str, env: Dict[str, str]) -> bool:
    """Verify RACE DAG can be built for this run."""
    try:
        from race_engine import DagBuilder
        builder = DagBuilder(run_dir, flow_type, env)
        jobs, stages = builder.build()
        if jobs and stages:
            logger.info(f"  RACE DAG: {len(jobs)} jobs, {len(stages)} stages")
            return True
        else:
            logger.warning(f"  RACE DAG build returned empty")
            return False
    except Exception as e:
        logger.warning(f"  RACE DAG verification failed: {e}")
        return False


def _preflight_launch_bins(user_config: Dict[str, str],
                           env: Dict[str, str]) -> Tuple[bool, str]:
    """Pre-flight: verify launch-mode binaries + display are usable.

    Prior behavior: if user_config declared `flow(use_lsf) "true"` but
    `bsub` wasn't in PATH (LSF not installed on the box), workspace_create
    succeeded and the failure only surfaced deep inside a stage when
    `submit_job` tried `exec bsub …` — buried in a per-node log and easy
    to miss. Same for `flow(use_xterm) "true"` without xterm or $DISPLAY.

    Three gates:
      1. use_lsf=true  → `bsub` (or $CBFLOW_BSUB_CMD) must be on PATH.
      2. use_xterm=true → `xterm` must be on PATH.
      3. use_xterm=true → $DISPLAY must be set and non-empty (xterm needs
         an X server to connect to; otherwise it exits immediately with no
         useful output and the enclosing run looks "clean" with empty logs).

    Returns (ok, error_block). error_block is a formatted multi-line
    diagnosis suitable for both terminal (stderr) and workspace log.
    """
    import shutil
    import re as _re

    # Framework defaults come from the resolved flow_registry.tcl (the
    # project baseline cascade). Reading them here (instead of hardcoding
    # 'false') is critical: the shipped default for use_xterm is TRUE, so
    # templates that omit the key still land in xterm mode. A missing
    # registry key is an error, never a guessed default.
    import cbflow_config as _cfgmod
    from tcl_config_parser import _resolved, _baseline_flow
    _base_cfg = _resolved(_baseline_flow(), run_dir=None)

    # Truthy / falsy value sets — must match utils.tcl is_true/is_false
    # so the preflight sees the same boolean the runtime will. Pre-fix
    # the preflight accepted only literal 'true'/'false'; a user_config
    # with `set flow(use_xterm) "0"` was mapped to the registry default
    # (true), causing workspace create to fail with "DISPLAY unset" on
    # headless CI even though the runtime treats "0" as false.
    _TRUTHY = {'true', '1', 'yes', 'on'}
    _FALSY  = {'false', '0', 'no', 'off'}

    def _norm(raw):
        # Strip quotes AND Tcl braces so `{true}` / `"true"` / `true`
        # all normalize. lower() for case-insensitive compare.
        v = raw.strip().strip('"').strip('{}').lower()
        if v in _TRUTHY:
            return 'true'
        if v in _FALSY:
            return 'false'
        return None

    def _resolve(key):
        raw = user_config.get(key, '')
        src = 'user_config.tcl'
        if not raw.strip():
            raw = _cfgmod.require(_base_cfg, key)
            src = 'flow_registry.tcl'
        v = _norm(raw)
        if v is None:
            raise ValueError(f"{key} = {raw!r} in {src} is not a boolean "
                             f"(expected one of {sorted(_TRUTHY | _FALSY)})")
        return v

    try:
        # test_mode short-circuit — in test runs we don't need bsub/xterm/DISPLAY.
        if _resolve('flow(test_mode)') == 'true':
            return True, ''

        use_lsf = _resolve('flow(use_lsf)')
        use_xterm = _resolve('flow(use_xterm)')
    except (ValueError, KeyError) as e:
        return False, f"Workspace create blocked — {e}"

    problems = []  # list of (headline, [fix lines])

    if use_lsf == 'true':
        _bsub_raw = os.environ.get('CBFLOW_BSUB_CMD', 'bsub').strip()
        _parts = _bsub_raw.split() if _bsub_raw else []
        bsub_cmd = _parts[0] if _parts else 'bsub'
        if not shutil.which(bsub_cmd):
            problems.append((
                "flow(use_lsf)=true but '{}' is not in PATH.".format(bsub_cmd),
                ["Every stage would die inside submit_job when it tried to "
                 "exec '{}'.".format(bsub_cmd),
                 "Fix one of:",
                 "  1. Install LSF client tools so '{}' is on PATH.".format(bsub_cmd),
                 "  2. Set flow(use_lsf) \"false\" in user_config.tcl.",
                 "  3. Export CBFLOW_BSUB_CMD=/abs/path/to/your/bsub-wrapper."]))

    if use_xterm == 'true':
        if not shutil.which('xterm'):
            problems.append((
                "flow(use_xterm)=true but 'xterm' is not in PATH.",
                ["Interactive subnodes would fail to launch — the run would "
                 "complete in seconds with empty logs.",
                 "Fix one of:",
                 "  1. Install xterm (apt/yum install xterm, brew install xterm).",
                 "  2. Set flow(use_xterm) \"false\" in user_config.tcl.",
                 "  3. Set flow(test_mode) \"true\" if this is a stub run."]))
        display = os.environ.get('DISPLAY', '').strip()
        if not display:
            problems.append((
                "flow(use_xterm)=true but $DISPLAY is empty/unset.",
                ["xterm needs an X server to connect to. Without $DISPLAY it "
                 "exits immediately and the run looks 'clean' with no log output.",
                 "Fix one of:",
                 "  1. Export DISPLAY=<host>:0 (or :0 on a local X session).",
                 "  2. Set flow(use_xterm) \"false\" in user_config.tcl.",
                 "  3. Set flow(test_mode) \"true\" if this is a stub run."]))

    if not problems:
        return True, ''

    # Format for both terminal + log consumption.
    lines = []
    lines.append("Workspace create blocked — launch-mode preflight failed")
    lines.append("=" * 60)
    for i, (headline, fixes) in enumerate(problems, 1):
        lines.append("")
        lines.append("[{}] {}".format(i, headline))
        for ln in fixes:
            lines.append("    " + ln)
    lines.append("")
    lines.append("Why this check exists: the symptoms it prevents are")
    lines.append("  - run completes in seconds",
                 )
    lines.append("  - no useful log output at the stage level")
    lines.append("  - stages show as DONE but no real work ran")
    return False, "\n".join(lines)


def _write_preflight_fail_log(run_dir: str, user_config: Dict[str, str],
                              env: Dict[str, str], err_block: str) -> str:
    """Persist a preflight-failure log so the diagnosis survives even if
    the caller cleans up the partial run directory. Writes two copies:

      1. Inside the run dir at logs/workspace_create.log (if dir still
         exists after the caller's cleanup decision).
      2. Alongside the run dir at <run_dir>.preflight_failed.log — this
         one is immune to rmtree(run_dir) and is what the user will see
         if they look at the workarea listing.

    Returns the external log path.
    """
    from datetime import datetime
    import socket

    external = os.path.abspath(run_dir).rstrip('/') + '.preflight_failed.log'
    header = [
        "=" * 70,
        "  CBflow Workspace Create — PREFLIGHT FAILURE",
        "=" * 70,
        "  Timestamp: {}".format(datetime.now().strftime('%Y-%m-%d %H:%M:%S')),
        "  User:      {}".format(os.environ.get('USER', 'unknown')),
        "  Hostname:  {}".format(socket.gethostname()),
        "  Run dir:   {}".format(os.path.abspath(run_dir)),
        "",
    ]
    footer = [
        "",
        "─" * 70,
        "  Relevant user_config flags",
        "─" * 70,
        "",
    ]
    for key in ('flow(use_lsf)', 'flow(use_xterm)', 'flow(test_mode)'):
        footer.append("  {} = {}".format(key, user_config.get(key, '(unset)')))
    footer += [
        "",
        "  CBFLOW_BSUB_CMD = {}".format(os.environ.get('CBFLOW_BSUB_CMD', '(unset)')),
        "  DISPLAY         = {}".format(os.environ.get('DISPLAY', '(unset)')),
        "",
    ]
    body = "\n".join(header + [err_block] + footer)

    # External log — always written, survives cleanup. Must survive even
    # on POSIX/C locale (default ASCII encoding would UnicodeEncodeError
    # on the box-drawing chars in the body).
    try:
        with open(external, 'w', encoding='utf-8') as f:
            f.write(body)
    except OSError as _ext_err:
        logger.debug(f'external log write failed ({external}): {_ext_err}')

    # Internal log — best-effort, same content.
    try:
        logs_dir = os.path.join(run_dir, 'logs')
        os.makedirs(logs_dir, exist_ok=True)
        with open(os.path.join(logs_dir, 'workspace_create.log'),
                  'w', encoding='utf-8') as f:
            f.write(body)
    except OSError as _int_err:
        logger.debug(f'internal log write failed: {_int_err}')

    return external


def _initialize_race_db(run_dir: str, flow_type: str, env: Dict[str, str]) -> Tuple[bool, str]:
    """Initialize the RACE status DB for this run and drop the `.race_db_pointer`
    file in the run dir.

    Prior behavior: workspace create only laid out `setup/` + env files; the
    DB was created lazily by the first `cbflow run all` call. That left a
    window where the run directory looked valid on disk (setup/, work/,
    logs/) but had no DB — so `cbflow run status`, dashboards, and any
    tool relying on `.race_db_pointer` would silently no-op or error out.
    Users would then discover it much later.

    Now workspace create hard-fails if the DB can't be initialized. The
    caller returns a non-zero exit and cleans up the partially-created run
    directory (see cmd_create in workspace_cmd.py — this function's False
    return is the trigger).

    Returns (ok, error_msg).
    """
    try:
        from race_engine import StatusDB, RaceEngine

        # Resolve db_base_path via the same mechanism the engine uses at
        # `run all` time so both agree on where the DB lives.
        eng = RaceEngine(run_dir, flow_type, env)
        db_base = eng._resolve_db_path()

        project_name = env.get('CBFLOW_PROJECT_NAME', '')
        run_name = env.get('CBFLOW_RUN_NAME', os.path.basename(run_dir))
        user = os.environ.get('USER', 'unknown')

        # A fresh run dir has no pointer, so StatusDB derives the DB name from
        # the run dir path. A DB left by an earlier run at the same path (run
        # dir deleted, DB still in the race area) would be adopted with all its
        # job states — the engine then skips stages that never ran here.
        # Archive it instead (renamed, not deleted).
        # Same domain as RaceEngine.initialize (flow(discipline,<FLOW>)) so
        # both agree on the DB location; an unmapped flow raises.
        from core import registry
        domain = registry.flow_discipline(flow_type)
        stale = os.path.join(db_base, project_name, domain, flow_type,
                             StatusDB.db_filename(run_dir, user))
        if os.path.exists(stale):
            archived = f"{stale}.stale-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
            os.rename(stale, archived)
            # WAL side files go with it: a new DB at this path that opens the
            # old -shm / -wal fails with "disk I/O error".
            for _side in ('-wal', '-shm'):
                if os.path.exists(stale + _side):
                    os.rename(stale + _side, archived + _side)
            logger.warning(f"  RACE DB from an earlier run at this path archived: {archived}")

        # StatusDB.__init__ creates the sqlite file + pointer file + schema.
        # Exceptions here mean project(race,db_path) is unreachable, the
        # dir isn't writable, or sqlite refuses — all reasons to fail loud
        # rather than deferring to first-run.
        db = StatusDB(
            run_dir,
            project_name=project_name,
            domain=domain,
            flow_type=flow_type,
            run_name=run_name,
            user=user,
            db_base_path=db_base,
        )
        db.set_run_info('flow_type', flow_type)
        db.set_run_info('run_dir', run_dir)
        db.set_run_info('project', project_name)
        db.set_run_info('user', user)
        db.set_run_info('created_by', 'workspace_create')
        db.set_run_info('created_at', datetime.now().isoformat())
        logger.info(f"  RACE DB:  {db.db_path}")

        pointer = os.path.join(run_dir, StatusDB.DB_POINTER_FILE)
        if not os.path.isfile(pointer):
            return False, (f"race DB created but pointer file "
                           f"'{pointer}' was not written")
        return True, ''
    except Exception as e:
        return False, f"race DB init failed: {type(e).__name__}: {e}"


def _append_release_cmd_pin(uc_path: str, user_config: Dict[str, str], env: Dict[str, str],
                            flow_type: str) -> None:
    """The project's CBflow release (project(cbflow_release)) pins command versions
    (release_versions.tcl CMDS_<FLOW>_<VENDOR>_<TOOL>_VERSION). Append the pin for
    this run's flow / tool to the run's own user_config.tcl as <arr>(tool,version),
    so the engine's handler lookup and the handlers use the released command tree.
    A tool,version the user set explicitly wins (no pin appended)."""
    release = env.get('CBFLOW_RELEASE_VERSION', '')
    arr = flow_type.lower()
    if not release or user_config.get(f'{arr}(tool,version)'):
        return
    try:
        from core.paths import get_cbflow_releases_dir
        rf = os.path.join(get_cbflow_releases_dir() or '', release, 'release_versions.tcl')
    except Exception:  # noqa: BLE001 — no releases dir: nothing to pin
        return
    if not os.path.exists(rf):
        return
    tool = user_config.get(f'{arr}(tool,name)', '').strip('"')
    if not tool:
        try:
            from core import registry
            dt = registry.project_value(user_config.get('project(name)', '').strip('"'), 'default_tools') or ''
            toks = dt.split()
            tool = dict(zip(toks[::2], toks[1::2])).get(flow_type, '').strip('"')
        except Exception:  # noqa: BLE001
            tool = ''
    if not tool:
        return
    rx = re.compile(rf'^set\s+CMDS_{re.escape(flow_type)}_[A-Z0-9]+_{re.escape(tool.upper())}_VERSION\s+"([^"]+)"', re.M)
    m = rx.search(open(rf).read())
    if not m:
        return
    with open(uc_path, 'a') as fh:
        fh.write(f'\n# CBflow release {release} (project(cbflow_release)): command version of '
                 f'{flow_type} {tool} — appended by workspace create\n'
                 f'set {arr}(tool,version) "{m.group(1)}"\n')
    logger.info(f"  Release {release}: {flow_type} {tool} commands pinned to {m.group(1)}")


def compose_run_dir_name(phase: str, flow_type: str, block: str, run_name: str) -> str:
    """<phase>_run_<FLOW>_<block>_<run_name> — the block (flow(design_name))
    keeps same-named runs of different blocks apart in the dashboard. The
    block is omitted when unset, not a plain name, or already leading the
    run_name; `<phase>_run_<FLOW>_` stays the run-dir shape tools match on."""
    import re as _re_blk
    if (block and _re_blk.match(r'^[A-Za-z0-9_.-]+$', block)
            and run_name != block and not run_name.startswith(block + '_')):
        run_name = f"{block}_{run_name}"
    return f"{phase}_run_{flow_type}_{run_name}"


# ── Main Entry Point ─────────────────────────────────────────────────────────

def create_run(config_file: str, env_vars: Dict[str, str],
               force: bool = False) -> Tuple[bool, str]:
    """Create a new CBFlow run directory.

    Args:
        config_file: Path to user_config.tcl
        env_vars: Merged environment variables (from .cbflow.env + .cbflow.tcl)
        force: If True, overwrite existing run directory

    Returns:
        (success, run_dir_name) - on failure, run_dir_name is empty string
    """
    # Step 1: Parse user config (env vars are auto-built by caller)
    user_config = _parse_user_config(config_file)

    # Step 3: Validate user config
    valid, flow_type, run_name, design_name, phase = _validate_user_config(user_config, env_vars)
    if not valid:
        return False, ''

    # Step 4: Validate workarea path
    # Runs must be created in project(workarea_path)/<design_name>/
    # Read workarea_path from project config if not in user config
    workarea_path = user_config.get('project(workarea_path)', '')
    if not workarea_path:
        project_name = user_config.get('project(name)', '')
        if project_name:
            # Walk the full project-config cascade (global identity + every
            # discipline overlay) via the shared registry helper
            # (PROJECT_CONFIG_VERSION required). Pre-fix only the legacy
            # monolith was checked, so workarea_path validation silently
            # skipped on migrated installs — runs could be created anywhere.
            from core import registry
            try:
                workarea_path = registry.project_value(project_name, 'workarea_path') or ''
            except registry.RegistryError as e:
                logger.error(f"  Error: {e}")
                return False, ''
    if workarea_path:
        workarea_design = os.path.join(os.path.abspath(workarea_path), design_name)
        cwd = os.path.abspath(os.getcwd())
        # CWD must be workarea/<design>/ or any subdirectory under it
        if not (cwd == workarea_design or cwd.startswith(workarea_design + os.sep)):
            logger.error("")
            logger.error(f"  ERROR: Runs must be created under the project workarea")
            logger.error(f"    Required: {workarea_design}/  (or any subdirectory)")
            logger.error(f"    Current:  {cwd}")
            logger.error("")
            logger.error(f"  Examples:")
            logger.error(f"    cd {workarea_design}")
            logger.error(f"    cd {workarea_design}/testruns")
            logger.error(f"    cd {workarea_design}/timing_experiments")
            logger.error(f"    cbflow workspace create --config <config_file>")
            logger.error("")
            return False, ''

    # Step 5: Build run directory name
    run_dir_name = compose_run_dir_name(phase, flow_type,
                                        user_config.get('flow(design_name)', ''),
                                        run_name)

    # Step 6: Handle existing directory
    if os.path.exists(run_dir_name):
        if not force:
            logger.error(f"  Error: Run directory already exists: {run_dir_name}")
            logger.error(f"  Use --force to recreate")
            return False, ''
        # Belt-and-braces path-traversal guard — the primary defense is
        # the allowlist on run_name/phase in _validate_user_config, but
        # also verify the composed name has no path separators and
        # resolves to a direct child of cwd before firing rmtree.
        _target_abs = os.path.realpath(run_dir_name)
        _cwd_abs = os.path.realpath(os.getcwd())
        if (os.sep in run_dir_name
                or '..' in run_dir_name.split(os.sep)
                or os.path.dirname(_target_abs) != _cwd_abs):
            logger.error(
                f"  Error: refusing to rmtree {run_dir_name!r} — "
                f"not a direct child of {_cwd_abs}. Fix flow(run_name) / phase.")
            return False, ''
        logger.info(f"  Removing existing: {run_dir_name}")
        shutil.rmtree(run_dir_name)

    # Step 6: Parse directory config — the dir_config.tcl of the flow's
    # discipline (merged flows use a fixed per-sub-flow layout and need none).
    flow_config_version = env_vars.get('FLOW_CONFIG_VERSION') or _get_flow_config_version()
    dir_config = {}
    if not parse_merged_flow(flow_type):
        from core import registry
        dir_config_path = os.path.join(
            registry.discipline_dir(registry.flow_discipline(flow_type)),
            'config', 'flow', flow_config_version, 'dir_config.tcl')
        if not os.path.exists(dir_config_path):
            logger.error(f"  Error: dir_config.tcl not found: {dir_config_path}")
            return False, ''
        dir_config = _parse_dir_config(dir_config_path)

    # Step 7: Create directory structure
    os.makedirs(run_dir_name, exist_ok=True)
    if not _create_directory_structure(run_dir_name, flow_type, dir_config):
        shutil.rmtree(run_dir_name, ignore_errors=True)
        return False, ''

    # Step 8: Copy user config
    setup_dir = os.path.join(run_dir_name, 'setup')
    os.makedirs(setup_dir, exist_ok=True)
    shutil.copy2(config_file, os.path.join(setup_dir, 'user_config.tcl'))
    _append_release_cmd_pin(os.path.join(setup_dir, 'user_config.tcl'), user_config, env_vars, flow_type)

    # Step 9: Generate environment files
    _generate_run_tcl_env(run_dir_name, env_vars, flow_type, design_name, run_name, phase)
    _generate_run_shell_env(run_dir_name, env_vars, flow_type, design_name, run_name, phase)

    # Step 10a: Verify launch-mode binaries + $DISPLAY (fatal). If the
    # user asked for LSF but bsub isn't in PATH — or for xterm and xterm
    # isn't installed, or $DISPLAY is empty — every real subnode will die
    # with no useful output. Catch it upfront. On failure, persist the
    # diagnosis to <run_dir>.preflight_failed.log (survives cleanup) so
    # users don't have to re-run just to see what went wrong.
    ok, err = _preflight_launch_bins(user_config, env_vars)
    if not ok:
        ext_log = _write_preflight_fail_log(run_dir_name, user_config,
                                            env_vars, err)
        shutil.rmtree(run_dir_name, ignore_errors=True)
        logger.error("Workspace create blocked — launch-mode preflight failed.")
        for ln in err.splitlines():
            logger.error("  " + ln)
        logger.error("")
        logger.error("  Full diagnosis written to: {}".format(ext_log))
        return False, ''

    # Step 10b: Verify engine DAG (fatal — a run whose DAG won't build has no
    # reason to exist; better to error at create time than surface it via a
    # failed `cbflow run all` later).
    if not _verify_engine_dag(run_dir_name, flow_type, env_vars):
        # Clean up so the workarea doesn't accumulate broken half-runs.
        shutil.rmtree(run_dir_name, ignore_errors=True)
        logger.error(f"  Run creation failed: DAG build did not succeed")
        return False, ''

    # Step 11: Initialize the RACE status DB + pointer file (fatal).
    # The DB is the single source of truth for job state; leaving it to
    # lazy init on first `cbflow run all` meant runs could exist on disk
    # without an owning DB — dashboards, status commands, and release
    # workflows would silently see nothing.
    ok, err = _initialize_race_db(run_dir_name, flow_type, env_vars)
    if not ok:
        shutil.rmtree(run_dir_name, ignore_errors=True)
        logger.error(f"  Run creation failed: {err}")
        logger.error(f"  Check project(race,db_path) — it must be set in "
                     f"project_pd_config.tcl and be writable.")
        return False, ''

    return True, run_dir_name
