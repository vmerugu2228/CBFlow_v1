#!/usr/bin/env python3
"""
CBflow Status Provider — Abstraction for stage/job status queries.
Supports stamp-based (Make) and SQLite-based (cbflow-engine) backends.
"""

import os
import re
import sqlite3
from abc import ABC, abstractmethod
from datetime import datetime
from pathlib import Path


class StageStatus:
    """Status constants."""
    PENDING = 'PENDING'
    RUNNING = 'RUNNING'
    DONE = 'DONE'
    FAIL = 'FAIL'
    SKIPPED = 'SKIPPED'


class StatusProvider(ABC):
    """Abstract status query interface."""

    @abstractmethod
    def get_stage_status(self, stage: str) -> dict:
        """Returns {status, timestamp, runtime, exit_code, ...}"""

    @abstractmethod
    def get_all_status(self) -> dict:
        """Returns {stage_name: {status, timestamp}, ...}"""

    @abstractmethod
    def get_subnode_status(self, stage: str, subnode: str) -> dict:
        """Returns status for a specific subnode."""

    @abstractmethod
    def get_completed_stages(self) -> list:
        """Return list of completed stage names."""

    @abstractmethod
    def get_stage_runtime(self, stage: str) -> float:
        """Return runtime in seconds for a stage (0 if not available)."""


class StampStatusProvider(StatusProvider):
    """Reads .stamps/ directory for stage completion status.
    This is the existing Make-based status mechanism."""

    def __init__(self, run_dir: str):
        self.run_dir = run_dir
        self.stamps_dir = os.path.join(run_dir, '.stamps')

    def get_stage_status(self, stage: str) -> dict:
        stamp = os.path.join(self.stamps_dir, f'{stage}.stamp')
        if os.path.exists(stamp):
            mtime = os.path.getmtime(stamp)
            return {
                'status': StageStatus.DONE,
                'timestamp': datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S'),
                'runtime': 0,
                'exit_code': 0,
            }
        return {'status': StageStatus.PENDING, 'timestamp': '', 'runtime': 0, 'exit_code': -1}

    def get_all_status(self) -> dict:
        result = {}
        if not os.path.isdir(self.stamps_dir):
            return result
        for stamp_file in sorted(Path(self.stamps_dir).glob('*.stamp')):
            # Only top-level stage stamps (not subnode stamps with _)
            name = stamp_file.stem
            if '_' not in name or name.endswith('1'):
                mtime = stamp_file.stat().st_mtime
                result[name] = {
                    'status': StageStatus.DONE,
                    'timestamp': datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S'),
                }
        return result

    def get_subnode_status(self, stage: str, subnode: str) -> dict:
        stamp = os.path.join(self.stamps_dir, f'{stage}_{subnode}.stamp')
        if os.path.exists(stamp):
            mtime = os.path.getmtime(stamp)
            return {
                'status': StageStatus.DONE,
                'timestamp': datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S'),
            }
        return {'status': StageStatus.PENDING, 'timestamp': ''}

    def get_completed_stages(self) -> list:
        if not os.path.isdir(self.stamps_dir):
            return []
        completed = []
        for stamp_file in sorted(Path(self.stamps_dir).glob('*.stamp')):
            name = stamp_file.stem
            if '_' not in name or name.endswith('1'):
                completed.append(name)
        return completed

    def get_stage_runtime(self, stage: str) -> float:
        return 0  # Stamps don't track runtime


