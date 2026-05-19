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
        config = self._load_node_config()
        if not config:
            return {}, []

        stages = self._parse_stages(config)
        stage_deps = self._parse_dependencies(config, stages)
        subnodes = self._parse_subnodes(config, stages)
        resource_map = self._parse_resource_map(config, stages)

        # Merge custom nodes from run-level runtime config
        custom_nodes, custom_deps = self._load_runtime_custom_nodes()
        self._custom_node_types = {}  # custom node name → base handler name
        for name, info in custom_nodes.items():
            if name not in stages:
                # Insert after the dependency stage
                dep = info.get('dependency', '')
                if dep and dep in stages:
                    idx = stages.index(dep) + 1
                    stages.insert(idx, name)
                else:
                    stages.append(name)
                stage_deps[name] = [dep] if dep else []
                subnodes[name] = info.get('subnodes', ['setup', 'run', 'validate', 'finish'])
                resource_map[name] = info.get('resource_tier', 'M')
                # Map custom node to its base handler (e.g., synthesis2_xyz → synthesis)
                node_type = info.get('type', '')
                if node_type:
                    self._custom_node_types[name] = re.sub(r'\d+$', '', node_type)
                logger.info(f"Custom node: {name} (dep={dep})")

        # Parse subnode-level dependencies (for parallel subnodes like PV drc/lvs)
        sub_deps = self._parse_subnode_dependencies(config, stages, subnodes)

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

    def _load_node_config(self) -> str:
        """Load node config TCL file content."""
        config_root = self.env_vars.get('CONFIG_ROOT',
                      self.env_vars.get('FLOW_DIR', ''))
        flow_version = self.env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
        config_path = os.path.join(config_root, 'config', 'flow', flow_version,
                                   'node_configs', f'{self.flow_type}_config.tcl')
        if not os.path.exists(config_path):
            # Try from FLOW_DIR directly
            config_path = os.path.join(self.env_vars.get('FLOW_DIR', ''),
                                       'config', 'flow', flow_version,
                                       'node_configs', f'{self.flow_type}_config.tcl')
        if os.path.exists(config_path):
            with open(config_path) as f:
                return f.read()
        logger.error(f"Node config not found: {config_path}")
        return ""

    def _parse_stages(self, config: str) -> list:
        m = re.search(r'stages\s+\{([^}]+)\}', config)
        return m.group(1).split() if m else []

    def _parse_dependencies(self, config: str, stages: list) -> dict:
        deps = {}
        for stage in stages:
            m = re.search(rf'dependencies,{stage}\s+\{{([^}}]*)\}}', config)
            if m:
                dep_list = m.group(1).split()
                deps[stage] = dep_list
            else:
                deps[stage] = []
        return deps

    def _parse_subnodes(self, config: str, stages: list) -> dict:
        subnodes = {}
        for stage in stages:
            m = re.search(rf'subnodes,{stage}\s+\{{([^}}]+)\}}', config)
            if m:
                subs = m.group(1).split()
                if subs == ['dynamic']:
                    # Dynamic stage (e.g., STA timing1) — resolve scenarios from user_config
                    subs = self._resolve_dynamic_subnodes(stage)
                subnodes[stage] = subs
        return subnodes

    def _resolve_dynamic_subnodes(self, stage: str) -> list:
        """Resolve dynamic subnodes for per-scenario/per-corner stages.

        Extraction stages → per-RC-corner (rc_max, rc_typ, rc_min)
        Timing stages     → per-MMMC-scenario
        """
        stage_base = re.sub(r'\d+(_\w+)?$', '', stage)

        # ── Extraction stages: dynamic per RC corner ──
        if stage_base == 'extraction':
            corners = self._resolve_rc_corners()
            if corners:
                return ['setup'] + corners + ['validate', 'finish']
            return ['setup', 'run', 'validate', 'finish']

        # ── Timing/other stages: dynamic per MMMC scenario ──
        scenarios = []
        user_config = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
        if os.path.exists(user_config):
            with open(user_config) as f:
                for line in f:
                    m = re.match(r'set\s+\w+\(mmmc,\w+_scenarios\)\s+"([^"]+)"', line.strip())
                    if m:
                        for s in m.group(1).split():
                            if s not in scenarios:
                                scenarios.append(s)
        if scenarios:
            return ['setup'] + scenarios + ['validate', 'finish']
        # Fallback: standard subnodes
        return ['setup', 'run', 'validate', 'finish']

    def _resolve_rc_corners(self) -> list:
        """Resolve RC corners for extraction dynamic subnodes.

        Priority:
          1. User override: sta(extraction,rc_corners) "rc_max rc_min" in user_config
          2. mmmc_config.tcl: rc_corner_list variable
          3. mmmc_config.tcl: rc_corners array keys
        """
        # Priority 1: user_config override
        user_config = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
        if os.path.exists(user_config):
            with open(user_config) as f:
                for line in f:
                    m = re.match(r'set\s+\w+\(extraction,rc_corners\)\s+"([^"]+)"', line.strip())
                    if m:
                        return m.group(1).split()

        # Priority 2+3: mmmc_config.tcl
        flow_dir = self.env_vars.get('FLOW_DIR', '')
        ver = self.env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0')
        mmmc_path = os.path.join(flow_dir, 'config', 'flow', ver, 'mmmc_config.tcl')
        if os.path.exists(mmmc_path):
            with open(mmmc_path) as f:
                content = f.read()
            # Priority 2: rc_corner_list variable
            m = re.search(r'set\s+rc_corner_list\s+\{([^}]+)\}', content)
            if m:
                return m.group(1).split()
            # Priority 3: rc_corners array keys
            corners = re.findall(r'^\s+(rc_\w+)\s+\{', content, re.MULTILINE)
            if corners:
                return corners

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

                # Determine subnodes based on node_type
                type_base = re.sub(r'\d+$', '', node_type) if node_type else name
                type_subnodes = ['setup', 'run', 'validate', 'finish']

                custom_nodes[name] = {
                    'type': node_type,
                    'dependency': dep,
                    'branch_key': branch,
                    'subnodes': type_subnodes,
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
        Tool info (vendor, name, version) comes from the flow's node config —
        NOT from env vars."""
        flow_dir = self.env_vars.get('FLOW_DIR', '')

        # Read tool info from node config (single source of truth)
        if not hasattr(self, '_tool_info'):
            self._tool_info = {'vendor': 'synopsys', 'name': 'fc', 'version': 'v1.0.0'}
            config = self._load_node_config()
            if config:
                m = re.search(r'tool,vendor\s+"([^"]+)"', config)
                if m:
                    self._tool_info['vendor'] = m.group(1)
                m = re.search(r'tool,name\s+"([^"]+)"', config)
                if m:
                    self._tool_info['name'] = m.group(1)
                m = re.search(r'tool,version\s+"([^"]+)"', config)
                if m:
                    self._tool_info['version'] = m.group(1)

        tool_vendor = self._tool_info['vendor']
        tool_name = self._tool_info['name']
        tool_version = self._tool_info['version']

        # Check node_types mapping in config (e.g., rtl1 → "inputs" uses inputs_subnode_handler.tcl)
        if not hasattr(self, '_node_types'):
            self._node_types = {}
            config = self._load_node_config()
            if config:
                for m in re.finditer(r'node_types,(\w+)\s+"([^"]+)"', config):
                    self._node_types[m.group(1)] = m.group(2)

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

    DB path structure: $project(race,db_path)/$project/$domain/$flow/$user_$run_$uid.db
    Example: /proj/phoenix/cbflow_db/phoenix/PD/SYNTH_PNR/vmerugu_run0_a3f2b1.db

    UID is a 6-char hex derived from run_dir absolute path — unique per run,
    deterministic (same run_dir always produces same UID), so the engine
    reconnects to the same DB on resume without creating duplicates.

    Falls back to $run_dir/.race_engine.db if project(race,db_path) not configured.
    """

    def __init__(self, run_dir: str, project_name: str = '', domain: str = 'PD',
                 flow_type: str = '', run_name: str = '', user: str = '',
                 db_base_path: str = ''):
        import hashlib
        # Generate deterministic 6-char UID from run_dir absolute path
        uid = hashlib.md5(os.path.abspath(run_dir).encode()).hexdigest()[:6]

        if db_base_path:
            user = user or os.environ.get('USER', 'unknown')
            db_dir = os.path.join(db_base_path, project_name, domain, flow_type)
            os.makedirs(db_dir, exist_ok=True)
            self.db_path = os.path.join(db_dir, f'{user}_{run_name}_{uid}.db')
        else:
            # Include run_name in local DB filename for identification
            if run_name:
                self.db_path = os.path.join(run_dir, f'.race_{run_name}_{uid}.db')
            else:
                self.db_path = os.path.join(run_dir, f'.race_{uid}.db')
        self._init_db()

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

        logger.info(f"RACE initialized: {len(self.jobs)} jobs, "
                     f"{len(self.stage_order)} stages")

        # Check DB session count against limit
        self._check_db_session_limit()
        return True

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
            warn_threshold = 8
            flow_dir = self.env_vars.get('FLOW_DIR', '')
            fc_path = os.path.join(flow_dir, 'config', 'flow',
                                   self.env_vars.get('FLOW_CONFIG_VERSION', 'v1.0.0'),
                                   'flow_config.tcl')
            if os.path.exists(fc_path):
                with open(fc_path) as f:
                    for line in f:
                        m = re.search(r'flow\(race,db_max_sessions\)\s+(\d+)', line)
                        if m: max_sessions = int(m.group(1))
                        m = re.search(r'flow\(race,db_warn_threshold\)\s+(\d+)', line)
                        if m: warn_threshold = int(m.group(1))

            # Count DBs in workarea
            workarea = os.path.dirname(self.run_dir)
            count = sum(1 for d in Path(workarea).iterdir()
                       if d.is_dir()
                       for _ in d.glob('.race_*.db'))

            if count >= max_sessions:
                logger.warning(f"RACE DB session limit reached ({count}/{max_sessions})! "
                              f"Run 'cbflow run db-manage --cleanup' to free sessions.")
            elif count >= warn_threshold:
                logger.warning(f"RACE DB sessions approaching limit ({count}/{max_sessions}). "
                              f"Consider: cbflow run db-manage --list")
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

        # Test mode delay — so GUI can observe status transitions
        import time as _time
        _time.sleep(5)

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
            result = subprocess.run(
                job.command, shell=True, env=run_env,
                cwd=self.run_dir, timeout=self._get_timeout(job))

            exit_code = result.returncode
            error_msg = ''

            if exit_code != 0:
                error_msg = f"Handler exited with code {exit_code}"

            self.db.record_complete(job, exit_code, error_msg)

            if exit_code == 0:
                logger.info(f"  [{job.stage}/{job.subnode}] done")
            else:
                logger.error(f"  [{job.stage}/{job.subnode}] FAILED (exit={exit_code})")

            return exit_code

        except subprocess.TimeoutExpired:
            self.db.record_complete(job, 124, 'Timeout exceeded')
            logger.error(f"  [{job.stage}/{job.subnode}] TIMEOUT")
            return 124
        except Exception as e:
            self.db.record_complete(job, 1, str(e))
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
        """Get timeout in seconds for a job from config."""
        # Default: 4 hours
        return 14400

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
