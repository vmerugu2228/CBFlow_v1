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
import os
import re
import sqlite3
import threading
import webbrowser
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse, parse_qs

DASHBOARD_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATES_DIR = os.path.join(DASHBOARD_DIR, 'templates')
STATIC_DIR = os.path.join(DASHBOARD_DIR, 'static')

# Shared stop flag — set by GUI, checked by engine threads
_stop_flag = False
_active_engines = []  # engines running in background threads


class RaceDashboard:
    """Data provider — reads RACE SQLite DB."""

    def __init__(self, run_dir: str):
        self.run_dir = run_dir
        self.db_path = self._find_db()
        self.flow_type = ''
        self._load_run_info()
        # Auto-initialize engine if DB doesn't exist yet (fresh run)
        if not os.path.exists(self.db_path):
            self._auto_init_engine()

    def _auto_init_engine(self):
        """Initialize RACE engine on first GUI load to create the DB."""
        try:
            env = {}
            env_file = os.path.join(self.run_dir, '.run.cbflow.env')
            if os.path.exists(env_file):
                with open(env_file) as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith('export ') and '=' in line:
                            kv = line[7:].split('=', 1)
                            env[kv[0]] = kv[1].strip('"')
            flow_type = env.get('CBFLOW_FLOW_TYPE', '')
            if not flow_type:
                return
            import sys
            sys.path.insert(0, os.path.join(os.path.dirname(DASHBOARD_DIR), 'commands'))
            from race_engine import RaceEngine
            engine = RaceEngine(self.run_dir, flow_type, env)
            engine.initialize()
            self.db_path = self._find_db()
            self.flow_type = flow_type
        except Exception as e:
            import traceback
            traceback.print_exc()

    def _find_db(self) -> str:
        import hashlib
        uid = hashlib.md5(os.path.abspath(self.run_dir).encode()).hexdigest()[:6]
        local = os.path.join(self.run_dir, f'.race_{uid}.db')
        if os.path.exists(local):
            return local
        for f in Path(self.run_dir).glob('.race_*.db'):
            return str(f)
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

    def _get_engine_cached(self):
        """Get engine with DAG built (cached per request cycle)."""
        if hasattr(self, '_engine_cache') and self._engine_cache:
            return self._engine_cache
        import sys
        sys.path.insert(0, os.path.join(os.path.dirname(DASHBOARD_DIR), 'commands'))
        from race_engine import RaceEngine
        env = {}
        env_file = os.path.join(self.run_dir, '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('export ') and '=' in line:
                        kv = line[7:].split('=', 1)
                        env[kv[0]] = kv[1].strip('"')
        engine = RaceEngine(self.run_dir, self.flow_type, env)
        engine.initialize()
        self._engine_cache = engine
        return engine

    def get_status(self) -> dict:
        conn = self._connect()
        if not conn:
            return {'run_info': {}, 'stages': [], 'summary': {}}
        try:
            # Run info
            run_info = {}
            for key, val in conn.execute('SELECT key, value FROM run_info'):
                run_info[key] = val

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
                    status = 'DONE'
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
                import sys
                sys.path.insert(0, os.path.join(os.path.dirname(DASHBOARD_DIR), 'commands'))
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

            # Stages with no deps that aren't first — add dep on previous for layout
            for stage in stage_order:
                if stage not in stage_deps and stage != stage_order[0]:
                    pass  # No implicit edges — only real deps

            # Add subnode-level edges from engine DAG (for parallel subnode layout)
            try:
                engine = self._get_engine_cached()
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

            return {'nodes': nodes, 'edges': edges, 'stage_order': stage_order,
                    'stage_deps': stage_deps, 'base_stages': base_stages}
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
        flow_dir = os.environ.get('FLOW_DIR', '')
        if not flow_dir:
            env_file = os.path.join(self.run_dir, '.run.cbflow.env')
            if os.path.exists(env_file):
                with open(env_file) as f:
                    for line in f:
                        if 'FLOW_DIR=' in line:
                            flow_dir = line.split('=', 1)[1].strip().strip('"')
                            break

        tlc_path = os.path.join(flow_dir, 'config', 'flow', 'v1.0.0', 'tool_launch_config.tcl')
        queue_map = {}
        queue_resources = {}
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

            # Check for overrides
            override_file = os.path.join(self.run_dir, 'setup',
                                          f'override_config.{stage_base}.tcl')
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

        # Read tool versions from env
        env_file = os.path.join(self.run_dir, '.run.cbflow.env')
        tool_versions = {}
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if '_VERSION=' in line and 'export' in line:
                        kv = line.replace('export ', '').strip().split('=', 1)
                        if len(kv) == 2:
                            tool_versions[kv[0]] = kv[1].strip('"')

        # Read available flow stages from node_config
        available_stages = stage_order

        return {
            'stages': configs,
            'queue_tiers': sorted(queue_resources.keys()),
            'queue_resources': queue_resources,
            'tool_versions': tool_versions,
            'available_stages': available_stages,
            'flow_type': self.flow_type,
        }

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
            # Get editable node config (LSF, version, timeout per stage)
            self._json_response(self.dashboard.get_node_config())
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
            elif path == '/api/action/stop':
                result = self._action_stop(body)
            elif path == '/api/action/add-node':
                result = self._action_add_node(body)
            elif path == '/api/action/delete-node':
                result = self._action_delete_node(body)
            elif path == '/api/action/create-branch':
                result = self._action_create_branch(body)
            elif path == '/api/node-config':
                result = self._action_update_node_config(body)
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
        """Retrace from stage or all."""
        from_stage = body.get('from_stage', '')
        engine = self._get_engine()
        if from_stage:
            engine.retrace(from_stage=from_stage)
            return {'ok': True, 'message': f'Retraced from {from_stage}'}
        else:
            engine.retrace()
            return {'ok': True, 'message': 'Full retrace complete'}

    def _action_bypass(self, body):
        """Bypass stages or specific jobs."""
        engine = self._get_engine()
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
        global _stop_flag, _active_engines
        _stop_flag = False
        stages = body.get('stages', [])
        if isinstance(stages, str):
            stages = [stages]

        def run():
            global _active_engines
            engine = self._get_engine()
            _active_engines.append(engine)
            try:
                engine.force(stages)
            finally:
                if engine in _active_engines:
                    _active_engines.remove(engine)

        t = threading.Thread(target=run, daemon=True)
        t.start()
        return {'ok': True, 'message': f'Forcing: {", ".join(stages)}', 'async': True}

    def _action_stop(self, body):
        """Stop all running engine executions."""
        global _stop_flag, _active_engines
        _stop_flag = True
        stopped = 0
        for engine in _active_engines:
            engine._interrupted = True
            stopped += 1
        return {'ok': True, 'message': f'Stop signal sent to {stopped} running engine(s)'}

    def _action_forcevalidate(self, body):
        """Force-validate stages or specific jobs."""
        engine = self._get_engine()
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
        """Add custom node."""
        name = body.get('name', '')
        node_type = body.get('type', '')
        dep = body.get('dep', '')
        if not name or not node_type or not dep:
            return {'error': 'name, type, dep required'}
        # Write to runtime_flow_config.tcl
        import subprocess
        cmd = ['python3', '-c',
               f'import sys; sys.path.insert(0,"{os.path.dirname(DASHBOARD_DIR)}/commands"); '
               f'from node_manager import NodeManager; '
               f'mgr = NodeManager("{self.dashboard.run_dir}", "{self.dashboard.flow_type}"); '
               f'mgr.add_node("{name}", "{node_type}", "{dep}")']
        result = subprocess.run(cmd, cwd=self.dashboard.run_dir, capture_output=True, text=True)
        if result.returncode != 0:
            return {'error': f'Add node failed: {result.stderr.strip()}'}
        # Re-initialize engine so new node appears in DB
        try:
            engine = self._get_engine()
        except Exception as e:
            return {'error': f'Engine init failed: {e}'}
        return {'ok': True, 'message': f'Added node: {name} (dep={dep})'}

    def _action_delete_node(self, body):
        """Delete custom node."""
        name = body.get('name', '')
        if not name:
            return {'error': 'name required'}
        import subprocess
        cmd = ['python3', '-c',
               f'import sys; sys.path.insert(0,"{os.path.dirname(DASHBOARD_DIR)}/commands"); '
               f'from node_manager import NodeManager; '
               f'mgr = NodeManager("{self.dashboard.run_dir}", "{self.dashboard.flow_type}"); '
               f'mgr.delete_node("{name}")']
        subprocess.run(cmd, cwd=self.dashboard.run_dir, capture_output=True)
        # Re-initialize engine so DB reflects the change
        try:
            engine = self._get_engine()
        except Exception:
            pass
        return {'ok': True, 'message': f'Deleted node: {name}'}

    def _action_create_branch(self, body):
        """Create flow branch."""
        name = body.get('name', '')
        from_stage = body.get('from_stage', '')
        if not name or not from_stage:
            return {'error': 'name and from_stage required'}
        import subprocess
        cmd = ['python3', '-c',
               f'import sys; sys.path.insert(0,"{os.path.dirname(DASHBOARD_DIR)}/commands"); '
               f'from node_manager import NodeManager; '
               f'mgr = NodeManager("{self.dashboard.run_dir}", "{self.dashboard.flow_type}"); '
               f'mgr.create_branch("{name}", "{from_stage}")']
        subprocess.run(cmd, cwd=self.dashboard.run_dir, capture_output=True)
        # Re-initialize engine so DB reflects the change
        try:
            engine = self._get_engine()
        except Exception:
            pass
        return {'ok': True, 'message': f'Branch "{name}" created from {from_stage}'}

    def _action_update_node_config(self, body):
        """Update per-node config (LSF queue, memory, timeout, version)."""
        stage = body.get('stage', '')
        if not stage:
            return {'error': 'stage required'}

        # Write overrides to setup/override_config.<stage>.tcl
        override_file = os.path.join(self.dashboard.run_dir, 'setup',
                                      f'override_config.{stage.rstrip("0123456789")}.tcl')
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

        if lines:
            os.makedirs(os.path.dirname(override_file), exist_ok=True)
            with open(override_file, 'w') as f:
                f.write(f'# RACE GUI config override for {stage}\n')
                f.write(f'# Updated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
                for line in lines:
                    f.write(line + '\n')

        return {'ok': True, 'message': f'Config updated for {stage}',
                'file': override_file, 'changes': lines}

    def _get_engine(self):
        """Get or create RACE engine for this run."""
        import sys
        sys.path.insert(0, os.path.join(os.path.dirname(DASHBOARD_DIR), 'commands'))
        from race_engine import RaceEngine

        run_dir = self.dashboard.run_dir
        # Load env
        env = {}
        env_file = os.path.join(run_dir, '.run.cbflow.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('export ') and '=' in line:
                        kv = line[7:].split('=', 1)
                        env[kv[0]] = kv[1].strip('"')

        engine = RaceEngine(run_dir, self.dashboard.flow_type, env)
        engine.initialize()
        return engine

    def _exec_engine(self, target):
        """Execute a target via RACE engine in background thread."""
        global _stop_flag, _active_engines
        _stop_flag = False

        def run():
            global _active_engines
            engine = self._get_engine()
            _active_engines.append(engine)
            try:
                engine.execute(target)
            finally:
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


def start_dashboard(run_dir: str, port: int = 8080, open_browser: bool = True):
    """Start the RACE Dashboard web server."""
    dashboard = RaceDashboard(run_dir)
    DashboardHandler.dashboard = dashboard

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
