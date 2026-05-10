#!/usr/bin/env python3
"""
CBFlow Metrics Command Handler

Collects, stores, and reports run metrics including stage durations,
success rates, and resource usage.
"""

import argparse
import csv
import io
import json
import os
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.metrics')


def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


def get_metrics_db_path() -> str:
    """Get the metrics database path."""
    core_dir = get_cbflow_core_dir()
    data_dir = os.path.join(core_dir, 'data')
    os.makedirs(data_dir, exist_ok=True)
    return os.path.join(data_dir, 'metrics.db')


class MetricsDB:
    """SQLite database for metrics storage."""

    SCHEMA = """
    CREATE TABLE IF NOT EXISTS run_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT,
        flow_type TEXT,
        run_name TEXT,
        run_dir TEXT,
        stage TEXT,
        start_time TEXT,
        end_time TEXT,
        duration_seconds REAL,
        status TEXT,
        exit_code INTEGER,
        release_version TEXT,
        design_name TEXT,
        phase TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS run_summary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project TEXT,
        flow_type TEXT,
        run_name TEXT,
        run_dir TEXT,
        total_stages INTEGER,
        completed_stages INTEGER,
        failed_stages INTEGER,
        total_duration_seconds REAL,
        status TEXT,
        release_version TEXT,
        collected_at TEXT DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_run_metrics_flow ON run_metrics(flow_type);
    CREATE INDEX IF NOT EXISTS idx_run_metrics_stage ON run_metrics(stage);
    CREATE INDEX IF NOT EXISTS idx_run_metrics_project ON run_metrics(project);
    """

    def __init__(self, db_path: str = None):
        self.db_path = db_path or get_metrics_db_path()
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        self.init_schema()

    def init_schema(self):
        """Create tables if they don't exist."""
        self.conn.executescript(self.SCHEMA)
        self.conn.commit()

    def insert_stage_metric(self, **kwargs):
        """Insert a stage metric record."""
        cols = ', '.join(kwargs.keys())
        placeholders = ', '.join(['?' for _ in kwargs])
        self.conn.execute(
            f"INSERT INTO run_metrics ({cols}) VALUES ({placeholders})",
            list(kwargs.values())
        )
        self.conn.commit()

    def insert_run_summary(self, **kwargs):
        """Insert a run summary record."""
        cols = ', '.join(kwargs.keys())
        placeholders = ', '.join(['?' for _ in kwargs])
        self.conn.execute(
            f"INSERT INTO run_summary ({cols}) VALUES ({placeholders})",
            list(kwargs.values())
        )
        self.conn.commit()

    def query_stage_stats(self, flow_type: str = None, stage: str = None) -> list:
        """Query aggregate statistics for stages."""
        query = """
            SELECT flow_type, stage,
                   COUNT(*) as runs,
                   AVG(duration_seconds) as avg_duration,
                   MIN(duration_seconds) as min_duration,
                   MAX(duration_seconds) as max_duration,
                   SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as successes,
                   SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failures
            FROM run_metrics
            WHERE duration_seconds IS NOT NULL
        """
        params = []
        if flow_type:
            query += " AND flow_type = ?"
            params.append(flow_type)
        if stage:
            query += " AND stage = ?"
            params.append(stage)

        query += " GROUP BY flow_type, stage ORDER BY flow_type, stage"

        return [dict(row) for row in self.conn.execute(query, params).fetchall()]

    def query_run_summaries(self, project: str = None, limit: int = 20) -> list:
        """Query recent run summaries."""
        query = "SELECT * FROM run_summary"
        params = []
        if project:
            query += " WHERE project = ?"
            params.append(project)
        query += " ORDER BY collected_at DESC LIMIT ?"
        params.append(limit)

        return [dict(row) for row in self.conn.execute(query, params).fetchall()]

    def query_success_rate(self, flow_type: str = None) -> dict:
        """Calculate success rate."""
        query = """
            SELECT flow_type,
                   COUNT(*) as total,
                   SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as successes
            FROM run_metrics
        """
        params = []
        if flow_type:
            query += " WHERE flow_type = ?"
            params.append(flow_type)
        query += " GROUP BY flow_type"

        results = {}
        for row in self.conn.execute(query, params).fetchall():
            row = dict(row)
            total = row['total']
            successes = row['successes']
            results[row['flow_type']] = {
                'total': total,
                'successes': successes,
                'rate': (successes / total * 100) if total > 0 else 0
            }
        return results

    def close(self):
        self.conn.close()


