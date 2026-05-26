#!/usr/bin/env python3
"""
CBFlow Checklist Command Handler
Exit milestone checklist generation, status tracking, sign-off, and waiver management.
Usage: cbflow flow checklist <subcommand> [options]
"""

import argparse
import glob
import os
import sqlite3
import sys
import re
import json
from datetime import datetime, date, timedelta

# Configure unified logging
from logging_config import configure_logging, get_logger
logger = configure_logging('cbflow.checklist')


def get_cbflow_core_dir() -> str:
    """Get CBFlow core directory from environment or determine from script location."""
    if 'CBFLOW_CORE_DIR' in os.environ:
        return os.environ['CBFLOW_CORE_DIR']
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))


def get_exit_config_dir() -> str:
    """Get exit criteria config directory."""
    core_dir = get_cbflow_core_dir()
    version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    return os.path.join(core_dir, 'config', 'exit', version)


def get_milestone_config_path(milestone: str) -> str:
    """Get the config file path for a given milestone."""
    return os.path.join(get_exit_config_dir(), f'{milestone}_config.tcl')


def get_available_milestones() -> list:
    """Scan the exit config directory for available milestone configs."""
    config_dir = get_exit_config_dir()
    if not os.path.isdir(config_dir):
        return []
    skip = ('waiver_config.tcl', 'threshold_overrides.tcl', 'remediation_config.tcl')
    return sorted(f.replace('_config.tcl', '') for f in os.listdir(config_dir)
                  if f.endswith('_config.tcl') and f not in skip)


def parse_milestone_info(content: str) -> dict:
    """Parse milestone_info fields from TCL config."""
    return dict(re.findall(r'set\s+milestone_info\((\w+)\)\s+"([^"]*)"', content))


def parse_tcl_array_block(content: str, array_name: str) -> dict:
    """Parse a TCL 'array set <name> { "key" { "f" "v" ... } ... }' block.

    Uses brace-depth counting to correctly handle nested TCL braces.
    """
    # Find start of array set block
    start_pat = rf'array\s+set\s+{re.escape(array_name)}\s+\{{'
    start_m = re.search(start_pat, content)
    if not start_m:
        return {}

    # Extract outer block by counting braces
    pos = start_m.end()
    depth = 1
    while pos < len(content) and depth > 0:
        if content[pos] == '{':
            depth += 1
        elif content[pos] == '}':
            depth -= 1
        pos += 1
    block = content[start_m.end():pos - 1]

    # Parse entries: "name" { ... } using brace counting
    result = {}
    entry_pat = re.compile(r'"([^"]+)"\s+\{')
    for em in entry_pat.finditer(block):
        name = em.group(1)
        p = em.end()
        d = 1
        while p < len(block) and d > 0:
            if block[p] == '{':
                d += 1
            elif block[p] == '}':
                d -= 1
            p += 1
        body = block[em.end():p - 1]
        result[name] = dict(re.findall(r'"([^"]+)"\s+"([^"]*)"', body))
    return result


def parse_mandatory_files(content: str) -> list:
    """Parse 'set mandatory_files { ... }' list from TCL config."""
    m = re.search(r'set\s+mandatory_files\s+\{([^}]+)\}', content)
    if not m:
        return []
    quoted = re.findall(r'"([^"]+)"', m.group(1))
    return quoted if quoted else m.group(1).strip().split()


def parse_simple_tcl_array(content: str, array_name: str) -> dict:
    """Parse a TCL 'array set <name> { k1 v1 k2 v2 ... }' (flat key-value pairs)."""
    pat = rf'array\s+set\s+{re.escape(array_name)}\s+\{{([^}}]+)\}}'
    m = re.search(pat, content)
    if not m:
        return {}
    pairs = re.findall(r'(\w+)\s+"?([^"\s}]+)"?', m.group(1))
    return dict(pairs)


def load_check_library(milestone_name: str, check_packs: dict) -> dict:
    """Load checks from category library files that apply to a milestone.

    Args:
        milestone_name: e.g. 'FP_EXIT', 'PRO_EXIT', 'BTO'
        check_packs: {category: min_phase} from the milestone config

    Returns:
        dict of check_name -> check_config (with pack_min_phase injected)
    """
    checks_dir = os.path.join(get_exit_config_dir(), 'checks')
    if not os.path.isdir(checks_dir):
        return {}

    library_checks = {}
    for category, pack_min_phase in check_packs.items():
        lib_file = os.path.join(checks_dir, f'{category}_checks.tcl')
        if not os.path.exists(lib_file):
            continue

        with open(lib_file, 'r') as f:
            content = f.read()

        # Parse the <category>_checks array
        all_checks = parse_tcl_array_block(content, f'{category}_checks')

        for name, cfg in all_checks.items():
            # Filter: only include checks whose applicable_milestones contains this milestone
            applicable = cfg.get('applicable_milestones', '')
            if milestone_name not in applicable.split():
                continue

            # Effective min_phase = max(check's own min_phase, pack's min_phase)
            check_phase = cfg.get('min_phase', 'P0')
            effective_phase = max(check_phase, pack_min_phase)
            cfg['min_phase'] = effective_phase
            cfg['source'] = f'{category}_checks'
            library_checks[name] = cfg

    return library_checks


def parse_milestone_config(config_path: str) -> dict:
    """Parse a complete milestone exit config TCL file into a structured dict."""
    if not os.path.exists(config_path):
        logger.error(f"Config file not found: {config_path}")
        return {}

    with open(config_path, 'r') as f:
        content = f.read()

    config = {
        'milestone_info': parse_milestone_info(content),
        'mandatory_checks': parse_tcl_array_block(content, 'mandatory_checks'),
        'optional_checks': parse_tcl_array_block(content, 'optional_checks'),
        'mandatory_files': parse_mandatory_files(content),
        'deliverables': parse_tcl_array_block(content, 'deliverables'),
        'check_packs': parse_simple_tcl_array(content, 'check_packs'),
    }

    # Load library checks from check packs and merge as optional checks
    if config['check_packs']:
        milestone_name = config['milestone_info'].get('name', '')
        lib_checks = load_check_library(milestone_name, config['check_packs'])
        # Library checks go into a separate key (not merged into optional_checks)
        # so they can be displayed/evaluated separately
        config['library_checks'] = lib_checks
    else:
        config['library_checks'] = {}

    return config


def parse_waiver_config() -> dict:
    """Parse waiver_config.tcl into {policy, waivers, patterns}."""
    waiver_path = os.path.join(get_exit_config_dir(), 'waiver_config.tcl')
    result = {'policy': {}, 'waivers': {}, 'patterns': {}}
    if not os.path.exists(waiver_path):
        return result

    with open(waiver_path, 'r') as f:
        content = f.read()

    # Parse waiver_policy
    m = re.search(r'array\s+set\s+waiver_policy\s+\{([^}]+)\}', content)
    if m:
        result['policy'] = dict(re.findall(r'(\w+)\s+(\S+)', m.group(1)))

    # Parse waiver entries (W001,field "value")
    m = re.search(r'array\s+set\s+waiver\s+\{(.*?)\}\s*$', content, re.DOTALL | re.MULTILINE)
    if m:
        for wid, field, val in re.findall(r'(\w+),(\w+)\s+"([^"]*)"', m.group(1)):
            result['waivers'].setdefault(wid, {})[field] = val

    # Parse waiver_patterns
    m = re.search(r'array\s+set\s+waiver_patterns\s+\{(.*?)\}\s*$', content, re.DOTALL | re.MULTILINE)
    if m:
        for scope_m in re.finditer(r'(\w+)\s+\{([^}]*)\}', m.group(1)):
            result['patterns'][scope_m.group(1)] = re.findall(r'"([^"]+)"', scope_m.group(2))

    return result


def parse_threshold_overrides() -> dict:
    """Parse threshold_overrides.tcl into {policy, project, phase} dicts."""
    override_path = os.path.join(get_exit_config_dir(), 'threshold_overrides.tcl')
    result = {'policy': {}, 'project': {}, 'phase': {}}
    if not os.path.exists(override_path):
        return result

    with open(override_path, 'r') as f:
        content = f.read()

    m = re.search(r'array\s+set\s+override_policy\s+\{([^}]+)\}', content)
    if m:
        result['policy'] = dict(re.findall(r'(\w+)\s+(\S+)', m.group(1)))

    # threshold_override: project,milestone,metric value (may have multiple blocks)
    for bm in re.finditer(r'array\s+set\s+threshold_override\s+\{([^}]+)\}', content):
        for p, ms, met, val in re.findall(r'(\w+),(\w+),(\w+)\s+([\d.e+-]+)', bm.group(1)):
            result['project'][(p, ms, met)] = val

    # phase_override: project,phase,milestone,metric value
    for bm in re.finditer(r'array\s+set\s+phase_override\s+\{([^}]+)\}', content):
        for p, ph, ms, met, val in re.findall(r'(\w+),(\w+),(\w+),(\w+)\s+([\d.e+-]+)', bm.group(1)):
            result['phase'][(p, ph, ms, met)] = val

    return result


