#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Project Command Handler
# Description: Handles project management operations
# Usage: cbflow project <subcommand> [options]
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import os
import sys
import json
import subprocess
import logging
from datetime import datetime
from pathlib import Path

# Configure unified logging
from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.project')

# Available flow types and project phases - loaded from existing Tcl config files
from tcl_config_parser import get_flow_descriptions as _get_flow_desc, get_phase_descriptions as _get_phase_desc
AVAILABLE_FLOWS = _get_flow_desc()
PROJECT_PHASES = _get_phase_desc()

# Version
VERSION = "2.0.0"


def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory from environment or determine from script location."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


def get_projects_file() -> str:
    """Get path to master_projects.json."""
    return os.path.join(get_cbflow_core_dir(), 'config', 'master_projects.json')


def load_projects() -> dict:
    """Load projects from master_projects.json."""
    projects_file = get_projects_file()
    if os.path.exists(projects_file):
        with open(projects_file, 'r') as f:
            return json.load(f)
    return {'version': '1.0', 'active_project': None, 'projects': {}}


def save_projects(data: dict) -> None:
    """Save projects to master_projects.json."""
    projects_file = get_projects_file()
    os.makedirs(os.path.dirname(projects_file), exist_ok=True)
    with open(projects_file, 'w') as f:
        json.dump(data, f, indent=2)


def get_available_technologies() -> list:
    """Get list of available technologies from config/tech directory."""
    core_dir = get_cbflow_core_dir()
    tech_dir = Path(core_dir) / "config" / "tech"
    technologies = []
    if tech_dir.exists():
        for item in sorted(tech_dir.iterdir()):
            if item.is_dir() and not item.name.startswith('.'):
                technologies.append(item.name)
    return technologies


def get_available_releases() -> list:
    """Get list of available release versions from workarea/releases directory."""
    core_dir = get_cbflow_core_dir()
    releases = []

    # Check multiple possible release locations
    release_dirs = [
        Path(core_dir) / "workarea" / "releases",
        Path(core_dir) / "releases",
        Path(core_dir) / "config" / "releases",
    ]

    for releases_dir in release_dirs:
        if releases_dir.exists():
            for item in sorted(releases_dir.glob("v*")):
                if item.is_dir() and item.name not in releases:
                    releases.append(item.name)

    # Also check config/flow for versioned directories
    flow_dir = Path(core_dir) / "config" / "flow"
    if flow_dir.exists():
        for item in sorted(flow_dir.glob("v*")):
            if item.is_dir() and item.name not in releases:
                releases.append(item.name)

    return sorted(releases, reverse=True)  # Most recent first


# ─────────────────────────────────────────────────────────────────────────────────
# Interactive Input Helpers
# ─────────────────────────────────────────────────────────────────────────────────

def get_input(prompt: str, default: str = None, required: bool = True) -> str:
    """Get user input with optional default."""
    if default:
        prompt = f"{prompt} [{default}]"
    prompt += ": "

    while True:
        value = input(prompt).strip()
        if value:
            return value
        elif default:
            return default
        elif not required:
            return ""
        else:
            logger.info("  [WARN] This field is required. Please enter a value.")


def get_yes_no(prompt: str, default: str = "n") -> bool:
    """Get yes/no confirmation."""
    prompt = f"{prompt} (y/N): " if default == "n" else f"{prompt} (Y/n): "
    while True:
        response = input(prompt).strip().lower()
        if response in ['y', 'yes']:
            return True
        elif response in ['n', 'no', '']:
            return default == 'y'
        else:
            logger.info("  Please enter 'y' or 'n'")


