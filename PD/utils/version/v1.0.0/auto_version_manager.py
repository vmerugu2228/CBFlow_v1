#!/usr/bin/env python3
"""
Auto Version Manager - Python Backend

Description: Automatic version generation based on version type
Version: 1.0.0
Author: Flow Management System
"""

import os
import re
from pathlib import Path
from typing import Optional, List
import sys

# Import color utilities
from color_utils import (
    print_success, print_error, print_warning, print_info, print_header,
    print_section, printer, Icons, Colors, colorize
)


class AutoVersionManager:
    """Handle automatic version generation and management"""

    def __init__(self):
        self.version = "1.0.0"

    def get_next_version(self, directory: str, version_type: str) -> str:
        """Get next version based on current version and type"""
        current_version = self._get_current_version_for_directory(directory)

        if not current_version:
            return "v1.0.0"

        # Parse current version (remove 'v' prefix)
        version_match = re.match(r'v(\d+)\.(\d+)\.(\d+)', current_version)
        if not version_match:
            print(f"Warning: Invalid version format '{current_version}', using v1.0.0")
            return "v1.0.0"

        major, minor, patch = map(int, version_match.groups())

        # Increment based on version type
        version_type = version_type.lower()
        if version_type == "major":
            major += 1
            minor = 0
            patch = 0
        elif version_type == "minor":
            minor += 1
            patch = 0
        else:  # patch or default
            patch += 1

        return f"v{major}.{minor}.{patch}"

    def get_next_release_version(self, version_type: str) -> str:
        """Get next release version based on existing releases"""
        releases_dir = Path("releases")

        if not releases_dir.exists():
            return "v1.0.0"

        # Find all release directories
        release_dirs = [d for d in releases_dir.iterdir()
                       if d.is_dir() and d.name.startswith('v')]

        if not release_dirs:
            return "v1.0.0"

        # Sort releases by version number
        sorted_releases = sorted(release_dirs, key=lambda x: self._version_sort_key(x.name))
        latest_release = sorted_releases[-1].name

        # Parse and increment
        version_match = re.match(r'v(\d+)\.(\d+)\.(\d+)', latest_release)
        if not version_match:
            return "v1.0.0"

        major, minor, patch = map(int, version_match.groups())

        # Increment based on version type
        version_type = version_type.lower()
        if version_type == "major":
            major += 1
            minor = 0
            patch = 0
        elif version_type == "minor":
            minor += 1
            patch = 0
        else:  # patch or default
            patch += 1

        return f"v{major}.{minor}.{patch}"

    def _get_current_version_for_directory(self, directory: str) -> Optional[str]:
        """Get current version for a directory"""
        dir_path = Path(directory)
        current_link = dir_path / "current"

        # Check if current symlink exists
        if current_link.exists() and current_link.is_symlink():
            try:
                return current_link.readlink().name
            except OSError as e:
                print(f"Warning: Could not read symlink {current_link}: {e}")
                return None

        # Special case for docs directory
        if directory == "docs":
            docs_current = Path("docs/current")
            if docs_current.exists() and docs_current.is_symlink():
                try:
                    return docs_current.readlink().name
                except OSError:
                    return None

        # Find latest version directory
        try:
            version_dirs = [d for d in dir_path.iterdir()
                           if d.is_dir() and d.name.startswith('v')]

            if version_dirs:
                sorted_versions = sorted(version_dirs, key=lambda x: self._version_sort_key(x.name))
                return sorted_versions[-1].name
        except OSError:
            pass

        return None

    def _version_sort_key(self, version: str) -> tuple:
        """Create sort key for version string"""
        try:
            version_match = re.match(r'v(\d+)\.(\d+)\.(\d+)', version)
            if version_match:
                return tuple(map(int, version_match.groups()))
        except (ValueError, AttributeError):
            pass
        return (0, 0, 0)


def main():
    """Command line interface"""
    if len(sys.argv) < 2:
        print_header("Auto Version Manager", Icons.GEAR)
        print_info("Usage: auto_version_manager.py <command> [args...]", Icons.INFO)
        print_section("Available Commands", Icons.ARROW_RIGHT)
        printer.print_item("get_next_version <directory> <version_type>", Icons.TAG)
        printer.print_item("get_next_release_version <version_type>", Icons.ROCKET)
        print_section("Version Types", Icons.ARROW_RIGHT)
        printer.print_item("major - X.0.0 (breaking changes)", Icons.FIRE)
        printer.print_item("minor - x.Y.0 (new features)", Icons.STAR)
        printer.print_item("patch - x.y.Z (bug fixes)", Icons.WRENCH)
        sys.exit(1)

    manager = AutoVersionManager()
    command = sys.argv[1]

    try:
        if command == "get_next_version" and len(sys.argv) >= 4:
            directory = sys.argv[2]
            version_type = sys.argv[3]
            result = manager.get_next_version(directory, version_type)
            print(result)

        elif command == "get_next_release_version" and len(sys.argv) >= 3:
            version_type = sys.argv[2]
            result = manager.get_next_release_version(version_type)
            print(result)

        else:
            print_error(f"Invalid command or arguments: {' '.join(sys.argv[1:])}", Icons.CROSS)
            print_info("Use 'auto_version_manager.py' without arguments to see available commands", Icons.QUESTION)
            sys.exit(1)

    except Exception as e:
        print_error(f"Version generation failed: {e}", Icons.ERROR)
        sys.exit(1)


if __name__ == "__main__":
    main()