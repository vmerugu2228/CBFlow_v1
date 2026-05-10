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

# Version
VERSION = "2.0.0"

# Valid flow types - loaded from existing Tcl config files
from tcl_config_parser import get_flow_types as _get_flow_types
FLOW_TYPES = _get_flow_types()



def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory from environment or determine from script location."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


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
    """Get available projects from config/project directory."""
    core_dir = get_cbflow_core_dir()
    project_dir = Path(core_dir) / "config" / "project"
    projects = []
    if project_dir.exists():
        for item in sorted(project_dir.iterdir()):
            if item.is_dir() and not item.name.startswith('.') and item.name != 'workspace':
                projects.append(item.name)
    return projects


def get_project_config(project: str, version: str = 'v1.0.0') -> dict:
    """Load project configuration."""
    core_dir = get_cbflow_core_dir()
    project_config_file = Path(core_dir) / "config" / "project" / project / version / f"{project}_config.tcl"

    config = {
        'name': project,
        'version': version,
        'config_file': str(project_config_file) if project_config_file.exists() else None
    }

    # Try to parse basic info from project config
    if project_config_file.exists():
        try:
            with open(project_config_file, 'r') as f:
                content = f.read()
                # Extract technology if present
                for line in content.split('\n'):
                    if 'technology' in line.lower() and 'set' in line:
                        parts = line.split('"')
                        if len(parts) >= 2:
                            config['technology'] = parts[1]
                            break
        except:
            pass

    return config


def is_workspace_initialized() -> bool:
    """Check if current directory has workspace environment."""
    return os.path.exists(os.path.join(os.getcwd(), '.cbflow.env'))


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


def _get_flow_mode(core_dir: str) -> str:
    """Read flow(mode) from flow_config.tcl. Returns 'default' or 'merged'."""
    import re
    version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    config_path = os.path.join(core_dir, 'config', 'flow', version, 'flow_config.tcl')
    if os.path.exists(config_path):
        try:
            with open(config_path, 'r') as f:
                for line in f:
                    m = re.match(r'set\s+flow\(mode\)\s+"(\w+)"', line.strip())
                    if m:
                        return m.group(1)
        except Exception:
            pass
    return 'default'


def _get_flow_specific_config(flow_type: str, design_name: str) -> str:
    """Return flow-specific user_config.tcl section with required variables."""
    ft = flow_type.upper()
    sections = []

    if ft in ('SYNTH_PNR', 'SYNTH_FP_PNR'):
        arr = 'synth_pnr'
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# {ft} Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# RTL Input
set {arr}(input,rtl_filelist)   ""              ;# RTL filelist (.f)
set {arr}(input,rtl_format)     "sverilog"      ;# sverilog | verilog | vhdl

# Timing Constraints
set {arr}(input,sdc_func_file)  ""              ;# Functional mode SDC

# UPF Power Intent
set {arr}(input,upf_file)      ""              ;# Power intent UPF (required)

# Floorplan (optional)
# set {arr}(input,def_file)       ""            ;# Floorplan DEF
""")

    elif ft == 'SYNTH':
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# SYNTH Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# RTL Input
set synth(input,rtl_filelist)  ""           ;# RTL filelist (.f)

# Timing Constraints
set synth(input,sdc_func_file) ""           ;# Functional mode SDC
""")

    elif ft == 'PNR':
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# PNR Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# Netlist (from synthesis output)
set pnr(input,netlist)         ""           ;# Gate-level netlist (.v)

# Timing Constraints
set pnr(input,sdc_func_file)   ""           ;# Functional mode SDC

# Floorplan
set pnr(input,def_file)        ""           ;# Floorplan DEF

# UPF (optional)
# set pnr(input,upf_file)       ""          ;# Power intent UPF
""")

    elif ft == 'FP':
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# FP Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# Netlist
set fp(input,netlist)          ""           ;# Gate-level netlist (.v)

# Timing Constraints
set fp(input,sdc_func_file)    ""           ;# Functional mode SDC

# UPF (optional)
# set fp(input,upf_file)        ""          ;# Power intent UPF
""")

    elif ft == 'STA':
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# STA Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# Netlist
set sta(input,netlist)         ""           ;# Gate-level netlist (.v)

# Timing Constraints
set sta(input,sdc_func_file)   ""           ;# Functional mode SDC

# Parasitics (optional)
# set sta(input,spef_file)      ""          ;# SPEF parasitic file
""")

    elif ft == 'ECO':
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# ECO Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
set eco(eco,type)              "timing"     ;# timing | functional
set eco(input,from_block)      "chip_finish" ;# Block to ECO from

# For functional ECO
# set eco(input,eco_verilog)   ""           ;# Modified netlist

# For manual ECO changes
# set eco(input,change_file)   ""           ;# Manual ECO change script
""")

    elif ft == 'LEC':
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# LEC Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# Reference Design (golden — choose ONE)
set lec(input,rtl_files)       ""           ;# RTL source files (RTL-to-gate)
# set lec(input,netlist_golden) ""          ;# Gate-level golden netlist (gate-to-gate)

