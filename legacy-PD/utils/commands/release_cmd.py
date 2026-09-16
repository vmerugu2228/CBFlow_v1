#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Release Command Handler
# Description: Handles release management operations
# Usage: cbflow flow release <subcommand> [options]
#
# Releases are stored in releases/ (top-level, global scope) and contain:
# - MANIFEST.json: Release metadata and component versions
# - CHANGELOG.md: Release notes
# - Symlinks to all component versions
# ═══════════════════════════════════════════════════════════════════════════════

import argparse
import os
import sys
import json
import shutil
import logging
from datetime import datetime
from pathlib import Path

# Configure unified logging
from logging_config import configure_logging, get_logger

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir

logger = configure_logging('cbflow.release')



def get_releases_dir() -> Path:
    """Get the releases directory (top-level, global scope)."""
    core_dir = get_cbflow_core_dir()
    releases_dir = Path(core_dir) / 'releases'
    releases_dir.mkdir(parents=True, exist_ok=True)
    return releases_dir


def get_available_releases() -> list:
    """Get list of available release versions."""
    releases_dir = get_releases_dir()
    releases = []
    if releases_dir.exists():
        for item in sorted(releases_dir.iterdir()):
            if item.is_dir() and item.name.startswith('v') and item.name != 'current':
                releases.append(item.name)
    return sorted(releases, reverse=True)


def get_current_release() -> str:
    """Get the current release version."""
    releases_dir = get_releases_dir()
    current_link = releases_dir / 'current'
    if current_link.is_symlink():
        return os.readlink(current_link)
    return None


def parse_version(version: str) -> tuple:
    """Parse version string to tuple (major, minor, patch)."""
    v = version.lstrip('v')
    parts = v.split('.')
    try:
        major = int(parts[0]) if len(parts) > 0 else 0
        minor = int(parts[1]) if len(parts) > 1 else 0
        patch = int(parts[2]) if len(parts) > 2 else 0
        return (major, minor, patch)
    except ValueError:
        return (0, 0, 0)


def increment_version(version: str, bump_type: str) -> str:
    """Increment version based on bump type."""
    major, minor, patch = parse_version(version)

    if bump_type == 'major':
        return f"v{major + 1}.0.0"
    elif bump_type == 'minor':
        return f"v{major}.{minor + 1}.0"
    elif bump_type == 'patch':
        return f"v{major}.{minor}.{patch + 1}"
    else:
        return version


# ═══════════════════════════════════════════════════════════════════════════════
# VERSION LOCKING — released versions become permanently read-only
# ═══════════════════════════════════════════════════════════════════════════════

def _is_locked(version_dir: str) -> bool:
    """Check if a version directory is locked (released)."""
    return os.path.exists(os.path.join(version_dir, '.locked'))


def _lock_version(version_dir: str, release_version: str):
    """Lock a version directory permanently. All files become read-only (444),
    all directories become non-writable (555). A .locked marker is written
    before permissions are changed. This is irreversible by design."""
    version_dir = str(version_dir)
    if _is_locked(version_dir):
        return  # Already locked

    # Write .locked marker BEFORE changing permissions
    locked_file = os.path.join(version_dir, '.locked')
    with open(locked_file, 'w') as f:
        f.write(f"Locked by release {release_version}\n")
        f.write(f"Date: {datetime.now().isoformat()}\n")
        f.write(f"User: {os.environ.get('USER', 'unknown')}\n")
        f.write(f"This version is permanently read-only.\n")

    # Make all files read-only (r--r--r--)
    for root, dirs, files in os.walk(version_dir):
        for fname in files:
            fpath = os.path.join(root, fname)
            try:
                os.chmod(fpath, 0o444)
            except OSError:
                pass
        for dname in dirs:
            dpath = os.path.join(root, dname)
            try:
                os.chmod(dpath, 0o555)
            except OSError:
                pass

    # Lock the version directory itself
    try:
        os.chmod(version_dir, 0o555)
    except OSError:
        pass

    logger.info(f"  Locked: {os.path.basename(version_dir)} (read-only)")


