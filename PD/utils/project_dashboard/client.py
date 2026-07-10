"""Snapshot builder + client for CBflow-ProjectDashboard.

Called by `cbflow run release --publish`. Builds the snapshot payload from
the just-completed release (workspace runs + on-disk release dir + each
run's RACE DB), then sends it to the project-dashboard daemon over its
control socket.
"""

import hashlib
import json
import os
import re
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import lifecycle


# ─── Payload construction ───────────────────────────────────────────────────

def build_payload(project, block, phase, milestone, release_dir, workspace,
                  runs, milestone_stage_map, published_by, override=False):
    """Assemble the publish payload from workspace runs + on-disk release.

    Args:
      project           project name (bumblebee / denali / ...)
      block             design/block name
      phase             phase string (LC1 / P0 / ...)
      milestone         exit milestone (BTO / PLACE_EXIT / ...)
      release_dir       directory just written by cmd_release
      workspace         workarea dir containing the runs
      runs              dict {flow_type: run_dir_name}
      milestone_stage_map  dict {milestone: required_stage}
      published_by      user running publish
      override          bool — allow replacing existing cell
    """
    payload = {
        'op': 'publish',
        'block': block, 'phase': phase, 'milestone': milestone,
        'published_by': published_by,
        'override': override,
        'release_tag': f'{phase}_{milestone}',
        'release_dir': release_dir,
    }

    primary_run_dir, race_db_path = _select_primary_run(
        workspace, runs, milestone, milestone_stage_map)
    payload['run_dir'] = primary_run_dir
    payload['race_db_path'] = race_db_path
    if primary_run_dir:
        payload['run_id'] = _run_id_for(primary_run_dir)

    # Manifest / release marker on disk
    manifest_path = os.path.join(release_dir, 'MANIFEST.json')
    manifest = _read_json(manifest_path)
    if manifest:
        payload['released_by'] = manifest.get('user') or published_by
        payload['released_at'] = manifest.get('timestamp')

    payload['project_info'] = _read_project_info(project)
    payload['block_info'] = _read_block_info(project, block)

    metrics, checklist, verdict, closability = _read_run_snapshot(
        race_db_path, milestone)
    payload['metrics'] = metrics
    payload['checklist'] = checklist
    payload['verdict'] = verdict
    payload['closability_pct'] = closability

    files = []
    for kind, name in (('MANIFEST', 'MANIFEST.json'),
                       ('RELEASE_COMPLETE', 'RELEASE_COMPLETE'),
                       ('CHANGELOG', 'CHANGELOG.md')):
        p = os.path.join(release_dir, name)
        if os.path.isfile(p):
            files.append({'kind': kind, 'rel_path': name,
                          'sha256': _sha256(p)})
    payload['files'] = files

    # Floorplan snapshot — DEF + LEF macro dimensions. Parsers are
    # defensive and return empty on missing / stub files, so we always
    # include the block (the row is only inserted when there's real data).
    try:
        import floorplan as _fp
        payload['floorplan'] = _fp.extract_from_release(
            release_dir, primary_run_dir)
    except Exception:
        payload['floorplan'] = {
            'def_path': '', 'lef_paths': [],
            'def': {'boundary': {}, 'rows': [], 'cells': [], 'units': 1000},
            'macros': {},
        }

    # Timing snapshot — first 100 paths per clock group. Real STA report
    # parsers live in the STA flow; here we just pass through a pre-built
    # JSON if one was dropped at `<release_dir>/timing_snapshot.json` (or
    # under a `timing/` subdir). Shape must match tracker_db.set_timing().
    timing = _load_timing_snapshot(release_dir)
    if timing:
        payload['timing'] = timing
    return payload