def get_active_waivers_for_milestone(milestone: str, project: str = '*') -> list:
    """Return list of active, non-expired waivers for a milestone."""
    today = date.today().isoformat()
    active = []
    for wid, f in parse_waiver_config()['waivers'].items():
        if f.get('status') != 'active' or f.get('milestone') != milestone:
            continue
        wp = f.get('project', '*')
        if project != '*' and wp != '*' and wp != project:
            continue
        if f.get('expiry_date', '') and f['expiry_date'] < today:
            continue
        active.append({'id': wid, **f})
    return active


def get_project_overrides(project: str, milestone: str, phase: str = '') -> dict:
    """Get all threshold overrides for a project/milestone combo (phase > project)."""
    ov = parse_threshold_overrides()
    result = {met: val for (p, ms, met), val in ov['project'].items() if p == project and ms == milestone}
    if phase:
        result.update({met: val for (p, ph, ms, met), val in ov['phase'].items()
                       if p == project and ph == phase and ms == milestone})
    return result


def format_checklist_text(config: dict, waivers: list, overrides: dict) -> str:
    """Format a milestone checklist as a terminal text report."""
    L = []  # output lines
    info = config.get('milestone_info', {})
    waivered = {w.get('check') for w in waivers}
    sep, thin = '='*72, '─'*68

    L += ['', sep, f'  EXIT MILESTONE CHECKLIST: {info.get("name","UNKNOWN")}', sep,
          f'  Description : {info.get("description","")}',
          f'  Stage       : {info.get("stage","")}',
          f'  Generated   : {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}', sep]

    # Checks helper
    def _fmt_checks(title, checks, show_overrides=False):
        L.append(f'\n  {title} ({len(checks)})\n  {thin}')
        for i, (name, f) in enumerate(checks.items(), 1):
            tag = '[WAIVED]' if name in waivered else '[  --  ]'
            L.append(f'  {i:>3}. {tag}  {name}')
            L.append(f'               Description : {f.get("description","")}')
            L.append(f'               Script      : {f.get("script","")}')
            L.append(f'               Criteria    : {f.get("criteria","")}')
            if show_overrides and overrides:
                criteria_lc = f.get('criteria', '').lower().replace(' ', '')
                for metric, val in overrides.items():
                    if metric.lower() in criteria_lc:
                        L.append(f'               Override    : {metric} = {val}')
            L.append('')

    _fmt_checks('MANDATORY CHECKS', config.get('mandatory_checks', {}), show_overrides=True)
    _fmt_checks('OPTIONAL CHECKS', config.get('optional_checks', {}))

    mfiles = config.get('mandatory_files', [])
    L.append(f'  REQUIRED FILES ({len(mfiles)})\n  {thin}')
    for i, fp in enumerate(mfiles, 1):
        L.append(f'  {i:>3}. [  --  ]  {fp}')

    deliverables = config.get('deliverables', {})
    L.append(f'\n  DELIVERABLES ({len(deliverables)})\n  {thin}')
    for i, (name, f) in enumerate(deliverables.items(), 1):
        L.append(f'  {i:>3}. {name}  ({f.get("type","")})  {f.get("source","")} -> {f.get("target","")}')

    L.append(f'\n  ACTIVE WAIVERS ({len(waivers)})\n  {thin}')
    if waivers:
        for w in waivers:
            L.append(f'    [{w.get("id","?")}] {w.get("check","?")} - {w.get("reason","")}')
            L.append(f'           Approved: {w.get("approved_by","")} on {w.get("approved_date","")}  '
                     f'Expires: {w.get("expiry_date","")}  Risk: {w.get("risk_level","")}')
    else:
        L.append('    No active waivers for this milestone.')

    L += ['', sep, '']
    return '\n'.join(L)


def format_checklist_json(config: dict, waivers: list, overrides: dict) -> str:
    """Format a milestone checklist as JSON."""
    waivered = {w.get('check') for w in waivers}

    def _with_status(checks):
        return {n: {**f, 'status': 'WAIVED' if n in waivered else 'PENDING'}
                for n, f in checks.items()}

    return json.dumps({
        'milestone_info': config.get('milestone_info', {}),
        'generated': datetime.now().isoformat(),
        'mandatory_checks': _with_status(config.get('mandatory_checks', {})),
        'optional_checks': _with_status(config.get('optional_checks', {})),
        'mandatory_files': config.get('mandatory_files', []),
        'deliverables': config.get('deliverables', {}),
        'active_waivers': waivers, 'threshold_overrides': overrides,
    }, indent=2)


def format_checklist_html(config: dict, waivers: list, overrides: dict) -> str:
    """Format a milestone checklist as a self-contained HTML report."""
    info = config.get('milestone_info', {})
    ms_name = info.get('name', 'UNKNOWN')
    ms_desc = info.get('description', '')
    ms_stage = info.get('stage', '')
    waivered_checks = {w.get('check') for w in waivers}
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    def _b(n):
        return f'<span class="badge {"waived" if n in waivered_checks else "pending"}">{"WAIVED" if n in waivered_checks else "PENDING"}</span>'

    def _cr(checks):
        return ''.join(f'<tr><td>{i}</td><td><code>{n}</code></td><td>{f.get("description","")}</td>'
                       f'<td><code>{f.get("script","")}</code></td><td><code>{f.get("criteria","")}</code></td>'
                       f'<td>{_b(n)}</td></tr>' for i, (n, f) in enumerate(checks.items(), 1))

    mandatory, optional = config.get('mandatory_checks', {}), config.get('optional_checks', {})
    mfiles, deliverables = config.get('mandatory_files', []), config.get('deliverables', {})

    none6 = '<tr><td colspan="6" style="text-align:center;color:#999;">None</td></tr>'
    none2 = '<tr><td colspan="2" style="text-align:center;color:#999;">None</td></tr>'
    fr = ''.join(f'<tr><td>{i}</td><td><code>{fp}</code></td><td><span class="badge pending">PENDING</span></td></tr>' for i, fp in enumerate(mfiles, 1))
    dr = ''.join(f'<tr><td>{i}</td><td><code>{n}</code></td><td><code>{f.get("source","")}</code></td><td><code>{f.get("target","")}</code></td><td>{f.get("type","")}</td></tr>' for i, (n, f) in enumerate(deliverables.items(), 1))
    wr = ''.join(f'<tr><td>{w.get("id","")}</td><td><code>{w.get("check","")}</code></td><td>{w.get("reason","")}</td><td>{w.get("approved_by","")}</td><td>{w.get("expiry_date","")}</td><td>{w.get("risk_level","")}</td></tr>' for w in waivers) if waivers else none6
    ovr = ''.join(f'<tr><td><code>{m}</code></td><td>{v}</td></tr>' for m, v in overrides.items()) if overrides else none2

    css = ('body{font-family:sans-serif;margin:2em;background:#f8f9fa;color:#333}'
           'h1{color:#1a5276;border-bottom:3px solid #1a5276;padding-bottom:.3em}h2{color:#2c3e50;margin-top:1.5em}'
           'table{border-collapse:collapse;width:100%;margin:1em 0;background:#fff}'
           'th,td{border:1px solid #ddd;padding:8px 12px;text-align:left;font-size:.9em}'
           'th{background:#2c3e50;color:#fff}tr:nth-child(even){background:#f2f2f2}'
           '.badge{padding:3px 8px;border-radius:4px;font-size:.8em;font-weight:bold}'
           '.badge.pending{background:#f0ad4e;color:#fff}.badge.waived{background:#5bc0de;color:#fff}'
           'code{background:#eee;padding:2px 5px;border-radius:3px}')

    chk_hdr = '<tr><th>#</th><th>Check</th><th>Description</th><th>Script</th><th>Criteria</th><th>Status</th></tr>'
    return (f'<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>CBFlow Checklist - {ms_name}</title>'
            f'<style>{css}</style></head><body><h1>Checklist: {ms_name}</h1>'
            f'<p><b>Description:</b> {ms_desc} | <b>Stage:</b> {ms_stage} | <b>Generated:</b> {timestamp}</p>'
            f'<h2>Mandatory Checks ({len(mandatory)})</h2><table>{chk_hdr}{_cr(mandatory)}</table>'
            f'<h2>Optional Checks ({len(optional)})</h2><table>{chk_hdr}{_cr(optional)}</table>'
            f'<h2>Required Files ({len(mfiles)})</h2><table><tr><th>#</th><th>File</th><th>Status</th></tr>{fr}</table>'
            f'<h2>Deliverables ({len(deliverables)})</h2><table><tr><th>#</th><th>Name</th><th>Source</th><th>Target</th><th>Type</th></tr>{dr}</table>'
            f'<h2>Waivers ({len(waivers)})</h2><table><tr><th>ID</th><th>Check</th><th>Reason</th><th>By</th><th>Expires</th><th>Risk</th></tr>{wr}</table>'
            f'<h2>Overrides</h2><table><tr><th>Metric</th><th>Value</th></tr>{ovr}</table>'
            f'<div style="margin-top:2em;color:#999;font-size:.85em;text-align:center">Generated by CBFlow</div></body></html>')


