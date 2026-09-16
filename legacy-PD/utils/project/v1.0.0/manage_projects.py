#!/usr/bin/env python3
"""
CBFlow Project Management CLI
Interactive tool for managing CBFlow projects and release associations
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path


# Available flow types in CBFlow
AVAILABLE_FLOWS = {
    "SYNTH": "Logic synthesis and optimization",
    "FP": "Floorplanning and power planning",
    "PNR": "Place and route implementation",
    "LEC": "Logic equivalence checking",
    "EMIR": "Power and thermal analysis",
    "ECO": "Engineering change orders",
    "CLP": "Conformal low power verification",
    "POPT": "Power optimization and clock gating",
    "FCFP": "Fullchip floorplanning"
}

# Project phases (from flow_config.tcl)
PROJECT_PHASES = {
    "P0": "Initial implementation and prototyping",
    "P1": "Design refinement and optimization",
    "P2": "Final implementation and sign-off",
    "P3": "Production and manufacturing release"
}


class ProjectManager:
    def __init__(self, config_file, core_dir):
        self.config_file = Path(config_file)
        self.core_dir = Path(core_dir)
        self.mapping_file = self.core_dir / "config" / "project_release_mapping.tcl"
        self.releases_dir = self.core_dir / "workarea" / "releases"
        self.technology_dir = self.core_dir / "config" / "technology"
        self.data = self.load_config()
        self.release_mappings = self.load_release_mappings()
        self.current_user = self.get_current_user()
        self.available_flows = AVAILABLE_FLOWS
        # Track pending changes
        self.has_pending_changes = False
        self.pending_changes = []  # List of change descriptions
        # Store original state for discard
        self._original_data = json.dumps(self.data)
        self._original_mappings = dict(self.release_mappings)

    def get_current_user(self):
        """Get current system user"""
        return os.environ.get('USER', os.environ.get('USERNAME', 'unknown'))

    def load_config(self):
        """Load existing config or create new one"""
        if self.config_file.exists():
            with open(self.config_file, 'r') as f:
                return json.load(f)
        else:
            return {
                "metadata": {
                    "version": "1.0",
                    "last_updated": datetime.now().strftime("%Y-%m-%d"),
                    "description": "CBFlow Master Project Registry"
                },
                "projects": {}
            }

    def mark_pending(self, change_description):
        """Mark that there are pending changes"""
        self.has_pending_changes = True
        self.pending_changes.append(change_description)
        print(f"\n[+] Change staged: {change_description}")
        print("   (Use 'Save all changes' from main menu to persist)")

    def save_all_changes(self):
        """Save all pending changes to files"""
        if not self.has_pending_changes:
            print("\n   No pending changes to save.")
            return False

        print("\n" + "=" * 60)
        print("  Review Pending Changes")
        print("=" * 60)
        print("\n  The following changes will be saved:\n")
        for i, change in enumerate(self.pending_changes, 1):
            print(f"    {i}. {change}")
        print()

        if not self.get_yes_no("  Save all changes?", "y"):
            print("\n[X] Save cancelled. Changes are still pending.")
            return False

        # Actually save the config
        self.data["metadata"]["last_updated"] = datetime.now().strftime("%Y-%m-%d")
        self.config_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_file, 'w') as f:
            json.dump(self.data, f, indent=2)
        print(f"\n[OK] Project configuration saved to: {self.config_file}")

        # Save release mappings if changed
        if self.release_mappings != self._original_mappings:
            self._save_release_mappings_to_file()
            print(f"[OK] Release mappings saved to: {self.mapping_file}")

        # Reset pending state
        self.has_pending_changes = False
        self.pending_changes = []
        self._original_data = json.dumps(self.data)
        self._original_mappings = dict(self.release_mappings)

        print(f"\n[OK] All {len(self.pending_changes) if self.pending_changes else 'pending'} changes saved successfully!")
        return True

    def discard_all_changes(self):
        """Discard all pending changes"""
        if not self.has_pending_changes:
            print("\n   No pending changes to discard.")
            return

        print("\n[!]  The following changes will be discarded:\n")
        for i, change in enumerate(self.pending_changes, 1):
            print(f"    {i}. {change}")
        print()

        if not self.get_yes_no("  Discard all changes?", "n"):
            print("\n[X] Discard cancelled. Changes are still pending.")
            return

        # Restore original state
        self.data = json.loads(self._original_data)
        self.release_mappings = dict(self._original_mappings)
        self.has_pending_changes = False
        self.pending_changes = []

        print("\n[OK] All pending changes discarded. Restored to last saved state.")

    def _save_release_mappings_to_file(self):
        """Internal method to save release mappings to TCL file"""
        self.mapping_file.parent.mkdir(parents=True, exist_ok=True)

        with open(self.mapping_file, 'w') as f:
            f.write("#!/usr/bin/env tclsh\n")
            f.write("# " + "=" * 78 + "\n")
            f.write("# CBFlow Project-Release Mapping\n")
            f.write("# " + "=" * 78 + "\n")
            f.write("# This file maps projects to their associated release versions\n")
            f.write("# Managed by: make manage_projects (Update Release Association)\n")
            f.write("#\n")
            f.write("# Usage:\n")
            f.write("#   source project_release_mapping.tcl\n")
            f.write("#   set release $project_releases(phoenix)  → Get release for phoenix\n")
            f.write("#\n")
            f.write("# DO NOT EDIT MANUALLY - Use manage_projects command\n")
            f.write("# " + "=" * 78 + "\n")
            f.write("\n")
            f.write("# Project → Release Version mapping\n")
            f.write("# Format: project_name \"version\"\n")
            f.write("array set project_releases {\n")

            for project in sorted(self.release_mappings.keys()):
                release = self.release_mappings[project]
                f.write(f"    {project:<15} \"{release}\"\n")

            f.write("}\n")

    def save_config(self):
        """Mark config as changed (legacy compatibility - now uses pending changes)"""
        # This is kept for compatibility but now just marks pending
        self.mark_pending("Project configuration updated")

    def load_release_mappings(self):
        """Load project-release mappings from TCL file"""
        mappings = {}
        if not self.mapping_file.exists():
            return mappings

        try:
            with open(self.mapping_file, 'r') as f:
                content = f.read()
                # Simple parser for TCL array
                # Format: project_name "version"
                import re
                pattern = r'(\w+)\s+"([^"]+)"'
                for match in re.finditer(pattern, content):
                    project, version = match.groups()
                    mappings[project] = version
        except Exception as e:
            print(f"[!]  Warning: Could not load release mappings: {e}")

        return mappings

    def save_release_mappings(self):
        """Mark release mappings as pending (actual save happens in save_all_changes)"""
        # This method is called after updating release_mappings
        # The actual file save happens in save_all_changes
        pass  # Changes are already tracked via mark_pending in update_release

    def get_available_releases(self):
        """Get list of available release versions"""
        releases = []
        if self.releases_dir.exists():
            for release_dir in sorted(self.releases_dir.glob("v*")):
                if release_dir.is_dir():
                    releases.append(release_dir.name)
        return releases

    def get_available_technologies(self):
        """Get list of available technologies from config/technology directory"""
        technologies = []
        if self.technology_dir.exists():
            for tech_dir in sorted(self.technology_dir.iterdir()):
                if tech_dir.is_dir() and not tech_dir.name.startswith('.'):
                    technologies.append(tech_dir.name)
        return technologies

    def select_technology(self, current_tech=None):
        """Interactive technology selection with validation"""
        technologies = self.get_available_technologies()

        if not technologies:
            print("\n  [!] No technologies defined!")
            print("      Create a technology first using: make manage_tech")
            return None

        print("\n  Available Technologies:")
        print("  " + "-" * 50)
        for i, tech in enumerate(technologies, 1):
            marker = " -> " if tech == current_tech else "    "
            print(f"  {marker}{i}. {tech}")
        print("  " + "-" * 50)
        print()

        while True:
            choice = self.get_input("  Select technology (number or name)", required=True)

            # Try as number first
            try:
                idx = int(choice)
                if 1 <= idx <= len(technologies):
                    return technologies[idx - 1]
                else:
                    print(f"  [!] Invalid selection. Please enter 1-{len(technologies)}")
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
                print(f"  [!] Multiple matches: {', '.join(matches)}")
                print("      Please be more specific.")
                continue

            print(f"\n  [X] Technology '{choice}' not found!")
            print("      Available technologies: " + ", ".join(technologies))
            print("      Create new technology using: make manage_tech")
            print()

    def get_date_input(self, prompt, default=None, required=True):
        """Get date input from user with validation (YYYY-MM-DD format)"""
        if default:
            prompt = f"{prompt} [{default}]"
        prompt += " (YYYY-MM-DD): "

        while True:
            value = input(prompt).strip()
            if not value and default:
                return default
            if not value and not required:
                return ""
            if not value:
                print("  [!] This field is required. Please enter a date.")
                continue

            # Validate date format
            try:
                datetime.strptime(value, "%Y-%m-%d")
                return value
            except ValueError:
                print("  [!] Invalid date format. Please use YYYY-MM-DD (e.g., 2025-06-15)")

    def select_phases(self, current_phases=None):
        """Interactive phase selection"""
        if current_phases is None:
            current_phases = list(PROJECT_PHASES.keys())  # Default: all phases

        print("\n  Available Phases:")
        print("  " + "-" * 60)
        phase_list = list(PROJECT_PHASES.keys())

        for i, phase in enumerate(phase_list, 1):
            desc = PROJECT_PHASES[phase]
            marker = "[x]" if phase in current_phases else "[ ]"
            print(f"    {marker} {i}. {phase} - {desc}")

        print("  " + "-" * 60)
        print()
        print("  Enter phase numbers separated by commas (e.g., 1,2,3,4)")
        print("  Or 'all' for all phases, 'none' for no phases")

        selection = input("  Select phases: ").strip().lower()

        if selection == 'all':
            return phase_list
        elif selection == 'none':
            return []
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
                print("  [!] Invalid input. Using all phases.")
                return phase_list

            return selected if selected else phase_list

    def edit_phase_schedule(self, current_schedule=None):
        """Edit detailed phase schedule with dates and milestones"""
        if current_schedule is None:
            current_schedule = {}

        phases = list(PROJECT_PHASES.keys())

        print("\n" + "=" * 70)
        print("  Phase Schedule Editor")
        print("=" * 70)
        print("\n  Configure schedule for each phase.\n")

        schedule = {}
        for phase in phases:
            phase_data = current_schedule.get(phase, {})
            current_start = phase_data.get("start_date", "")
            current_end = phase_data.get("end_date", "")
            current_milestone = phase_data.get("milestone", "")

            print(f"\n  --- {phase}: {PROJECT_PHASES[phase]} ---")

            if current_start or current_end:
                print(f"      Current: {current_start} to {current_end}")
                if current_milestone:
                    print(f"      Milestone: {current_milestone}")

            start_date = self.get_date_input(
                f"    {phase} Start Date",
                default=current_start,
                required=False
            )

            end_date = ""
            if start_date:
                end_date = self.get_date_input(
                    f"    {phase} End Date",
                    default=current_end,
                    required=False
                )

            milestone = ""
            if start_date:
                milestone = self.get_input(
                    f"    {phase} Milestone",
                    default=current_milestone,
                    required=False
                )

            if start_date:
                schedule[phase] = {
                    "start_date": start_date,
                    "end_date": end_date,
                    "milestone": milestone
                }

        return schedule

    def display_phase_schedule(self, schedule):
        """Display phase schedule in a formatted table"""
        if not schedule:
            print("    No schedule defined.")
            return

        print("\n  Phase Schedule:")
        print("  " + "-" * 70)
        print(f"  {'Phase':<6} {'Start':<12} {'End':<12} {'Milestone':<35}")
        print("  " + "-" * 70)

        for phase in PROJECT_PHASES.keys():
            if phase in schedule:
                data = schedule[phase]
                start = data.get("start_date", "N/A")
                end = data.get("end_date", "N/A")
                milestone = data.get("milestone", "")[:35]
                print(f"  {phase:<6} {start:<12} {end:<12} {milestone}")

        print("  " + "-" * 70)

    def is_flow_owner(self, project_name):
        """Check if current user is a flow owner for the project"""
        if project_name not in self.data["projects"]:
            return False

        project = self.data["projects"][project_name]
        flow_owners = project.get("flow_owners", {})

        # Check if user is any of the flow owners
        for role, owner in flow_owners.items():
            if owner.lower() == self.current_user.lower():
                return True

        return False

    def list_projects(self):
        """List all projects in a beautiful table format"""
        projects = self.data.get("projects", {})

        if not projects:
            print("\n No projects defined yet.\n")
            return

        # Table characters
        TL, TR, BL, BR = "╔", "╗", "╚", "╝"
        H, V = "═", "║"
        LT, RT = "╠", "╣"
        HL = "─"  # Light horizontal for inner separators

        print()
        # Title
        print(f"  {TL}{H*76}{TR}")
        print(f"  {V}{'CBFlow Projects':^76}{V}")
        print(f"  {LT}{H*76}{RT}")

        sorted_projects = sorted(projects.items())
        W = 74  # Content width (inside borders)

        for idx, (name, info) in enumerate(sorted_projects):
            status = info.get("status", "active")
            status_icon = "✓" if status == "active" else "○"
            release = info.get("release_version", "N/A")
            technology = info.get("technology", "N/A")
            description = info.get("description", "N/A")
            chip_lead = info.get("chip_lead", "N/A")
            enabled_flows = info.get('enabled_flows', [])
            flow_owners = info.get('flow_owners', {})
            tags = info.get('tags', [])

            # Helper to print a row with proper padding
            def row(content):
                print(f"  {V} {content:<{W}} {V}")

            def separator():
                print(f"  {V} {HL*W} {V}")

            # Project header row
            header = f"{status_icon} Project: {name:<16} Status: [{status.upper():<8}] Release: {release}"
            row(header)
            separator()

            # Details
            desc_display = description[:57] + "..." if len(description) > 60 else description
            row(f"{'Description:':<14}{desc_display}")
            separator()

            tech_chip = f"{technology:<16}  Chip Lead: {chip_lead}"
            row(f"{'Technology:':<14}{tech_chip}")
            separator()

            flows_str = ', '.join(enabled_flows) if enabled_flows else 'None configured'
            if len(flows_str) > 58:
                flows_str = flows_str[:55] + "..."
            row(f"{'Flows:':<14}{flows_str}")
            separator()

            # Flow Owners
            fe = flow_owners.get('frontend', 'N/A')
            be = flow_owners.get('backend', 'N/A')
            ve = flow_owners.get('verification', 'N/A')
            # Truncate if needed
            fe, be, ve = fe[:12], be[:12], ve[:12]
            owners_str = f"FE: {fe:<12} BE: {be:<12} VE: {ve}"
            row(f"{'Flow Owners:':<14}{owners_str}")

            # Tags (if any)
            if tags:
                separator()
                tags_str = ', '.join(tags)
                if len(tags_str) > 58:
                    tags_str = tags_str[:55] + "..."
                row(f"{'Tags:':<14}{tags_str}")

            # Separator or bottom border
            if idx < len(sorted_projects) - 1:
                print(f"  {LT}{H*76}{RT}")
            else:
                print(f"  {BL}{H*76}{BR}")

        print()

    def get_input(self, prompt, default=None, required=True):
        """Get user input with optional default"""
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
                print("  [!]  This field is required. Please enter a value.")

    def get_yes_no(self, prompt, default="n"):
        """Get yes/no confirmation"""
        prompt = f"{prompt} (y/N): " if default == "n" else f"{prompt} (Y/n): "
        while True:
            response = input(prompt).strip().lower()
            if response in ['y', 'yes']:
                return True
            elif response in ['n', 'no', '']:
                return default == 'y'
            else:
                print("  Please enter 'y' or 'n'")

    def select_flows(self, current_flows=None):
        """Interactive flow selection"""
        if current_flows is None:
            current_flows = []

        print("    Available Flows:")
        print("    ─────────────────────────────────────────────────────────")
        flow_list = list(self.available_flows.keys())

        for i, flow in enumerate(flow_list, 1):
            desc = self.available_flows[flow]
            marker = "✓" if flow in current_flows else " "
            print(f"    [{marker}] {i:2}. {flow:<6} - {desc}")

        print("    ─────────────────────────────────────────────────────────")
        print()
        print("    Enter flow numbers separated by commas (e.g., 1,2,3)")

        selection = input("    Select flows: ").strip().lower()

        if selection == 'all':
            return flow_list
        elif selection == 'common':
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
                print("    [!]  Invalid input. Please enter numbers separated by commas.")
                return self.select_flows(current_flows)

            return selected

    def add_project(self):
        """Add a new project"""
        print("\n" + "=" * 80)
        print("  Add New Project")
        print("=" * 80)
        print()

        # Get project name
        name = self.get_input("Project Name (lowercase, no spaces)")

        # Check if exists
        if name in self.data["projects"]:
            print(f"\n[X] Project '{name}' already exists!")
            return

        # Collect project information
        print("\n[+] Enter project details:\n")

        description = self.get_input("Description")
        chip_lead = self.get_input("Chip Lead", default="Not specified", required=False)

        print("\n  Flow Owners:")
        frontend_owner = self.get_input("    Frontend Owner", required=True)
        backend_owner = self.get_input("    Backend Owner", required=True)
        verification_owner = self.get_input("    Verification Owner", required=True)

        flow_owners = {
            "frontend": frontend_owner,
            "backend": backend_owner,
            "verification": verification_owner
        }

        # Technology Selection (must be from existing technologies)
        print("\n  Technology:")
        technology = self.select_technology()
        if not technology:
            print("\n  [X] No technology selected. Project creation cancelled.")
            return

        # Status - new projects are always active
        status = "active"

        # Tags
        tags_input = self.get_input("Tags (comma-separated, e.g., soc,high-performance)", required=False)
        tags = [t.strip() for t in tags_input.split(",")] if tags_input else []

        # Project Phases
        print("\n  Project Phases:")
        print("    Select which phases apply to this project.")
        phases = self.select_phases()

        # Project Timeline
        print("\n  Project Timeline:")
        project_start_date = self.get_date_input("  Project Start Date", required=True)
        tapeout_date = self.get_date_input("  Tapeout Schedule", required=True)

        # Phase Schedule (optional during add, can be detailed in edit)
        phase_schedule = {}
        if self.get_yes_no("  Configure detailed phase schedule now?", "n"):
            phase_schedule = self.edit_phase_schedule()

        # Flow Selection
        print("\n  Flow Configuration:")
        print("    Select which flows to enable for this project.")
        print("    Each enabled flow will have its own workspace path.")
        print()

        enabled_flows = self.select_flows()

        if not enabled_flows:
            print("\n  [!]  No flows selected! At least one flow is required.")
            return

        # Workspace paths per flow
        print("\n  Workspace Paths:")
        print("    Configure workspace path for each enabled flow.")
        print("    Block workspaces will be created at: <workspace_path>/<block_name>/")
        print()

        flow_workspaces = {}
        for flow in enabled_flows:
            flow_workspaces[flow] = self.get_input(
                f"    Workspace path for {flow}",
                required=True
            )

        # Release Version
        print("\n  Release Version:")
        available_releases = self.get_available_releases()
        if available_releases:
            print("    Available releases:")
            for i, rel in enumerate(available_releases, 1):
                print(f"      {i}. {rel}")
            print()
            release_input = self.get_input("    Release version (enter number or version)", required=True)
            try:
                idx = int(release_input)
                if 1 <= idx <= len(available_releases):
                    release_version = available_releases[idx - 1]
                else:
                    release_version = release_input
            except ValueError:
                release_version = release_input
        else:
            release_version = self.get_input("    Release version (e.g., v1.0.0)", required=True)

        # Create project entry
        project_data = {
            "name": name,
            "description": description,
            "chip_lead": chip_lead,
            "flow_owners": flow_owners,
            "technology": technology,
            "status": status,
            "created_date": datetime.now().strftime("%Y-%m-%d"),
            "tags": tags,
            "phases": phases,
            "project_start_date": project_start_date,
            "tapeout_date": tapeout_date,
            "phase_schedule": phase_schedule,
            "release_version": release_version,
            "enabled_flows": enabled_flows,
            "flow_workspaces": flow_workspaces
        }

        # Show summary
        print("\n" + "-" * 80)
        print("  Project Summary:")
        print("-" * 80)
        print(f"  Name:        {name}")
        print(f"  Description: {description}")
        print(f"  Chip Lead:   {chip_lead}")
        print(f"  Flow Owners:")
        print(f"    Frontend:     {flow_owners['frontend']}")
        print(f"    Backend:      {flow_owners['backend']}")
        print(f"    Verification: {flow_owners['verification']}")
        print(f"  Technology:  {technology}")
        print(f"  Status:      {status}")
        print(f"  Phases:      {', '.join(phases)}")
        print(f"  Start Date:  {project_start_date}")
        print(f"  Tapeout:     {tapeout_date}")
        print(f"  Release:     {release_version}")
        print(f"  Flows:       {', '.join(enabled_flows)}")
        print(f"  Flow Workspaces:")
        for flow, path in flow_workspaces.items():
            print(f"    {flow}: {path}")
        if tags:
            print(f"  Tags:        {', '.join(tags)}")
        if phase_schedule:
            self.display_phase_schedule(phase_schedule)
        print()

        if self.get_yes_no("Stage this project for saving?", "y"):
            self.data["projects"][name] = project_data
            self.mark_pending(f"Add project '{name}'")
        else:
            print("\n[X] Project creation cancelled.")

    def edit_project(self, name=None):
        """Edit an existing project - only allowed for flow owners"""
        if not name:
            if not self.data["projects"]:
                print("\n  No projects available to edit.\n")
                return

            print("\n" + "=" * 80)
            print("  Edit Project")
            print("=" * 80)
            print("\nAvailable projects:")
            for proj_name in sorted(self.data["projects"].keys()):
                status = self.data["projects"][proj_name].get("status", "active")
                print(f"  - {proj_name} [{status}]")
            print()

            name = self.get_input("Enter project name to edit")

        if name not in self.data["projects"]:
            print(f"\n  Project '{name}' not found!\n")
            return

        # Check if current user is a flow owner
        if not self.is_flow_owner(name):
            project = self.data["projects"][name]
            flow_owners = project.get("flow_owners", {})
            print(f"\n  ACCESS DENIED: Only flow owners can edit this project!")
            print(f"\n  Current user: {self.current_user}")
            print(f"\n  Project flow owners:")
            print(f"    Frontend:     {flow_owners.get('frontend', 'N/A')}")
            print(f"    Backend:      {flow_owners.get('backend', 'N/A')}")
            print(f"    Verification: {flow_owners.get('verification', 'N/A')}")
            print()
            return

        project = self.data["projects"][name]
        changes_made = False

        while True:
            # Get current values for display
            description = project.get("description", "N/A")
            chip_lead = project.get("chip_lead", "Not specified")
            flow_owners = project.get("flow_owners", {})
            fe_owner = flow_owners.get("frontend", "Not specified")
            be_owner = flow_owners.get("backend", "Not specified")
            ve_owner = flow_owners.get("verification", "Not specified")
            technology = project.get("technology", "Not specified")
            tags = project.get("tags", [])
            tags_str = ", ".join(tags) if tags else "None"
            phases = project.get("phases", list(PROJECT_PHASES.keys()))
            phases_str = ", ".join(phases) if phases else "All"
            start_date = project.get("project_start_date", "Not set")
            tapeout_date = project.get("tapeout_date", "Not set")
            phase_schedule = project.get("phase_schedule", {})
            release = project.get("release_version", "Not Assigned")
            enabled_flows = project.get("enabled_flows", [])
            flows_str = ", ".join(enabled_flows) if enabled_flows else "None"

            print("\n" + "=" * 80)
            print(f"  Edit Project: {name}")
            print("=" * 80)
            print(f"\n  Authenticated as: {self.current_user}")
            print("\n  Select a field to edit:\n")
            print(f"     1. Description       : {description[:45]}{'...' if len(description) > 45 else ''}")
            print(f"     2. Chip Lead         : {chip_lead}")
            print(f"     3. Frontend Owner    : {fe_owner}")
            print(f"     4. Backend Owner     : {be_owner}")
            print(f"     5. Verification Owner: {ve_owner}")
            print(f"     6. Technology        : {technology}")
            print(f"     7. Tags              : {tags_str[:35]}{'...' if len(tags_str) > 35 else ''}")
            print(f"     8. Phases            : {phases_str}")
            print(f"     9. Project Start Date: {start_date}")
            print(f"    10. Tapeout Date      : {tapeout_date}")
            print(f"    11. Phase Schedule    : {len(phase_schedule)} phases configured")
            print(f"    12. Release Version   : {release}")
            print(f"    13. Enabled Flows     : {flows_str[:35]}{'...' if len(flows_str) > 35 else ''}")
            print()
            print("     0. Done - Save changes and return")
            print("     c. Cancel - Discard changes and return")
            print()

            choice = input("  Select field [0-13, c]: ").strip().lower()

            if choice == "0":
                if changes_made:
                    if self.get_yes_no("Stage changes for saving?", "y"):
                        self.data["projects"][name] = project
                        self.mark_pending(f"Edit project '{name}'")
                    else:
                        print("\n  Changes cancelled.")
                else:
                    print("\n  No changes made.")
                break

            elif choice == "c":
                if changes_made:
                    print("\n  Discarding changes...")
                break

            elif choice == "1":
                print(f"\n  Current value: {description}")
                new_value = self.get_input("  New description", default=description, required=False)
                if new_value and new_value != description:
                    project["description"] = new_value
                    changes_made = True
                    print("  [OK] Description updated.")

            elif choice == "2":
                print(f"\n  Current value: {chip_lead}")
                new_value = self.get_input("  New chip lead", default=chip_lead, required=False)
                if new_value and new_value != chip_lead:
                    project["chip_lead"] = new_value
                    changes_made = True
                    print("  [OK] Chip lead updated.")

            elif choice == "3":
                print(f"\n  Current value: {fe_owner}")
                new_value = self.get_input("  New frontend owner", default=fe_owner, required=True)
                if new_value != fe_owner:
                    flow_owners["frontend"] = new_value
                    project["flow_owners"] = flow_owners
                    changes_made = True
                    print("  [OK] Frontend owner updated.")

            elif choice == "4":
                print(f"\n  Current value: {be_owner}")
                new_value = self.get_input("  New backend owner", default=be_owner, required=True)
                if new_value != be_owner:
                    flow_owners["backend"] = new_value
                    project["flow_owners"] = flow_owners
                    changes_made = True
                    print("  [OK] Backend owner updated.")

            elif choice == "5":
                print(f"\n  Current value: {ve_owner}")
                new_value = self.get_input("  New verification owner", default=ve_owner, required=True)
                if new_value != ve_owner:
                    flow_owners["verification"] = new_value
                    project["flow_owners"] = flow_owners
                    changes_made = True
                    print("  [OK] Verification owner updated.")

            elif choice == "6":
                print(f"\n  Current value: {technology}")
                new_value = self.select_technology(current_tech=technology)
                if new_value and new_value != technology:
                    project["technology"] = new_value
                    changes_made = True
                    print("  [OK] Technology updated.")
                elif not new_value:
                    print("  Technology not changed.")

            elif choice == "7":
                print(f"\n  Current value: {tags_str}")
                new_value = self.get_input("  New tags (comma-separated)", default=tags_str if tags else "", required=False)
                new_tags = [t.strip() for t in new_value.split(",")] if new_value else []
                if new_tags != tags:
                    project["tags"] = new_tags
                    changes_made = True
                    print("  [OK] Tags updated.")

            elif choice == "8":
                print(f"\n  Current phases: {phases_str}")
                new_phases = self.select_phases(phases)
                if new_phases != phases:
                    project["phases"] = new_phases
                    changes_made = True
                    print("  [OK] Phases updated.")

            elif choice == "9":
                print(f"\n  Current value: {start_date}")
                new_value = self.get_date_input("  New project start date", default=start_date if start_date != "Not set" else None, required=True)
                if new_value and new_value != start_date:
                    project["project_start_date"] = new_value
                    changes_made = True
                    print("  [OK] Project start date updated.")

            elif choice == "10":
                print(f"\n  Current value: {tapeout_date}")
                new_value = self.get_date_input("  New tapeout date", default=tapeout_date if tapeout_date != "Not set" else None, required=True)
                if new_value and new_value != tapeout_date:
                    project["tapeout_date"] = new_value
                    changes_made = True
                    print("  [OK] Tapeout date updated.")

            elif choice == "11":
                print(f"\n  Current phase schedule:")
                if phase_schedule:
                    self.display_phase_schedule(phase_schedule)
                else:
                    print("    No schedule configured.")
                print()
                new_schedule = self.edit_phase_schedule(phase_schedule)
                if new_schedule != phase_schedule:
                    project["phase_schedule"] = new_schedule
                    changes_made = True
                    print("  [OK] Phase schedule updated.")

            elif choice == "12":
                print(f"\n  Current value: {release}")
                available_releases = self.get_available_releases()
                if available_releases:
                    print("\n  Available releases:")
                    for i, rel in enumerate(available_releases, 1):
                        marker = " -> " if rel == release else "    "
                        print(f"  {marker}{i}. {rel}")
                    print()
                    release_input = self.get_input("  Release version (number or version)", default=release, required=True)
                    try:
                        idx = int(release_input)
                        if 1 <= idx <= len(available_releases):
                            new_release = available_releases[idx - 1]
                        else:
                            new_release = release_input
                    except ValueError:
                        new_release = release_input
                else:
                    new_release = self.get_input("  Release version (e.g., v1.0.0)", default=release, required=True)

                if new_release != release:
                    project["release_version"] = new_release
                    changes_made = True
                    print("  [OK] Release version updated.")

            elif choice == "13":
                print(f"\n  Current flows: {flows_str}")
                print()
                new_flows = self.select_flows(enabled_flows)
                if new_flows and new_flows != enabled_flows:
                    project["enabled_flows"] = new_flows
                    changes_made = True

                    # Update workspace paths for new flows
                    flow_workspaces = project.get("flow_workspaces", {})
                    print("\n  Configure workspace paths for enabled flows:")
                    for flow in new_flows:
                        current_path = flow_workspaces.get(flow, "")
                        flow_workspaces[flow] = self.get_input(
                            f"    Workspace path for {flow}",
                            default=current_path,
                            required=True
                        )
                    # Remove paths for disabled flows
                    flow_workspaces = {k: v for k, v in flow_workspaces.items() if k in new_flows}
                    project["flow_workspaces"] = flow_workspaces
                    print("  [OK] Flows and workspaces updated.")

            else:
                print("\n  Invalid option. Please select 0-13 or 'c'.")

    def toggle_status(self, name=None):
        """Toggle project status between active and inactive - only allowed for flow owners"""
        if not self.data["projects"]:
            print("\n[X] No projects available.\n")
            return

        if not name:
            print("\n" + "=" * 80)
            print("  Toggle Project Status")
            print("=" * 80)
            print("\nAvailable projects:")
            for proj_name in sorted(self.data["projects"].keys()):
                status = self.data["projects"][proj_name].get("status", "active")
                print(f"  - {proj_name} [{status}]")
            print()

            name = self.get_input("Enter project name to toggle status")

        if name not in self.data["projects"]:
            print(f"\n[X] Project '{name}' not found!\n")
            return

        # Check if current user is a flow owner
        if not self.is_flow_owner(name):
            project = self.data["projects"][name]
            flow_owners = project.get("flow_owners", {})
            print(f"\n[X] ACCESS DENIED: Only flow owners can change project status!")
            print(f"\n  Current user: {self.current_user}")
            print(f"\n  Project flow owners:")
            print(f"    Frontend:     {flow_owners.get('frontend', 'N/A')}")
            print(f"    Backend:      {flow_owners.get('backend', 'N/A')}")
            print(f"    Verification: {flow_owners.get('verification', 'N/A')}")
            print()
            return

        project = self.data["projects"][name]
        current_status = project.get("status", "active")
        new_status = "inactive" if current_status == "active" else "active"

        print(f"\n  Current Status: {current_status}")
        print(f"  New Status:     {new_status}")
        print()

        if self.get_yes_no(f"Change status to '{new_status}'?", "y"):
            project["status"] = new_status
            self.data["projects"][name] = project
            self.mark_pending(f"Toggle project '{name}' status: {current_status} → {new_status}")
        else:
            print("\n[X] Status change cancelled.")

    def update_release(self, name=None):
        """Update release association for a project - only allowed for flow owners"""
        if not self.data["projects"]:
            print("\n[X] No projects available.\n")
            return

        if not name:
            print("\n" + "=" * 80)
            print("  Update Release Association")
            print("=" * 80)
            print()

            # Show current mappings
            print("Current Project-Release Mappings:")
            print("-" * 80)
            for proj_name in sorted(self.data["projects"].keys()):
                status = self.data["projects"][proj_name].get("status", "active")
                release = self.release_mappings.get(proj_name, "Not Assigned")
                status_icon = "✓" if status == "active" else "○"
                print(f"  {status_icon} {proj_name:<20} [{status:<8}]  →  {release}")
            print()

            name = self.get_input("Enter project name to update release")

        if name not in self.data["projects"]:
            print(f"\n[X] Project '{name}' not found!\n")
            return

        project = self.data["projects"][name]

        # Check if project is active
        status = project.get("status", "active")
        if status != "active":
            print(f"\n[X] ERROR: Cannot assign release to inactive project!")
            print(f"\n  Project Status: {status.upper()}")
            print("\n  Only ACTIVE projects can be associated with releases.")
            print("\n  To activate this project, use option 3 (Toggle status).")
            print("\n  Note: Only flow owners can change project status.")
            print()
            return

        # Check if current user is a flow owner
        if not self.is_flow_owner(name):
            flow_owners = project.get("flow_owners", {})
            print(f"\n[X] ACCESS DENIED: Only flow owners can update release associations!")
            print(f"\n  Current user: {self.current_user}")
            print(f"\n  Project flow owners:")
            print(f"    Frontend:     {flow_owners.get('frontend', 'N/A')}")
            print(f"    Backend:      {flow_owners.get('backend', 'N/A')}")
            print(f"    Verification: {flow_owners.get('verification', 'N/A')}")
            print()
            return

        # Show available releases
        available_releases = self.get_available_releases()
        if not available_releases:
            print("\n[X] No releases available!")
            print("\n  Create a release first using: cbflow flow release create")
            print()
            return

        print(f"\n  Project: {name}")
        print(f"  Status:  {status.upper()}")
        current_release = self.release_mappings.get(name, "Not Assigned")
        print(f"  Current Release: {current_release}")
        print()

        print("Available Releases:")
        for i, release in enumerate(available_releases, 1):
            marker = "→" if release == current_release else " "
            print(f"  {marker} {i}. {release}")
        print()

        # Get selection
        choice = self.get_input("Select release number (or 'cancel' to abort)")

        if choice.lower() == 'cancel':
            print("\n[X] Release update cancelled.")
            return

        try:
            release_idx = int(choice) - 1
            if release_idx < 0 or release_idx >= len(available_releases):
                print("\n[X] Invalid selection!")
                return

            new_release = available_releases[release_idx]
        except ValueError:
            print("\n[X] Invalid input! Please enter a number.")
            return

        # Confirm
        print()
        print(f"  Project:     {name}")
        print(f"  New Release: {new_release}")
        print()

        if self.get_yes_no("Confirm release association?", "y"):
            old_release = self.release_mappings.get(name, "None")
            self.release_mappings[name] = new_release
            # Also update in project data for consistency
            if name in self.data["projects"]:
                self.data["projects"][name]["release_version"] = new_release
            self.mark_pending(f"Update release for '{name}': {old_release} → {new_release}")
        else:
            print("\n[X] Release update cancelled.")

    def view_project(self, name=None):
        """View detailed project information"""
        if not self.data["projects"]:
            print("\n[X] No projects available.\n")
            return

        if not name:
            print("\n" + "=" * 80)
            print("  View Project Details")
            print("=" * 80)
            print("\nAvailable projects:")
            for proj_name in sorted(self.data["projects"].keys()):
                status = self.data["projects"][proj_name].get("status", "active")
                print(f"  - {proj_name} [{status}]")
            print()

            name = self.get_input("Enter project name to view")

        if name not in self.data["projects"]:
            print(f"\n[X] Project '{name}' not found!\n")
            return

        project = self.data["projects"][name]
        status = project.get("status", "active")
        release = self.release_mappings.get(name, "Not Assigned")

        print("\n" + "=" * 80)
        print(f"  Project: {name}")
        print("=" * 80)
        print(f"\n  Status:       [{status.upper()}]")
        print(f"  Release:      {release}")
        print(f"  Description:  {project.get('description', 'N/A')}")
        print(f"  Chip Lead:    {project.get('chip_lead', 'Not specified')}")
        print(f"\n  Flow Owners:")
        flow_owners = project.get('flow_owners', {})
        print(f"    Frontend:     {flow_owners.get('frontend', 'Not specified')}")
        print(f"    Backend:      {flow_owners.get('backend', 'Not specified')}")
        print(f"    Verification: {flow_owners.get('verification', 'Not specified')}")
        print(f"\n  Technology:   {project.get('technology', 'Not specified')}")
        print(f"  Created:      {project.get('created_date', 'N/A')}")
        if project.get('tags'):
            print(f"  Tags:         {', '.join(project.get('tags', []))}")

        # Show enabled flows and workspaces
        enabled_flows = project.get('enabled_flows', [])
        flow_workspaces = project.get('flow_workspaces', {})

        print(f"\n  Enabled Flows ({len(enabled_flows)}):")
        if enabled_flows:
            print("  ─────────────────────────────────────────────────────────")
            for flow in enabled_flows:
                desc = AVAILABLE_FLOWS.get(flow, "Unknown flow")
                workspace = flow_workspaces.get(flow, "Not configured")
                print(f"    {flow:<6} - {desc}")
                print(f"           Workspace: {workspace}")
            print("  ─────────────────────────────────────────────────────────")
        else:
            print("    No flows enabled")

        print()
        print("  Block Workspace Usage:")
        print("    make init_workspace PROJECT=<project> FLOW=<flow> BLOCK=<block_name>")
        print()
        print("  Example:")
        if enabled_flows:
            sample_flow = enabled_flows[0]
            print(f"    make init_workspace PROJECT={name} FLOW={sample_flow} BLOCK=cpu_core")
        print()

    def select_project(self):
        """Display project selection menu and return selected project name"""
        projects = self.data.get("projects", {})

        print("\n" + "=" * 80)
        print("  Select Project")
        print("=" * 80)

        # Show pending changes indicator
        if self.has_pending_changes:
            print(f"\n  [!]  PENDING CHANGES: {len(self.pending_changes)} unsaved change(s)")

        if not projects:
            print("\n  No projects available.")
            print("\n  Options:")
            print("    1. Add new project")
            if self.has_pending_changes:
                print("    2. [S] Save all changes")
                print("    3. [D]  Discard all changes")
                print("    4. [X] Exit")
            else:
                print("    2. [X] Exit")
            print()
            choice = input("  Select option: ").strip()
            if choice == "1":
                self.add_project()
                return None
            elif self.has_pending_changes and choice == "2":
                self.save_all_changes()
                return None
            elif self.has_pending_changes and choice == "3":
                self.discard_all_changes()
                return None
            elif (self.has_pending_changes and choice == "4") or (not self.has_pending_changes and choice == "2"):
                return "EXIT"
            return None

        # List projects with numbers
        print()
        sorted_projects = sorted(projects.keys())
        for i, proj_name in enumerate(sorted_projects, 1):
            proj = projects[proj_name]
            status = proj.get("status", "active")
            status_icon = "✓" if status == "active" else "○"
            release = proj.get("release_version", "No release")
            print(f"    {i:2}. {status_icon} {proj_name:<20} [{status:<8}] {release}")

        print()
        next_opt = len(sorted_projects) + 1
        print(f"    {next_opt:2}. [+] Add new project")
        next_opt += 1
        print(f"    {next_opt:2}.  List all projects (detailed view)")
        next_opt += 1

        # Save/Discard options if there are pending changes
        save_opt = discard_opt = 0
        if self.has_pending_changes:
            save_opt = next_opt
            print(f"    {next_opt:2}. [S] Save all changes ({len(self.pending_changes)} pending)")
            next_opt += 1
            discard_opt = next_opt
            print(f"    {next_opt:2}. [D]  Discard all changes")
            next_opt += 1

        exit_opt = next_opt
        print(f"    {next_opt:2}. [X] Exit")
        print()

        choice = input("  Select project or option: ").strip()

        try:
            choice_num = int(choice)
            if 1 <= choice_num <= len(sorted_projects):
                return sorted_projects[choice_num - 1]
            elif choice_num == len(sorted_projects) + 1:
                self.add_project()
                return None
            elif choice_num == len(sorted_projects) + 2:
                self.list_projects()
                return None
            elif self.has_pending_changes and choice_num == save_opt:
                self.save_all_changes()
                return None
            elif self.has_pending_changes and choice_num == discard_opt:
                self.discard_all_changes()
                return None
            elif choice_num == exit_opt:
                return "EXIT"
            else:
                print("\n[X] Invalid selection.")
                return None
        except ValueError:
            # Check if they typed a project name directly
            if choice in projects:
                return choice
            print("\n[X] Invalid input. Please enter a number or project name.")
            return None

    def project_menu(self, project_name):
        """Display operations menu for a selected project"""
        if project_name not in self.data["projects"]:
            print(f"\n[X] Project '{project_name}' not found!")
            return

        project = self.data["projects"][project_name]
        status = project.get("status", "active")
        release = project.get("release_version", "Not assigned")
        is_owner = self.is_flow_owner(project_name)

        while True:
            print("\n" + "=" * 80)
            print(f"  Project: {project_name}")
            print("=" * 80)
            print(f"\n  Status:   [{status.upper()}]")
            print(f"  Release:  {release}")
            print()
            if is_owner:
                print(f"  Access:   {self.current_user} [Flow Owner - can edit]")
            else:
                print(f"  Access:   {self.current_user} [Read-only - not a flow owner]")
            print()
            print("  Operations:")
            print("    1. View project details")
            if is_owner:
                print("    2. Edit project")
                print("    3. Toggle status (active/inactive)")
                print("    4. Update release association")
            else:
                print("    2. Edit project (requires flow owner)")
                print("    3. Toggle status (requires flow owner)")
                print("    4. Update release (requires flow owner)")
            print("    5. Back to project selection")
            print()

            choice = input("  Select operation [1-5]: ").strip()

            if choice == "1":
                self.view_project(project_name)
            elif choice == "2":
                self.edit_project(project_name)
            elif choice == "3":
                self.toggle_status(project_name)
                # Refresh status after toggle
                if project_name in self.data["projects"]:
                    status = self.data["projects"][project_name].get("status", "active")
            elif choice == "4":
                self.update_release(project_name)
                # Refresh release after update
                if project_name in self.data["projects"]:
                    release = self.data["projects"][project_name].get("release_version", "Not assigned")
            elif choice == "5":
                break
            else:
                print("\n[X] Invalid option. Please select 1-5.")

    def print_goodbye(self):
        """Print goodbye message with other available manage commands"""
        print("\n" + "=" * 70)
        print("  Thank you for using CBFlow Project Management!")
        print("=" * 70)
        print("\n  Other available management commands:\n")
        print("    cbflow flow config manage-flow  - Manage flow types")
        print("    cbflow flow config manage-node  - Manage nodes and subnodes")
        print("    cbflow flow config manage-tech  - Manage technology configurations")
        print()
        print("  For full command list: cbflow flow --help")
        print()

    def main_menu(self):
        """Display main menu - project-first navigation"""
        while True:
            print("\n" + "=" * 80)
            print("  CBFlow Project Management")
            print("=" * 80)
            print(f"\n  Configuration: {self.config_file}")
            print(f"  Current User:  {self.current_user}")
            print(f"  Total Projects: {len(self.data.get('projects', {}))}")

            # Count active/inactive
            active_count = sum(1 for p in self.data.get('projects', {}).values() if p.get('status') == 'active')
            inactive_count = len(self.data.get('projects', {})) - active_count
            # Count release assignments
            assigned_count = len(self.release_mappings)
            print(f"  Active: {active_count} | Inactive: {inactive_count} | Releases Assigned: {assigned_count}")

            # Select project first
            selected = self.select_project()

            if selected == "EXIT":
                # Check for unsaved changes before exit
                if self.has_pending_changes:
                    print("\n" + "=" * 60)
                    print("  [!]  You have unsaved changes!")
                    print("=" * 60)
                    print("\n  Pending changes:")
                    for i, change in enumerate(self.pending_changes, 1):
                        print(f"    {i}. {change}")
                    print()
                    print("  Options:")
                    print("    1. [S] Save changes and exit")
                    print("    2. [D]  Discard changes and exit")
                    print("    3. [<]  Go back (don't exit)")
                    print()
                    exit_choice = input("  Select option [1-3]: ").strip()
                    if exit_choice == "1":
                        self.save_all_changes()
                        self.print_goodbye()
                        break
                    elif exit_choice == "2":
                        print("\n[D]  Changes discarded.")
                        self.print_goodbye()
                        break
                    elif exit_choice == "3":
                        continue  # Go back to select_project
                    else:
                        continue  # Invalid choice, go back
                else:
                    self.print_goodbye()
                    break
            elif selected:
                self.project_menu(selected)


def main():
    # Detect CORE_DIR
    if "CBFLOW_CORE_DIR" in os.environ:
        core_dir = Path(os.environ["CBFLOW_CORE_DIR"])
    else:
        # Script is in utils/project/v1.0.0/, so core is 3 levels up
        script_dir = Path(__file__).parent.resolve()
        core_dir = script_dir.parent.parent.parent

    config_file = core_dir / "config" / "master_projects.json"

    print("\n" + "=" * 80)
    print("  CBFlow Project Management CLI")
    print("=" * 80)
    print(f"\n  Core Directory:  {core_dir}")
    print(f"  Config File:     {config_file}")
    print()

    manager = ProjectManager(config_file, core_dir)

    # If command-line arguments provided, execute non-interactively
    if len(sys.argv) > 1:
        command = sys.argv[1].lower()
        if command == "list":
            manager.list_projects()
        elif command == "add" and len(sys.argv) > 2:
            # Non-interactive add would need all parameters
            print("[X] Non-interactive add not yet implemented. Use interactive mode.")
        else:
            print(f"[X] Unknown command: {command}")
            print("Usage: manage_projects.py [list]")
    else:
        # Interactive mode
        manager.main_menu()


if __name__ == "__main__":
    main()
