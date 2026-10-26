#!/usr/bin/env python3
"""
CBFlow Trending Command Handler

Historical trending, baseline management, and QoR regression analysis.
Tracks metrics across runs and compares against established baselines
to detect degradations in design quality.
"""

import argparse
import getpass
import json
import os
import re
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

from logging_config import configure_logging, get_logger

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir

logger = configure_logging('cbflow.trending')

KNOWN_METRICS = ['wns', 'tns', 'power', 'utilization', 'drc', 'cell_count',
                 'buffer_count', 'hold_wns', 'hold_tns', 'congestion',
                 'density', 'wirelength']
TREND_IMPROVED, TREND_DEGRADED, TREND_STABLE = 'IMPROVED', 'DEGRADED', 'STABLE'
LOWER_IS_BETTER = {'tns', 'drc', 'congestion', 'hold_tns'}
HIGHER_IS_BETTER = {'wns', 'hold_wns'}



def get_metrics_db_path() -> str:
    """Get the metrics database path."""
    core_dir = get_cbflow_core_dir()
    data_dir = os.path.join(core_dir, 'data')
    os.makedirs(data_dir, exist_ok=True)
    return os.path.join(data_dir, 'metrics.db')


class TrendingDB:
    """SQLite database interface for trending and baseline data."""

    SCHEMA = """
    CREATE TABLE IF NOT EXISTS qor_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT NOT NULL, flow_type TEXT, run_name TEXT, run_dir TEXT,
        milestone TEXT, metric_name TEXT NOT NULL, metric_value REAL,
        threshold REAL, status TEXT DEFAULT 'pass', phase TEXT,
        collected_at TEXT DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS baselines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT NOT NULL, flow_type TEXT NOT NULL,
        milestone TEXT NOT NULL, metric_name TEXT NOT NULL,
        baseline_value REAL NOT NULL, set_by TEXT,
        set_at TEXT DEFAULT CURRENT_TIMESTAMP, notes TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_qor_project ON qor_history(project);
    CREATE INDEX IF NOT EXISTS idx_qor_metric ON qor_history(metric_name);
    CREATE INDEX IF NOT EXISTS idx_qor_flow ON qor_history(flow_type);
    CREATE INDEX IF NOT EXISTS idx_qor_milestone ON qor_history(milestone);
    CREATE INDEX IF NOT EXISTS idx_baselines_project ON baselines(project);
    CREATE INDEX IF NOT EXISTS idx_baselines_flow ON baselines(flow_type);
    """

    def __init__(self, db_path: str = None):
        self.db_path = db_path or get_metrics_db_path()
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(self.SCHEMA)
        self.conn.commit()

    def close(self):
        self.conn.close()

    def insert_qor_record(self, **kwargs):
        """Insert a QoR history record."""
        cols = ', '.join(kwargs.keys())
        placeholders = ', '.join(['?' for _ in kwargs])
        self.conn.execute(f"INSERT INTO qor_history ({cols}) VALUES ({placeholders})",
                          list(kwargs.values()))
        self.conn.commit()

    def query_metric_history(self, project, metric_name, flow_type=None, last_n=None):
        """Query metric history for trending."""
        fc = "AND flow_type = ?" if flow_type else ""
        params = [project, metric_name] + ([flow_type] if flow_type else [])
        if last_n:
            params.append(last_n)
            query = f"""SELECT * FROM (
                SELECT id, project, flow_type, run_name, run_dir, milestone,
                       metric_name, metric_value, threshold, status, phase, collected_at
                FROM qor_history WHERE project = ? AND metric_name = ?
                {fc} ORDER BY collected_at DESC LIMIT ?
            ) sub ORDER BY collected_at ASC"""
        else:
            query = f"""SELECT id, project, flow_type, run_name, run_dir, milestone,
                metric_name, metric_value, threshold, status, phase, collected_at
                FROM qor_history WHERE project = ? AND metric_name = ?
                {fc} ORDER BY collected_at ASC"""
        return [dict(r) for r in self.conn.execute(query, params).fetchall()]

    def query_latest_metrics(self, project, run_dir=None, flow_type=None):
        """Query the latest metrics for a project/run."""
        if run_dir:
            q = """SELECT metric_name, metric_value, milestone, status, collected_at
                FROM qor_history WHERE project = ? AND run_dir = ? ORDER BY collected_at DESC"""
            params = [project, run_dir]
        else:
            q = """SELECT metric_name, metric_value, milestone, status, collected_at
                FROM qor_history WHERE project = ? AND collected_at = (
                    SELECT MAX(collected_at) FROM qor_history WHERE project = ?)"""
            params = [project, project]
        if flow_type:
            q = q.replace("ORDER BY", "AND flow_type = ? ORDER BY")
            params.append(flow_type)
        return [dict(r) for r in self.conn.execute(q, params).fetchall()]

    def query_all_metrics(self, project, flow_type=None, last_n=None):
        """Query all QoR records for aggregate stats."""
        q, p = "SELECT * FROM qor_history WHERE project = ?", [project]
        if flow_type:
            q += " AND flow_type = ?"; p.append(flow_type)
        q += " ORDER BY collected_at DESC"
        if last_n:
            q += " LIMIT ?"; p.append(last_n)
        return [dict(r) for r in self.conn.execute(q, p).fetchall()]

    def query_run_count(self, project, flow_type=None):
        """Count distinct runs for a project."""
        q, p = "SELECT COUNT(DISTINCT run_name) as cnt FROM qor_history WHERE project = ?", [project]
        if flow_type:
            q += " AND flow_type = ?"; p.append(flow_type)
        row = self.conn.execute(q, p).fetchone()
        return dict(row)['cnt'] if row else 0

    def set_baseline(self, project, flow_type, milestone, metric_name, value,
                     set_by=None, notes=None):
        """Set or update a baseline value."""
        existing = self.conn.execute(
            "SELECT id FROM baselines WHERE project=? AND flow_type=? AND milestone=? AND metric_name=?",
            [project, flow_type, milestone, metric_name]).fetchone()
        now = datetime.now().isoformat()
        if existing:
            self.conn.execute("UPDATE baselines SET baseline_value=?, set_by=?, set_at=?, notes=? WHERE id=?",
                              [value, set_by, now, notes, existing['id']])
        else:
            self.conn.execute(
                "INSERT INTO baselines (project,flow_type,milestone,metric_name,baseline_value,set_by,set_at,notes) VALUES (?,?,?,?,?,?,?,?)",
                [project, flow_type, milestone, metric_name, value, set_by, now, notes])
        self.conn.commit()
        action = "Updated" if existing else "Created"
        logger.info(f"{action} baseline for {metric_name} (milestone={milestone})")

    def query_baselines(self, project, flow_type=None, milestone=None):
        """Query baselines for a project."""
        q, p = "SELECT * FROM baselines WHERE project = ?", [project]
        if flow_type:
            q += " AND flow_type = ?"; p.append(flow_type)
        if milestone:
            q += " AND milestone = ?"; p.append(milestone)
        q += " ORDER BY flow_type, milestone, metric_name"
        return [dict(r) for r in self.conn.execute(q, p).fetchall()]