class MetricsCollector:
    """Collects metrics from run directories."""

    def __init__(self, db: MetricsDB = None):
        self.db = db or MetricsDB()

    def collect_run_metrics(self, run_dir: str) -> dict:
        """Collect metrics from a run directory.

        Parses .run.cbflow.env, .stamps/ directory, and .run.status for timing data.
        """
        run_dir = Path(run_dir)
        metrics = {
            'run_dir': str(run_dir),
            'stages': [],
            'summary': {}
        }

        # Parse environment
        env_file = run_dir / '.run.cbflow.env'
        env_vars = self._parse_env_file(env_file)

        project = env_vars.get('CBFLOW_PROJECT', '')
        flow_type = env_vars.get('CBFLOW_FLOW_TYPE', '')
        run_name = env_vars.get('CBFLOW_RUN_NAME', run_dir.name)
        design_name = env_vars.get('CBFLOW_DESIGN_NAME', '')
        phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')
        release = env_vars.get('CBFLOW_RELEASE_VERSION', '')

        # Parse stamps for stage completion times
        stamps_dir = run_dir / '.stamps'
        if stamps_dir.exists():
            stamp_times = {}
            for stamp_file in sorted(stamps_dir.glob('*.stamp')):
                stage_name = stamp_file.stem
                stamp_times[stage_name] = stamp_file.stat().st_mtime

            # Calculate durations between stamps
            sorted_stamps = sorted(stamp_times.items(), key=lambda x: x[1])
            for i, (stage, mtime) in enumerate(sorted_stamps):
                end_time = datetime.fromtimestamp(mtime)
                if i > 0:
                    start_time = datetime.fromtimestamp(sorted_stamps[i-1][1])
                else:
                    # First stage - use env file mtime as start
                    if env_file.exists():
                        start_time = datetime.fromtimestamp(env_file.stat().st_mtime)
                    else:
                        start_time = end_time

                duration = (end_time - start_time).total_seconds()

                stage_metric = {
                    'project': project,
                    'flow_type': flow_type,
                    'run_name': run_name,
                    'run_dir': str(run_dir),
                    'stage': stage,
                    'start_time': start_time.isoformat(),
                    'end_time': end_time.isoformat(),
                    'duration_seconds': max(0, duration),
                    'status': 'completed',
                    'exit_code': 0,
                    'release_version': release,
                    'design_name': design_name,
                    'phase': phase,
                }

                metrics['stages'].append(stage_metric)
                self.db.insert_stage_metric(**stage_metric)

        # Parse .run.status for additional info
        status_file = run_dir / '.run.status'
        if status_file.exists():
            self._parse_status_file(status_file, metrics)

        # Create run summary
        total_stages = len(metrics['stages'])
        completed = sum(1 for s in metrics['stages'] if s['status'] == 'completed')
        failed = sum(1 for s in metrics['stages'] if s['status'] == 'failed')
        total_duration = sum(s['duration_seconds'] for s in metrics['stages'])

        summary = {
            'project': project,
            'flow_type': flow_type,
            'run_name': run_name,
            'run_dir': str(run_dir),
            'total_stages': total_stages,
            'completed_stages': completed,
            'failed_stages': failed,
            'total_duration_seconds': total_duration,
            'status': 'completed' if failed == 0 and total_stages > 0 else 'failed',
            'release_version': release,
        }
        metrics['summary'] = summary
        self.db.insert_run_summary(**summary)

        logger.info(f"Collected metrics from {run_dir.name}: "
                   f"{total_stages} stages, {total_duration:.0f}s total")

        return metrics

    def _parse_env_file(self, env_file: Path) -> dict:
        """Parse .run.cbflow.env file."""
        env_vars = {}
        if env_file.exists():
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('export ') and '=' in line:
                        key_val = line[7:]
                        key, val = key_val.split('=', 1)
                        env_vars[key] = val.strip('"').strip("'")
        return env_vars

    def _parse_status_file(self, status_file: Path, metrics: dict):
        """Parse .run.status file for warnings and errors."""
        try:
            with open(status_file, 'r') as f:
                content = f.read()

            warnings = content.count('WARNING')
            errors = content.count('ERROR')
            metrics['summary']['warnings'] = warnings
            metrics['summary']['errors'] = errors
        except Exception:
            pass


