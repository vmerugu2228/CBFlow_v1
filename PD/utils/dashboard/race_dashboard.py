#!/usr/bin/env python3
"""
RACE Dashboard — Lightweight web GUI for CBflow flow visualization.
Zero external dependencies — Python stdlib only (http.server + sqlite3).

Usage:
    cbflow run dashboard                  # Start at http://localhost:8080
    cbflow run dashboard --port 9090      # Custom port
    cbflow run dashboard --no-browser     # Don't auto-open browser

Provides:
    /           Dashboard overview (stage pipeline, progress, stats)
    /dag        DAG dependency graph (SVG)
    /grid       Job grid table (sortable, filterable)
    /api/status JSON run status
    /api/dag    JSON DAG structure
    /api/job/X  JSON job details
"""

import http.server
import json
import logging
import os
import re
import sqlite3
import sys
import threading
import webbrowser
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse, parse_qs

logger = logging.getLogger('cbflow.dashboard')

DASHBOARD_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATES_DIR = os.path.join(DASHBOARD_DIR, 'templates')
STATIC_DIR = os.path.join(DASHBOARD_DIR, 'static')
COMMANDS_DIR = os.path.join(os.path.dirname(DASHBOARD_DIR), 'commands')

# Ensure commands dir is importable
if COMMANDS_DIR not in sys.path:
    sys.path.insert(0, COMMANDS_DIR)

# Thread-safe execution state
_stop_event = threading.Event()
_engines_lock = threading.Lock()
_active_engines = []

# Config key → input type map (canonical, shared between dashboard and engine)
_INPUT_KEY_TO_TYPE = {
    'rtl_filelist': 'rtl', 'rtl_file': 'rtl',
    'sdc_func_file': 'sdc', 'sdc_file': 'sdc',
    'upf_file': 'upf',
    'netlist': 'netlist', 'netlist_golden': 'netlist_golden',
    'netlist_revised': 'netlist_revised',
    'def_file': 'def', 'gds_file': 'gds', 'spef_file': 'spef',
    'constraints': 'constraints', 'power_spec': 'power_spec',
}