def _load_timing_snapshot(release_dir):
    """Look for a pre-built timing snapshot next to the release. Returns
    the parsed payload or None. Silently ignores malformed files — timing
    is optional and shouldn't fail the publish."""
    import json
    for name in ('timing_snapshot.json', 'timing/snapshot.json'):
        p = os.path.join(release_dir, name)
        if not os.path.isfile(p):
            continue
        try:
            with open(p) as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(data, dict) and isinstance(data.get('clock_groups'), list):
            # Trim to first 100 paths per group, defensively.
            for g in data['clock_groups']:
                if isinstance(g.get('paths'), list) and len(g['paths']) > 100:
                    g['paths'] = g['paths'][:100]
            return data
    return None


def publish(project, payload):
    """Send the built payload to the daemon (starts it if not running).

    Returns the JSON reply dict.
    """
    lifecycle.ensure_daemon(project)
    return lifecycle.send_publish(project, payload)


# ─── Primary-run selection ──────────────────────────────────────────────────

def _select_primary_run(workspace, runs, milestone, milestone_stage_map):
    """Pick the workspace run whose flow_type generated the milestone's
    required_stage. Return (absolute_run_dir, race_db_path)."""
    if not runs:
        return '', ''
    required = milestone_stage_map.get(milestone, '')
    # Prefer flows that plausibly contain the required stage.
    ordering = ['SYNTH_PNR', 'PNR', 'FP', 'FCFP', 'STA', 'SYNTH']
    def _score(flow):
        try:
            return (0, ordering.index(flow))
        except ValueError:
            return (1, len(ordering))
    for flow in sorted(runs.keys(), key=_score):
        run_dir = os.path.join(workspace, runs[flow])
        db = _resolve_race_db(run_dir)
        if db:
            return run_dir, db
    # No RACE DB found on any run — return first flow anyway.
    fallback = list(runs.items())[0]
    return os.path.join(workspace, fallback[1]), ''


def _resolve_race_db(run_dir):
    pointer = os.path.join(run_dir, '.race_db_pointer')
    if os.path.isfile(pointer):
        try:
            with open(pointer) as f:
                p = f.read().strip()
            if p and os.path.isfile(p):
                return p
        except OSError:
            pass
    for name in sorted(os.listdir(run_dir)):
        if name.startswith('.race_') and name.endswith('.db'):
            return os.path.join(run_dir, name)
    return ''


def _run_id_for(run_dir):
    canonical = os.path.realpath(os.path.abspath(run_dir))
    return hashlib.md5(canonical.encode()).hexdigest()[:12]


# ─── RACE DB reads ──────────────────────────────────────────────────────────

def _read_run_snapshot(race_db_path, milestone):
    """Pull metrics + checklist rows from a run's RACE DB.

    Returns (metrics, checklist, verdict, closability_pct).
    Verdict is derived from mandatory checklist results.
    """
    metrics, checklist = [], []
    verdict = 'UNKNOWN'
    closability = None
    if not race_db_path or not os.path.isfile(race_db_path):
        return metrics, checklist, verdict, closability

    try:
        conn = sqlite3.connect(race_db_path)
        conn.row_factory = sqlite3.Row
        # stage_metrics
        try:
            for r in conn.execute(
                'SELECT stage, metric_name, metric_value '
                'FROM stage_metrics'):
                metrics.append({
                    'category': 'stage',
                    'name': r['metric_name'],
                    'value': r['metric_value'],
                    'scenario': r['stage'],
                })
        except sqlite3.Error:
            pass
        # metrics_snapshot
        try:
            for r in conn.execute(
                'SELECT stage, node_name, metric_category, metric_name, '
                'metric_value, metric_unit, scenario, corner '
                'FROM metrics_snapshot'):
                metrics.append({
                    'category': r['metric_category'],
                    'name': r['metric_name'],
                    'value': r['metric_value'],
                    'unit': r['metric_unit'],
                    'scenario': r['scenario'] or r['stage'],
                    'corner': r['corner'],
                })
        except sqlite3.Error:
            pass
        # checklist_results for this milestone
        try:
            for r in conn.execute(
                'SELECT milestone, check_name, check_type, category, status, '
                'metric_value, threshold, severity, detail '
                'FROM checklist_results WHERE milestone=?',
                (milestone,)):
                checklist.append(dict(r))
        except sqlite3.Error:
            pass
        conn.close()
    except sqlite3.Error:
        return metrics, checklist, verdict, closability

    # Verdict + closability from mandatory checks.
    mandatory = [c for c in checklist if c.get('check_type') == 'mandatory']
    if mandatory:
        passed = sum(1 for c in mandatory if c.get('status') in ('PASS', 'SKIPPED'))
        waived = sum(1 for c in mandatory if c.get('status') == 'WAIVED')
        blocked = sum(1 for c in mandatory
                      if c.get('status') in ('FAIL', 'PENDING', None))
        closability = round(100.0 * passed / len(mandatory), 1)
        if blocked > 0:
            verdict = 'BLOCKED'
        elif waived > 0:
            verdict = 'CONDITIONAL'
        else:
            verdict = 'PASS'
    return metrics, checklist, verdict, closability