# Implementation Design (revised)
set lec(input,netlist_revised)  ""          ;# Implementation netlist

# Power Intent (optional)
# set lec(input,svf_file)       ""          ;# SVF guidance from synthesis
""")

    elif ft == 'CLP':
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# CLP Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# PG Netlist (from write_data output)
set clp(input,reference_netlist) ""         ;# PG netlist (.vc_lp.v)

# Power Intent
set clp(input,upf_file)         ""          ;# UPF power intent
""")

    elif ft == 'FCFP':
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# FCFP Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
# Netlist
set fcfp(input,netlist)        ""           ;# Gate-level netlist or RTL filelist

# Timing Constraints
set fcfp(input,sdc_func_file)  ""           ;# Functional mode SDC
""")

    else:
        # Generic template for other flows
        arr = ft.lower()
        sections.append(f"""# ─────────────────────────────────────────────────────────────────────────────────
# {ft} Design Inputs (REQUIRED)
# ─────────────────────────────────────────────────────────────────────────────────
set {arr}(input,netlist)       ""           ;# Input netlist
set {arr}(input,sdc_func_file) ""           ;# Functional mode SDC
""")

    return '\n'.join(sections)


# ─────────────────────────────────────────────────────────────────────────────────
# Workspace Commands
# ─────────────────────────────────────────────��───────────────────────────────────

def cmd_init(args: argparse.Namespace) -> int:
    """Initialize a workspace with release version and project."""
    core_dir = get_cbflow_core_dir()

    # Determine release version
    release_version = getattr(args, 'release', None)
    if not release_version:
        # Use current release if not specified
        release_version = get_current_release()
        if not release_version:
            release_version = 'v1.0.0'

    # Check release version exists in releases/
    releases_dir = Path(core_dir) / 'releases'
    release_dir = releases_dir / release_version

    if not release_dir.exists():
        available = get_available_releases()
        logger.error(f"Release {release_version} not found in {releases_dir}")
        if available:
            logger.info(f"Available releases: {', '.join(available)}")
        else:
            logger.info("No releases found. Create one with: cbflow flow release create")
        return 1

    # Get project name (required)
    project_name = getattr(args, 'project', None)
    if not project_name:
        available_projects = get_available_projects()
        logger.error("Project name is required. Use --project <name>")
        if available_projects:
            logger.info(f"Available projects: {', '.join(available_projects)}")
        else:
            logger.info("No projects found in config/project/")
        return 1

    # Validate project exists
    available_projects = get_available_projects()
    if project_name not in available_projects:
        logger.error(f"Project '{project_name}' not found")
        if available_projects:
            logger.info(f"Available projects: {', '.join(available_projects)}")
        return 1

    # Get flow type (required)
    flow_type = getattr(args, 'flow', None)
    if not flow_type:
        logger.error("Flow type is required. Use --flow <type>")
        logger.info(f"Available flow types: {', '.join(FLOW_TYPES)}")
        return 1

    flow_type = flow_type.upper()
    from tcl_config_parser import is_merged_flow

    # Check flow mode -- auto-merge SYNTH/PNR into SYNTH_PNR when mode=merged
    flow_mode = _get_flow_mode(core_dir)
    if flow_mode == "merged":
        if flow_type in ("SYNTH", "PNR"):
            merged_flow = "SYNTH_PNR"
            logger.info(f"")
            logger.info(f"  Flow mode is 'merged': {flow_type} -> {merged_flow}")
            logger.info(f"  SYNTH and PNR run as a single merged flow")
            logger.info(f"  FP (floorplanning) remains independent")
            logger.info(f"")
            flow_type = merged_flow
        elif flow_type == "FP":
            logger.info(f"  Flow mode is 'merged': FP stays independent (floorplanning)")

    if flow_type not in FLOW_TYPES and not is_merged_flow(flow_type):
        logger.error(f"Invalid flow type: {flow_type}")
        logger.info(f"Available flow types: {', '.join(FLOW_TYPES)}")
        logger.info(f"Merged flows: e.g., SYNTH_FP, SYNTH_PNR, SYNTH_FP_PNR")
        return 1

    # Design name is set in user_config.tcl at run creation time
    # At workspace init, use project name as placeholder
    block_name = project_name

    # Load release manifest for component versions
    manifest = load_release_manifest(release_version)
    components = manifest.get('components', {})

    # Get project version from release manifest
    project_comp_key = f"config.project.{project_name}"
    project_version = components.get(project_comp_key, {}).get('version', 'v1.0.0')
    project_config = get_project_config(project_name, project_version)

    logger.info("")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info(f"  CBFlow Workspace Initialization")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info("")
    logger.info(f"Configuration:")
    logger.info(f"  Project:         {project_name}")
    logger.info(f"  Flow Type:       {flow_type}")
    logger.info(f"  Release Version: {release_version}")
    logger.info(f"  Core Directory:  {core_dir}")
    logger.info(f"  Workspace:       {os.getcwd()}")
    logger.info(f"  Components:      {len(components)}")
    logger.info("")

    # Check for existing workspace
    if os.path.exists('.cbflow.env'):
        logger.warning("Existing workspace environment found!")
        if not getattr(args, 'force', False):
            logger.info("Use --force to overwrite existing workspace")
            return 1
        # Backup existing
        backup_dir = '.backup'
        os.makedirs(backup_dir, exist_ok=True)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_file = os.path.join(backup_dir, f'.cbflow.env.backup.{timestamp}')
        os.rename('.cbflow.env', backup_file)
        logger.info(f"Backed up existing .cbflow.env to {backup_file}")

    # Build component version exports (matching release_versions.tcl naming)
    component_exports = []
    for comp_name, comp_info in sorted(components.items()):
        version = comp_info.get('version', 'v1.0.0')
        # Convert component name to variable name: config.flow -> CONFIG_FLOW_VERSION
        var_name = comp_name.upper().replace('.', '_') + "_VERSION"
        component_exports.append(f'export {var_name}="{version}"')

    component_versions_str = '\n'.join(component_exports)

    # Get key versions for path configuration
    flow_version = components.get('config.flow', {}).get('version', 'v1.0.0')
    utils_version = components.get('utils.utilities', {}).get('version', 'v1.0.0')
    gen_version = components.get('utils.generation', {}).get('version', 'v1.0.0')
    node_mgmt_version = components.get('utils.node_management', {}).get('version', 'v1.0.0')
    validation_version = components.get('utils.validation', {}).get('version', 'v1.0.0')
    makefile_version = components.get('utils.makefile_commands', {}).get('version', 'v1.0.0')
    setup_version = components.get('config.setup.common', {}).get('version', 'v1.0.0')

    # Get project-specific setup version if available
    project_setup_key = f"config.setup.{project_name}"
    project_setup_version = components.get(project_setup_key, {}).get('version', setup_version)

    # Get technology from project config or default
    technology = project_config.get('technology', '') or os.environ.get('TECH_NAME', '')

    # Create .cbflow.env file
    env_content = f"""# CBFlow Workspace Environment
# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
# Project: {project_name}
# Release: {release_version}
# Components: {len(components)}

# Project Configuration
export CBFLOW_PROJECT="{project_name}"
export CBFLOW_PROJECT_VERSION="{project_version}"
export CBFLOW_PROJECT_CONFIG="{core_dir}/config/project/{project_name}/{project_version}/{project_name}_config.tcl"
export CBFLOW_TECHNOLOGY="{technology}"

# Release Configuration
export CBFLOW_RELEASE_VERSION="{release_version}"
export CBFLOW_RELEASE_TAG="{release_version}"
export CBFLOW_RELEASE_PHASE="${{CBFLOW_RELEASE_PHASE:-P0}}"
export CBFLOW_CORE_DIR="{core_dir}"
export CBFLOW_ROOT="{get_cbflow_root()}"
export CBFLOW_RELEASE_DIR="{core_dir}/releases/{release_version}"
export CBFLOW_RELEASE_OUTPUT_DIR=""
export FLOW_DIR="{core_dir}"

# Component Versions (from release manifest - matches release_versions.tcl)
{component_versions_str}

# Flow Configuration Paths
export CBFLOW_FLOW_CONFIG="{core_dir}/config/flow/{flow_version}/flow_config.tcl"
export CBFLOW_RELEASE_CONFIG="{core_dir}/config/flow/{flow_version}/release_config.tcl"
export CBFLOW_RELEASE_VERSIONS="{core_dir}/releases/{release_version}/release_versions.tcl"
export CBFLOW_SETUP_CONFIG="{core_dir}/config/setup/common/{setup_version}/setup.tcl"
export CBFLOW_PROJECT_SETUP="{core_dir}/config/setup/{project_name}/{project_setup_version}/setup.tcl"