class MetricsReporter:
    """Generates metrics reports."""

    def __init__(self, db: MetricsDB = None):
        self.db = db or MetricsDB()

    def generate_report(self, project: str = None, flow_type: str = None) -> dict:
        """Generate a comprehensive metrics report."""
        report = {
            'generated_at': datetime.now().isoformat(),
            'stage_stats': self.db.query_stage_stats(flow_type=flow_type),
            'recent_runs': self.db.query_run_summaries(project=project),
            'success_rates': self.db.query_success_rate(flow_type=flow_type),
        }
        return report

    def format_report_text(self, report: dict) -> str:
        """Format report as human-readable text."""
        lines = []
        lines.append(f"")
        lines.append(f"{'═'*70}")
        lines.append(f"  CBFlow Metrics Report")
        lines.append(f"  Generated: {report['generated_at'][:19]}")
        lines.append(f"{'═'*70}")

        # Stage statistics
        stage_stats = report.get('stage_stats', [])
        if stage_stats:
            lines.append(f"")
            lines.append(f"  Stage Performance Statistics:")
            lines.append(f"  {'─'*65}")
            lines.append(f"  {'Flow':8s} {'Stage':20s} {'Runs':>5s} {'Avg(s)':>8s} "
                        f"{'Min(s)':>8s} {'Max(s)':>8s} {'Pass%':>6s}")
            lines.append(f"  {'─'*65}")

            for stat in stage_stats:
                total = stat['successes'] + stat['failures']
                pass_rate = (stat['successes'] / total * 100) if total > 0 else 0
                lines.append(f"  {stat['flow_type']:8s} {stat['stage']:20s} "
                           f"{stat['runs']:5d} {stat['avg_duration']:8.1f} "
                           f"{stat['min_duration']:8.1f} {stat['max_duration']:8.1f} "
                           f"{pass_rate:5.1f}%")

        # Success rates
        success_rates = report.get('success_rates', {})
        if success_rates:
            lines.append(f"")
            lines.append(f"  Overall Success Rates:")
            lines.append(f"  {'─'*40}")
            for flow, rates in sorted(success_rates.items()):
                lines.append(f"  {flow:12s} {rates['rate']:5.1f}% "
                           f"({rates['successes']}/{rates['total']})")

        # Recent runs
        recent_runs = report.get('recent_runs', [])
        if recent_runs:
            lines.append(f"")
            lines.append(f"  Recent Runs (last {len(recent_runs)}):")
            lines.append(f"  {'─'*65}")
            lines.append(f"  {'Flow':8s} {'Run Name':20s} {'Stages':>7s} "
                        f"{'Duration':>10s} {'Status':>10s}")
            lines.append(f"  {'─'*65}")

            for run in recent_runs:
                duration = run.get('total_duration_seconds', 0)
                if duration > 3600:
                    dur_str = f"{duration/3600:.1f}h"
                elif duration > 60:
                    dur_str = f"{duration/60:.1f}m"
                else:
                    dur_str = f"{duration:.0f}s"

                lines.append(f"  {run.get('flow_type', ''):8s} "
                           f"{run.get('run_name', '')[:20]:20s} "
                           f"{run.get('completed_stages', 0):>3d}/"
                           f"{run.get('total_stages', 0):<3d} "
                           f"{dur_str:>10s} {run.get('status', ''):>10s}")

        if not stage_stats and not recent_runs:
            lines.append(f"")
            lines.append(f"  No metrics data available yet.")
            lines.append(f"  Run 'cbflow flow metrics collect' from a run directory to start collecting.")

        lines.append(f"")
        lines.append(f"{'═'*70}")
        lines.append(f"")
        return '\n'.join(lines)