def select_technology(current_tech: str = None) -> str:
    """Interactive technology selection."""
    technologies = get_available_technologies()

    if not technologies:
        logger.info("")
        logger.info("  [WARN] No technologies defined in config/tech/")
        logger.info("         Enter technology name manually.")
        return get_input("  Technology", required=True)

    logger.info("")
    logger.info("  Available Technologies:")
    logger.info("  " + "─" * 50)
    for i, tech in enumerate(technologies, 1):
        marker = " -> " if tech == current_tech else "    "
        logger.info(f"  {marker}{i}. {tech}")
    logger.info("  " + "─" * 50)
    logger.info("")

    while True:
        choice = get_input("  Select technology (number or name)", required=True)

        # Try as number first
        try:
            idx = int(choice)
            if 1 <= idx <= len(technologies):
                return technologies[idx - 1]
            else:
                logger.info(f"  [WARN] Invalid selection. Please enter 1-{len(technologies)}")
                continue
        except ValueError:
            pass

        # Try as name
        if choice in technologies:
            return choice

        # Check for partial match
        matches = [t for t in technologies if choice.lower() in t.lower()]
        if len(matches) == 1:
            return matches[0]
        elif len(matches) > 1:
            logger.info(f"  [WARN] Multiple matches: {', '.join(matches)}")
            logger.info("         Please be more specific.")
            continue

        # Allow manual entry if not found
        if get_yes_no(f"  Technology '{choice}' not in list. Use anyway?", "n"):
            return choice
        logger.info("")


def select_flows(current_flows: list = None) -> list:
    """Interactive flow selection."""
    if current_flows is None:
        current_flows = []

    logger.info("")
    logger.info("  Available Flows:")
    logger.info("  " + "─" * 60)
    flow_list = list(AVAILABLE_FLOWS.keys())

    for i, flow in enumerate(flow_list, 1):
        desc = AVAILABLE_FLOWS[flow]
        marker = "[DONE]" if flow in current_flows else "[    ]"
        logger.info(f"    {marker} {i:2}. {flow:<6} - {desc}")

    logger.info("  " + "─" * 60)
    logger.info("")
    logger.info("  Enter flow numbers separated by commas (e.g., 1,2,3)")
    logger.info("  Or 'all' for all flows, 'common' for SYNTH,FP,PNR,STA,LEC,PV")

    selection = input("  Select flows: ").strip().lower()

    if selection == 'all':
        return flow_list
    elif selection == 'common':
        return ["SYNTH", "FP", "PNR", "STA", "LEC", "PV"]
    else:
        selected = []
        try:
            indices = [int(x.strip()) for x in selection.split(",") if x.strip()]
            for idx in indices:
                if 1 <= idx <= len(flow_list):
                    flow = flow_list[idx - 1]
                    if flow not in selected:
                        selected.append(flow)
        except ValueError:
            logger.info("  [WARN] Invalid input. Using common flows.")
            return ["SYNTH", "FP", "PNR", "STA", "LEC", "PV"]

        return selected if selected else ["SYNTH", "FP", "PNR", "STA", "LEC", "PV"]


def select_phases(current_phases: list = None) -> list:
    """Interactive phase selection."""
    if current_phases is None:
        current_phases = list(PROJECT_PHASES.keys())

    logger.info("")
    logger.info("  Available Phases:")
    logger.info("  " + "─" * 60)
    phase_list = list(PROJECT_PHASES.keys())

    for i, phase in enumerate(phase_list, 1):
        desc = PROJECT_PHASES[phase]
        marker = "[DONE]" if phase in current_phases else "[    ]"
        logger.info(f"    {marker} {i}. {phase} - {desc}")

    logger.info("  " + "─" * 60)
    logger.info("")
    logger.info("  Enter phase numbers separated by commas (e.g., 1,2,3,4)")
    logger.info("  Or 'all' for all phases")

    selection = input("  Select phases: ").strip().lower()

    if selection == 'all' or not selection:
        return phase_list
    else:
        selected = []
        try:
            indices = [int(x.strip()) for x in selection.split(",") if x.strip()]
            for idx in indices:
                if 1 <= idx <= len(phase_list):
                    phase = phase_list[idx - 1]
                    if phase not in selected:
                        selected.append(phase)
        except ValueError:
            logger.info("  [WARN] Invalid input. Using all phases.")
            return phase_list

        return selected if selected else phase_list