class QoRExtractor:
    """Extracts QoR metrics from run report files."""

    METRIC_PATTERNS = {
        'wns': [re.compile(r'WNS\s*[=:]\s*([+-]?\d+\.?\d*)', re.I),
                re.compile(r'worst\s+negative\s+slack\s*[=:]\s*([+-]?\d+\.?\d*)', re.I)],
        'tns': [re.compile(r'TNS\s*[=:]\s*([+-]?\d+\.?\d*)', re.I),
                re.compile(r'total\s+negative\s+slack\s*[=:]\s*([+-]?\d+\.?\d*)', re.I)],
        'power': [re.compile(r'total\s+power\s*[=:]\s*([+-]?\d+\.?\d*)', re.I),
                  re.compile(r'power\s*[=:]\s*([+-]?\d+\.?\d*)\s*[muW]', re.I)],
        'utilization': [re.compile(r'utilization\s*[=:]\s*([+-]?\d+\.?\d*)\s*%?', re.I),
                        re.compile(r'cell\s+utilization\s*[=:]\s*([+-]?\d+\.?\d*)', re.I)],
        'drc': [re.compile(r'total\s+DRC\s+violations?\s*[=:]\s*(\d+)', re.I),
                re.compile(r'DRC\s+count\s*[=:]\s*(\d+)', re.I),
                re.compile(r'number\s+of\s+DRC\s*[=:]\s*(\d+)', re.I)],
        'hold_wns': [re.compile(r'hold\s+WNS\s*[=:]\s*([+-]?\d+\.?\d*)', re.I)],
        'hold_tns': [re.compile(r'hold\s+TNS\s*[=:]\s*([+-]?\d+\.?\d*)', re.I)],
        'cell_count': [re.compile(r'cell\s+count\s*[=:]\s*(\d+)', re.I),
                       re.compile(r'number\s+of\s+cells?\s*[=:]\s*(\d+)', re.I)],
        'buffer_count': [re.compile(r'buffer\s+count\s*[=:]\s*(\d+)', re.I),
                         re.compile(r'number\s+of\s+buffers?\s*[=:]\s*(\d+)', re.I)],
    }
    REPORT_GLOBS = ['reports/**/qor*.rpt', 'reports/**/timing*.rpt',
                    'reports/**/*summary*.rpt', 'reports/**/*power*.rpt',
                    'reports/**/*drc*.rpt', 'reports/**/*utilization*.rpt',
                    'logs/**/qor*.log', 'rpt/**/qor*.rpt', 'rpt/**/*summary*.rpt']

    def extract_from_run(self, run_dir):
        """Extract all QoR metrics from a run directory."""
        run_path, metrics, report_files = Path(run_dir), {}, []
        for g in self.REPORT_GLOBS:
            report_files.extend(run_path.glob(g))
        if not report_files:
            report_files = list(run_path.rglob('*.rpt'))
        logger.debug(f"Found {len(report_files)} report files in {run_dir}")
        for rf in report_files:
            try:
                for n, v in self._parse_content(rf.read_text(errors='replace')).items():
                    metrics.setdefault(n, v)
            except Exception as e:
                logger.debug(f"  Could not parse {rf}: {e}")
        for jf in list(run_path.rglob('*qor*.json')) + list(run_path.rglob('*summary*.json')):
            try:
                for n, v in self._parse_json(json.loads(jf.read_text())).items():
                    metrics.setdefault(n, v)
            except Exception:
                pass
        return metrics

    def _parse_content(self, content):
        metrics = {}
        for name, patterns in self.METRIC_PATTERNS.items():
            for p in patterns:
                m = p.search(content)
                if m:
                    try: metrics[name] = float(m.group(1))
                    except ValueError: pass
                    break
        return metrics

    def _parse_json(self, data):
        metrics = {}
        if not isinstance(data, dict):
            return metrics
        for key, value in self._flatten(data).items():
            kl = key.lower().replace('-', '_').replace(' ', '_')
            for mn in KNOWN_METRICS:
                if mn in kl:
                    try: metrics[mn] = float(value)
                    except (ValueError, TypeError): pass
                    break
        return metrics

    @staticmethod
    def _flatten(d, prefix='', sep='.'):
        items = []
        for k, v in d.items():
            nk = f"{prefix}{sep}{k}" if prefix else k
            if isinstance(v, dict):
                items.extend(QoRExtractor._flatten(v, nk, sep).items())
            else:
                items.append((nk, v))
        return dict(items)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def parse_env_file(env_file):
    """Parse a .run.cbflow.env file."""
    env_vars = {}
    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('export ') and '=' in line:
                    key, val = line[7:].split('=', 1)
                    env_vars[key] = val.strip('"').strip("'")
    return env_vars