# ─── Config reads (project + block) ─────────────────────────────────────────

def _project_config_path(project):
    """Locate PD/config/project/<project>/v1.0.0/<project>_config.tcl."""
    flow_dir = os.environ.get('FLOW_DIR')
    if not flow_dir:
        flow_dir = os.path.abspath(
            os.path.join(SCRIPT_DIR, os.pardir, os.pardir))
    version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    return os.path.join(flow_dir, 'config', 'project', project, version,
                        f'{project}_config.tcl')


def _read_project_info(project):
    """Extract the header-tile values we care about from the project config."""
    path = _project_config_path(project)
    info = {}
    if not os.path.isfile(path):
        return info
    try:
        with open(path) as f:
            text = f.read()
    except OSError:
        return info
    def _grab(key):
        m = re.search(r'^\s*set\s+project\(' + re.escape(key)
                      + r'\)\s+"([^"]*)"', text, re.MULTILINE)
        return m.group(1) if m else None
    info['tapeout_date'] = _grab('tapeout_date')
    info['current_phase'] = _grab('current_phase')
    info['technology'] = _grab('technology')
    info['metal_stack'] = _grab('metal_stack')
    info['lib_config_tag'] = _grab('lib_config_tag')
    info['cbflow_release'] = _grab('cbflow_release')
    info['developed_by'] = _grab('dashboard,developed_by')
    # phases is a Tcl list
    m = re.search(r'^\s*set\s+project\(phases\)\s+\{([^}]*)\}',
                  text, re.MULTILINE)
    if m:
        info['phases'] = m.group(1).split()
    return info


def _read_block_info(project, block):
    """Get DL level + parent for the block from the project's design_hierarchy."""
    path = _project_config_path(project)
    info = {'block_name': block}
    if not os.path.isfile(path):
        return info
    try:
        with open(path) as f:
            text = f.read()
    except OSError:
        return info
    m = re.search(r'^\s*set\s+project\(design_hierarchy\)\s+\{(.*?)^\}',
                  text, re.MULTILINE | re.DOTALL)
    if not m:
        return info
    body = m.group(1)
    # Very loose scan: find `<block> {` then within its braces pluck level/parent.
    idx = body.find(block + ' {')
    if idx < 0:
        return info
    # Balanced-brace slice
    depth, i = 1, body.find('{', idx) + 1
    start = i
    while i < len(body) and depth > 0:
        if body[i] == '{':
            depth += 1
        elif body[i] == '}':
            depth -= 1
        i += 1
    entry = body[start:i-1]
    for k in ('level', 'parent', 'description'):
        mk = re.search(r'\b' + k + r'\s+"([^"]*)"', entry)
        if mk:
            info['dl_level' if k == 'level' else k] = mk.group(1)
    return info


# ─── Helpers ────────────────────────────────────────────────────────────────

def _read_json(path):
    if not os.path.isfile(path):
        return {}
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _sha256(path):
    h = hashlib.sha256()
    try:
        with open(path, 'rb') as f:
            for chunk in iter(lambda: f.read(65536), b''):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return ''