class SqliteStatusProvider(StatusProvider):
    """Reads cbflow-engine SQLite database for job status.
    Provides richer data: actual runtime, CPU/mem, LSF job ID, exit codes.

    DB path resolved from:
      1. $project(engine,db_path)/$project/$domain/$flow/$user_$run.db
      2. $run_dir/.cbflow_engine.db (fallback)
    """

    DB_NAME = '.cbflow_engine.db'

    def __init__(self, run_dir: str, db_path: str = None):
        self.run_dir = run_dir
        self.db_path = db_path or os.path.join(run_dir, self.DB_NAME)

    def _connect(self):
        if not os.path.exists(self.db_path):
            return None
        return sqlite3.connect(self.db_path)

    def get_stage_status(self, stage: str) -> dict:
        conn = self._connect()
        if not conn:
            return {'status': StageStatus.PENDING, 'timestamp': '', 'runtime': 0, 'exit_code': -1}
        try:
            cur = conn.execute(
                'SELECT status, start_time, end_time, exit_code, lsf_job_id '
                'FROM jobs WHERE job_name = ? ORDER BY rowid DESC LIMIT 1', (stage,))
            row = cur.fetchone()
            if row:
                status, start, end, exit_code, lsf_id = row
                runtime = 0
                if start and end:
                    try:
                        t0 = datetime.fromisoformat(start)
                        t1 = datetime.fromisoformat(end)
                        runtime = (t1 - t0).total_seconds()
                    except Exception:
                        pass
                return {
                    'status': status,
                    'timestamp': end or start or '',
                    'runtime': runtime,
                    'exit_code': exit_code or 0,
                    'lsf_job_id': lsf_id or '',
                }
            return {'status': StageStatus.PENDING, 'timestamp': '', 'runtime': 0, 'exit_code': -1}
        finally:
            conn.close()

    def get_all_status(self) -> dict:
        conn = self._connect()
        if not conn:
            return {}
        try:
            result = {}
            cur = conn.execute(
                'SELECT job_name, status, end_time, start_time '
                'FROM jobs WHERE job_type = "stage" ORDER BY rowid')
            for name, status, end, start in cur:
                result[name] = {
                    'status': status,
                    'timestamp': end or start or '',
                }
            return result
        finally:
            conn.close()

    def get_subnode_status(self, stage: str, subnode: str) -> dict:
        conn = self._connect()
        if not conn:
            return {'status': StageStatus.PENDING, 'timestamp': ''}
        try:
            job_name = f'{stage}_{subnode}'
            cur = conn.execute(
                'SELECT status, end_time, start_time FROM jobs '
                'WHERE job_name = ? ORDER BY rowid DESC LIMIT 1', (job_name,))
            row = cur.fetchone()
            if row:
                return {'status': row[0], 'timestamp': row[1] or row[2] or ''}
            return {'status': StageStatus.PENDING, 'timestamp': ''}
        finally:
            conn.close()

    def get_completed_stages(self) -> list:
        conn = self._connect()
        if not conn:
            return []
        try:
            cur = conn.execute(
                "SELECT job_name FROM jobs WHERE job_type = 'stage' AND status = 'DONE' ORDER BY rowid")
            return [row[0] for row in cur]
        finally:
            conn.close()

    def get_stage_runtime(self, stage: str) -> float:
        info = self.get_stage_status(stage)
        return info.get('runtime', 0)


def get_status_provider(run_dir: str = None) -> StatusProvider:
    """Factory: return best available status provider for this run directory.

    Checks for SQLite DB at:
      1. Structured path: $project(engine,db_path)/$project/$domain/$flow/$user_$run.db
      2. Local path: $run_dir/.cbflow_engine.db
      3. Falls back to stamps
    """
    if run_dir is None:
        run_dir = os.getcwd()

    # Check local DB first (fast path) — matches .cbflow_engine_*.db pattern
    import hashlib
    uid = hashlib.md5(os.path.abspath(run_dir).encode()).hexdigest()[:6]
    local_db_uid = os.path.join(run_dir, f'.cbflow_engine_{uid}.db')
    local_db_legacy = os.path.join(run_dir, SqliteStatusProvider.DB_NAME)
    if os.path.exists(local_db_uid):
        return SqliteStatusProvider(run_dir, db_path=local_db_uid)
    if os.path.exists(local_db_legacy):
        return SqliteStatusProvider(run_dir, db_path=local_db_legacy)

    # Check structured DB path from run env
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if os.path.exists(env_file):
        project = flow_type = run_name = ''
        with open(env_file) as f:
            for line in f:
                if 'CBFLOW_PROJECT_NAME=' in line:
                    project = line.split('=', 1)[1].strip().strip('"')
                elif 'CBFLOW_FLOW_TYPE=' in line:
                    flow_type = line.split('=', 1)[1].strip().strip('"')
                elif 'CBFLOW_RUN_NAME=' in line:
                    run_name = line.split('=', 1)[1].strip().strip('"')

        if project and flow_type and run_name:
            user = os.environ.get('USER', 'unknown')
            # Try to find db_base from project config (read from env)
            # For now, check common pattern
            for db_base_candidate in [
                os.environ.get('CBFLOW_ENGINE_DB_PATH', ''),
            ]:
                if db_base_candidate:
                    structured_db = os.path.join(db_base_candidate, project, 'PD',
                                                  flow_type, f'{user}_{run_name}.db')
                    if os.path.exists(structured_db):
                        return SqliteStatusProvider(run_dir, db_path=structured_db)

    # Fallback to stamps (Make mode)
    return StampStatusProvider(run_dir)
