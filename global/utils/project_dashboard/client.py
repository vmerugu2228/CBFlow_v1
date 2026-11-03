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

    # Discipline tag (v3 schema addition, 2026-11-02). Resolved from the
    # primary run's flow_type via tcl_config_parser.get_flow_discipline so
    # Tier 3 of the smartgrid can filter published rows per discipline.
    # Legacy publishers that don't ship this leave the column NULL — the
    # reader treats NULL as 'PD'.
    payload['discipline'] = _resolve_discipline(runs, milestone,
                                                milestone_stage_map)

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
    required_stage. Return (absolute_run_dir, race_db_path).

    Discipline-agnostic: ask `tcl_config_parser.get_flow_stages(flow)` which
    flows contain `required_stage` instead of hardcoding the PD order
    (SYNTH_PNR / PNR / FP / FCFP / STA / SYNTH). Falls back to any run
    with a RACE DB when no flow claims the stage.
    """
    if not runs:
        return '', ''
    required = milestone_stage_map.get(milestone, '')

    # Score 0: flows whose get_flow_stages() contains required_stage.
    # Score 1: everything else (preserves original fallback shape).
    def _score(flow):
        if required:
            try:
                stages = _flow_stages(flow)
            except Exception:
                stages = ()
            if required in stages:
                return (0, flow)
        return (1, flow)
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


def _resolve_discipline(runs, milestone, milestone_stage_map):
    """Resolve the discipline that owns this publish's primary flow.

    Picking order:
      1. If milestone_stage_map maps milestone → required_stage, find the
         flow in `runs` whose node_configs contain required_stage. If
         that flow has a declared discipline, use it. This is the
         authoritative map — a BTO publish from a workspace with both
         SYNTH_PNR and SIM runs should tag as PD (SYNTH_PNR's discipline)
         because BTO's required_stage comes from SYNTH_PNR.
      2. Otherwise take the first flow in `runs` with a declared
         discipline (insertion-order iteration — flows typically appear
         in workspace-config order, which the user controls).
      3. Fallback to 'PD' when nothing matches.

    Never raises.
    """
    if not runs:
        return 'PD'
    try:
        import sys as _sys, os as _os
        _cmds = _os.path.join(_os.path.dirname(_os.path.dirname(
            _os.path.abspath(__file__))), 'commands')
        if _cmds not in _sys.path:
            _sys.path.insert(0, _cmds)
        from tcl_config_parser import get_flow_discipline
    except Exception:
        return 'PD'

    # Step 1: milestone → required_stage → owning flow.
    required_stage = (milestone_stage_map or {}).get(milestone, '')
    if required_stage:
        for flow in runs.keys():
            try:
                stages = _flow_stages(flow)
            except Exception:
                stages = ()
            if required_stage in stages:
                try:
                    disc = (get_flow_discipline(flow) or '').upper()
                except Exception:
                    disc = ''
                if disc:
                    return disc

    # Step 2: first flow in runs with a declared discipline.
    for flow in runs.keys():
        try:
            disc = (get_flow_discipline(flow) or '').upper()
        except Exception:
            disc = ''
        if disc:
            return disc
    return 'PD'


def _flow_stages(flow_type):
    """Return the stages a flow owns, read from its node_config via the
    standard resolver. Cached per-flow because every publish touches it
    and resolver spawning tclsh is slow (~100ms).
    """
    cache = getattr(_flow_stages, '_cache', None)
    if cache is None:
        cache = _flow_stages._cache = {}
    if flow_type in cache:
        return cache[flow_type]
    try:
        import sys as _sys, os as _os
        _cmds = _os.path.join(_os.path.dirname(_os.path.dirname(
            _os.path.abspath(__file__))), 'commands')
        if _cmds not in _sys.path:
            _sys.path.insert(0, _cmds)
        from tcl_config_parser import get_flow_stages
        stages = tuple(get_flow_stages(flow_type) or ())
    except Exception:
        stages = ()
    cache[flow_type] = stages
    return stages


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
        # Read-only tap into the per-run RACE DB. Use the shared helper so
        # busy_timeout / PRAGMA set matches the daemon writer — otherwise
        # a long client scan can collide with concurrent engine writes
        # and surface SQLITE_BUSY instead of waiting.
        _utils_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if _utils_dir not in sys.path:
            sys.path.insert(0, _utils_dir)
        from core.db import sqlite_connect as _sqlite_connect
        conn = _sqlite_connect(race_db_path)
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

def _project_config_paths(project):
    """Return every project-config file to scan for `set project(...)` keys.

    Pre-fix: this helper returned ONLY the pre-split monolith at
    PD/config/project/<project>/v1.0.0/<project>_config.tcl — which the
    cbflow_global refactor deleted. Every published SmartGrid snapshot
    then showed empty tapeout_date / current_phase / technology /
    metal_stack / phases because the file never existed.

    Post-split layout (per CLAUDE.md config cascade):
      1. global/config/project/<project>/<ver>/project_config.tcl
         — identity + hierarchy + tapeout + dft/verif params
      2. PD/config/project/<project>/<ver>/project_pd_config.tcl
         — PD overlay (release, lsf, lib_root, metal_stack)

    Scan both and merge; later files win on duplicate keys (matches the
    actual cascade order used by the engine).
    """
    version = os.environ.get('FLOW_CONFIG_VERSION', 'v1.0.0')
    paths = []
    # Global project config
    global_root = os.environ.get('CBFLOW_GLOBAL_DIR', '')
    if global_root:
        paths.append(os.path.join(global_root, 'config', 'project',
                                   project, version, 'project_config.tcl'))
    # PD overlay
    flow_dir = os.environ.get('FLOW_DIR')
    if not flow_dir:
        flow_dir = os.path.abspath(
            os.path.join(SCRIPT_DIR, os.pardir, os.pardir))
    paths.append(os.path.join(flow_dir, 'config', 'project', project,
                               version, 'project_pd_config.tcl'))
    # Legacy monolith — kept as a fallback for pre-split installs that
    # haven't migrated yet. Scanned LAST so it never shadows the split
    # files when both exist.
    paths.append(os.path.join(flow_dir, 'config', 'project', project,
                               version, f'{project}_config.tcl'))
    return paths


def _project_config_path(project):
    """Back-compat shim — returns the first existing path, or the
    legacy monolith path if none exist (callers only use this for
    diagnostics)."""
    for p in _project_config_paths(project):
        if os.path.isfile(p):
            return p
    return _project_config_paths(project)[-1]


def _read_project_info(project):
    """Extract the header-tile values we care about from the project config."""
    paths = _project_config_paths(project)
    info = {}
    # Concatenate all existing config bodies — later files override
    # earlier ones because _grab uses first-match-wins and we scan
    # the concatenation in reverse-priority order (lowest first).
    bodies = []
    for p in paths:
        if not os.path.isfile(p):
            continue
        try:
            with open(p, encoding='utf-8', errors='replace') as f:
                bodies.append(f.read())
        except OSError:
            continue
    if not bodies:
        return info
    # PD overlay should override global — scan PD-overlay body FIRST so
    # the first-match-wins regex grabs its value when both declare the
    # same key (matches the engine's cascade behavior).
    text = '\n'.join(reversed(bodies))
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