def format_status_text(milestone: str, sd: dict) -> str:
    """Format milestone status as a terminal text report."""
    sep, thin = '='*72, '─'*68
    icon_map = {'PASS': '[PASS]', 'FAIL': '[FAIL]', 'WAIVED': '[WAIV]', 'PENDING': '[ -- ]', 'SKIPPED': '[SKIP]'}
    opt_map = {'PASS': '[PASS]', 'FAIL': '[WARN]', 'WAIVED': '[WAIV]', 'PENDING': '[ -- ]', 'SKIPPED': '[SKIP]'}
    L = ['', sep, f'  MILESTONE STATUS: {milestone}', sep,
         f'  Run Dir: {sd.get("run_dir","")}  |  {sd.get("timestamp","")}',
         f'  Completion: {sd.get("completion_pct",0):.1f}%  |  Verdict: {sd.get("verdict","UNKNOWN")}',
         sep, '', '  MANDATORY CHECKS', f'  {thin}']
    for c in sd.get('mandatory_checks', []):
        L.append(f'    {icon_map.get(c["status"],"[??]")}  {c["name"]}')
        if c.get('detail'):
            L.append(f'              {c["detail"]}')
    L += ['', '  OPTIONAL CHECKS', f'  {thin}']
    for c in sd.get('optional_checks', []):
        L.append(f'    {opt_map.get(c["status"],"[??]")}  {c["name"]}')
    lib_checks = sd.get('library_checks', [])
    active_lib = [c for c in lib_checks if c.get('status') != 'SKIPPED']
    if active_lib:
        L += ['', f'  LIBRARY CHECKS ({len(active_lib)} active)', f'  {thin}']
        for c in active_lib:
            L.append(f'    {opt_map.get(c["status"],"[??]")}  {c["name"]}')
    L += ['', '  REQUIRED FILES', f'  {thin}']
    for f in sd.get('file_status', []):
        L.append(f'    {"[PASS]" if f["exists"] else "[FAIL]"}  {f["path"]}')
    blockers = sd.get('blocking_items', [])
    if blockers:
        L += ['', f'  BLOCKING ITEMS ({len(blockers)})', f'  {thin}']
        L += [f'    * {b}' for b in blockers]
    L += ['', sep, '']
    return '\n'.join(L)