def determine_trend(current, previous, metric_name):
    """Return IMPROVED, DEGRADED, or STABLE based on metric semantics."""
    if previous == 0 and current == 0:
        return TREND_STABLE
    delta = current - previous
    if previous != 0 and abs(delta / previous) < 0.001:
        return TREND_STABLE
    if metric_name in LOWER_IS_BETTER:
        return TREND_IMPROVED if delta < 0 else TREND_DEGRADED
    elif metric_name in HIGHER_IS_BETTER:
        return TREND_IMPROVED if delta > 0 else TREND_DEGRADED
    return TREND_IMPROVED if delta < 0 else TREND_DEGRADED


def format_duration(seconds):
    if seconds > 3600: return f"{seconds/3600:.1f}h"
    if seconds > 60: return f"{seconds/60:.1f}m"
    return f"{seconds:.0f}s"


def trend_indicator(trend):
    return {'IMPROVED': '[IMPROVED]', 'DEGRADED': '[DEGRADED]'}.get(trend, '[STABLE]  ')


# ---------------------------------------------------------------------------
# Command handlers
# ---------------------------------------------------------------------------

def cmd_report(args):
    """Show trending report for a metric across runs."""
    project, metric = args.project, getattr(args, 'metric', 'wns')
    flow_type, last_n = getattr(args, 'flow', None), getattr(args, 'last', None)
    db = TrendingDB()
    try:
        history = db.query_metric_history(project, metric, flow_type, last_n)
        if not history:
            print(f"\n  No trending data for '{metric}' in '{project}'."
                  f"\n  Use 'cbflow flow trending record' first.\n")
            return 0
        flow_s = f"  |  Flow: {flow_type}" if flow_type else ""
        print(f"\n{'='*78}\n  CBFlow Trending Report"
              f"\n  Project: {project}  |  Metric: {metric}{flow_s}\n{'='*78}\n")
        print(f"  {'#':>3s}  {'Run Name':24s}  {'Value':>12s}  "
              f"{'Delta':>10s}  {'Trend':12s}  {'Date':19s}")
        print(f"  {'-'*3}  {'-'*24}  {'-'*12}  {'-'*10}  {'-'*12}  {'-'*19}")
        values = []
        for i, rec in enumerate(history):
            v = rec['metric_value']; values.append(v)
            rn = (rec['run_name'] or 'unknown')[:24]
            ds = (rec['collected_at'] or '')[:19]
            if i == 0:
                d_s, t_s = '---', '---'
            else:
                prev = history[i-1]['metric_value']
                d_s = f"{v - prev:+.4f}"
                t_s = trend_indicator(determine_trend(v, prev, metric))
            print(f"  {i+1:3d}  {rn:24s}  {v:12.4f}  {d_s:>10s}  {t_s:12s}  {ds}")
        if values:
            print(f"\n  {'-'*74}\n  Statistics ({len(values)} data points):")
            print(f"    Min:  {min(values):12.4f}\n    Max:  {max(values):12.4f}"
                  f"\n    Avg:  {sum(values)/len(values):12.4f}")
            if len(values) >= 2:
                print(f"    Overall trend: {determine_trend(values[-1], values[0], metric)}")
        print(f"{'='*78}\n")
    finally:
        db.close()
    return 0


