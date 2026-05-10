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
    _parse_set_statements, _parse_tcl_string, _parse_tcl_list,
    get_flow_types, get_phases, _get_config_root, _get_flow_config_version,
    is_merged_flow, parse_merged_flow
)

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
    'TECHNOLOGY_VERSION', 'UTILITIES_VERSION',
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
    """Parse user_config.tcl into a dict.

    Uses tcl_config_parser._parse_set_statements() for consistency.
    Returns dict like {'flow(type)': 'SYNTH', 'flow(run_name)': 'run1', ...}
    """
    with open(config_file, 'r') as f:
        content = f.read()

    raw = _parse_set_statements(content)
    result = {}
    for key, raw_val in raw.items():
        result[key] = _parse_tcl_string(raw_val)
    return result


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

    # Design name from user_config (primary source)
    design_name = user_config.get('flow(design_name)', '')
    if not design_name:
        design_name = env.get('CBFLOW_BLOCK_NAME', env.get('PROJECT_NAME', 'design'))

    # Phase
    phase = user_config.get('project(phase)', user_config.get('flow(phase)', 'P0'))

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
        for d in ['.stamps', 'logs', 'setup', 'work']:
            os.makedirs(os.path.join(run_dir, d), exist_ok=True)
        # Per-flow work dirs
        for sf in sub_flows:
            os.makedirs(os.path.join(run_dir, 'work', sf), exist_ok=True)
        return True

    # Single flow
    dirs = dir_config.get(flow_type)
    if not dirs:
        dirs = ['.stamps', 'logs', 'setup', 'work', f'work/{flow_type}']

    for d in dirs:
        full_path = os.path.join(run_dir, d)
        os.makedirs(full_path, exist_ok=True)

    return True


# ── Environment File Generation ──────────────────────────────────────────────

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
    """Verify cbflow-engine DAG can be built for this run."""
    try:
        from cbflow_engine import DagBuilder
        builder = DagBuilder(run_dir, flow_type, env)
        jobs, stages = builder.build()
        if jobs and stages:
            logger.info(f"  cbflow-engine DAG: {len(jobs)} jobs, {len(stages)} stages")
            return True
        else:
            logger.warning(f"  cbflow-engine DAG build returned empty")
            return False
    except Exception as e:
        logger.warning(f"  cbflow-engine DAG verification failed: {e}")
        return False


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

    # Step 4: Build run directory name
    run_dir_name = f"{phase}_run_{flow_type}_{run_name}"

    # Step 5: Handle existing directory
    if os.path.exists(run_dir_name):
        if not force:
            logger.error(f"  Error: Run directory already exists: {run_dir_name}")
            logger.error(f"  Use --force to recreate")
            return False, ''
        logger.info(f"  Removing existing: {run_dir_name}")
        shutil.rmtree(run_dir_name)

    # Step 6: Parse directory config
    config_root = env_vars.get('CONFIG_ROOT', '')
    flow_config_version = env_vars.get('FLOW_CONFIG_VERSION', _get_flow_config_version())
    dir_config_path = os.path.join(config_root, 'flow', flow_config_version, 'dir_config.tcl')
    dir_config = _parse_dir_config(dir_config_path)

    # Step 7: Create directory structure
    os.makedirs(run_dir_name, exist_ok=True)
    _create_directory_structure(run_dir_name, flow_type, dir_config)

    # Step 8: Copy user config
    setup_dir = os.path.join(run_dir_name, 'setup')
    os.makedirs(setup_dir, exist_ok=True)
    shutil.copy2(config_file, os.path.join(setup_dir, 'user_config.tcl'))

    # Step 9: Generate environment files
    _generate_run_tcl_env(run_dir_name, env_vars, flow_type, design_name, run_name, phase)
    _generate_run_shell_env(run_dir_name, env_vars, flow_type, design_name, run_name, phase)

    # Step 10: Verify engine DAG
    _verify_engine_dag(run_dir_name, flow_type, env_vars)

    return True, run_dir_name
