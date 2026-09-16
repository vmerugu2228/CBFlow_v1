#!/usr/bin/env python3
"""
Hierarchical Release Manager - Python Backend

Description: Release management for hierarchical config/scripts structure
Version: 1.0.0
Author: Flow Management System
"""

import os
import json
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional
import shutil
import sys

# Import color utilities
from color_utils import (
    print_success, print_error, print_warning, print_info, print_header,
    print_section, printer, Icons, Colors, colorize
)


class HierarchicalReleaseManager:
    """Handle hierarchical release creation and management"""

    def __init__(self):
        self.version = "1.0.0"

    def create_release_flow(self, release_version: str, description: str = "",
                          milestone: str = "", version_overrides: str = ""):
        """Create a complete release flow"""
        print(f"Creating release {release_version}...")

        # Create release directory structure
        release_dir = Path("releases") / release_version
        self._create_release_structure(release_dir)

        # Collect current versions from hierarchical structure
        components = self._collect_current_versions()

        # Apply version overrides if provided
        if version_overrides:
            components = self._apply_version_overrides(components, version_overrides)

        # Bundle components
        self._bundle_components(release_dir, components)

        # Generate manifest
        self._generate_manifest(release_dir, release_version, description, milestone, components)

        # Generate changelog
        self._generate_changelog(release_dir, release_version, description, milestone, components)

        # Generate flow release config
        self._generate_flow_release_config(release_dir, release_version, description, components)

        # Update current release symlink
        self._update_current_symlink(release_version)

        print_success(f"Release {release_version} created successfully!", Icons.ROCKET)
        return str(release_dir)

    def _create_release_structure(self, release_dir: Path):
        """Create release directory structure"""
        release_dir.mkdir(parents=True, exist_ok=True)
        (release_dir / "bundled_versions").mkdir(exist_ok=True)
        (release_dir / "metadata").mkdir(exist_ok=True)
        (release_dir / "packages").mkdir(exist_ok=True)
        (release_dir / "documentation").mkdir(exist_ok=True)

    def _collect_current_versions(self) -> Dict[str, str]:
        """Collect current versions using comprehensive discovery (same logic as TCL auto-discovery)"""
        components = {}

        # Use comprehensive discovery like our TCL script
        print_info("Running comprehensive version discovery...", Icons.PACKAGE)

        # Discover script versions
        scripts_dir = Path("scripts")
        if scripts_dir.exists():
            for script_dir in scripts_dir.iterdir():
                if script_dir.is_dir():
                    # Find version directories (v*)
                    version_dirs = [d for d in script_dir.iterdir()
                                  if d.is_dir() and d.name.startswith('v')]
                    if version_dirs:
                        # Get latest version (simple sort)
                        latest_version = sorted([d.name for d in version_dirs])[-1]
                        components[f"utils/{script_dir.name}"] = latest_version
                        print(f"  📁 Script: {script_dir.name} -> {latest_version}")

        # Discover config versions
        config_dir = Path("config")
        if config_dir.exists():
            # Flow configs (flow, version, flow_release)
            for config_name in ["flow", "version", "flow_release"]:
                config_path = config_dir / config_name
                if config_path.exists():
                    version_dirs = [d for d in config_path.iterdir()
                                  if d.is_dir() and d.name.startswith('v')]
                    if version_dirs:
                        latest_version = sorted([d.name for d in version_dirs])[-1]
                        components[f"config/{config_name}"] = latest_version
                        print(f"  📁 Config: {config_name} -> {latest_version}")

            # Project configs
            project_dir = config_dir / "project"
            if project_dir.exists():
                for proj in project_dir.iterdir():
                    if proj.is_dir():
                        version_dirs = [d for d in proj.iterdir()
                                      if d.is_dir() and d.name.startswith('v')]
                        if version_dirs:
                            latest_version = sorted([d.name for d in version_dirs])[-1]
                            components[f"config/project/{proj.name}"] = latest_version
                            print(f"  📁 Project: {proj.name} -> {latest_version}")

            # Technology configs
            tech_dir = config_dir / "technology"
            if tech_dir.exists():
                for tech in tech_dir.iterdir():
                    if tech.is_dir():
                        version_dirs = [d for d in tech.iterdir()
                                      if d.is_dir() and d.name.startswith('v')]
                        if version_dirs:
                            latest_version = sorted([d.name for d in version_dirs])[-1]
                            components[f"config/technology/{tech.name}"] = latest_version
                            print(f"  📁 Technology: {tech.name} -> {latest_version}")

            # EDA configs
            eda_dir = config_dir / "eda"
            if eda_dir.exists():
                for flow in eda_dir.iterdir():
                    if flow.is_dir():
                        for vendor in flow.iterdir():
                            if vendor.is_dir():
                                for tool in vendor.iterdir():
                                    if tool.is_dir():
                                        version_dirs = [d for d in tool.iterdir()
                                                      if d.is_dir() and d.name.startswith('v')]
                                        if version_dirs:
                                            latest_version = sorted([d.name for d in version_dirs])[-1]
                                            eda_key = f"config/eda/{flow.name}/{vendor.name}/{tool.name}"
                                            components[eda_key] = latest_version
                                            print(f"  📁 EDA Config: {flow.name}_{vendor.name}_{tool.name} -> {latest_version}")

        # Discover command versions
        cmds_dir = Path("cmds")
        if cmds_dir.exists():
            for flow in cmds_dir.iterdir():
                if flow.is_dir():
                    for vendor in flow.iterdir():
                        if vendor.is_dir():
                            for tool in vendor.iterdir():
                                if tool.is_dir():
                                    version_dirs = [d for d in tool.iterdir()
                                                  if d.is_dir() and d.name.startswith('v')]
                                    if version_dirs:
                                        latest_version = sorted([d.name for d in version_dirs])[-1]
                                        cmd_key = f"cmds/{flow.name}/{vendor.name}/{tool.name}"
                                        components[cmd_key] = latest_version
                                        print(f"  📁 Command: {flow.name}_{vendor.name}_{tool.name} -> {latest_version}")

        # Discover release versions
        releases_dir = Path("releases")
        if releases_dir.exists():
            version_dirs = [d for d in releases_dir.iterdir()
                          if d.is_dir() and d.name.startswith('v')]
            if version_dirs:
                latest_version = sorted([d.name for d in version_dirs])[-1]
                components["releases"] = latest_version
                print(f"  📁 Releases: releases -> {latest_version}")

        print_success(f"Discovered {len(components)} components with versions", Icons.ROCKET)
        return components

    def _apply_version_overrides(self, components: Dict[str, str], overrides: str) -> Dict[str, str]:
        """Apply version overrides to components"""
        for override in overrides.split(","):
            if ":" in override:
                comp_name, comp_version = override.split(":", 1)
                comp_name = comp_name.strip()
                comp_version = comp_version.strip()
                components[comp_name] = comp_version
                print(f"Override: {comp_name} -> {comp_version}")
        return components

    def _bundle_components(self, release_dir: Path, components: Dict[str, str]):
        """Bundle components into release using symlinks"""
        bundled_dir = release_dir / "bundled_versions"

        for comp_name, comp_version in components.items():
            print_info(f"Linking {comp_name}:{comp_version}", Icons.PACKAGE)

            source_dir = Path(comp_name) / comp_version
            target_dir = bundled_dir / comp_name

            if source_dir.exists():
                # Create parent directories if needed
                target_dir.parent.mkdir(parents=True, exist_ok=True)

                # Create symlink to the version directory
                try:
                    if target_dir.exists() or target_dir.is_symlink():
                        if target_dir.is_symlink():
                            target_dir.unlink()
                        else:
                            shutil.rmtree(target_dir)

                    # Convert to absolute paths for reliable symlinks
                    abs_source = source_dir.resolve()
                    target_dir.symlink_to(abs_source, target_is_directory=True)
                    print(f"  🔗 Created symlink: {target_dir} -> {abs_source}")

                except Exception as e:
                    print(f"Warning: Failed to create symlink for {comp_name}: {e}")
            else:
                print(f"Warning: {source_dir} not found")

    def _generate_manifest(self, release_dir: Path, release_version: str,
                          description: str, milestone: str, components: Dict[str, str]):
        """Generate release manifest"""
        manifest_file = release_dir / "MANIFEST.json"

        manifest_data = {
            "release_version": release_version,
            "created_date": datetime.now().isoformat(),
            "description": description,
            "components": components
        }

        if milestone:
            manifest_data["milestone"] = milestone

        try:
            with open(manifest_file, 'w', encoding='utf-8') as f:
                json.dump(manifest_data, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"Error writing manifest: {e}")

    def _generate_changelog(self, release_dir: Path, release_version: str,
                          description: str, milestone: str, components: Dict[str, str]):
        """Generate release changelog"""
        changelog_file = release_dir / "CHANGELOG.md"

        content = f"""# Release {release_version}

**Release Date:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
**Description:** {description}
"""

        if milestone:
            content += f"**Milestone:** {milestone}\n"

        content += "\n## Changes from Previous Release\n\n"
        content += "- Enhanced to include all components (flow, scripts, docs, config, cmds)\n"

        content += "\n## Component Versions\n\n"
        for comp_name, comp_version in sorted(components.items()):
            content += f"- **{comp_name}**: {comp_version}\n"

        try:
            with open(changelog_file, 'w', encoding='utf-8') as f:
                f.write(content)
        except Exception as e:
            print(f"Error writing changelog: {e}")

    def _generate_flow_release_config(self, release_dir: Path, release_version: str,
                                    description: str, components: Dict[str, str]):
        """Generate flow_release_config.tcl file for TCL initialization system"""
        config_dir = Path("config/flow_release") / release_version
        config_dir.mkdir(parents=True, exist_ok=True)

        config_file = config_dir / "flow_release_config.tcl"

        # Organize components by type
        project_versions = {}
        technology_versions = {}
        config_versions = {}
        script_versions = {}

        for comp_name, comp_version in components.items():
            if comp_name.startswith("config/project/"):
                project_name = comp_name.split("/")[2]
                project_versions[project_name] = comp_version
            elif comp_name.startswith("config/technology/"):
                tech_name = comp_name.split("/")[2]
                technology_versions[tech_name] = comp_version
            elif comp_name.startswith("config/"):
                config_name = comp_name.split("/")[-1]
                config_versions[config_name] = comp_version
            elif comp_name.startswith("utils/"):
                script_name = comp_name.split("/")[-1]
                script_versions[script_name] = comp_version

        try:
            with open(config_file, 'w', encoding='utf-8') as f:
                f.write(f"""# Flow Release Configuration {release_version}
# Defines all component versions for this flow release
# All config scripts, projects, and technology versions included in this release

#===============================================================================
# FLOW RELEASE INFORMATION
#===============================================================================

# Release metadata
array set release_info {{
    version "{release_version}"
    name "Flow Management System Release {release_version}"
    description "{description}"
    release_date "{datetime.now().strftime('%Y-%m-%d')}"
    status "stable"
    compatibility "{release_version.split('.')[0]}.x"
}}

#===============================================================================
# CONFIG VERSIONS - All configuration script versions for this release
#===============================================================================

# Flow configuration versions
array set config_versions {{
""")
                for config_name, version in config_versions.items():
                    f.write(f'    {config_name} "{version}"\n')

                f.write("""
}

#===============================================================================
# PROJECT VERSIONS - Supported project configurations in this release
#===============================================================================

# Project configuration versions
array set project_versions {
""")
                for project_name, version in project_versions.items():
                    f.write(f'    {project_name} "{version}"\n')

                f.write("""
}

#===============================================================================
# TECHNOLOGY VERSIONS - Technology node configurations in this release
#===============================================================================

# Technology configuration versions
array set technology_versions {
""")
                for tech_name, version in technology_versions.items():
                    f.write(f'    {tech_name} "{version}"\n')

                f.write("""
}

#===============================================================================
# SCRIPT VERSIONS - Flow utility script versions
#===============================================================================

# Script versions included in this release
array set script_versions {
""")
                for script_name, version in script_versions.items():
                    f.write(f'    {script_name} "{version}"\n')

                f.write(f"""
}}

#===============================================================================
# TOOL VERSIONS - External tool compatibility
#===============================================================================

# External tool versions validated for this release
array set tool_versions {{
    tcl_version "8.6"
    make_version "4.0"
    git_version "2.0"
    shell_version "bash-5.0"
}}

#===============================================================================
# RELEASE UTILITY FUNCTIONS
#===============================================================================

# Get release information
proc get_release_info {{key}} {{
    global release_info
    if {{[info exists release_info($key)]}} {{
        return $release_info($key)
    }}
    return ""
}}

# Get config version for a specific component
proc get_config_version {{component}} {{
    global config_versions
    if {{[info exists config_versions($component)]}} {{
        return $config_versions($component)
    }}
    return "current"
}}

# Get project version
proc get_project_version {{project_name}} {{
    global project_versions
    if {{[info exists project_versions($project_name)]}} {{
        return $project_versions($project_name)
    }}
    return ""
}}

# Get technology version
proc get_technology_version {{tech_name}} {{
    global technology_versions
    if {{[info exists technology_versions($tech_name)]}} {{
        return $technology_versions($tech_name)
    }}
    return ""
}}

# Get script version
proc get_script_version {{script_name}} {{
    global script_versions
    if {{[info exists script_versions($script_name)]}} {{
        return $script_versions($script_name)
    }}
    return "current"
}}

# Get all supported projects for this release
proc get_supported_projects {{}} {{
    global project_versions
    return [array names project_versions]
}}

# Get all supported technologies for this release
proc get_supported_technologies {{}} {{
    global technology_versions
    return [array names technology_versions]
}}

# Validate if a project/technology combination is supported
proc validate_project_technology {{project_name tech_name}} {{
    set project_version [get_project_version $project_name]
    set tech_version [get_technology_version $tech_name]

    if {{$project_version eq "" || $tech_version eq ""}} {{
        return false
    }}
    return true
}}

#===============================================================================
# PATH GENERATION BASED ON RELEASE CONFIG
#===============================================================================

# Generate paths based on release configuration
proc generate_release_paths {{project_root project_name tech_name}} {{
    set project_version [get_project_version $project_name]
    set tech_version [get_technology_version $tech_name]
    set config_version [get_config_version "flow_config"]
    set utils_version [get_script_version "flow_utils"]

    if {{$project_version eq ""}} {{
        error "Project '$project_name' not supported in this release"
    }}

    if {{$tech_version eq ""}} {{
        error "Technology '$tech_name' not supported in this release"
    }}

    set paths [dict create \\
        project_config [file join $project_root "config" "project" $project_name $project_version] \\
        tech_config [file join $project_root "config" "technology" $tech_name $tech_version] \\
        flow_config [file join $project_root "config" "flow" $config_version] \\
        utils_root [file join $project_root "scripts" "flow_utils" $utils_version] \\
        release_config [file join $project_root "config" "flow_release" [get_release_info version]] \\
    ]

    return $paths
}}

#===============================================================================
# RELEASE VALIDATION
#===============================================================================

# Validate that all required components exist for this release
proc validate_release_components {{project_root}} {{
    set validation_errors {{}}

    # Check flow config exists
    set flow_config_path [file join $project_root "config" "flow" [get_config_version "flow_config"]]
    if {{![file exists $flow_config_path]}} {{
        lappend validation_errors "Flow config directory missing: $flow_config_path"
    }}

    # Check utils exist
    set utils_path [file join $project_root "scripts" "flow_utils" [get_script_version "flow_utils"]]
    if {{![file exists $utils_path]}} {{
        lappend validation_errors "Flow utils directory missing: $utils_path"
    }}

    # Check each supported project exists
    foreach project [get_supported_projects] {{
        set project_path [file join $project_root "config" "project" $project [get_project_version $project]]
        if {{![file exists $project_path]}} {{
            lappend validation_errors "Project config missing: $project_path"
        }}
    }}

    # Check each supported technology exists
    foreach tech [get_supported_technologies] {{
        set tech_path [file join $project_root "config" "technology" $tech [get_technology_version $tech]]
        if {{![file exists $tech_path]}} {{
            lappend validation_errors "Technology config missing: $tech_path"
        }}
    }}

    return $validation_errors
}}

#===============================================================================
# COMPATIBILITY FUNCTIONS
#===============================================================================

# Check if current environment is compatible with this release
proc check_environment_compatibility {{}} {{
    global tool_versions
    set compatibility_issues {{}}

    # Check TCL version
    set current_tcl [info tclversion]
    set required_tcl $tool_versions(tcl_version)
    if {{[package vcompare $current_tcl $required_tcl] < 0}} {{
        lappend compatibility_issues "TCL version $current_tcl < required $required_tcl"
    }}

    return $compatibility_issues
}}

#===============================================================================
# RELEASE SUMMARY
#===============================================================================

# Print complete release summary
proc print_release_summary {{}} {{
    global release_info project_versions technology_versions config_versions

    puts "🚀 Flow Release Summary"
    puts "======================="
    puts ""
    puts "Release Information:"
    puts "  Version:     [get_release_info version]"
    puts "  Name:        [get_release_info name]"
    puts "  Description: [get_release_info description]"
    puts "  Date:        [get_release_info release_date]"
    puts "  Status:      [get_release_info status]"
    puts ""

    puts "Supported Projects:"
    foreach project [lsort [array names project_versions]] {{
        puts "  $project: $project_versions($project)"
    }}
    puts ""

    puts "Supported Technologies:"
    foreach tech [lsort [array names technology_versions]] {{
        puts "  $tech: $technology_versions($tech)"
    }}
    puts ""

    puts "Config Versions:"
    foreach config [lsort [array names config_versions]] {{
        puts "  $config: $config_versions($config)"
    }}
    puts ""
}}

# Load validation on source
set compatibility_issues [check_environment_compatibility]
if {{[llength $compatibility_issues] > 0}} {{
    puts "WARNING: Environment compatibility issues:"
    foreach issue $compatibility_issues {{
        puts "  - $issue"
    }}
}} else {{
    puts "✅ Flow Release Config loaded: [get_release_info version]"
    puts "   Projects: [llength [get_supported_projects]], Technologies: [llength [get_supported_technologies]]"
}}
""")

            print_success(f"Generated flow_release_config.tcl for {release_version}", Icons.GEAR)

        except Exception as e:
            print_error(f"Error generating flow_release_config.tcl: {e}")

    def _update_current_symlink(self, release_version: str):
        """Update current release symlink"""
        releases_dir = Path("releases")
        current_link = releases_dir / "current"

        try:
            if current_link.exists():
                current_link.unlink()
            current_link.symlink_to(release_version)
        except Exception as e:
            print(f"Warning: Could not update current symlink: {e}")


def main():
    """Command line interface"""
    if len(sys.argv) < 3:
        print("Usage: hierarchical_release_manager.py <version> <description> [milestone] [overrides]")
        print("Example: hierarchical_release_manager.py v1.0.0 'Initial release' '' ''")
        sys.exit(1)

    try:
        manager = HierarchicalReleaseManager()

        version = sys.argv[1]
        description = sys.argv[2] if len(sys.argv) > 2 else ""
        milestone = sys.argv[3] if len(sys.argv) > 3 else ""
        overrides = sys.argv[4] if len(sys.argv) > 4 else ""

        manager.create_release_flow(version, description, milestone, overrides)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()