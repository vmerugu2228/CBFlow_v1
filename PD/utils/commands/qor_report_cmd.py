#!/usr/bin/env python3
"""
CBFlow QoR (Quality of Results) Report Command Handler

Generates, compares, and summarizes QoR reports from PD run directories.
Extracts timing, power, area, congestion, DRC, LVS, and CTS metrics
from report files, compares against exit milestone thresholds, and
produces formatted reports in text, JSON, CSV, or HTML.
"""

import argparse
import csv
import io
import json
import os
import re
import sqlite3
import sys
try:
    from dataclasses import dataclass, field, asdict
except ImportError:
    raise ImportError("dataclasses required — run: pip install dataclasses (Python 3.6 backport)")
from datetime import datetime
from pathlib import Path
from typing import Optional

from logging_config import configure_logging, get_logger

import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.paths import get_cbflow_core_dir, get_flow_config_version

logger = configure_logging('cbflow.qor_report')


# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

from core.paths import CBFLOW_VERSION as VERSION

def _get_valid_milestones():
    """Scan exit config directory for available milestones."""
    exit_dir = os.path.join(os.environ.get('CBFLOW_CORE_DIR', ''), 'config', 'exit',
                           get_flow_config_version())
    if not os.path.isdir(exit_dir):
        return []
    skip = ('waiver_config.tcl', 'threshold_overrides.tcl', 'remediation_config.tcl')
    return sorted(f.replace('_config.tcl', '') for f in os.listdir(exit_dir)
                  if f.endswith('_config.tcl') and f not in skip)


def _get_milestone_stage_mapping():
    """Read MILESTONE_STAGE_MAPPING from release_config.tcl."""
    flow_dir = os.environ.get('FLOW_DIR', os.environ.get('CBFLOW_CORE_DIR', ''))
    version = get_flow_config_version()
    rc_path = os.path.join(flow_dir, 'config', 'flow', version, 'release_config.tcl')
    mapping = {}
    if os.path.exists(rc_path):
        with open(rc_path) as f:
            content = f.read()
        # Parse: array set MILESTONE_STAGE_MAPPING { FP_EXIT "init_design" ... }
        m = re.search(r'array\s+set\s+MILESTONE_STAGE_MAPPING\s+\{([^}]+)\}', content)
        if m:
            pairs = re.findall(r'(\w+)\s+"?(\w+)"?', m.group(1))
            mapping = dict(pairs)
    return mapping


# ─────────────────────────────────────────────────────────────────────────────
# Utility Helpers
# ─────────────────────────────────────────────────────────────────────────────


def get_exit_config_dir() -> str:
    """Get exit criteria config directory."""
    core_dir = get_cbflow_core_dir()
    version = get_flow_config_version()
    return os.path.join(core_dir, 'config', 'exit', version)


def parse_env_file(env_file: Path) -> dict:
    """Parse a .run.cbflow.env file into a dict."""
    env_vars = {}
    if env_file.exists():
        try:
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('export ') and '=' in line:
                        key_val = line[7:]
                        key, val = key_val.split('=', 1)
                        env_vars[key] = val.strip('"').strip("'")
        except Exception as e:
            logger.debug(f"Could not parse env file {env_file}: {e}")
    return env_vars


def safe_float(value: str, default=None) -> Optional[float]:
    """Safely parse a float from a string, stripping units."""
    if value is None:
        return default
    cleaned = re.sub(r'[a-zA-Z%]+$', '', str(value).strip())
    try:
        return float(cleaned)
    except (ValueError, TypeError):
        return default


# ─────────────────────────────────────────────────────────────────────────────
# QoR Metrics Data Structure
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class QoRMetrics:
    """Container for extracted QoR metrics from a run directory."""
    # Run identification
    run_dir: str = ""
    project: str = ""
    flow_type: str = ""
    run_name: str = ""
    phase: str = ""
    design_name: str = ""

    # Timing
    setup_wns: Optional[float] = None
    setup_tns: Optional[float] = None
    hold_wns: Optional[float] = None
    hold_tns: Optional[float] = None
    fep_count: Optional[int] = None

    # Area
    utilization: Optional[float] = None
    cell_count: Optional[int] = None

    # Power
    total_power: Optional[float] = None
    dynamic_power: Optional[float] = None
    leakage_power: Optional[float] = None
    clock_power: Optional[float] = None
    power_unit: str = "mW"

    # Physical quality
    drc_violations: Optional[int] = None
    lvs_match: Optional[int] = None       # 1 = match, 0 = mismatch
    max_congestion: Optional[float] = None
    overflow_count: Optional[int] = None

    # Clock tree quality
    clock_skew: Optional[float] = None
    insertion_delay: Optional[float] = None
    clock_coverage: Optional[float] = None

    # Metadata
    extracted_at: str = field(default_factory=lambda: datetime.now().isoformat())

    def to_dict(self) -> dict:
        return asdict(self)

    def get(self, key: str, default=None):
        return getattr(self, key, default)


# ─────────────────────────────────────────────────────────────────────────────
# Report File Parsers
# ─────────────────────────────────────────────────────────────────────────────

