#!/usr/bin/env python3
"""
Makefile Helper - Python Backend

Provides help and status functions for Makefile commands
"""

import os
import sys
import subprocess
from pathlib import Path


# ANSI codes for bold text only
BOLD = ""
RESET = ""


def print_header(text):
    """Print a bold header"""
    print(f"\n{BOLD}{text}{RESET}")
    print("=" * len(text))


def print_section(text):
    """Print a bold section header"""
    print(f"\n{BOLD}{text}{RESET}")


def print_item(text):
    """Print an item"""
    print(f"  {text}")


class MakefileHelper:
    """Helper functions for Makefile commands"""

    def __init__(self):
        self.flow_version = "3.0.0"

    def show_help(self):
        """Show help information"""
        print_header("CBFlow Management System Help")

        print_section("Core Commands")
        print_item("cbflow flow --help           - Show all flow commands")
        print_item("cbflow flow check            - Check CBFlow installation")
        print_item("cbflow flow types            - List all flow types")

        print_section("Project Management")
        print_item("cbflow flow project list     - List all projects")
        print_item("cbflow flow project create   - Create new project (interactive)")
        print_item("cbflow flow project info --name <project>  - Show project details")
        print_item("cbflow flow project manage   - Interactive project management")

        print_section("Version Management")
        print_item("cbflow flow version list --dir <dir>   - List versions")
        print_item("cbflow flow version create --dir <dir> --version <ver>  - Create version")
        print_item("cbflow flow version set-current --dir <dir> --version <ver>  - Set current")
        print_item("cbflow flow version get-current --dir <dir>  - Get current version")
        print_item("cbflow flow version diff --dir <dir> --v1 <v1> --v2 <v2>  - Compare")
        print_item("cbflow flow version status   - Show version status")

        print_section("Release Management")
        print_item("cbflow flow release list     - List all releases")
        print_item("cbflow flow release create --type <type>  - Create release")
        print_item("cbflow flow release info --version <ver>  - Show release info")

        print_section("Configuration Management")
        print_item("cbflow flow config manage-flow  - Interactive flow management")
        print_item("cbflow flow config manage-node  - Interactive node management")
        print_item("cbflow flow config manage-tech  - Interactive technology management")
        print_item("cbflow flow config validate     - Validate configuration")
        print_item("cbflow flow config status       - Show config status")

        print_section("Flow Information")
        print_item("cbflow flow info --flow <type>    - Show flow type info")
        print_item("cbflow flow stages --flow <type>  - Show flow stages")
        print_item("cbflow flow nodes --flow <type>   - Show flow nodes")

        print_section("Version Types")
        print_item("major  - X.0.0 (breaking changes, incompatible API changes)")
        print_item("minor  - x.Y.0 (new features, backward compatible)")
        print_item("patch  - x.y.Z (bug fixes, backward compatible)")

        print("\nFor more help: cbflow flow --help")

    def show_status(self):
        """Show system status"""
        print_header("Flow Management System Status")

        # System version
        print_section("System Information")
        print_item(f"Flow Version: {self.flow_version}")

        # Git repository status
        print_section("Git Repository")
        if Path(".git").exists():
            try:
                # Get current branch
                branch = subprocess.run(
                    ["git", "branch", "--show-current"],
                    capture_output=True, text=True, check=True
                ).stdout.strip()

                # Get current commit
                commit = subprocess.run(
                    ["git", "rev-parse", "--short", "HEAD"],
                    capture_output=True, text=True, check=True
                ).stdout.strip()

                # Get uncommitted changes count
                status_output = subprocess.run(
                    ["git", "status", "--porcelain"],
                    capture_output=True, text=True, check=True
                ).stdout.strip()

                changes_count = len(status_output.split('\n')) if status_output else 0

                print_item("Git repository initialized")
                print_item(f"Branch: {branch}")
                print_item(f"Commit: {commit}")
                if changes_count > 0:
                    print_item(f"Uncommitted changes: {changes_count}")
                else:
                    print_item("Working directory clean")

            except subprocess.CalledProcessError:
                print_item("Git repository exists but has issues")
        else:
            print_item("Git repository not initialized")
            print_item("Run 'make init' to initialize")

        # Version control status
        print_section("Version Control")
        try:
            # Count hierarchical structure
            config_types = len([d for d in Path("config").iterdir() if d.is_dir()]) if Path("config").exists() else 0
            scripts_types = len([d for d in Path("scripts").iterdir() if d.is_dir()]) if Path("scripts").exists() else 0

            # Count total versions
            total_versions = 0
            for base_dir in ["config", "scripts"]:
                if Path(base_dir).exists():
                    for type_dir in Path(base_dir).iterdir():
                        if type_dir.is_dir():
                            versions = [d for d in type_dir.iterdir() if d.is_dir() and d.name.startswith('v')]
                            total_versions += len(versions)

            print_item("Hierarchical structure detected")
            print_item(f"Config types: {config_types}")
            print_item(f"Script types: {scripts_types}")
            print_item(f"Total versions: {total_versions}")

        except Exception as e:
            print_item(f"Error checking version control: {e}")

        # Release status
        print_section("Releases")
        releases_dir = Path("releases")
        if releases_dir.exists():
            release_dirs = [d for d in releases_dir.iterdir() if d.is_dir() and d.name.startswith('v')]
            release_count = len(release_dirs)

            if release_count > 0:
                print_item(f"Found {release_count} releases")

                # Show latest releases
                sorted_releases = sorted(release_dirs, key=lambda x: x.name, reverse=True)[:3]
                print_item("Latest releases:")
                for release in sorted_releases:
                    version = release.name
                    # Check if it has a milestone
                    manifest_file = release / "MANIFEST.json"
                    milestone_info = ""
                    if manifest_file.exists():
                        try:
                            import json
                            with open(manifest_file, 'r') as f:
                                manifest = json.load(f)
                                milestone = manifest.get('milestone', '')
                                if milestone:
                                    milestone_info = f" ({milestone})"
                        except Exception:
                            pass

                    print_item(f"  {version}{milestone_info}")
            else:
                print_item("No releases found")
        else:
            print_item("No releases directory found")

        # Component status
        print_section("Components Status")

        # Check cmds components
        cmds_dir = Path("cmds")
        if cmds_dir.exists():
            cmd_components = [d for d in cmds_dir.iterdir() if d.is_dir()]
            cmd_count = len(cmd_components)
            print_item(f"Command components: {cmd_count}")

            # Check for current versions
            current_versions = 0
            for comp in cmd_components:
                current_link = comp / "current"
                if current_link.exists() and current_link.is_symlink():
                    current_versions += 1

            if current_versions == cmd_count:
                print_item("All components have current versions set")
            else:
                print_item(f"Components missing current version: {cmd_count - current_versions}")
        else:
            print_item("No cmds directory found")

        # Check docs
        docs_dir = Path("docs")
        if docs_dir.exists():
            current_link = docs_dir / "current"
            if current_link.exists() and current_link.is_symlink():
                try:
                    current_version = current_link.readlink().name
                    print_item(f"Documentation: {current_version}")
                except Exception:
                    print_item("Documentation current link broken")
            else:
                print_item("Documentation current version not set")
        else:
            print_item("No docs directory found")

        # System health summary
        print_section("System Health")

        # Quick health checks
        health_issues = []

        if not Path(".git").exists():
            health_issues.append("Git not initialized")

        if not Path("releases").exists():
            health_issues.append("No releases directory")

        if not Path("config").exists() or not Path("scripts").exists():
            health_issues.append("Missing core directories")

        if health_issues:
            print_item("System health issues detected:")
            for issue in health_issues:
                print_item(f"  - {issue}")
            print_item("Run 'make help' for guidance on fixing issues")
        else:
            print_item("System is healthy and operational")

        print("\nUse 'make help' to see available commands.")

    def show_version_help(self):
        """Show version control specific help"""
        print_header("CBFlow Version Control Help")

        print_section("Version Management Commands")
        print_item("cbflow flow version list --dir <dir>      - List all versions")
        print_item("cbflow flow version create --dir <dir> --version <ver>  - Create version")
        print_item("cbflow flow version set-current --dir <dir> --version <ver>  - Set current")
        print_item("cbflow flow version get-current --dir <dir>  - Get current version")
        print_item("cbflow flow version diff --dir <dir> --v1 <v1> --v2 <v2>  - Compare")
        print_item("cbflow flow version status  - Show version status")

        print_section("Version Types")
        print_item("major - Increment X in vX.Y.Z (breaking changes)")
        print_item("minor - Increment Y in vX.Y.Z (new features)")
        print_item("patch - Increment Z in vX.Y.Z (bug fixes)")

        print_section("Usage Examples")
        print_item("Create version explicitly:")
        print_item("  cbflow flow version create --dir config --version v2.0.0 --desc \"Major update\"")
        print_item("")
        print_item("Version management:")
        print_item("  cbflow flow version list --dir config           # List all versions")
        print_item("  cbflow flow version get-current --dir config    # Show current")
        print_item("  cbflow flow version set-current --dir config --version v2.0.0  # Set current")
        print_item("  cbflow flow version diff --dir config --v1 v1.0.0 --v2 v2.0.0  # Compare")

        print("\nFor more help: cbflow flow version --help")


def main():
    """Command line interface"""
    if len(sys.argv) < 2:
        print_header("Makefile Helper")
        print_item("Usage: makefile_helper.py <command>")
        print_section("Available Commands")
        print_item("help - Show comprehensive help")
        print_item("status - Show system status")
        print_item("version_help - Show version control help")
        sys.exit(1)

    try:
        helper = MakefileHelper()
        command = sys.argv[1]

        if command == "help":
            helper.show_help()
        elif command == "status":
            helper.show_status()
        elif command == "version_help":
            helper.show_version_help()
        else:
            print(f"Error: Invalid command: {command}")
            print("Use 'makefile_helper.py' without arguments to see available commands")
            sys.exit(1)

    except Exception as e:
        print(f"Error: Helper operation failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
