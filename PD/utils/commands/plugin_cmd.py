#!/usr/bin/env python3
"""
CBFlow Plugin Command Handler

Manages flow plugins: register, unregister, scaffold, and list.
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from datetime import datetime

from logging_config import configure_logging, get_logger

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir

logger = configure_logging('cbflow.plugin')



def get_plugins_dir() -> Path:
    """Get the plugins directory."""
    return Path(get_cbflow_core_dir()) / 'plugins'


def get_templates_dir() -> Path:
    """Get the scaffold templates directory."""
    return Path(os.path.dirname(os.path.abspath(__file__))) / 'scaffold_templates'


class PluginManager:
    """Manages CBFlow flow plugins."""

    def __init__(self):
        self.plugins_dir = get_plugins_dir()
        self.plugins_dir.mkdir(parents=True, exist_ok=True)
        self.templates_dir = get_templates_dir()
        self.core_dir = Path(get_cbflow_core_dir())

    def discover_plugins(self) -> list:
        """Scan plugins directory for registered flows."""
        plugins = []
        if not self.plugins_dir.exists():
            return plugins

        for plugin_dir in sorted(self.plugins_dir.iterdir()):
            if not plugin_dir.is_dir():
                continue
            registry_file = plugin_dir / 'flow_registry.json'
            if registry_file.exists():
                try:
                    with open(registry_file, 'r') as f:
                        registry = json.load(f)
                    registry['_plugin_dir'] = str(plugin_dir)
                    plugins.append(registry)
                except Exception as e:
                    logger.warning(f"Failed to read plugin {plugin_dir.name}: {e}")

        return plugins

    def register_flow(self, flow_name: str, manifest_path: str = None) -> bool:
        """Register a new flow plugin."""
        flow_name = flow_name.upper()
        plugin_dir = self.plugins_dir / flow_name

        if plugin_dir.exists():
            logger.error(f"Plugin already registered: {flow_name}")
            logger.info(f"Use 'cbflow flow plugin unregister --name {flow_name}' first")
            return False

        if manifest_path:
            # Copy from provided manifest
            manifest_path = Path(manifest_path)
            if not manifest_path.exists():
                logger.error(f"Manifest not found: {manifest_path}")
                return False

            try:
                with open(manifest_path, 'r') as f:
                    registry = json.load(f)
            except Exception as e:
                logger.error(f"Failed to read manifest: {e}")
                return False
        else:
            logger.error("Must provide --manifest path to flow_registry.json")
            return False

        # Create plugin directory
        plugin_dir.mkdir(parents=True, exist_ok=True)

        # Copy manifest
        registry_file = plugin_dir / 'flow_registry.json'
        with open(registry_file, 'w') as f:
            json.dump(registry, f, indent=4)

        # Copy node config if referenced and exists
        node_config = registry.get('node_config')
        if node_config and manifest_path.parent:
            src_config = manifest_path.parent / node_config
            if src_config.exists():
                shutil.copy2(src_config, plugin_dir / node_config)

        # Copy generator if referenced and exists
        generator = registry.get('generator')
        if generator and manifest_path.parent:
            src_generator = manifest_path.parent / generator
            if src_generator.exists():
                shutil.copy2(src_generator, plugin_dir / generator)

        logger.info(f"Plugin registered: {flow_name}")
        logger.info(f"  Directory: {plugin_dir}")
        logger.info(f"  Stages: {', '.join(registry.get('stages', []))}")
        logger.info(f"  Tool: {registry.get('vendor', 'N/A')}/{registry.get('tool', 'N/A')}")

        return True

    def unregister_flow(self, flow_name: str) -> bool:
        """Unregister a flow plugin."""
        flow_name = flow_name.upper()
        plugin_dir = self.plugins_dir / flow_name

        if not plugin_dir.exists():
            logger.error(f"Plugin not found: {flow_name}")
            return False

        shutil.rmtree(plugin_dir)
        logger.info(f"Plugin unregistered: {flow_name}")
        return True

    def scaffold_flow(self, name: str, vendor: str, tool: str, description: str = '') -> bool:
        """Generate template files for a new flow."""
        name = name.upper()
        name_lower = name.lower()
        vendor = vendor.lower()
        tool = tool.lower()

        if not description:
            description = f"{name} flow using {vendor} {tool}"

        output_dir = self.plugins_dir / name
        if output_dir.exists():
            logger.error(f"Plugin directory already exists: {output_dir}")
            return False

        output_dir.mkdir(parents=True, exist_ok=True)

        replacements = {
            '{{FLOW_NAME}}': name,
            '{{FLOW_NAME_LOWER}}': name_lower,
            '{{VENDOR}}': vendor,
            '{{TOOL}}': tool,
            '{{DESCRIPTION}}': description,
        }

        # Generate from templates
        templates = {
            'flow_registry_template.json': 'flow_registry.json',
            'node_config_template.tcl': f'{name}_config.tcl',
            'makefile_generator_template.tcl': f'{name_lower}_makefile_generator.tcl',
        }

        for template_name, output_name in templates.items():
            template_path = self.templates_dir / template_name
            if template_path.exists():
                content = template_path.read_text()
                for key, value in replacements.items():
                    content = content.replace(key, value)
                (output_dir / output_name).write_text(content)
                logger.info(f"  Created: {output_dir / output_name}")
            else:
                logger.warning(f"  Template not found: {template_path}")

        # Create cmd scripts directory
        cmd_dir = self.core_dir / 'cmds' / name / vendor / tool / 'v1.0.0'
        cmd_dir.mkdir(parents=True, exist_ok=True)

        # Create a basic inputs handler
        inputs_handler = cmd_dir / f'inputs_{tool}.tcl'
        inputs_handler.write_text(f"""#!/usr/bin/env tclsh