class ReportParser:
    """Extracts QoR metrics from EDA tool report files."""

    @staticmethod
    def _read_file_safe(filepath: Path) -> str:
        """Read file content, return empty string on failure."""
        try:
            if filepath.exists():
                with open(filepath, 'r', errors='replace') as f:
                    return f.read()
        except Exception as e:
            logger.debug(f"Could not read {filepath}: {e}")
        return ""

    @staticmethod
    def _search_numeric(content: str, patterns: list, as_int: bool = False):
        """Search content for patterns and extract the first numeric value found."""
        for pat in patterns:
            match = re.search(pat, content, re.IGNORECASE | re.MULTILINE)
            if match:
                try:
                    val = match.group(1).strip()
                    return int(float(val)) if as_int else safe_float(val)
                except (ValueError, IndexError):
                    continue
        return None

    @classmethod
    def extract_timing(cls, run_dir: Path) -> dict:
        """Extract timing metrics from reports/timing/ directory."""
        timing_dir = run_dir / 'reports' / 'timing'
        metrics = {}

        # Scan all files in the timing directory
        content_parts = []
        if timing_dir.is_dir():
            for rpt in sorted(timing_dir.glob('*.rpt')):
                content_parts.append(cls._read_file_safe(rpt))
            for rpt in sorted(timing_dir.glob('*.rpt.gz')):
                logger.debug(f"Skipping compressed file: {rpt}")
        content = '\n'.join(content_parts)

        if not content:
            return metrics

        # WNS (Worst Negative Slack)
        wns_patterns = [
            r'(?:wns|worst\s*negative\s*slack|worst\s*slack)\s*[=:]\s*([-\d.]+)',
            r'(?:setup\s*wns|setup\s*worst)\s*[=:]\s*([-\d.]+)',
            r'WNS\s*\((?:setup|SETUPF?)\)\s*[=:]\s*([-\d.]+)',
            r'^\s*WNS\s+([-\d.]+)',
        ]
        metrics['setup_wns'] = cls._search_numeric(content, wns_patterns)

        # TNS (Total Negative Slack)
        tns_patterns = [
            r'(?:tns|total\s*negative\s*slack|total\s*slack)\s*[=:]\s*([-\d.]+)',
            r'(?:setup\s*tns|setup\s*total)\s*[=:]\s*([-\d.]+)',
            r'TNS\s*\((?:setup|SETUPF?)\)\s*[=:]\s*([-\d.]+)',
            r'^\s*TNS\s+([-\d.]+)',
        ]
        metrics['setup_tns'] = cls._search_numeric(content, tns_patterns)

        # Hold WNS
        hold_wns_patterns = [
            r'(?:hold\s*wns|hold\s*worst\s*slack)\s*[=:]\s*([-\d.]+)',
            r'WNS\s*\((?:hold|HOLDF?)\)\s*[=:]\s*([-\d.]+)',
        ]
        metrics['hold_wns'] = cls._search_numeric(content, hold_wns_patterns)

        # Hold TNS
        hold_tns_patterns = [
            r'(?:hold\s*tns|hold\s*total\s*slack)\s*[=:]\s*([-\d.]+)',
            r'TNS\s*\((?:hold|HOLDF?)\)\s*[=:]\s*([-\d.]+)',
        ]
        metrics['hold_tns'] = cls._search_numeric(content, hold_tns_patterns)

        # Failing Endpoint count
        fep_patterns = [
            r'(?:failing\s*endpoints?|fep|num.*violat)\s*[=:]\s*(\d+)',
            r'(?:total\s*violating\s*paths?)\s*[=:]\s*(\d+)',
            r'NVP\s*[=:]\s*(\d+)',
        ]
        metrics['fep_count'] = cls._search_numeric(content, fep_patterns, as_int=True)

        return metrics

    @classmethod
    def extract_power(cls, run_dir: Path) -> dict:
        """Extract power metrics from reports/power/ directory."""
        power_dir = run_dir / 'reports' / 'power'
        metrics = {}

        content_parts = []
        if power_dir.is_dir():
            for rpt in sorted(power_dir.glob('*.rpt')):
                content_parts.append(cls._read_file_safe(rpt))
        content = '\n'.join(content_parts)

        if not content:
            return metrics

        # Total power
        total_patterns = [
            r'(?:total\s*power)\s*[=:]\s*([\d.]+)\s*(\w+)?',
            r'(?:total)\s*(?:internal|switch|leak).*?(?:total)\s*[=:]\s*([\d.]+)',
            r'Total\s+Power\s*[=:]\s*([\d.eE+-]+)',
        ]
        metrics['total_power'] = cls._search_numeric(content, total_patterns)

        # Dynamic power
        dynamic_patterns = [
            r'(?:dynamic\s*power|switching\s*power)\s*[=:]\s*([\d.]+)',
            r'(?:internal\s*\+\s*switching)\s*[=:]\s*([\d.]+)',
            r'Dynamic\s+Power\s*[=:]\s*([\d.eE+-]+)',
        ]
        metrics['dynamic_power'] = cls._search_numeric(content, dynamic_patterns)

        # Leakage power
        leakage_patterns = [
            r'(?:leakage\s*power|static\s*power)\s*[=:]\s*([\d.]+)',
            r'Leakage\s+Power\s*[=:]\s*([\d.eE+-]+)',
        ]
        metrics['leakage_power'] = cls._search_numeric(content, leakage_patterns)

        # Clock power
        clock_patterns = [
            r'(?:clock\s*(?:network\s*)?power)\s*[=:]\s*([\d.]+)',
            r'Clock\s+Power\s*[=:]\s*([\d.eE+-]+)',
        ]
        metrics['clock_power'] = cls._search_numeric(content, clock_patterns)

        # Try to detect units
        unit_match = re.search(
            r'(?:total\s*power)\s*[=:]\s*[\d.]+\s*(mW|uW|nW|W)', content, re.IGNORECASE
        )
        if unit_match:
            metrics['power_unit'] = unit_match.group(1)

        return metrics

    @classmethod
    def extract_congestion(cls, run_dir: Path) -> dict:
        """Extract congestion metrics from reports/congestion/."""
        cong_dir = run_dir / 'reports' / 'congestion'
        metrics = {}

        content_parts = []
        if cong_dir.is_dir():
            for rpt in sorted(cong_dir.glob('*.rpt')):
                content_parts.append(cls._read_file_safe(rpt))
        content = '\n'.join(content_parts)

        if not content:
            return metrics

        cong_patterns = [
            r'(?:max\s*congestion|worst\s*congestion|peak\s*congestion)\s*[=:]\s*([\d.]+)',
            r'(?:congestion)\s*[=:]\s*([\d.]+)%',
            r'(?:overflow)\s*[=:]\s*(\d+)',
        ]
        metrics['max_congestion'] = cls._search_numeric(content, cong_patterns[:2])

        overflow_patterns = [
            r'(?:total\s*overflow|overflow\s*count|overflows)\s*[=:]\s*(\d+)',
            r'(?:OF|overflow)\s*[=:]\s*(\d+)',
        ]
        metrics['overflow_count'] = cls._search_numeric(content, overflow_patterns, as_int=True)

        return metrics

    @classmethod
    def extract_drc(cls, run_dir: Path) -> dict:
        """Extract DRC violation counts from reports/drc/."""
        drc_dir = run_dir / 'reports' / 'drc'
        metrics = {}

        content_parts = []
        if drc_dir.is_dir():
            for rpt in sorted(drc_dir.glob('*.rpt')):
                content_parts.append(cls._read_file_safe(rpt))
        content = '\n'.join(content_parts)

        if not content:
            return metrics

        drc_patterns = [
            r'(?:total\s*(?:drc\s*)?violations?)\s*[=:]\s*(\d+)',
            r'(?:drc\s*(?:error|violation)\s*count)\s*[=:]\s*(\d+)',
            r'(?:number\s*of\s*(?:drc\s*)?violations?)\s*[=:]\s*(\d+)',
            r'(?:violation|error)\s*(?:count|total)\s*[=:]\s*(\d+)',
            r'Total\s+DRC\s*[=:]\s*(\d+)',
        ]
        metrics['drc_violations'] = cls._search_numeric(content, drc_patterns, as_int=True)

        return metrics

    @classmethod
    def extract_lvs(cls, run_dir: Path) -> dict:
        """Extract LVS match status from reports/lvs/."""
        lvs_dir = run_dir / 'reports' / 'lvs'
        metrics = {}

        content_parts = []
        if lvs_dir.is_dir():
            for rpt in sorted(lvs_dir.glob('*.rpt')):
                content_parts.append(cls._read_file_safe(rpt))
        content = '\n'.join(content_parts)

        if not content:
            return metrics

        # LVS match: look for CLEAN / MATCH / PASS
        if re.search(r'\b(?:CLEAN|MATCH|PASS(?:ED)?)\b', content, re.IGNORECASE):
            metrics['lvs_match'] = 1
        elif re.search(r'\b(?:MISMATCH|FAIL(?:ED)?|NOT\s*CLEAN)\b', content, re.IGNORECASE):
            metrics['lvs_match'] = 0

        return metrics

    @classmethod
    def extract_floorplan(cls, run_dir: Path) -> dict:
        """Extract utilization and area from reports/floorplan/."""
        fp_dir = run_dir / 'reports' / 'floorplan'
        metrics = {}

        content_parts = []
        if fp_dir.is_dir():
            for rpt in sorted(fp_dir.glob('*.rpt')):
                content_parts.append(cls._read_file_safe(rpt))
        # Also try reports/place/ for post-placement utilization
        place_dir = run_dir / 'reports' / 'place'
        if place_dir.is_dir():
            for rpt in sorted(place_dir.glob('*.rpt')):
                content_parts.append(cls._read_file_safe(rpt))
        content = '\n'.join(content_parts)

        if not content:
            return metrics

        util_patterns = [
            r'(?:utilization|density|placement\s*density)\s*[=:]\s*([\d.]+)\s*%',
            r'(?:utilization|density)\s*[=:]\s*0?\.([\d]+)',
            r'(?:cell\s*area\s*/\s*core\s*area)\s*[=:]\s*([\d.]+)',
        ]
        val = cls._search_numeric(content, util_patterns)
        if val is not None:
            # Normalize to fraction if reported as percentage
            metrics['utilization'] = val / 100.0 if val > 1.0 else val

        cell_patterns = [
            r'(?:total\s*(?:std\s*)?cells?|cell\s*count|instance\s*count)\s*[=:]\s*(\d+)',
            r'(?:number\s*of\s*(?:std\s*)?cells?)\s*[=:]\s*(\d+)',
        ]
        metrics['cell_count'] = cls._search_numeric(content, cell_patterns, as_int=True)

        return metrics

    @classmethod
    def extract_cts(cls, run_dir: Path) -> dict:
        """Extract clock tree quality from reports/cts/."""
        cts_dir = run_dir / 'reports' / 'cts'
        metrics = {}

        content_parts = []
        if cts_dir.is_dir():
            for rpt in sorted(cts_dir.glob('*.rpt')):
                content_parts.append(cls._read_file_safe(rpt))
        content = '\n'.join(content_parts)

        if not content:
            return metrics

        skew_patterns = [
            r'(?:clock\s*skew|max\s*skew|global\s*skew)\s*[=:]\s*([\d.]+)',
            r'(?:skew)\s*[=:]\s*([\d.]+)',
        ]
        metrics['clock_skew'] = cls._search_numeric(content, skew_patterns)

        ins_patterns = [
            r'(?:insertion\s*delay|max\s*insertion|insertion)\s*[=:]\s*([\d.]+)',
            r'(?:max\s*latency|clock\s*latency)\s*[=:]\s*([\d.]+)',
        ]
        metrics['insertion_delay'] = cls._search_numeric(content, ins_patterns)

        cov_patterns = [
            r'(?:clock\s*coverage|coverage)\s*[=:]\s*([\d.]+)\s*%',
            r'(?:clock\s*coverage|coverage)\s*[=:]\s*([\d.]+)',
        ]
        val = cls._search_numeric(content, cov_patterns)
        if val is not None:
            metrics['clock_coverage'] = val if val > 1.0 else val * 100.0

        return metrics