# Utility Scripts
export CBFLOW_START_RUN_SCRIPT="{core_dir}/utils/utilities/{utils_version}/start_run.tcl"
export CBFLOW_GEN_CONFIG_SCRIPT="{core_dir}/utils/generation/{gen_version}/generate_setup.tcl"
"""

    with open('.cbflow.env', 'w') as f:
        f.write(env_content)

    # Build component version TCL variables (matching release_versions.tcl naming)
    component_tcl_vars = []
    for comp_name, comp_info in sorted(components.items()):
        version = comp_info.get('version', 'v1.0.0')
        var_name = comp_name.upper().replace('.', '_') + "_VERSION"
        component_tcl_vars.append(f'set {var_name} "{version}"')

    component_versions_tcl = '\n'.join(component_tcl_vars)

    # Parse technology info (e.g., "tsmc_7nm" -> vendor="tsmc", node="7nm")
    tech_parts = technology.split('_', 1)
    tech_vendor = tech_parts[0] if tech_parts else "unknown"
    tech_node = tech_parts[1] if len(tech_parts) > 1 else "unknown"
    tech_version = components.get(f'config.tech.{technology}', {}).get('version', 'v1.0.0')

    # Create .cbflow.tcl file (TCL version of environment)
    tcl_content = f"""#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Workspace Environment (TCL)
# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
# Project: {project_name}
# Release: {release_version}
# ═══════════════════════════════════════════════════════════════════════════════

# Project Configuration
set CBFLOW_PROJECT "{project_name}"
set CBFLOW_PROJECT_VERSION "{project_version}"
set CBFLOW_PROJECT_CONFIG "{core_dir}/config/project/{project_name}/{project_version}/{project_name}_config.tcl"
set CBFLOW_TECHNOLOGY "{technology}"

# Release Configuration
set CBFLOW_RELEASE_VERSION "{release_version}"
set CBFLOW_RELEASE_TAG "{release_version}"
set ::env(CBFLOW_RELEASE_TAG) "{release_version}"
set ::env(CBFLOW_RELEASE_PHASE) "${{::env(CBFLOW_RELEASE_PHASE)}}"
catch {{ set ::env(CBFLOW_RELEASE_PHASE) "P0" }}
set CBFLOW_CORE_DIR "{core_dir}"
set CBFLOW_ROOT "{get_cbflow_root()}"
set CBFLOW_RELEASE_DIR "{core_dir}/releases/{release_version}"
set FLOW_DIR "{core_dir}"

# Legacy Environment Variables (for compatibility with existing scripts)
# Using ::env() to set as environment variables accessible via $::env(VAR)
set ::env(FLOW_DIR) "{core_dir}"
set ::env(CONFIG_ROOT) "{core_dir}/config"
set ::env(SCRIPTS_ROOT) "{core_dir}/utils"
set ::env(PROJECT_ROOT) "{core_dir}/config/project/{project_name}"
set ::env(PROJECT_NAME) "{project_name}"
set ::env(PROJECT_VERSION) "{project_version}"
set ::env(TECHNOLOGY_VENDOR) "{tech_vendor}"
set ::env(TECHNOLOGY_NODE) "{tech_node}"
set ::env(TECHNOLOGY_VERSION) "{tech_version}"
set ::env(FLOW_CONFIG_VERSION) "{flow_version}"
set ::env(UTILITIES_VERSION) "{utils_version}"
set ::env(GENERATION_VERSION) "{gen_version}"
set ::env(NODE_MANAGEMENT_VERSION) "{node_mgmt_version}"
set ::env(VALIDATION_VERSION) "{validation_version}"
set ::env(MAKEFILE_COMMANDS_VERSION) "{makefile_version}"

# Workspace-Locked Variables (set during workspace init, cannot be overridden)
set ::env(CBFLOW_FLOW_TYPE) "{flow_type}"
set ::env(CBFLOW_BLOCK_NAME) "{block_name}"
set ::env(CBFLOW_PROJECT_NAME) "{project_name}"

# Component Versions (from release manifest)
{component_versions_tcl}

# Flow Configuration Paths
set CBFLOW_FLOW_CONFIG "{core_dir}/config/flow/{flow_version}/flow_config.tcl"
set CBFLOW_RELEASE_CONFIG "{core_dir}/config/flow/{flow_version}/release_config.tcl"
set CBFLOW_RELEASE_VERSIONS "{core_dir}/releases/{release_version}/release_versions.tcl"
set CBFLOW_SETUP_CONFIG "{core_dir}/config/setup/common/{setup_version}/setup.tcl"
set CBFLOW_PROJECT_SETUP "{core_dir}/config/setup/{project_name}/{project_setup_version}/setup.tcl"

# Utility Scripts
set CBFLOW_START_RUN_SCRIPT "{core_dir}/utils/utilities/{utils_version}/start_run.tcl"
set CBFLOW_GEN_CONFIG_SCRIPT "{core_dir}/utils/generation/{gen_version}/generate_setup.tcl"

puts "INFO: Loaded CBFlow workspace environment for project {project_name}"
"""

    with open('.cbflow.tcl', 'w') as f:
        f.write(tcl_content)

    # Create user_config.tcl template if it doesn't exist
    if not os.path.exists('user_config.tcl'):
        # Flow-specific input sections
        flow_inputs = _get_flow_specific_config(flow_type, block_name)

        user_config_content = f"""#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# User Configuration File - {project_name}/{block_name}