def scan_versioned_components() -> dict:
    """Scan all versioned components in the codebase."""
    core_dir = Path(get_cbflow_core_dir())
    components = {}

    # Define component categories to scan
    scan_paths = [
        # Config components
        ('config/flow', 'config.flow'),
        ('config/tech', 'config.tech'),
        ('config/project', 'config.project'),
        ('config/setup', 'config.setup'),
        ('config/exit', 'config.exit'),
        # Utils components
        ('utils/utilities', 'utils.utilities'),
        ('utils/version', 'utils.version'),
        ('utils/generation', 'utils.generation'),
        ('utils/validation', 'utils.validation'),
        ('utils/node_management', 'utils.node_management'),
        ('utils/makefile_commands', 'utils.makefile_commands'),
        ('utils/project', 'utils.project'),
        # Cmds components (flow-specific)
        ('cmds', 'cmds'),
    ]

    for rel_path, component_prefix in scan_paths:
        base_path = core_dir / rel_path

        if not base_path.exists():
            continue

        if component_prefix == 'cmds':
            # Special handling for cmds - has nested structure
            for flow_type in base_path.iterdir():
                if not flow_type.is_dir() or flow_type.name.startswith('.'):
                    continue
                for vendor in flow_type.iterdir():
                    if not vendor.is_dir():
                        continue
                    for tool in vendor.iterdir():
                        if not tool.is_dir():
                            continue
                        versions = _get_versions(tool)
                        if versions:
                            comp_name = f"cmds.{flow_type.name}.{vendor.name}.{tool.name}"
                            current = _get_current_version(tool)
                            components[comp_name] = {
                                'path': str(tool.relative_to(core_dir)),
                                'versions': versions,
                                'current': current or versions[0] if versions else None
                            }
        elif component_prefix.startswith('config.'):
            # Config components may have sub-components (e.g., tech/tsmc_7nm)
            for sub in base_path.iterdir():
                if not sub.is_dir() or sub.name.startswith('.') or sub.name in ['workspace', 'current']:
                    continue
                versions = _get_versions(sub)
                if versions:
                    comp_name = f"{component_prefix}.{sub.name}"
                    current = _get_current_version(sub)
                    components[comp_name] = {
                        'path': str(sub.relative_to(core_dir)),
                        'versions': versions,
                        'current': current or versions[0] if versions else None
                    }
                else:
                    # Check if this directory itself has versions
                    versions = _get_versions(base_path)
                    if versions and component_prefix not in components:
                        current = _get_current_version(base_path)
                        components[component_prefix] = {
                            'path': str(base_path.relative_to(core_dir)),
                            'versions': versions,
                            'current': current or versions[0] if versions else None
                        }
        else:
            # Utils components - direct versioned directories
            versions = _get_versions(base_path)
            if versions:
                current = _get_current_version(base_path)
                components[component_prefix] = {
                    'path': str(base_path.relative_to(core_dir)),
                    'versions': versions,
                    'current': current or versions[0] if versions else None
                }

    return components


def _get_versions(path: Path) -> list:
    """Get all version directories in a path."""
    versions = []
    if path.exists():
        for item in path.iterdir():
            if item.is_dir() and item.name.startswith('v') and item.name != 'current':
                versions.append(item.name)
    return sorted(versions, reverse=True)


def _get_current_version(path: Path) -> str:
    """Get current version from symlink."""
    current_link = path / 'current'
    if current_link.is_symlink():
        return os.readlink(current_link)
    return None


# ─────────────────────────────────────────────────────────────────────────────────
# Release Commands
# ─────────────────────────────────────────────────────────────────────────────────

def cmd_generate_config(args: argparse.Namespace) -> int:
    """Generate a release configuration template with current versions."""
    output_file = args.output

    logger.info("")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("  Generating Release Configuration Template")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("")

    # Scan all components
    components = scan_versioned_components()

    if not components:
        logger.error("No versioned components found")
        return 1

    # Determine next version
    available = get_available_releases()
    if available:
        next_version = increment_version(available[0], 'patch')
    else:
        next_version = 'v1.0.0'

    # Build config structure
    config = {
        "_comment": "CBFlow Release Configuration - Edit versions as needed",
        "_generated": datetime.now().isoformat(),
        "release": {
            "version": next_version,
            "description": "Release description here",
            "milestone": "",
            "author": os.environ.get('USER', 'unknown')
        },
        "components": {}
    }

    # Add components with their current versions
    for comp_name, comp_info in sorted(components.items()):
        config["components"][comp_name] = {
            "version": comp_info['current'],
            "path": comp_info['path'],
            "available": comp_info['versions'][:5]  # Show top 5 versions
        }

    # Write config file
    try:
        with open(output_file, 'w') as f:
            json.dump(config, f, indent=2)

        logger.info(f"Generated: {output_file}")
        logger.info("")
        logger.info(f"Components found: {len(components)}")
        logger.info("")
        logger.info("Next steps:")
        logger.info(f"  1. Edit {output_file} to set desired versions")
        logger.info(f"  2. Update release.version, description, milestone")
        logger.info(f"  3. Run: cbflow flow release create --config {output_file}")
        logger.info("")

        return 0

    except Exception as e:
        logger.error(f"Failed to write config: {e}")
        return 1


def get_previous_release_components(releases_dir: Path) -> dict:
    """Get component versions from the previous (latest) release."""
    available = get_available_releases()
    if not available:
        return {}

    latest_release = available[0]
    manifest_file = releases_dir / latest_release / "MANIFEST.json"

    if not manifest_file.exists():
        return {}

    try:
        with open(manifest_file, 'r') as f:
            manifest = json.load(f)
        return manifest.get('components', {})
    except Exception:
        return {}


