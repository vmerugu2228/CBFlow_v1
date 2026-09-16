#!/usr/bin/env python3
"""
Changelog Manager - Python Backend

Description: Automatic changelog generation for version changes
Version: 1.0.0
Author: Flow Management System
"""

import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List
import sys

# Import color utilities
from color_utils import (
    print_success, print_error, print_warning, print_info, print_header,
    print_section, printer, Icons, Colors, colorize
)


class ChangelogManager:
    """Handle automatic changelog generation and management"""

    def __init__(self):
        self.version = "1.0.0"
        self.change_types = {
            "major": {"emoji": "🚀", "category": "BREAKING CHANGES"},
            "minor": {"emoji": "✨", "category": "FEATURES"},
            "patch": {"emoji": "🐛", "category": "FIXES"},
            "manual": {"emoji": "🔄", "category": "CHANGES"}
        }

    def update_changelog(self, directory: str, version: str, description: str, version_type: str):
        """Update changelog for a version change"""
        dir_path = Path(directory)
        changelog_file = dir_path / "CHANGELOG.md"

        # Create changelog if it doesn't exist
        if not changelog_file.exists():
            self._create_initial_changelog(changelog_file, directory)

        # Read existing content
        try:
            with open(changelog_file, 'r', encoding='utf-8') as f:
                existing_content = f.read()
        except Exception as e:
            print(f"Error reading changelog: {e}")
            return

        # Generate new entry
        new_entry = self._generate_changelog_entry(version, description, version_type)

        # Insert new entry after header
        updated_content = self._insert_changelog_entry(existing_content, new_entry)

        # Write updated content
        try:
            with open(changelog_file, 'w', encoding='utf-8') as f:
                f.write(updated_content)
            print_success(f"Updated changelog: {changelog_file}", Icons.DOCUMENT)
        except Exception as e:
            print_error(f"Failed to write changelog: {e}", Icons.ERROR)

    def _create_initial_changelog(self, changelog_file: Path, directory: str):
        """Create initial changelog file"""
        component_name = Path(directory).name

        content = f"""# Changelog - {component_name}

All notable changes to the {component_name} component will be documented in this file.

The format is based on Keep a Changelog (https://keepachangelog.com/en/1.0.0/),
and this project adheres to Semantic Versioning (https://semver.org/spec/v2.0.0.html).

"""

        try:
            with open(changelog_file, 'w', encoding='utf-8') as f:
                f.write(content)
            print_success(f"Created initial changelog: {changelog_file}", Icons.DOCUMENT)
        except Exception as e:
            print_error(f"Failed to create changelog: {e}", Icons.ERROR)

    def _generate_changelog_entry(self, version: str, description: str, version_type: str) -> str:
        """Generate changelog entry for a version"""
        timestamp = datetime.now().strftime("%Y-%m-%d")

        # Get change type info
        version_type = version_type.lower()
        change_info = self.change_types.get(version_type, self.change_types["manual"])

        entry = f"""## [{version}] - {timestamp}

### {change_info['emoji']} {change_info['category']}
- {description}

"""
        return entry

    def _insert_changelog_entry(self, existing_content: str, new_entry: str) -> str:
        """Insert new entry into existing changelog content"""
        lines = existing_content.split('\n')
        new_lines = []
        header_passed = False
        entry_inserted = False

        for line in lines:
            # Look for main header
            if not header_passed and line.startswith('# Changelog'):
                new_lines.append(line)
                header_passed = True
                continue

            # Insert new entry before first existing entry or description
            if (header_passed and not entry_inserted and
                (line.startswith('## ') or line.strip().startswith('All notable changes'))):
                new_lines.append('')
                new_lines.append(new_entry.rstrip())
                entry_inserted = True

            new_lines.append(line)

        # If no insertion point found, append at the end
        if not entry_inserted:
            new_lines.extend(['', new_entry.rstrip()])

        return '\n'.join(new_lines)


def main():
    """Command line interface"""
    if len(sys.argv) != 5:
        print("Usage: changelog_manager.py <directory> <version> <description> <version_type>")
        print("Example: changelog_manager.py config/flow v1.1.1 'Bug fixes for timing' patch")
        sys.exit(1)

    try:
        manager = ChangelogManager()
        directory = sys.argv[1]
        version = sys.argv[2]
        description = sys.argv[3]
        version_type = sys.argv[4]

        manager.update_changelog(directory, version, description, version_type)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()