# Flow: {flow_type} | Release: {release_version}
# Edit this file to configure your design run
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Design (from workspace init — do not modify)
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "{project_name}"
set project(phase)       "P0"
set project(technology)  "{technology}"
set design(name)         "{block_name}"
set design(top_module)   "{block_name}"

# ─────────────────────────────────────────────────────────────────────────────────
# Flow Configuration
# ─────────────────────────────────────────────────────────────────────────────────
set flow(type)           "{flow_type}"
set flow(design_name)    "{block_name}"
set flow(run_name)       "run1"
set flow(test_mode)      "false"

{flow_inputs}
# ═══════════════════════════════════════════════════════════════════════════════
# End of User Configuration
# ═══════════════════════════════════════════════════════════════════════════════
"""
        with open('user_config.tcl', 'w') as f:
            f.write(user_config_content)
        logger.info("Created user_config.tcl template")

    logger.info("")
    logger.info(f"Workspace initialized successfully!")
    logger.info("")
    logger.info(f"Next Steps:")
    logger.info("  1. Edit user_config.tcl with your design specifics")
    logger.info("  2. cbflow workspace create --config user_config.tcl")
    logger.info("")
    logger.info("Other commands:")
    logger.info("  cbflow workspace status       - Show workspace status")
    logger.info("  cbflow workspace list-runs    - List all runs")
    return 0


def cmd_template(args: argparse.Namespace) -> int:
    """Dump a user_config.tcl template for a specific flow type."""
    flow_type = getattr(args, 'flow', '').upper()
    output = getattr(args, 'output', None)

    if not flow_type:
        logger.error("  Error: --flow is required")
        logger.error("  Usage: cbflow workspace template --flow SYNTH_PNR")
        return 1

    from tcl_config_parser import get_flow_types
    valid_flows = get_flow_types()
    if flow_type not in valid_flows:
        logger.error(f"  Unknown flow type: {flow_type}")
        logger.error(f"  Available: {', '.join(sorted(valid_flows))}")
        return 1

    design_name = "my_design"
    project_name = "my_project"

    flow_inputs = _get_flow_specific_config(flow_type, design_name)

    template = f"""#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow User Configuration - {flow_type}