def check_version_changes(new_components: dict, previous_components: dict) -> tuple:
    """
    Check for version changes between new and previous release.
    Returns: (has_changes: bool, changes: list of change descriptions)
    """
    changes = []

    if not previous_components:
        # No previous release, all components are new
        return True, ["First release - all components are new"]

    # Check for version changes
    for comp_name, comp_info in new_components.items():
        new_version = comp_info.get('version', '')

        if comp_name in previous_components:
            prev_version = previous_components[comp_name].get('version', '')
            if new_version != prev_version:
                changes.append(f"{comp_name}: {prev_version} -> {new_version}")
        else:
            changes.append(f"{comp_name}: (new component) {new_version}")

    # Check for removed components
    for comp_name in previous_components:
        if comp_name not in new_components:
            changes.append(f"{comp_name}: (removed)")

    return len(changes) > 0, changes


def diff_components(manifest1: dict, manifest2: dict) -> dict:
    """
    Compare components between two release manifests.
    Returns dict with 'added', 'removed', 'changed', 'unchanged' keys.
    """
    comp1 = manifest1.get('components', {})
    comp2 = manifest2.get('components', {})

    result = {
        'added': {},
        'removed': {},
        'changed': {},
        'unchanged': {}
    }

    # Find added and changed
    for name, info in comp2.items():
        if name not in comp1:
            result['added'][name] = info
        else:
            v1 = comp1[name].get('version', '')
            v2 = info.get('version', '')
            if v1 != v2:
                result['changed'][name] = {
                    'from': v1,
                    'to': v2,
                    'path': info.get('path', '')
                }
            else:
                result['unchanged'][name] = info

    # Find removed
    for name, info in comp1.items():
        if name not in comp2:
            result['removed'][name] = info

    return result


def diff_changelogs(releases_dir: Path, v1: str, v2: str) -> dict:
    """Compare changelogs between two releases."""
    changelog1 = releases_dir / v1 / 'CHANGELOG.md'
    changelog2 = releases_dir / v2 / 'CHANGELOG.md'

    result = {'v1_exists': False, 'v2_exists': False, 'v1_content': '', 'v2_content': ''}

    if changelog1.exists():
        result['v1_exists'] = True
        result['v1_content'] = changelog1.read_text()

    if changelog2.exists():
        result['v2_exists'] = True
        result['v2_content'] = changelog2.read_text()

    return result


def format_diff_text(v1: str, v2: str, diff_result: dict, changelog_diff: dict, meta1: dict, meta2: dict) -> str:
    """Format diff as human-readable text."""
    lines = []
    lines.append(f"")
    lines.append(f"{'═'*70}")
    lines.append(f"  CBFlow Release Comparison: {v1} vs {v2}")
    lines.append(f"{'═'*70}")
    lines.append(f"")

    # Metadata comparison
    lines.append(f"  Release Metadata:")
    lines.append(f"  {'─'*50}")
    lines.append(f"  {'':4}{'':20} {'v1 (' + v1 + ')':>20} {'v2 (' + v2 + ')':>20}")
    lines.append(f"  {'':4}{'Created':20} {meta1.get('created', 'N/A')[:19]:>20} {meta2.get('created', 'N/A')[:19]:>20}")
    lines.append(f"  {'':4}{'Description':20} {meta1.get('description', 'N/A')[:20]:>20} {meta2.get('description', 'N/A')[:20]:>20}")
    lines.append(f"")

    # Summary
    added = diff_result['added']
    removed = diff_result['removed']
    changed = diff_result['changed']
    unchanged = diff_result['unchanged']

    lines.append(f"  Summary:")
    lines.append(f"  {'─'*50}")
    lines.append(f"    Added:     {len(added)}")
    lines.append(f"    Removed:   {len(removed)}")
    lines.append(f"    Changed:   {len(changed)}")
    lines.append(f"    Unchanged: {len(unchanged)}")
    lines.append(f"    Total:     {len(added) + len(removed) + len(changed) + len(unchanged)}")
    lines.append(f"")

    # Changed components
    if changed:
        lines.append(f"  Changed Components:")
        lines.append(f"  {'─'*50}")
        for name, info in sorted(changed.items()):
            lines.append(f"    {name}")
            lines.append(f"      {info['from']} -> {info['to']}")
        lines.append(f"")

    # Added components
    if added:
        lines.append(f"  Added Components:")
        lines.append(f"  {'─'*50}")
        for name, info in sorted(added.items()):
            lines.append(f"    + {name} ({info.get('version', 'N/A')})")
        lines.append(f"")

    # Removed components
    if removed:
        lines.append(f"  Removed Components:")
        lines.append(f"  {'─'*50}")
        for name, info in sorted(removed.items()):
            lines.append(f"    - {name} ({info.get('version', 'N/A')})")
        lines.append(f"")

    # Changelog diff
    if changelog_diff.get('v2_exists') and not changelog_diff.get('v1_exists'):
        lines.append(f"  Changelog: Added in {v2}")
    elif changelog_diff.get('v1_exists') and changelog_diff.get('v2_exists'):
        if changelog_diff['v1_content'] != changelog_diff['v2_content']:
            lines.append(f"  Changelog: Updated between {v1} and {v2}")

    if not added and not removed and not changed:
        lines.append(f"  No component changes detected between {v1} and {v2}")

    lines.append(f"")
    return '\n'.join(lines)