def cmd_baseline_set(args):
    """Set a baseline value for a metric."""
    if args.metric not in KNOWN_METRICS:
        logger.warning(f"'{args.metric}' is not standard. Known: {', '.join(KNOWN_METRICS)}")
    db = TrendingDB()
    try:
        db.set_baseline(args.project, args.flow, args.milestone, args.metric,
                        args.value, getpass.getuser(), getattr(args, 'notes', None))
        print(f"  Baseline set: {args.metric} = {args.value} "
              f"(project={args.project}, flow={args.flow}, milestone={args.milestone})")
        if getattr(args, 'notes', None):
            print(f"  Notes: {args.notes}")
    finally:
        db.close()
    return 0


def cmd_baseline_show(args):
    """Show baselines for a project."""
    db = TrendingDB()
    try:
        baselines = db.query_baselines(args.project, milestone=getattr(args, 'milestone', None))
        if not baselines:
            print(f"\n  No baselines for '{args.project}'."
                  f"\n  Use 'cbflow flow trending baseline set' to define baselines.\n")
            return 0
        ms = getattr(args, 'milestone', None)
        ms_s = f"  |  Milestone: {ms}" if ms else ""
        print(f"\n{'='*78}\n  CBFlow Baselines - Project: {args.project}{ms_s}\n{'='*78}\n")
        print(f"  {'Flow':10s}  {'Milestone':12s}  {'Metric':16s}  "
              f"{'Value':>12s}  {'Set By':10s}  {'Date':19s}")
        print(f"  {'-'*10}  {'-'*12}  {'-'*16}  {'-'*12}  {'-'*10}  {'-'*19}")
        for bl in baselines:
            print(f"  {(bl['flow_type'] or '')[:10]:10s}  "
                  f"{(bl['milestone'] or '')[:12]:12s}  "
                  f"{(bl['metric_name'] or '')[:16]:16s}  "
                  f"{bl['baseline_value']:12.4f}  "
                  f"{(bl['set_by'] or '')[:10]:10s}  "
                  f"{(bl['set_at'] or '')[:19]}")
            if bl.get('notes'):
                print(f"  {'':10s}  {'':12s}  Notes: {bl['notes']}")
        print(f"{'='*78}\n")
    finally:
        db.close()
    return 0