# ─────────────────────────────────────────────────────────────────────────────
# QoR Extraction
# ─────────────────────────────────────────────────────────────────────────────

def extract_qor_metrics(run_dir: str) -> QoRMetrics:
    """Extract all QoR metrics from a run directory."""
    run_path = Path(run_dir)
    metrics = QoRMetrics(run_dir=str(run_path))

    # Parse run environment
    env_file = run_path / '.run.cbflow.env'
    env_vars = parse_env_file(env_file)
    metrics.project = env_vars.get('CBFLOW_PROJECT', '')
    metrics.flow_type = env_vars.get('CBFLOW_FLOW_TYPE', env_vars.get('FLOW_TYPE', ''))
    metrics.run_name = env_vars.get('CBFLOW_RUN_NAME', run_path.name)
    metrics.design_name = env_vars.get('CBFLOW_DESIGN_NAME', '')
    metrics.phase = env_vars.get('CBFLOW_PROJECT_PHASE', '')

    # Extract from each report category
    for attr, value in ReportParser.extract_timing(run_path).items():
        if value is not None:
            setattr(metrics, attr, value)

    for attr, value in ReportParser.extract_power(run_path).items():
        if value is not None:
            setattr(metrics, attr, value)

    for attr, value in ReportParser.extract_congestion(run_path).items():
        if value is not None:
            setattr(metrics, attr, value)

    for attr, value in ReportParser.extract_drc(run_path).items():
        if value is not None:
            setattr(metrics, attr, value)

    for attr, value in ReportParser.extract_lvs(run_path).items():
        if value is not None:
            setattr(metrics, attr, value)

    for attr, value in ReportParser.extract_floorplan(run_path).items():
        if value is not None:
            setattr(metrics, attr, value)

    for attr, value in ReportParser.extract_cts(run_path).items():
        if value is not None:
            setattr(metrics, attr, value)

    logger.info(f"Extracted QoR metrics from: {run_path.name}")
    return metrics


def detect_current_stage(run_dir: Path) -> Optional[str]:
    """Auto-detect the current/latest completed stage from RACE DB."""
    try:
        from status_provider import StatusProvider
        provider = StatusProvider(str(run_dir))
        all_status = provider.get_all_status()
        # Find the latest completed stage by timestamp
        latest_stage, latest_ts = None, ''
        for stage, info in all_status.items():
            if info.get('status') in ('DONE', 'BYPASSED', 'FORCE_VALIDATED'):
                ts = info.get('timestamp', '')
                if ts > latest_ts:
                    latest_ts = ts
                    latest_stage = stage
        return latest_stage
    except Exception:
        return None


def auto_detect_milestone(run_dir: Path) -> str:
    """Detect the appropriate milestone based on the run's current stage."""
    stage = detect_current_stage(run_dir)
    if stage:
        base = stage.rstrip('0123456789').lower()
        # Invert mapping: stage_name -> milestone
        mapping = _get_milestone_stage_mapping()
        stage_to_milestone = {v.lower(): k for k, v in mapping.items()}
        if base in stage_to_milestone:
            return stage_to_milestone[base]
    # No hardcoded default — return None and let caller handle
    milestones = _get_valid_milestones()
    if milestones:
        return milestones[-1]  # Last milestone alphabetically as best guess
    return ''