def _find_check_report(run_dir: str, check_name: str, check_config: dict = None) -> str:
    """Find a report file for a check in the run directory, or return None.

    Priority: check_config['report_file'] > check_config['grep_file'] > convention fallback.
    """
    # Use explicit report_file from check config
    if check_config:
        for field in ('report_file', 'grep_file'):
            val = check_config.get(field, '')
            if val:
                path = os.path.join(run_dir, val)
                if os.path.exists(path):
                    return path

    # Fallback: convention-based lookup
    candidates = [
        os.path.join(run_dir, 'reports', f'{check_name}.rpt'),
        os.path.join(run_dir, 'reports', f'{check_name}_summary.rpt'),
        os.path.join(run_dir, 'logs', f'{check_name}.log'),
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


def _evaluate_report(report_path: str) -> str:
    """Read a report file and determine PASS/FAIL/PENDING status."""
    try:
        with open(report_path, 'r') as f:
            content = f.read()
        if re.search(r'\bPASS(ED)?\b', content, re.IGNORECASE):
            return 'PASS'
        elif re.search(r'\bFAIL(ED)?\b', content, re.IGNORECASE):
            return 'FAIL'
        return 'PENDING'
    except Exception:
        return 'FAIL'


def _evaluate_checks(run_dir: str, checks: dict, waivered: set, phase: str = '') -> list:
    """Evaluate checks against a run directory. Returns [{name, status, detail}].

    Phase-aware: checks with min_phase higher than current phase are SKIPPED.
    Supports grep-based evaluation via grep_pattern/grep_pass_if fields.
    """
    _phase_order = {'P0': 0, 'P1': 1, 'P2': 2, 'P3': 3}
    results = []
    for name, config in checks.items():
        # Phase filtering: skip checks not yet active at current phase
        if phase and config.get('min_phase'):
            cur = _phase_order.get(phase.upper(), 0)
            req = _phase_order.get(config['min_phase'].upper(), 0)
            if cur < req:
                results.append({'name': name, 'status': 'SKIPPED',
                                'detail': f'Requires phase {config["min_phase"]} (current: {phase})'})
                continue

        if name in waivered:
            results.append({'name': name, 'status': 'WAIVED', 'detail': 'Waived'})
            continue

        report = _find_check_report(run_dir, name, check_config=config)

        if report:
            # Grep-based evaluation
            if config.get('grep_pattern'):
                try:
                    with open(report, 'r') as f:
                        content = f.read()
                    found = bool(re.search(config['grep_pattern'], content))
                    pass_if = config.get('grep_pass_if', 'found')
                    if (pass_if == 'found' and found) or (pass_if == 'not_found' and not found):
                        status = 'PASS'
                    else:
                        status = 'FAIL'
                    detail = f'{status} (grep {"found" if found else "not found"}: {config["grep_pattern"]})'
                except Exception as e:
                    status, detail = 'FAIL', f'Grep error: {e}'
            else:
                # Standard PASS/FAIL keyword evaluation
                status = _evaluate_report(report)
                detail = (f'{status} (from {os.path.basename(report)})' if status != 'PENDING'
                          else f'No clear verdict: {os.path.basename(report)}')
            results.append({'name': name, 'status': status, 'detail': detail})
        else:
            results.append({'name': name, 'status': 'PENDING', 'detail': 'No report found'})
    return results


def _find_run_db(run_dir: str) -> str:
    """Find the RACE SQLite database for a run directory.

    Resolution order:
      1. .race_db_pointer file (points to race area DB)
      2. Local .race_*.db files (legacy fallback)
      3. None
    """
    # Check pointer file first (race area DB)
    pointer_path = os.path.join(run_dir, '.race_db_pointer')
    if os.path.exists(pointer_path):
        try:
            with open(pointer_path) as f:
                stored_path = f.read().strip()
            if stored_path and os.path.exists(stored_path):
                return stored_path
        except (OSError, IOError):
            pass

    # Fallback: local DB files
    pattern = os.path.join(run_dir, '.race_*.db')
    matches = glob.glob(pattern)
    if matches:
        return matches[0]
    return None


def _write_checklist_to_db(run_dir: str, milestone: str, phase: str,
                           mand_res: list, opt_res: list, lib_res: list,
                           checks_config: dict) -> None:
    """Write checklist evaluation results to the run's SQLite database.

    Args:
        run_dir: Path to the run directory containing the .race_*.db file.
        milestone: Milestone name (e.g. 'FP_EXIT', 'BTO').
        phase: Design phase (e.g. 'P0', 'P1') or empty string.
        mand_res: Evaluation results for mandatory checks (from _evaluate_checks).
        opt_res: Evaluation results for optional checks (from _evaluate_checks).
        lib_res: Evaluation results for library checks (from _evaluate_checks).
        checks_config: Parsed milestone config dict (from parse_milestone_config).
    """
    db_path = _find_run_db(run_dir)
    if not db_path:
        logger.debug(f"No RACE database found in {run_dir}, skipping DB write")
        return

    mandatory_checks = checks_config.get('mandatory_checks', {})
    optional_checks = checks_config.get('optional_checks', {})
    library_checks = checks_config.get('library_checks', {})

    evaluated_by = os.environ.get('USER', '')

    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()

        cur.execute('''CREATE TABLE IF NOT EXISTS checklist_results (
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

        rows = []
        for check_type, results, cfg_dict in [
            ('mandatory', mand_res, mandatory_checks),
            ('optional', opt_res, optional_checks),
            ('library', lib_res, library_checks),
        ]:
            for r in results:
                name = r['name']
                cfg = cfg_dict.get(name, {})
                category = cfg.get('category', cfg.get('source', ''))
                severity = cfg.get('severity', '')
                report_file = cfg.get('report_file', cfg.get('grep_file', ''))
                threshold = cfg.get('criteria', '')
                rows.append((
                    milestone,
                    name,
                    check_type,
                    category,
                    severity,
                    r.get('status', 'PENDING'),
                    '',           # metric_value — not evaluated here
                    threshold,
                    r.get('detail', ''),
                    report_file,
                    phase,
                    evaluated_by,
                ))

        cur.executemany(
            '''INSERT INTO checklist_results
               (milestone, check_name, check_type, category, severity,
                status, metric_value, threshold, detail, report_file,
                phase, evaluated_by)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            rows,
        )

        conn.commit()
        conn.close()
        logger.info(f"Wrote {len(rows)} checklist results to {os.path.basename(db_path)}")
    except Exception as e:
        logger.warning(f"Failed to write checklist results to DB: {e}")


def _load_and_validate_config(milestone: str, run_dir: str = None):
    """Load milestone config, validate paths. Returns (config, path) or (None, None)."""
    if run_dir and not os.path.isdir(run_dir):
        logger.error(f"Run directory does not exist: {run_dir}")
        return None, None
    config_path = get_milestone_config_path(milestone)
    if not os.path.exists(config_path):
        logger.error(f"Milestone config not found: {config_path}")
        return None, None
    config = parse_milestone_config(config_path)
    if not config:
        logger.error(f"Failed to parse milestone config: {config_path}")
        return None, None
    return config, config_path


def cmd_generate(args: argparse.Namespace) -> int:
    """Generate a formatted checklist for a milestone."""
    milestone = args.milestone
    project = getattr(args, 'project', '') or os.environ.get('CBFLOW_PROJECT', '')
    phase = getattr(args, 'phase', '') or ''
    output_format = getattr(args, 'format', 'text') or 'text'

    config, _ = _load_and_validate_config(milestone)
    if not config:
        logger.error(f"Available milestones: {', '.join(get_available_milestones())}")
        return 1
    logger.info(f"Generating checklist for milestone: {milestone}")

    # Load waivers
    waivers = get_active_waivers_for_milestone(milestone, project=project or '*')

    # Load threshold overrides
    overrides = {}
    if project:
        overrides = get_project_overrides(project, milestone, phase=phase)

    # Format output
    if output_format == 'json':
        output = format_checklist_json(config, waivers, overrides)
    elif output_format == 'html':
        output = format_checklist_html(config, waivers, overrides)
    else:
        output = format_checklist_text(config, waivers, overrides)

    print(output)
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    """Check actual status of a milestone against a run directory."""
    milestone, run_dir = args.milestone, args.run_dir
    project = getattr(args, 'project', '') or os.environ.get('CBFLOW_PROJECT', '')
    phase = getattr(args, 'phase', '') or ''

    # Auto-detect phase from run if not provided
    if not phase:
        phase = _detect_phase(run_dir)

    config, _ = _load_and_validate_config(milestone, run_dir)
    if not config:
        return 1
    logger.info(f"Checking milestone status: {milestone} in {run_dir}" +
                (f" (phase: {phase})" if phase else ""))

    waivers = get_active_waivers_for_milestone(milestone, project=project or '*')
    waivered_checks = {w.get('check') for w in waivers}

    # Evaluate checks (phase-aware)
    mand_res = _evaluate_checks(run_dir, config.get('mandatory_checks', {}), waivered_checks, phase=phase)
    opt_res = _evaluate_checks(run_dir, config.get('optional_checks', {}), waivered_checks, phase=phase)

    # Evaluate library checks (from check packs — treated as optional/informational)
    lib_res = _evaluate_checks(run_dir, config.get('library_checks', {}), waivered_checks, phase=phase)

    # Compute blockers and passed counts (SKIPPED checks don't count)
    active_mand = [r for r in mand_res if r['status'] != 'SKIPPED']
    blocking, m_pass, m_total = [], 0, len(active_mand)
    for r in active_mand:
        if r['status'] in ('PASS', 'WAIVED'):
            m_pass += 1
        else:
            blocking.append(f'Mandatory check {"FAILED" if r["status"]=="FAIL" else "not run"}: {r["name"]}')

    # Evaluate mandatory files
    file_status = [{'path': fp, 'exists': os.path.exists(os.path.join(run_dir, fp))}
                   for fp in config.get('mandatory_files', [])]
    for fs in file_status:
        m_total += 1
        if fs['exists']:
            m_pass += 1
        else:
            blocking.append(f'Missing mandatory file: {fs["path"]}')

    pct = (m_pass / m_total * 100) if m_total > 0 else 0.0
    verdict = 'PASS' if not blocking else 'BLOCKED'

    status_data = {
        'milestone': milestone, 'run_dir': run_dir,
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'completion_pct': pct, 'verdict': verdict,
        'mandatory_checks': mand_res, 'optional_checks': opt_res,
        'library_checks': lib_res,
        'file_status': file_status, 'blocking_items': blocking,
        'active_waivers': waivers,
    }

    # Write results to SQLite database
    _write_checklist_to_db(run_dir, milestone, phase, mand_res, opt_res, lib_res, config)

    print(format_status_text(milestone, status_data))

    # Save report
    logs_dir = os.path.join(run_dir, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    rpt = os.path.join(logs_dir, f'checklist_status_{milestone}_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json')
    with open(rpt, 'w') as f:
        json.dump(status_data, f, indent=2, default=str)
    logger.info(f"Status report saved to: {rpt}")
    return 0 if verdict == 'PASS' else 1


def cmd_signoff(args: argparse.Namespace) -> int:
    """Record a sign-off for a milestone."""
    milestone, run_dir, approver = args.milestone, args.run_dir, args.approver
    phase = getattr(args, 'phase', '') or ''

    # Auto-detect phase from run if not provided
    if not phase:
        phase = _detect_phase(run_dir)

    config, _ = _load_and_validate_config(milestone, run_dir)
    if not config:
        return 1
    logger.info(f"Sign-off: {milestone} by {approver} in {run_dir}" +
                (f" (phase: {phase})" if phase else ""))

    project = os.environ.get('CBFLOW_PROJECT', '')
    waivers = get_active_waivers_for_milestone(milestone, project=project or '*')
    waivered_checks = {w.get('check') for w in waivers}

    # Evaluate all checks using shared helpers (phase-aware)
    mandatory_eval = _evaluate_checks(
        run_dir, config.get('mandatory_checks', {}), waivered_checks, phase=phase)
    optional_eval = _evaluate_checks(
        run_dir, config.get('optional_checks', {}), waivered_checks, phase=phase)
    library_eval = _evaluate_checks(
        run_dir, config.get('library_checks', {}), waivered_checks, phase=phase)

    # Build snapshot dict from evaluations
    checks_snapshot = {}
    all_passed = True
    for ctype, evals, src in [('mandatory', mandatory_eval, config['mandatory_checks']),
                               ('optional', optional_eval, config['optional_checks'])]:
        for r in evals:
            checks_snapshot[r['name']] = {
                'type': ctype, 'status': r['status'],
                'description': src.get(r['name'], {}).get('description', ''),
            }
            if ctype == 'mandatory' and r['status'] not in ('PASS', 'WAIVED', 'SKIPPED'):
                all_passed = False

    # Check mandatory files
    files_snapshot = {fp: os.path.exists(os.path.join(run_dir, fp))
                      for fp in config.get('mandatory_files', [])}
    if not all(files_snapshot.values()):
        all_passed = False

    # Determine verdict
    verdict = ('approved' if all_passed and not waivers else
               'conditional' if all_passed else 'rejected')

    # Build sign-off record
    timestamp = datetime.now()
    mand_snaps = [c for c in checks_snapshot.values() if c['type'] == 'mandatory']
    signoff_record = {
        'milestone': milestone, 'approver': approver,
        'timestamp': timestamp.isoformat(), 'run_dir': run_dir,
        'verdict': verdict, 'checks': checks_snapshot,
        'mandatory_files': files_snapshot,
        'active_waivers': [{'id': w.get('id',''), 'check': w.get('check',''),
                            'reason': w.get('reason',''), 'approved_by': w.get('approved_by',''),
                            'expiry_date': w.get('expiry_date','')} for w in waivers],
        'summary': {
            'total_mandatory': len(mand_snaps),
            'passed': sum(1 for c in mand_snaps if c['status'] == 'PASS'),
            'failed': sum(1 for c in mand_snaps if c['status'] == 'FAIL'),
            'waived': sum(1 for c in mand_snaps if c['status'] == 'WAIVED'),
            'pending': sum(1 for c in mand_snaps if c['status'] == 'PENDING'),
            'files_present': sum(files_snapshot.values()),
            'files_missing': sum(1 for v in files_snapshot.values() if not v),
        },
    }

    # Save sign-off file
    logs_dir = os.path.join(run_dir, 'logs')
    os.makedirs(logs_dir, exist_ok=True)
    signoff_file = os.path.join(
        logs_dir,
        f'signoff_{milestone}_{timestamp.strftime("%Y%m%d_%H%M%S")}.json'
    )

    with open(signoff_file, 'w') as f:
        json.dump(signoff_record, f, indent=2, default=str)

    # Write results to SQLite database
    _write_checklist_to_db(run_dir, milestone, phase,
                           mandatory_eval, optional_eval, library_eval, config)

    # Print summary
    s = signoff_record['summary']
    logger.info(f'\n{"="*60}\n  Sign-Off Recorded: {milestone}\n{"="*60}')
    logger.info(f'  Approver: {approver}  |  {timestamp.strftime("%Y-%m-%d %H:%M:%S")}  |  Verdict: {verdict.upper()}')
    logger.info(f'  Mandatory: {s["passed"]} pass, {s["failed"]} fail, {s["waived"]} waived, {s["pending"]} pending')
    logger.info(f'  Files: {s["files_present"]} present, {s["files_missing"]} missing')
    logger.info(f'  Saved to: {signoff_file}\n{"="*60}\n')

    if verdict == 'rejected':
        logger.warning('REJECTED verdict. Resolve blocking items before proceeding.')
    elif verdict == 'conditional':
        logger.warning('CONDITIONAL verdict. Active waivers are in effect.')

    return 0 if verdict != 'rejected' else 1


def cmd_list(args: argparse.Namespace) -> int:
    """List all available milestones with their check counts and descriptions."""
    milestones = get_available_milestones()
    if not milestones:
        logger.error(f"No milestone configs found at {get_exit_config_dir()}")
        return 1

    logger.info(f'\n{"="*80}\n  AVAILABLE EXIT MILESTONES\n{"="*80}')
    logger.info(f'  Config directory: {get_exit_config_dir()}')
    logger.info(f'  {"Milestone":<16} {"Stage":<14} {"Mand":>5} {"Opt":>5} {"Lib":>5}  Description')
    logger.info(f'  {"─"*16} {"─"*14} {"─"*5} {"─"*5} {"─"*5}  {"─"*30}')

    for ms_name in milestones:
        cfg = parse_milestone_config(get_milestone_config_path(ms_name))
        info = cfg.get('milestone_info', {})
        logger.info(f'  {ms_name:<16} {info.get("stage",""):<14} '
                    f'{len(cfg.get("mandatory_checks",{})):>5} '
                    f'{len(cfg.get("optional_checks",{})):>5} '
                    f'{len(cfg.get("library_checks",{})):>5}  '
                    f'{info.get("description","")}')

    logger.info(f'  Total: {len(milestones)} milestones\n{"="*72}\n')
    return 0


def cmd_waiver(args: argparse.Namespace) -> int:
    """Manage waivers: list, add, or revoke."""
    action = args.action

    if action == 'list':
        return _waiver_list(args)
    elif action == 'add':
        return _waiver_add(args)
    elif action == 'revoke':
        return _waiver_revoke(args)
    else:
        logger.error(f"Unknown waiver action: {action}")
        return 1


def _waiver_list(args: argparse.Namespace) -> int:
    """List all active waivers, optionally filtered by milestone."""
    ms_filter = getattr(args, 'milestone', None)
    waiver_data = parse_waiver_config()
    today = date.today().isoformat()

    title = f'WAIVERS FOR MILESTONE: {ms_filter}' if ms_filter else 'ALL WAIVERS'
    logger.info(f'\n{"="*72}\n  {title}\n{"="*72}')

    displayed = 0
    for wid in sorted(waiver_data['waivers'].keys()):
        f = waiver_data['waivers'][wid]
        if ms_filter and f.get('milestone') != ms_filter:
            continue
        status = f.get('status', 'unknown')
        expiry = f.get('expiry_date', '')
        if status == 'active' and expiry and expiry < today:
            status = 'expired'
        displayed += 1
        logger.info(f'\n  [{wid}] {status.upper()} | {f.get("milestone","")} / {f.get("check","")}')
        logger.info(f'    Project: {f.get("project","*")}  Block: {f.get("block","*")}')
        logger.info(f'    Reason: {f.get("reason","")}')
        logger.info(f'    Approved: {f.get("approved_by","")} on {f.get("approved_date","")}  '
                    f'Expires: {expiry}  Risk: {f.get("risk_level","")}')
        if f.get('conditions'):
            logger.info(f'    Conditions: {f["conditions"]}')

    if displayed == 0:
        logger.info('  No waivers found.')
    logger.info(f'\n  Total: {displayed} waiver(s)\n{"="*72}\n')
    return 0


def _waiver_add(args: argparse.Namespace) -> int:
    """Add a new waiver by printing the TCL snippet to add to waiver_config.tcl."""
    milestone = getattr(args, 'milestone', None)
    check = getattr(args, 'check', None)
    reason, approver = getattr(args, 'reason', None), getattr(args, 'approver', None)
    expiry, project = getattr(args, 'expiry', None), getattr(args, 'project', None) or '*'

    if not all([milestone, check, reason, approver]):
        logger.error("Required: --milestone, --check, --reason, --approver")
        return 1

    config, _ = _load_and_validate_config(milestone)
    if not config:
        return 1
    all_checks = set(config.get('mandatory_checks', {}).keys()) | set(config.get('optional_checks', {}).keys())
    if check not in all_checks:
        logger.error(f"Check '{check}' not in {milestone}. Available: {', '.join(sorted(all_checks))}")
        return 1

    # Generate next waiver ID
    existing = list(parse_waiver_config()['waivers'].keys())
    nums = [int(w[1:]) for w in existing if w[0] == 'W' and w[1:].isdigit()]
    new_id = f'W{(max(nums) + 1 if nums else 1):03d}'

    today_str = date.today().isoformat()
    expiry_str = expiry or ''

    if not expiry_str:
        expiry_str = (date.today() + timedelta(days=90)).isoformat()
        logger.info(f"No expiry provided, defaulting to 90 days: {expiry_str}")

    # Build TCL snippet
    fields = [('milestone', milestone), ('check', check), ('project', project),
              ('block', '*'), ('reason', reason), ('approved_by', approver),
              ('approved_date', today_str), ('expiry_date', expiry_str),
              ('status', 'active'), ('risk_level', 'medium'), ('conditions', '')]
    snippet = f'    # Waiver {new_id}\n' + '\n'.join(
        f'    {new_id},{k:<16}"{v}"' for k, v in fields)

    logger.info(f'\n{"="*72}\n  NEW WAIVER: {new_id}\n{"="*72}')
    logger.info(f'  {milestone} / {check} | Project: {project} | Approver: {approver} | Expires: {expiry_str}')
    logger.info(f'  Reason: {reason}')
    logger.info(f'{"─"*72}\n  Add to "array set waiver" block in:')
    logger.info(f'  {os.path.join(get_exit_config_dir(), "waiver_config.tcl")}\n')
    print(snippet)
    logger.info(f'\n{"="*72}\n')
    return 0


def _waiver_revoke(args: argparse.Namespace) -> int:
    """Mark a waiver as revoked in waiver_config.tcl."""
    waiver_id = getattr(args, 'waiver_id', None)
    if not waiver_id:
        milestone, check = getattr(args, 'milestone', None), getattr(args, 'check', None)
        if not milestone or not check:
            logger.error("Provide --waiver-id, or both --milestone and --check.")
            return 1
        for wid, f in parse_waiver_config()['waivers'].items():
            if f.get('milestone') == milestone and f.get('check') == check:
                waiver_id = wid
                break
        if not waiver_id:
            logger.error(f"No waiver found for {milestone}/{check}")
            return 1

    wpath = os.path.join(get_exit_config_dir(), 'waiver_config.tcl')
    if not os.path.exists(wpath):
        logger.error(f"Waiver config not found: {wpath}")
        return 1
    with open(wpath, 'r') as fh:
        content = fh.read()

    pat = rf'({re.escape(waiver_id)},status\s+)"active"'
    if not re.search(pat, content):
        logger.error(f"Waiver {waiver_id} is not active or not found.")
        return 1
    content = re.sub(pat, r'\1"revoked"', content)

    with open(wpath, 'w') as fh:
        fh.write(content)
    logger.info(f'\n{"="*60}\n  Waiver {waiver_id} REVOKED. Updated: {wpath}\n{"="*60}\n')
    return 0


# ═══════════════════════════════════════════════════════════════════════════════
# CHECK MANAGEMENT — add, remove, list checks in milestone configs
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_add_check(args: argparse.Namespace) -> int:
    """Add a check to a milestone config file.

    Supports three check types:
      1. Script-based: runs a TCL/Python script, checks exit code
      2. Grep-based:   greps a report file for a pattern, PASS if found (or not found)
      3. File-based:   checks if a file exists (added to mandatory_files)

    Examples:
      cbflow flow checklist add-check --milestone PRO_EXIT \\
        --name timing_closure --type mandatory \\
        --description "Setup timing must be clean" \\
        --script "check_timing_closure.tcl" \\
        --criteria "setup_wns >= 0"

      cbflow flow checklist add-check --milestone BTO \\
        --name drc_clean --type mandatory \\
        --description "DRC must be zero violations" \\
        --grep-file "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt" \\
        --grep-pattern "Total.*0.*violation" \\
        --grep-pass-if "found"

      cbflow flow checklist add-check --milestone BTO \\
        --name gds_exists --type file \\
        --file-path r"outputs/${design_name}.gds"
    """
    milestone = args.milestone
    config_path = get_milestone_config_path(milestone)

    if not os.path.exists(config_path):
        logger.error(f"Milestone config not found: {config_path}")
        logger.error(f"Available milestones: {', '.join(get_available_milestones())}")
        return 1

    with open(config_path, 'r') as f:
        content = f.read()

    check_name = args.name
    check_type = args.check_type  # mandatory or optional
    description = args.description or f"Check: {check_name}"

    # Check if name already exists
    if f'"{check_name}"' in content:
        logger.error(f"Check '{check_name}' already exists in {milestone}. Remove it first or use a different name.")
        return 1

    # ── Build the check entry ────────────────────────────────────────────
    if args.file_path:
        # File existence check — add to mandatory_files
        file_path = args.file_path
        # Find mandatory_files block and append
        m = re.search(r'(set mandatory_files\s*\{)(.*?)(\})', content, re.DOTALL)
        if m:
            existing = m.group(2).rstrip()
            new_files = f'{existing}\n    "{file_path}"'
            content = content[:m.start()] + f'{m.group(1)}{new_files}\n{m.group(3)}' + content[m.end():]
            logger.info(f'Added file check: "{file_path}" to mandatory_files')
        else:
            # No mandatory_files block — create one
            content += f'\nset mandatory_files {{\n    "{file_path}"\n}}\n'
            logger.info(f'Created mandatory_files with: "{file_path}"')

    else:
        # Script or grep check
        script = args.script or ""
        criteria = args.criteria or ""

        # Build check fields
        fields = f'        "description" "{description}"\n'
        if script:
            fields += f'        "script" "{script}"\n'
        if criteria:
            fields += f'        "criteria" "{criteria}"\n'

        # Grep-based check — encode grep info in script/criteria
        if args.grep_file:
            grep_file = args.grep_file
            grep_pattern = args.grep_pattern or ""
            grep_pass_if = args.grep_pass_if or "found"  # "found" or "not_found"
            fields += f'        "grep_file" "{grep_file}"\n'
            fields += f'        "grep_pattern" "{grep_pattern}"\n'
            fields += f'        "grep_pass_if" "{grep_pass_if}"\n'
            if not script:
                fields += f'        "script" "grep_check"\n'
            if not criteria:
                fields += f'        "criteria" "grep {grep_pass_if}: {grep_pattern}"\n'

        check_entry = f'    "{check_name}" {{\n{fields}    }}\n'

        # Find the right array block and append
        array_name = 'mandatory_checks' if check_type == 'mandatory' else 'optional_checks'

        # Find the closing brace of the array
        pattern = rf'(array\s+set\s+{array_name}\s+\{{)(.*?)(\}})'
        m = re.search(pattern, content, re.DOTALL)
        if m:
            existing = m.group(2).rstrip()
            new_block = f'{existing}\n{check_entry}'
            content = content[:m.start()] + f'{m.group(1)}{new_block}{m.group(3)}' + content[m.end():]
        else:
            # Array doesn't exist — create it
            content += f'\narray set {array_name} {{\n{check_entry}}}\n'

        logger.info(f'Added {check_type} check: "{check_name}" to {milestone}')

    # Write back
    with open(config_path, 'w') as f:
        f.write(content)

    # Show confirmation
    print(f'\n  Check added to {milestone}:')
    print(f'  {"─" * 50}')
    print(f'  Name:        {check_name}')
    print(f'  Type:        {check_type}')
    print(f'  Description: {description}')
    if args.script:
        print(f'  Script:      {args.script}')
    if args.criteria:
        print(f'  Criteria:    {args.criteria}')
    if args.grep_file:
        print(f'  Grep file:   {args.grep_file}')
        print(f'  Grep pattern:{args.grep_pattern}')
        print(f'  Pass if:     {args.grep_pass_if or "found"}')
    if args.file_path:
        print(f'  File:        {args.file_path}')
    print(f'  Config:      {config_path}')
    print(f'  {"─" * 50}\n')
    return 0


def cmd_remove_check(args: argparse.Namespace) -> int:
    """Remove a check from a milestone config file."""
    milestone = args.milestone
    config_path = get_milestone_config_path(milestone)

    if not os.path.exists(config_path):
        logger.error(f"Milestone config not found: {config_path}")
        return 1

    with open(config_path, 'r') as f:
        content = f.read()

    check_name = args.name

    if f'"{check_name}"' not in content:
        logger.error(f"Check '{check_name}' not found in {milestone}")
        return 1

    # Remove from mandatory_checks or optional_checks
    # Pattern: "check_name" { ... }  (with brace-depth counting)
    removed = False
    for array_name in ('mandatory_checks', 'optional_checks'):
        pattern = rf'(array\s+set\s+{array_name}\s+\{{)(.*?)(\}})'
        m = re.search(pattern, content, re.DOTALL)
        if not m:
            continue
        block = m.group(2)
        # Find and remove the check entry
        entry_pat = rf'\s*"{re.escape(check_name)}"\s*\{{'
        em = re.search(entry_pat, block)
        if not em:
            continue
        # Count braces to find end of entry
        pos = em.end()
        depth = 1
        while pos < len(block) and depth > 0:
            if block[pos] == '{': depth += 1
            elif block[pos] == '}': depth -= 1
            pos += 1
        # Remove the entry
        new_block = block[:em.start()] + block[pos:]
        content = content[:m.start()] + f'{m.group(1)}{new_block}{m.group(3)}' + content[m.end():]
        removed = True
        logger.info(f'Removed "{check_name}" from {array_name} in {milestone}')
        break

    # Also remove from mandatory_files if it's a file check
    file_pat = rf'\s*"{re.escape(check_name)}"'
    if re.search(file_pat, content):
        content = re.sub(file_pat + r'\n?', '', content)
        removed = True

    if not removed:
        logger.error(f"Could not remove '{check_name}' from {milestone}")
        return 1

    with open(config_path, 'w') as f:
        f.write(content)

    print(f'\n  Removed check "{check_name}" from {milestone}')
    print(f'  Config: {config_path}\n')
    return 0


def _detect_phase(run_dir: str) -> str:
    """Auto-detect project phase from run directory.

    Resolution order:
      1. SQLite DB: run_config 'env.CBFLOW_PROJECT_PHASE'
      2. Run dir name prefix: P0_run_..., P1_run_..., P2_run_..., P3_run_...
      3. Empty string (no phase filtering)
    """
    # Try DB first
    db_path = _find_run_db(run_dir)
    if db_path:
        try:
            conn = sqlite3.connect(db_path)
            row = conn.execute(
                "SELECT value FROM run_config WHERE key = 'env.CBFLOW_PROJECT_PHASE'"
            ).fetchone()
            conn.close()
            if row and row[0]:
                return row[0]
        except (sqlite3.OperationalError, OSError):
            pass

    # Try run dir name prefix
    dirname = os.path.basename(os.path.abspath(run_dir))
    for p in ('P0', 'P1', 'P2', 'P3'):
        if dirname.startswith(f'{p}_'):
            return p

    return ''


def _check_id_prefix(category: str) -> str:
    """Map category to check ID prefix."""
    prefixes = {
        'timing': 'TMG', 'timing_checks': 'TMG',
        'placement': 'PLC', 'placement_checks': 'PLC',
        'clock': 'CLK', 'clock_checks': 'CLK',
        'power': 'PWR', 'power_checks': 'PWR',
        'routing': 'RTG', 'routing_checks': 'RTG',
        'physical': 'PHY', 'physical_checks': 'PHY',
        'si': 'SI', 'si_checks': 'SI',
        'manufacturing': 'MFG', 'manufacturing_checks': 'MFG',
        'sta_flow': 'STA', 'sta_flow_checks': 'STA',
        'lec_flow': 'LEC', 'lec_flow_checks': 'LEC',
        'clp_flow': 'CLP', 'clp_flow_checks': 'CLP',
        'pv_flow': 'PV', 'pv_flow_checks': 'PV',
        'emir_flow': 'EMIR', 'emir_flow_checks': 'EMIR',
        'eco_flow': 'ECO', 'eco_flow_checks': 'ECO',
    }
    return prefixes.get(category, category[:3].upper())


def _color(text: str, color: str) -> str:
    """Apply ANSI color to text. Returns plain text if not a TTY."""
    if not sys.stdout.isatty():
        return text
    codes = {
        'red': '\033[91m', 'green': '\033[92m', 'yellow': '\033[93m',
        'cyan': '\033[96m', 'bold': '\033[1m', 'dim': '\033[2m',
        'reset': '\033[0m',
    }
    return f'{codes.get(color, "")}{text}{codes["reset"]}'


def _status_color(status: str) -> str:
    """Color a status string: PASS=green, FAIL=red, SKIP=dim, etc."""
    if status == 'PASS':
        return _color('PASS', 'green')
    elif status == 'FAIL':
        return _color('FAIL', 'red')
    elif status == 'SKIPPED':
        return _color('SKIP', 'dim')
    elif status == 'WAIVED':
        return _color('WAIV', 'yellow')
    return status[:4]


def cmd_list_checks(args: argparse.Namespace) -> int:
    """List all checks in a milestone in tabular format with check IDs."""
    milestone = args.milestone
    phase = getattr(args, 'phase', '') or ''
    output_file = getattr(args, 'output', '') or ''
    summary_mode = getattr(args, 'summary', False)
    run_dir = getattr(args, 'run_dir', '') or ''

    # Auto-detect phase from run directory if not explicitly provided
    if not phase and run_dir:
        phase = _detect_phase(run_dir)

    config_path = get_milestone_config_path(milestone)
    if not os.path.exists(config_path):
        logger.error(f"Milestone config not found: {config_path}")
        logger.error(f"Available: {', '.join(get_available_milestones())}")
        return 1

    cfg = parse_milestone_config(config_path)
    info = cfg.get('milestone_info', {})

    # Build unified check list with IDs
    _phase_order = {'P0': 0, 'P1': 1, 'P2': 2, 'P3': 3}
    all_checks = []
    id_counters = {}

    def _add_checks(checks_dict, check_type):
        for name, fields in checks_dict.items():
            cat = fields.get('source', fields.get('category', ''))
            if not cat or cat in ('mandatory', 'optional'):
                # Inline checks: derive prefix from check name or script
                script = fields.get('script', '')
                if 'timing' in name or 'timing' in script or 'qor' in name:
                    cat = 'timing'
                elif 'utilization' in name or 'density' in name:
                    cat = 'placement'
                elif 'clock' in name or 'cts' in name:
                    cat = 'clock'
                elif 'power' in name or 'ir_drop' in name:
                    cat = 'power'
                elif 'routing' in name or 'route' in name or 'drc' in name:
                    cat = 'routing'
                elif 'congestion' in name:
                    cat = 'routing'
                elif 'legality' in name or 'physical' in name:
                    cat = 'physical'
                elif name.startswith('si_') or 'signal_integrity' in name:
                    cat = 'si'
                else:
                    cat = 'CHK'
            prefix = _check_id_prefix(cat)
            id_counters.setdefault(prefix, 0)
            id_counters[prefix] += 1
            check_id = f'{prefix}-{id_counters[prefix]:03d}'

            min_phase = fields.get('min_phase', 'P0')
            # Show phase range: P0 → "P0-P3", P2 → "P2-P3"
            phase_range = f'{min_phase}-P3' if min_phase != 'P3' else 'P3'
            script = fields.get('script', fields.get('report_pattern', fields.get('grep_pattern', '')))
            severity = fields.get('severity', '-')

            # Phase filter: skip if check's min_phase > requested phase
            if phase:
                cur = _phase_order.get(phase.upper(), 0)
                req = _phase_order.get(min_phase.upper(), 0)
                if cur < req:
                    continue

            # Evaluate status if run_dir provided
            status = '-'
            if run_dir:
                report = _find_check_report(run_dir, name, check_config=fields)
                if report:
                    if fields.get('grep_pattern'):
                        try:
                            with open(report) as f:
                                content = f.read()
                            found = bool(re.search(fields['grep_pattern'], content))
                            pass_if = fields.get('grep_pass_if', 'found')
                            status = 'PASS' if (pass_if == 'found' and found) or (pass_if == 'not_found' and not found) else 'FAIL'
                        except Exception:
                            status = 'FAIL'
                    else:
                        status = _evaluate_report(report)
                else:
                    status = 'PENDING'

            all_checks.append({
                'id': check_id, 'name': name, 'type': check_type,
                'description': fields.get('description', ''),
                'script': script[:30] if script else '-',
                'phase': phase_range, 'min_phase': min_phase,
                'severity': severity, 'status': status,
            })

    _add_checks(cfg.get('mandatory_checks', {}), 'mandatory')
    _add_checks(cfg.get('optional_checks', {}), 'optional')
    _add_checks(cfg.get('library_checks', {}), 'library')

    # ── Summary mode ──────────────────────────────────────────────────
    if summary_mode:
        lines = _format_summary(milestone, info, all_checks, phase, cfg)
        output = '\n'.join(lines)
        if output_file:
            with open(output_file, 'w') as f:
                f.write(output + '\n')
            print(f'  Summary written to: {output_file}')
        else:
            print(output)
        return 0

    # ── Full tabular output ───────────────────────────────────────────
    lines = []
    sep = '═' * 120
    thin = '─' * 120

    phase_label = f' (Phase: {phase})' if phase else ''
    lines.append(f'\n{sep}')
    lines.append(f'  {milestone} — {info.get("description", "")}{phase_label}')
    lines.append(f'  Stage: {info.get("stage", "")}  |  Node: {info.get("stage_node", "")}  |  Checks: {len(all_checks)}')
    lines.append(sep)

    # Table header
    has_status = run_dir != ''
    if has_status:
        hdr = f'  {"ID":<10} {"Status":<6} {"Type":<10} {"Phase":<7} {"Severity":<10} {"Check Name":<32} {"Description":<40}'
        lines.append(hdr)
        lines.append(f'  {thin}')
        for c in all_checks:
            st = _status_color(c['status'])
            lines.append(
                f'  {c["id"]:<10} {st:<15} {c["type"]:<10} {c["phase"]:<7} {c["severity"]:<10} '
                f'{c["name"]:<32} {c["description"][:40]}'
            )
    else:
        hdr = f'  {"ID":<10} {"Type":<10} {"Phase":<7} {"Severity":<10} {"Check Name":<32} {"Script/Pattern":<30}'
        lines.append(hdr)
        lines.append(f'  {thin}')
        for c in all_checks:
            lines.append(
                f'  {c["id"]:<10} {c["type"]:<10} {c["phase"]:<7} {c["severity"]:<10} '
                f'{c["name"]:<32} {c["script"]:<30}'
            )

    # Mandatory files
    files = cfg.get('mandatory_files', [])
    if files:
        lines.append(f'\n  MANDATORY FILES ({len(files)}):')
        lines.append(f'  {"─" * 68}')
        for i, fp in enumerate(files, 1):
            lines.append(f'  {i:2d}. {fp}')

    lines.append(f'\n{sep}\n')

    output = '\n'.join(lines)
    if output_file:
        # Strip ANSI colors for file output
        clean = re.sub(r'\033\[[0-9;]*m', '', output)
        with open(output_file, 'w') as f:
            f.write(clean + '\n')
        print(f'  Checklist written to: {output_file}')
    else:
        print(output)

    return 0


def _format_summary(milestone: str, info: dict, checks: list, phase: str, cfg: dict) -> list:
    """Format a compact summary of check counts by type, severity, and category."""
    L = []
    sep = '═' * 80
    thin = '─' * 80

    phase_label = f' (Phase: {phase})' if phase else ''
    L.append(f'\n{sep}')
    L.append(f'  {milestone} — SUMMARY{phase_label}')
    L.append(f'  {info.get("description", "")}')
    L.append(sep)

    # By type
    types = {}
    for c in checks:
        types.setdefault(c['type'], []).append(c)
    L.append(f'\n  BY TYPE:')
    L.append(f'  {"Type":<12} {"Count":>6}  {"PASS":>6} {"FAIL":>6} {"PEND":>6} {"SKIP":>6}')
    L.append(f'  {thin}')
    for t in ['mandatory', 'optional', 'library']:
        if t not in types:
            continue
        tc = types[t]
        p = sum(1 for c in tc if c['status'] == 'PASS')
        f = sum(1 for c in tc if c['status'] == 'FAIL')
        pn = sum(1 for c in tc if c['status'] == 'PENDING')
        sk = sum(1 for c in tc if c['status'] == 'SKIPPED')
        L.append(f'  {t:<12} {len(tc):>6}  {p:>6} {f:>6} {pn:>6} {sk:>6}')

    total = len(checks)
    tp = sum(1 for c in checks if c['status'] == 'PASS')
    tf = sum(1 for c in checks if c['status'] == 'FAIL')
    tpn = sum(1 for c in checks if c['status'] == 'PENDING')
    tsk = sum(1 for c in checks if c['status'] == 'SKIPPED')
    L.append(f'  {"TOTAL":<12} {total:>6}  {tp:>6} {tf:>6} {tpn:>6} {tsk:>6}')

    # By severity
    sevs = {}
    for c in checks:
        sevs.setdefault(c['severity'], []).append(c)
    L.append(f'\n  BY SEVERITY:')
    L.append(f'  {"Severity":<12} {"Count":>6}  {"PASS":>6} {"FAIL":>6}')
    L.append(f'  {thin}')
    for s in ['critical', 'major', 'minor', '-']:
        if s not in sevs:
            continue
        sc = sevs[s]
        p = sum(1 for c in sc if c['status'] == 'PASS')
        f = sum(1 for c in sc if c['status'] == 'FAIL')
        L.append(f'  {s:<12} {len(sc):>6}  {p:>6} {f:>6}')

    # By category
    cats = {}
    for c in checks:
        prefix = c['id'].split('-')[0]
        cats.setdefault(prefix, []).append(c)
    L.append(f'\n  BY CATEGORY:')
    L.append(f'  {"Category":<12} {"Count":>6}  {"PASS":>6} {"FAIL":>6}')
    L.append(f'  {thin}')
    for cat in sorted(cats.keys()):
        cc = cats[cat]
        p = sum(1 for c in cc if c['status'] == 'PASS')
        f = sum(1 for c in cc if c['status'] == 'FAIL')
        L.append(f'  {cat:<12} {len(cc):>6}  {p:>6} {f:>6}')

    # By phase
    phases = {}
    for c in checks:
        phases.setdefault(c['phase'], []).append(c)
    L.append(f'\n  BY PHASE:')
    L.append(f'  {"Phase":<12} {"Count":>6}')
    L.append(f'  {thin}')
    for p in ['P0', 'P1', 'P2', 'P3']:
        if p in phases:
            L.append(f'  {p:<12} {len(phases[p]):>6}')

    # Files
    files = cfg.get('mandatory_files', [])
    L.append(f'\n  MANDATORY FILES: {len(files)}')

    # Failed checks (if any evaluated)
    failed = [c for c in checks if c['status'] == 'FAIL']
    if failed:
        L.append(f'\n  {_color(f"FAILED CHECKS ({len(failed)}):", "red")}')
        L.append(f'  {thin}')
        for c in failed:
            L.append(f'  {_color(c["id"], "red")}  {c["name"]}  ({c["severity"]})')

    L.append(f'\n{sep}\n')
    return L


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser for checklist commands."""
    parser = argparse.ArgumentParser(
        prog='cbflow flow checklist',
        description='CBFlow Exit Milestone Checklist Management',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  cbflow flow checklist generate --milestone FP_EXIT --format json
  cbflow flow checklist status --milestone FP_EXIT --run-dir /path/to/run
  cbflow flow checklist sign-off --milestone FP_EXIT --run-dir /path/to/run --approver chip_lead
  cbflow flow checklist list
  cbflow flow checklist waiver --action list --milestone FP_EXIT
  cbflow flow checklist waiver --action add --milestone FP_EXIT --check congestion_analysis --reason "..." --approver chip_lead
        """)
    sub = parser.add_subparsers(dest='command', help='Checklist commands')

    # generate
    g = sub.add_parser('generate', help='Generate a formatted checklist for a milestone')
    g.add_argument('--milestone', required=True, help='Exit milestone name')
    g.add_argument('--project', default='', help='Project name for threshold overrides')
    g.add_argument('--phase', default='', help='Design phase (e.g., P0, P1, P2)')
    g.add_argument('--format', choices=['text', 'json', 'html'], default='text', help='Output format')

    # status
    s = sub.add_parser('status', help='Check milestone status against a run directory')
    s.add_argument('--milestone', required=True, help='Exit milestone name')
    s.add_argument('--run-dir', required=True, dest='run_dir', help='Run directory path')
    s.add_argument('--project', default='', help='Project name')
    s.add_argument('--phase', default='', help='Design phase')

    # sign-off
    so = sub.add_parser('sign-off', help='Record a sign-off for a milestone')
    so.add_argument('--milestone', required=True, help='Exit milestone name')
    so.add_argument('--run-dir', required=True, dest='run_dir', help='Run directory path')
    so.add_argument('--approver', required=True, help='Approver name')
    so.add_argument('--phase', default='', help='Design phase (P0/P1/P2/P3)')

    # list milestones
    sub.add_parser('list', help='List all available milestones')

    # list-checks
    lc = sub.add_parser('list-checks', help='List all checks in a milestone',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="""List checks in tabular format with check IDs, severity, phase, and status.

Examples:
  cbflow flow checklist list-checks --milestone FP_EXIT
  cbflow flow checklist list-checks --milestone PRO_EXIT --phase P2
  cbflow flow checklist list-checks --milestone BTO --phase P3 --run-dir . --summary
  cbflow flow checklist list-checks --milestone BTO --output checks_BTO.txt
""")
    lc.add_argument('--milestone', required=True, help='Milestone name (e.g., FP_EXIT, BTO, STA_SIGNOFF)')
    lc.add_argument('--phase', default='', help='Filter checks active at this phase (P0/P1/P2/P3)')
    lc.add_argument('--run-dir', dest='run_dir', default='', help='Run directory to evaluate PASS/FAIL status')
    lc.add_argument('--output', '-o', default='', help='Write output to file (no ANSI colors)')
    lc.add_argument('--summary', '-s', action='store_true', help='Show compact summary (counts by type/severity/category)')

    # add-check
    _fmt = argparse.RawDescriptionHelpFormatter
    ac = sub.add_parser('add-check', help='Add a check to a milestone',
        formatter_class=_fmt,
        description="""Add a new check to an exit milestone configuration.

Three check modes:
  1. Script-based:  --script <file> --criteria <expr>
  2. Grep-based:    --grep-file <report> --grep-pattern <regex> [--grep-pass-if found|not_found]
  3. File existence: --file-path <path>

Examples:
  cbflow flow checklist add-check --milestone PRO_EXIT --name timing_clean \\
    --type mandatory --description "Setup WNS must be >= 0" \\
    --script check_timing.tcl --criteria "setup_wns >= 0"

  cbflow flow checklist add-check --milestone BTO --name drc_zero \\
    --type mandatory --description "DRC violations must be zero" \\
    --grep-file "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt" \\
    --grep-pattern "Total.*0.*violation" --grep-pass-if found

  cbflow flow checklist add-check --milestone BTO --name gds_exists \\
    --type file --file-path r"outputs/${design_name}.gds"
""")
    ac.add_argument('--milestone', required=True, help='Target milestone')
    ac.add_argument('--name', required=True, help='Check name (unique identifier)')
    ac.add_argument('--type', dest='check_type', required=True,
                    choices=['mandatory', 'optional', 'file'],
                    help='Check type: mandatory, optional, or file')
    ac.add_argument('--description', help='Human-readable description')
    ac.add_argument('--script', help='Script to execute (TCL/Python)')
    ac.add_argument('--criteria', help='Pass/fail criteria expression')
    ac.add_argument('--grep-file', dest='grep_file', help='Report file to grep')
    ac.add_argument('--grep-pattern', dest='grep_pattern', help='Regex pattern to search')
    ac.add_argument('--grep-pass-if', dest='grep_pass_if', choices=['found', 'not_found'],
                    default='found', help='PASS if pattern is found or not_found (default: found)')
    ac.add_argument('--file-path', dest='file_path', help='File path for existence check')

    # remove-check
    rc = sub.add_parser('remove-check', help='Remove a check from a milestone')
    rc.add_argument('--milestone', required=True, help='Target milestone')
    rc.add_argument('--name', required=True, help='Check name to remove')

    # waiver
    w = sub.add_parser('waiver', help='Manage waivers (list, add, revoke)')
    w.add_argument('--action', required=True, choices=['list', 'add', 'revoke'], help='Waiver action')
    w.add_argument('--milestone', help='Milestone to filter or target')
    w.add_argument('--check', help='Check name (for add/revoke)')
    w.add_argument('--reason', help='Justification (for add)')
    w.add_argument('--approver', help='Approver name (for add)')
    w.add_argument('--expiry', help='Expiry date YYYY-MM-DD (for add, default: +90 days)')
    w.add_argument('--project', default='', help='Project scope (default: all)')
    w.add_argument('--waiver-id', dest='waiver_id', help='Waiver ID to revoke (e.g., W001)')

    return parser


def main() -> int:
    """Main entry point."""
    parser = create_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 0

    # Command dispatch
    commands = {
        'generate': cmd_generate,
        'status': cmd_status,
        'sign-off': cmd_signoff,
        'list': cmd_list,
        'list-checks': cmd_list_checks,
        'add-check': cmd_add_check,
        'remove-check': cmd_remove_check,
        'waiver': cmd_waiver,
    }

    if args.command in commands:
        return commands[args.command](args)
    else:
        logger.error(f"Unknown command: {args.command}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
