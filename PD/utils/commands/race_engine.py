#!/usr/bin/env python3
"""
RACE — Python-native DAG executor replacing GNU Make.

Features:
  - DAG built from node_configs (stages, subnodes, dependencies)
  - SQLite status tracking (job history, runtime, exit codes, LSF job IDs)
  - Smart retrace (invalidate + downstream propagation)
  - Parallel-ready dispatch (independent subnodes)
  - 4 launch modes: local, xterm, LSF batch, LSF+xterm
  - Error halt with structured reporting
  - SQLite-only status tracking (no .stamps files)

Usage:
  engine = RaceEngine(run_dir, flow_type, env_vars)
  engine.initialize()
  engine.execute('all')                     # Run complete flow
  engine.execute('place1')                  # Run single stage
  engine.retrace(from_stage='cts1')         # Smart retrace
  engine.status()                           # Query status
"""

import os
import re
import sys
import json
import time
import socket
import sqlite3
import subprocess
import signal
from pathlib import Path
from datetime import datetime

import logging
logger = logging.getLogger('cbflow.engine')


# ═══════════════════════════════════════════════════════════════════════════════
# DAG NODE
# ═══════════════════════════════════════════════════════════════════════════════

class Job:
    """A single executable unit — corresponds to a subnode handler invocation."""

    READY = 'READY'
    PENDING = 'PENDING'
    RUNNING = 'RUNNING'
    DONE = 'DONE'
    FAIL = 'FAIL'
    INVALIDATED = 'INVALIDATED'
    BYPASSED = 'BYPASSED'
    FORCE_VALIDATED = 'FORCE_VALIDATED'

    def __init__(self, name: str, stage: str, subnode: str, command: str,
                 job_type: str = 'subnode', resource_tier: str = 'S'):
        self.name = name              # e.g., "synthesis1_run"
        self.stage = stage            # e.g., "synthesis1"
        self.subnode = subnode        # e.g., "run"
        self.command = command        # tclsh handler.tcl subnode pwd stage
        self.job_type = job_type      # 'subnode' or 'stage' (sentinel)
        self.resource_tier = resource_tier
        self.deps = []                # list of Job names this depends on
        self.status = Job.READY
        self.start_time = None
        self.end_time = None
        self.exit_code = None
        self.lsf_job_id = None
        self.pid = None

    COMPLETED_STATES = frozenset(('DONE', 'BYPASSED', 'FORCE_VALIDATED'))

    @property
    def is_completed(self):
        return self.status in Job.COMPLETED_STATES

    def is_ready(self, completed_jobs: set) -> bool:
        """True if all dependencies are satisfied."""
        if self.status not in (Job.READY, Job.INVALIDATED):
            return False
        return all(dep in completed_jobs for dep in self.deps)


# ═══════════════════════════════════════════════════════════════════════════════
# DAG BUILDER
# ═══════════════════════════════════════════════════════════════════════════════