# ─────────────────────────────────────────────────────────────────────────────
# Threshold Loading
# ─────────────────────────────────────────────────────────────────────────────

def load_thresholds(milestone: str, project: str = '', phase: str = '') -> dict:
    """Load threshold values for a given milestone.

    Resolution order: phase override > project override > exit config default.
    """
    thresholds = {}

    # Try to load from threshold_overrides.tcl
    override_path = os.path.join(get_exit_config_dir(), 'threshold_overrides.tcl')
    if project and os.path.exists(override_path):
        try:
            with open(override_path, 'r') as f:
                content = f.read()

            # Parse project-level overrides: key = project,milestone,metric
            for match in re.finditer(
                rf'{re.escape(project)},{re.escape(milestone)},(\w+)\s+([\d.eE+-]+)',
                content
            ):
                metric_name = match.group(1)
                metric_val = safe_float(match.group(2))
                if metric_val is not None:
                    thresholds[metric_name] = metric_val

            # Parse phase-level overrides: key = project,phase,milestone,metric
            if phase:
                for match in re.finditer(
                    rf'{re.escape(project)},{re.escape(phase)},{re.escape(milestone)},(\w+)\s+([\d.eE+-]+)',
                    content
                ):
                    metric_name = match.group(1)
                    metric_val = safe_float(match.group(2))
                    if metric_val is not None:
                        thresholds[metric_name] = metric_val

        except Exception as e:
            logger.debug(f"Could not parse threshold overrides: {e}")

    return thresholds


def evaluate_threshold(metric_name: str, actual, threshold) -> str:
    """Evaluate a metric against its threshold. Returns PASS/FAIL/N_A."""
    if actual is None:
        return 'N/A'
    if threshold is None:
        return 'N/A'

    actual_f = safe_float(str(actual))
    threshold_f = safe_float(str(threshold))
    if actual_f is None or threshold_f is None:
        return 'N/A'

    # Metrics where higher is worse (slack-like: actual >= threshold is pass)
    slack_metrics = {'setup_wns', 'setup_tns', 'hold_wns', 'hold_tns'}
    # Metrics where lower is better (violations, skew, etc.)
    lower_better = {'drc_violations', 'clock_skew', 'max_insertion_delay',
                    'max_congestion', 'overflow_count', 'max_ir_drop'}
    # Metrics where higher is better (coverage, utilization_min, match)
    higher_better = {'clock_coverage', 'utilization_min', 'pin_accessibility',
                     'lvs_match'}

    if metric_name in slack_metrics:
        return 'PASS' if actual_f >= threshold_f else 'FAIL'
    elif metric_name in lower_better:
        return 'PASS' if actual_f <= threshold_f else 'FAIL'
    elif metric_name in higher_better:
        return 'PASS' if actual_f >= threshold_f else 'FAIL'
    elif metric_name == 'utilization_max':
        return 'PASS' if actual_f <= threshold_f else 'FAIL'
    elif metric_name == 'fep_count':
        return 'PASS' if actual_f <= threshold_f else 'FAIL'
    else:
        # Default: treat as lower-is-better for unknowns
        return 'PASS' if actual_f <= threshold_f else 'FAIL'


# ─────────────────────────────────────────────────────────────────────────────
# Report Formatters
# ─────────────────────────────────────────────────────────────────────────────

def _fmt_val(val, precision: int = 2) -> str:
    """Format a metric value for display."""
    if val is None:
        return 'N/A'
    if isinstance(val, int):
        return str(val)
    if isinstance(val, float):
        return f'{val:.{precision}f}'
    return str(val)