def select_release(current_release: str = None) -> str:
    """Interactive release version selection."""
    releases = get_available_releases()

    logger.info("")
    logger.info("  Release Version:")

    if not releases:
        logger.info("  [WARN] No existing releases found.")
        logger.info("         Enter release version manually.")
        return get_input("  Release Version (e.g., v1.0.0)", default="v1.0.0", required=True)

    logger.info("  " + "─" * 50)
    for i, rel in enumerate(releases, 1):
        marker = " -> " if rel == current_release else "    "
        logger.info(f"  {marker}{i}. {rel}")
    logger.info("  " + "─" * 50)
    logger.info("")

    while True:
        choice = get_input("  Select release (number or version)", default=releases[0] if releases else "v1.0.0", required=True)

        # Try as number first
        try:
            idx = int(choice)
            if 1 <= idx <= len(releases):
                return releases[idx - 1]
            else:
                logger.info(f"  [WARN] Invalid selection. Please enter 1-{len(releases)}")
                continue
        except ValueError:
            pass

        # Try as version name
        if choice in releases:
            return choice

        # Check for partial match (e.g., "1.0" matches "v1.0.0")
        matches = [r for r in releases if choice in r]
        if len(matches) == 1:
            return matches[0]
        elif len(matches) > 1:
            logger.info(f"  [WARN] Multiple matches: {', '.join(matches)}")
            logger.info("         Please be more specific.")
            continue

        # Allow manual entry if not found
        if get_yes_no(f"  Release '{choice}' not in list. Use anyway?", "n"):
            return choice
        logger.info("")


# ─────────────────────────────────────────────────────────────────────────────────
# Project Commands
# ─────────────────────────────────────────────────────────────────────────────────

def cmd_list(args: argparse.Namespace) -> int:
    """List all projects."""
    projects = load_projects()
    project_list = projects.get('projects', {})

    if not project_list:
        logger.info("")
        logger.info("  No projects found")
        logger.info("")
        logger.info("  Create a project with:")
        logger.info("    cbflow flow project create")
        logger.info("")
        return 0

    logger.info("")
    logger.info("═" * 65)
    logger.info("  CBFlow Projects")
    logger.info("═" * 65)
    logger.info("")
    logger.info(f"  {'Name':<18} {'Technology':<15} {'Status':<10} {'Release'}")
    logger.info("  " + "─" * 60)

    for name, info in sorted(project_list.items()):
        tech = info.get('technology', 'N/A')
        status = info.get('status', 'active').upper()
        release = info.get('release_version', 'N/A')
        logger.info(f"  {name:<18} {tech:<15} {status:<10} {release}")

    logger.info("")
    logger.info(f"  Total: {len(project_list)} project(s)")
    logger.info("")

    return 0


def cmd_info(args: argparse.Namespace) -> int:
    """Show project information."""
    projects = load_projects()
    project_list = projects.get('projects', {})

    if args.name not in project_list:
        logger.error(f"Project not found: {args.name}")
        return 1

    info = project_list[args.name]
    status = info.get('status', 'active')

    logger.info("")
    logger.info("═" * 60)
    logger.info(f"  Project: {args.name}")
    logger.info("═" * 60)
    logger.info("")
    logger.info(f"  Status:          [{status.upper()}]")
    logger.info(f"  Release:         {info.get('release_version', 'N/A')}")
    logger.info("")
    logger.info(f"  Technology:      {info.get('technology', 'N/A')}")
    logger.info(f"  Description:     {info.get('description', '(none)')}")
    logger.info(f"  Created:         {info.get('created', 'N/A')}")

    # Show chip lead
    if 'chip_lead' in info:
        logger.info(f"  Chip Lead:       {info['chip_lead']}")

    # Show flow owners
    owners = info.get('flow_owners', {})
    if owners:
        logger.info("")
        logger.info("  Flow Owners:")
        for role, owner_name in owners.items():
            logger.info(f"    {role:<15}: {owner_name}")

    # Show enabled flows
    flows = info.get('enabled_flows', [])
    logger.info("")
    if flows:
        logger.info(f"  Enabled Flows:   {', '.join(flows)}")
    else:
        logger.info(f"  Enabled Flows:   (none)")

    # Show phases
    phases = info.get('phases', [])
    if phases:
        logger.info(f"  Phases:          {', '.join(phases)}")

    # Show timeline
    start_date = info.get('project_start_date')
    tapeout = info.get('tapeout_date')
    if start_date or tapeout:
        logger.info("")
        logger.info("  Timeline:")
        if start_date:
            logger.info(f"    Start Date:    {start_date}")
        if tapeout:
            logger.info(f"    Tapeout:       {tapeout}")

    logger.info("")

    return 0