def cmd_check(args):
    """Check latest run against baselines. Returns 1 if violations found."""
    project, run_dir = args.project, getattr(args, 'run_dir', None)
    threshold_pct = getattr(args, 'threshold_pct', 10.0)
    flow_type = getattr(args, 'flow', None)
    db = TrendingDB()
    try:
        baselines = db.query_baselines(project, flow_type=flow_type)
        if not baselines:
            logger.warning(f"No baselines for '{project}'. Nothing to check.")
            return 0
        current = {}
        if run_dir:
            latest = db.query_latest_metrics(project, run_dir=run_dir, flow_type=flow_type)
            current = {m['metric_name']: m['metric_value'] for m in latest} if latest \
                else QoRExtractor().extract_from_run(run_dir)
        else:
            for m in db.query_latest_metrics(project, flow_type=flow_type):
                current[m['metric_name']] = m['metric_value']
        if not current:
            logger.error("No current metrics available for comparison.")
            return 1
        print(f"\n{'='*78}\n  CBFlow Baseline Check - Project: {project}")
        if run_dir:
            print(f"  Run Dir: {run_dir}")
        print(f"  Threshold: {threshold_pct:.1f}%\n{'='*78}\n")
        print(f"  {'Milestone':12s}  {'Metric':16s}  {'Baseline':>12s}  "
              f"{'Current':>12s}  {'Delta%':>8s}  {'Result'}")
        print(f"  {'-'*12}  {'-'*16}  {'-'*12}  {'-'*12}  {'-'*8}  {'-'*10}")
        violations, checked = [], 0
        for bl in baselines:
            mn = bl['metric_name']
            if mn not in current:
                print(f"  {bl['milestone']:12s}  {mn:16s}  "
                      f"{bl['baseline_value']:12.4f}  {'N/A':>12s}  {'---':>8s}  SKIP")
                continue
            checked += 1
            bv, cv = bl['baseline_value'], current[mn]
            dp = ((cv - bv) / abs(bv) * 100) if bv != 0 else (0.0 if cv == 0 else 100.0)
            trend = determine_trend(cv, bv, mn)
            if trend == TREND_DEGRADED and abs(dp) > threshold_pct:
                result = 'FAIL'
                violations.append({'milestone': bl['milestone'], 'metric': mn,
                                   'baseline': bv, 'current': cv, 'delta_pct': dp})
            elif trend == TREND_DEGRADED:
                result = 'WARN'
            else:
                result = 'PASS'
            print(f"  {bl['milestone']:12s}  {mn:16s}  {bv:12.4f}  "
                  f"{cv:12.4f}  {dp:+7.1f}%  {result}")
        print(f"\n  {'-'*74}\n  Checked: {checked}  |  Violations: {len(violations)}"
              f"  |  Threshold: {threshold_pct:.1f}%")
        if violations:
            print(f"\n  DEGRADATION VIOLATIONS:")
            for v in violations:
                print(f"    - {v['metric']} at {v['milestone']}: "
                      f"{v['baseline']:.4f} -> {v['current']:.4f} ({v['delta_pct']:+.1f}%)")
        print(f"\n  Overall: {'FAIL' if violations else 'PASS'}\n{'='*78}\n")
    finally:
        db.close()
    return 1 if violations else 0