def format_text_report(metrics: QoRMetrics, milestone: str,
                       thresholds: dict) -> str:
    """Generate a text-format QoR report."""
    lines = []
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    w = 70

    lines.append('')
    lines.append(f'{"="*w}')
    lines.append(f'  CBFlow QoR Report')
    lines.append(f'{"="*w}')
    lines.append(f'  Project:    {metrics.project or "N/A"}')
    lines.append(f'  Design:     {metrics.design_name or "N/A"}')
    lines.append(f'  Flow:       {metrics.flow_type or "N/A"}')
    lines.append(f'  Run:        {metrics.run_name or "N/A"}')
    lines.append(f'  Milestone:  {milestone}')
    lines.append(f'  Date:       {now}')
    lines.append(f'{"="*w}')

    # Timing summary
    lines.append('')
    lines.append(f'  Timing Summary')
    lines.append(f'  {"-"*65}')
    lines.append(f'  {"Metric":<30s} {"Value":>15s}')
    lines.append(f'  {"-"*65}')
    lines.append(f'  {"Setup WNS (ps)":<30s} {_fmt_val(metrics.setup_wns):>15s}')
    lines.append(f'  {"Setup TNS (ps)":<30s} {_fmt_val(metrics.setup_tns):>15s}')
    lines.append(f'  {"Hold WNS (ps)":<30s} {_fmt_val(metrics.hold_wns):>15s}')
    lines.append(f'  {"Hold TNS (ps)":<30s} {_fmt_val(metrics.hold_tns):>15s}')
    lines.append(f'  {"Failing Endpoints":<30s} {_fmt_val(metrics.fep_count):>15s}')

    # Area summary
    lines.append('')
    lines.append(f'  Area Summary')
    lines.append(f'  {"-"*65}')
    util_str = _fmt_val(metrics.utilization, 4)
    if metrics.utilization is not None:
        util_str += f' ({metrics.utilization * 100:.1f}%)'
    lines.append(f'  {"Utilization":<30s} {util_str:>15s}')
    lines.append(f'  {"Cell Count":<30s} {_fmt_val(metrics.cell_count):>15s}')

    # Power summary
    lines.append('')
    lines.append(f'  Power Summary ({metrics.power_unit})')
    lines.append(f'  {"-"*65}')
    lines.append(f'  {"Total Power":<30s} {_fmt_val(metrics.total_power):>15s}')
    lines.append(f'  {"Dynamic Power":<30s} {_fmt_val(metrics.dynamic_power):>15s}')
    lines.append(f'  {"Leakage Power":<30s} {_fmt_val(metrics.leakage_power):>15s}')
    lines.append(f'  {"Clock Power":<30s} {_fmt_val(metrics.clock_power):>15s}')

    # Physical quality
    lines.append('')
    lines.append(f'  Physical Quality')
    lines.append(f'  {"-"*65}')
    lines.append(f'  {"DRC Violations":<30s} {_fmt_val(metrics.drc_violations):>15s}')
    lvs_str = 'N/A'
    if metrics.lvs_match == 1:
        lvs_str = 'CLEAN'
    elif metrics.lvs_match == 0:
        lvs_str = 'MISMATCH'
    lines.append(f'  {"LVS Status":<30s} {lvs_str:>15s}')
    lines.append(f'  {"Max Congestion":<30s} {_fmt_val(metrics.max_congestion):>15s}')
    lines.append(f'  {"Overflow Count":<30s} {_fmt_val(metrics.overflow_count):>15s}')

    # Clock tree quality (only for CTS/post-CTS milestones)
    valid_milestones = _get_valid_milestones()
    if milestone in valid_milestones or \
       metrics.clock_skew is not None or metrics.insertion_delay is not None:
        lines.append('')
        lines.append(f'  Clock Tree Quality')
        lines.append(f'  {"-"*65}')
        lines.append(f'  {"Clock Skew (ps)":<30s} {_fmt_val(metrics.clock_skew):>15s}')
        lines.append(f'  {"Insertion Delay (ps)":<30s} {_fmt_val(metrics.insertion_delay):>15s}')
        cov_str = _fmt_val(metrics.clock_coverage)
        if metrics.clock_coverage is not None:
            cov_str += '%'
        lines.append(f'  {"Clock Coverage":<30s} {cov_str:>15s}')

    # Threshold comparison table
    lines.append('')
    lines.append(f'  Threshold Comparison ({milestone})')
    lines.append(f'  {"-"*65}')
    lines.append(f'  {"Metric":<24s} {"Actual":>10s} {"Threshold":>12s} {"Status":>8s}')
    lines.append(f'  {"-"*65}')

    blocking = []
    metric_map = {
        'setup_wns':           metrics.setup_wns,
        'setup_tns':           metrics.setup_tns,
        'hold_wns':            metrics.hold_wns,
        'utilization_min':     metrics.utilization,
        'utilization_max':     metrics.utilization,
        'drc_violations':      metrics.drc_violations,
        'lvs_match':           metrics.lvs_match,
        'max_congestion':      metrics.max_congestion,
        'clock_skew':          metrics.clock_skew,
        'max_insertion_delay': metrics.insertion_delay,
        'clock_coverage':      metrics.clock_coverage,
        'pin_accessibility':   None,  # Not extracted currently
        'max_ir_drop':         None,
        'fep_count':           metrics.fep_count,
    }

    for metric_name, thresh_val in sorted(thresholds.items()):
        actual_val = metric_map.get(metric_name)
        status = evaluate_threshold(metric_name, actual_val, thresh_val)
        lines.append(f'  {metric_name:<24s} {_fmt_val(actual_val):>10s} '
                     f'{_fmt_val(thresh_val):>12s} {status:>8s}')
        if status == 'FAIL':
            blocking.append(metric_name)

    # Overall verdict
    lines.append('')
    lines.append(f'  {"-"*65}')
    if blocking:
        lines.append(f'  Verdict: FAIL')
        lines.append(f'  Blocking items ({len(blocking)}):')
        for item in blocking:
            actual_v = metric_map.get(item)
            lines.append(f'    - {item}: actual={_fmt_val(actual_v)}, '
                        f'threshold={_fmt_val(thresholds.get(item))}')
    else:
        lines.append(f'  Verdict: PASS')
        lines.append(f'  All threshold checks passed for milestone {milestone}.')

    lines.append(f'{"="*w}')
    lines.append('')

    return '\n'.join(lines)


def format_json_report(metrics: QoRMetrics, milestone: str,
                       thresholds: dict) -> str:
    """Generate a JSON-format QoR report."""
    metric_map = {
        'setup_wns': metrics.setup_wns, 'setup_tns': metrics.setup_tns,
        'hold_wns': metrics.hold_wns, 'hold_tns': metrics.hold_tns,
        'fep_count': metrics.fep_count, 'utilization': metrics.utilization,
        'cell_count': metrics.cell_count, 'total_power': metrics.total_power,
        'dynamic_power': metrics.dynamic_power, 'leakage_power': metrics.leakage_power,
        'clock_power': metrics.clock_power, 'drc_violations': metrics.drc_violations,
        'lvs_match': metrics.lvs_match, 'max_congestion': metrics.max_congestion,
        'overflow_count': metrics.overflow_count, 'clock_skew': metrics.clock_skew,
        'insertion_delay': metrics.insertion_delay,
        'clock_coverage': metrics.clock_coverage,
    }

    # Build threshold checks
    checks = []
    for metric_name, thresh_val in sorted(thresholds.items()):
        actual_val = metric_map.get(metric_name)
        if actual_val is None and metric_name == 'utilization_min':
            actual_val = metrics.utilization
        if actual_val is None and metric_name == 'utilization_max':
            actual_val = metrics.utilization
        if actual_val is None and metric_name == 'max_insertion_delay':
            actual_val = metrics.insertion_delay
        status = evaluate_threshold(metric_name, actual_val, thresh_val)
        checks.append({
            'metric': metric_name,
            'actual': actual_val,
            'threshold': thresh_val,
            'status': status,
        })

    blocking = [c for c in checks if c['status'] == 'FAIL']

    report = {
        'header': {
            'project': metrics.project,
            'design': metrics.design_name,
            'flow_type': metrics.flow_type,
            'run_name': metrics.run_name,
            'run_dir': metrics.run_dir,
            'milestone': milestone,
            'phase': metrics.phase,
            'generated_at': datetime.now().isoformat(),
        },
        'timing': {
            'setup_wns': metrics.setup_wns,
            'setup_tns': metrics.setup_tns,
            'hold_wns': metrics.hold_wns,
            'hold_tns': metrics.hold_tns,
            'fep_count': metrics.fep_count,
        },
        'area': {
            'utilization': metrics.utilization,
            'cell_count': metrics.cell_count,
        },
        'power': {
            'total': metrics.total_power,
            'dynamic': metrics.dynamic_power,
            'leakage': metrics.leakage_power,
            'clock': metrics.clock_power,
            'unit': metrics.power_unit,
        },
        'physical': {
            'drc_violations': metrics.drc_violations,
            'lvs_match': metrics.lvs_match,
            'max_congestion': metrics.max_congestion,
            'overflow_count': metrics.overflow_count,
        },
        'clock_tree': {
            'skew': metrics.clock_skew,
            'insertion_delay': metrics.insertion_delay,
            'coverage': metrics.clock_coverage,
        },
        'threshold_checks': checks,
        'verdict': {
            'status': 'FAIL' if blocking else 'PASS',
            'blocking_count': len(blocking),
            'blocking_items': [c['metric'] for c in blocking],
        },
    }

    return json.dumps(report, indent=2, default=str)


