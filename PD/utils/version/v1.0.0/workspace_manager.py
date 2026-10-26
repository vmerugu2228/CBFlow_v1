#!/usr/bin/env python3
"""
Version Directory Manager - Simple Directory-Based Versioning

Provides straightforward version management:
- Copy an existing version to create a new one
- Update the 'current' symlink to promote a version
- List all available versions
"""

import os
import sys
import shutil
from pathlib import Path
from datetime import datetime
from typing import Optional

# Import color utilities
from color_utils import (
    print_success, print_error, print_warning, print_info, print_header,
    print_section, printer, Icons, Colors, colorize
)


class VersionDirectoryManager:
    """Simple directory-based version management"""

    def __init__(self):
        self.version = "2.0.0"

    def copy_version(self, component_dir: str, from_version: str, to_version: str) -> str:
        """Copy an existing version directory to create a new version"""
        base_dir = Path(component_dir)
        source_dir = base_dir / from_version
        target_dir = base_dir / to_version

        print_info(f"Creating {to_version} from {from_version} in {component_dir}", Icons.WRENCH)

        if not source_dir.exists():
            raise FileNotFoundError(f"Source version {from_version} does not exist in {component_dir}")

        if target_dir.exists():
            raise FileExistsError(f"Target version {to_version} already exists in {component_dir}")

        # Copy the version directory
        shutil.copytree(source_dir, target_dir)

        # Add version metadata
        metadata_file = target_dir / ".version_info"
        with open(metadata_file, 'w') as f:
            f.write(f"version={to_version}\n")
            f.write(f"copied_from={from_version}\n")
            f.write(f"created={datetime.now().isoformat()}\n")

        print_success(f"Created {to_version} from {from_version}", Icons.TAG)
        print_info(f"Edit files in: {target_dir}", Icons.WRENCH)
        print_info(f"When ready, promote with: set_current {component_dir} {to_version}", Icons.ARROW_RIGHT)

        return str(target_dir)

    def set_current(self, component_dir: str, version: str) -> str:
        """Update the 'current' symlink to point to a version"""
        base_dir = Path(component_dir)
        version_dir = base_dir / version
        current_link = base_dir / "current"

        print_info(f"Setting current version to {version}", Icons.ROCKET)

        if not version_dir.exists():
            raise FileNotFoundError(f"Version {version} does not exist in {component_dir}")

        # Show old current version
        if current_link.is_symlink():
            try:
                old_version = os.readlink(current_link)
                print_info(f"Previous current: {old_version}", Icons.INFO)
            except Exception:
                pass

        # Update symlink
        if current_link.exists() or current_link.is_symlink():
            current_link.unlink()
        current_link.symlink_to(version)

        print_success(f"Current version set to {version}", Icons.CROWN)
        return str(version_dir)

    def list_versions(self, component_dir: str):
        """List all versions and show which is current"""
        base_dir = Path(component_dir)

        print_header(f"Versions: {component_dir}", Icons.FOLDER)

        # Find current version
        current_link = base_dir / "current"
        current_version = None
        if current_link.is_symlink():
            try:
                current_version = os.readlink(current_link)
            except Exception:
                pass

        # Find all version directories
        version_dirs = sorted(
            [d for d in base_dir.iterdir() if d.is_dir() and d.name.startswith('v')],
            key=lambda x: x.name
        )

        if not version_dirs:
            print_info("No versions found", Icons.INFO)
            return

        print_section("Available Versions", Icons.TAG)
        for version_dir in version_dirs:
            version = version_dir.name
            is_current = version == current_version
            printer.print_version(version, is_current)

            # Show metadata if available
            metadata_file = version_dir / ".version_info"
            if metadata_file.exists():
                try:
                    with open(metadata_file, 'r') as f:
                        for line in f:
                            key, _, val = line.strip().partition('=')
                            if key in ('created', 'description', 'copied_from'):
                                printer.print_item(f"{key}: {val}", Icons.CLOCK, indent=4)
                except Exception:
                    pass

        if current_version:
            print_info(f"\nCurrent: {current_version}", Icons.CROWN)
        else:
            print_warning("No current version set", Icons.WARNING)


def main():
    """Command line interface"""
    if len(sys.argv) < 2:
        print_header("Version Directory Manager", Icons.WRENCH)
        print_info("Usage: workspace_manager.py <command> [args...]", Icons.INFO)
        print_section("Available Commands", Icons.ARROW_RIGHT)
        printer.print_item("copy_version <component_dir> <from_version> <to_version>", Icons.PACKAGE)
        printer.print_item("set_current <component_dir> <version>", Icons.ROCKET)
        printer.print_item("list_versions <component_dir>", Icons.TAG)
        sys.exit(1)

    try:
        manager = VersionDirectoryManager()
        command = sys.argv[1]

        if command == "copy_version" and len(sys.argv) >= 5:
            component_dir = sys.argv[2]
            from_version = sys.argv[3]
            to_version = sys.argv[4]
            manager.copy_version(component_dir, from_version, to_version)

        elif command == "set_current" and len(sys.argv) >= 4:
            component_dir = sys.argv[2]
            version = sys.argv[3]
            manager.set_current(component_dir, version)

        elif command == "list_versions" and len(sys.argv) >= 3:
            component_dir = sys.argv[2]
            manager.list_versions(component_dir)

        # Keep backward compatibility for promote_version
        elif command == "promote_version" and len(sys.argv) >= 4:
            component_dir = sys.argv[2]
            version = sys.argv[3]
            manager.set_current(component_dir, version)

        else:
            print_error(f"Invalid command: {command}", Icons.CROSS)
            sys.exit(1)

    except Exception as e:
        print_error(f"Operation failed: {e}", Icons.ERROR)
        sys.exit(1)


if __name__ == "__main__":
    main()