def cmd_record(args):
    """Record QoR metrics from a run into the qor_history table."""
    run_dir = getattr(args, 'run_dir', None) or os.getcwd()
    run_path = Path(run_dir)
    if not run_path.is_dir():
        logger.error(f"Run directory does not exist: {run_dir}")
        return 1
    env_vars = parse_env_file(run_path / '.run.cbflow.env')
    project = getattr(args, 'project', None) or env_vars.get('CBFLOW_PROJECT', '')
    flow_type = getattr(args, 'flow', None) or env_vars.get('CBFLOW_FLOW_TYPE', '')
    milestone = getattr(args, 'milestone', None) or env_vars.get('CBFLOW_PROJECT_PHASE', 'default')
    run_name = env_vars.get('CBFLOW_RUN_NAME', run_path.name)
    phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')
    if not project:
        logger.error("Cannot determine project. Use --project or set CBFLOW_PROJECT in .run.cbflow.env.")
        return 1
    metrics = QoRExtractor().extract_from_run(run_dir)
    if not metrics:
        logger.warning(f"No QoR metrics found in {run_dir}. Check reports/ or rpt/ directories.")
        return 0
    db = TrendingDB()
    now = datetime.now().isoformat()
    try:
        for mn, mv in metrics.items():
            db.insert_qor_record(project=project, flow_type=flow_type, run_name=run_name,
                                 run_dir=str(run_path), milestone=milestone, metric_name=mn,
                                 metric_value=mv, threshold=None, status='pass',
                                 phase=phase, collected_at=now)
        logger.info(f"Recorded {len(metrics)} metrics from {run_path.name} "
                    f"(project={project}, flow={flow_type})")
        print(f"\n  Recorded {len(metrics)} QoR metrics:")
        for n, v in sorted(metrics.items()):
            print(f"    {n:20s} = {v:.4f}")
        print()
    finally:
        db.close()
    return 0


def cmd_stats(args):
    """Show aggregate QoR statistics for a project."""
    project, flow_type = args.project, getattr(args, 'flow', None)
    last_n = getattr(args, 'last', None)
    db = TrendingDB()
    try:
        records = db.query_all_metrics(project, flow_type, last_n)
        if not records:
            print(f"\n  No QoR data for '{project}'. Use 'cbflow flow trending record' first.\n")
            return 0
        run_count = db.query_run_count(project, flow_type)
        metric_data = {}
        for rec in records:
            metric_data.setdefault(rec['metric_name'], []).append(rec['metric_value'])
        pass_count = sum(1 for r in records if r.get('status') == 'pass')
        total = len(records)
        pass_rate = (pass_count / total * 100) if total > 0 else 0
        milestone_data = {}
        for rec in records:
            ms = rec.get('milestone') or 'default'
            milestone_data.setdefault(ms, {}).setdefault(rec['metric_name'], []).append(rec['metric_value'])
        avg_dur = None
        try:
            dq, dp = "SELECT AVG(total_duration_seconds) as d FROM run_summary WHERE project=?", [project]
            if flow_type:
                dq += " AND flow_type=?"; dp.append(flow_type)
            dr = db.conn.execute(dq, dp).fetchone()
            if dr and dr['d'] is not None:
                avg_dur = dr['d']
        except Exception:
            pass
        fs = f"  |  Flow: {flow_type}" if flow_type else ""
        print(f"\n{'='*78}\n  CBFlow QoR Statistics - Project: {project}{fs}\n{'='*78}\n")
        print(f"  Overview:\n    Total distinct runs:   {run_count}"
              f"\n    Total metric records:  {total}"
              f"\n    Pass rate:             {pass_rate:.1f}% ({pass_count}/{total})")
        if avg_dur is not None:
            print(f"    Avg run duration:      {format_duration(avg_dur)}")
        print(f"\n  Metric Statistics:\n  {'-'*74}")
        print(f"  {'Metric':16s}  {'Count':>6s}  {'Min':>12s}  "
              f"{'Max':>12s}  {'Avg':>12s}  {'Trend'}")
        print(f"  {'-'*16}  {'-'*6}  {'-'*12}  {'-'*12}  {'-'*12}  {'-'*10}")
        for mn in sorted(metric_data):
            vals = metric_data[mn]
            cnt, avg_v = len(vals), sum(vals) / len(vals)
            trend = determine_trend(vals[0], vals[-1], mn) if cnt >= 2 else TREND_STABLE
            print(f"  {mn:16s}  {cnt:6d}  {min(vals):12.4f}  "
                  f"{max(vals):12.4f}  {avg_v:12.4f}  {trend}")
        if milestone_data:
            print(f"\n  Per-Milestone Summary:\n  {'-'*74}")
            for ms in sorted(milestone_data):
                print(f"  [{ms}]")
                for mn in sorted(milestone_data[ms]):
                    vals = milestone_data[ms][mn]
                    if mn in HIGHER_IS_BETTER:
                        best, worst = max(vals), min(vals)
                    else:
                        best, worst = min(vals), max(vals)
                    print(f"    {mn:16s}  best={best:12.4f}  worst={worst:12.4f}  ({len(vals)} samples)")
        print(f"\n{'='*78}\n")
    finally:
        db.close()
    return 0