class DagBuilder:
    """Builds job DAG from node_config.tcl files."""

    def __init__(self, run_dir: str, flow_type: str, env_vars: dict):
        self.run_dir = run_dir
        self.flow_type = flow_type
        self.env_vars = env_vars

    def build(self) -> tuple:
        """Returns (jobs_dict, stage_order) where jobs_dict maps name→Job.

        Merges two sources:
          1. Base stages from node_config.tcl (flow-level, never changes)
          2. Custom nodes from $run_dir/setup/runtime_flow_config.tcl (run-level)
        """
        cfg = self._resolve_config()
        if not cfg:
            return {}, []
        self._resolved_cfg = cfg  # stored for _resolve_dynamic_subnodes

        stages = cfg.get('stages', '').split()
        if not stages:
            logger.error("No stages found in config")
            return {}, []

        stage_deps = {}
        subnodes = {}
        for stage in stages:
            stage_deps[stage] = cfg.get(f'dependencies,{stage}', '').split()
            subs_str = cfg.get(f'subnodes,{stage}', '')
            if subs_str:
                subs = subs_str.split()
                if subs == ['dynamic']:
                    subs = self._resolve_dynamic_subnodes(stage)
                subnodes[stage] = subs

        # Store node_types and tool_info from resolved config
        self._node_types = {}
        for stage in stages:
            nt = cfg.get(f'node_types,{stage}', '')
            if nt:
                self._node_types[stage] = nt

        self._tool_info = {
            'vendor': cfg.get('tool,vendor', ''),
            'name': cfg.get('tool,name', ''),
            'version': cfg.get('tool,version', ''),
        }
        # Re-resolve vendor when user overrode tool,name (vendor may be stale from default tool)
        default_tool = cfg.get('default_tool', '')
        if (self._tool_info['name'] and default_tool
                and self._tool_info['name'] != default_tool):
            import re as _re
            flow_dir = self.env_vars.get('FLOW_DIR', '')
            cfg_ver = self.env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
            tool_cfg = os.path.join(flow_dir, 'config', 'flow', cfg_ver,
                                    'node_configs', '{}_{}_config.tcl'.format(
                                        self.flow_type, self._tool_info['name']))
            if os.path.isfile(tool_cfg):
                with open(tool_cfg, 'r') as _tcf:
                    for _line in _tcf:
                        _m = _re.search(r'tool,vendor["\s]+["\s]*([^"}\s]+)', _line)
                        if _m:
                            self._tool_info['vendor'] = _m.group(1)
                            logger.info("Auto-resolved vendor from %s: %s",
                                       os.path.basename(tool_cfg), self._tool_info['vendor'])
                            break

        if not self._tool_info['vendor'] or not self._tool_info['name']:
            logger.error("tool,vendor and tool,name must be set in config — "
                         "no defaults. Check flow_config.tcl or user_config.tcl.")
            raise ValueError("Missing required config: tool,vendor and tool,name")

        resource_map = self._parse_resource_map(self._load_node_config(), stages)

        # Merge custom nodes from run-level runtime config
        custom_nodes, custom_deps = self._load_runtime_custom_nodes()
        self._custom_node_types = {}  # custom node name → base handler name
        for name, info in custom_nodes.items():
            if name not in stages:
                dep = info.get('dependency', '')
                if dep and dep in stages:
                    idx = stages.index(dep) + 1
                    stages.insert(idx, name)
                else:
                    stages.append(name)
                stage_deps[name] = [dep] if dep else []
                resource_map[name] = info.get('resource_tier', 'M')

                # Resolve subnodes: find base node type, inherit its subnodes
                node_type = info.get('type', '')
                type_base = re.sub(r'\d+$', '', node_type) if node_type else ''
                if node_type:
                    self._custom_node_types[name] = type_base

                # Derive dynamic types from config (stages with subnodes = {dynamic})
                dynamic_types = set()
                for k, v in cfg.items():
                    if k.startswith('subnodes,') and v.strip() == 'dynamic':
                        # Extract stage base type (e.g., timing1 → timing)
                        stage_name = k.split(',')[1]
                        stage_type = cfg.get(f'stages,{stage_name},type', stage_name.rstrip('0123456789'))
                        dynamic_types.add(stage_type)
                if type_base in dynamic_types:
                    # Always resolve independently — each node gets its own scenarios
                    subnodes[name] = self._resolve_dynamic_subnodes(name)
                else:
                    # Non-dynamic: inherit subnodes from base node of same type
                    base_subs = None
                    for existing in stages:
                        if existing != name and existing.rstrip('0123456789') == type_base:
                            base_subs = subnodes.get(existing)
                            break
                    if base_subs:
                        subnodes[name] = list(base_subs)
                    else:
                        # No base node found — read from resolved config
                        subs_str = cfg.get(f'subnodes,{name}', '')
                    if subs_str:
                        subs = subs_str.split()
                        if subs == ['dynamic']:
                            subnodes[name] = self._resolve_dynamic_subnodes(name)
                        else:
                            subnodes[name] = subs
                    else:
                        # Read subnodes from config, fallback to standard pattern
                        configured_subs = cfg.get(f'subnodes,{name}', '').strip()
                        if configured_subs and configured_subs != 'dynamic':
                            subnodes[name] = configured_subs.split()
                        else:
                            # Stage type from config determines subnodes
                            st = cfg.get(f'stage_types,{name}', '')
                            if st in ('execution', 'export_data', 'release_data'):
                                subnodes[name] = ['setup', 'run', 'validate', 'finish']

                logger.info(f"Custom node: {name} (type={node_type}, dep={dep}, subs={subnodes.get(name, [])})")

        # Parse subnode-level dependencies from resolved config
        sub_deps = {}
        for stage in stages:
            for sn in subnodes.get(stage, []):
                dep_key = f'subnode_dependencies,{stage},{sn}'
                if dep_key in cfg and cfg[dep_key]:
                    sub_deps[f'{stage}_{sn}'] = [f'{stage}_{d}' for d in cfg[dep_key].split()]

        # Auto-generate parallel deps for dynamic subnodes (MMMC scenarios)
        # Pattern: setup has no deps, each scenario depends on setup,
        #          validate depends on all scenarios, finish depends on validate
        for stage in stages:
            stage_subs = subnodes.get(stage, [])
            if len(stage_subs) > 4 and 'setup' in stage_subs and 'validate' in stage_subs:
                # Check if this stage already has subnode_deps defined
                has_deps = any(f'{stage}_{sn}' in sub_deps for sn in stage_subs)
                if not has_deps:
                    scenarios = [s for s in stage_subs if s not in ('setup', 'validate', 'finish')]
                    if scenarios:
                        sub_deps[f'{stage}_setup'] = []
                        for sc in scenarios:
                            sub_deps[f'{stage}_{sc}'] = [f'{stage}_setup']
                        sub_deps[f'{stage}_validate'] = [f'{stage}_{sc}' for sc in scenarios]
                        sub_deps[f'{stage}_finish'] = [f'{stage}_validate']

        jobs = {}
        stage_order = stages

        for stage in stages:
            stage_subnodes = subnodes.get(stage, [])
            stage_dep_jobs = stage_deps.get(stage, [])

            # Leaf node — no subnodes, stage executes directly
            if not stage_subnodes:
                # Extract the input type from stage name (rtl1 → rtl)
                input_type = stage.rstrip('0123456789')
                cmd = self._build_command(stage, input_type)
                tier = resource_map.get(stage, 'S')
                job = Job(stage, stage, input_type, cmd,
                          job_type='stage', resource_tier=tier)
                for dep_stage in stage_dep_jobs:
                    job.deps.append(dep_stage)
                jobs[stage] = job
                continue

            # Stage with subnodes — standard processing
            prev_subnode_name = None
            has_subnode_deps = any(f'{stage}_{sn}' in sub_deps for sn in stage_subnodes)

            for subnode in stage_subnodes:
                job_name = f'{stage}_{subnode}'
                cmd = self._build_command(stage, subnode)
                tier = resource_map.get(stage, 'M')

                job = Job(job_name, stage, subnode, cmd,
                          job_type='subnode', resource_tier=tier)

                if has_subnode_deps and job_name in sub_deps:
                    for dep in sub_deps[job_name]:
                        job.deps.append(dep)
                    if not job.deps:
                        for dep_stage in stage_dep_jobs:
                            job.deps.append(dep_stage)
                else:
                    if prev_subnode_name is None:
                        for dep_stage in stage_dep_jobs:
                            job.deps.append(dep_stage)
                    else:
                        job.deps.append(prev_subnode_name)

                jobs[job_name] = job
                prev_subnode_name = job_name

            # Stage sentinel job (marks stage complete in DB)
            sentinel = Job(stage, stage, '_sentinel', '',
                           job_type='stage', resource_tier='S')
            if has_subnode_deps:
                for sn in stage_subnodes:
                    sentinel.deps.append(f'{stage}_{sn}')
            elif prev_subnode_name:
                sentinel.deps.append(prev_subnode_name)
            jobs[stage] = sentinel

        return jobs, stage_order

    def _resolve_config(self) -> dict:
        """Execute node config via tclsh and capture resolved variables.

        Returns dict of key→value from TCL-resolved config.
        No regex parsing — TCL foreach loops, variable substitution all work.
        """
        flow_dir = self.env_vars.get('FLOW_DIR', '')
        resolver = os.path.join(flow_dir, 'utils', 'commands', 'config_resolver.tcl')
        if not os.path.exists(resolver):
            logger.error(f"Config resolver not found: {resolver}")
            return {}

        try:
            result = subprocess.run(
                ['tclsh', resolver, self.flow_type, self.run_dir],
                capture_output=True, text=True, timeout=30,
                env={**os.environ, **{k: v for k, v in self.env_vars.items() if v}}
            )
            if result.returncode != 0:
                logger.error(f"Config resolver failed: {result.stderr.strip()}")
                return {}

            cfg = {}
            for line in result.stdout.splitlines():
                if line.startswith('CBFLOW_CFG:'):
                    kv = line[len('CBFLOW_CFG:'):]
                    eq = kv.find('=')
                    if eq > 0:
                        cfg[kv[:eq]] = kv[eq+1:]
            return cfg

        except subprocess.TimeoutExpired:
            logger.error("Config resolver timed out (30s)")
            return {}
        except Exception as e:
            logger.error(f"Config resolver error: {e}")
            return {}

    def _load_node_config(self) -> str:
        """Load node config TCL file content (for resource_map regex parsing)."""
        config_root = self.env_vars.get('CONFIG_ROOT',
                      self.env_vars.get('FLOW_DIR', ''))
        flow_version = self.env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
        config_path = os.path.join(config_root, 'config', 'flow', flow_version,
                                   'node_configs', f'{self.flow_type}_config.tcl')
        if not os.path.exists(config_path):
            config_path = os.path.join(self.env_vars.get('FLOW_DIR', ''),
                                       'config', 'flow', flow_version,
                                       'node_configs', f'{self.flow_type}_config.tcl')
        if os.path.exists(config_path):
            with open(config_path) as f:
                return f.read()
        return ""

    def _resolve_dynamic_subnodes(self, stage: str) -> list:
        """Resolve dynamic subnodes for per-scenario/per-corner stages.

        Uses resolved config from _resolve_config() — no regex on file text.
        Extraction stages → per-RC-corner (from rc_corner_list)
        Timing stages     → per-MMMC-scenario (from user_config or scenario sets)
        """
        cfg = self._resolved_cfg
        stage_base = re.sub(r'\d+(_\w+)?$', '', stage)

        # ── Extraction stages: dynamic per RC corner ──
        if stage_base == 'extraction':
            # From resolved config (rc_corner_list set by mmmc_config via [lsort [array names rc_corners]])
            rc_list = cfg.get('rc_corner_list', '')
            if rc_list:
                corners = rc_list.split()
                return ['setup'] + corners + ['validate', 'finish']
            logger.error(f"No rc_corner_list found for dynamic extraction stage {stage}")
            return []

        # ── Timing/other stages: dynamic per MMMC scenario ──
        flow_array = self.flow_type.lower()
        scenarios = []

        # Priority 1: Per-node override — setup/override_config.<stage>.tcl
        override_file = os.path.join(self.run_dir, 'setup', f'override_config.{stage}.tcl')
        if os.path.exists(override_file):
            with open(override_file) as f:
                for line in f:
                    m = re.match(rf'set\s+{flow_array}\(mmmc,\w+_scenarios\)\s+"([^"]+)"', line.strip())
                    if m:
                        for s in m.group(1).split():
                            if s not in scenarios:
                                scenarios.append(s)

        # Priority 2: Generic scenarios in user_config — sta(mmmc,setup_scenarios)
        if not scenarios:
            user_config = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
            if os.path.exists(user_config):
                with open(user_config) as f:
                    for line in f:
                        m = re.match(rf'set\s+{flow_array}\(mmmc,\w+_scenarios\)\s+"([^"]+)"', line.strip())
                        if m:
                            for s in m.group(1).split():
                                if s not in scenarios:
                                    scenarios.append(s)

        # Priority 3: scenario set from node config
        if not scenarios:
            scenario_set = cfg.get('mmmc,scenario_set', 'signoff')
            set_scenarios = cfg.get(f'mmmc_scenario_set,{scenario_set}', '')
            if set_scenarios:
                scenarios = set_scenarios.split()

        if scenarios:
            return ['setup'] + scenarios + ['validate', 'finish']

        logger.error(f"No MMMC scenarios resolved for dynamic stage {stage}")
        return []

    def _load_runtime_custom_nodes(self) -> tuple:
        """Load custom nodes from $run_dir/setup/runtime_flow_config.tcl.

        These are added at run-level by:
          cbflow run add-node --node place2 --type place --dep place1
          cbflow run create-branch --name eco_branch --from signoff1

        Returns: (custom_nodes_dict, custom_deps_dict)
        """
        custom_nodes = {}
        custom_deps = {}
        runtime_config = os.path.join(self.run_dir, 'setup', 'runtime_flow_config.tcl')
        if not os.path.exists(runtime_config):
            return custom_nodes, custom_deps

        try:
            with open(runtime_config) as f:
                content = f.read()

            # Parse two formats:
            # Format 1 (array set): stages,place2,type place
            # Format 2 (set):       synth_pnr(stages,place2,type) "place"
            node_names = set()

            # Format 1: inside array set block
            for m in re.finditer(r'stages,(\w+),(?:type|dependencies)', content):
                node_names.add(m.group(1))

            # Format 2: individual set commands
            flow_lower = self.flow_type.lower()
            for m in re.finditer(rf'{flow_lower}\(stages,(\w+),', content):
                node_names.add(m.group(1))

            for name in node_names:
                node_type = ''
                dep = ''
                branch = ''
                # Try format 1 (array set)
                m = re.search(rf'stages,{name},type\s+(\S+)', content)
                if m: node_type = m.group(1).strip('"')
                m = re.search(rf'stages,{name},dependencies\s+(\S+)', content)
                if m: dep = m.group(1).strip('"')
                m = re.search(rf'stages,{name},branch_key\s+(\S+)', content)
                if m: branch = m.group(1).strip('"')
                # Try format 2 (set command) — overrides if found
                m = re.search(rf'{flow_lower}\(stages,{name},type\)\s+"([^"]*)"', content)
                if m: node_type = m.group(1)
                m = re.search(rf'{flow_lower}\(stages,{name},dependencies\)\s+"([^"]*)"', content)
                if m: dep = m.group(1)
                m = re.search(rf'{flow_lower}\(stages,{name},branch_key\)\s+"([^"]*)"', content)
                if m: branch = m.group(1)

                custom_nodes[name] = {
                    'type': node_type,
                    'dependency': dep,
                    'branch_key': branch,
                }
                custom_deps[name] = [dep] if dep else []

        except Exception as e:
            logger.debug(f"Error loading runtime config: {e}")

        return custom_nodes, custom_deps

    def _parse_subnode_dependencies(self, config: str, stages: list, subnodes: dict) -> dict:
        """Parse subnode_dependencies from config for parallel subnode support."""
        sub_deps = {}
        for stage in stages:
            for subnode in subnodes.get(stage, []):
                key = f'subnode_dependencies,{stage},{subnode}'
                m = re.search(rf'{re.escape(key)}\s+\{{([^}}]*)\}}', config)
                if m:
                    dep_list = m.group(1).split()
                    sub_deps[f'{stage}_{subnode}'] = [f'{stage}_{d}' for d in dep_list]
        return sub_deps

    def _parse_resource_map(self, config: str, stages: list) -> dict:
        """Map stages to resource tiers from tool_launch_config."""
        resource_map = {}
        tlc_path = os.path.join(self.env_vars.get('FLOW_DIR', ''),
                                'config', 'flow',
                                self.env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0'),
                                'tool_launch_config.tcl')
        if os.path.exists(tlc_path):
            with open(tlc_path) as f:
                tlc = f.read()
            for stage in stages:
                stage_base = stage.rstrip('0123456789')
                flow_lower = self.flow_type.lower()
                pattern = rf'flow_mapping,{flow_lower},{stage_base}\)\s+"(\w+)"'
                m = re.search(pattern, tlc, re.IGNORECASE)
                if m:
                    resource_map[stage] = m.group(1)
        return resource_map

    def _build_command(self, stage: str, subnode: str) -> str:
        """Build the tclsh handler invocation command.
        Tool info and node_types set by _resolve_config() in build()."""
        flow_dir = self.env_vars.get('FLOW_DIR', '')

        tool_vendor = self._tool_info['vendor']
        tool_name = self._tool_info['name']
        tool_version = self._tool_info['version']

        # For custom nodes (e.g., synthesis2_xyz), use the stored base type
        custom_types = getattr(self, '_custom_node_types', {})
        handler_base = custom_types.get(stage) or self._node_types.get(stage, stage.rstrip('0123456789'))
        handler = os.path.join(flow_dir, 'cmds', self.flow_type,
                               tool_vendor, tool_name, tool_version,
                               f'{handler_base}_subnode_handler.tcl')

        return f'tclsh "{handler}" {subnode} "{self.run_dir}" {stage}'


