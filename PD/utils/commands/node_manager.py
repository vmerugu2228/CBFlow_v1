#!/usr/bin/env python3
"""
CBFlow Node Manager

Python replacement for the TCL manage_node.tcl system.
Manages custom nodes, branches, and graph operations for CBFlow runs.

Replaces:
  - utils/node_management/v1.0.0/manage_node.tcl (350 lines)
  - utils/node_management/v1.0.0/lib/node_ops.tcl (247 lines)
  - utils/node_management/v1.0.0/lib/branch_ops.tcl (423 lines)
  - utils/node_management/v1.0.0/lib/graph_ops.tcl (374 lines)
  - utils/node_management/v1.0.0/lib/persistence.tcl (118 lines)
  - utils/node_management/v1.0.0/lib/flow_config.tcl (143 lines)
  - utils/node_management/v1.0.0/lib/common.tcl (95 lines)

Custom nodes are stored in setup/runtime_flow_config.tcl as TCL array set blocks.
This file MUST stay in TCL format because the generated Makefile sources it at
runtime.

Usage:
    from node_manager import NodeManager
    mgr = NodeManager(run_dir='/path/to/run', flow_type='PNR')
    mgr.add_node('place2', 'place', 'place1')
    mgr.create_branch('Fix Timing Branch', 'place1')
    mgr.validate()
"""

import os
import re
from datetime import datetime
from typing import Dict, List, Optional

from tcl_config_parser import (
    get_flow_stages, get_subnodes, get_tool_info,
    _load_node_config, _parse_tcl_list, _parse_tcl_string,
)
import cbflow_config as _cfg
# MakefileGenerator no longer used — RACE builds DAG at runtime
from logging_config import get_logger

logger = get_logger('node_manager')


# ═══════════════════════════════════════════════════════════════════════════════
# NODE MANAGER
# ═══════════════════════════════════════════════════════════════════════════════