# Generated template — edit all values before running
# Usage: cbflow workspace create --config <this_file>
# ═══════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────────
# Project & Flow [MANDATORY]
# ─────────────────────────────────────────────────────────────────────────────────
set project(name)        "{project_name}"     ;# Your project name (must match config/project/<name>)
set project(phase)       "P0"                 ;# Design phase (P0, P1, etc.)
set flow(type)           "{flow_type}"
set flow(design_name)    "{design_name}"      ;# Your design/block name
set flow(run_name)       "run1"               ;# Unique run identifier
set flow(test_mode)      "false"              ;# Set "true" to skip EDA tool execution

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

    core_dir = get_cbflow_core_dir()
    user_config = _parse_user_config(config_file)

    # Extract from user_config
    project_name = user_config.get('project(name)', '')
    flow_type = user_config.get('flow(type)', '').upper()
    design_name = user_config.get('flow(design_name)', project_name)
    technology = user_config.get('project(technology)', '')

    if not project_name:
        logger.error("  Error: project(name) not set in user_config.tcl")
        return {}
    if not flow_type:
        logger.error("  Error: flow(type) not set in user_config.tcl")
        return {}

    # Auto-detect all paths from FLOW_DIR
    config_root = os.path.join(core_dir, 'config')
    scripts_root = os.path.join(core_dir, 'utils')
    project_root = os.path.join(config_root, 'project', project_name)

    # Resolve CBflow release version from project config → releases/current fallback
    release_version = ''

    # Read from project config: project(cbflow_release)
    # Find project config version directory (use 'current' symlink or latest)
    proj_versions_dir = os.path.join(project_root, 'current')
    if not os.path.exists(proj_versions_dir):
        proj_versions_dir = os.path.join(project_root, 'v1.0.0')
        # Try to find the latest version if v1.0.0 doesn't exist
        if not os.path.exists(proj_versions_dir) and os.path.isdir(project_root):
            versions_list = sorted([d for d in os.listdir(project_root) if os.path.isdir(os.path.join(project_root, d))], reverse=True)
            if versions_list:
                proj_versions_dir = os.path.join(project_root, versions_list[0])
    proj_config_file = os.path.join(proj_versions_dir, f'{project_name}_config.tcl')
    if os.path.exists(proj_config_file):
        with open(proj_config_file, 'r') as f:
            for line in f:
                m = re.match(r'set\s+project\(cbflow_release\)\s+"([^"]*)"', line.strip())
                if m:
                    release_version = m.group(1)
                    break

    # project(cbflow_release) is mandatory — no silent fallback
    if not release_version:
        logger.error("")
        logger.error("  project(cbflow_release) not found in project config.")
        logger.error(f"  Checked: {proj_config_file}")
        logger.error("")
        logger.error("  Add to your project config:")
        logger.error(f'    set project(cbflow_release) "v1.0.0"')
        logger.error("")
        # List available releases
        releases_dir = os.path.join(core_dir, 'releases')
        if os.path.isdir(releases_dir):
            avail = sorted([d for d in os.listdir(releases_dir)
                           if d.startswith('v') and os.path.isdir(os.path.join(releases_dir, d))])
            if avail:
                logger.error(f"  Available releases: {', '.join(avail)}")
                logger.error("")
        return None

    # Validate release exists
    release_dir = os.path.join(core_dir, 'releases', release_version)
    if not os.path.isdir(release_dir):
        logger.error("")
        logger.error(f"  Release '{release_version}' not found at: {release_dir}")
        releases_dir = os.path.join(core_dir, 'releases')
        avail = sorted([d for d in os.listdir(releases_dir)
                       if d.startswith('v') and os.path.isdir(os.path.join(releases_dir, d))])
        if avail:
            logger.error(f"  Available releases: {', '.join(avail)}")
        logger.error("")
        return None

    # Load component versions from release
    versions = {}
    release_file = os.path.join(core_dir, 'releases', release_version, 'release_versions.tcl')
    if os.path.exists(release_file):
        with open(release_file, 'r') as f:
            for line in f:
                m = re.match(r'set\s+(\w+)\s+"([^"]*)"', line.strip())
                if m:
                    versions[m.group(1)] = m.group(2)

    # Resolve technology from project config if not in user_config
    if not technology:
        proj_config = os.path.join(proj_versions_dir, f'{project_name}_config.tcl')
        if os.path.exists(proj_config):
            with open(proj_config, 'r') as f:
                for line in f:
                    m = re.match(r'set\s+project\(technology\)\s+"([^"]*)"', line.strip())
                    if m:
                        technology = m.group(1)
                        break

    tech_parts = technology.split('_', 1) if technology else ['', '']
    tech_vendor = tech_parts[0] if tech_parts[0] else ''
    tech_node = tech_parts[1] if len(tech_parts) > 1 else ''

    # Build the complete env dict
    env = {
        'FLOW_DIR': core_dir,
        'CONFIG_ROOT': config_root,
        'SCRIPTS_ROOT': scripts_root,
        'PROJECT_ROOT': project_root,
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

    # Extract tool vendor/name overrides from user_config
    # e.g., pnr(tool,vendor) "cadence", pnr(tool,name) "innovus"
    from start_run import _parse_user_config
    uc = _parse_user_config(config_file)
    arr = flow_type.lower().replace('_', '_')  # pnr, synth_pnr, sta, etc.
    tool_vendor = uc.get(f'{arr}(tool,vendor)', '')
    tool_name = uc.get(f'{arr}(tool,name)', '')
    if tool_vendor:
        env['CBFLOW_TOOL_VENDOR'] = tool_vendor
    if tool_name:
        env['CBFLOW_TOOL_NAME'] = tool_name

    return env


def _get_mandatory_inputs_from_config(core_dir: str, flow_type: str) -> list:
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
    flow_config_ver = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    config_file = os.path.join(core_dir, 'config', 'flow', flow_config_ver,
                               'node_configs', f'{flow_type}_config.tcl')
    if not os.path.exists(config_file):
        return []

    with open(config_file, 'r') as f:
        content = f.read()

    # Match: mandatory_user_inputs { var1 var2 var3 }
    m = _re.search(r'mandatory_user_inputs\s*\{([^}]*)\}', content)
    if m:
        raw = m.group(1).strip()
        return [v.strip() for v in raw.split() if v.strip()]
    return []


def _validate_mandatory_inputs(user_config: dict, flow_type: str) -> list:
    """Validate mandatory design inputs are set (non-empty) in user_config.

    Returns list of error messages. Empty list = all good.
    """
    errors = []
    ft = flow_type.upper()

    core_dir = get_cbflow_core_dir()

    # Common mandatory fields for all flows
    project_name = user_config.get('project(name)', '')
    if not project_name:
        errors.append("project(name) is empty")
    else:
        # Validate project exists in config
        project_dir = os.path.join(core_dir, 'config', 'project', project_name)
        if not os.path.isdir(project_dir):
            available = [d for d in os.listdir(os.path.join(core_dir, 'config', 'project'))
                        if os.path.isdir(os.path.join(core_dir, 'config', 'project', d))]
            errors.append(f"project '{project_name}' not found in config/project/. Available: {', '.join(available)}")

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
        # Read block_list from project config
        proj_version = 'v1.0.0'
        proj_config_file = os.path.join(core_dir, 'config', 'project', project_name,
                                        proj_version, f'{project_name}_config.tcl')
        if os.path.exists(proj_config_file):
            import re as _re
            with open(proj_config_file, 'r') as f:
                content = f.read()
            m = _re.search(r'set\s+project\(block_list\)\s+"([^"]*)"', content)
            if m:
                valid_designs = m.group(1).split()
                if design_name not in valid_designs:
                    errors.append(f"design '{design_name}' not found in project '{project_name}'. "
                                  f"Available designs: {', '.join(valid_designs)}")

    # Flow-specific mandatory inputs
    # First check node config for user-defined mandatory_user_inputs, then hardcoded defaults
    mandatory_from_config = _get_mandatory_inputs_from_config(core_dir, ft)

    if mandatory_from_config:
        # Data-driven: mandatory inputs defined in <FLOW>_config.tcl
        for var_key in mandatory_from_config:
            if not user_config.get(var_key, ''):
                errors.append(f"{var_key} is empty — required by {ft} flow config")
    elif ft == 'SYNTH_PNR':
        if not user_config.get('synth_pnr(input,rtl_filelist)', ''):
            errors.append("synth_pnr(input,rtl_filelist) is empty — RTL filelist required")
        if not user_config.get('synth_pnr(input,sdc_func_file)', ''):
            errors.append("synth_pnr(input,sdc_func_file) is empty — SDC constraints required")
        if not user_config.get('synth_pnr(input,upf_file)', ''):
            errors.append("synth_pnr(input,upf_file) is empty — UPF power intent required for SYNTH_PNR")

    elif ft == 'SYNTH':
        if not user_config.get('synth(input,rtl_filelist)', ''):
            errors.append("synth(input,rtl_filelist) is empty — RTL filelist required")
        if not user_config.get('synth(input,sdc_func_file)', ''):
            errors.append("synth(input,sdc_func_file) is empty — SDC constraints required")

    elif ft == 'PNR':
        if not user_config.get('pnr(input,netlist)', ''):
            errors.append("pnr(input,netlist) is empty — gate-level netlist is required for PnR")
        if not user_config.get('pnr(input,sdc_func_file)', ''):
            errors.append("pnr(input,sdc_func_file) is empty — SDC constraints are required")

    elif ft == 'FP':
        if not user_config.get('fp(input,netlist)', ''):
            errors.append("fp(input,netlist) is empty — netlist is required for floorplan")

    elif ft == 'FCFP':
        if not user_config.get('fcfp(input,netlist)', ''):
            errors.append("fcfp(input,netlist) is empty — netlist is required")

    elif ft == 'ECO':
        if not user_config.get('eco(eco,type)', ''):
            errors.append("eco(eco,type) is empty — must be 'timing' or 'functional'")

    elif ft == 'LEC':
        has_ref = user_config.get('lec(input,rtl_files)', '') or \
                  user_config.get('lec(input,netlist_golden)', '')
        if not has_ref:
            errors.append("No reference design — set lec(input,rtl_files) or lec(input,netlist_golden)")
        if not user_config.get('lec(input,netlist_revised)', ''):
            errors.append("lec(input,netlist_revised) is empty — implementation netlist is required")

    elif ft == 'CLP':
        if not user_config.get('clp(input,reference_netlist)', ''):
            errors.append("clp(input,reference_netlist) is empty — PG netlist is required")
        if not user_config.get('clp(input,upf_file)', ''):
            errors.append("clp(input,upf_file) is empty — UPF is required for low-power verification")

    return errors


def cmd_create(args: argparse.Namespace) -> int:
    """Create a new run from user_config.tcl. No workspace init required."""
    config_file = getattr(args, 'config', None)
    if not config_file:
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

    project = env_vars.get('PROJECT_NAME', '')
    flow_type = env_vars.get('CBFLOW_FLOW_TYPE', '')
    design = env_vars.get('CBFLOW_DESIGN_NAME', '')
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')
    release = env_vars.get('CBFLOW_RELEASE_VERSION', '')

    print()
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

    # Show progress while thread runs
    for i, (step_name, step_time) in enumerate(steps):
        pct = int((i / total_steps) * 100)
        filled = int(bar_width * i / total_steps)
        bar = '\033[32m' + '#' * filled + '\033[0m' + '-' * (bar_width - filled)
        sys.stdout.write(f"\r  [{bar}] {pct:3d}%  {step_name}...")
        sys.stdout.flush()
        _time.sleep(step_time)

    # Wait for creation to finish
    create_thread.join()

    # Final 100%
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
        print(f"  \033[32m{'=' * 60}\033[0m")
        print(f"  \033[32;1mRun Created Successfully\033[0m")
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

    # Parse stamps
    stamps_dir = os.path.join(run_dir, '.stamps')
    if os.path.exists(stamps_dir):
        all_stamps = sorted([f for f in os.listdir(stamps_dir) if f.endswith('.stamp')])
        info['subnodes_completed'] = len(all_stamps)

        info['completed_list'] = [s.replace('.stamp', '') for s in all_stamps]

        # Get total stages from flow config and count completed by matching config names
        try:
            from tcl_config_parser import get_flow_stages
            stages = get_flow_stages(info['flow_type'])
            info['stages_total'] = len(stages)
            # Count completed by matching stamp names against config stage names
            stamp_names = set(s.replace('.stamp', '') for s in all_stamps)
            completed_count = 0
            for stage in stages:
                # Check both unsuffixed and suffixed forms
                if stage in stamp_names or f"{stage}1" in stamp_names:
                    completed_count += 1
            info['stages_completed'] = completed_count
        except Exception:
            # Fallback: count stamps that have a matching .stamp (no subnode suffix)
            info['stages_total'] = 0
            info['stages_completed'] = len(all_stamps)

        # Last activity timestamp
        if all_stamps:
            last_stamp = os.path.join(stamps_dir, all_stamps[-1])
            mtime = os.path.getmtime(last_stamp)
            info['last_activity'] = datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S')

        # Determine status
        if info['stages_total'] > 0 and info['stages_completed'] >= info['stages_total']:
            info['status'] = 'completed'
        elif info['stages_completed'] > 0:
            info['status'] = 'in progress'
    else:
        try:
            from tcl_config_parser import get_flow_stages
            stages = get_flow_stages(info['flow_type'])
            info['stages_total'] = len(stages)
        except Exception:
            pass

    # Check for Makefile
    info['has_makefile'] = False  # Makefile no longer generated — engine is default

    return info


def cmd_list_runs(args: argparse.Namespace) -> int:
    """List all existing runs in workspace."""
    if not is_workspace_initialized():
        logger.error(f"Workspace not initialized. Run 'cbflow workspace init' first.")
        return 1

    logger.info("")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info(f"  CBFlow Runs in Workspace")
    logger.info(f"═══════════════════════════════════════════════════════════════")
    logger.info("")

    runs = sorted([d for d in os.listdir('.') if os.path.isdir(d) and '_run_' in d])

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

    stamps_dir = os.path.join(run_dir, '.stamps')
    stamp_times = {}
    if os.path.exists(stamps_dir):
        for sf in os.listdir(stamps_dir):
            if sf.endswith('.stamp'):
                name = sf.replace('.stamp', '')
                stamp_times[name] = os.path.getmtime(os.path.join(stamps_dir, sf))

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
        stage_key = stage if stage in stamp_times else f"{stage}1"
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
        stage_key = stage if stage in stamp_times else f"{stage}1"
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
        logger.error("Workspace not initialized. Run 'cbflow workspace init' first.")
        return 1

    run_dir = args.run
    if not os.path.isdir(run_dir):
        logger.error(f"Run directory not found: {run_dir}")
        logger.info("")
        logger.info("Available runs:")
        runs = [d for d in os.listdir('.') if os.path.isdir(d) and '_run_' in d]
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

    stamps_dir = os.path.join(run_dir, '.stamps')
    completed_stamps = set()
    stamp_times = {}
    if os.path.exists(stamps_dir):
        for sf in os.listdir(stamps_dir):
            if sf.endswith('.stamp'):
                name = sf.replace('.stamp', '')
                completed_stamps.add(name)
                stamp_times[name] = os.path.getmtime(os.path.join(stamps_dir, sf))

    if stages:
        for stage in stages:
            # Check both suffixed and unsuffixed
            stage_done = stage in completed_stamps or f"{stage}1" in completed_stamps
            stage_key = stage if stage in completed_stamps else f"{stage}1"
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
        logger.error("Workspace not initialized. Run 'cbflow workspace init' first.")
        return 1

    runs = [d for d in os.listdir('.') if os.path.isdir(d) and '_run_' in d]

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
        runs = sorted([d for d in os.listdir('.') if os.path.isdir(d) and '_run_' in d])
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
        runs = sorted([d for d in os.listdir('.') if os.path.isdir(d) and '_run_' in d])

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
        logger.info("  Initialize with:")
        logger.info("    cbflow workspace init --project <name> --flow <type>")

    logger.info("")
    return 0


def cmd_update(args: argparse.Namespace) -> int:
    """Update workspace to new release."""
    if not is_workspace_initialized():
        logger.error("Workspace not initialized. Run 'cbflow workspace init' first.")
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
                              help='Force recreate if run directory already exists')

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