# ---------------------------------------------------------------------------
# Argument parser and main
# ---------------------------------------------------------------------------

def create_parser():
    """Create argument parser for trending commands."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow trending',
        description='CBFlow Historical Trending and Baseline Analysis',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow trending report --project myproj --metric wns
  cbflow flow trending report --project myproj --metric drc --last 10
  cbflow flow trending baseline set --project myproj --flow PNR \\
      --milestone signoff --metric wns --value -0.050
  cbflow flow trending baseline show --project myproj
  cbflow flow trending check --project myproj --run-dir ./run_PNR_001
  cbflow flow trending record --run-dir ./run_PNR_001 --project myproj
  cbflow flow trending stats --project myproj --flow PNR --last 20
        """)
    sub = parser.add_subparsers(dest='command', help='Trending commands')

    rp = sub.add_parser('report', help='Show trending data for a metric')
    rp.add_argument('--project', required=True, help='Project name')
    rp.add_argument('--flow', help='Filter by flow type')
    rp.add_argument('--metric', default='wns',
                    help=f'Metric to trend. Known: {", ".join(KNOWN_METRICS)}')
    rp.add_argument('--last', type=int, help='Show only last N runs')

    bp = sub.add_parser('baseline', help='Manage baselines')
    bsub = bp.add_subparsers(dest='baseline_command', help='Baseline sub-commands')
    bs = bsub.add_parser('set', help='Set a baseline value')
    bs.add_argument('--project', required=True); bs.add_argument('--flow', required=True)
    bs.add_argument('--milestone', required=True); bs.add_argument('--metric', required=True)
    bs.add_argument('--value', required=True, type=float); bs.add_argument('--notes')
    bw = bsub.add_parser('show', help='Show baselines')
    bw.add_argument('--project', required=True); bw.add_argument('--milestone')

    cp = sub.add_parser('check', help='Check run against baselines')
    cp.add_argument('--project', required=True); cp.add_argument('--run-dir')
    cp.add_argument('--flow'); cp.add_argument('--threshold-pct', type=float, default=10.0)

    rc = sub.add_parser('record', help='Record QoR metrics from a run')
    rc.add_argument('--run-dir'); rc.add_argument('--project'); rc.add_argument('--flow')
    rc.add_argument('--milestone')

    sp = sub.add_parser('stats', help='Show aggregate QoR statistics')
    sp.add_argument('--project', required=True); sp.add_argument('--flow')
    sp.add_argument('--last', type=int)

    sub.add_parser('help', help='Show help')
    return parser


def main():
    """Main entry point for trending commands."""
    parser = create_parser()
    args = parser.parse_args()
    if not args.command or args.command == 'help':
        parser.print_help()
        return 0
    commands = {'report': cmd_report, 'check': cmd_check,
                'record': cmd_record, 'stats': cmd_stats}
    if args.command == 'baseline':
        bc = getattr(args, 'baseline_command', None)
        if not bc:
            parser.parse_args(['baseline', '--help'])
            return 0
        handlers = {'set': cmd_baseline_set, 'show': cmd_baseline_show}
        if bc in handlers:
            return handlers[bc](args)
        logger.error(f"Unknown baseline command: {bc}")
        return 1
    if args.command in commands:
        return commands[args.command](args)
    logger.error(f"Unknown command: {args.command}")
    return 1


if __name__ == '__main__':
    sys.exit(main())