def format_csv_report(metrics: QoRMetrics, milestone: str,
                      thresholds: dict) -> str:
    """Generate a CSV-format QoR report."""
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['metric', 'value', 'threshold', 'status', 'milestone',
                     'project', 'run_name'])

    rows = [
        ('setup_wns', metrics.setup_wns),
        ('setup_tns', metrics.setup_tns),
        ('hold_wns', metrics.hold_wns),
        ('hold_tns', metrics.hold_tns),
        ('fep_count', metrics.fep_count),
        ('utilization', metrics.utilization),
        ('cell_count', metrics.cell_count),
        ('total_power', metrics.total_power),
        ('dynamic_power', metrics.dynamic_power),
        ('leakage_power', metrics.leakage_power),
        ('clock_power', metrics.clock_power),
        ('drc_violations', metrics.drc_violations),
        ('lvs_match', metrics.lvs_match),
        ('max_congestion', metrics.max_congestion),
        ('clock_skew', metrics.clock_skew),
        ('insertion_delay', metrics.insertion_delay),
        ('clock_coverage', metrics.clock_coverage),
    ]

    for name, val in rows:
        thresh = thresholds.get(name)
        status = evaluate_threshold(name, val, thresh) if thresh is not None else ''
        writer.writerow([name, _fmt_val(val), _fmt_val(thresh), status,
                         milestone, metrics.project, metrics.run_name])

    return output.getvalue()


