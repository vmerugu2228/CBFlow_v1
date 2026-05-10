#!/usr/bin/env python3
"""
CBFlow Makefile Generator

Generates Makefiles for CBFlow runs. Replaces the TCL gen_run_makefile.tcl system.
Reads flow configuration from tcl_config_parser.py and produces:
  - Main Makefile (with variables, main targets, stage includes, common targets)
  - Per-stage .make/{stage}.mk files (with subnode stamp rules and dependencies)

Supports all 11 flow types: SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP

Usage:
    from makefile_generator import MakefileGenerator
    gen = MakefileGenerator('FP', env_vars, '/path/to/run_dir')
    gen.generate()
"""

import os
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

from tcl_config_parser import (
    get_flow_stages, get_subnodes, get_tool_info,
    _load_node_config, _parse_tcl_list, _parse_tcl_string,
    is_merged_flow, parse_merged_flow
)


# ═══════════════════════════════════════════════════════════════════════════════
# TOOL VERSION VARIABLE MAPPING
# ═══════════════════════════════════════════════════════════════════════════════

# Explicit mapping for tool names that need non-trivial uppercasing or
# special naming (e.g. conformal_lp -> CONFORMAL_LP_VERSION).
# Derived from each flow's tool,name in *_config.tcl.
_TOOL_VERSION_OVERRIDES: Dict[str, str] = {
    # These are derived automatically: TOOL_NAME.upper() + "_VERSION"
    # Listed here only for documentation / reference:
    # innovus       -> INNOVUS_VERSION
    # genus         -> GENUS_VERSION
    # tempus        -> TEMPUS_VERSION
    # formality     -> FORMALITY_VERSION
    # calibre       -> CALIBRE_VERSION
    # icc2          -> ICC2_VERSION
    # voltus        -> VOLTUS_VERSION
    # conformal_lp  -> CONFORMAL_LP_VERSION
    # power_compiler -> POWER_COMPILER_VERSION
}