# ═══════════════════════════════════════════════════════════════════════════════
# STATUS DATABASE
# ═══════════════════════════════════════════════════════════════════════════════

class StatusDB:
    """SQLite database for job status tracking.

    DB is stored in the RACE area: $project(race,db_path)/$project/$domain/$flow/<run>_<user>_<uid>.db
    Example: /proj/phoenix/race_db/phoenix/PD/SYNTH_PNR/P0_run_SYNTH_PNR_test1_vmerugu_a3f2b1.db

    A pointer file (.race_db_pointer) in the run_dir stores the absolute path
    to the DB in the race area — used by dashboard and other tools to locate it.

    UID is a 6-char hex derived from run_dir absolute path — unique per run,
    deterministic (same run_dir always produces same UID).

    Falls back to local $run_dir/.race_<name>.db only if race area not configured.
    """

    # Pointer file stored in run_dir that contains absolute path to DB
    DB_POINTER_FILE = '.race_db_pointer'

    def __init__(self, run_dir: str, project_name: str = '', domain: str = 'PD',
                 flow_type: str = '', run_name: str = '', user: str = '',
                 db_base_path: str = ''):
        import hashlib
        self.run_dir = run_dir
        # Generate deterministic 6-char UID from run_dir absolute path
        uid = hashlib.md5(os.path.abspath(run_dir).encode()).hexdigest()[:6]
        user = user or os.environ.get('USER', 'unknown')
        # Full run directory basename for human-readable DB identification
        run_dir_name = os.path.basename(os.path.abspath(run_dir))
        db_filename = f'{run_dir_name}_{user}_{uid}.db'

        # Priority 1: Check existing pointer file (for reconnect/resume)
        pointer_path = os.path.join(run_dir, self.DB_POINTER_FILE)
        if os.path.exists(pointer_path):
            try:
                with open(pointer_path) as f:
                    stored_path = f.read().strip()
                if stored_path and os.path.exists(stored_path):
                    self.db_path = stored_path
                    self._init_db()
                    return
            except (OSError, IOError):
                pass

        # Priority 2: Race area (from project config)
        if db_base_path:
            db_dir = os.path.join(db_base_path, project_name, domain, flow_type)
            os.makedirs(db_dir, exist_ok=True)
            self.db_path = os.path.join(db_dir, db_filename)
            # Write pointer file in run_dir for other tools to find the DB
            self._write_pointer(pointer_path, self.db_path)
        else:
            # Fallback: local DB (only if race area not configured)
            self.db_path = os.path.join(run_dir, f'.race_{db_filename}')

        # Backward compat: if old DB exists locally, use it (avoid losing state)
        old_path = os.path.join(run_dir, f'.race_{run_name}_{uid}.db') if run_name else ''
        if old_path and os.path.exists(old_path) and not os.path.exists(self.db_path):
            self.db_path = old_path

        self._init_db()

    @staticmethod
    def _write_pointer(pointer_path: str, db_path: str):
        """Write pointer file in run_dir with absolute path to DB."""
        try:
            with open(pointer_path, 'w') as f:
                f.write(os.path.abspath(db_path) + '\n')
        except (OSError, IOError):
            pass  # Non-critical — tools can still find DB via race area scan

    @staticmethod
    def find_db_from_run_dir(run_dir: str) -> str:
        """Find the RACE database for a run directory.

        Resolution order:
          1. .race_db_pointer file in run_dir (points to race area)
          2. Local .race_*.db files in run_dir (legacy fallback)
          3. None
        """
        # Check pointer file
        pointer_path = os.path.join(run_dir, StatusDB.DB_POINTER_FILE)
        if os.path.exists(pointer_path):
            try:
                with open(pointer_path) as f:
                    stored_path = f.read().strip()
                if stored_path and os.path.exists(stored_path):
                    return stored_path
            except (OSError, IOError):
                pass

        # Fallback: local DB files
        import glob as _glob
        matches = _glob.glob(os.path.join(run_dir, '.race_*.db'))
        if matches:
            return matches[0]

        return None

    def _init_db(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute('''CREATE TABLE IF NOT EXISTS jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_name TEXT NOT NULL,
            stage TEXT NOT NULL,
            subnode TEXT,
            job_type TEXT DEFAULT 'subnode',
            status TEXT DEFAULT 'READY',
            command TEXT,
            start_time TEXT,
            end_time TEXT,
            runtime_sec REAL,
            exit_code INTEGER,
            lsf_job_id TEXT,
            lsf_queue TEXT,
            resource_tier TEXT,
            pid INTEGER,
            hostname TEXT,
            cpu_used REAL,
            mem_peak_mb REAL,
            log_file TEXT,
            error_msg TEXT,
            retry_count INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now'))
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS run_info (
            key TEXT PRIMARY KEY,
            value TEXT
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS stage_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            stage TEXT NOT NULL,
            metric_name TEXT NOT NULL,
            metric_value TEXT,
            captured_at TEXT DEFAULT (datetime('now'))
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS job_order (
            seq INTEGER PRIMARY KEY,
            job_name TEXT NOT NULL UNIQUE,
            stage TEXT NOT NULL,
            subnode TEXT,
            job_type TEXT
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS run_config (
            key TEXT PRIMARY KEY,
            value TEXT
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS dag_structure (
            job_name TEXT PRIMARY KEY,
            stage TEXT,
            subnode TEXT,
            job_type TEXT,
            deps TEXT,
            branch_key TEXT,
            branch_name TEXT,
            node_type TEXT
        )''')

        # ── New tables: comprehensive data collection ─────────────────────
        conn.execute('''CREATE TABLE IF NOT EXISTS design_info (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TEXT DEFAULT (datetime('now'))
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS checklist_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            milestone TEXT NOT NULL,
            check_name TEXT NOT NULL,
            check_type TEXT,
            category TEXT,
            severity TEXT,
            status TEXT,
            metric_value TEXT,
            threshold TEXT,
            detail TEXT,
            report_file TEXT,
            phase TEXT,
            evaluated_at TEXT DEFAULT (datetime('now')),
            evaluated_by TEXT
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS release_info (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            release_tag TEXT NOT NULL,
            milestone TEXT,
            phase TEXT,
            release_dir TEXT,
            released_by TEXT,
            released_at TEXT DEFAULT (datetime('now')),
            description TEXT,
            status TEXT DEFAULT 'active',
            files_json TEXT,
            signoff_json TEXT
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS lsf_details (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_name TEXT NOT NULL,
            lsf_job_id TEXT,
            queue TEXT,
            resource_tier TEXT,
            requested_mem_mb INTEGER,
            requested_cpu INTEGER,
            requested_walltime TEXT,
            actual_mem_peak_mb REAL,
            actual_cpu_time_sec REAL,
            actual_walltime_sec REAL,
            exec_host TEXT,
            submit_time TEXT,
            start_time TEXT,
            end_time TEXT,
            exit_code INTEGER,
            exit_reason TEXT,
            cost_estimate REAL,
            submitted_at TEXT DEFAULT (datetime('now'))
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS run_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_name TEXT NOT NULL,
            stage TEXT,
            log_file TEXT,
            log_size_bytes INTEGER,
            error_count INTEGER DEFAULT 0,
            warning_count INTEGER DEFAULT 0,
            critical_errors TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS metrics_snapshot (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            stage TEXT NOT NULL,
            node_name TEXT,
            metric_category TEXT,
            metric_name TEXT NOT NULL,
            metric_value REAL,
            metric_unit TEXT,
            scenario TEXT,
            corner TEXT,
            captured_from TEXT,
            captured_at TEXT DEFAULT (datetime('now'))
        )''')
        conn.execute('''CREATE TABLE IF NOT EXISTS config_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            config_file TEXT,
            change_type TEXT,
            changed_by TEXT,
            changed_at TEXT DEFAULT (datetime('now')),
            content_hash TEXT,
            summary TEXT
        )''')
        conn.commit()
        conn.close()

    def record_pending(self, jobs: list):
        """Mark multiple jobs as PENDING in DB (batch insert)."""
        conn = sqlite3.connect(self.db_path)
        now = datetime.now().isoformat()
        for job in jobs:
            conn.execute(
                'INSERT INTO jobs (job_name, stage, subnode, job_type, status, command, '
                'start_time, resource_tier) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                (job.name, job.stage, job.subnode, job.job_type, Job.PENDING,
                 job.command, now, job.resource_tier))
        conn.commit()
        conn.close()

    def record_start(self, job: Job):
        conn = sqlite3.connect(self.db_path)
        now = datetime.now().isoformat()
        # Try to update existing PENDING row first
        cur = conn.execute(
            'UPDATE jobs SET status = ?, start_time = ? '
            'WHERE job_name = ? AND status = ?',
            (Job.RUNNING, now, job.name, Job.PENDING))
        if cur.rowcount == 0:
            # No PENDING row — insert fresh
            conn.execute(
                'INSERT INTO jobs (job_name, stage, subnode, job_type, status, command, '
                'start_time, resource_tier) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                (job.name, job.stage, job.subnode, job.job_type, Job.RUNNING,
                 job.command, now, job.resource_tier))
        conn.commit()
        conn.close()
        job.start_time = now
        job.status = Job.RUNNING

    def record_complete(self, job: Job, exit_code: int, error_msg: str = '', status_override: str = None):
        conn = sqlite3.connect(self.db_path)
        now = datetime.now().isoformat()
        status = status_override or (Job.DONE if exit_code == 0 else Job.FAIL)

        # Compute runtime
        runtime_sec = 0
        if job.start_time:
            try:
                t0 = datetime.fromisoformat(job.start_time)
                t1 = datetime.fromisoformat(now)
                runtime_sec = (t1 - t0).total_seconds()
            except Exception:
                pass

        hostname = socket.gethostname()

        conn.execute(
            'UPDATE jobs SET status = ?, end_time = ?, runtime_sec = ?, exit_code = ?, '
            'lsf_job_id = ?, pid = ?, hostname = ?, error_msg = ? '
            'WHERE job_name = ? AND status = ?',
            (status, now, runtime_sec, exit_code, job.lsf_job_id, job.pid,
             hostname, error_msg, job.name, Job.RUNNING))
        conn.commit()
        conn.close()
        job.end_time = now
        job.exit_code = exit_code
        job.status = status

    def reset_stale_jobs(self):
        """Reset stale RUNNING jobs back to READY on init.
        Only resets RUNNING (truly stale from crashes). Does NOT touch PENDING —
        those are legitimately queued by an active execute_jobs() in another thread."""
        conn = sqlite3.connect(self.db_path)
        # Only reset RUNNING (stale from crash/interrupt) — never PENDING
        conn.execute("UPDATE jobs SET status = ? WHERE status = ?",
                     (Job.READY, Job.RUNNING))
        conn.commit()
        conn.close()

    def record_ready(self, jobs: list):
        """Reset PENDING jobs back to READY in DB (after upstream failure)."""
        conn = sqlite3.connect(self.db_path)
        for job in jobs:
            conn.execute('UPDATE jobs SET status = ? WHERE job_name = ? AND status = ?',
                         (Job.READY, job.name, Job.PENDING))
        conn.commit()
        conn.close()

    def record_direct(self, job: Job, status: str):
        """Write a status directly to DB (for bypass/forcevalidate — no start/complete pair)."""
        conn = sqlite3.connect(self.db_path)
        now = datetime.now().isoformat()
        hostname = socket.gethostname()
        conn.execute(
            'INSERT INTO jobs (job_name, stage, subnode, job_type, status, command, '
            'start_time, end_time, runtime_sec, exit_code, hostname) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            (job.name, job.stage, job.subnode, job.job_type, status,
             job.command, now, now, 0, 0, hostname))
        conn.commit()
        conn.close()
        job.status = status

    def save_job_order(self, jobs: dict):
        """Save canonical DAG order to job_order table. Rebuilds every time."""
        conn = sqlite3.connect(self.db_path)
        conn.execute('DELETE FROM job_order')
        for seq, (name, job) in enumerate(jobs.items()):
            conn.execute(
                'INSERT OR REPLACE INTO job_order (seq, job_name, stage, subnode, job_type) '
                'VALUES (?, ?, ?, ?, ?)',
                (seq, job.name, job.stage, job.subnode, job.job_type))
        conn.commit()
        conn.close()

    def seed_missing_jobs(self, jobs: dict):
        """Insert READY rows for jobs not yet in DB (e.g., dynamically added nodes)."""
        conn = sqlite3.connect(self.db_path)
        existing = {row[0] for row in conn.execute('SELECT DISTINCT job_name FROM jobs')}
        now = datetime.now().isoformat()
        count = 0
        for name, job in jobs.items():
            if name not in existing:
                conn.execute(
                    'INSERT INTO jobs (job_name, stage, subnode, job_type, status, command, '
                    'resource_tier, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                    (job.name, job.stage, job.subnode, job.job_type, Job.READY,
                     job.command, job.resource_tier, now))
                count += 1
        if count > 0:
            conn.commit()
        conn.close()
        return count

    def invalidate(self, job_names: list):
        """Set jobs to INVALIDATED — works on ANY current status."""
        conn = sqlite3.connect(self.db_path)
        for name in job_names:
            conn.execute('UPDATE jobs SET status = ? WHERE job_name = ? AND status != ?',
                         (Job.INVALIDATED, name, Job.INVALIDATED))
        conn.commit()
        conn.close()

    def get_completed(self) -> dict:
        """Get jobs whose LATEST entry is a completed state. Returns {name: status}."""
        conn = sqlite3.connect(self.db_path)
        cur = conn.execute(
            "SELECT job_name, status FROM jobs "
            "WHERE id IN (SELECT MAX(id) FROM jobs GROUP BY job_name) "
            "AND status IN ('DONE','BYPASSED','FORCE_VALIDATED')")
        result = {row[0]: row[1] for row in cur}
        conn.close()
        return result

    def set_run_info(self, key: str, value: str):
        conn = sqlite3.connect(self.db_path)
        conn.execute('INSERT OR REPLACE INTO run_info (key, value) VALUES (?, ?)',
                     (key, value))
        conn.commit()
        conn.close()

    def get_run_info(self, key: str) -> str:
        conn = sqlite3.connect(self.db_path)
        cur = conn.execute('SELECT value FROM run_info WHERE key = ?', (key,))
        row = cur.fetchone()
        conn.close()
        return row[0] if row else ''

    def record_metric(self, stage: str, metric_name: str, metric_value: str):
        conn = sqlite3.connect(self.db_path)
        conn.execute('INSERT INTO stage_metrics (stage, metric_name, metric_value) VALUES (?, ?, ?)',
                     (stage, metric_name, metric_value))
        conn.commit()
        conn.close()

    def get_metrics(self, stage: str = None) -> list:
        conn = sqlite3.connect(self.db_path)
        if stage:
            cur = conn.execute('SELECT stage, metric_name, metric_value, captured_at '
                               'FROM stage_metrics WHERE stage = ? ORDER BY id', (stage,))
        else:
            cur = conn.execute('SELECT stage, metric_name, metric_value, captured_at '
                               'FROM stage_metrics ORDER BY id')
        rows = [{'stage': r[0], 'metric': r[1], 'value': r[2], 'time': r[3]} for r in cur]
        conn.close()
        return rows

    def set_config(self, key: str, value: str):
        """Store a config key-value in run_config table."""
        conn = sqlite3.connect(self.db_path)
        conn.execute('INSERT OR REPLACE INTO run_config (key, value) VALUES (?, ?)', (key, value))
        conn.commit()
        conn.close()

    def get_config(self, key: str, default: str = '') -> str:
        """Read a config value from run_config table."""
        conn = sqlite3.connect(self.db_path)
        row = conn.execute('SELECT value FROM run_config WHERE key = ?', (key,)).fetchone()
        conn.close()
        return row[0] if row else default

    def get_all_config(self) -> dict:
        """Read all config values from run_config table."""
        conn = sqlite3.connect(self.db_path)
        result = {r[0]: r[1] for r in conn.execute('SELECT key, value FROM run_config')}
        conn.close()
        return result

    def save_dag_structure(self, jobs: dict):
        """Save full DAG structure to dag_structure table."""
        conn = sqlite3.connect(self.db_path)
        conn.execute('DELETE FROM dag_structure')
        for name, job in jobs.items():
            conn.execute(
                'INSERT INTO dag_structure (job_name, stage, subnode, job_type, deps, node_type) '
                'VALUES (?, ?, ?, ?, ?, ?)',
                (name, job.stage, job.subnode, job.job_type,
                 json.dumps(job.deps), job.stage.rstrip('0123456789_')))
        conn.commit()
        conn.close()

    def get_full_status(self) -> dict:
        """Get complete run status from DB."""
        conn = sqlite3.connect(self.db_path)

        # Run info
        run_info = {}
        for key, val in conn.execute('SELECT key, value FROM run_info'):
            run_info[key] = val

        # All jobs with full detail
        jobs = []
        for row in conn.execute(
            'SELECT job_name, stage, subnode, job_type, status, start_time, end_time, '
            'runtime_sec, exit_code, lsf_job_id, lsf_queue, resource_tier, '
            'hostname, error_msg, retry_count FROM jobs ORDER BY id'):
            jobs.append({
                'name': row[0], 'stage': row[1], 'subnode': row[2],
                'type': row[3], 'status': row[4],
                'start': row[5], 'end': row[6], 'runtime': row[7],
                'exit_code': row[8], 'lsf_job_id': row[9], 'lsf_queue': row[10],
                'tier': row[11], 'host': row[12], 'error': row[13], 'retries': row[14],
            })

        # Stage summary
        stages = {}
        for row in conn.execute(
            "SELECT stage, status, MIN(start_time), MAX(end_time), "
            "SUM(runtime_sec), COUNT(*), SUM(CASE WHEN status='DONE' THEN 1 ELSE 0 END), "
            "SUM(CASE WHEN status='FAIL' THEN 1 ELSE 0 END) "
            "FROM jobs WHERE job_type='subnode' GROUP BY stage ORDER BY MIN(id)"):
            stages[row[0]] = {
                'status': row[1], 'start': row[2], 'end': row[3],
                'total_runtime': row[4] or 0,
                'total_jobs': row[5], 'done': row[6], 'failed': row[7],
            }

        # Metrics
        metrics = self.get_metrics()

        conn.close()
        return {
            'run_info': run_info,
            'stages': stages,
            'jobs': jobs,
            'metrics': metrics,
        }


