#!/usr/bin/env python3
"""
Flow Version Manager Python Backend

Comprehensive version control system for flow management with:
- Semantic versioning with symlink management
- Dynamic directory registration
- Comprehensive validation and error handling
- Registry-based version tracking
"""

import os
import sys
import json
import shutil
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any

# Import color utilities
from color_utils import (
    print_success, print_error, print_warning, print_info, print_header,
    print_section, printer, Icons, Colors, colorize
)

class FlowVersionManager:
    """Flow version management system"""

    def __init__(self):
        self.version = "2.0.0"
        self.registry_file = Path(__file__).parent.parent / "flow_version_registry.json"
        self.version_registry = self.load_registry()
        self.debug_mode = False

    def load_registry(self) -> Dict[str, Any]:
        """Load version registry from JSON file"""
        if self.registry_file.exists():
            try:
                with open(self.registry_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Warning: Could not load registry: {e}")
        return {}

    def save_registry(self):
        """Save version registry to JSON file"""
        try:
            with open(self.registry_file, 'w') as f:
                json.dump(self.version_registry, f, indent=2)
        except Exception as e:
            print(f"Error: Could not save registry: {e}")
            raise

    def validate_inputs(self, directory_type: str, version_tag: str, description: str):
        """Validate input parameters"""
        if not directory_type.strip():
            raise ValueError("Directory type cannot be empty")

        if not version_tag.strip():
            raise ValueError("Version tag cannot be empty")

        if not description.strip():
            raise ValueError("Description cannot be empty")

        # Validate version format (should start with 'v')
        if not version_tag.startswith('v'):
            raise ValueError(f"Version tag must start with 'v': {version_tag}")

    def create_new_version(self, directory_type: str, version_tag: str, description: str):
        """Create a new version directory with proper content copying"""
        print_info(f"Creating new version: {directory_type} {version_tag}", Icons.WRENCH)

        self.validate_inputs(directory_type, version_tag, description)

        base_dir = Path(directory_type)
        version_dir = base_dir / version_tag

        # Check if version already exists
        if version_dir.exists():
            raise FileExistsError(f"Version {version_tag} already exists for {directory_type}")

        # Ensure base directory exists
        base_dir.mkdir(parents=True, exist_ok=True)

        # Find source for content copying
        source_dir = self._find_source_version(base_dir)

        if source_dir:
            print_info(f"Copying content from {source_dir.name} to {version_tag}", Icons.PACKAGE)
            # Copy all content from source version
            shutil.copytree(source_dir, version_dir)
            print_success(f"Content copied from {source_dir.name}", Icons.CHECKMARK)
        else:
            # No previous version exists, create empty structure
            print_info(f"No previous version found, creating initial structure", Icons.FOLDER)
            version_dir.mkdir(parents=True, exist_ok=True)

            # Create a basic README to indicate this is the initial version
            readme_file = version_dir / "README.md"
            with open(readme_file, 'w') as f:
                f.write(f"# {directory_type} - {version_tag}\n\n")
                f.write(f"## Description\n{description}\n\n")
                f.write(f"## Version Information\n")
                f.write(f"- Version: {version_tag}\n")
                f.write(f"- Created: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"- Type: Initial version\n\n")
                f.write(f"## Contents\n")
                f.write(f"This is the initial version for {directory_type}. ")
                f.write(f"Add your files and configurations in this directory.\n")

            print_success(f"Initial version structure created with README", Icons.DOCUMENT)

        # Update current symlink to point to new version
        self._update_current_symlink(base_dir, version_tag)

        # Add to registry
        self.register_version(directory_type, version_tag, description)

        # Save registry
        self.save_registry()

        print_success(f"Version {version_tag} created successfully for {directory_type}", Icons.TAG)
        return str(version_dir)

    def register_version(self, directory_type: str, version_tag: str, description: str):
        """Register a version in the internal registry"""
        if directory_type not in self.version_registry:
            self.version_registry[directory_type] = {
                "available_versions": {},
                "current_version": None,
                "creation_date": datetime.now().isoformat()
            }

        self.version_registry[directory_type]["available_versions"][version_tag] = {
            "description": description,
            "creation_date": datetime.now().isoformat()
        }

    def _find_source_version(self, base_dir: Path) -> Optional[Path]:
        """Find the best source version to copy from"""
        # First, check if there's a current symlink
        current_link = base_dir / "current"
        if current_link.exists() and current_link.is_symlink():
            try:
                current_target = current_link.readlink()
                if current_target.is_absolute():
                    source_dir = current_target
                else:
                    source_dir = base_dir / current_target

                if source_dir.exists() and source_dir.is_dir():
                    return source_dir
            except Exception:
                pass

        # If no current link or it's broken, find the latest version
        version_dirs = [d for d in base_dir.iterdir()
                       if d.is_dir() and d.name.startswith('v') and d.name != 'current']

        if not version_dirs:
            return None

        # Sort by version number (simple string sort should work for vX.Y.Z format)
        latest_version = sorted(version_dirs, key=lambda x: x.name)[-1]
        return latest_version

    def _update_current_symlink(self, base_dir: Path, version_tag: str):
        """Update the current symlink to point to the new version"""
        current_link = base_dir / "current"

        # Remove existing symlink if it exists
        if current_link.exists() or current_link.is_symlink():
            current_link.unlink()

        # Create new symlink pointing to the new version
        current_link.symlink_to(version_tag)
        print_success(f"Updated 'current' symlink to point to {version_tag}", Icons.CURRENT)

        # Update registry with current version
        directory_type = str(base_dir)
        if directory_type in self.version_registry:
            self.version_registry[directory_type]["current_version"] = version_tag

    def validate_all_versions(self):
        """Validate all registered versions"""
        print_info("Validating all versions...", Icons.GEAR)
        validation_errors = 0

        for directory_name, registry_data in self.version_registry.items():
            available_versions = registry_data.get("available_versions", {})

            for version_tag, version_info in available_versions.items():
                version_path = Path(directory_name) / version_tag

                if not version_path.exists():
                    print(f"Error: Version directory missing: {version_path}")
                    validation_errors += 1
                else:
                    print(f"OK: Version validated: {version_path}")

        if validation_errors > 0:
            raise RuntimeError(f"Validation failed: {validation_errors} errors found")

        print("OK: All versions validated successfully")

    def add_directory_to_version_control(self, directory: str, description: str, version: str):
        """Add a directory to version control"""
        print(f" Adding directory to version control: {directory}")
        self.create_new_version(directory, version, description)

    def list_managed_directories(self):
        """List all directories under version control"""
        print("📁 Managed Directories:")
        print("=" * 50)

        if not self.version_registry:
            print("No directories under version control")
            return

        for directory_name, registry_data in self.version_registry.items():
            current_version = registry_data.get("current_version", "none")
            version_count = len(registry_data.get("available_versions", {}))
            creation_date = registry_data.get("creation_date", "unknown")

            print(f"Directory: {directory_name}")
            print(f"  Current Version: {current_version}")
            print(f"  Total Versions: {version_count}")
            print(f"  Created: {creation_date}")

            # List all versions
            available_versions = registry_data.get("available_versions", {})
            if available_versions:
                print("  Available Versions:")
                for version_tag, version_info in available_versions.items():
                    desc = version_info.get("description", "No description")
                    marker = " CURRENT" if version_tag == current_version else ""
                    print(f"    {version_tag}: {desc}{marker}")
            print()


def main():
    """Command line interface"""
    if len(sys.argv) < 2:
        print("Usage: flow_version_manager.py <command> [args...]")
        print("Commands:")
        print("  validate_all_versions")
        print("  list_managed_directories")
        print("  create_version <directory> <version> <description>")
        print("  add_directory <directory> <description> <version>")
        sys.exit(1)

    try:
        manager = FlowVersionManager()
        command = sys.argv[1]

        if command == "validate_all_versions":
            manager.validate_all_versions()

        elif command == "list_managed_directories":
            manager.list_managed_directories()

        elif command == "create_version" and len(sys.argv) >= 5:
            directory = sys.argv[2]
            version = sys.argv[3]
            description = sys.argv[4]
            manager.create_new_version(directory, version, description)

        elif command == "add_directory" and len(sys.argv) >= 5:
            directory = sys.argv[2]
            description = sys.argv[3]
            version = sys.argv[4]
            manager.add_directory_to_version_control(directory, description, version)

        else:
            print(f"Invalid command: {command}")
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()