#===============================================================================
# {name} Flow - Inputs Stage Handler ({vendor}/{tool})
# Generated by: cbflow flow scaffold
#===============================================================================

proc {name_lower}_inputs {{}} {{
    puts "INFO: {name} inputs stage - loading design data"
    # Add your inputs stage implementation here
    return 1
}}
""")
        logger.info(f"  Created: {inputs_handler}")

        logger.info(f"")
        logger.info(f"Plugin scaffolded: {name}")
        logger.info(f"  Plugin dir: {output_dir}")
        logger.info(f"  Commands dir: {cmd_dir}")
        logger.info(f"")
        logger.info(f"Next steps:")
        logger.info(f"  1. Edit {output_dir}/flow_registry.json to customize stages")
        logger.info(f"  2. Edit {output_dir}/{name}_config.tcl for node configuration")
        logger.info(f"  3. Add command scripts in {cmd_dir}/")
        logger.info(f"  4. Register: cbflow flow plugin register --name {name}")
        logger.info(f"     (or it's already discoverable in the plugins directory)")

        return True

    def list_plugins(self) -> list:
        """List all registered plugins."""
        return self.discover_plugins()


def cmd_register(args: argparse.Namespace) -> int:
    """Register a flow plugin."""
    manager = PluginManager()
    manifest = getattr(args, 'manifest', None)
    name = getattr(args, 'name', None)

    if not name:
        logger.error("Must provide --name for the flow")
        return 1

    success = manager.register_flow(name, manifest)
    return 0 if success else 1


def cmd_unregister(args: argparse.Namespace) -> int:
    """Unregister a flow plugin."""
    manager = PluginManager()
    name = args.name

    if not name:
        logger.error("Must provide --name for the flow")
        return 1

    success = manager.unregister_flow(name)
    return 0 if success else 1


def cmd_scaffold(args: argparse.Namespace) -> int:
    """Scaffold a new flow."""
    manager = PluginManager()

    name = args.name
    vendor = getattr(args, 'vendor', 'generic')
    tool = getattr(args, 'tool', 'generic')
    description = getattr(args, 'desc', '')

    if not name:
        logger.error("Must provide --name for the flow")
        return 1

    success = manager.scaffold_flow(name, vendor, tool, description)
    return 0 if success else 1


def cmd_list(args: argparse.Namespace) -> int:
    """List registered plugins."""
    manager = PluginManager()
    plugins = manager.list_plugins()

    if not plugins:
        logger.info("No plugins registered")
        logger.info(f"Plugin directory: {get_plugins_dir()}")
        logger.info(f"")
        logger.info(f"Create a new plugin:")
        logger.info(f"  cbflow flow plugin scaffold --name MYFLOW --vendor acme --tool mytool")
        return 0

    logger.info("")
    logger.info(f"{'═'*60}")
    logger.info(f"  Registered Plugins ({len(plugins)})")
    logger.info(f"{'═'*60}")

    for plugin in plugins:
        flow_type = plugin.get('flow_type', 'UNKNOWN')
        desc = plugin.get('description', '')
        vendor = plugin.get('vendor', 'N/A')
        tool = plugin.get('tool', 'N/A')
        version = plugin.get('version', 'N/A')
        stages = plugin.get('stages', [])

        logger.info(f"")
        logger.info(f"  {flow_type} (v{version})")
        logger.info(f"    Description: {desc}")
        logger.info(f"    Tool:        {vendor}/{tool}")
        logger.info(f"    Stages:      {', '.join(stages)}")

    logger.info(f"")
    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow plugin',
        description='CBFlow Plugin Management',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow plugin list
  cbflow flow plugin scaffold --name MYFLOW --vendor acme --tool mytool
  cbflow flow plugin register --name MYFLOW --manifest ./flow_registry.json
  cbflow flow plugin unregister --name MYFLOW
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Plugin commands')

    # list command
    subparsers.add_parser('list', help='List registered plugins')

    # scaffold command
    scaffold_parser = subparsers.add_parser('scaffold', help='Scaffold a new flow plugin')
    scaffold_parser.add_argument('--name', '-n', required=True, help='Flow name (e.g., MYFLOW)')
    scaffold_parser.add_argument('--vendor', '-V', default='generic', help='EDA vendor name')
    scaffold_parser.add_argument('--tool', '-t', default='generic', help='Tool name')
    scaffold_parser.add_argument('--desc', '-d', default='', help='Flow description')

    # register command
    register_parser = subparsers.add_parser('register', help='Register a flow plugin')
    register_parser.add_argument('--name', '-n', required=True, help='Flow name')
    register_parser.add_argument('--manifest', '-m', help='Path to flow_registry.json')

    # unregister command
    unreg_parser = subparsers.add_parser('unregister', help='Unregister a flow plugin')
    unreg_parser.add_argument('--name', '-n', required=True, help='Flow name to remove')

    # help
    subparsers.add_parser('help', help='Show help')

    return parser


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()

    if not args.command or args.command == 'help':
        parser.print_help()
        return 0

    commands = {
        'list': cmd_list,
        'scaffold': cmd_scaffold,
        'register': cmd_register,
        'unregister': cmd_unregister,
    }

    if args.command in commands:
        return commands[args.command](args)

    return 1


if __name__ == '__main__':
    sys.exit(main())