def format_diff_json(v1: str, v2: str, diff_result: dict, changelog_diff: dict, meta1: dict, meta2: dict) -> str:
    """Format diff as JSON."""
    output = {
        'comparison': {'v1': v1, 'v2': v2},
        'metadata': {
            'v1': {
                'created': meta1.get('created', ''),
                'description': meta1.get('description', '')
            },
            'v2': {
                'created': meta2.get('created', ''),
                'description': meta2.get('description', '')
            }
        },
        'summary': {
            'added': len(diff_result['added']),
            'removed': len(diff_result['removed']),
            'changed': len(diff_result['changed']),
            'unchanged': len(diff_result['unchanged'])
        },
        'components': {
            'added': {k: {'version': v.get('version', ''), 'path': v.get('path', '')}
                     for k, v in diff_result['added'].items()},
            'removed': {k: {'version': v.get('version', ''), 'path': v.get('path', '')}
                       for k, v in diff_result['removed'].items()},
            'changed': diff_result['changed'],
            'unchanged': list(diff_result['unchanged'].keys())
        },
        'changelog_changed': (changelog_diff.get('v1_content', '') != changelog_diff.get('v2_content', ''))
    }
    return json.dumps(output, indent=2)


def format_diff_markdown(v1: str, v2: str, diff_result: dict, changelog_diff: dict, meta1: dict, meta2: dict) -> str:
    """Format diff as Markdown."""
    lines = []
    lines.append(f"# Release Comparison: {v1} vs {v2}")
    lines.append(f"")

    added = diff_result['added']
    removed = diff_result['removed']
    changed = diff_result['changed']
    unchanged = diff_result['unchanged']

    # Summary table
    lines.append(f"## Summary")
    lines.append(f"")
    lines.append(f"| Metric | Count |")
    lines.append(f"|--------|-------|")
    lines.append(f"| Added | {len(added)} |")
    lines.append(f"| Removed | {len(removed)} |")
    lines.append(f"| Changed | {len(changed)} |")
    lines.append(f"| Unchanged | {len(unchanged)} |")
    lines.append(f"")

    # Changed
    if changed:
        lines.append(f"## Changed Components")
        lines.append(f"")
        lines.append(f"| Component | From | To |")
        lines.append(f"|-----------|------|----|")
        for name, info in sorted(changed.items()):
            lines.append(f"| {name} | {info['from']} | {info['to']} |")
        lines.append(f"")

    # Added
    if added:
        lines.append(f"## Added Components")
        lines.append(f"")
        for name, info in sorted(added.items()):
            lines.append(f"- **{name}** ({info.get('version', 'N/A')})")
        lines.append(f"")

    # Removed
    if removed:
        lines.append(f"## Removed Components")
        lines.append(f"")
        for name, info in sorted(removed.items()):
            lines.append(f"- ~~{name}~~ ({info.get('version', 'N/A')})")
        lines.append(f"")

    return '\n'.join(lines)