class RaceDashboard:
    """Data provider — reads RACE SQLite DB + configs."""

    def __init__(self, run_dir: str):
        self.run_dir = run_dir
        self._env_cache = None
        self.db_path = self._find_db()
        self.flow_type = ''
        self._load_run_info()
        # Auto-initialize engine if DB doesn't exist yet (fresh run)
        if not os.path.exists(self.db_path):
            self._init_engine_full()

    # ── Environment & path helpers (single source of truth) ───────────────

    def _load_env(self) -> dict:
        """Load environment from .run.cbflow.env — cached after first call."""
        if self._env_cache is not None:
            return self._env_cache
        env = {}
        env_file = os.path.join(self.run_dir, '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('export ') and '=' in line:
                        kv = line[7:].split('=', 1)
                        env[kv[0]] = kv[1].strip('"')
        self._env_cache = env
        return env

    @property
    def flow_dir(self) -> str:
        """FLOW_DIR from cached env."""
        return self._load_env().get('FLOW_DIR', '')

    @property
    def node_config_path(self) -> str:
        """Path to flow's node_config.tcl file."""
        ver = self._load_env().get('FLOW_CONFIG_VERSION', 'v1.0.0')
        return os.path.join(self.flow_dir, 'config', 'flow', ver,
                            'node_configs', f'{self.flow_type}_config.tcl')

    # ── Engine creation (2 paths only) ────────────────────────────────────

    def _init_engine_full(self):
        """Initialize RACE engine on first GUI load to create the DB.
        Full init with reset_stale=True — called ONLY at startup."""
        try:
            env = self._load_env()
            flow_type = env.get('CBFLOW_FLOW_TYPE', '')
            if not flow_type:
                return
            from race_engine import RaceEngine
            engine = RaceEngine(self.run_dir, flow_type, env)
            engine.initialize()  # Full init (reset_stale=True default)
            self.db_path = self._find_db()
            self.flow_type = flow_type
        except Exception as e:
            logger.error(f"Engine init failed: {e}")
            import traceback
            traceback.print_exc()

    def _get_engine(self):
        """Get a lightweight RACE engine (reset_stale=False).
        Used by all API calls and action handlers — never resets active jobs."""
        from race_engine import RaceEngine
        engine = RaceEngine(self.run_dir, self.flow_type, self._load_env())
        engine.initialize(reset_stale=False)
        return engine

    # ── DB access ─────────────────────────────────────────────────────────

    def _find_db(self) -> str:
        import hashlib
        uid = hashlib.md5(os.path.abspath(self.run_dir).encode()).hexdigest()[:6]
        # Try new naming: .race_{run_name}_{uid}.db
        env = self._load_env()
        run_name = env.get('CBFLOW_RUN_NAME', '')
        if run_name:
            named = os.path.join(self.run_dir, f'.race_{run_name}_{uid}.db')
            if os.path.exists(named):
                return named
        # Try old naming: .race_{uid}.db
        local = os.path.join(self.run_dir, f'.race_{uid}.db')
        if os.path.exists(local):
            return local
        # Glob fallback
        for f in Path(self.run_dir).glob('.race_*.db'):
            return str(f)
        # Default for new DB creation
        if run_name:
            return os.path.join(self.run_dir, f'.race_{run_name}_{uid}.db')
        return local

    def _load_run_info(self):
        conn = self._connect()
        if not conn:
            return
        try:
            for key, val in conn.execute('SELECT key, value FROM run_info'):
                if key == 'flow_type':
                    self.flow_type = val
        finally:
            conn.close()

    def _connect(self):
        if not os.path.exists(self.db_path):
            return None
        return sqlite3.connect(self.db_path)

    # ── File change detection (single implementation) ───────────────────────

    def _check_source_changes(self):
        """Check if source input files changed since last completion — invalidate affected nodes."""
        try:
            conn = self._connect()
            if not conn:
                return

            # Skip check if any jobs are currently RUNNING (avoid race with execution)
            running = conn.execute(
                "SELECT COUNT(*) FROM jobs WHERE status = 'RUNNING' "
                "AND id IN (SELECT MAX(id) FROM jobs GROUP BY job_name)").fetchone()
            if running and running[0] > 0:
                conn.close()
                return

            # Read source file paths from user_config using canonical key map
            source_files = {}
            user_config = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
            if os.path.exists(user_config):
                with open(user_config) as f:
                    for line in f:
                        line = line.strip()
                        m = re.match(r'set\s+\w+\(input,(\w+)\)\s+"([^"]*)"', line)
                        if m and m.group(2):
                            input_type = _INPUT_KEY_TO_TYPE.get(m.group(1))
                            if input_type:
                                source_files.setdefault(input_type, []).append(m.group(2))

            if not source_files:
                conn.close()
                return

            # For each input node, check if source files changed or deleted
            import time as _time
            now_ts = _time.time()
            changed_stages = []
            for input_type, files in source_files.items():
                node_name = f'{input_type}1'
                cur = conn.execute(
                    "SELECT end_time, status FROM jobs WHERE job_name = ? "
                    "AND status IN ('DONE','BYPASSED','FORCE_VALIDATED') "
                    "ORDER BY id DESC LIMIT 1", (node_name,))
                row = cur.fetchone()
                if not row or not row[0]:
                    continue

                try:
                    done_time = datetime.fromisoformat(row[0]).timestamp()
                except (ValueError, TypeError):
                    continue

                # Skip recently force-validated jobs (within 30s) to avoid race condition
                if row[1] == 'FORCE_VALIDATED' and (now_ts - done_time) < 30:
                    continue

                for src in files:
                    try:
                        if not os.path.exists(src):
                            changed_stages.append(node_name)
                            break
                        elif os.path.getmtime(src) > done_time:
                            changed_stages.append(node_name)
                            break
                    except OSError:
                        pass

            # Invalidate changed nodes + downstream
            if changed_stages:
                for node in changed_stages:
                    conn.execute("UPDATE jobs SET status = 'INVALIDATED' WHERE job_name = ? AND status IN ('DONE','BYPASSED')", (node,))

                # BFS downstream using dependency edges from node config
                edges = self._get_dependency_edges()
                changed_set = set(changed_stages)
                queue = list(changed_set)
                visited = set(changed_set)
                while queue:
                    cur_stage = queue.pop(0)
                    for downstream in edges.get(cur_stage, []):
                        if downstream not in visited:
                            visited.add(downstream)
                            queue.append(downstream)
                            conn.execute(
                                "UPDATE jobs SET status = 'INVALIDATED' "
                                "WHERE stage = ? AND status IN ('DONE','BYPASSED')",
                                (downstream,))

                conn.commit()

            conn.close()
        except Exception as e:
            logger.debug(f"Source change check error: {e}")

    def _get_dependency_edges(self) -> dict:
        """Parse dependency edges from node config. Returns {parent: [children]}."""
        edges = {}
        nc_path = self.node_config_path
        # Also check runtime config for custom nodes
        rt_path = os.path.join(self.run_dir, 'setup', 'runtime_flow_config.tcl')
        for path in [nc_path, rt_path]:
            if path and os.path.exists(path):
                try:
                    with open(path) as f:
                        content = f.read()
                    for m in re.finditer(r'dependencies,(\w+)\s+\{([^}]*)\}', content):
                        stage = m.group(1)
                        for dep in m.group(2).split():
                            edges.setdefault(dep, []).append(stage)
                except OSError:
                    pass
        return edges

    def get_status(self) -> dict:
        # Run file change detection on each status poll (lightweight check)
        self._check_source_changes()

        conn = self._connect()
        if not conn:
            return {'run_info': {}, 'stages': [], 'summary': {}}
        try:
            # Run info from DB
            run_info = {}
            for key, val in conn.execute('SELECT key, value FROM run_info'):
                run_info[key] = val

            # Enrich with env data (single read, cached)
            env = self._load_env()
            if env.get('CBFLOW_DESIGN_NAME'):
                run_info['design_name'] = env['CBFLOW_DESIGN_NAME']
            if env.get('CBFLOW_PROJECT_PHASE'):
                run_info['phase'] = env['CBFLOW_PROJECT_PHASE']
            if env.get('CBFLOW_RUN_NAME'):
                run_info['run_name'] = env['CBFLOW_RUN_NAME']

            # Get tech node info — use TECH_NAME from run env, not glob all tech dirs
            if self.flow_dir:
                import glob as _glob
                tech_name = env.get('TECH_NAME', '')
                tech_version = env.get('TECH_VERSION', 'v1.0.0')
                if tech_name:
                    # Use the specific tech config for this run
                    tech_dirs = [os.path.join(self.flow_dir, 'config', 'tech', tech_name, tech_version, 'tech_config.tcl')]
                else:
                    # Fallback: glob (but this picks wrong tech)
                    tech_dirs = _glob.glob(os.path.join(self.flow_dir, 'config', 'tech', '*', '*/tech_config.tcl'))
                for tech_dir in tech_dirs:
                    try:
                        with open(tech_dir) as tf:
                            for line in tf:
                                if 'tech(node)' in line:
                                    m = re.search(r'"([^"]+)"', line)
                                    if m: run_info['tech_node'] = m.group(1)
                                elif 'tech(foundry)' in line:
                                    m = re.search(r'"([^"]+)"', line)
                                    if m: run_info['foundry'] = m.group(1)
                                elif 'tech(track,default)' in line and 'set ' in line:
                                    m = re.search(r'"([^"]+)"', line)
                                    if m and 'track_variant' not in run_info:
                                        run_info['track_variant'] = m.group(1)
                                elif 'tech(metal_stack_name)' in line:
                                    m = re.search(r'"([^"]+)"', line)
                                    if m: run_info['metal_stack'] = m.group(1)
                        break  # Use first tech config found
                    except Exception:
                        pass

                # Get tool info from node config
                nc_path = self.node_config_path
                if os.path.exists(nc_path):
                    with open(nc_path) as nf:
                        for line in nf:
                            if 'tool,vendor' in line:
                                m = re.search(r'"([^"]+)"', line)
                                if m: run_info['tool_vendor'] = m.group(1)
                            elif 'tool,name' in line:
                                m = re.search(r'"([^"]+)"', line)
                                if m: run_info['tool_name'] = m.group(1)

                # Get tool module from flow config
                ver = env.get('FLOW_CONFIG_VERSION', 'v1.0.0')
                fc_path = os.path.join(self.flow_dir, 'config', 'flow', ver, 'flow_config.tcl')
                tool_name = run_info.get('tool_name', '')
                if tool_name and os.path.exists(fc_path):
                    with open(fc_path) as ff:
                        for line in ff:
                            m = re.search(rf'flow\(tool_module,{re.escape(tool_name)}\)\s+"([^"]+)"', line)
                            if m:
                                run_info['tool_module'] = m.group(1)
                                break

            # Stage summary
            stages = []
            cur = conn.execute("""
                SELECT j.stage,
                    MAX(CASE WHEN j.job_type='stage' THEN j.status END) as stage_status,
                    COUNT(CASE WHEN o2.job_type='subnode' THEN 1 END) as total,
                    SUM(CASE WHEN o2.job_type='subnode' AND j.status IN ('DONE','BYPASSED','FORCE_VALIDATED') THEN 1 ELSE 0 END) as done,
                    SUM(CASE WHEN o2.job_type='subnode' AND j.status='FAIL' THEN 1 ELSE 0 END) as failed,
                    SUM(CASE WHEN o2.job_type='subnode' THEN j.runtime_sec ELSE 0 END) as runtime,
                    MIN(CASE WHEN o2.job_type='subnode' THEN j.start_time END) as started,
                    MAX(CASE WHEN o2.job_type='subnode' THEN j.end_time END) as ended,
                    SUM(CASE WHEN o2.job_type='subnode' AND j.status='RUNNING' THEN 1 ELSE 0 END) as running,
                    SUM(CASE WHEN o2.job_type='subnode' AND j.status='PENDING' THEN 1 ELSE 0 END) as pending,
                    SUM(CASE WHEN o2.job_type='subnode' AND j.status='INVALIDATED' THEN 1 ELSE 0 END) as invalidated
                FROM jobs j
                INNER JOIN (SELECT job_name, MAX(id) as mid FROM jobs GROUP BY job_name) g
                    ON j.job_name = g.job_name AND j.id = g.mid
                INNER JOIN job_order o2 ON j.job_name = o2.job_name
                WHERE j.stage IN (SELECT DISTINCT stage FROM job_order)
                GROUP BY j.stage ORDER BY (SELECT MIN(seq) FROM job_order o WHERE o.stage = j.stage)
            """)
            for row in cur:
                sentinel_status = row[1] or 'READY'
                total = row[2] or 0
                done = row[3] or 0
                failed = row[4] or 0

                # Compute progressive status from subnodes:
                # - Any FAIL → FAIL
                # - Any RUNNING → RUNNING
                # - Any PENDING → PENDING
                # - All DONE/BYPASSED/FORCE_VALIDATED → DONE (use sentinel)
                # - Some DONE, rest READY → RUNNING (partial progress)
                # - All READY → READY
                # - All INVALIDATED → INVALIDATED
                running_c = row[8] or 0
                pending_c = row[9] or 0
                invalidated_c = row[10] or 0

                if total == 0:
                    # Leaf node — use its own status directly
                    status = sentinel_status
                elif failed > 0:
                    status = 'FAIL'
                elif running_c > 0:
                    status = 'RUNNING'
                elif done == total and done > 0:
                    status = sentinel_status  # preserve DONE/BYPASSED/FORCE_VALIDATED
                elif done > 0 and pending_c > 0:
                    status = 'RUNNING'
                elif pending_c > 0:
                    status = 'PENDING'
                elif done > 0 and invalidated_c > 0:
                    status = 'PENDING'  # partial progress + invalidated
                elif invalidated_c > 0:
                    status = 'INVALIDATED'
                elif done > 0 and done < total:
                    status = 'RUNNING'
                else:
                    status = sentinel_status

                ready_count = max(0, total - done - failed - running_c - pending_c - invalidated_c)

                stages.append({
                    'name': row[0], 'status': status,
                    'jobs_total': total, 'jobs_done': done, 'jobs_failed': failed,
                    'jobs_running': running_c, 'jobs_pending': pending_c,
                    'jobs_invalidated': invalidated_c, 'jobs_ready': ready_count,
                    'runtime': round(row[5] or 0, 2),
                    'started': row[6] or '', 'ended': row[7] or '',
                })

            # Count running jobs from DB
            running = 0
            try:
                rc = conn.execute(
                    "SELECT COUNT(*) FROM jobs "
                    "WHERE id IN (SELECT MAX(id) FROM jobs GROUP BY job_name) "
                    "AND stage IN (SELECT DISTINCT stage FROM job_order) "
                    "AND status = 'RUNNING'").fetchone()
                running = rc[0] if rc else 0
            except Exception:
                pass

            # Summary
            total = sum(s['jobs_total'] for s in stages)
            done = sum(s['jobs_done'] for s in stages)
            failed = sum(s['jobs_failed'] for s in stages)
            invalidated = sum(1 for s in stages if s['status'] == 'INVALIDATED')
            ready = total - done - failed - running
            return {
                'run_info': run_info,
                'stages': stages,
                'summary': {
                    'total': total, 'done': done, 'failed': failed,
                    'running': running, 'ready': max(0, ready),
                    'invalidated': invalidated,
                    'stages_total': len(stages),
                    'stages_done': sum(1 for s in stages
                                       if s['status'] in ('DONE', 'BYPASSED', 'FORCE_VALIDATED')),
                }
            }
        finally:
            conn.close()

    def get_dag(self) -> dict:
        conn = self._connect()
        if not conn:
            return {'nodes': [], 'edges': []}
        try:
            nodes = []
            edges = []
            cur = conn.execute("""
                SELECT j.job_name, j.stage, j.subnode, j.job_type, j.status,
                       j.runtime_sec, j.exit_code, j.error_msg, j.command
                FROM jobs j
                INNER JOIN (SELECT job_name, MAX(id) as max_id
                            FROM jobs GROUP BY job_name) g
                ON j.job_name = g.job_name AND j.id = g.max_id
                INNER JOIN job_order o ON j.job_name = o.job_name
                ORDER BY o.seq
            """)
            for row in cur:
                nodes.append({
                    'id': row[0], 'stage': row[1], 'subnode': row[2],
                    'type': row[3], 'status': row[4] or 'READY',
                    'runtime': round(row[5] or 0, 2),
                    'exit_code': row[6], 'error': row[7] or '',
                })
            # Build stage order from job_order
            stage_order = []
            seen = set()
            for row in conn.execute("SELECT stage FROM job_order WHERE job_type = 'stage' ORDER BY seq"):
                if row[0] not in seen:
                    stage_order.append(row[0])
                    seen.add(row[0])

            # Build edges from actual stage dependencies (from engine DAG)
            # Read dependencies: each stage sentinel depends on prev stage sentinel
            stage_deps = {}
            try:
                from tcl_config_parser import _load_node_config
                nc = _load_node_config(self.flow_type)
                if nc:
                    for stage in stage_order:
                        dep_key = f'dependencies,{stage}'
                        raw = nc.get(dep_key, '')
                        if raw:
                            for d in raw.strip('{}').split():
                                d = d.strip()
                                if d and d in seen:
                                    edges.append({'from': d, 'to': stage})
                                    stage_deps.setdefault(stage, []).append(d)
                # Custom node deps from runtime config
                rtf = os.path.join(self.run_dir, 'setup', 'runtime_flow_config.tcl')
                if os.path.exists(rtf):
                    with open(rtf) as f:
                        rtc = f.read()
                    import re as _re
                    for m in _re.finditer(r'stages,(\w+),dependencies\s+(\w+)', rtc):
                        cname, cdep = m.group(1), m.group(2)
                        if cname in seen and cdep in seen:
                            edges.append({'from': cdep, 'to': cname})
                            stage_deps.setdefault(cname, []).append(cdep)
            except Exception:
                # Fallback: chain consecutive stages
                for i in range(1, len(stage_order)):
                    edges.append({'from': stage_order[i-1], 'to': stage_order[i]})

            # Add subnode-level edges from engine DAG (for parallel subnode layout)
            try:
                engine = self._get_engine()
                for name, job in engine.jobs.items():
                    if job.job_type == 'subnode' and job.deps:
                        for dep in job.deps:
                            # Only add intra-stage subnode deps (not cross-stage)
                            dep_job = engine.jobs.get(dep)
                            if dep_job and dep_job.stage == job.stage and dep_job.job_type == 'subnode':
                                edges.append({'from': dep, 'to': name})
            except Exception:
                pass

            # Identify base stages vs custom
            base_stages = []
            try:
                from tcl_config_parser import get_flow_stages
                base_stages = list(get_flow_stages(self.flow_type))
            except Exception:
                base_stages = list(stage_order)

            # Parse branch info from runtime_flow_config.tcl
            branch_info = {}  # {node_name: {branch_key, branch_name, tag}}
            branch_meta = {}  # {branch_key: {name, tag}}
            rtf = os.path.join(self.run_dir, 'setup', 'runtime_flow_config.tcl')
            if os.path.exists(rtf):
                try:
                    with open(rtf) as f:
                        rtc = f.read()
                    import re as _re
                    # Parse branch keys metadata
                    for m in _re.finditer(r'branch_keys,(\S+),name\s+"([^"]*)"', rtc):
                        bkey = m.group(1)
                        branch_meta.setdefault(bkey, {})['name'] = m.group(2)
                    for m in _re.finditer(r'branch_keys,(\S+),tag\s+"([^"]*)"', rtc):
                        bkey = m.group(1)
                        branch_meta.setdefault(bkey, {})['tag'] = m.group(2)
                    # Parse node → branch_key mappings
                    for m in _re.finditer(r'stages,(\w+),branch_key\s+(\S+)', rtc):
                        node, bkey = m.group(1), m.group(2)
                        meta = branch_meta.get(bkey, {})
                        branch_info[node] = {
                            'branch_key': bkey,
                            'branch_name': meta.get('name', ''),
                            'branch_tag': meta.get('tag', ''),
                        }
                except Exception:
                    pass

            return {'nodes': nodes, 'edges': edges, 'stage_order': stage_order,
                    'stage_deps': stage_deps, 'base_stages': base_stages,
                    'branch_info': branch_info}
        finally:
            conn.close()

    def get_job(self, job_name: str) -> dict:
        conn = self._connect()
        if not conn:
            return {}
        try:
            cur = conn.execute("""
                SELECT job_name, stage, subnode, job_type, status, command,
                       start_time, end_time, runtime_sec, exit_code,
                       lsf_job_id, lsf_queue, resource_tier, pid,
                       hostname, error_msg, retry_count
                FROM jobs WHERE job_name = ? ORDER BY id DESC LIMIT 1
            """, (job_name,))
            row = cur.fetchone()
            if not row:
                return {}
            result = {
                'name': row[0], 'stage': row[1], 'subnode': row[2],
                'type': row[3], 'status': row[4], 'command': row[5] or '',
                'start_time': row[6] or '', 'end_time': row[7] or '',
                'runtime': round(row[8] or 0, 2), 'exit_code': row[9],
                'lsf_job_id': row[10] or '', 'lsf_queue': row[11] or '',
                'resource_tier': row[12] or '', 'pid': row[13],
                'hostname': row[14] or '', 'error_msg': row[15] or '',
                'retry_count': row[16] or 0,
            }
            # Read log tail if available
            log_path = os.path.join(self.run_dir, 'work', self.flow_type,
                                     row[1], 'run', f'{row[1].rstrip("0123456789")}.log')
            if os.path.exists(log_path):
                try:
                    with open(log_path) as f:
                        lines = f.readlines()
                    result['log_tail'] = [l.rstrip() for l in lines[-50:]]
                except Exception:
                    result['log_tail'] = []
            else:
                result['log_tail'] = []
            return result
        finally:
            conn.close()

    def get_node_config(self) -> dict:
        """Get editable config per stage (LSF queue, memory, timeout, version)."""
        configs = {}
        # Read tool_launch_config for LSF mappings
        flow_dir = self.flow_dir

        # Read queue tiers from lsf_config.tcl (single source of truth)
        # and stage mappings from tool_launch_config.tcl
        queue_map = {}
        queue_resources = {}

        lsf_path = os.path.join(flow_dir, 'config', 'flow', 'v1.0.0', 'lsf_config.tcl')
        if os.path.exists(lsf_path):
            with open(lsf_path) as f:
                lsf_content = f.read()
            # Match both formats: array set block (key "val") and set lsf(key) "val"
            for m in re.finditer(r'queue_types,(\w+),(\w+)\s+"([^"]+)"', lsf_content):
                queue_resources.setdefault(m.group(1), {})[m.group(2)] = m.group(3)

        tlc_path = os.path.join(flow_dir, 'config', 'flow', 'v1.0.0', 'tool_launch_config.tcl')
        if os.path.exists(tlc_path):
            with open(tlc_path) as f:
                tlc = f.read()
            for m in re.finditer(r'flow_mapping,(\w+),(\w+)\)\s+"(\w+)"', tlc):
                queue_map[f'{m.group(1)}_{m.group(2)}'] = m.group(3)
            for m in re.finditer(r'queue_types,(\w+),(\w+)\)\s+"([^"]+)"', tlc):
                queue_resources.setdefault(m.group(1), {})[m.group(2)] = m.group(3)

        # Read node_config for timeouts
        conn = self._connect()
        stage_order = []
        if conn:
            try:
                cur = conn.execute("SELECT stage, MIN(seq) as s FROM job_order GROUP BY stage ORDER BY s")
                stage_order = [r[0] for r in cur]
            finally:
                conn.close()

        flow_lower = self.flow_type.lower()
        for stage in stage_order:
            stage_base = stage.rstrip('0123456789')
            tier = queue_map.get(f'{flow_lower}_{stage_base}', 'M')
            resources = queue_resources.get(tier, {})
            configs[stage] = {
                'lsf_queue': tier,
                'lsf_memory': resources.get('memory', '16GB'),
                'lsf_cpu': resources.get('cpu', '8'),
                'lsf_runtime': resources.get('runtime_limit', '4:00'),
                'timeout': '60',
                'tool_version': 'v1.0.0',
            }

            # Check for overrides (type-level then node-level, node wins)
            for override_name in [stage_base, stage]:
                override_file = os.path.join(self.run_dir, 'setup',
                                              f'override_config.{override_name}.tcl')
                if os.path.exists(override_file):
                    with open(override_file) as f:
                        for line in f:
                            if 'memory' in line:
                                m = re.search(r'"([^"]+)"', line)
                                if m: configs[stage]['lsf_memory'] = m.group(1)
                            if 'cpu' in line:
                                m = re.search(r'"([^"]+)"', line)
                                if m: configs[stage]['lsf_cpu'] = m.group(1)

        # Read timeouts from node_config
        flow_ver = 'v1.0.0'
        nc_path = os.path.join(flow_dir, 'config', 'flow', flow_ver,
                                'node_configs', f'{self.flow_type}_config.tcl')
        if os.path.exists(nc_path):
            with open(nc_path) as f:
                nc = f.read()
            for stage in stage_order:
                m = re.search(rf'runtime,timeout,{stage}\s+(\d+)', nc)
                if m:
                    configs[stage]['timeout'] = m.group(1)

        # Read tool module versions from flow_config (single source of truth)
        tool_modules = {}
        fc_path = os.path.join(flow_dir, 'config', 'flow', 'v1.0.0', 'flow_config.tcl')
        if os.path.exists(fc_path):
            with open(fc_path) as f:
                for line in f:
                    m = re.search(r'flow\(tool_module,(\w+)\)\s+"([^"]+)"', line)
                    if m:
                        tool_modules[m.group(1)] = m.group(2)

        # Get the tool name for this flow from node config
        flow_tool = ''
        if nc_path and os.path.exists(nc_path):
            with open(nc_path) as f:
                nc_content = f.read()
            m = re.search(r'tool,name\s+"([^"]+)"', nc_content)
            if m:
                flow_tool = m.group(1)

        # Set tool_module per stage
        for stage in stage_order:
            if flow_tool and flow_tool in tool_modules:
                configs[stage]['tool_module'] = tool_modules[flow_tool]
            # Check override
            stage_base = stage.rstrip('0123456789')
            override_file = os.path.join(self.run_dir, 'setup',
                                          f'override_config.{stage_base}.tcl')
            if os.path.exists(override_file):
                with open(override_file) as f:
                    for line in f:
                        if 'tool_module' in line:
                            m = re.search(r'"([^"]+)"', line)
                            if m: configs[stage]['tool_module'] = m.group(1)

        # Read available flow stages from node_config
        available_stages = stage_order

        return {
            'stages': configs,
            'queue_tiers': sorted(queue_resources.keys()),
            'queue_resources': queue_resources,
            'tool_modules': tool_modules,
            'flow_tool': flow_tool,
            'available_stages': available_stages,
            'flow_type': self.flow_type,
        }

    def get_node_full_config(self, stage: str) -> dict:
        """Get ALL config variables for a node from all config sources.
        Parses 6 config files, filters by node name/type, groups by category."""
        if not stage:
            return {'error': 'stage required', 'categories': {}}

        stage_base = re.sub(r'\d+(_\w+)?$', '', stage)
        flow_lower = self.flow_type.lower()
        flow_upper = self.flow_type.upper()
        ver = self._load_env().get('FLOW_CONFIG_VERSION', 'v1.0.0')
        config_dir = os.path.join(self.flow_dir, 'config', 'flow', ver)
        categories = {}  # {category_name: [{key, value, source}]}

        def _add(cat, key, value, source='config'):
            categories.setdefault(cat, []).append({
                'key': key, 'value': str(value).strip(), 'source': source})

        def _parse_array_keys(filepath, match_fn):
            """Parse TCL array set blocks, return matching key-value pairs."""
            results = []
            if not os.path.exists(filepath):
                return results
            with open(filepath) as f:
                content = f.read()
            for m in re.finditer(r'^\s+([\w,]+)\s+(?:\{([^}]*)\}|"([^"]*)"|([\w./\-]+))\s*$',
                                 content, re.MULTILINE):
                key = m.group(1)
                value = m.group(2) or m.group(3) or m.group(4) or ''
                if match_fn(key):
                    results.append((key, value.strip()))
            return results

        def _parse_set_stmts(filepath, match_fn):
            """Parse TCL set statements, return matching key-value pairs."""
            results = []
            if not os.path.exists(filepath):
                return results
            with open(filepath) as f:
                for line in f:
                    line = line.strip()
                    m = re.match(r'set\s+(\S+)\s+"([^"]*)"', line)
                    if m and match_fn(m.group(1)):
                        results.append((m.group(1), m.group(2)))
            return results

        # ── 1. Node Config (SYNTH_PNR_config.tcl) ──
        nc_path = self.node_config_path
        for key, val in _parse_array_keys(nc_path,
                lambda k: stage in k or stage_base in k):
            _add('Node Config', key, val)

        # ── 2. LSF & Resources (lsf_config.tcl + tool_launch_config.tcl) ──
        lsf_path = os.path.join(config_dir, 'lsf_config.tcl')
        tlc_path = os.path.join(config_dir, 'tool_launch_config.tcl')
        # Find queue tier for this node
        queue_tier = 'M'
        for key, val in _parse_array_keys(lsf_path,
                lambda k: flow_lower in k.lower() and stage_base in k.lower()):
            queue_tier = val
            _add('LSF & Resources', f'queue_tier ({stage_base})', val)
        for key, val in _parse_array_keys(tlc_path,
                lambda k: flow_lower in k.lower() and stage_base in k.lower()):
            if val != queue_tier:
                queue_tier = val
            _add('LSF & Resources', f'queue_mapping ({stage_base})', val)
        # Get queue tier details
        for key, val in _parse_array_keys(lsf_path,
                lambda k: k.startswith(f'queue_types,{queue_tier},')):
            prop = key.split(',')[-1]
            _add('LSF & Resources', f'{queue_tier}.{prop}', val)

        # ── 3. Tool Config (<tool>_config.tcl) ──
        # Find the tool config file from cmds/<flow>/<vendor>/<tool>/v1.0.0/<tool>_config.tcl
        tool_vendor = ''
        tool_name = ''
        nc_path2 = self.node_config_path
        if os.path.exists(nc_path2):
            with open(nc_path2) as f:
                for line in f:
                    if 'tool,vendor' in line:
                        m2 = re.search(r'"([^"]+)"', line)
                        if m2: tool_vendor = m2.group(1)
                    elif 'tool,name' in line:
                        m2 = re.search(r'"([^"]+)"', line)
                        if m2: tool_name = m2.group(1)

        if tool_vendor and tool_name:
            tool_config_dir = os.path.join(self.flow_dir, 'cmds', flow_upper,
                                           tool_vendor, tool_name, ver)
            tool_config_file = os.path.join(tool_config_dir, f'{tool_name}_config.tcl')
            if os.path.exists(tool_config_file):
                for key, val in _parse_array_keys(tool_config_file,
                        lambda k: stage_base in k or k.startswith('common,')):
                    _add('Tool Config', key, val, 'tool_config')
            # Also check for fc_config.tcl (Synopsys FC naming)
            elif os.path.exists(os.path.join(tool_config_dir, 'fc_config.tcl')):
                for key, val in _parse_array_keys(
                        os.path.join(tool_config_dir, 'fc_config.tcl'),
                        lambda k: stage_base in k or k.startswith('common,')):
                    _add('Tool Config', key, val, 'tool_config')

        # ── 3b. Flow Settings (flow_config.tcl) ──
        fc_path = os.path.join(config_dir, 'flow_config.tcl')
        for key, val in _parse_set_stmts(fc_path,
                lambda k: 'flow(use_lsf)' in k or 'flow(use_xterm)' in k or
                           'flow(tool_module' in k or 'flow(tool_name' in k or
                           'flow(tool_vendor' in k):
            _add('Flow Settings', key, val)

        # ── 4. Exit Criteria (release_config.tcl) ──
        rc_path = os.path.join(config_dir, 'release_config.tcl')
        stage_upper = stage_base.upper()
        for key, val in _parse_array_keys(rc_path,
                lambda k: flow_upper in k and stage_upper in k):
            _add('Exit Criteria', key, val)

        # ── 5. Apply overrides ──
        overrides = {}
        for pattern in [f'override_config.{stage_base}.tcl',
                        f'override_config.{stage}.tcl']:
            override_file = os.path.join(self.run_dir, 'setup', pattern)
            if os.path.exists(override_file):
                with open(override_file) as f:
                    for line in f:
                        line = line.strip()
                        m = re.match(r'set\s+(\S+)\s+"([^"]*)"', line)
                        if m:
                            overrides[m.group(1)] = m.group(2)

        # Mark overridden values
        for cat_vars in categories.values():
            for var in cat_vars:
                for okey, oval in overrides.items():
                    if var['key'] in okey or okey.endswith(var['key']):
                        var['value'] = oval
                        var['source'] = 'override'

        # Add override-only variables
        all_keys = {v['key'] for vs in categories.values() for v in vs}
        for okey, oval in overrides.items():
            if okey not in all_keys:
                _add('Overrides', okey, oval, 'override')

        return {
            'stage': stage,
            'stage_base': stage_base,
            'flow_type': self.flow_type,
            'categories': categories,
        }

    def get_mmmc_scenarios(self) -> dict:
        """Read MMMC config — all scenarios, scenario sets, and per-node assignments."""
        ver = self._load_env().get('FLOW_CONFIG_VERSION', 'v1.0.0')
        mmmc_path = os.path.join(self.flow_dir, 'config', 'flow', ver, 'mmmc_config.tcl')
        if not os.path.exists(mmmc_path):
            return {'error': 'mmmc_config.tcl not found', 'scenarios': [], 'nodes': {}, 'sets': {}}

        with open(mmmc_path) as f:
            content = f.read()

        # Parse all analysis views (the master list of available scenarios)
        all_scenarios = []
        for m in re.finditer(r'"([\w_]+)"\s*\{\s*corner\s+"(\w+)"\s*mode\s+"(\w+)"\s*voltage\s+([\d.]+)\s*temperature\s+([-\d]+)\s*analysis_type\s+"(\w+)"', content):
            all_scenarios.append({
                'name': m.group(1),
                'corner': m.group(2),
                'mode': m.group(3),
                'voltage': m.group(4),
                'temp': m.group(5),
                'type': m.group(6),
            })

        # Parse scenario sets
        sets = {}
        for m in re.finditer(r'(\w+)\s*\{\s*scenarios\s*\{([^}]*)\}\s*description\s*"([^"]*)"', content):
            set_name = m.group(1)
            scenarios = m.group(2).split()
            sets[set_name] = {'scenarios': scenarios, 'description': m.group(3)}

        # Parse per-node assignments
        nodes = {}
        # Match: node_name { setup {s1 s2} hold {h1 h2} }
        for m in re.finditer(r'(\w+)\s*\{\s*setup\s*\{([^}]*)\}\s*hold\s*\{([^}]*)\}', content):
            node = m.group(1)
            if node in ('setup', 'hold', 'power', 'signoff', 'all', 'sta_setup', 'sta_hold', 'sta_signoff'):
                continue  # skip scenario set names that match pattern
            setup_scenarios = m.group(2).split()
            hold_scenarios = m.group(3).split()
            nodes[node] = {'setup': setup_scenarios, 'hold': hold_scenarios}

        return {
            'scenarios': all_scenarios,
            'sets': sets,
            'nodes': nodes,
        }

    def get_input_vars(self, node_name: str) -> dict:
        """Get input variables for a leaf input node from user_config.tcl."""
        variables = {}
        node_base = node_name.rstrip('0123456789')  # rtl1 → rtl, sdc1 → sdc
        flow_lower = self.flow_type.lower()

        user_config = os.path.join(self.run_dir, 'setup', 'user_config.tcl')
        if os.path.exists(user_config):
            with open(user_config) as f:
                for line in f:
                    line = line.strip()
                    # Match patterns like: set synth_pnr(input,rtl_filelist) "path"
                    # or set sta(input,netlist) "path"
                    m = re.match(r'set\s+(\w+\([^)]*\))\s+"([^"]*)"', line)
                    if m:
                        key = m.group(1)
                        val = m.group(2)
                        # Check if this variable relates to this input node type
                        key_lower = key.lower()
                        if node_base in key_lower or f'input,{node_base}' in key_lower:
                            variables[key] = val
                        # Also match generic input variables (netlist, sdc, upf, etc.)
                        elif f'input,{node_base}_' in key_lower or f',{node_base}' in key_lower:
                            variables[key] = val

        return {'node': node_name, 'type': node_base, 'variables': variables}

    def get_all_jobs(self) -> list:
        conn = self._connect()
        if not conn:
            return []
        try:
            jobs = []
            cur = conn.execute("""
                SELECT j.job_name, j.stage, j.subnode, j.job_type, j.status,
                       j.runtime_sec, j.exit_code, j.hostname, j.lsf_job_id, j.error_msg
                FROM jobs j
                INNER JOIN (SELECT job_name, MAX(id) as max_id
                            FROM jobs GROUP BY job_name) g
                ON j.job_name = g.job_name AND j.id = g.max_id
                INNER JOIN job_order o ON j.job_name = o.job_name
                ORDER BY o.seq
            """)
            for row in cur:
                jobs.append({
                    'name': row[0], 'stage': row[1], 'subnode': row[2],
                    'type': row[3], 'status': row[4] or 'READY',
                    'runtime': round(row[5] or 0, 2), 'exit_code': row[6],
                    'hostname': row[7] or '', 'lsf_job_id': row[8] or '',
                    'error': row[9] or '',
                })
            return jobs
        finally:
            conn.close()


class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP request handler for RACE GUI."""

    dashboard = None  # Set by server

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/')

        if path == '' or path == '/':
            self._serve_template('dashboard.html')
        elif path == '/dag':
            self._serve_template('dag.html')
        elif path == '/grid':
            self._serve_template('grid.html')
        elif path == '/api/status':
            self._json_response(self.dashboard.get_status())
        elif path == '/api/dag':
            self._json_response(self.dashboard.get_dag())
        elif path == '/api/jobs':
            self._json_response(self.dashboard.get_all_jobs())
        elif path.startswith('/api/job/'):
            job_name = path[len('/api/job/'):]
            self._json_response(self.dashboard.get_job(job_name))
        elif path == '/api/node-config':
            self._json_response(self.dashboard.get_node_config())
        elif path.startswith('/api/node-full-config'):
            stage = parse_qs(parsed.query).get('stage', [''])[0]
            self._json_response(self.dashboard.get_node_full_config(stage))
        elif path == '/api/mmmc-scenarios':
            self._json_response(self.dashboard.get_mmmc_scenarios())
        elif path.startswith('/api/input-vars/'):
            node_name = path[len('/api/input-vars/'):]
            self._json_response(self.dashboard.get_input_vars(node_name))
        elif path.startswith('/static/'):
            self._serve_static(path[len('/static/'):])
        else:
            self.send_error(404)

    def do_POST(self):
        """Handle all GUI actions — node operations, config edits, execution."""
        parsed = urlparse(self.path)
        path = parsed.path.rstrip('/')
        body = self._read_body()

        try:
            if path == '/api/action/run':
                result = self._action_run(body)
            elif path == '/api/action/run-stage':
                result = self._action_run_stage(body)
            elif path == '/api/action/run-to-subnode':
                result = self._action_run_to_subnode(body)
            elif path == '/api/action/retrace':
                result = self._action_retrace(body)
            elif path == '/api/action/bypass':
                result = self._action_bypass(body)
            elif path == '/api/action/force':
                result = self._action_force(body)
            elif path == '/api/action/forcevalidate':
                result = self._action_forcevalidate(body)
            elif path == '/api/action/interactive':
                result = self._action_interactive(body)
            elif path == '/api/action/save-mmmc':
                result = self._action_save_mmmc(body)
            elif path == '/api/action/stop':
                result = self._action_stop(body)
            elif path == '/api/action/add-node':
                result = self._action_add_node(body)
            elif path == '/api/action/delete-node':
                result = self._action_delete_node(body)
            elif path == '/api/action/save-node-config':
                result = self._action_save_node_full_config(body)
            elif path == '/api/action/delete-branch':
                result = self._action_delete_branch(body)
            elif path == '/api/action/rename-node':
                result = self._action_rename_node(body)
            elif path == '/api/action/create-branch':
                result = self._action_create_branch(body)
            elif path == '/api/node-config':
                result = self._action_update_node_config(body)
            elif path.startswith('/api/input-vars/'):
                node_name = path[len('/api/input-vars/'):]
                result = self._action_save_input_vars(node_name, body)
            else:
                self._json_response({'error': f'Unknown action: {path}'}, 404)
                return
            self._json_response(result)
        except Exception as e:
            self._json_response({'error': str(e)}, 500)

    def _read_body(self) -> dict:
        length = int(self.headers.get('Content-Length', 0))
        if length > 0:
            return json.loads(self.rfile.read(length))
        return {}

    # ── Action Handlers ──────────────────────────────────────────────────

    def _action_run(self, body):
        """Run complete flow (cbflow run all)."""
        return self._exec_engine('all')

    def _action_run_stage(self, body):
        """Run specific stage."""
        stage = body.get('stage', '')
        if not stage:
            return {'error': 'stage required'}
        return self._exec_engine(stage)

    def _action_run_to_subnode(self, body):
        """Run up to a specific subnode only (not the full stage)."""
        stage = body.get('stage', '')
        subnode = body.get('subnode', '')
        if not stage or not subnode:
            return {'error': 'stage and subnode required'}

        def run():
            engine = self._get_engine()
            # Collect only the target subnode and its upstream deps within this stage
            target_jobs = set()
            target_jobs.add(subnode)
            # Walk deps upward
            visited = set()
            stack = [subnode]
            while stack:
                name = stack.pop()
                if name in visited:
                    continue
                visited.add(name)
                target_jobs.add(name)
                job = engine.jobs.get(name)
                if job:
                    for dep in job.deps:
                        stack.append(dep)
            engine.execute_jobs(target_jobs)

        t = threading.Thread(target=run, daemon=True)
        t.start()
        return {'ok': True, 'message': f'Running up to {subnode}', 'async': True}

    def _action_retrace(self, body):
        """Retrace from stage or all. Updates active engine if one is running."""
        from_stage = body.get('from_stage', '')
        # Use active running engine if available (so in-memory state is updated)
        engine = self._get_active_or_new_engine()
        if from_stage:
            engine.retrace(from_stage=from_stage)
            return {'ok': True, 'message': f'Retraced from {from_stage}'}
        else:
            engine.retrace()
            return {'ok': True, 'message': 'Full retrace complete'}

    def _action_bypass(self, body):
        """Bypass stages or specific jobs. Updates active engine if one is running."""
        engine = self._get_active_or_new_engine()
        jobs = body.get('jobs', [])
        if jobs:
            if isinstance(jobs, str):
                jobs = [jobs]
            engine.bypass_jobs(jobs)
            return {'ok': True, 'message': f'Bypassed: {", ".join(jobs)}'}
        stages = body.get('stages', [])
        if isinstance(stages, str):
            stages = [stages]
        engine.bypass(stages)
        return {'ok': True, 'message': f'Bypassed: {", ".join(stages)}'}

    def _action_force(self, body):
        """Force re-run stages (background thread)."""
        _stop_event.clear()
        stages = body.get('stages', [])
        if isinstance(stages, str):
            stages = [stages]

        def run():
            engine = self._get_engine()
            with _engines_lock:
                _active_engines.append(engine)
            try:
                engine.force(stages)
            finally:
                with _engines_lock:
                    if engine in _active_engines:
                        _active_engines.remove(engine)

        t = threading.Thread(target=run, daemon=True)
        t.start()
        return {'ok': True, 'message': f'Forcing: {", ".join(stages)}', 'async': True}

    def _action_interactive(self, body):
        """Launch interactive EDA tool session for a node."""
        node = body.get('node', '')
        if not node:
            return {'error': 'node required'}
        import subprocess
        run_dir = self.dashboard.run_dir
        cmd = ['cbflow', 'run', 'interactive', '--load', node]
        try:
            subprocess.Popen(cmd, cwd=run_dir)
            return {'ok': True, 'message': f'Interactive session launching for {node}'}
        except Exception as e:
            return {'error': f'Failed to launch: {e}'}

    def _action_save_mmmc(self, body):
        """Save MMMC scenario overrides to setup/override_config.<node>.tcl."""
        node = body.get('node', '')
        setup = body.get('setup', [])
        hold = body.get('hold', [])
        if not node:
            return {'error': 'node required'}

        override_path = os.path.join(self.dashboard.run_dir, 'setup',
                                      f'override_config.{node}.tcl')
        os.makedirs(os.path.dirname(override_path), exist_ok=True)

        # Read existing override — preserve ALL existing content,
        # only remove THIS node's mmmc lines (keep other nodes' mmmc settings)
        existing_lines = []
        if os.path.exists(override_path):
            with open(override_path) as f:
                for line in f:
                    # Only strip THIS node's mmmc scenario lines
                    if f'mmmc({node},' in line:
                        continue
                    existing_lines.append(line)

        flow_lower = self.dashboard.flow_type.lower()
        setup_str = ' '.join(setup)
        hold_str = ' '.join(hold)

        with open(override_path, 'w') as f:
            if existing_lines:
                f.writelines(existing_lines)
                if not existing_lines[-1].endswith('\n'):
                    f.write('\n')
            else:
                f.write(f'# CBflow override config for {node}\n')
                f.write(f'# Updated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n\n')

            f.write(f'# MMMC scenario assignments (from GUI)\n')
            f.write(f'set mmmc({node},setup_scenarios) "{setup_str}"\n')
            f.write(f'set mmmc({node},hold_scenarios) "{hold_str}"\n')

        return {'ok': True, 'message': f'MMMC override saved for {node}: {len(setup)} setup, {len(hold)} hold',
                'file': override_path}

    def _action_stop(self, body):
        """Stop all running engine executions."""
        _stop_event.set()
        with _engines_lock:
            engines = list(_active_engines)
        stopped = 0
        for engine in engines:
            engine._interrupted = True
            stopped += 1
        return {'ok': True, 'message': f'Stop signal sent to {stopped} running engine(s)'}

    def _action_forcevalidate(self, body):
        """Force-validate stages or specific jobs. Updates active engine if one is running."""
        engine = self._get_active_or_new_engine()
        jobs = body.get('jobs', [])
        if jobs:
            if isinstance(jobs, str):
                jobs = [jobs]
            engine.forcevalidate_jobs(jobs)
            return {'ok': True, 'message': f'Force-validated: {", ".join(jobs)}'}
        stages = body.get('stages', [])
        if isinstance(stages, str):
            stages = [stages]
        engine.forcevalidate(stages)
        return {'ok': True, 'message': f'Force-validated: {", ".join(stages)}'}

    def _action_add_node(self, body):
        """Add custom node. If auto_name=true, auto-generate next available name."""
        name = body.get('name', '')
        node_type = body.get('type', '')
        dep = body.get('dep', '')
        auto_name = body.get('auto_name', False)

        try:
            from node_manager import NodeManager
            mgr = NodeManager(self.dashboard.run_dir, self.dashboard.flow_type)

            if auto_name and node_type and dep:
                suffix = mgr._next_suffix(node_type)
                name = f"{node_type}{suffix}"

            if not name or not node_type or not dep:
                return {'error': 'name, type, dep required'}

            mgr.add_node(name, node_type, dep)
        except Exception as e:
            return {'error': f'Add node failed: {e}'}

        self._seed_new_nodes_only()
        return {'ok': True, 'message': f'Added node: {name} (dep={dep})'}

    def _action_delete_node(self, body):
        """Delete custom node."""
        name = body.get('name', '')
        if not name:
            return {'error': 'name required'}
        try:
            from node_manager import NodeManager
            mgr = NodeManager(self.dashboard.run_dir, self.dashboard.flow_type)

            # Check for dependents BEFORE attempting delete
            dependents = mgr._find_dependents(name)
            if dependents:
                return {'error': 'Cannot delete "' + name + '" -- these nodes depend on it: ' + ', '.join(dependents) + '. Delete them first.'}

            if not mgr.delete_node(name):
                return {'error': 'Cannot delete "' + name + '" -- it may be a base stage or not found.'}

            self._seed_new_nodes_only()
            return {'ok': True, 'message': f'Deleted node: {name}'}
        except Exception as e:
            return {'error': f'Delete node failed: {e}'}

    def _action_save_node_full_config(self, body):
        """Save edited config variables to override_config file.
        Scope: 'node' (this node), 'branch' (all branch nodes), 'type' (all nodes of this type)."""
        stage = body.get('stage', '')
        stage_base = body.get('stage_base', '') or re.sub(r'\d+(_\w+)?$', '', stage)
        branch_key = body.get('branch_key', '')
        scope = body.get('scope', 'node')
        variables = body.get('variables', {})
        if not stage or not variables:
            return {'error': 'stage and variables required'}

        flow_lower = self.dashboard.flow_type.lower()
        setup_dir = os.path.join(self.dashboard.run_dir, 'setup')
        os.makedirs(setup_dir, exist_ok=True)

        # Determine override filename based on scope
        # Override cascade in generate_setup.tcl (lowest → highest priority):
        #   override_config.tcl              (global)
        #   override_config.<flow>.tcl       (flow-level)
        #   override_config.<stage_base>.tcl (type-level, e.g., cts)
        #   override_config.<branch_name>.tcl (branch-level — all nodes in branch)
        #   override_config.<node>.tcl       (node-level, e.g., cts2)

        if scope == 'branch' and branch_key:
            # Resolve branch name from branch_key
            branch_name = ''
            rtf = os.path.join(setup_dir, 'runtime_flow_config.tcl')
            if os.path.exists(rtf):
                with open(rtf) as f:
                    rtc = f.read()
                m = re.search(rf'branch_keys,{re.escape(branch_key)},name\s+"([^"]*)"', rtc)
                if m:
                    branch_name = m.group(1)
            if not branch_name:
                branch_name = branch_key
            fname = f'override_config.{branch_name}.tcl'
        elif scope == 'type':
            fname = f'override_config.{stage_base}.tcl'
        else:
            fname = f'override_config.{stage}.tcl'

        # Build override content
        lines = [f'# Override config for {fname} ({self.dashboard.flow_type})']
        lines.append(f'# Scope: {scope} | Generated by CBflow Dashboard')
        lines.append('')
        for key, value in sorted(variables.items()):
            if '(' in key:
                lines.append(f'set {key} "{value}"')
            else:
                lines.append(f'set {flow_lower}({key}) "{value}"')
        lines.append('')
        content = '\n'.join(lines)

        # Write single override file
        with open(os.path.join(setup_dir, fname), 'w') as f:
            f.write(content)
        written = [fname]

        unique_files = list(set(written))
        return {'ok': True, 'message': f'Saved {len(variables)} variables to {", ".join(unique_files)} (scope: {scope})'}

    def _action_delete_branch(self, body):
        """Delete an entire branch by key. Blocks if external nodes depend on it."""
        branch_key = body.get('branch_key', '')
        if not branch_key:
            return {'error': 'branch_key required'}
        try:
            from node_manager import NodeManager
            mgr = NodeManager(self.dashboard.run_dir, self.dashboard.flow_type)

            branch_name = mgr.branches.get(branch_key, {}).get('name', branch_key)

            # Check for external dependents BEFORE attempting delete
            branch_nodes = set(n for n, info in mgr.custom_nodes.items()
                               if info.get('branch_key') == branch_key)
            ext_deps = []
            for node in branch_nodes:
                for name, info in mgr.custom_nodes.items():
                    if name not in branch_nodes and info.get('dependencies') == node:
                        ext_deps.append(f'"{name}" depends on "{node}"')

            if ext_deps:
                return {'error': 'Cannot delete branch "' + branch_name + '" -- other nodes depend on it: ' + '; '.join(ext_deps) + '. Delete the dependent nodes or branches first.'}

            if not mgr.delete_branch_by_key(branch_key):
                return {'error': 'Cannot delete branch "' + branch_name + '" -- branch not found or already deleted.'}

            self._seed_new_nodes_only()
            return {'ok': True, 'message': f'Branch "{branch_name}" deleted'}

        except Exception as e:
            return {'error': f'Delete branch failed: {e}'}

    def _action_rename_node(self, body):
        """Rename a custom node."""
        old_name = body.get('old_name', '')
        new_name = body.get('new_name', '')
        if not old_name or not new_name:
            return {'error': 'old_name and new_name required'}
        try:
            from node_manager import NodeManager
            mgr = NodeManager(self.dashboard.run_dir, self.dashboard.flow_type)
            if not mgr.rename_node(old_name, new_name):
                return {'error': f'Rename failed — check logs'}

            # Also rename in DB
            db_path = self.dashboard.db_path
            if os.path.exists(db_path):
                import sqlite3
                conn = sqlite3.connect(db_path)
                # Update job_order
                conn.execute("UPDATE job_order SET job_name=?, stage=? WHERE stage=? AND subnode='_sentinel'",
                             (new_name, new_name, old_name))
                conn.execute("UPDATE job_order SET stage=? WHERE stage=?", (new_name, old_name))
                conn.execute("UPDATE job_order SET job_name=REPLACE(job_name, ?, ?) WHERE job_name LIKE ?",
                             (old_name, new_name, f'{old_name}_%'))
                # Update jobs table
                conn.execute("UPDATE jobs SET stage=? WHERE stage=?", (new_name, old_name))
                conn.execute("UPDATE jobs SET job_name=? WHERE job_name=?", (new_name, old_name))
                conn.execute("UPDATE jobs SET job_name=REPLACE(job_name, ?, ?) WHERE job_name LIKE ?",
                             (old_name, new_name, f'{old_name}_%'))
                conn.commit()
                conn.close()
        except Exception as e:
            return {'error': f'Rename failed: {e}'}

        self._seed_new_nodes_only()
        return {'ok': True, 'message': f'Renamed: {old_name} → {new_name}'}

    def _action_create_branch(self, body):
        """Create flow branch."""
        name = body.get('name', '')
        from_stage = body.get('from_stage', '')
        if not name or not from_stage:
            return {'error': 'name and from_stage required'}
        try:
            from node_manager import NodeManager
            mgr = NodeManager(self.dashboard.run_dir, self.dashboard.flow_type)
            tag = body.get('tag', '')
            mgr.create_branch(name, from_stage, tag=tag)
        except Exception as e:
            return {'error': f'Create branch failed: {e}'}

        self._seed_new_nodes_only()
        return {'ok': True, 'message': f'Branch "{name}" created from {from_stage}'}

    def _action_update_node_config(self, body):
        """Update per-node config (LSF queue, memory, timeout, version)."""
        stage = body.get('stage', '')
        if not stage:
            return {'error': 'stage required'}

        # Write overrides to setup/override_config.<node>.tcl (per-node, not per-type)
        override_file = os.path.join(self.dashboard.run_dir, 'setup',
                                      f'override_config.{stage}.tcl')
        lines = []
        flow_lower = self.dashboard.flow_type.lower()

        if body.get('lsf_queue'):
            lines.append(f'set lsf(flow_mapping,{flow_lower},{stage.rstrip("0123456789")}) "{body["lsf_queue"]}"')
        if body.get('lsf_memory'):
            lines.append(f'set lsf(queue_types,{body.get("lsf_queue","M")},memory) "{body["lsf_memory"]}"')
        if body.get('lsf_cpu'):
            lines.append(f'set lsf(queue_types,{body.get("lsf_queue","M")},cpu) "{body["lsf_cpu"]}"')
        if body.get('timeout'):
            lines.append(f'set {flow_lower}(runtime,timeout,{stage}) "{body["timeout"]}"')
        if body.get('tool_version'):
            lines.append(f'set {flow_lower}(tool,version) "{body["tool_version"]}"')
        if body.get('tool_module'):
            lines.append(f'set flow(tool_module,{self._get_flow_tool()}) "{body["tool_module"]}"')

        if lines:
            os.makedirs(os.path.dirname(override_file), exist_ok=True)
            with open(override_file, 'w') as f:
                f.write(f'# RACE GUI config override for {stage}\n')
                f.write(f'# Updated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
                for line in lines:
                    f.write(line + '\n')

        return {'ok': True, 'message': f'Config updated for {stage}',
                'file': override_file, 'changes': lines}

    def _action_save_input_vars(self, node_name, body):
        """Save input variables to user_config.tcl."""
        variables = body.get('variables', {})
        if not variables:
            return {'error': 'No variables to save'}

        user_config = os.path.join(self.dashboard.run_dir, 'setup', 'user_config.tcl')
        if not os.path.exists(user_config):
            return {'error': 'user_config.tcl not found'}

        with open(user_config) as f:
            lines = f.readlines()

        # Update existing lines or append new ones
        updated_keys = set()
        for i, line in enumerate(lines):
            for key, val in variables.items():
                if key in line and line.strip().startswith('set '):
                    lines[i] = f'set {key} "{val}"\n'
                    updated_keys.add(key)

        # Append any new variables not found in existing file
        for key, val in variables.items():
            if key not in updated_keys:
                lines.append(f'set {key} "{val}"\n')

        with open(user_config, 'w') as f:
            f.writelines(lines)

        return {'ok': True, 'message': f'Input variables saved for {node_name} ({len(variables)} vars)'}

    def _seed_new_nodes_only(self):
        """Add new nodes to DB without disturbing existing job states.
        Only seeds missing jobs + updates job_order — no reset, no invalidation."""
        try:
            from race_engine import DagBuilder, StatusDB

            env = self.dashboard._load_env()
            builder = DagBuilder(self.dashboard.run_dir, self.dashboard.flow_type, env)
            jobs, stages = builder.build()
            if not jobs:
                return

            db_path = self.dashboard.db_path
            if not os.path.exists(db_path):
                return

            db = StatusDB.__new__(StatusDB)
            db.db_path = db_path
            db.save_job_order(jobs)
            db.seed_missing_jobs(jobs)
        except Exception as e:
            logger.debug(f"Seed new nodes error: {e}")

    def _get_flow_tool(self):
        """Get the tool name for this flow from node config."""
        try:
            nc_path = self.dashboard.node_config_path
            if os.path.exists(nc_path):
                with open(nc_path) as f:
                    for line in f:
                        m = re.search(r'tool,name\s+"([^"]+)"', line)
                        if m:
                            return m.group(1)
        except Exception as e:
            logger.debug(f"Get flow tool error: {e}")
        return 'fc'

    def _get_engine(self):
        """Get RACE engine via dashboard's lightweight init."""
        return self.dashboard._get_engine()

    def _get_active_or_new_engine(self):
        """Get the active running engine if one exists, otherwise create new.
        This ensures retrace/bypass/forcevalidate during execution update the
        SAME engine's in-memory state, not a throwaway copy."""
        with _engines_lock:
            if _active_engines:
                return _active_engines[0]
        return self._get_engine()

    def _exec_engine(self, target):
        """Execute a target via RACE engine in background thread."""
        _stop_event.clear()

        def run():
            engine = self._get_engine()
            with _engines_lock:
                _active_engines.append(engine)
            try:
                engine.execute(target)
            finally:
                with _engines_lock:
                    if engine in _active_engines:
                        _active_engines.remove(engine)

        t = threading.Thread(target=run, daemon=True)
        t.start()
        return {'ok': True, 'message': f'Executing: {target}', 'async': True}

    def _serve_template(self, name):
        filepath = os.path.join(TEMPLATES_DIR, name)
        if os.path.exists(filepath):
            with open(filepath, 'rb') as f:
                content = f.read()
            # Inject run info into template
            run_info = self.dashboard.get_status().get('run_info', {})
            content = content.replace(b'{{FLOW_TYPE}}', run_info.get('flow_type', '').encode())
            content = content.replace(b'{{PROJECT}}', run_info.get('project', '').encode())
            content = content.replace(b'{{RUN_DIR}}', self.dashboard.run_dir.encode())
            content = content.replace(b'{{RESULT}}', run_info.get('result', '').encode())
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_error(404, f'Template not found: {name}')

    def _serve_static(self, name):
        filepath = os.path.join(STATIC_DIR, name)
        if os.path.exists(filepath):
            with open(filepath, 'rb') as f:
                content = f.read()
            ctype = 'text/css' if name.endswith('.css') else \
                    'application/javascript' if name.endswith('.js') else \
                    'text/plain'
            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_error(404)

    def _json_response(self, data):
        body = json.dumps(data, default=str).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # Suppress access logs


def _file_watcher(dashboard):
    """Background thread that monitors source input files for changes every 1 second."""
    import time
    while True:
        try:
            dashboard._check_source_changes()
        except Exception:
            pass
        time.sleep(1)


def _find_free_port(start: int = 8080, end: int = 8180) -> int:
    """Find a free port in the given range."""
    import socket
    for port in range(start, end):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('0.0.0.0', port))
                return port
        except OSError:
            continue
    raise RuntimeError(f"No free port found in range {start}-{end}")