def cmd_create(args: argparse.Namespace) -> int:
    """Create a new project - interactive mode."""
    projects = load_projects()
    project_list = projects.setdefault('projects', {})

    # Check if running interactively (no name provided)
    if not getattr(args, 'name', None):
        return cmd_create_interactive(projects, project_list)

    # Non-interactive mode with arguments
    if args.name in project_list:
        logger.error(f"Project already exists: {args.name}")
        return 1

    project_list[args.name] = {
        'technology': args.tech,
        'description': getattr(args, 'description', '') or '',
        'status': 'active',
        'created': datetime.now().isoformat(),
        'enabled_flows': [],
        'design_hierarchy': {},
    }

    save_projects(projects)
    logger.info(f"Project created: {args.name}")
    logger.info("")
    logger.info("Next steps:")
    logger.info(f"  cbflow flow project info --name {args.name}")

    return 0


def cmd_create_interactive(projects: dict, project_list: dict) -> int:
    """Interactive project creation."""
    logger.info("")
    logger.info("═" * 80)
    logger.info("  CBFlow - Create New Project")
    logger.info("═" * 80)
    logger.info("")

    # Get project name
    name = get_input("  Project Name (lowercase, no spaces)")

    # Check if exists
    if name in project_list:
        logger.error(f"Project '{name}' already exists!")
        return 1

    # Collect project information
    logger.info("")
    logger.info("  Enter project details:")
    logger.info("")

    description = get_input("  Description", required=False)
    chip_lead = get_input("  Chip Lead", default="Not specified", required=False)

    logger.info("")
    logger.info("  Flow Owners:")
    frontend_owner = get_input("    Frontend Owner", required=True)
    backend_owner = get_input("    Backend Owner", required=True)
    verification_owner = get_input("    Verification Owner", required=True)

    flow_owners = {
        "frontend": frontend_owner,
        "backend": backend_owner,
        "verification": verification_owner
    }

    # Technology Selection
    logger.info("")
    logger.info("  Technology:")
    technology = select_technology()
    if not technology:
        logger.info("")
        logger.info("  [FAIL] No technology selected. Project creation cancelled.")
        return 1

    # Tags
    tags_input = get_input("  Tags (comma-separated, e.g., soc,high-performance)", required=False)
    tags = [t.strip() for t in tags_input.split(",")] if tags_input else []

    # Project Phases
    logger.info("")
    logger.info("  Project Phases:")
    logger.info("    Select which phases apply to this project.")
    phases = select_phases()

    # Project Timeline
    logger.info("")
    logger.info("  Project Timeline:")
    project_start_date = get_input("  Project Start Date (YYYY-MM-DD)", required=False)
    tapeout_date = get_input("  Tapeout Schedule (YYYY-MM-DD)", required=False)

    # Flow Selection
    logger.info("")
    logger.info("  Flow Configuration:")
    logger.info("    Select which flows to enable for this project.")
    logger.info("")

    enabled_flows = select_flows()

    if not enabled_flows:
        logger.info("")
        logger.info("  [WARN] No flows selected! Using common flows.")
        enabled_flows = ["SYNTH", "FP", "PNR", "STA", "LEC", "PV"]

    # Release Version - select from existing releases
    release_version = select_release()

    # Create project entry
    project_data = {
        "name": name,
        "description": description,
        "chip_lead": chip_lead,
        "flow_owners": flow_owners,
        "technology": technology,
        "status": "active",
        "created": datetime.now().isoformat(),
        "tags": tags,
        "phases": phases,
        "project_start_date": project_start_date,
        "tapeout_date": tapeout_date,
        "release_version": release_version,
        "enabled_flows": enabled_flows,
        "design_hierarchy": {}
    }

    # Show summary
    logger.info("")
    logger.info("─" * 80)
    logger.info("  Project Summary:")
    logger.info("─" * 80)
    logger.info(f"  Name:          {name}")
    logger.info(f"  Description:   {description or '(none)'}")
    logger.info(f"  Chip Lead:     {chip_lead}")
    logger.info(f"  Flow Owners:")
    logger.info(f"    Frontend:      {flow_owners['frontend']}")
    logger.info(f"    Backend:       {flow_owners['backend']}")
    logger.info(f"    Verification:  {flow_owners['verification']}")
    logger.info(f"  Technology:    {technology}")
    logger.info(f"  Status:        active")
    logger.info(f"  Phases:        {', '.join(phases)}")
    if project_start_date:
        logger.info(f"  Start Date:    {project_start_date}")
    if tapeout_date:
        logger.info(f"  Tapeout:       {tapeout_date}")
    logger.info(f"  Release:       {release_version}")
    logger.info(f"  Flows:         {', '.join(enabled_flows)}")
    if tags:
        logger.info(f"  Tags:          {', '.join(tags)}")
    logger.info("")

    if get_yes_no("  Create this project?", "y"):
        project_list[name] = project_data
        save_projects(projects)
        logger.info("")
        logger.info(f"Project created: {name}")
        logger.info("")
        logger.info("Next steps:")
        logger.info(f"  cbflow flow project info --name {name}")
        return 0
    else:
        logger.info("")
        logger.info("  [FAIL] Project creation cancelled.")
        return 1


