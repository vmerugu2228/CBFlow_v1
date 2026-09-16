#!/usr/bin/env python3
"""
CBflow Status Provider — SQLite-based status queries from RACE DB.
"""

import os
import hashlib
import sqlite3
from datetime import datetime
from pathlib import Path


class StageStatus:
    """Status constants."""
    READY = 'READY'
    PENDING = 'PENDING'
    RUNNING = 'RUNNING'
    DONE = 'DONE'
    FAIL = 'FAIL'
    SKIPPED = 'SKIPPED'
    INVALIDATED = 'INVALIDATED'


class StatusProvider:
    """Reads RACE SQLite database for job status.
    Provides: status, runtime, exit codes, LSF job IDs, hostname, error messages.

    DB found at:
      1. Structured: $project(engine,db_path)/$project/$domain/$flow/$user_$run_$uid.db
      2. Local: $run_dir/.race_$uid.db
    """

    DB_PREFIX = '.race_'

    def __init__(self, run_dir: str, db_path: str = None):
        self.run_dir = run_dir
        self.db_path = db_path or self._find_db(run_dir)

    def _find_db(self, run_dir: str) -> str:
        """Find the engine DB file for this run directory."""
        uid = hashlib.md5(os.path.abspath(run_dir).encode()).hexdigest()[:6]

        # Check local DB with UID
        local = os.path.join(run_dir, f'{self.DB_PREFIX}{uid}.db')
        if os.path.exists(local):
            return local

        # Check any .race_*.db in run_dir
        for f in Path(run_dir).glob(f'{self.DB_PREFIX}*.db'):
            return str(f)

        # Return expected path (may not exist yet — engine will create it)
        return local

    def _connect(self):
        if not os.path.exists(self.db_path):
            return None
        return sqlite3.connect(self.db_path)

    def get_stage_status(self, stage: str) -> dict:
        conn = self._connect()
        if not conn:
            return {'status': StageStatus.READY, 'timestamp': '', 'runtime': 0, 'exit_code': -1}
        try:
            cur = conn.execute(
                'SELECT status, start_time, end_time, runtime_sec, exit_code, lsf_job_id '
                'FROM jobs WHERE job_name = ? ORDER BY rowid DESC LIMIT 1', (stage,))
            row = cur.fetchone()
            if row:
                return {
                    'status': row[0], 'timestamp': row[2] or row[1] or '',
                    'runtime': row[3] or 0, 'exit_code': row[4] or 0,
                    'lsf_job_id': row[5] or '',
                }
            return {'status': StageStatus.READY, 'timestamp': '', 'runtime': 0, 'exit_code': -1}
        finally:
            conn.close()

    def get_all_status(self) -> dict:
        conn = self._connect()
        if not conn:
            return {}
        try:
            result = {}
            cur = conn.execute(
                "SELECT job_name, status, end_time, start_time, runtime_sec "
                "FROM jobs WHERE job_type = 'stage' "
                "AND id IN (SELECT MAX(id) FROM jobs GROUP BY job_name) "
                "ORDER BY id")
            for name, status, end, start, runtime in cur:
                result[name] = {
                    'status': status,
                    'timestamp': end or start or '',
                    'runtime': runtime or 0,
                }
            return result
        finally:
            conn.close()

    def get_subnode_status(self, stage: str, subnode: str) -> dict:
        conn = self._connect()
        if not conn:
            return {'status': StageStatus.READY, 'timestamp': ''}
        try:
            job_name = f'{stage}_{subnode}'
            cur = conn.execute(
                'SELECT status, end_time, start_time, runtime_sec FROM jobs '
                'WHERE job_name = ? ORDER BY rowid DESC LIMIT 1', (job_name,))
            row = cur.fetchone()
            if row:
                return {'status': row[0], 'timestamp': row[1] or row[2] or '', 'runtime': row[3] or 0}
            return {'status': StageStatus.READY, 'timestamp': ''}
        finally:
            conn.close()

    def get_completed_stages(self) -> list:
        conn = self._connect()
        if not conn:
            return []
        try:
            cur = conn.execute(
                "SELECT job_name FROM jobs "
                "WHERE job_type = 'stage' AND status IN ('DONE','BYPASSED','FORCE_VALIDATED') "
                "AND id IN (SELECT MAX(id) FROM jobs GROUP BY job_name) "
                "ORDER BY id")
            return [row[0] for row in cur]
        finally:
            conn.close()

    def get_stage_runtime(self, stage: str) -> float:
        info = self.get_stage_status(stage)
        return info.get('runtime', 0)

    def db_exists(self) -> bool:
        return os.path.exists(self.db_path)


def get_status_provider(run_dir: str = None) -> StatusProvider:
    """Return status provider for this run directory."""
    if run_dir is None:
        run_dir = os.getcwd()
    return StatusProvider(run_dir)