def cmd_create(args: argparse.Namespace) -> int:
    """Create a new release from configuration file."""
    releases_dir = get_releases_dir()
    core_dir = Path(get_cbflow_core_dir())

    # Check if config file provided
    if hasattr(args, 'config') and args.config:
        config_file = args.config
        if not os.path.exists(config_file):
            logger.error(f"Config file not found: {config_file}")
            return 1

        # Load config
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read config: {e}")
            return 1

        new_version = config.get('release', {}).get('version', '')
        description = config.get('release', {}).get('description', '')
        milestone = config.get('release', {}).get('milestone', '')
        components = config.get('components', {})

    else:
        # Auto-generate from current versions
        if hasattr(args, 'version') and args.version:
            new_version = args.version
            if not new_version.startswith('v'):
                new_version = f"v{new_version}"
        elif hasattr(args, 'type') and args.type:
            available = get_available_releases()
            if available:
                new_version = increment_version(available[0], args.type)
            else:
                new_version = 'v1.0.0'
        else:
            logger.error("Must specify --config <file>, --type (patch|minor|major), or --version")
            logger.info("")
            logger.info("Examples:")
            logger.info("  cbflow flow release create --config release_config.json")
            logger.info("  cbflow flow release create --type patch --desc 'Bug fixes'")
            logger.info("  cbflow flow release create --version v2.0.0 --desc 'Major release'")
            logger.info("")
            logger.info("Generate a config template first:")
            logger.info("  cbflow flow release generate-config --output release_config.json")
            return 1

        description = getattr(args, 'desc', None) or f"Release {new_version}"
        milestone = getattr(args, 'milestone', None) or ""

        # Scan current versions
        scanned = scan_versioned_components()
        components = {name: {'version': info['current'], 'path': info['path']}
                      for name, info in scanned.items() if info['current']}

    # Validate version
    if not new_version:
        logger.error("No version specified in config")
        return 1

    # Check if version already exists
    new_release_dir = releases_dir / new_version
    if new_release_dir.exists():
        logger.error(f"Release {new_version} already exists")
        return 1

    # Check for version changes compared to previous release
    previous_components = get_previous_release_components(releases_dir)
    has_changes, changes = check_version_changes(components, previous_components)

    if not has_changes:
        logger.warning("")
        logger.warning("═══════════════════════════════════════════════════════════════")
        logger.warning("  No Version Changes Detected")
        logger.warning("═══════════════════════════════════════════════════════════════")
        logger.warning("")
        logger.warning("All component versions are identical to the previous release.")
        logger.warning("A new release should only be created when there are actual changes.")
        logger.warning("")
        logger.warning("To create a release with changes:")
        logger.warning("  1. Update component versions using: cbflow flow version create")
        logger.warning("  2. Then create a new release: cbflow flow release create --type patch")
        logger.warning("")
        logger.warning("Or use --force flag to create release anyway (not recommended):")
        logger.warning(f"  cbflow flow release create --type patch --force")
        logger.warning("")

        # Check for --force flag
        if hasattr(args, 'force') and args.force:
            logger.warning("--force flag detected, proceeding anyway...")
        else:
            return 1

    # Log the changes detected
    if has_changes and changes:
        logger.info("")
        logger.info("Version changes detected:")
        for change in changes[:10]:  # Show first 10 changes
            logger.info(f"  - {change}")
        if len(changes) > 10:
            logger.info(f"  ... and {len(changes) - 10} more changes")

    logger.info("")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("  Creating New Release")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("")
    logger.info(f"  Version:     {new_version}")
    logger.info(f"  Description: {description}")
    if milestone:
        logger.info(f"  Milestone:   {milestone}")
    logger.info(f"  Location:    {new_release_dir}")
    logger.info(f"  Components:  {len(components)}")
    logger.info("")

    try:
        # Create release directory
        new_release_dir.mkdir(parents=True, exist_ok=True)

        # Create component symlinks directory
        components_dir = new_release_dir / 'components'
        components_dir.mkdir(exist_ok=True)

        # Create symlinks for each component
        linked_components = {}
        for comp_name, comp_info in components.items():
            version = comp_info.get('version')
            path = comp_info.get('path')

            if not version or not path:
                continue

            # Create symlink
            source_path = core_dir / path / version
            if source_path.exists():
                # Create hierarchical symlink structure
                link_name = comp_name.replace('.', '_')
                link_path = components_dir / link_name

                # Use relative path for symlink
                rel_source = os.path.relpath(source_path, components_dir)
                link_path.symlink_to(rel_source)

                linked_components[comp_name] = {
                    'version': version,
                    'path': path,
                    'link': str(link_path.relative_to(new_release_dir))
                }
                logger.info(f"  Linked: {comp_name} -> {version}")
            else:
                logger.warning(f"  Skipped: {comp_name} ({version} not found)")

        # Create MANIFEST.json
        manifest = {
            "version": new_version,
            "description": description,
            "milestone": milestone,
            "created": datetime.now().isoformat(),
            "author": os.environ.get('USER', 'unknown'),
            "components": linked_components
        }

        manifest_file = new_release_dir / "MANIFEST.json"
        with open(manifest_file, 'w') as f:
            json.dump(manifest, f, indent=2)

        # Create CHANGELOG.md
        changelog_content = f"""# Release {new_version}

## Overview
- **Version:** {new_version}
- **Date:** {datetime.now().strftime('%Y-%m-%d')}
- **Milestone:** {milestone or 'N/A'}

## Description
{description}

## Components
"""
        for comp_name, comp_info in sorted(linked_components.items()):
            changelog_content += f"- **{comp_name}:** {comp_info['version']}\n"

        changelog_content += f"""
## Changes
- Initial release

## Notes
Generated by CBFlow Release Manager
"""

        changelog_file = new_release_dir / "CHANGELOG.md"
        with open(changelog_file, 'w') as f:
            f.write(changelog_content)

        # Create release_versions.tcl for compatibility
        tcl_content = f"""#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow Release {new_version}
# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
# Description: {description}
# ═══════════════════════════════════════════════════════════════════════════════

# Release Version
set CBFLOW_RELEASE_VERSION "{new_version}"

# Component Versions
"""
        for comp_name, comp_info in sorted(linked_components.items()):
            var_name = comp_name.upper().replace('.', '_') + "_VERSION"
            tcl_content += f'set {var_name} "{comp_info["version"]}"\n'

        tcl_content += f"""
# Release Metadata
set CBFLOW_RELEASE_DATE "{datetime.now().strftime('%Y-%m-%d')}"
set CBFLOW_RELEASE_DESCRIPTION "{description}"
set CBFLOW_RELEASE_MILESTONE "{milestone}"

puts "INFO: Loaded CBFlow Release {new_version}"
"""

        tcl_file = new_release_dir / "release_versions.tcl"
        with open(tcl_file, 'w') as f:
            f.write(tcl_content)

        # ── Lock all component version directories (permanent, irreversible) ──
        logger.info("")
        logger.info("  Locking component versions (permanent read-only)...")
        locked_count = 0
        for comp_name, comp_info in linked_components.items():
            version = comp_info.get('version', '')
            path = comp_info.get('path', '')
            if version and path:
                version_dir = core_dir / path / version
                if version_dir.exists() and not _is_locked(str(version_dir)):
                    _lock_version(str(version_dir), new_version)
                    locked_count += 1

        # Lock the release directory itself
        _lock_version(str(new_release_dir), new_version)

        logger.info("")
        logger.info(f"Release {new_version} created and locked successfully!")
        logger.info("")
        logger.info(f"  Components linked: {len(linked_components)}")
        logger.info(f"  Components locked: {locked_count}")
        logger.info("")
        logger.info("Files created:")
        logger.info(f"  - {manifest_file.relative_to(core_dir)}")
        logger.info(f"  - {changelog_file.relative_to(core_dir)}")
        logger.info(f"  - {tcl_file.relative_to(core_dir)}")
        logger.info("")
        logger.info("Next steps:")
        logger.info(f"  1. Set as current: cbflow flow release set-current --version {new_version}")
        logger.info(f"  2. Initialize workspace: cbflow workspace init --release {new_version}")
        logger.info("")
        logger.info("Note: All released component versions are now permanently read-only.")
        logger.info("      To make changes, create a new dev version:")
        logger.info(f"      cbflow flow dev start --component <name> --from {new_version}")

        # ── Auto git commit + push ──────────────────────────────────────────
        logger.info("")
        logger.info("  Committing release to git...")
        import subprocess as _sp
        try:
            _sp.run(['git', 'add', '-A'], cwd=str(core_dir),
                    capture_output=True, text=True, check=True)
            _sp.run(['git', 'commit', '-m',
                     f'Release {new_version}: {description}'],
                    cwd=str(core_dir), capture_output=True, text=True, check=True)
            logger.info(f"  Committed: Release {new_version}")

            result = _sp.run(['git', 'push'], cwd=str(core_dir),
                             capture_output=True, text=True)
            if result.returncode == 0:
                logger.info(f"  Pushed to remote")
            else:
                logger.warning(f"  Push failed (commit saved locally): {result.stderr.strip()}")
        except _sp.CalledProcessError as e:
            logger.warning(f"  Git commit failed: {e.stderr.strip() if e.stderr else e}")
            logger.warning("  Release created successfully but not committed to git.")
        except FileNotFoundError:
            logger.warning("  Git not found — release created but not committed.")

        return 0

    except Exception as e:
        logger.error(f"Failed to create release: {e}")
        # Cleanup on failure
        if new_release_dir.exists():
            shutil.rmtree(new_release_dir)
        return 1