def cmd_delete(args: argparse.Namespace) -> int:
    """Delete a project - only chip lead can delete, and project must be INACTIVE."""
    projects = load_projects()
    project_list = projects.get('projects', {})

    if args.name not in project_list:
        logger.error(f"Project not found: {args.name}")
        return 1

    project = project_list[args.name]
    current_user = os.environ.get('USER', os.environ.get('USERNAME', 'unknown'))
    chip_lead = project.get('chip_lead', '')
    status = project.get('status', 'active')

    # Check 1: Only chip lead can delete
    if chip_lead.lower() != current_user.lower():
        logger.error(f"ACCESS DENIED: Only the chip lead can delete this project!")
        logger.info(f"  Current user: {current_user}")
        logger.info(f"  Chip Lead:    {chip_lead}")
        return 1

    # Check 2: Cannot delete ACTIVE projects
    if status.lower() == 'active':
        logger.error(f"Cannot delete ACTIVE project!")
        logger.info(f"  Project '{args.name}' is currently ACTIVE.")
        logger.info(f"  Change status to INACTIVE first using:")
        logger.info(f"    cbflow flow project manage")
        return 1

    confirm = getattr(args, 'confirm', False)

    if not confirm:
        logger.warning(f"This will permanently delete project '{args.name}'!")
        logger.info("Use --confirm flag to proceed")
        return 1

    del project_list[args.name]
    save_projects(projects)
    logger.info(f"Project deleted: {args.name}")

    return 0


def cmd_manage(args: argparse.Namespace) -> int:
    """Launch interactive project management."""
    core_dir = get_cbflow_core_dir()

    # Call the existing Python manage_projects script
    manage_script = os.path.join(core_dir, 'utils', 'project', os.environ.get('UTILITIES_VERSION', 'v1.0.0'), 'manage_projects.py')

    if os.path.exists(manage_script):
        try:
            result = subprocess.run(['python3', manage_script])
            return result.returncode
        except Exception as e:
            logger.error(f"Failed to launch project manager: {e}")
            return 1
    else:
        logger.error(f"Project manager not found: {manage_script}")
        return 1


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow project',
        description='CBFlow - Project Management',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow project list
  cbflow flow project info --name phoenix
  cbflow flow project create                        # Interactive mode
  cbflow flow project create --name phoenix --tech tsmc_7nm  # Quick mode
  cbflow flow project delete --name phoenix --confirm
  cbflow flow project manage                        # Full interactive manager
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # list command
    subparsers.add_parser('list', help='List all projects')

    # info command
    info_parser = subparsers.add_parser('info', help='Show project info')
    info_parser.add_argument('--name', '-n', required=True, help='Project name')

    # create command (interactive by default)
    create_parser = subparsers.add_parser('create', help='Create a new project (interactive)')
    create_parser.add_argument('--name', '-n', required=False, help='Project name (optional, prompts if not provided)')
    create_parser.add_argument('--tech', '-t', required=False, help='Technology node (optional, prompts if not provided)')
    create_parser.add_argument('--description', '-d', default='', help='Project description')

    # delete command
    delete_parser = subparsers.add_parser('delete', help='Delete a project')
    delete_parser.add_argument('--name', '-n', required=True, help='Project name')
    delete_parser.add_argument('--confirm', action='store_true', help='Confirm deletion')

    # manage command (interactive)
    subparsers.add_parser('manage', help='Launch interactive project manager')

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
        'info': cmd_info,
        'create': cmd_create,
        'delete': cmd_delete,
        'manage': cmd_manage,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