class MakefileGenerator:
    """Generates Makefiles for a single CBFlow run directory.

    Supports both single flows (FP, PNR, SYNTH) and merged flows (SYNTH_FP, SYNTH_FP_PNR).
    For merged flows, stages are prefixed with the flow name (e.g., synth_inputs, fp_floorplan).
    """

    def __init__(self, flow_type: str, env_vars: Dict[str, str], run_dir: str):
        """
        Args:
            flow_type: Flow type string (e.g. 'FP', 'PNR', 'SYNTH', 'SYNTH_FP').
            env_vars:  Merged environment variables (from .cbflow.env + .cbflow.tcl).
            run_dir:   Absolute path to the run directory where Makefile is written.
        """
        self.flow_type = flow_type.upper()
        self.flow_lower = flow_type.lower()
        self.env = env_vars
        self.run_dir = os.path.abspath(run_dir)
        self.merged = is_merged_flow(self.flow_type)

        if self.merged:
            self._init_merged()
        else:
            self._init_single()

    def _init_single(self):
        """Initialize for a single flow."""
        self.stages: List[str] = get_flow_stages(self.flow_type)
        self.tool_info: Dict[str, str] = get_tool_info(self.flow_type)
        self.node_config: Dict[str, str] = _load_node_config(self.flow_type)

        # Allow user_config to override tool vendor/name via env_vars
        # user_config sets pnr(tool,vendor) "cadence" → passed as env CBFLOW_TOOL_VENDOR
        # or parsed from user_config during workspace create
        if self.env:
            user_vendor = self.env.get('CBFLOW_TOOL_VENDOR', '')
            user_tool = self.env.get('CBFLOW_TOOL_NAME', '')
            if user_vendor:
                self.tool_info['vendor'] = user_vendor
            if user_tool:
                self.tool_info['name'] = user_tool

        self.tool_version_var: str = self._get_tool_version_var()
        self.tool_version: str = self.tool_info.get('version', 'v1.0.0') or 'v1.0.0'
        self.vendor: str = self.tool_info.get('vendor', '')
        self.tool_name: str = self.tool_info.get('name', '')
        # Stage metadata (same tool for all stages in single flow)
        self.stage_meta: Dict[str, dict] = {}
        for s in self.stages:
            self.stage_meta[s] = {
                'flow': self.flow_type,
                'original_stage': s,
                'tool_info': self.tool_info,
                'prefix': self.flow_lower,
            }

    def _init_merged(self):
        """Initialize for a merged flow (e.g., SYNTH_FP)."""
        from tcl_config_parser import get_merged_flow_stages
        merged_stages = get_merged_flow_stages(self.flow_type)

        self.stages = [s['name'] for s in merged_stages]
        self.stage_meta: Dict[str, dict] = {}
        self.sub_flows = parse_merged_flow(self.flow_type)

        # Collect unique tool infos
        self._tool_infos: Dict[str, dict] = {}  # prefix -> tool_info
        self._tool_version_vars: Dict[str, str] = {}  # prefix -> VERSION var

        for s in merged_stages:
            self.stage_meta[s['name']] = {
                'flow': s['flow'],
                'original_stage': s['original_stage'],
                'tool_info': s['tool'],
                'prefix': s['prefix'],
                'dependency': s.get('dependency', ''),
            }
            if s['prefix'] not in self._tool_infos:
                self._tool_infos[s['prefix']] = s['tool']
                tool_name = s['tool'].get('name', '')
                self._tool_version_vars[s['prefix']] = f"{tool_name.upper()}_VERSION" if tool_name else ''

        # Use first flow's tool as default (for header display)
        first_flow = self.sub_flows[0] if self.sub_flows else self.flow_type
        self.tool_info = get_tool_info(first_flow)
        self.node_config = {}  # Not used directly for merged
        self.tool_version_var = self._get_tool_version_var()
        self.tool_version = self.tool_info.get('version', 'v1.0.0') or 'v1.0.0'
        self.vendor = self.tool_info.get('vendor', '')
        self.tool_name = self.tool_info.get('name', '')

    # ═══════════════════════════════════════════════════════════════════════════
    # PUBLIC API
    # ═══════════════════════════════════════════════════════════════════════════

    def generate(self) -> bool:
        """Generate the main Makefile and per-stage .mk files.

        Returns True on success, False on failure.
        """
        try:
            makefile_path = os.path.join(self.run_dir, 'Makefile')
            with open(makefile_path, 'w') as mf:
                self._write_header(mf)
                self._write_variables(mf)
                self._write_main_targets(mf)
                self._write_stage_stamps_and_includes(mf)
                self._write_clean_target(mf)
                # Note: All utility targets (node mgmt, status, retrace, update, etc.)
                # are now handled by 'cbflow run <command>' - not in Makefile

            # Generate per-stage .mk files
            self._generate_stage_makefiles()
            return True

        except Exception as e:
            print(f"ERROR: Makefile generation failed: {e}")
            return False

    # ═══════════════════════════════════════════════════════════════════════════
    # TOOL VERSION VARIABLE
    # ═══════════════════════════════════════════════════════════════════════════

    def _get_tool_version_var(self) -> str:
        """Map the tool name to its Makefile VERSION variable name.

        Examples:
            innovus       -> INNOVUS_VERSION
            genus         -> GENUS_VERSION
            conformal_lp  -> CONFORMAL_LP_VERSION
            power_compiler -> POWER_COMPILER_VERSION
        """
        tool_name = self.tool_info.get('name', '')
        if not tool_name:
            return f"{self.flow_type}_TOOL_VERSION"
        return f"{tool_name.upper()}_VERSION"

    # ═══════════════════════════════════════════════════════════════════════════
    # HEADER
    # ═══════════════════════════════════════════════════════════════════════════

    def _write_header(self, mf) -> None:
        """Write the Makefile header block."""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        mf.write(f"# {'=' * 79}\n")
        mf.write(f"# CBFlow {self.flow_type} MAKEFILE\n")
        mf.write(f"# Auto-generated for {self.flow_type} flow\n")
        mf.write(f"# Generated: {timestamp}\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

    # ═══════════════════════════════════════════════════════════════════════════
    # VARIABLES
    # ═══════════════════════════════════════════════════════════════════════════

    def _write_variables(self, mf) -> None:
        """Write the variables section."""
        mf.write(f"# {'=' * 79}\n")
        mf.write(f"# {self.flow_type} VARIABLES\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        mf.write("# Environment variables - read from .run.cbflow.env\n")
        mf.write("FLOW_DIR ?= $(shell grep '^export FLOW_DIR=' .run.cbflow.env"
                 " | cut -d'=' -f2 | tr -d '\"')\n")
        mf.write("GENERATION_VERSION ?= $(shell grep '^export GENERATION_VERSION='"
                 " .run.cbflow.env | cut -d'=' -f2 | tr -d '\"')\n")
        mf.write("UTILITIES_VERSION ?= $(shell grep '^export UTILITIES_VERSION='"
                 " .run.cbflow.env | cut -d'=' -f2 | tr -d '\"')\n")
        mf.write("NODE_MANAGEMENT_VERSION ?= $(shell grep '^export NODE_MANAGEMENT_VERSION='"
                 " .run.cbflow.env | cut -d'=' -f2 | tr -d '\"')\n")
        if self.merged:
            # Include all unique tool version vars for merged flows
            seen_vars = set()
            for prefix, tool_info in self._tool_infos.items():
                var = self._tool_version_vars.get(prefix, '')
                version = tool_info.get('version', 'v1.0.0') or 'v1.0.0'
                if var and var not in seen_vars:
                    mf.write(f"{var} ?= {version}\n")
                    seen_vars.add(var)
        else:
            mf.write(f"{self.tool_version_var} ?= {self.tool_version}\n")
        mf.write("\n")

        mf.write("# Directories\n")
        mf.write("STAMP_DIR = .stamps\n")
        mf.write("WORK_DIR = work\n")
        mf.write("LOGS_DIR = logs\n")
        mf.write("\n")

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN TARGETS (all, help, clean)
    # ═══════════════════════════════════════════════════════════════════════════

    def _write_main_targets(self, mf) -> None:
        """Write the main targets section: default goal, all, help."""
        stages_str = " ".join(self.stages)

        mf.write(f"# {'=' * 79}\n")
        mf.write(f"# MAIN {self.flow_type} TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        mf.write(".DEFAULT_GOAL := help\n")
        mf.write("\n")

        # all target
        mf.write(f"# Complete {self.flow_type} flow\n")
        mf.write(".PHONY: all\n")
        mf.write(f"all: {stages_str}\n")
        mf.write(f"\t@echo \"done {self.flow_type} flow completed successfully\"\n")
        mf.write("\n")

        # help target
        mf.write("# Show help information\n")
        mf.write(".PHONY: help\n")
        mf.write("help:\n")
        mf.write(f"\t@echo \"CBFlow {self.flow_type} Makefile\"\n")
        mf.write(f"\t@echo \"\"\n")
        mf.write(f"\t@echo \"Flow stages:\"\n")
        for stage in self.stages:
            padded = stage.ljust(12)
            mf.write(f"\t@echo \"  make {padded}   Run {stage} stage\"\n")
        mf.write(f"\t@echo \"\"\n")
        mf.write(f"\t@echo \"Commands:\"\n")
        mf.write(f"\t@echo \"  make all           Run complete {self.flow_type} flow\"\n")
        mf.write(f"\t@echo \"  make clean         Clean all generated files\"\n")
        mf.write("\n")

    # ═══════════════════════════════════════════════════════════════════════════
    # STAGE STAMP VARIABLES AND INCLUDES
    # ═══════════════════════════════════════════════════════════════════════════

    def _write_stage_stamps_and_includes(self, mf) -> None:
        """Write stage stamp variable definitions and include directives."""
        mf.write(f"# {'=' * 79}\n")
        mf.write(f"# {self.flow_type} STAGE TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        # Stamp variables
        for stage in self.stages:
            stage_upper = stage.upper()
            mf.write(f"{stage_upper}_STAMP = $(STAMP_DIR)/{stage}.stamp\n")
        mf.write("\n")

        # Include directives
        for stage in self.stages:
            mf.write(f"include .make/{stage}.mk\n")
        mf.write("\n")

    # ═══════════════════════════════════════════════════════════════════════════
    # CLEAN TARGET
    # ═══════════════════════════════════════════════════════════════════════════

    def _write_clean_target(self, mf) -> None:
        """Write the clean target."""
        mf.write(f"# {'=' * 79}\n")
        mf.write(f"# CLEAN\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")
        mf.write(f"# Clean {self.flow_type} results\n")
        mf.write(".PHONY: clean\n")
        mf.write("clean:\n")
        mf.write(f"\t@echo \"Cleaning {self.flow_type} files...\"\n")
        mf.write("\t@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make\n")
        mf.write("\t@rm -f Makefile\n")
        mf.write(f"\t@echo \"[DONE] Clean completed\"\n")
        mf.write("\n")

    # ═══════════════════════════════════════════════════════════════════════════
    # LEGACY COMMON TARGETS (kept for reference, no longer generated)
    # ═══════════════════════════════════════════════════════════════════════════

    def _write_common_targets(self, mf) -> None:
        """Legacy: Write all common targets. No longer called - use cbflow commands instead."""
        pass

    # ── MMMC Targets ──────────────────────────────────────────────────────────

    def _write_mmmc_targets(self, mf) -> None:
        """Write MMMC scenario information targets."""
        mf.write(f"# {'=' * 79}\n")
        mf.write("# MMMC SCENARIO INFORMATION TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        mf.write("# MMMC corners information (show available scenario combinations)\n")
        mf.write(".PHONY: mmmc_corners\n")
        mf.write("mmmc_corners:\n")
        mf.write('\t@if [ -z "$(TYPE)" ]; then \\\n')
        mf.write('\t\techo "Error: TYPE parameter required"; \\\n')
        mf.write('\t\techo "Usage: make mmmc_corners TYPE=<setup|hold|power|timing|all>"; \\\n')
        mf.write('\t\techo ""; \\\n')
        mf.write('\t\techo "Available types (scenarios are read from MMMC config):"; \\\n')
        mf.write('\t\techo "  setup, hold, power, timing, all"; \\\n')
        mf.write('\t\techo ""; \\\n')
        mf.write('\t\techo "Examples:"; \\\n')
        mf.write('\t\techo "  make mmmc_corners TYPE=setup    # Show setup scenarios"; \\\n')
        mf.write('\t\techo "  make mmmc_corners TYPE=timing   # Show timing scenarios"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@echo "==============================================================================="\n')
        mf.write('\t@echo "MMMC Scenarios for Type: $(TYPE)"\n')
        mf.write('\t@echo "==============================================================================="\n')
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/show_mmmc_scenarios.tcl" "$(TYPE)"\n')
        mf.write("\n")

        mf.write("# MMMC node scenarios (show hardcoded node assignments)\n")
        mf.write(".PHONY: mmmc_nodes\n")
        mf.write("mmmc_nodes:\n")
        mf.write('\t@if [ -n "$(NODE)" ]; then \\\n')
        mf.write('\t\ttclsh "$(FLOW_DIR)/utils/show_mmmc_nodes.tcl" "$(NODE)"; \\\n')
        mf.write('\telse \\\n')
        mf.write('\t\ttclsh "$(FLOW_DIR)/utils/show_mmmc_nodes.tcl"; \\\n')
        mf.write('\tfi\n')
        mf.write("\n")

    # ── Release Targets ───────────────────────────────────────────────────────

    def _write_release_targets(self, mf) -> None:
        """Write release management targets."""
        mf.write(f"# {'=' * 79}\n")
        mf.write("# RELEASE MANAGEMENT TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        mf.write("# Create release package\n")
        mf.write(".PHONY: release\n")
        mf.write("release:\n")
        mf.write('\t@if [ -z "$(TAG)" ] || [ -z "$(TYPE)" ]; then \\\n')
        mf.write('\t\techo "Error: Missing required parameters"; \\\n')
        mf.write('\t\techo "Usage: make release TAG=<tag_name> TYPE=<release_type>'
                 ' [NOTES=\\"<notes>\\"] [NODE=<node_name>] [DIR=<node_dir>]'
                 ' [MILESTONE=<exit_milestone>]"; \\\n')
        mf.write('\t\techo ""; \\\n')
        mf.write('\t\techo "Available release types:"; \\\n')
        mf.write('\t\techo "  synthesis       - Synthesis deliverables"; \\\n')
        mf.write('\t\techo "  pnr_floorplan   - PNR floorplan deliverables"; \\\n')
        mf.write('\t\techo "  pnr_placed      - PNR placed design deliverables"; \\\n')
        mf.write('\t\techo "  pnr_cts         - PNR clock tree synthesis deliverables"; \\\n')
        mf.write('\t\techo "  pnr_postroute   - PNR post-route deliverables"; \\\n')
        mf.write('\t\techo "  pnr_signoff     - PNR signoff deliverables"; \\\n')
        mf.write('\t\techo "  signoff         - Final signoff deliverables"; \\\n')
        mf.write('\t\techo ""; \\\n')
        mf.write('\t\techo "Available exit milestones:"; \\\n')
        mf.write('\t\techo "  FP_EXIT      - Floorplan exit milestone"; \\\n')
        mf.write('\t\techo "  PLACE_EXIT   - Placement exit milestone"; \\\n')
        mf.write('\t\techo "  CTS_EXIT     - CTS exit milestone"; \\\n')
        mf.write('\t\techo "  PRO_EXIT     - Post-route optimization exit milestone"; \\\n')
        mf.write('\t\techo "  BTO          - Backend tapeout milestone"; \\\n')
        mf.write('\t\techo "  MTO          - Mask tapeout milestone"; \\\n')
        mf.write('\t\techo ""; \\\n')
        mf.write('\t\techo "Examples:"; \\\n')

        # Flow-specific release examples
        self._write_release_examples(mf)

        mf.write('\t\techo "  make release TAG=v6.0 TYPE=pnr_postroute'
                 ' MILESTONE=PRO_EXIT"; \\\n')
        mf.write('\t\techo "  make release TAG=tapeout TYPE=signoff'
                 ' MILESTONE=BTO NOTES=\\"Backend tapeout\\""; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@echo "Creating release: $(TAG) (type: $(TYPE))"\n')
        mf.write('\t@# Build command with optional parameters\n')
        mf.write('\t@CMD="tclsh \\"$(FLOW_DIR)/utils/release_data.tcl\\"'
                 ' \\"$(TAG)\\" \\"$(TYPE)\\""; \\\n')
        mf.write('\tif [ -n "$(NOTES)" ]; then CMD="$$CMD -notes \\"$(NOTES)\\""; fi; \\\n')
        mf.write('\tif [ -n "$(NODE)" ]; then CMD="$$CMD -node_name \\"$(NODE)\\""; fi; \\\n')
        mf.write('\tif [ -n "$(DIR)" ]; then CMD="$$CMD -directory \\"$(DIR)\\""; fi; \\\n')
        mf.write('\tif [ -n "$(MILESTONE)" ]; then CMD="$$CMD -m \\"$(MILESTONE)\\""; fi; \\\n')
        mf.write('\teval $$CMD\n')
        mf.write('\t@echo "done Release $(TAG) created successfully"\n')
        mf.write("\n")

    def _write_release_examples(self, mf) -> None:
        """Write flow-specific release usage examples."""
        ft = self.flow_type
        if ft == "SYNTH":
            mf.write('\t\techo "  make release TAG=v1.0 TYPE=synthesis"; \\\n')
            mf.write('\t\techo "  make release TAG=v2.0 TYPE=synthesis'
                     ' NOTES=\\"Final synthesis\\""; \\\n')
            mf.write('\t\techo "  make release TAG=v3.0 TYPE=synthesis'
                     ' NODE=synthesis1"; \\\n')
            mf.write('\t\techo "  make release TAG=v4.0 TYPE=synthesis'
                     ' DIR=work/SYNTH/synthesis_custom"; \\\n')
            mf.write('\t\techo "  make release TAG=v5.0 TYPE=synthesis'
                     ' MILESTONE=SYNTH_EXIT"; \\\n')
        elif ft == "PNR":
            mf.write('\t\techo "  make release TAG=v1.0 TYPE=pnr_floorplan"; \\\n')
            mf.write('\t\techo "  make release TAG=v2.0 TYPE=pnr_placed'
                     ' NOTES=\\"Final placed\\""; \\\n')
            mf.write('\t\techo "  make release TAG=v3.0 TYPE=pnr_floorplan'
                     ' NODE=floorplan1"; \\\n')
            mf.write('\t\techo "  make release TAG=v4.0 TYPE=pnr_floorplan'
                     ' DIR=work/PNR/floorplan_custom"; \\\n')
            mf.write('\t\techo "  make release TAG=v5.0 TYPE=pnr_floorplan'
                     ' MILESTONE=FP_EXIT"; \\\n')
        elif ft == "FP":
            mf.write('\t\techo "  make release TAG=v1.0 TYPE=fp_floorplan"; \\\n')
            mf.write('\t\techo "  make release TAG=v2.0 TYPE=fp_powerplan'
                     ' NOTES=\\"Final powerplan\\""; \\\n')
            mf.write('\t\techo "  make release TAG=v3.0 TYPE=fp_floorplan'
                     ' NODE=floorplan1"; \\\n')
            mf.write('\t\techo "  make release TAG=v4.0 TYPE=fp_floorplan'
                     ' DIR=work/FP/floorplan_custom"; \\\n')
            mf.write('\t\techo "  make release TAG=v5.0 TYPE=fp_floorplan'
                     ' MILESTONE=FP_EXIT"; \\\n')
        else:
            ft_lower = ft.lower()
            mf.write(f'\t\techo "  make release TAG=v1.0 TYPE={ft}"; \\\n')
            mf.write(f'\t\techo "  make release TAG=v2.0 TYPE={ft}'
                     f' NOTES=\\"Final {ft}\\""; \\\n')
            mf.write(f'\t\techo "  make release TAG=v3.0 TYPE={ft}'
                     f' NODE=stage1"; \\\n')
            mf.write(f'\t\techo "  make release TAG=v4.0 TYPE={ft}'
                     f' DIR=work/custom"; \\\n')
            mf.write(f'\t\techo "  make release TAG=v5.0 TYPE={ft}'
                     f' MILESTONE=EXIT"; \\\n')

    # ── Node Management Targets ───────────────────────────────────────────────

    def _write_node_management_targets(self, mf) -> None:
        """Write node management targets."""
        mf.write(f"# {'=' * 79}\n")
        mf.write("# NODE MANAGEMENT TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        # Add node
        mf.write("# Add a new custom node to the flow\n")
        mf.write(".PHONY: add_node\n")
        mf.write("add_node:\n")
        mf.write('\t@if [ -z "$(NODE)" ] || [ -z "$(TYPE)" ]; then \\\n')
        mf.write('\t\techo "Error: Missing required parameters"; \\\n')
        mf.write('\t\techo "Usage: make add_node NODE=<node_name> TYPE=<node_type>'
                 ' [DEP=<dependency>]"; \\\n')
        mf.write('\t\techo "Examples:"; \\\n')
        mf.write('\t\techo "  make add_node NODE=floorplan2 TYPE=floorplan DEP=inputs"; \\\n')
        mf.write('\t\techo "  make add_node NODE=synthesis2 TYPE=synthesis DEP=synthesis1"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/node_management/$(NODE_MANAGEMENT_VERSION)/'
                 'manage_node.tcl" -add -node "$(NODE)" -node_type "$(TYPE)"'
                 ' $$([ -n "$(DEP)" ] && echo "-dep $(DEP)")\n')
        mf.write("\n")

        # Delete node
        mf.write("# Delete a custom node from the flow\n")
        mf.write(".PHONY: delete_node\n")
        mf.write("delete_node:\n")
        mf.write('\t@if [ -z "$(NODE)" ]; then \\\n')
        mf.write('\t\techo "Error: NODE parameter required"; \\\n')
        mf.write('\t\techo "Usage: make delete_node NODE=<node_name>"; \\\n')
        mf.write('\t\techo "Example: make delete_node NODE=floorplan2"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/node_management/$(NODE_MANAGEMENT_VERSION)/'
                 'manage_node.tcl" -delete -node "$(NODE)"\n')
        mf.write("\n")

        # List nodes
        mf.write("# List all available nodes in the flow\n")
        mf.write(".PHONY: list_nodes\n")
        mf.write("list_nodes:\n")
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/node_management/$(NODE_MANAGEMENT_VERSION)/'
                 'manage_node.tcl" list\n')
        mf.write("\n")

        # Show graph
        mf.write("# Show flow graph\n")
        mf.write(".PHONY: show_graph\n")
        mf.write("show_graph:\n")
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/node_management/$(NODE_MANAGEMENT_VERSION)/'
                 'manage_node.tcl" graph\n')
        mf.write("\n")

        # Validate nodes
        mf.write("# Validate node configuration\n")
        mf.write(".PHONY: validate_nodes\n")
        mf.write("validate_nodes:\n")
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/node_management/$(NODE_MANAGEMENT_VERSION)/'
                 'manage_node.tcl" validate\n')
        mf.write("\n")

    # ── Status Targets ────────────────────────────────────────────────────────

    def _write_status_targets(self, mf) -> None:
        """Write status and monitoring targets."""
        mf.write(f"# {'=' * 79}\n")
        mf.write("# STATUS AND MONITORING TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        mf.write("# Show run status summary\n")
        mf.write(".PHONY: status\n")
        mf.write("status:\n")
        mf.write('\t@if [ -f ".run.status" ]; then \\\n')
        mf.write('\t\techo "Run Status Summary:"; \\\n')
        mf.write("\t\tawk 'BEGIN{complete=0; error=0; total=0}"
                 " /COMPLETE/{complete++; total++} /ERROR/{error++; total++}"
                 ' END{printf "Completed: %d\\nErrors: %d\\nTotal: %d\\n",'
                 " complete, error, total}' .run.status; \\\n")
        mf.write('\t\techo "Last 10 status entries:"; \\\n')
        mf.write('\t\ttail -10 .run.status | while read line; do echo "  $$line"; done; \\\n')
        mf.write('\telse \\\n')
        mf.write('\t\techo "No status file found - run not started yet"; \\\n')
        mf.write('\tfi\n')
        mf.write("\n")

        mf.write("# Show detailed run status\n")
        mf.write(".PHONY: run_status\n")
        mf.write("run_status:\n")
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/utilities/$(UTILITIES_VERSION)/'
                 'run_status.tcl" "$(PWD)"\n')
        mf.write("\n")

    # ── Branch Targets ────────────────────────────────────────────────────────

    def _write_branch_targets(self, mf) -> None:
        """Write branch management targets."""
        mf.write(f"# {'=' * 79}\n")
        mf.write("# BRANCH MANAGEMENT TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        # Create branch
        mf.write("# Create a new branch from current state\n")
        mf.write(".PHONY: create_branch\n")
        mf.write("create_branch:\n")
        mf.write('\t@if [ -z "$(BRANCH)" ] || [ -z "$(FROM)" ]; then \\\n')
        mf.write('\t\techo "Error: BRANCH and FROM parameters required"; \\\n')
        mf.write('\t\techo "Usage: make create_branch BRANCH=<branch_name>'
                 ' FROM=<source_stage>"; \\\n')
        mf.write('\t\techo "Examples:"; \\\n')
        mf.write('\t\techo "  make create_branch BRANCH=experiment1 FROM=synthesis"; \\\n')
        mf.write('\t\techo "  make create_branch BRANCH=fix_timing FROM=inputs"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/node_management/$(NODE_MANAGEMENT_VERSION)/'
                 'manage_node.tcl" -create_branch -node "$(FROM)" -branch_name "$(BRANCH)"\n')
        mf.write("\n")

        # Delete branch
        mf.write("# Delete a branch\n")
        mf.write(".PHONY: delete_branch\n")
        mf.write("delete_branch:\n")
        mf.write('\t@if [ -z "$(NODE)" ]; then \\\n')
        mf.write('\t\techo "Error: NODE parameter required"; \\\n')
        mf.write('\t\techo "Usage: make delete_branch NODE=<branch_start_node>"; \\\n')
        mf.write('\t\techo "Example: make delete_branch NODE=synthesis_branch1"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/node_management/$(NODE_MANAGEMENT_VERSION)/'
                 'manage_node.tcl" -delete_branch -node "$(NODE)"\n')
        mf.write("\n")

        # List branches
        mf.write("# List all available branches\n")
        mf.write(".PHONY: list_branches\n")
        mf.write("list_branches:\n")
        mf.write('\t@tclsh "$(FLOW_DIR)/utils/node_management/$(NODE_MANAGEMENT_VERSION)/'
                 'manage_node.tcl" -list_branches\n')
        mf.write("\n")

    # ── Update Targets ────────────────────────────────────────────────────────

    def _write_update_targets(self, mf) -> None:
        """Write run update targets."""
        mf.write(f"# {'=' * 79}\n")
        mf.write("# RUN UPDATE TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        mf.write("# Workspace directory (parent of current run)\n")
        mf.write('WORKSPACE_DIR ?= $(shell dirname "$(PWD)")\n')
        mf.write("\n")

        mf.write("# Update run to workspace release version or specific release\n")
        mf.write("# Usage: make update                    - Update to workspace release\n")
        mf.write("#        make update RELEASE=v2.0.0     - Update to specific release\n")
        mf.write("#        make update REGENERATE=1       - Also regenerate Makefile\n")
        mf.write(".PHONY: update\n")
        mf.write("update:\n")
        mf.write('\t@echo ""\n')
        mf.write('\t@echo "==============================================================="\n')
        mf.write('\t@if [ -n "$(RELEASE)" ]; then \\\n')
        mf.write('\t\techo "  CBFlow Run Update to Release $(RELEASE)"; \\\n')
        mf.write('\telse \\\n')
        mf.write('\t\techo "  CBFlow Run Update"; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@echo "==============================================================="\n')
        mf.write('\t@echo ""\n')
        mf.write('\t@if [ -z "$(RELEASE)" ] && [ ! -f "$(WORKSPACE_DIR)/.cbflow.env" ]; then \\\n')
        mf.write('\t\techo "Error: Workspace environment not found at'
                 ' $(WORKSPACE_DIR)/.cbflow.env"; \\\n')
        mf.write("\t\techo \"   Run 'make init' in the workspace first,"
                 ' or specify RELEASE=vX.Y.Z"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@echo "Current Run:     $(PWD)"\n')
        mf.write('\t@if [ -z "$(RELEASE)" ]; then \\\n')
        mf.write('\t\techo "Workspace:       $(WORKSPACE_DIR)"; \\\n')
        mf.write('\tfi\n')
        mf.write("\t@current_release=$$(grep 'CBFLOW_RELEASE_VERSION='"
                 " .run.cbflow.env 2>/dev/null | cut -d'=' -f2 | tr -d '\"'); \\\n")
        mf.write('\tif [ -n "$(RELEASE)" ]; then \\\n')
        mf.write('\t\ttarget_release="$(RELEASE)"; \\\n')
        mf.write('\telse \\\n')
        mf.write("\t\ttarget_release=$$(grep 'CBFLOW_RELEASE_VERSION='"
                 ' "$(WORKSPACE_DIR)/.cbflow.env"'
                 " | cut -d'=' -f2 | tr -d '\"'); \\\n")
        mf.write('\tfi; \\\n')
        mf.write('\techo "Current Release: $$current_release"; \\\n')
        mf.write('\techo "Target Release:  $$target_release"; \\\n')
        mf.write('\techo ""; \\\n')
        mf.write('\tif [ "$$current_release" = "$$target_release" ]; then \\\n')
        mf.write('\t\techo "Run is already at the target release version"; \\\n')
        mf.write('\t\texit 0; \\\n')
        mf.write('\tfi; \\\n')
        mf.write('\techo "This will update run environment files to the new release."; \\\n')
        mf.write('\techo ""; \\\n')
        mf.write('\tread -p "Do you want to proceed? (y/N): " confirm; \\\n')
        mf.write('\tif [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \\\n')
        mf.write('\t\techo ""; \\\n')
        mf.write('\t\techo "Update cancelled."; \\\n')
        mf.write('\t\texit 0; \\\n')
        mf.write('\tfi; \\\n')
        mf.write('\techo ""; \\\n')
        mf.write('\tif [ -n "$(RELEASE)" ]; then \\\n')
        mf.write('\t\tCMD="tclsh \\"$(FLOW_DIR)/utils/utilities/$(UTILITIES_VERSION)/'
                 'run_update.tcl\\" \\"$(PWD)\\" -release \\"$(RELEASE)\\" -backup"; \\\n')
        mf.write('\telse \\\n')
        mf.write('\t\tCMD="tclsh \\"$(FLOW_DIR)/utils/utilities/$(UTILITIES_VERSION)/'
                 'run_update.tcl\\" \\"$(PWD)\\"'
                 ' -workspace \\"$(WORKSPACE_DIR)\\" -backup"; \\\n')
        mf.write('\tfi; \\\n')
        mf.write('\tif [ "$(REGENERATE)" = "1" ]; then \\\n')
        mf.write('\t\tCMD="$$CMD -regenerate"; \\\n')
        mf.write('\tfi; \\\n')
        mf.write('\teval $$CMD\n')
        mf.write('\t@echo ""\n')
        mf.write('\t@if [ "$(REGENERATE)" != "1" ]; then \\\n')
        mf.write("\t\techo \"Note: Run 'make generate_makefile' or"
                 " 'make update REGENERATE=1' to regenerate the Makefile.\"; \\\n")
        mf.write('\t\techo ""; \\\n')
        mf.write('\tfi\n')
        mf.write("\n")

        # Release info
        mf.write("# Show current release information\n")
        mf.write(".PHONY: release_info\n")
        mf.write("release_info:\n")
        mf.write('\t@echo ""\n')
        mf.write('\t@echo "==============================================================="\n')
        mf.write('\t@echo "  CBFlow Release Information"\n')
        mf.write('\t@echo "==============================================================="\n')
        mf.write('\t@echo ""\n')
        mf.write('\t@echo "Run Directory:"\n')
        mf.write('\t@echo "  $(PWD)"\n')
        mf.write('\t@echo ""\n')
        mf.write('\t@echo "Run Release Version:"\n')
        mf.write("\t@grep 'CBFLOW_RELEASE_VERSION=' .run.cbflow.env 2>/dev/null"
                 " | cut -d'=' -f2 | tr -d '\"' | sed 's/^/  /'\n")
        mf.write('\t@echo ""\n')
        mf.write('\t@echo "Workspace Release Version:"\n')
        mf.write('\t@if [ -f "$(WORKSPACE_DIR)/.cbflow.env" ]; then \\\n')
        mf.write("\t\tgrep 'CBFLOW_RELEASE_VERSION='"
                 ' "$(WORKSPACE_DIR)/.cbflow.env"'
                 " | cut -d'=' -f2 | tr -d '\"' | sed 's/^/  /'; \\\n")
        mf.write('\telse \\\n')
        mf.write('\t\techo "  (workspace not initialized)"; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@echo ""\n')
        mf.write('\t@echo "Component Versions:"\n')
        mf.write("\t@grep '_VERSION=' .run.cbflow.env 2>/dev/null"
                 " | grep -v 'CBFLOW_RELEASE' | sed 's/export /  /' | sed 's/\"//g'\n")
        mf.write('\t@echo ""\n')
        mf.write("\n")

    # ── Retrace Targets ───────────────────────────────────────────────────────

    def _write_retrace_targets(self, mf) -> None:
        """Write retrace targets (with flow-specific stage list in case statement)."""
        stages_str = " ".join(self.stages)

        mf.write(f"# {'=' * 79}\n")
        mf.write("# RETRACE TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        # Main retrace target
        mf.write("# Remove stamps to force rerun\n")
        mf.write(".PHONY: retrace\n")
        mf.write("retrace:\n")
        mf.write('\t@echo "Removing completion stamps to force rerun..."\n')
        mf.write('\t@if [ -n "$(NODE)" ]; then \\\n')
        mf.write('\t\techo "Selective retrace from node: $(NODE)"; \\\n')
        mf.write('\t\t$(MAKE) retrace-from-node NODE=$(NODE); \\\n')
        mf.write('\telse \\\n')
        mf.write('\t\techo "Complete retrace - removing all stamps..."; \\\n')
        mf.write('\t\t$(MAKE) retrace-all; \\\n')
        mf.write('\tfi\n')
        mf.write("\n")

        # Retrace all
        mf.write("# Remove all stamps\n")
        mf.write(".PHONY: retrace-all\n")
        mf.write("retrace-all:\n")
        mf.write('\t@if [ -d "$(STAMP_DIR)" ]; then \\\n')
        mf.write('\t\techo "Found stamp directory: $(STAMP_DIR)"; \\\n')
        mf.write('\t\tfor stamp in $(STAMP_DIR)/*.stamp; do \\\n')
        mf.write('\t\t\tif [ -f "$$stamp" ]; then \\\n')
        mf.write('\t\t\t\techo "  Removing: $$stamp"; \\\n')
        mf.write('\t\t\t\trm -f "$$stamp"; \\\n')
        mf.write('\t\t\tfi; \\\n')
        mf.write('\t\tdone; \\\n')
        mf.write('\t\techo "  Keeping stamp directory structure..."; \\\n')
        mf.write('\telse \\\n')
        mf.write('\t\techo "No stamp directory found - nothing to retrace"; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@if [ -f ".run.status" ]; then \\\n')
        mf.write('\t\techo "  Clearing run status file..."; \\\n')
        mf.write('\t\trm -f ".run.status"; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@echo "done Complete retrace finished - all steps will rerun"\n')
        mf.write("\n")

        # Selective retrace from node
        mf.write("# Remove stamps from specified node onwards"
                 " (supports stages and subnodes)\n")
        mf.write(".PHONY: retrace-from-node\n")
        mf.write("retrace-from-node:\n")
        mf.write('\t@if [ -z "$(NODE)" ]; then \\\n')
        mf.write('\t\techo "Error: NODE not specified"; \\\n')
        mf.write('\t\techo "Usage: make retrace NODE=<stage_name|subnode_name>"; \\\n')
        mf.write(f'\t\techo "Available stages: {stages_str}"; \\\n')
        mf.write('\t\techo "Available subnodes: Use format stage_subnode'
                 ' (e.g., inputs_validate, synthesis_run)"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')

        # Build case statement with flow-specific stages
        mf.write('\t@case "$(NODE)" in \\\n')
        for i, stage in enumerate(self.stages):
            remaining = self.stages[i:]
            remaining_str = " ".join(remaining)
            mf.write(f'\t\t{stage}) echo "Valid stage: {stage}"; '
                     f'echo "Will retrace: {remaining_str}"; '
                     f'$(MAKE) retrace-stages STAGES="{remaining_str}" ;; \\\n')
        mf.write(f'\t\t*) echo "Unknown node: $(NODE)";'
                 f' echo "Available stages: {stages_str}"; exit 1 ;; \\\n')
        mf.write('\tesac\n')
        mf.write("\n")

        # Retrace specific stages
        mf.write("# Remove stamps for specific stages\n")
        mf.write(".PHONY: retrace-stages\n")
        mf.write("retrace-stages:\n")
        mf.write('\t@if [ -z "$(STAGES)" ]; then \\\n')
        mf.write('\t\techo "Error: STAGES not specified"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@echo "Removing stamps for stages: $(STAGES)"\n')
        mf.write('\t@for stage in $(STAGES); do \\\n')
        mf.write('\t\tif [ -f "$(STAMP_DIR)/$$stage.stamp" ]; then \\\n')
        mf.write('\t\t\techo "  Removing: $(STAMP_DIR)/$$stage.stamp"; \\\n')
        mf.write('\t\t\trm -f "$(STAMP_DIR)/$$stage.stamp"; \\\n')
        mf.write('\t\telse \\\n')
        mf.write('\t\t\techo "  No stamp found for stage: $$stage"; \\\n')
        mf.write('\t\tfi; \\\n')
        mf.write('\tdone\n')
        mf.write('\t@if [ -f ".run.status" ]; then \\\n')
        mf.write('\t\techo "  Updating run status file..."; \\\n')
        mf.write('\t\tgrep -v "$(STAGES)" .run.status > .run.status.tmp || true; \\\n')
        mf.write('\t\tmv .run.status.tmp .run.status; \\\n')
        mf.write('\tfi\n')
        mf.write('\t@echo "done Selective retrace completed"\n')
        mf.write("\n")

    # ── Generate Makefile Target ──────────────────────────────────────────────

    def _write_generate_makefile_target(self, mf) -> None:
        """Write the Makefile regeneration target."""
        mf.write(f"# {'=' * 79}\n")
        mf.write("# MAKEFILE REGENERATION TARGET\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        mf.write("# Regenerate Makefile in current run directory\n")
        mf.write(".PHONY: generate_makefile\n")
        mf.write("generate_makefile:\n")
        mf.write(f'\t@echo "Regenerating Makefile for {self.flow_type} flow..."\n')
        mf.write('\t@echo "Using generation script:'
                 ' $(FLOW_DIR)/utils/generation/$(GENERATION_VERSION)/gen_run_makefile.tcl"\n')
        mf.write('\t@if [ -f ".run.cbflow.tcl" ] || [ -f ".config.tcl" ]'
                 ' || [ -f "user_config_fp_test.tcl" ]; then \\\n')
        mf.write('\t\tif [ -f ".run.cbflow.tcl" ]; then \\\n')
        mf.write('\t\t\techo "Found CBFlow environment file: .run.cbflow.tcl"; \\\n')
        mf.write('\t\telif [ -f ".config.tcl" ]; then \\\n')
        mf.write('\t\t\techo "Found config file: .config.tcl"; \\\n')
        mf.write('\t\telse \\\n')
        mf.write('\t\t\techo "Found user config file: user_config_fp_test.tcl"; \\\n')
        mf.write('\t\tfi; \\\n')
        mf.write('\t\ttclsh "$(FLOW_DIR)/utils/generation/$(GENERATION_VERSION)/'
                 'gen_run_makefile.tcl"; \\\n')
        mf.write('\t\techo "done Makefile regenerated successfully"; \\\n')
        mf.write('\telse \\\n')
        mf.write('\t\techo "ERROR: No CBFlow configuration file found'
                 ' in current directory"; \\\n')
        mf.write('\t\techo "Expected files: .run.cbflow.tcl, .config.tcl,'
                 ' or user config files"; \\\n')
        mf.write('\t\techo "Please run from a CBFlow run directory'
                 ' or ensure config is present"; \\\n')
        mf.write('\t\texit 1; \\\n')
        mf.write('\tfi\n')
        mf.write("\n")

    # ═══════════════════════════════════════════════════════════════════════════
    # FLOW-SPECIFIC TARGETS
    # ═══════════════════════════════════════════════════════════════════════════

    def _write_flow_specific_targets(self, mf) -> None:
        """Write flow-specific targets and the clean target."""
        mf.write(f"# {'=' * 79}\n")
        mf.write(f"# {self.flow_type}-SPECIFIC TARGETS\n")
        mf.write(f"# {'=' * 79}\n")
        mf.write("\n")

        ft = self.flow_type
        tool_ver_ref = f"$({self.tool_version_var})"

        if ft == "PNR":
            self._write_pnr_specific_targets(mf, tool_ver_ref)
        elif ft == "SYNTH":
            self._write_synth_specific_targets(mf, tool_ver_ref)

        # Clean target (common to all flows)
        mf.write(f"# Clean {self.flow_type} results\n")
        mf.write(".PHONY: clean\n")
        mf.write("clean:\n")
        mf.write(f'\t@echo "Cleaning {self.flow_type} files..."\n')
        mf.write('\t@rm -rf $(WORK_DIR) $(LOGS_DIR) $(STAMP_DIR) .make\n')
        mf.write('\t@rm -f Makefile\n')
        mf.write('\t@echo "done Clean completed"\n')
        mf.write("\n")

    def _write_pnr_specific_targets(self, mf, tool_ver_ref: str) -> None:
        """Write PNR-specific extra targets."""
        mf.write("# Run timing analysis\n")
        mf.write(".PHONY: timing\n")
        mf.write("timing:\n")
        mf.write('\t@echo "Running timing analysis..."\n')
        mf.write(f'\t@tclsh "$(FLOW_DIR)/cmds/PNR/{self.vendor}/{self.tool_name}/'
                 f'{tool_ver_ref}/timing_analysis.tcl"\n')
        mf.write("\n")

        mf.write("# Run power analysis\n")
        mf.write(".PHONY: power\n")
        mf.write("power:\n")
        mf.write('\t@echo "Running power analysis..."\n')
        mf.write(f'\t@tclsh "$(FLOW_DIR)/cmds/PNR/{self.vendor}/{self.tool_name}/'
                 f'{tool_ver_ref}/power_analysis.tcl"\n')
        mf.write("\n")

        mf.write("# Run DRC check\n")
        mf.write(".PHONY: drc\n")
        mf.write("drc:\n")
        mf.write('\t@echo "Running DRC check..."\n')
        mf.write(f'\t@tclsh "$(FLOW_DIR)/cmds/PNR/{self.vendor}/{self.tool_name}/'
                 f'{tool_ver_ref}/drc_check.tcl"\n')
        mf.write("\n")

    def _write_synth_specific_targets(self, mf, tool_ver_ref: str) -> None:
        """Write SYNTH-specific extra targets."""
        mf.write("# Check RTL quality\n")
        mf.write(".PHONY: check_rtl\n")
        mf.write("check_rtl:\n")
        mf.write('\t@echo "Running RTL quality check..."\n')
        mf.write(f'\t@tclsh "$(FLOW_DIR)/cmds/SYNTH/{self.vendor}/{self.tool_name}/'
                 f'{tool_ver_ref}/check_rtl.tcl"\n')
        mf.write("\n")

        mf.write("# Show QoR summary\n")
        mf.write(".PHONY: qor\n")
        mf.write("qor:\n")
        mf.write('\t@echo "Generating QoR summary..."\n')
        mf.write(f'\t@tclsh "$(FLOW_DIR)/cmds/SYNTH/{self.vendor}/{self.tool_name}/'
                 f'{tool_ver_ref}/qor_summary.tcl"\n')
        mf.write("\n")

    # ═══════════════════════════════════════════════════════════════════════════
    # PER-STAGE .MK FILE GENERATION
    # ═══════════════════════════════════════════════════════════════════════════

    def _generate_stage_makefiles(self) -> None:
        """Create the .make/ directory and write individual stage .mk files."""
        make_dir = os.path.join(self.run_dir, '.make')
        os.makedirs(make_dir, exist_ok=True)

        for stage in self.stages:
            meta = self.stage_meta.get(stage, {})
            if self.merged:
                # Get subnodes from the original flow config
                original_stage = meta.get('original_stage', stage)
                original_flow = meta.get('flow', self.flow_type)
                subnodes = get_subnodes(original_flow, original_stage)
            else:
                subnodes = get_subnodes(self.flow_type, stage)
            self._write_stage_mk(stage, subnodes)

    def _write_stage_mk(self, stage: str, subnodes: List[str]) -> None:
        """Write a single .make/{stage}.mk file."""
        mk_path = os.path.join(self.run_dir, '.make', f'{stage}.mk')
        meta = self.stage_meta.get(stage, {})

        if self.merged:
            # Use per-stage tool info for merged flows
            tool_info = meta.get('tool_info', self.tool_info)
            flow = meta.get('flow', self.flow_type)
            vendor = tool_info.get('vendor', '')
            tool_name = tool_info.get('name', '')
            prefix = meta.get('prefix', '')
            tool_ver_var = self._tool_version_vars.get(prefix, self.tool_version_var)
            tool_ver_ref = f"$({tool_ver_var})"
            tool_path = f"{flow}/{vendor}/{tool_name}/{tool_ver_ref}"
            original_stage = meta.get('original_stage', stage)
            # Handler script name is based on original stage name (strip suffix)
            import re
            handler_base = re.sub(r'\d+$', '', original_stage)
        else:
            tool_ver_ref = f"$({self.tool_version_var})"
            tool_path = f"{self.flow_type}/{self.vendor}/{self.tool_name}/{tool_ver_ref}"
            flow = self.flow_type
            # Strip numeric suffix from stage name to get handler base name
            import re as _re
            handler_base = _re.sub(r'\d+$', '', stage)

        with open(mk_path, 'w') as mk:
            mk.write(f"# CBFlow {flow} {stage} Stage Makefile\n")
            mk.write(f"# Auto-generated for {self.flow_type} flow\n")
            mk.write("\n")

            if subnodes:
                self._write_subnode_stage(mk, stage, subnodes, tool_path, handler_base)
            else:
                self._write_simple_stage(mk, stage, tool_path)

    # ── Stage with subnodes ───────────────────────────────────────────────────

    def _write_subnode_stage(self, mk, stage: str, subnodes: List[str],
                             tool_path: str, handler_base: str = None) -> None:
        """Write a stage .mk file that has subnodes."""
        stage_upper = stage.upper()
        subnodes_str = ", ".join(subnodes)

        mk.write(f"# {stage} stage with subnodes: {subnodes_str}\n")
        mk.write("\n")

        # Subnode stamp variables
        for subnode in subnodes:
            subnode_upper = subnode.upper()
            mk.write(f"{stage_upper}_{subnode_upper}_STAMP"
                     f" = $(STAMP_DIR)/{stage}_{subnode}.stamp\n")
        mk.write("\n")

        # .PHONY stage target
        mk.write(f".PHONY: {stage}\n")
        mk.write(f"{stage}: $({stage_upper}_STAMP)\n")
        mk.write("\n")

        # Stage stamp rule -- depends on subnode stamps
        # For inputs stages: depends on ALL subnode stamps
        # For other stages: depends on LAST subnode stamp (finish)
        if self._is_inputs_stage(stage):
            all_stamps = " ".join(
                f"$({stage_upper}_{sn.upper()}_STAMP)" for sn in subnodes
            )
            mk.write(f"$({stage_upper}_STAMP): {all_stamps}\n")
        else:
            last_subnode = subnodes[-1]
            mk.write(f"$({stage_upper}_STAMP):"
                     f" $({stage_upper}_{last_subnode.upper()}_STAMP)\n")

        mk.write(f'\t@echo "done {stage} stage completed"\n')
        mk.write("\t@touch $@\n")
        mk.write("\n")

        # Determine stage dependency (previous stage stamp for first subnode)
        prev_stage_dep = self._get_stage_dependency(stage)

        # Individual subnode targets
        for subnode in subnodes:
            self._write_subnode_target(mk, stage, subnode, subnodes,
                                       tool_path, prev_stage_dep, handler_base)

    def _write_subnode_target(self, mk, stage: str, subnode: str,
                              subnodes: List[str], tool_path: str,
                              prev_stage_dep: str, handler_base: str = None) -> None:
        """Write a single subnode target rule."""
        stage_upper = stage.upper()
        subnode_upper = subnode.upper()

        # Build dependency list
        deps = []

        # First subnode gets dependency on the previous stage stamp
        first_subnode = subnodes[0]
        if subnode == first_subnode and prev_stage_dep:
            deps.append(prev_stage_dep)

        # Subnode-level dependencies (from config)
        subnode_deps = self._get_subnode_dependencies(stage, subnode)
        for dep in subnode_deps:
            dep_upper = dep.upper()
            deps.append(f"$({stage_upper}_{dep_upper}_STAMP)")

        dep_str = " ".join(deps)

        # For merged flows, the handler script uses the ORIGINAL stage name
        # e.g., synth_inputs → SYNTH/.../inputs_subnode_handler.tcl
        script_stage = handler_base if handler_base else stage

        mk.write(f"# {stage} {subnode} subnode\n")
        mk.write(f"$({stage_upper}_{subnode_upper}_STAMP): {dep_str}\n")
        mk.write(f'\t@echo "Running {stage} {subnode}..."\n')
        mk.write("\t@mkdir -p $(STAMP_DIR) $(LOGS_DIR)\n")
        mk.write(f'\t@tclsh "$(FLOW_DIR)/cmds/{tool_path}/'
                 f'{script_stage}_subnode_handler.tcl" {subnode} "$(PWD)" {stage}\n')
        mk.write(f'\t@echo "done {stage} {subnode} completed"\n')
        mk.write("\t@touch $@\n")
        mk.write("\n")

    # ── Simple stage (no subnodes) ────────────────────────────────────────────

    def _write_simple_stage(self, mk, stage: str, tool_path: str) -> None:
        """Write a simple stage .mk file (no subnodes)."""
        stage_upper = stage.upper()

        # Determine dependency on previous stage
        prev_dep = self._get_stage_dependency(stage)
        dep_str = prev_dep if prev_dep else ""

        mk.write(f"# {stage} stage (simple)\n")
        mk.write(f".PHONY: {stage}\n")
        mk.write(f"{stage}: $({stage_upper}_STAMP)\n")
        mk.write("\n")

        mk.write(f"$({stage_upper}_STAMP): {dep_str}\n")
        mk.write(f'\t@echo "Running {stage}..."\n')
        mk.write("\t@mkdir -p $(STAMP_DIR) $(LOGS_DIR)\n")
        mk.write(f'\t@tclsh "$(FLOW_DIR)/cmds/{tool_path}/{stage}.tcl" "$(PWD)"\n')
        mk.write(f'\t@echo "done {stage} completed"\n')
        mk.write("\t@touch $@\n")
        mk.write("\n")

    # ═══════════════════════════════════════════════════════════════════════════
    # DEPENDENCY RESOLUTION HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def _is_inputs_stage(self, stage: str) -> bool:
        """Check if a stage is an 'inputs'-type stage.

        The inputs stage has its completion stamp depend on ALL subnode stamps
        (since input subnodes like netlist, sdc, def, etc. are independent).
        Other stages use sequential dependencies where the stage stamp depends
        only on the last subnode (finish).
        """
        if self.merged:
            # For merged: synth_inputs, fp_inputs, pnr_inputs
            meta = self.stage_meta.get(stage, {})
            original = meta.get('original_stage', stage)
            base = re.sub(r'\d+$', '', original)
            return base == 'inputs'

        # Check node_types config first
        node_type = self.node_config.get(f'node_types,{stage}', '')
        if node_type:
            return _parse_tcl_string(node_type) == 'inputs'
        # Fallback: check stage name
        base = re.sub(r'\d+$', '', stage)
        return base == 'inputs'

    def _get_stage_dependency(self, stage: str) -> str:
        """Get the Make dependency string for a stage's first subnode.

        For merged flows, uses the cross-flow dependency from stage_meta.
        For single flows, looks up from node_config.
        """
        if self.merged:
            meta = self.stage_meta.get(stage, {})
            dep = meta.get('dependency', '')
            if dep:
                return f"$({dep.upper()}_STAMP)"
            return ""

        # Single flow: look up from node_config
        dep_key = f'dependencies,{stage}'
        raw = self.node_config.get(dep_key, '')
        if not raw:
            base = re.sub(r'\d+$', '', stage)
            if base != stage:
                raw = self.node_config.get(f'dependencies,{base}', '')

        if raw:
            dep_stages = _parse_tcl_list(raw)
            if dep_stages:
                dep_stamps = []
                for ds in dep_stages:
                    dep_stamps.append(f"$({ds.upper()}_STAMP)")
                return " ".join(dep_stamps)
        return ""

    def _get_subnode_dependencies(self, stage: str, subnode: str) -> List[str]:
        """Get the list of subnode dependencies from config.

        For merged flows, loads from the original flow's node config.
        """
        if self.merged:
            meta = self.stage_meta.get(stage, {})
            original_stage = meta.get('original_stage', stage)
            original_flow = meta.get('flow', self.flow_type)
            node_config = _load_node_config(original_flow)
            key = f'subnode_dependencies,{original_stage},{subnode}'
            raw = node_config.get(key, '')
            if not raw:
                base = re.sub(r'\d+$', '', original_stage)
                if base != original_stage:
                    raw = node_config.get(f'subnode_dependencies,{base},{subnode}', '')
            if raw:
                return _parse_tcl_list(raw)
            return []

        # Single flow
        key = f'subnode_dependencies,{stage},{subnode}'
        raw = self.node_config.get(key, '')
        if not raw:
            base = re.sub(r'\d+$', '', stage)
            if base != stage:
                raw = self.node_config.get(f'subnode_dependencies,{base},{subnode}', '')
        if raw:
            return _parse_tcl_list(raw)
        return []


# ═══════════════════════════════════════════════════════════════════════════════
# CONVENIENCE FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════

def generate_makefile(flow_type: str, env_vars: Dict[str, str],
                      run_dir: str) -> bool:
    """Generate a Makefile for a CBFlow run.

    This is the main entry point, matching the interface of the old
    gen_run_makefile.tcl system.

    Args:
        flow_type: Flow type (e.g. 'FP', 'PNR', 'SYNTH', 'STA', etc.)
        env_vars:  Merged environment variables.
        run_dir:   Absolute path to the run directory.

    Returns:
        True on success, False on failure.
    """
    generator = MakefileGenerator(flow_type, env_vars, run_dir)
    return generator.generate()


# ═══════════════════════════════════════════════════════════════════════════════
# CLI ENTRY POINT (for testing / standalone use)
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    import sys

    if len(sys.argv) < 2:
        print("Usage: python makefile_generator.py <FLOW_TYPE> [run_dir]")
        print("  FLOW_TYPE: SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP")
        sys.exit(1)

    flow = sys.argv[1].upper()
    run_dir = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()

    # Gather environment variables
    env = dict(os.environ)

    print(f"Generating Makefile for {flow} flow in {run_dir}...")
    success = generate_makefile(flow, env, run_dir)
    if success:
        print(f"Makefile generated successfully in {run_dir}")
    else:
        print("Makefile generation failed", file=sys.stderr)
        sys.exit(1)