class NodeManager:
    """
    Manages custom nodes and branches for a CBFlow run.

    Custom nodes extend the base flow graph with additional stages. Branches
    create parallel execution paths from a given point in the flow. All
    configuration is persisted to setup/runtime_flow_config.tcl in TCL
    array set format so the generated Makefile can source it at runtime.
    """

    def __init__(self, run_dir: str = None, flow_type: str = None, env_vars: dict = None):
        self.run_dir = run_dir or os.getcwd()
        self.flow_type = flow_type or self._detect_flow_type()
        self.env = env_vars or {}
        self.flow_lower = self.flow_type.lower()

        # Load base stages from config — run-aware so user_config overrides apply.
        self.base_stages = get_flow_stages(self.flow_type, run_dir=self.run_dir)
        self.node_config = _load_node_config(self.flow_type, run_dir=self.run_dir)

        # Load custom nodes from runtime config
        self.custom_nodes = {}   # {name: {type, dependencies, branch_key}}
        self.branches = {}       # {key: {name, created_date, created_by}}
        self._load_runtime_config()

    # ─────────────────────────────────────────────────────────────────────────
    # Flow Detection
    # ─────────────────────────────────────────────────────────────────────────

    def _detect_flow_type(self) -> str:
        """Read flow type from the run environment file."""
        env_file = os.path.join(self.run_dir, '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if 'CBFLOW_FLOW_TYPE' in line:
                        return line.split('=', 1)[-1].strip().strip('"')
        return ''

    # ─────────────────────────────────────────────────────────────────────────
    # Persistence
    # ─────────────────────────────────────────────────────────────────────────

    def _load_runtime_config(self):
        """Hydrate custom_nodes + branches from the resolved cascade.

        `setup/runtime_flow_config.tcl` is sourced by the resolver, so every
        custom-node `stages,<name>,*` key and every `branch_keys,<key>,*`
        key surfaces in the cascade dict — no regex pass over the raw file.
        """
        cfg = _cfg.load_resolved_config(self.flow_type, self.run_dir)

        # Extract custom nodes: keys like "stages,place2,type" → "place"
        node_names = set()
        for key in cfg:
            if key.startswith('stages,') and key.count(',') >= 2:
                parts = key.split(',')
                node_names.add(parts[1])

        for name in node_names:
            self.custom_nodes[name] = {
                'type':         _parse_tcl_string(_cfg.optional(cfg, f'stages,{name},type') or ''),
                'dependencies': _parse_tcl_string(_cfg.optional(cfg, f'stages,{name},dependencies') or ''),
                'branch_key':   _parse_tcl_string(_cfg.optional(cfg, f'stages,{name},branch_key') or ''),
            }

        # Extract branches: keys like "branch_keys,abc123,name"
        branch_keys = set()
        for key in cfg:
            if key.startswith('branch_keys,') and key.count(',') >= 2:
                branch_keys.add(key.split(',')[1])

        for bkey in branch_keys:
            self.branches[bkey] = {
                'name':         _parse_tcl_string(_cfg.optional(cfg, f'branch_keys,{bkey},name') or bkey),
                'created_date': _parse_tcl_string(_cfg.optional(cfg, f'branch_keys,{bkey},created_date') or ''),
                'created_by':   _parse_tcl_string(_cfg.optional(cfg, f'branch_keys,{bkey},created_by') or ''),
            }

    def _save_runtime_config(self):
        """Write custom nodes and branches back to TCL format."""
        setup_dir = os.path.join(self.run_dir, 'setup')
        os.makedirs(setup_dir, exist_ok=True)
        config_file = os.path.join(setup_dir, 'runtime_flow_config.tcl')

        lines = []
        lines.append('# CBFlow Runtime Flow Configuration')
        lines.append(f'# Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}')
        lines.append(f'# Custom nodes and branches for {self.flow_type} flow')
        lines.append('')

        if not self.custom_nodes and not self.branches:
            lines.append('# No custom nodes defined')
            with open(config_file, 'w') as f:
                f.write('\n'.join(lines) + '\n')
            return

        lines.append(f'array set {self.flow_lower} {{')

        # Write custom nodes
        for name, info in sorted(self.custom_nodes.items()):
            lines.append(f'    stages,{name},type {info.get("type", "")}')
            lines.append(f'    stages,{name},dependencies {info.get("dependencies", "")}')
            if info.get('branch_key'):
                lines.append(f'    stages,{name},branch_key {info["branch_key"]}')

        # Write branches
        for bkey, info in sorted(self.branches.items()):
            lines.append(f'    branch_keys,{bkey},name "{info.get("name", bkey)}"')
            if info.get('tag'):
                lines.append(f'    branch_keys,{bkey},tag "{info["tag"]}"')
            if info.get('created_date'):
                lines.append(f'    branch_keys,{bkey},created_date "{info["created_date"]}"')
            if info.get('created_by'):
                lines.append(f'    branch_keys,{bkey},created_by "{info["created_by"]}"')

        lines.append('}')
        lines.append('')

        with open(config_file, 'w') as f:
            f.write('\n'.join(lines) + '\n')

    def _regenerate_makefile(self):
        """Verify engine DAG after node changes (Makefile no longer generated)."""
        try:
            from race_engine import DagBuilder
            builder = DagBuilder(self.run_dir, self.flow_type, self.env)
            jobs, stages = builder.build()
            logger.info(f"  [DONE] Engine DAG verified: {len(jobs)} jobs, {len(stages)} stages")
        except Exception as e:
            logger.warning(f"  Engine DAG verification failed: {e}")

    # ─────────────────────────────────────────────────────────────────────────
    # Node Operations
    # ─────────────────────────────────────────────────────────────────────────

    def add_node(self, name: str, node_type: str, dependency: str) -> bool:
        """
        Add a custom node to the flow.

        Args:
            name: Unique name for the new node (e.g., 'place2').
            node_type: Type of stage this node represents (must match a base
                       stage or base type stripped of its numeric suffix).
            dependency: Name of the node this new node depends on.

        Returns:
            True if the node was successfully added, False otherwise.
        """
        # Check all stages (base + custom)
        all_stages = list(self.base_stages)
        all_stages.extend(self.custom_nodes.keys())
        # Also check stripped versions (e.g. "place" from "place1")
        base_types = sorted(set(re.sub(r'\d+$', '', s) for s in self.base_stages))

        # Validate node type
        if node_type not in self.base_stages and node_type not in base_types:
            logger.error(f"  Error: Invalid node type '{node_type}' for {self.flow_type}")
            logger.error(f"  Valid types: {', '.join(base_types)}")
            return False

        # Check for duplicates
        if name in all_stages:
            logger.error(f"  Error: Node '{name}' already exists")
            return False

        # Validate dependency exists
        if dependency and dependency not in all_stages:
            logger.error(f"  Error: Dependency '{dependency}' not found")
            logger.error(f"  Available: {', '.join(all_stages)}")
            return False

        # Check circular dependencies
        if self._has_circular_dependency(name, dependency):
            logger.error(f"  Error: Adding '{name}' would create a circular dependency")
            return False

        # Add the node
        self.custom_nodes[name] = {
            'type': node_type,
            'dependencies': dependency or '',
            'branch_key': '',
        }

        self._save_runtime_config()
        self._regenerate_makefile()

        logger.info(f"  [DONE] Added node '{name}' (type={node_type}, after={dependency})")
        return True

    def delete_node(self, name: str) -> bool:
        """
        Delete a custom node from the flow.

        Base stages cannot be deleted. If other custom nodes depend on the
        deleted node they will be orphaned (a warning is emitted).

        Args:
            name: Name of the custom node to delete.

        Returns:
            True if the node was successfully deleted, False otherwise.
        """
        # Can't delete base stages
        if name in self.base_stages:
            logger.error(f"  Error: Cannot delete base stage '{name}'")
            return False

        if name not in self.custom_nodes:
            logger.error(f"  Error: Custom node '{name}' not found")
            logger.error(f"  Custom nodes: {', '.join(self.custom_nodes.keys()) or 'none'}")
            return False

        # Block if other nodes depend on this one (would become orphaned)
        dependents = self._find_dependents(name)
        if dependents:
            logger.error(f"  Error: Cannot delete '{name}' — these nodes depend on it:")
            for d in dependents:
                logger.error(f"    - {d}")
            logger.error(f"  Delete the dependent nodes first, or delete the entire branch.")
            return False

        del self.custom_nodes[name]

        # Remove orphaned branches (branches with no remaining nodes)
        active_branch_keys = set(
            info.get('branch_key', '') for info in self.custom_nodes.values()
        )
        for bkey in list(self.branches.keys()):
            if bkey not in active_branch_keys:
                del self.branches[bkey]

        self._save_runtime_config()
        self._regenerate_makefile()

        logger.info(f"  [DONE] Deleted node '{name}'")
        return True

    def rename_node(self, old_name: str, new_name: str) -> bool:
        """Rename a custom node. Updates the node itself and all dependencies referencing it.
        Base stages cannot be renamed."""
        import re as _re
        if old_name in self.base_stages:
            logger.error(f"  Error: Cannot rename base stage '{old_name}'")
            return False
        if old_name not in self.custom_nodes:
            logger.error(f"  Error: Custom node '{old_name}' not found")
            return False
        if new_name in self.custom_nodes or new_name in self.base_stages:
            logger.error(f"  Error: Name '{new_name}' already exists")
            return False
        if not _re.match(r'^[a-zA-Z_]\w*$', new_name):
            logger.error(f"  Error: Invalid name '{new_name}' (use alphanumeric + underscore)")
            return False

        # Rename the node
        node_info = self.custom_nodes.pop(old_name)
        self.custom_nodes[new_name] = node_info

        # Update dependencies in other nodes that reference old_name
        for name, info in self.custom_nodes.items():
            if info.get('dependencies', '') == old_name:
                info['dependencies'] = new_name

        self._save_runtime_config()
        self._regenerate_makefile()
        logger.info(f"  [DONE] Renamed '{old_name}' → '{new_name}'")
        return True

    def get_all_nodes(self) -> dict:
        """
        Return all nodes (base + custom) with metadata.

        Returns:
            Dictionary mapping node names to their metadata including type,
            dependencies, branch_key (if any), and whether the node is custom.
        """
        nodes = {}
        for i, stage in enumerate(self.base_stages):
            nodes[stage] = {
                'type': 'base',
                'index': i,
                'dependencies': self._get_stage_dependencies(stage),
                'custom': False,
            }
        for name, info in self.custom_nodes.items():
            nodes[name] = {
                'type': info.get('type', ''),
                'dependencies': info.get('dependencies', ''),
                'branch_key': info.get('branch_key', ''),
                'custom': True,
            }
        return nodes

    # ─────────────────────────────────────────────────────────────────────────
    # Branch Operations
    # ─────────────────────────────────────────────────────────────────────────

    def create_branch(self, branch_name: str, from_stage: str, tag: str = '') -> bool:
        """
        Create a branch from a stage.

        When branching from a base stage, new nodes are created for every
        remaining stage in the flow (from that point onward). When branching
        from a custom node, a single branch node is created.

        Args:
            branch_name: Human-readable name for the branch.
            from_stage: Stage to branch from.
            tag: Optional tag appended to node names (e.g., tag='timing_fix'
                 produces place2_timing_fix, cts2_timing_fix, etc.)

        Returns:
            True if the branch was successfully created, False otherwise.
        """
        import random

        all_stages = list(self.base_stages) + list(self.custom_nodes.keys())

        if from_stage not in all_stages:
            logger.error(f"  Error: Stage '{from_stage}' not found")
            return False

        # Check for duplicate branch name
        existing_branches = [v.get('branch_name', '') for v in self.custom_nodes.values()
                            if isinstance(v, dict)]
        if branch_name in existing_branches:
            logger.error(f"  Error: Branch '{branch_name}' already exists")
            logger.error(f"  Use a different name or delete the existing branch first")
            return False

        # Generate branch key
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        base_type = re.sub(r'\d+$', '', from_stage)
        branch_key = f"{base_type}_{timestamp}_{random.randint(100, 999)}"

        # Find the index of from_stage in base stages
        from_idx = None
        for i, s in enumerate(self.base_stages):
            stripped = re.sub(r'\d+$', '', s)
            if s == from_stage or stripped == from_stage:
                from_idx = i
                break

        if from_idx is None:
            # from_stage is a custom node — find where it maps in the base flow
            # and create branch nodes for all remaining downstream stages
            # Use the stored type from custom_nodes if available (handles names like synthesis2_xyz)
            custom_info = self.custom_nodes.get(from_stage, {})
            base_type = custom_info.get('type', '') or re.sub(r'\d+$', '', from_stage)

            # Find the base stage index that matches this custom node's type
            base_idx = None
            for i, s in enumerate(self.base_stages):
                if re.sub(r'\d+$', '', s) == base_type:
                    base_idx = i
                    break

            if base_idx is not None:
                # Create branch nodes for all stages AFTER the matching base stage
                stages_to_branch = self.base_stages[base_idx + 1:]
                prev_dep = from_stage
                for stage in stages_to_branch:
                    sbase = re.sub(r'\d+$', '', stage)
                    suffix = self._next_suffix(sbase)
                    tag_suffix = f"_{tag}" if tag else ""
                    new_name = f"{sbase}{suffix}{tag_suffix}"
                    while new_name in self.base_stages or new_name in self.custom_nodes:
                        suffix += 1
                        new_name = f"{sbase}{suffix}{tag_suffix}"
                    self.custom_nodes[new_name] = {
                        'type': sbase,
                        'dependencies': prev_dep,
                        'branch_key': branch_key,
                        'branch_name': branch_name,
                    }
                    prev_dep = new_name
            else:
                # Can't find base type — create a single branch node
                logger.info(f"  Creating single branch node from '{from_stage}'")
                suffix = self._next_suffix(base_type)
                tag_suffix = f"_{tag}" if tag else ""
                new_name = f"{base_type}{suffix}{tag_suffix}"
                while new_name in self.base_stages or new_name in self.custom_nodes:
                    suffix += 1
                    new_name = f"{base_type}{suffix}{tag_suffix}"
                self.custom_nodes[new_name] = {
                    'type': base_type,
                    'dependencies': from_stage,
                    'branch_key': branch_key,
                }
        else:
            # Create branch nodes for remaining stages
            stages_to_branch = self.base_stages[from_idx:]

            first_node = True
            prev_dep = ''
            for stage in stages_to_branch:
                base_name = re.sub(r'\d+$', '', stage)
                suffix = self._next_suffix(base_name)
                tag_suffix = f"_{tag}" if tag else ""
                new_name = f"{base_name}{suffix}{tag_suffix}"
                while new_name in self.base_stages or new_name in self.custom_nodes:
                    suffix += 1
                    new_name = f"{base_name}{suffix}{tag_suffix}"

                if first_node:
                    # First branch node inherits same dependencies as original stage
                    orig_deps = self._get_stage_dependencies(from_stage) or ''
                    self.custom_nodes[new_name] = {
                        'type': base_name,
                        'dependencies': orig_deps,
                        'branch_key': branch_key,
                        'branch_name': branch_name,
                    }
                    first_node = False
                else:
                    self.custom_nodes[new_name] = {
                        'type': base_name,
                        'dependencies': prev_dep,
                        'branch_key': branch_key,
                        'branch_name': branch_name,
                    }
                prev_dep = new_name

        # Store branch metadata
        self.branches[branch_key] = {
            'name': branch_name,
            'tag': tag,
            'created_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'created_by': os.environ.get('USER', 'unknown'),
        }

        self._save_runtime_config()
        self._regenerate_makefile()

        branch_nodes = [
            n for n, info in self.custom_nodes.items()
            if info.get('branch_key') == branch_key
        ]
        logger.info(f"  [DONE] Branch '{branch_name}' created with {len(branch_nodes)} nodes")
        for n in branch_nodes:
            logger.info(f"    - {n}")
        return True

    def delete_branch(self, branch_name: str) -> bool:
        """
        Delete a branch by name, removing all its nodes.

        Args:
            branch_name: Human-readable name of the branch to delete.

        Returns:
            True if the branch was successfully deleted, False otherwise.
        """
        # Find branch key by name
        target_key = None
        for bkey, info in self.branches.items():
            if info.get('name') == branch_name:
                target_key = bkey
                break

        if not target_key:
            logger.error(f"  Error: Branch '{branch_name}' not found")
            if self.branches:
                logger.error("  Available branches:")
                for bkey, info in self.branches.items():
                    logger.error(f"    - {info.get('name', bkey)}")
            return False

        return self.delete_branch_by_key(target_key)

    def delete_branch_by_key(self, branch_key: str) -> bool:
        """Delete a branch by key. Blocks if external nodes depend on branch nodes."""
        if branch_key not in self.branches:
            logger.error(f"  Error: Branch key '{branch_key}' not found")
            return False

        branch_name = self.branches[branch_key].get('name', branch_key)

        # Find all nodes in this branch
        branch_nodes = set(
            n for n, info in self.custom_nodes.items()
            if info.get('branch_key') == branch_key
        )

        if not branch_nodes:
            del self.branches[branch_key]
            self._save_runtime_config()
            logger.info(f"  [DONE] Branch '{branch_name}' deleted (no nodes)")
            return True

        # Check for external dependents — nodes OUTSIDE this branch that depend on nodes IN this branch
        external_dependents = {}
        for node in branch_nodes:
            for name, info in self.custom_nodes.items():
                if name not in branch_nodes and info.get('dependencies') == node:
                    external_dependents.setdefault(node, []).append(name)

        if external_dependents:
            logger.error(f"  Error: Cannot delete branch '{branch_name}' — external nodes depend on it:")
            for node, deps in external_dependents.items():
                for d in deps:
                    logger.error(f"    {d} depends on {node}")
            logger.error(f"  Delete the dependent nodes/branches first.")
            return False

        # Safe to delete — remove all branch nodes
        for node in branch_nodes:
            del self.custom_nodes[node]

        del self.branches[branch_key]

        self._save_runtime_config()
        self._regenerate_makefile()

        logger.info(f"  [DONE] Branch '{branch_name}' deleted ({len(branch_nodes)} nodes removed)")
        return True

    def list_branches(self) -> list:
        """
        Return list of branches with their metadata and member nodes.

        Returns:
            List of dicts, each containing key, name, created_date,
            created_by, and nodes list.
        """
        result = []
        for bkey, info in self.branches.items():
            nodes = [
                n for n, ninfo in self.custom_nodes.items()
                if ninfo.get('branch_key') == bkey
            ]
            result.append({
                'key': bkey,
                'name': info.get('name', bkey),
                'created_date': info.get('created_date', ''),
                'created_by': info.get('created_by', ''),
                'nodes': nodes,
            })
        return result

    # ─────────────────────────────────────────────────────────────────────────
    # Graph Helpers
    # ─────────────────────────────────────────────────────────────────────────

    def _get_stage_dependencies(self, stage: str) -> str:
        """
        Get the dependency for a base stage from the node config.

        Looks up the dependency key in node_config, first with the full stage
        name and then with the numeric suffix stripped.

        Args:
            stage: Base stage name (e.g., 'place1').

        Returns:
            Name of the dependency stage, or empty string if none found.
        """
        dep_key = f'dependencies,{stage}'
        raw = self.node_config.get(dep_key, '')
        if raw:
            deps = _parse_tcl_list(raw)
            return ' '.join(deps) if deps else ''
        # Try without suffix
        stripped = re.sub(r'\d+$', '', stage)
        if stripped != stage:
            raw = self.node_config.get(f'dependencies,{stripped}', '')
            if raw:
                deps = _parse_tcl_list(raw)
                return ' '.join(deps) if deps else ''
        return ''

    def _has_circular_dependency(self, new_node: str, dependency: str) -> bool:
        """
        Check if adding new_node with the given dependency creates a cycle.

        Performs a depth-first search from the dependency back through the
        graph to see if it reaches new_node.

        Args:
            new_node: Name of the proposed new node.
            dependency: Name of the node it would depend on.

        Returns:
            True if a cycle would be created, False otherwise.
        """
        if not dependency:
            return False

        visited = set()

        def dfs(node):
            if node == new_node:
                return True
            if node in visited:
                return False
            visited.add(node)
            # Check custom node deps
            if node in self.custom_nodes:
                dep = self.custom_nodes[node].get('dependencies', '')
                if dep and dfs(dep):
                    return True
            return False

        return dfs(dependency)

    def _find_dependents(self, node_name: str) -> list:
        """
        Find custom nodes that directly depend on the given node.

        Args:
            node_name: Name of the node to find dependents for.

        Returns:
            List of custom node names that depend on node_name.
        """
        dependents = []
        for name, info in self.custom_nodes.items():
            if info.get('dependencies') == node_name:
                dependents.append(name)
        return dependents

    def _next_suffix(self, base_name: str) -> int:
        """
        Find the next available numeric suffix for a node name.

        Scans all existing node names (base + custom) that match the given
        base_name pattern and returns the next integer suffix.

        Args:
            base_name: Base name without numeric suffix (e.g., 'place').

        Returns:
            Next available integer suffix (e.g., 2 if 'place1' exists).
        """
        all_names = list(self.base_stages) + list(self.custom_nodes.keys())
        max_suffix = 0
        for name in all_names:
            m = re.match(rf'^{re.escape(base_name)}(\d+)$', name)
            if m:
                max_suffix = max(max_suffix, int(m.group(1)))
        return max_suffix + 1

    # ─────────────────────────────────────────────────────────────────────────
    # Validation
    # ─────────────────────────────────────────────────────────────────────────

    def validate(self) -> bool:
        """
        Validate the complete node configuration.

        Checks that:
          - All dependency references point to existing nodes.
          - No circular dependencies exist among custom nodes.

        Returns:
            True if validation passes, False otherwise.
        """
        errors = []
        all_nodes = self.get_all_nodes()

        # Check all dependencies exist
        for name, info in all_nodes.items():
            dep = info.get('dependencies', '')
            if dep and dep not in all_nodes:
                errors.append(f"Node '{name}' depends on '{dep}' which doesn't exist")

        # Check for circular dependencies
        for name in self.custom_nodes:
            dep = self.custom_nodes[name].get('dependencies', '')
            if dep and self._has_circular_dependency(name, dep):
                errors.append(f"Circular dependency detected involving '{name}'")

        if errors:
            logger.error(f"  Validation failed: {len(errors)} error(s)")
            for e in errors:
                logger.error(f"    - {e}")
            return False

        logger.info(f"  [PASS] Node configuration valid ({len(all_nodes)} nodes)")
        return True