def cmd_list(args: argparse.Namespace) -> int:
    """List all releases."""
    releases_dir = get_releases_dir()
    current = get_current_release()

    logger.info("")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("  CBFlow Releases")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info(f"  Location: {releases_dir}")
    logger.info("")

    available = get_available_releases()

    if not available:
        logger.info("No releases found")
        logger.info("")
        logger.info("Create a release:")
        logger.info("  1. Generate config: cbflow flow release generate-config --output release.json")
        logger.info("  2. Edit the config file with desired versions")
        logger.info("  3. Create release: cbflow flow release create --config release.json")
        return 0

    logger.info(f"  {'Version':<12} {'Status':<10} {'Components':<12} {'Description'}")
    logger.info("  " + "─" * 66)

    for version in available:
        release_dir = releases_dir / version

        # Get info from MANIFEST.json
        description = ""
        num_components = 0
        manifest_file = release_dir / "MANIFEST.json"
        if manifest_file.exists():
            try:
                with open(manifest_file, 'r') as f:
                    manifest = json.load(f)
                    description = manifest.get('description', '')[:35]
                    num_components = len(manifest.get('components', {}))
            except Exception:
                pass

        status = "CURRENT" if version == current else ""
        logger.info(f"  {version:<12} {status:<10} {num_components:<12} {description}")

    logger.info("")
    logger.info(f"Total: {len(available)} release(s)")
    if current:
        logger.info(f"Current: {current}")

    return 0


def cmd_info(args: argparse.Namespace) -> int:
    """Show release information."""
    version = args.version
    if not version.startswith('v'):
        version = f"v{version}"

    releases_dir = get_releases_dir()
    release_dir = releases_dir / version

    if not release_dir.exists():
        logger.error(f"Release {version} not found")
        available = get_available_releases()
        if available:
            logger.info(f"Available: {', '.join(available[:5])}")
        return 1

    logger.info("")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info(f"  Release Information: {version}")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("")

    # Show MANIFEST.json
    manifest_file = release_dir / "MANIFEST.json"
    if manifest_file.exists():
        try:
            with open(manifest_file, 'r') as f:
                manifest = json.load(f)

            logger.info(f"  Version:       {manifest.get('version', version)}")
            logger.info(f"  Description:   {manifest.get('description', 'N/A')}")
            logger.info(f"  Milestone:     {manifest.get('milestone', 'N/A')}")
            logger.info(f"  Created:       {manifest.get('created', 'N/A')}")
            logger.info(f"  Author:        {manifest.get('author', 'N/A')}")
            logger.info("")

            components = manifest.get('components', {})
            if components:
                logger.info(f"  Components ({len(components)}):")
                logger.info("  " + "─" * 50)
                for comp_name, comp_info in sorted(components.items()):
                    ver = comp_info.get('version', 'N/A')
                    logger.info(f"  {comp_name}: {ver}")
        except Exception as e:
            logger.warning(f"Could not read MANIFEST.json: {e}")

    logger.info("")
    return 0