def cmd_collect(args: argparse.Namespace) -> int:
    """Collect metrics from run directory."""
    run_dir = getattr(args, 'run_dir', None) or os.getcwd()

    # Check if it's a run directory
    run_path = Path(run_dir)
    if not (run_path / '.run.cbflow.env').exists() and not (run_path / '.stamps').exists():
        # Try to collect from all subdirectories
        sub_runs = [d for d in run_path.iterdir()
                   if d.is_dir() and (d / '.run.cbflow.env').exists()]
        if not sub_runs:
            logger.error("No run directories found")
            return 1

        collector = MetricsCollector()
        for sub_run in sub_runs:
            try:
                collector.collect_run_metrics(str(sub_run))
            except Exception as e:
                logger.warning(f"Failed to collect from {sub_run.name}: {e}")
        collector.db.close()
        logger.info(f"Collected metrics from {len(sub_runs)} run directories")
        return 0

    collector = MetricsCollector()
    try:
        collector.collect_run_metrics(run_dir)
    except Exception as e:
        logger.error(f"Failed to collect metrics: {e}")
        return 1
    finally:
        collector.db.close()

    return 0


def cmd_report(args: argparse.Namespace) -> int:
    """Generate metrics report."""
    project = getattr(args, 'project', None)
    flow_type = getattr(args, 'flow', None)

    db = MetricsDB()
    reporter = MetricsReporter(db)

    try:
        report = reporter.generate_report(project=project, flow_type=flow_type)
        output = reporter.format_report_text(report)
        print(output)
    finally:
        db.close()

    return 0


def cmd_export(args: argparse.Namespace) -> int:
    """Export metrics data."""
    fmt = getattr(args, 'format', 'json')
    output_file = getattr(args, 'output', None)

    db = MetricsDB()

    try:
        stage_stats = db.query_stage_stats()
        run_summaries = db.query_run_summaries(limit=100)

        if fmt == 'json':
            data = {
                'exported_at': datetime.now().isoformat(),
                'stage_statistics': stage_stats,
                'run_summaries': run_summaries,
            }
            content = json.dumps(data, indent=2, default=str)
        elif fmt == 'csv':
            output = io.StringIO()
            if stage_stats:
                writer = csv.DictWriter(output, fieldnames=stage_stats[0].keys())
                writer.writeheader()
                writer.writerows(stage_stats)
            content = output.getvalue()
        else:
            logger.error(f"Unknown format: {fmt}")
            return 1

        if output_file:
            with open(output_file, 'w') as f:
                f.write(content)
            logger.info(f"Exported to: {output_file}")
        else:
            print(content)

    finally:
        db.close()

    return 0


def create_parser() -> argparse.ArgumentParser:
    """Create argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow metrics',
        description='CBFlow Metrics and Analytics',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow metrics collect                    Collect from current directory
  cbflow flow metrics collect --run-dir ./P0_run_PNR_test
  cbflow flow metrics report                     Show metrics report
  cbflow flow metrics report --flow PNR          Filter by flow type
  cbflow flow metrics export --format json       Export as JSON
  cbflow flow metrics export --format csv -o metrics.csv
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='Metrics commands')

    # collect command
    collect_parser = subparsers.add_parser('collect', help='Collect metrics from run directory')
    collect_parser.add_argument('--run-dir', help='Run directory path (default: current directory)')

    # report command
    report_parser = subparsers.add_parser('report', help='Generate metrics report')
    report_parser.add_argument('--project', help='Filter by project')
    report_parser.add_argument('--flow', help='Filter by flow type')

    # export command
    export_parser = subparsers.add_parser('export', help='Export metrics data')
    export_parser.add_argument('--format', choices=['json', 'csv'], default='json',
                              help='Export format')
    export_parser.add_argument('--output', '-o', help='Output file path')

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
        'collect': cmd_collect,
        'report': cmd_report,
        'export': cmd_export,
    }

    if args.command in commands:
        return commands[args.command](args)

    return 1


if __name__ == '__main__':
    sys.exit(main())