# ═══════════════════════════════════════════════════════════════════════════════
# ENGINE
# ═══════════════════════════════════════════════════════════════════════════════

class RaceEngine:
    """Python-native DAG executor replacing GNU Make."""

    def __init__(self, run_dir: str, flow_type: str, env_vars: dict):
        self.run_dir = run_dir
        self.flow_type = flow_type
        self.env_vars = env_vars or {}
        self.jobs = {}
        self.stage_order = []
        self.db = None
        self._interrupted = False

    def initialize(self, reset_stale=True) -> bool:
        """Build DAG and initialize status DB.

        Args:
            reset_stale: If True (default), reset stale RUNNING jobs and
                         run file-change detection.  Set to False for
                         lightweight init used by dashboard API calls and
                         action handlers — avoids disturbing active execution.
        """
        # Build DAG
        builder = DagBuilder(self.run_dir, self.flow_type, self.env_vars)
        self.jobs, self.stage_order = builder.build()
        if not self.jobs:
            logger.error(f"Failed to build DAG for {self.flow_type}")
            return False

        # Store resolved config for runtime lookups (e.g., _get_timeout)
        self._resolved_config = getattr(builder, '_resolved_cfg', {})

        # Initialize status DB
        # Path: $project(race,db_path)/$project_name/$domain/$flow_type/$user_$run_name.db
        # Resolved from project_config.tcl or env vars
        db_base = self._resolve_db_path()
        project_name = self.env_vars.get('CBFLOW_PROJECT_NAME', '')
        run_name = self.env_vars.get('CBFLOW_RUN_NAME', os.path.basename(self.run_dir))
        user = os.environ.get('USER', 'unknown')

        self.db = StatusDB(
            self.run_dir,
            project_name=project_name,
            domain='PD',
            flow_type=self.flow_type,
            run_name=run_name,
            user=user,
            db_base_path=db_base,
        )
        logger.info(f"Status DB: {self.db.db_path}")
        self.db.set_run_info('flow_type', self.flow_type)
        self.db.set_run_info('run_dir', self.run_dir)
        self.db.set_run_info('project', project_name)
        self.db.set_run_info('user', user)
        self.db.set_run_info('initialized', datetime.now().isoformat())

        # ── Ownership: store owner on first init, verify on subsequent ────
        existing_owner = self.db.get_run_info('owner_uid')
        if not existing_owner:
            # First initialization — record owner
            self.db.set_run_info('owner', user)
            self.db.set_run_info('owner_uid', str(os.getuid()))
            self.db.set_run_info('owner_host', os.uname().nodename)
            self.db.set_run_info('created_at', datetime.now().isoformat())
            logger.info(f"Run owner: {user} (uid={os.getuid()})")

        # Restore completed state from DB (for resume after crash)
        completed = self.db.get_completed()
        for name, job in self.jobs.items():
            if name in completed:
                job.status = completed[name]

        # Save canonical DAG order and seed DB rows for new jobs
        self.db.save_job_order(self.jobs)
        self.db.seed_missing_jobs(self.jobs)

        # Save run config and DAG structure for reconstruction
        self.db.set_run_info('run_name', run_name)
        self.db.set_config('run_name', run_name)
        self.db.set_config('flow_type', self.flow_type)
        self.db.set_config('project_name', project_name)
        for k, v in self.env_vars.items():
            self.db.set_config(f'env.{k}', v)
        # Store user_config.tcl content
        uc_path = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
        if os.path.exists(uc_path):
            with open(uc_path) as f:
                self.db.set_config('user_config_content', f.read())
        # Store runtime_flow_config.tcl content (branches)
        rtf_path = os.path.join(self.run_dir, 'setup', 'runtime_flow_config.tcl')
        if os.path.exists(rtf_path):
            with open(rtf_path) as f:
                self.db.set_config('runtime_flow_config_content', f.read())
        self.db.save_dag_structure(self.jobs)

        if reset_stale:
            # Clean up stale RUNNING from interrupted runs — reset to READY
            # Only on first startup, NOT on dashboard API refreshes
            self.db.reset_stale_jobs()

            # ── File change detection: auto-invalidate downstream ───
            changed = self._detect_input_changes()
            if changed:
                logger.info(f"File changes detected — auto-invalidating affected stages")
                for stage, changed_files in changed.items():
                    for f in changed_files:
                        logger.info(f"  CHANGED: {stage} → {f}")
                    self._auto_retrace_from(stage)

        # ── Populate design_info and track config changes ──
        self._populate_design_info()
        self._track_config_changes()

        logger.info(f"RACE initialized: {len(self.jobs)} jobs, "
                     f"{len(self.stage_order)} stages")

        # Check DB session count against limit
        self._check_db_session_limit()
        return True

    # ── Ownership enforcement ────────────────────────────────────────────────

    def _check_ownership(self):
        """Verify current user is the run owner. Raises PermissionError if not."""
        if not self.db:
            return
        owner_uid = self.db.get_run_info('owner_uid')
        if owner_uid:
            if os.getuid() != int(owner_uid):
                owner_name = self.db.get_run_info('owner') or 'unknown'
                raise PermissionError(
                    f"Run owned by '{owner_name}' — only the owner can modify this run"
                )

    # ── Design info + config tracking ─────────────────────────────────────

    def _populate_design_info(self):
        """Extract design metadata from resolved config and store in DB."""
        if not self.db:
            return
        info_keys = {
            'CBFLOW_DESIGN_NAME': 'design_name',
            'CBFLOW_BLOCK_NAME': 'block_name',
            'CBFLOW_PROJECT_NAME': 'project_name',
            'CBFLOW_PROJECT_PHASE': 'phase',
            'CBFLOW_FLOW_TYPE': 'flow_type',
        }
        conn = sqlite3.connect(self.db.db_path)
        for env_key, db_key in info_keys.items():
            val = self.env_vars.get(env_key, '')
            if val:
                conn.execute(
                    "INSERT OR REPLACE INTO design_info (key, value, updated_at) "
                    "VALUES (?, ?, datetime('now'))", (db_key, val)
                )
        # Store run_name and flow_type for quick access
        conn.execute(
            "INSERT OR REPLACE INTO design_info (key, value, updated_at) "
            "VALUES ('run_name', ?, datetime('now'))",
            (self.env_vars.get('CBFLOW_RUN_NAME', ''),)
        )
        conn.commit()
        conn.close()

    def _track_config_changes(self):
        """Track config file changes via content hashing."""
        import hashlib
        if not self.db:
            return
        config_files = [
            os.path.join(self.run_dir, 'setup', 'user_config.tcl'),
            os.path.join(self.run_dir, 'setup', 'override_config.tcl'),
            os.path.join(self.run_dir, 'setup', 'runtime_flow_config.tcl'),
        ]
        # Include all override_config.*.tcl files
        setup_dir = os.path.join(self.run_dir, 'setup')
        if os.path.isdir(setup_dir):
            for f in os.listdir(setup_dir):
                if f.startswith('override_config.') and f.endswith('.tcl'):
                    config_files.append(os.path.join(setup_dir, f))

        conn = sqlite3.connect(self.db.db_path)
        user = os.environ.get('USER', 'unknown')
        for cfg_path in config_files:
            if not os.path.exists(cfg_path):
                continue
            with open(cfg_path, 'rb') as f:
                content_hash = hashlib.md5(f.read()).hexdigest()
            fname = os.path.basename(cfg_path)
            # Check if hash changed
            row = conn.execute(
                "SELECT content_hash FROM config_history "
                "WHERE config_file = ? ORDER BY id DESC LIMIT 1", (fname,)
            ).fetchone()
            if not row:
                conn.execute(
                    "INSERT INTO config_history (config_file, change_type, changed_by, content_hash, summary) "
                    "VALUES (?, 'created', ?, ?, 'Initial config')",
                    (fname, user, content_hash)
                )
            elif row[0] != content_hash:
                conn.execute(
                    "INSERT INTO config_history (config_file, change_type, changed_by, content_hash, summary) "
                    "VALUES (?, 'modified', ?, ?, 'Config updated')",
                    (fname, user, content_hash)
                )
        conn.commit()
        conn.close()

    def _record_log_summary(self, job_name: str, stage: str, log_file: str):
        """Scan a log file for errors/warnings and store summary in DB."""
        if not self.db or not log_file or not os.path.exists(log_file):
            return
        try:
            with open(log_file, 'r', errors='replace') as f:
                content = f.read()
            log_size = os.path.getsize(log_file)
            error_count = len(re.findall(r'\bERROR\b', content, re.IGNORECASE))
            warning_count = len(re.findall(r'\bWARNING\b', content, re.IGNORECASE))
            # Extract critical error lines (first 10)
            critical = []
            for line in content.splitlines():
                if re.search(r'\b(ERROR|FATAL|CRITICAL)\b', line, re.IGNORECASE):
                    critical.append(line.strip()[:200])
                    if len(critical) >= 10:
                        break
            import json
            conn = sqlite3.connect(self.db.db_path)
            conn.execute(
                "INSERT INTO run_logs (job_name, stage, log_file, log_size_bytes, "
                "error_count, warning_count, critical_errors) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (job_name, stage, os.path.relpath(log_file, self.run_dir),
                 log_size, error_count, warning_count,
                 json.dumps(critical) if critical else None)
            )
            conn.commit()
            conn.close()
        except Exception:
            pass  # Non-critical — don't fail job because of log scanning

    def _record_lsf_details(self, job_name: str, job):
        """Record LSF resource details for a completed job."""
        if not self.db or not getattr(job, 'lsf_job_id', None):
            return
        try:
            conn = sqlite3.connect(self.db.db_path)
            conn.execute(
                "INSERT INTO lsf_details (job_name, lsf_job_id, queue, resource_tier, "
                "exec_host, start_time, end_time, exit_code) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (job_name, job.lsf_job_id,
                 getattr(job, 'lsf_queue', None),
                 getattr(job, 'resource_tier', None),
                 getattr(job, 'hostname', None),
                 getattr(job, 'start_time', None),
                 getattr(job, 'end_time', None),
                 getattr(job, 'exit_code', None))
            )
            conn.commit()
            conn.close()
        except Exception:
            pass

    # ── Invalidation helper ─────────────────────────────────────────────────

    def _invalidate_jobs(self, job_names: list):
        """Invalidate jobs: set in-memory status + update DB."""
        for name in job_names:
            job = self.jobs.get(name)
            if job:
                job.status = Job.INVALIDATED
        if job_names:
            self.db.invalidate(job_names)

    def bypass(self, stages: list) -> int:
        """Mark stages as skipped (bypass). Works on any current status."""
        self._check_ownership()
        count = 0
        for stage in stages:
            for name, job in self.jobs.items():
                if job.stage == stage and job.status != Job.BYPASSED:
                    self.db.record_direct(job, Job.BYPASSED)
                    count += 1
            logger.info(f"Bypassed: {stage}")
        logger.info(f"Total bypassed: {count} jobs")
        return 0

    def forcevalidate(self, stages: list) -> int:
        """Mark stages + all upstream as completed (force-validate).
        If you force-validate cts1, then rtl1/sdc1/upf1 → init_design1 → synthesis1 → place1 → cts1
        all get marked as FORCE_VALIDATED."""
        self._check_ownership()
        all_jobs = set()
        for stage in stages:
            upstream = self._get_jobs_for_target(stage)
            all_jobs.update(upstream)

        count = 0
        validated_stages = set()
        for name in all_jobs:
            job = self.jobs.get(name)
            if job:
                self.db.record_direct(job, Job.FORCE_VALIDATED)
                count += 1
                validated_stages.add(job.stage)

        for stage in sorted(validated_stages):
            logger.info(f"Force-validated: {stage}")
        logger.info(f"Total force-validated: {count} jobs")
        return 0

    def forcevalidate_jobs(self, job_names: list) -> int:
        """Force-validate specific jobs by name (subnode-level)."""
        count = 0
        for jname in job_names:
            job = self.jobs.get(jname)
            if job:
                self.db.record_direct(job, Job.FORCE_VALIDATED)
                count += 1
                logger.info(f"Force-validated: {jname}")
        logger.info(f"Total force-validated: {count} jobs")
        return 0

    def bypass_jobs(self, job_names: list) -> int:
        """Bypass specific jobs by name (subnode-level). Works on any status."""
        count = 0
        for jname in job_names:
            job = self.jobs.get(jname)
            if job and job.status != Job.BYPASSED:
                self.db.record_direct(job, Job.BYPASSED)
                count += 1
                logger.info(f"Bypassed: {jname}")
        logger.info(f"Total bypassed: {count} jobs")
        return 0

    def force(self, stages: list) -> int:
        """Force re-execute specific stages + upstream deps. Invalidate true downstream."""
        self._check_ownership()
        target_jobs = set()
        for stage in stages:
            stage_jobs = self._get_jobs_for_target(stage)
            target_jobs.update(stage_jobs)

        # Invalidate TRUE downstream via dependency graph
        target_stages = set(self.jobs[n].stage for n in target_jobs if n in self.jobs)
        downstream = set()
        self._collect_downstream(target_stages, downstream)
        # Only invalidate completed downstream jobs
        downstream = {n for n in downstream if self.jobs.get(n) and self.jobs[n].is_completed}

        # Invalidate target + downstream in one call
        self._invalidate_jobs(list(target_jobs | downstream))

        up_stages = sorted(target_stages)
        down_stages = sorted(set(self.jobs[n].stage for n in downstream if n in self.jobs))
        logger.info(f"Force re-execute: {', '.join(up_stages)}")
        if down_stages:
            logger.info(f"Downstream invalidated: {', '.join(down_stages)}")

        return self.execute_jobs(target_jobs)

    def _collect_downstream(self, source_stages: set, result: set):
        """Collect all jobs that are TRUE downstream of source_stages via dependency graph."""
        # Build reverse dep map: for each job, which jobs depend on it
        dependents = {}  # job_name -> list of job_names that depend on it
        for name, job in self.jobs.items():
            for dep in job.deps:
                if dep not in dependents:
                    dependents[dep] = []
                dependents[dep].append(name)

        # BFS from all jobs in source_stages
        queue = []
        for name, job in self.jobs.items():
            if job.stage in source_stages:
                # Find all jobs that depend on this job
                for dependent in dependents.get(name, []):
                    if self.jobs[dependent].stage not in source_stages:
                        queue.append(dependent)

        visited = set()
        while queue:
            name = queue.pop(0)
            if name in visited:
                continue
            visited.add(name)
            result.add(name)
            # Continue downstream
            for dependent in dependents.get(name, []):
                if dependent not in visited:
                    queue.append(dependent)

    def execute(self, target: str = 'all', env_vars: dict = None) -> int:
        """Execute target (stage name or 'all')."""
        self._check_ownership()
        if env_vars:
            self.env_vars.update(env_vars)

        # Determine which jobs to run
        if target == 'all':
            target_jobs = set(self.jobs.keys())
        else:
            target_jobs = self._get_jobs_for_target(target)

        return self.execute_jobs(target_jobs)

    def execute_jobs(self, target_jobs: set) -> int:
        """Execute a set of jobs respecting dependencies."""
        # Install signal handler for graceful interrupt (main thread only)
        import threading
        if threading.current_thread() is threading.main_thread():
            signal.signal(signal.SIGINT, self._handle_interrupt)

        target_desc = ', '.join(sorted({self.jobs[n].stage for n in target_jobs if n in self.jobs}))
        self.db.set_run_info('target', target_desc)
        self.db.set_run_info('started', datetime.now().isoformat())

        logger.info(f"Executing {len(target_jobs)} jobs ({target_desc})")

        # Topological execution
        completed = {n for n, j in self.jobs.items() if j.is_completed}
        failed = set()

        # Mark all non-completed target jobs as PENDING in DB upfront
        # Iterate in DAG order (self.jobs preserves insertion order) — NOT set order
        pending_jobs = []
        for name, job in self.jobs.items():
            if name in target_jobs and name not in completed and job.status in (Job.READY, Job.INVALIDATED):
                job.status = Job.PENDING
                pending_jobs.append(job)
        if pending_jobs:
            self.db.record_pending(pending_jobs)

        while target_jobs - completed - failed and not self._interrupted:
            # Re-sync from DB: catch external invalidation (retrace/bypass during execution)
            self._sync_from_db(target_jobs, completed, failed)

            # Find jobs whose deps are satisfied (still PENDING after sync)
            ready = []
            for name in target_jobs - completed - failed:
                job = self.jobs[name]
                if job.status == Job.PENDING and all(d in completed for d in job.deps):
                    ready.append(job)

            if not ready:
                # Check if we're stuck (deps failed)
                remaining = target_jobs - completed - failed
                if remaining:
                    stuck_deps = set()
                    for name in remaining:
                        for dep in self.jobs[name].deps:
                            if dep in failed:
                                stuck_deps.add(dep)
                    if stuck_deps:
                        logger.error(f"Blocked by failed jobs: {', '.join(stuck_deps)}")
                    else:
                        logger.error(f"Deadlock: {len(remaining)} jobs stuck")
                break

            # Execute ready jobs in parallel (independent branches run concurrently)
            import concurrent.futures
            if len(ready) == 1 or self._interrupted:
                # Single job or interrupted — run sequentially
                for job in ready:
                    if self._interrupted:
                        break
                    rc = self._execute_job(job)
                    if rc == 0:
                        completed.add(job.name)
                    else:
                        failed.add(job.name)
                        logger.error(f"FAILED: {job.name} (exit={rc})")
                        break
            else:
                # Multiple independent jobs ready — run in parallel
                logger.info(f"  Launching {len(ready)} jobs in parallel: {', '.join(j.name for j in ready)}")
                results = {}
                with concurrent.futures.ThreadPoolExecutor(max_workers=len(ready)) as pool:
                    futures = {pool.submit(self._execute_job, job): job for job in ready}
                    for future in concurrent.futures.as_completed(futures):
                        job = futures[future]
                        try:
                            rc = future.result()
                            results[job.name] = rc
                            if rc == 0:
                                completed.add(job.name)
                            else:
                                failed.add(job.name)
                                logger.error(f"FAILED: {job.name} (exit={rc})")
                        except Exception as e:
                            failed.add(job.name)
                            logger.error(f"FAILED: {job.name} (exception={e})")

            if failed:
                # Reset all remaining PENDING jobs back to READY
                # (downstream jobs that will never run due to failure)
                remaining_pending = []
                for name in target_jobs - completed - failed:
                    job = self.jobs[name]
                    if job.status == Job.PENDING:
                        job.status = Job.READY
                        remaining_pending.append(job)
                if remaining_pending:
                    self.db.record_ready(remaining_pending)
                    logger.info(f"Reset {len(remaining_pending)} downstream jobs to READY")
                break

        # Summary
        done_count = len([j for j in self.jobs.values()
                         if j.is_completed and j.name in target_jobs])
        fail_count = len(failed)
        total = len(target_jobs)

        self.db.set_run_info('completed', datetime.now().isoformat())
        self.db.set_run_info('result', 'PASS' if fail_count == 0 else 'FAIL')

        if self._interrupted:
            logger.warning(f"\nInterrupted. Completed {done_count}/{total} jobs.")
            return 130  # Standard SIGINT exit code
        elif fail_count > 0:
            logger.error(f"\nFAILED. {done_count}/{total} completed, "
                          f"{fail_count} failed.")
            self._report_failures(failed)
            return 1
        else:
            logger.info(f"\nSUCCESS. All {done_count} jobs completed.")
            return 0

    def retrace(self, from_stage: str = None, stages: list = None) -> bool:
        """Smart retrace — invalidate specified stages + TRUE downstream via dependency graph."""
        self._check_ownership()
        invalidate_names = []

        if from_stage:
            # Invalidate from_stage + true downstream via dependency graph
            for name, job in self.jobs.items():
                if job.stage == from_stage:
                    invalidate_names.append(name)
            downstream = set()
            self._collect_downstream({from_stage}, downstream)
            invalidate_names.extend(downstream)

        elif stages:
            for stage in stages:
                for name, job in self.jobs.items():
                    if job.stage == stage:
                        invalidate_names.append(name)
            # Also invalidate true downstream of all specified stages
            downstream = set()
            self._collect_downstream(set(stages), downstream)
            invalidate_names.extend(downstream)
        else:
            # Full retrace — all jobs
            invalidate_names = list(self.jobs.keys())

        # Deduplicate
        invalidate_names = list(dict.fromkeys(invalidate_names))

        self._invalidate_jobs(invalidate_names)

        logger.info(f"Retraced {len(invalidate_names)} jobs"
                     f"{f' from {from_stage}' if from_stage else ''}")
        return True

    def status(self) -> dict:
        """Return structured status of all stages."""
        result = {}
        for stage in self.stage_order:
            stage_job = self.jobs.get(stage)
            if stage_job:
                # Collect subnode statuses
                subnodes = {}
                for name, job in self.jobs.items():
                    if job.stage == stage and job.job_type != 'stage':
                        subnodes[job.subnode] = {
                            'status': job.status,
                            'runtime': self._calc_runtime(job),
                        }
                result[stage] = {
                    'status': stage_job.status,
                    'subnodes': subnodes,
                    'runtime': sum(s.get('runtime', 0) for s in subnodes.values()),
                }
        return result

    # ── Private Methods ──────────────────────────────────────────────────────

    def _detect_input_changes(self) -> dict:
        """Detect changes in source input files and work directories.

        Two types of change detection:
        1. SOURCE FILE CHANGES — checks if the original input files (from user_config.tcl)
           have been modified after the input node completed. This catches RTL/SDC/UPF edits.
        2. WORK DIR CHANGES — checks if any file in a stage's work directory
           was modified after the stage completed.

        If changes detected, the affected stage + all downstream get invalidated.

        Returns: {stage_name: [list of changed files]} or empty dict
        """
        changed = {}
        conn = sqlite3.connect(self.db.db_path)

        # ── 1. Source file change detection (input leaf nodes) ────────────
        # Read source file paths from user_config.tcl
        source_files = self._get_source_input_files()

        for stage in self.stage_order:
            # Get stage completion time from DB
            cur = conn.execute(
                "SELECT end_time FROM jobs WHERE job_name = ? "
                "AND status IN ('DONE','BYPASSED','FORCE_VALIDATED') "
                "ORDER BY id DESC LIMIT 1", (stage,))
            row = cur.fetchone()
            if not row or not row[0]:
                continue

            try:
                stage_done_time = datetime.fromisoformat(row[0]).timestamp()
            except (ValueError, TypeError):
                continue

            changed_files = []

            # Check source files mapped to this stage
            stage_base = stage.rstrip('0123456789')
            for src_path in source_files.get(stage_base, []):
                try:
                    if os.path.exists(src_path):
                        fmtime = os.path.getmtime(src_path)
                        if fmtime > stage_done_time:
                            changed_files.append(f'SOURCE: {src_path}')
                except OSError:
                    pass

            # Check work directory files
            work_dir = os.path.join(self.run_dir, 'work', self.flow_type, stage)
            if os.path.isdir(work_dir):
                for root, dirs, files in os.walk(work_dir):
                    dirs[:] = [d for d in dirs if d != 'reports']
                    for f in files:
                        fp = os.path.join(root, f)
                        try:
                            actual = os.path.realpath(fp)
                            fmtime = os.path.getmtime(actual)
                            if fmtime > stage_done_time:
                                rel_path = os.path.relpath(fp, self.run_dir)
                                if rel_path not in changed_files:
                                    changed_files.append(rel_path)
                        except OSError:
                            pass

            if changed_files:
                changed[stage] = changed_files

        conn.close()
        return changed

    def _get_source_input_files(self) -> dict:
        """Read source input file paths from user_config.tcl.
        Maps input type (rtl, sdc, upf, netlist, etc.) to list of source file paths.
        These are the ORIGINAL files that the user provides — not the copies in work dirs."""
        source_map = {}  # {input_type: [file_paths]}
        user_config = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
        if not os.path.exists(user_config):
            return source_map

        # Map of config key patterns to input node types
        key_to_type = {
            'rtl_filelist': 'rtl', 'rtl_format': None,
            'sdc_func_file': 'sdc', 'sdc_file': 'sdc',
            'upf_file': 'upf',
            'netlist': 'netlist', 'netlist_golden': 'netlist_golden',
            'netlist_revised': 'netlist_revised',
            'def_file': 'def',
            'gds_file': 'gds',
            'spef_file': 'spef',
            'constraints': 'constraints',
            'power_spec': 'power_spec',
        }

        with open(user_config) as f:
            for line in f:
                line = line.strip()
                m = re.match(r'set\s+\w+\(input,(\w+)\)\s+"([^"]*)"', line)
                if m:
                    key_name = m.group(1)
                    file_path = m.group(2)
                    if not file_path or not os.path.exists(file_path):
                        continue
                    # Find which input type this maps to
                    input_type = key_to_type.get(key_name)
                    if input_type is None:
                        # Try matching by prefix
                        for kp, it in key_to_type.items():
                            if key_name.startswith(kp.split('_')[0]) and it:
                                input_type = it
                                break
                    if input_type:
                        source_map.setdefault(input_type, []).append(file_path)

        return source_map

    def _auto_retrace_from(self, stage: str):
        """Auto-invalidate a stage and its TRUE downstream via dependency graph."""
        # Collect changed stage jobs (only completed ones)
        invalidated = [name for name, job in self.jobs.items()
                       if job.stage == stage and job.status in Job.COMPLETED_STATES]

        # Collect true downstream (only completed ones)
        downstream = set()
        self._collect_downstream({stage}, downstream)
        invalidated.extend(n for n in downstream
                           if self.jobs.get(n) and self.jobs[n].status in Job.COMPLETED_STATES)

        if invalidated:
            self._invalidate_jobs(invalidated)
            stages_affected = sorted(set(self.jobs[n].stage for n in invalidated if n in self.jobs))
            logger.info(f"  Auto-retraced {len(invalidated)} jobs: {' → '.join(stages_affected)}")

    def _check_db_session_limit(self):
        """Warn if RACE DB session count approaches or exceeds the configured limit."""
        try:
            max_sessions = 10
            flow_dir = self.env_vars.get('FLOW_DIR', '')
            fc_path = os.path.join(flow_dir, 'config', 'flow',
                                   self.env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0'),
                                   'flow_config.tcl')
            if os.path.exists(fc_path):
                with open(fc_path) as f:
                    for line in f:
                        m = re.search(r'flow\(race,db_max_sessions\)\s+(\d+)', line)
                        if m: max_sessions = int(m.group(1))
            warn_threshold = int(max_sessions * 0.8)

            # Count DBs: prefer race area, fallback to workarea local scan
            count = 0
            if self.db and hasattr(self.db, 'db_path'):
                db_dir = os.path.dirname(self.db.db_path)
                if os.path.isdir(db_dir):
                    count = sum(1 for f in os.listdir(db_dir) if f.endswith('.db'))
            if count == 0:
                # Fallback: count local .race_*.db in workarea
                workarea = os.path.dirname(self.run_dir)
                count = sum(1 for d in Path(workarea).iterdir()
                           if d.is_dir()
                           for _ in d.glob('.race_*.db'))

            if count >= max_sessions:
                logger.error(f"RACE DB session limit reached ({count}/{max_sessions})! "
                            f"Run 'cbflow manage delete-db' to free sessions.")
            elif count >= warn_threshold:
                logger.warning(f"RACE DB sessions at {count}/{max_sessions} (80% threshold). "
                              f"Consider: cbflow manage list --path <race_area>")
        except Exception:
            pass  # Non-critical — don't block init

    def _resolve_db_path(self) -> str:
        """Resolve DB base path from project_config.tcl.

        Reads project(race,db_path) from project config.
        Returns empty string if not configured (falls back to run_dir).

        Convention: $db_path/$project/$domain/$flow/$user_$run.db
        Example:    /proj/phoenix/cbflow_db/phoenix/PD/SYNTH_PNR/vmerugu_run0.db
        """
        db_path = ''

        # Try project config
        project_name = self.env_vars.get('CBFLOW_PROJECT_NAME', '')
        config_root = self.env_vars.get('CONFIG_ROOT',
                      self.env_vars.get('FLOW_DIR', ''))
        if project_name and config_root:
            # Search project config for race,db_path
            for ver_dir in Path(os.path.join(config_root, 'config', 'project',
                                             project_name)).glob('v*/'):
                for cfg_file in ver_dir.glob('*_config.tcl'):
                    try:
                        with open(cfg_file) as f:
                            for line in f:
                                m = re.match(r'set\s+project\(race,db_path\)\s+"([^"]+)"',
                                             line.strip())
                                if m:
                                    db_path = m.group(1)
                                    break
                    except (OSError, UnicodeDecodeError):
                        pass
                    if db_path:
                        break
                if db_path:
                    break

        return db_path

    def _validate_required_inputs(self, job: Job) -> list:
        """Check if required input files exist before executing a stage.
        Returns list of missing files, or empty list if all OK."""
        if not hasattr(self, '_required_inputs_cache'):
            self._required_inputs_cache = {}
            # Read required_inputs from node config
            flow_dir = self.env_vars.get('FLOW_DIR', '')
            nc_path = os.path.join(flow_dir, 'config', 'flow',
                                   self.env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0'),
                                   'node_configs', f'{self.flow_type}_config.tcl')
            config = ''
            if os.path.exists(nc_path):
                with open(nc_path) as f:
                    config = f.read()
            if config:
                # Match both: set flow(required_inputs,stage) "files" AND array set {required_inputs,stage {files}}
                for m in re.finditer(r'required_inputs,(\w+)\)\s+"([^"]*)"', config):
                    stage = m.group(1)
                    files = m.group(2).split()
                    self._required_inputs_cache[stage] = files

        required = self._required_inputs_cache.get(job.stage, [])
        missing = []
        for f in required:
            full_path = os.path.join(self.run_dir, f)
            if not os.path.exists(full_path):
                missing.append(f)
        return missing

    def _sync_from_db(self, target_jobs: set, completed: set, failed: set):
        """Re-sync in-memory job status from DB to catch external changes.
        Called each iteration of execute_jobs() loop so that retrace/bypass/
        forcevalidate actions from the dashboard take effect immediately."""
        try:
            db_status = self.db.get_completed()  # {name: status} for completed jobs
            # Also get invalidated/ready jobs
            conn = sqlite3.connect(self.db.db_path)
            cur = conn.execute(
                "SELECT job_name, status FROM jobs "
                "WHERE id IN (SELECT MAX(id) FROM jobs GROUP BY job_name)")
            db_latest = {row[0]: row[1] for row in cur}
            conn.close()

            for name in list(target_jobs - completed - failed):
                job = self.jobs.get(name)
                if not job:
                    continue
                db_st = db_latest.get(name, '')
                if not db_st:
                    continue

                # External invalidation: DB says INVALIDATED but we think PENDING
                if db_st == Job.INVALIDATED and job.status == Job.PENDING:
                    job.status = Job.INVALIDATED
                    logger.info(f"  [{job.stage}/{job.subnode}] externally invalidated — skipping")

                # External bypass: DB says BYPASSED
                elif db_st == Job.BYPASSED and job.status != Job.BYPASSED:
                    job.status = Job.BYPASSED
                    completed.add(name)
                    logger.info(f"  [{job.stage}/{job.subnode}] externally bypassed")

                # External force-validate: DB says FORCE_VALIDATED
                elif db_st == Job.FORCE_VALIDATED and job.status != Job.FORCE_VALIDATED:
                    job.status = Job.FORCE_VALIDATED
                    completed.add(name)
                    logger.info(f"  [{job.stage}/{job.subnode}] externally force-validated")

                # External ready reset (shouldn't happen often but handle it)
                elif db_st == Job.READY and job.status == Job.PENDING:
                    job.status = Job.READY

        except Exception as e:
            logger.debug(f"DB sync error (non-fatal): {e}")

    def _execute_job(self, job: Job) -> int:
        """Execute a single job. Returns exit code."""
        if job.job_type == 'stage' and job.subnode == '_sentinel':
            # Sentinel — mark stage complete in DB
            self.db.record_start(job)
            self.db.record_complete(job, 0)
            logger.info(f"  [{job.stage}] stage complete")
            return 0

        # ── Pre-execution check: required input files from upstream ──
        # Only check on the first subnode (setup) of each stage
        # Skip in test mode — no real EDA outputs are produced
        is_test_mode = self.env_vars.get('CBFLOW_TEST_MODE', '') == 'true' or \
                       os.environ.get('CBFLOW_TEST_MODE', '') == 'true'
        if not is_test_mode:
            # Check user_config.tcl for flow(test_mode)
            uc = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
            if os.path.exists(uc):
                with open(uc) as f:
                    for line in f:
                        if 'test_mode' in line and '"true"' in line:
                            is_test_mode = True
                            break
        if not is_test_mode and job.subnode in ('setup', job.stage.rstrip('0123456789')):
            missing = self._validate_required_inputs(job)
            if missing:
                logger.error(f"  [{job.stage}/{job.subnode}] BLOCKED — required input files missing:")
                for f in missing:
                    logger.error(f"    MISSING: {f}")
                logger.error(f"  This usually means the upstream stage failed to produce its output.")
                logger.error(f"  Check the upstream stage's logs for errors.")
                self.db.record_start(job)
                self.db.record_complete(job, 1, f'Missing required inputs: {", ".join(missing)}')
                return 1

        # Subnode/leaf job — execute handler
        self.db.record_start(job)
        logger.info(f"  [{job.stage}/{job.subnode}] running...")

        # Build environment: os.environ + .run.cbflow.env + engine vars
        run_env = os.environ.copy()
        # Load ALL vars from .run.cbflow.env (SCRIPTS_ROOT, CONFIG_ROOT, etc.)
        env_file = os.path.join(self.run_dir, '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        if line.startswith('export '):
                            line = line[7:]
                        k, v = line.split('=', 1)
                        run_env[k] = v.strip('"').strip("'")
        run_env.update(self.env_vars)
        run_env['CBFLOW_ENGINE'] = '1'
        run_env['CBFLOW_RUN_DIR'] = self.run_dir
        run_env['CBFLOW_NODE_NAME'] = job.stage
        run_env['CBFLOW_SUBNODE'] = job.subnode

        try:
            # Log to work/<FLOW>/<stage>/run/<node_name>.log (tool run log)
            log_dir = os.path.join(self.run_dir, 'work', self.flow_type, job.stage, 'run')
            os.makedirs(log_dir, exist_ok=True)
            log_file = os.path.join(log_dir, f'{job.name}.log')

            with open(log_file, 'w') as lf:
                result = subprocess.run(
                    job.command, shell=True, env=run_env,
                    cwd=self.run_dir, timeout=self._get_timeout(job),
                    stdout=lf, stderr=subprocess.STDOUT)

            exit_code = result.returncode
            error_msg = ''

            if exit_code != 0:
                # Read log for detailed error context
                try:
                    with open(log_file) as lf:
                        lines = lf.readlines()

                    # Extract ERROR/FATAL/error lines for summary
                    error_lines = [l.rstrip() for l in lines if any(
                        k in l.upper() for k in ('ERROR', 'FATAL', 'FAILED', 'ABORT')
                    )]
                    tail = ''.join(lines[-30:]) if len(lines) > 30 else ''.join(lines)

                    if error_lines:
                        error_summary = '\n'.join(error_lines[-10:])
                        error_msg = f"ERRORS:\n{error_summary}\n\nLog tail:\n{tail}"
                    else:
                        error_msg = f"Process exited with code {exit_code} (no ERROR lines found)\n\nLog tail:\n{tail}"
                except Exception:
                    error_msg = f"Process exited with code {exit_code}. Log: {log_file}"

            self.db.record_complete(job, exit_code, error_msg)

            # ── Record log summary and LSF details to DB ──
            self._record_log_summary(job.name, job.stage, log_file)
            self._record_lsf_details(job.name, job)

            if exit_code == 0:
                logger.info(f"  [{job.stage}/{job.subnode}] done")
            else:
                logger.error(f"  [{job.stage}/{job.subnode}] FAILED (exit={exit_code})")
                logger.error(f"  Log: {log_file}")
                # Print first few error lines to console
                if error_msg:
                    for line in error_msg.split('\n')[:5]:
                        logger.error(f"  {line}")

            return exit_code

        except subprocess.TimeoutExpired:
            error_msg = f"Job timed out after {self._get_timeout(job)}s. Stage: {job.stage}, Subnode: {job.subnode}"
            self.db.record_complete(job, 124, error_msg)
            logger.error(f"  [{job.stage}/{job.subnode}] TIMEOUT — {error_msg}")
            return 124
        except Exception as e:
            error_msg = f"Execution error: {str(e)}\nCommand: {job.command}"
            self.db.record_complete(job, 1, error_msg)
            logger.error(f"  [{job.stage}/{job.subnode}] ERROR: {e}")
            return 1

    def _get_jobs_for_target(self, target: str) -> set:
        """Get all jobs needed to complete a target (stage + its dependencies)."""
        if target in self.jobs and self.jobs[target].job_type == 'stage':
            # Collect this stage and all upstream stages
            needed = set()
            self._collect_upstream(target, needed)
            return needed
        elif target in self.jobs:
            return {target}
        else:
            # Try as stage name
            stage = target.rstrip('0123456789') + '1' if not target[-1].isdigit() else target
            if stage in self.jobs:
                needed = set()
                self._collect_upstream(stage, needed)
                return needed
            logger.error(f"Unknown target: {target}")
            return set()

    def _collect_upstream(self, job_name: str, needed: set):
        """Recursively collect a job and all its upstream dependencies."""
        if job_name in needed:
            return
        needed.add(job_name)
        job = self.jobs.get(job_name)
        if job:
            for dep in job.deps:
                self._collect_upstream(dep, needed)
            # Also collect all subnodes for this stage
            if job.job_type == 'stage':
                for name, j in self.jobs.items():
                    if j.stage == job.stage:
                        if name not in needed:
                            needed.add(name)
                            for dep in j.deps:
                                self._collect_upstream(dep, needed)

    def _get_timeout(self, job: Job) -> int:
        """Get timeout in seconds for a job from config.

        Reads runtime,timeout,<stage> from resolved config (value in minutes).
        Falls back to 14400 seconds (4 hours) if not configured.
        """
        timeout_key = f'runtime,timeout,{job.stage}'
        timeout_val = self._resolved_config.get(timeout_key, '') if hasattr(self, '_resolved_config') else ''
        if timeout_val:
            try:
                return int(timeout_val) * 60  # config is in minutes
            except ValueError:
                pass
        return 14400  # 4 hour default if not in config

    def _calc_runtime(self, job: Job) -> float:
        if job.start_time and job.end_time:
            try:
                t0 = datetime.fromisoformat(job.start_time)
                t1 = datetime.fromisoformat(job.end_time)
                return (t1 - t0).total_seconds()
            except Exception:
                pass
        return 0

    def _handle_interrupt(self, signum, frame):
        logger.warning("\nInterrupt received — stopping after current job...")
        self._interrupted = True

    def _report_failures(self, failed: set):
        """Print failure summary."""
        print(f"\n{'=' * 60}")
        print(f"  FAILURE REPORT")
        print(f"{'=' * 60}")
        for name in sorted(failed):
            job = self.jobs.get(name)
            if job:
                print(f"  FAILED: {name}")
                print(f"    Command: {job.command[:80]}...")
                print(f"    Exit:    {job.exit_code}")
                if job.start_time:
                    print(f"    Started: {job.start_time}")
        print(f"{'=' * 60}\n")