def cmd_set_current(args: argparse.Namespace) -> int:
    """Set a release as current."""
    version = args.version
    if not version.startswith('v'):
        version = f"v{version}"

    releases_dir = get_releases_dir()
    release_dir = releases_dir / version
    current_link = releases_dir / 'current'

    if not release_dir.exists():
        logger.error(f"Release {version} not found")
        available = get_available_releases()
        if available:
            logger.info(f"Available: {', '.join(available)}")
        return 1

    try:
        # Remove existing symlink
        if current_link.is_symlink():
            current_link.unlink()
        elif current_link.exists():
            logger.error(f"'current' exists but is not a symlink")
            return 1

        # Create new symlink
        current_link.symlink_to(version)

        logger.info(f"Set current release to {version}")
        return 0

    except Exception as e:
        logger.error(f"Failed to set current release: {e}")
        return 1


def cmd_validate(args: argparse.Namespace) -> int:
    """Validate a release."""
    version = args.version
    if not version.startswith('v'):
        version = f"v{version}"

    releases_dir = get_releases_dir()
    release_dir = releases_dir / version
    core_dir = Path(get_cbflow_core_dir())

    if not release_dir.exists():
        logger.error(f"Release {version} not found")
        return 1

    logger.info("")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info(f"  Validating Release: {version}")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("")

    issues = []
    warnings = []

    # Check required files
    required_files = ['MANIFEST.json', 'release_versions.tcl']
    for req_file in required_files:
        if (release_dir / req_file).exists():
            logger.info(f"  [PASS] {req_file}")
        else:
            issues.append(f"Missing required file: {req_file}")
            logger.info(f"  [FAIL] {req_file}")

    # Check optional files
    optional_files = ['CHANGELOG.md']
    for opt_file in optional_files:
        if (release_dir / opt_file).exists():
            logger.info(f"  [PASS] {opt_file}")
        else:
            warnings.append(f"Missing optional file: {opt_file}")
            logger.info(f"  [WARN] {opt_file} (optional)")

    # Check component symlinks
    components_dir = release_dir / 'components'
    if components_dir.exists():
        logger.info("")
        logger.info("Component Links:")
        for link in components_dir.iterdir():
            if link.is_symlink():
                target = link.resolve()
                if target.exists():
                    logger.info(f"  [PASS] {link.name} -> {os.readlink(link)}")
                else:
                    issues.append(f"Broken symlink: {link.name}")
                    logger.info(f"  [FAIL] {link.name} -> {os.readlink(link)}")

    logger.info("")

    if issues:
        logger.error(f"Validation FAILED - {len(issues)} issue(s)")
        for issue in issues:
            logger.error(f"  - {issue}")
        return 1
    elif warnings:
        logger.warning(f"Validation PASSED with {len(warnings)} warning(s)")
        for warn in warnings:
            logger.warning(f"  - {warn}")
        return 0
    else:
        logger.info("Validation PASSED")
        return 0


def cmd_components(args: argparse.Namespace) -> int:
    """List all versioned components in the codebase."""
    logger.info("")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("  CBFlow Versioned Components")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("")

    components = scan_versioned_components()

    if not components:
        logger.info("No versioned components found")
        return 0

    logger.info(f"  {'Component':<40} {'Current':<10} {'Available Versions'}")
    logger.info("  " + "─" * 76)

    for comp_name, comp_info in sorted(components.items()):
        current = comp_info['current'] or 'N/A'
        versions = ', '.join(comp_info['versions'][:3])
        if len(comp_info['versions']) > 3:
            versions += '...'
        logger.info(f"  {comp_name:<40} {current:<10} {versions}")

    logger.info("")
    logger.info(f"Total: {len(components)} component(s)")

    return 0