def format_html_report(metrics: QoRMetrics, milestone: str,
                       thresholds: dict) -> str:
    """Generate a self-contained HTML QoR report."""
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    # Build threshold rows
    threshold_rows = []
    metric_map = {
        'setup_wns': metrics.setup_wns, 'setup_tns': metrics.setup_tns,
        'hold_wns': metrics.hold_wns, 'utilization_min': metrics.utilization,
        'utilization_max': metrics.utilization, 'drc_violations': metrics.drc_violations,
        'lvs_match': metrics.lvs_match, 'max_congestion': metrics.max_congestion,
        'clock_skew': metrics.clock_skew, 'max_insertion_delay': metrics.insertion_delay,
        'clock_coverage': metrics.clock_coverage, 'fep_count': metrics.fep_count,
        'pin_accessibility': None, 'max_ir_drop': None,
    }
    blocking = []
    for mname, tval in sorted(thresholds.items()):
        aval = metric_map.get(mname)
        status = evaluate_threshold(mname, aval, tval)
        color = '#28a745' if status == 'PASS' else '#dc3545' if status == 'FAIL' else '#6c757d'
        threshold_rows.append(
            f'<tr><td>{mname}</td><td>{_fmt_val(aval)}</td>'
            f'<td>{_fmt_val(tval)}</td>'
            f'<td style="color:{color};font-weight:bold">{status}</td></tr>'
        )
        if status == 'FAIL':
            blocking.append(mname)

    verdict = 'FAIL' if blocking else 'PASS'
    verdict_color = '#dc3545' if blocking else '#28a745'
    blocking_html = ''
    if blocking:
        items = ''.join(f'<li>{b}</li>' for b in blocking)
        blocking_html = f'<h3>Blocking Items</h3><ul>{items}</ul>'

    lvs_str = 'N/A'
    if metrics.lvs_match == 1:
        lvs_str = 'CLEAN'
    elif metrics.lvs_match == 0:
        lvs_str = 'MISMATCH'

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>CBFlow QoR Report - {metrics.run_name}</title>
<style>
  body {{ font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
         margin: 2em auto; max-width: 900px; color: #333; background: #f8f9fa; }}
  h1 {{ color: #1a5276; border-bottom: 3px solid #1a5276; padding-bottom: 0.3em; }}
  h2 {{ color: #2c3e50; margin-top: 1.5em; }}
  table {{ border-collapse: collapse; width: 100%; margin: 0.8em 0; }}
  th, td {{ padding: 8px 12px; border: 1px solid #dee2e6; text-align: left; }}
  th {{ background: #1a5276; color: white; }}
  tr:nth-child(even) {{ background: #f2f2f2; }}
  .header-table td {{ border: none; padding: 4px 12px; }}
  .header-table td:first-child {{ font-weight: bold; width: 120px; }}
  .verdict {{ font-size: 1.4em; font-weight: bold; padding: 0.5em; text-align: center;
              border-radius: 6px; margin: 1em 0; }}
  .meta {{ color: #6c757d; font-size: 0.85em; margin-top: 2em; }}
</style>
</head>
<body>
<h1>CBFlow QoR Report</h1>
<table class="header-table">
<tr><td>Project</td><td>{metrics.project or 'N/A'}</td></tr>
<tr><td>Design</td><td>{metrics.design_name or 'N/A'}</td></tr>
<tr><td>Flow</td><td>{metrics.flow_type or 'N/A'}</td></tr>
<tr><td>Run</td><td>{metrics.run_name or 'N/A'}</td></tr>
<tr><td>Milestone</td><td>{milestone}</td></tr>
<tr><td>Date</td><td>{now}</td></tr>
</table>

<h2>Timing Summary</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Setup WNS (ps)</td><td>{_fmt_val(metrics.setup_wns)}</td></tr>
<tr><td>Setup TNS (ps)</td><td>{_fmt_val(metrics.setup_tns)}</td></tr>
<tr><td>Hold WNS (ps)</td><td>{_fmt_val(metrics.hold_wns)}</td></tr>
<tr><td>Hold TNS (ps)</td><td>{_fmt_val(metrics.hold_tns)}</td></tr>
<tr><td>Failing Endpoints</td><td>{_fmt_val(metrics.fep_count)}</td></tr>
</table>

<h2>Area Summary</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Utilization</td><td>{_fmt_val(metrics.utilization, 4)}{f' ({metrics.utilization*100:.1f}%)' if metrics.utilization is not None else ''}</td></tr>
<tr><td>Cell Count</td><td>{_fmt_val(metrics.cell_count)}</td></tr>
</table>

<h2>Power Summary ({metrics.power_unit})</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Total Power</td><td>{_fmt_val(metrics.total_power)}</td></tr>
<tr><td>Dynamic Power</td><td>{_fmt_val(metrics.dynamic_power)}</td></tr>
<tr><td>Leakage Power</td><td>{_fmt_val(metrics.leakage_power)}</td></tr>
<tr><td>Clock Power</td><td>{_fmt_val(metrics.clock_power)}</td></tr>
</table>

<h2>Physical Quality</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>DRC Violations</td><td>{_fmt_val(metrics.drc_violations)}</td></tr>
<tr><td>LVS Status</td><td>{lvs_str}</td></tr>
<tr><td>Max Congestion</td><td>{_fmt_val(metrics.max_congestion)}</td></tr>
<tr><td>Overflow Count</td><td>{_fmt_val(metrics.overflow_count)}</td></tr>
</table>

<h2>Clock Tree Quality</h2>
<table>
<tr><th>Metric</th><th>Value</th></tr>
<tr><td>Clock Skew (ps)</td><td>{_fmt_val(metrics.clock_skew)}</td></tr>
<tr><td>Insertion Delay (ps)</td><td>{_fmt_val(metrics.insertion_delay)}</td></tr>
<tr><td>Clock Coverage</td><td>{_fmt_val(metrics.clock_coverage)}{'%' if metrics.clock_coverage is not None else ''}</td></tr>
</table>

<h2>Threshold Comparison ({milestone})</h2>
<table>
<tr><th>Metric</th><th>Actual</th><th>Threshold</th><th>Status</th></tr>
{''.join(threshold_rows)}
</table>

<div class="verdict" style="color:{verdict_color};border:2px solid {verdict_color}">
  Verdict: {verdict}
</div>
{blocking_html}

<div class="meta">Generated by CBFlow v{VERSION} QoR Report</div>
</body>
</html>"""
    return html


# ─────────────────────────────────────────────────────────────────────────────
# Compare Formatter
# ─────────────────────────────────────────────────────────────────────────────

def format_compare_text(m1: QoRMetrics, m2: QoRMetrics) -> str:
    """Generate a side-by-side comparison between two runs."""
    lines = []
    w = 80

    lines.append('')
    lines.append(f'{"="*w}')
    lines.append(f'  CBFlow QoR Comparison')
    lines.append(f'{"="*w}')
    lines.append(f'  Run 1: {m1.run_name} ({m1.run_dir})')
    lines.append(f'  Run 2: {m2.run_name} ({m2.run_dir})')
    lines.append(f'{"="*w}')
    lines.append('')

    fields = [
        ('Timing',   [
            ('Setup WNS (ps)',    'setup_wns',  True),
            ('Setup TNS (ps)',    'setup_tns',  True),
            ('Hold WNS (ps)',     'hold_wns',   True),
            ('Hold TNS (ps)',     'hold_tns',   True),
            ('Failing Endpoints', 'fep_count',  False),
        ]),
        ('Area',     [
            ('Utilization',  'utilization', False),
            ('Cell Count',   'cell_count',  False),
        ]),
        ('Power',    [
            ('Total Power',   'total_power',   False),
            ('Dynamic Power', 'dynamic_power', False),
            ('Leakage Power', 'leakage_power', False),
            ('Clock Power',   'clock_power',   False),
        ]),
        ('Physical', [
            ('DRC Violations', 'drc_violations', False),
            ('Max Congestion', 'max_congestion', False),
        ]),
        ('CTS',      [
            ('Clock Skew (ps)',        'clock_skew',       False),
            ('Insertion Delay (ps)',   'insertion_delay',  False),
            ('Clock Coverage (%)',     'clock_coverage',   True),
        ]),
    ]

    hdr = f'  {"Metric":<26s} {"Run 1":>12s} {"Run 2":>12s} {"Delta":>12s} {"Trend":>8s}'
    sep = f'  {"-"*74}'

    for section, items in fields:
        lines.append(f'  {section}')
        lines.append(sep)
        lines.append(hdr)
        lines.append(sep)

        for label, attr, higher_is_better in items:
            v1 = getattr(m1, attr, None)
            v2 = getattr(m2, attr, None)

            delta_str = ''
            trend = ''
            if v1 is not None and v2 is not None:
                try:
                    d = float(v2) - float(v1)
                    delta_str = f'{d:+.2f}'
                    if abs(d) < 1e-9:
                        trend = '--'
                    elif higher_is_better:
                        trend = 'UP' if d > 0 else 'DOWN'
                    else:
                        trend = 'UP' if d < 0 else 'DOWN'
                except (TypeError, ValueError):
                    pass

            lines.append(f'  {label:<26s} {_fmt_val(v1):>12s} {_fmt_val(v2):>12s} '
                        f'{delta_str:>12s} {trend:>8s}')

        lines.append('')

    lines.append(f'{"="*w}')
    lines.append('')
    return '\n'.join(lines)


def format_compare_json(m1: QoRMetrics, m2: QoRMetrics) -> str:
    """Generate a JSON comparison between two runs."""
    fields = [
        'setup_wns', 'setup_tns', 'hold_wns', 'hold_tns', 'fep_count',
        'utilization', 'cell_count', 'total_power', 'dynamic_power',
        'leakage_power', 'clock_power', 'drc_violations', 'max_congestion',
        'clock_skew', 'insertion_delay', 'clock_coverage',
    ]

    comparisons = []
    for attr in fields:
        v1 = getattr(m1, attr, None)
        v2 = getattr(m2, attr, None)
        delta = None
        if v1 is not None and v2 is not None:
            try:
                delta = float(v2) - float(v1)
            except (TypeError, ValueError):
                pass
        comparisons.append({
            'metric': attr,
            'run1_value': v1,
            'run2_value': v2,
            'delta': delta,
        })

    report = {
        'run1': {'name': m1.run_name, 'dir': m1.run_dir},
        'run2': {'name': m2.run_name, 'dir': m2.run_dir},
        'generated_at': datetime.now().isoformat(),
        'comparisons': comparisons,
    }
    return json.dumps(report, indent=2, default=str)


# ─────────────────────────────────────────────────────────────────────────────
# Command Handlers
# ─────────────────────────────────────────────────────────────────────────────

def cmd_generate(args: argparse.Namespace) -> int:
    """Generate a QoR summary report for a run."""
    run_dir = Path(args.run_dir)
    if not run_dir.is_dir():
        logger.error(f"Run directory does not exist: {run_dir}")
        return 1

    # Detect flow type
    env_file = run_dir / '.run.cbflow.env'
    if not env_file.exists():
        logger.warning(f"No .run.cbflow.env found in {run_dir}; "
                       f"metrics extraction may be incomplete.")

    # Extract metrics
    metrics = extract_qor_metrics(str(run_dir))

    # Determine milestone
    milestone = getattr(args, 'milestone', None)
    if not milestone:
        milestone = auto_detect_milestone(run_dir)
        logger.info(f"Auto-detected milestone: {milestone}")

    # Load thresholds
    thresholds = load_thresholds(
        milestone,
        project=metrics.project,
        phase=metrics.phase,
    )

    # Format report
    fmt = getattr(args, 'format', 'text')
    if fmt == 'json':
        output = format_json_report(metrics, milestone, thresholds)
    elif fmt == 'csv':
        output = format_csv_report(metrics, milestone, thresholds)
    elif fmt == 'html':
        output = format_html_report(metrics, milestone, thresholds)
    else:
        output = format_text_report(metrics, milestone, thresholds)

    # Write output
    output_file = getattr(args, 'output', None)
    if output_file:
        out_path = Path(output_file)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, 'w') as f:
            f.write(output)
        logger.info(f"Report written to: {out_path}")
    else:
        print(output)

    return 0


def cmd_compare(args: argparse.Namespace) -> int:
    """Compare QoR between two runs."""
    run_dir1 = Path(args.run_dir1)
    run_dir2 = Path(args.run_dir2)

    for rd in (run_dir1, run_dir2):
        if not rd.is_dir():
            logger.error(f"Run directory does not exist: {rd}")
            return 1

    m1 = extract_qor_metrics(str(run_dir1))
    m2 = extract_qor_metrics(str(run_dir2))

    fmt = getattr(args, 'format', 'text')
    if fmt == 'json':
        output = format_compare_json(m1, m2)
    else:
        output = format_compare_text(m1, m2)

    output_file = getattr(args, 'output', None)
    if output_file:
        out_path = Path(output_file)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, 'w') as f:
            f.write(output)
        logger.info(f"Comparison report written to: {out_path}")
    else:
        print(output)

    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    """Aggregate QoR across all runs for a project from the metrics DB."""
    project = args.project
    flow_filter = getattr(args, 'flow', None)

    core_dir = get_cbflow_core_dir()
    db_path = os.path.join(core_dir, 'data', 'metrics.db')

    if not os.path.exists(db_path):
        logger.error(f"Metrics database not found: {db_path}")
        logger.info("Run 'cbflow flow metrics collect' to populate the database.")
        return 1

    try:
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row

        # Query run summaries
        query = "SELECT * FROM run_summary WHERE project = ?"
        params = [project]
        if flow_filter:
            query += " AND flow_type = ?"
            params.append(flow_filter)
        query += " ORDER BY collected_at DESC LIMIT 50"

        rows = [dict(r) for r in conn.execute(query, params).fetchall()]

        if not rows:
            logger.info(f"No run data found for project '{project}'.")
            conn.close()
            return 0

        # Print summary
        lines = []
        lines.append('')
        lines.append(f'{"="*75}')
        lines.append(f'  CBFlow QoR Summary - Project: {project}')
        if flow_filter:
            lines.append(f'  Flow Filter: {flow_filter}')
        lines.append(f'  Runs Found: {len(rows)}')
        lines.append(f'{"="*75}')
        lines.append('')
        lines.append(f'  {"Run Name":<25s} {"Flow":<8s} {"Stages":>7s} '
                     f'{"Duration":>10s} {"Status":>10s} {"Date":>12s}')
        lines.append(f'  {"-"*70}')

        for row in rows:
            dur = row.get('total_duration_seconds', 0)
            if dur > 3600:
                dur_s = f'{dur/3600:.1f}h'
            elif dur > 60:
                dur_s = f'{dur/60:.1f}m'
            else:
                dur_s = f'{dur:.0f}s'
            date_s = (row.get('collected_at', '') or '')[:10]
            lines.append(
                f'  {row.get("run_name","")[:25]:<25s} '
                f'{row.get("flow_type",""):8s} '
                f'{row.get("completed_stages",0):>3d}/'
                f'{row.get("total_stages",0):<3d} '
                f'{dur_s:>10s} {row.get("status",""):>10s} {date_s:>12s}'
            )

        # Aggregate stats
        total_runs = len(rows)
        completed = sum(1 for r in rows if r.get('status') == 'completed')
        failed = total_runs - completed
        avg_dur = sum(r.get('total_duration_seconds', 0) for r in rows) / max(total_runs, 1)
        lines.append('')
        lines.append(f'  {"-"*70}')
        lines.append(f'  Completed: {completed}/{total_runs} '
                     f'({completed/total_runs*100:.0f}%)  |  '
                     f'Failed: {failed}  |  '
                     f'Avg Duration: {avg_dur:.0f}s')
        lines.append(f'{"="*75}')
        lines.append('')

        print('\n'.join(lines))
        conn.close()

    except sqlite3.Error as e:
        logger.error(f"Database error: {e}")
        return 1

    return 0


# ─────────────────────────────────────────────────────────────────────────────
# Argument Parser
# ─────────────────────────────────────────────────────────────────────────────

def create_parser() -> argparse.ArgumentParser:
    """Create argument parser."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow qor-report',
        description='CBFlow QoR (Quality of Results) Report Generation',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow qor-report generate --run-dir ./P0_run_PNR_test
  cbflow flow qor-report generate --run-dir ./run1 --milestone FP_EXIT
  cbflow flow qor-report generate --run-dir ./run1 --format json -o qor.json
  cbflow flow qor-report generate --run-dir ./run1 --format html -o qor.html
  cbflow flow qor-report compare --run-dir1 ./run1 --run-dir2 ./run2
  cbflow flow qor-report compare --run-dir1 ./run1 --run-dir2 ./run2 --format json
  cbflow flow qor-report summary --project ravendrive
  cbflow flow qor-report summary --project india --flow PNR
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='QoR report commands')

    # generate command
    gen_parser = subparsers.add_parser(
        'generate', help='Generate QoR summary report for a run'
    )
    gen_parser.add_argument(
        '--run-dir', required=True,
        help='Path to the run directory'
    )
    gen_parser.add_argument(
        '--milestone',
        choices=_get_valid_milestones() or None,
        default=None,
        help='Exit milestone to evaluate against (auto-detected if omitted)'
    )
    gen_parser.add_argument(
        '--format', choices=['text', 'json', 'csv', 'html'],
        default='text',
        help='Output format (default: text)'
    )
    gen_parser.add_argument(
        '-o', '--output', default=None,
        help='Output file path (default: stdout)'
    )

    # compare command
    cmp_parser = subparsers.add_parser(
        'compare', help='Compare QoR between two runs'
    )
    cmp_parser.add_argument(
        '--run-dir1', required=True,
        help='Path to the first run directory'
    )
    cmp_parser.add_argument(
        '--run-dir2', required=True,
        help='Path to the second run directory'
    )
    cmp_parser.add_argument(
        '--format', choices=['text', 'json'],
        default='text',
        help='Output format (default: text)'
    )
    cmp_parser.add_argument(
        '-o', '--output', default=None,
        help='Output file path (default: stdout)'
    )

    # summary command
    sum_parser = subparsers.add_parser(
        'summary', help='Aggregate QoR summary across runs for a project'
    )
    sum_parser.add_argument(
        '--project', required=True,
        help='Project name'
    )
    sum_parser.add_argument(
        '--flow', default=None,
        help='Filter by flow type (e.g., PNR, SYNTH)'
    )

    # help
    subparsers.add_parser('help', help='Show help')

    return parser


# ─────────────────────────────────────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = create_parser()
    args = parser.parse_args()

    if not args.command or args.command == 'help':
        parser.print_help()
        return 0

    commands = {
        'generate': cmd_generate,
        'compare': cmd_compare,
        'summary': cmd_summary,
    }

    if args.command in commands:
        return commands[args.command](args)

    logger.error(f"Unknown command: {args.command}")
    return 1


if __name__ == '__main__':
    sys.exit(main())