def start_dashboard(run_dir: str, port: int = 0, open_browser: bool = True):
    """Start the RACE Dashboard web server.

    Args:
        port: Port number. 0 = auto-find free port starting from 8080.
              Allows multiple users / runs to open dashboards simultaneously.
    """
    dashboard = RaceDashboard(run_dir)
    DashboardHandler.dashboard = dashboard

    # Auto-find free port if not specified or default
    if port == 0:
        port = _find_free_port()

    # Start file watcher thread for near-instant change detection
    watcher = threading.Thread(target=_file_watcher, args=(dashboard,), daemon=True)
    watcher.start()

    try:
        server = http.server.HTTPServer(('0.0.0.0', port), DashboardHandler)
    except OSError:
        # Requested port busy — auto-find a free one
        port = _find_free_port(port + 1)
        server = http.server.HTTPServer(('0.0.0.0', port), DashboardHandler)

    url = f'http://localhost:{port}'

    print(f'\n  RACE Dashboard')
    print(f'  {"=" * 50}')
    print(f'  URL:       {url}')
    print(f'  Run:       {os.path.basename(run_dir)}')
    print(f'  Flow:      {dashboard.flow_type}')
    print(f'  DB:        {os.path.basename(dashboard.db_path)}')
    print(f'  {"=" * 50}')
    print(f'  Press Ctrl+C to stop\n')

    if open_browser:
        threading.Timer(1.0, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\n  Dashboard stopped.')
        server.shutdown()