def cmd_diff(args: argparse.Namespace) -> int:
    """Compare two releases."""
    v1 = args.v1
    v2 = args.v2
    format_type = getattr(args, 'format', 'text')

    releases_dir = get_releases_dir()

    # Validate versions exist
    v1_dir = releases_dir / v1
    v2_dir = releases_dir / v2

    if not v1_dir.exists():
        logger.error(f"Release not found: {v1}")
        return 1

    if not v2_dir.exists():
        logger.error(f"Release not found: {v2}")
        return 1

    # Load manifests
    manifest1_path = v1_dir / 'MANIFEST.json'
    manifest2_path = v2_dir / 'MANIFEST.json'

    if not manifest1_path.exists():
        logger.error(f"MANIFEST.json not found in {v1}")
        return 1

    if not manifest2_path.exists():
        logger.error(f"MANIFEST.json not found in {v2}")
        return 1

    try:
        with open(manifest1_path, 'r') as f:
            manifest1 = json.load(f)
        with open(manifest2_path, 'r') as f:
            manifest2 = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read manifests: {e}")
        return 1

    # Compute diff
    diff_result = diff_components(manifest1, manifest2)
    changelog_diff = diff_changelogs(releases_dir, v1, v2)

    # Format output
    if format_type == 'json':
        output = format_diff_json(v1, v2, diff_result, changelog_diff, manifest1, manifest2)
    elif format_type == 'markdown':
        output = format_diff_markdown(v1, v2, diff_result, changelog_diff, manifest1, manifest2)
    else:
        output = format_diff_text(v1, v2, diff_result, changelog_diff, manifest1, manifest2)

    print(output)
    return 0


def cmd_help(args: argparse.Namespace) -> int:
    """Show detailed release help."""
    logger.info("")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("  CBFlow Release Management - Help")
    logger.info("═══════════════════════════════════════════════════════════════")
    logger.info("")
    logger.info("WORKFLOW:")
    logger.info("  1. Generate config template with current versions:")
    logger.info("     cbflow flow release generate-config --output release.json")
    logger.info("")
    logger.info("  2. Edit release.json to set desired component versions")
    logger.info("")
    logger.info("  3. Create release from config:")
    logger.info("     cbflow flow release create --config release.json")
    logger.info("")
    logger.info("  4. Set as current release:")
    logger.info("     cbflow flow release set-current --version v1.0.0")
    logger.info("")
    logger.info("COMMANDS:")
    logger.info("  generate-config --output <file>     Generate config template")
    logger.info("  create --config <file>              Create release from config")
    logger.info("  create --type <type>                Create with auto-versions")
    logger.info("  list                                List all releases")
    logger.info("  info --version <ver>                Show release details")
    logger.info("  set-current --version <ver>         Set current release")
    logger.info("  validate --version <ver>            Validate release")
    logger.info("  components                          List versioned components")
    logger.info("")
    logger.info("VERSION TYPES (for --type):")
    logger.info("  patch  - Bug fixes (x.y.Z+1)")
    logger.info("  minor  - New features (x.Y+1.0)")
    logger.info("  major  - Breaking changes (X+1.0.0)")
    logger.info("")
    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow release',
        description='CBFlow - Release Management',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate config template
  cbflow flow release generate-config --output release_config.json

  # Create release from config
  cbflow flow release create --config release_config.json

  # Create release with auto-versioning
  cbflow flow release create --type patch --desc "Bug fixes"

  # List and manage releases
  cbflow flow release list
  cbflow flow release info --version v1.0.0
  cbflow flow release set-current --version v1.0.0
  cbflow flow release validate --version v1.0.0

  # List available components
  cbflow flow release components
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # generate-config command
    gen_parser = subparsers.add_parser('generate-config', help='Generate release config template')
    gen_parser.add_argument('--output', '-o', required=True, help='Output file path')

    # create command
    create_parser = subparsers.add_parser('create', help='Create a new release')
    create_parser.add_argument('--config', '-c', help='Release config file')
    create_parser.add_argument('--type', '-t', choices=['patch', 'minor', 'major'],
                              help='Version bump type (if no config)')
    create_parser.add_argument('--version', '-v', help='Explicit version (if no config)')
    create_parser.add_argument('--desc', '-d', help='Release description')
    create_parser.add_argument('--milestone', '-m', help='Milestone name')
    create_parser.add_argument('--force', '-f', action='store_true',
                              help='Force release creation even without version changes')

    # list command
    subparsers.add_parser('list', help='List all releases')

    # info command
    info_parser = subparsers.add_parser('info', help='Show release info')
    info_parser.add_argument('--version', '-v', required=True, help='Release version')

    # set-current command
    set_parser = subparsers.add_parser('set-current', help='Set current release')
    set_parser.add_argument('--version', '-v', required=True, help='Release version')

    # validate command
    validate_parser = subparsers.add_parser('validate', help='Validate a release')
    validate_parser.add_argument('--version', '-v', required=True, help='Release version')

    # components command
    subparsers.add_parser('components', help='List versioned components')

    # diff command
    diff_parser = subparsers.add_parser('diff', help='Compare two releases')
    diff_parser.add_argument('--v1', required=True, help='First release version (e.g., v1.0.0)')
    diff_parser.add_argument('--v2', required=True, help='Second release version (e.g., v1.0.1)')
    diff_parser.add_argument('--format', choices=['text', 'json', 'markdown'], default='text',
                            help='Output format (default: text)')

    # help command
    subparsers.add_parser('help', help='Show detailed help')

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
        'generate-config': cmd_generate_config,
        'create': cmd_create,
        'list': cmd_list,
        'info': cmd_info,
        'set-current': cmd_set_current,
        'validate': cmd_validate,
        'components': cmd_components,
        'diff': cmd_diff,
        'help': cmd_help,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
