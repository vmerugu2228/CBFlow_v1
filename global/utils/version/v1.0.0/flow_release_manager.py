#!/usr/bin/env python3
"""
Flow Release Manager - Python Backend

Description: Streamlined release listing and info management
Version: 1.0.0
Author: Flow Management System
"""

import json
from pathlib import Path
from typing import List, Dict, Optional
import sys

# Import color utilities
from color_utils import (
    print_success, print_error, print_warning, print_info, print_header,
    print_section, printer, Icons, Colors, colorize
)


class FlowReleaseManager:
    """Handle release listing and information display"""

    def __init__(self):
        self.version = "1.0.0"

    def list_available_releases(self):
        """List all available releases"""
        print_header("Available Flow Releases", Icons.PACKAGE)

        releases_dir = Path("releases")
        if not releases_dir.exists():
            print_warning("No releases directory found", Icons.FOLDER)
            return

        # Find all release directories
        release_dirs = [d for d in releases_dir.iterdir()
                       if d.is_dir() and d.name.startswith('v')]

        if not release_dirs:
            print_info("No releases found", Icons.PACKAGE)
            return

        # Sort releases
        sorted_releases = sorted(release_dirs, key=lambda x: x.name)

        for release_dir in sorted_releases:
            release_version = release_dir.name

            if (release_dir / "CHANGELOG.md").exists():
                # Try to get milestone info
                milestone = ""
                description = ""

                manifest_file = release_dir / "MANIFEST.json"
                if manifest_file.exists():
                    try:
                        with open(manifest_file, 'r') as f:
                            manifest = json.load(f)
                            milestone = manifest.get('milestone', '')
                            description = manifest.get('description', '')
                    except Exception:
                        pass

                printer.print_release(release_version, description, milestone)

                # Show milestone if available
                milestone_file = release_dir / "metadata" / "milestone.txt"
                if milestone_file.exists():
                    try:
                        with open(milestone_file, 'r') as f:
                            milestone = f.read().strip()
                        if milestone:
                            print(f"   🎯 Milestone: {milestone}")
                    except Exception:
                        pass

                print("   📝 Available")
                print()

    def get_release_info(self, release_version: str):
        """Get detailed information about a release"""
        release_path = Path("releases") / release_version

        if not release_path.exists():
            print(f"❌ Release {release_version} not found")
            return

        print(f"📋 Release Information: {release_version}")
        print("=" * 50)

        # Show CHANGELOG if exists
        changelog_file = release_path / "CHANGELOG.md"
        if changelog_file.exists():
            print("\n📝 CHANGELOG:")
            try:
                with open(changelog_file, 'r', encoding='utf-8') as f:
                    print(f.read())
            except Exception as e:
                print(f"Error reading changelog: {e}")

        # Show MANIFEST if exists
        manifest_file = release_path / "MANIFEST.json"
        if manifest_file.exists():
            print("📋 MANIFEST:")
            try:
                with open(manifest_file, 'r', encoding='utf-8') as f:
                    print(f.read())
            except Exception as e:
                print(f"Error reading manifest: {e}")

    def show_available_component_versions(self):
        """Show all available component versions"""
        print_header("Available Component Versions", Icons.FOLDER)

        # Show config components
        printer.print_component("CONFIG", Icons.GEAR)
        self._show_component_versions("config")

        # Show scripts components
        printer.print_component("SCRIPTS", Icons.SCROLL)
        self._show_component_versions("scripts")

        # Show docs components
        printer.print_component("DOCS", Icons.BOOK)
        docs_current = Path("docs/current")
        if docs_current.exists() and docs_current.is_symlink():
            try:
                current_version = docs_current.readlink().name
                print(colorize(f"  docs: {current_version}", Colors.BRIGHT_CYAN) +
                      colorize(f" {Icons.CURRENT} CURRENT", Colors.BRIGHT_GREEN, Colors.BOLD))
            except Exception:
                pass
        print()

        # Show cmds components
        printer.print_component("CMDS", Icons.LIGHTNING)
        self._show_component_versions("cmds")

    def _show_component_versions(self, component_type: str):
        """Show versions for a specific component type"""
        base_dir = Path(component_type)
        if not base_dir.exists():
            return

        for component in base_dir.iterdir():
            if not component.is_dir() or component.name == "changelogs":
                continue

            comp_name = component.name
            print(colorize(f"  {comp_name}/", Colors.BRIGHT_CYAN))

            # Get current version
            current_target = ""
            current_link = component / "current"
            if current_link.exists() and current_link.is_symlink():
                try:
                    current_target = current_link.readlink().name
                except Exception:
                    pass

            # List all versions
            version_dirs = [d for d in component.iterdir()
                          if d.is_dir() and d.name.startswith('v')]

            for version_dir in sorted(version_dirs, key=lambda x: x.name):
                version = version_dir.name
                is_current = version == current_target
                printer.print_version(version, is_current)
            print()


def main():
    """Command line interface"""
    if len(sys.argv) < 2:
        print_header("Flow Release Manager", Icons.PACKAGE)
        print_info("Usage: flow_release_manager.py <command> [args...]", Icons.INFO)
        print_section("Available Commands", Icons.ARROW_RIGHT)
        printer.print_item("list_releases", Icons.PACKAGE)
        printer.print_item("get_release_info <version>", Icons.INFO)
        printer.print_item("show_component_versions", Icons.FOLDER)
        sys.exit(1)

    try:
        manager = FlowReleaseManager()
        command = sys.argv[1]

        if command == "list_releases":
            manager.list_available_releases()

        elif command == "get_release_info" and len(sys.argv) >= 3:
            release_version = sys.argv[2]
            manager.get_release_info(release_version)

        elif command == "show_component_versions":
            manager.show_available_component_versions()

        else:
            print_error(f"Invalid command: {command}", Icons.CROSS)
            print_info("Use 'flow_release_manager.py' without arguments to see available commands", Icons.QUESTION)
            sys.exit(1)

    except Exception as e:
        print_error(f"Operation failed: {e}", Icons.ERROR)
        sys.exit(1)


if __name__ == "__main__":
    main()