"""Snapshot builder + client for CBflow-ProjectDashboard.

Called by `cbflow run release` (best-effort by default: publishes only if
the daemon is already running; `--publish` starts it, `--no-publish`
skips). Builds the snapshot payload from
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
import checklist_stats
import dash_config


# ─── Payload construction ───────────────────────────────────────────────────

def build_payload(project, block, phase, milestone, release_dir, workspace,
                  runs, milestone_stage_map, published_by, override=False,
                  flow='', attach_to='', checklist_milestone=None):
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
      flow              flow whose release this is (cell identity)
      attach_to         signoff run (STA / PV / LEC …): the exit it verified;
                        verdict from its metrics.rpt Status
      checklist_milestone  checklist to snapshot (default: milestone; a
                        signoff run's <FLOW>_SIGNOFF; '' = none)
    """
    payload = {
        'op': 'publish',
        'block': block, 'phase': phase, 'milestone': milestone,
        'flow': flow, 'attach_to': attach_to,
        'published_by': published_by,
        'override': override,
        'release_tag': os.path.basename(os.path.normpath(release_dir)),
        'release_dir': release_dir,
    }

    primary_run_dir, race_db_path = _select_primary_run(
        workspace, runs, milestone, milestone_stage_map)
    payload['run_dir'] = primary_run_dir
    if not flow:
        # Packaged release: the cell's flow is the primary run's flow
        payload['flow'] = next((f for f, rd in runs.items()
                                if os.path.join(workspace, rd) == primary_run_dir), '')
    payload['race_db_path'] = race_db_path
    if primary_run_dir:
        payload['run_id'] = _run_id_for(primary_run_dir)

    # Manifest / release marker on disk
    manifest_path = os.path.join(release_dir, dash_config.release_name('marker,manifest'))
    manifest = _read_json(manifest_path)
    if manifest:
        payload['released_by'] = manifest.get('user') or published_by
        payload['released_at'] = manifest.get('timestamp')

    payload['project_info'] = _read_project_info(project)
    payload['block_info'] = _read_block_info(project, block)

    _ckm = milestone if checklist_milestone is None else checklist_milestone
    metrics, checklist, verdict, closability = _read_run_snapshot(
        race_db_path, _ckm)
    payload['metrics'] = metrics
    payload['checklist'] = checklist
    payload['verdict'] = verdict
    payload['closability_pct'] = closability
    if attach_to and not _ckm:
        payload['checklist'], payload['closability_pct'] = [], None

    # Discipline tag: the discipline owning the cell's flow
    # (flow(discipline,<FLOW>) in flow_registry.tcl) — Tier 3 filters on it.
    if not payload['flow']:
        raise ValueError('publish: no flow for this release (no workspace run '
                         'matches the primary run)')
    payload['discipline'] = dash_config.registry.flow_discipline(payload['flow'])

    files = []
    for kind, key in (('MANIFEST', 'marker,manifest'),
                      ('RELEASE_COMPLETE', 'marker,complete'),
                      ('CHANGELOG', 'file,changelog')):
        name = dash_config.release_name(key)
        p = os.path.join(release_dir, name)
        if os.path.isfile(p):
            files.append({'kind': kind, 'rel_path': name,
                          'sha256': _sha256(p)})
    # Images under <release_dir>/<release(dir,images)>/ — kind IMAGE_<TAG>,
    # tag = filename up to the first '_' or '.' (routing_layout.png -> IMAGE_ROUTING)
    img_sub = dash_config.release_name('dir,images')
    img_dir = os.path.join(release_dir, img_sub)
    if os.path.isdir(img_dir):
        for name in sorted(os.listdir(img_dir)):
            if os.path.splitext(name)[1].lower() in ('.png', '.jpg', '.jpeg', '.svg', '.gif', '.webp'):
                tag = re.split(r'[_.]', name, 1)[0].upper() or 'IMAGE'
                p = os.path.join(img_dir, name)
                files.append({'kind': f'IMAGE_{tag}', 'rel_path': f'{img_sub}/{name}',
                              'sha256': _sha256(p)})
    payload['files'] = files
    # Release metrics report (metrics.rpt): "Key : value" lines grouped by
    # "# category: <c>" headers — written by the flow for the exit it fills.
    report = _read_metrics_report(os.path.join(release_dir,
                                               dash_config.release_name('file,metrics')))
    payload['metrics'] = payload['metrics'] + report
    if attach_to:
        # Signoff verdict: the flow's own "Status" line (PASS / FAIL)
        status = next((m['value'] for m in report if m['name'] == 'Status'), '').upper()
        payload['verdict'] = {'PASS': 'PASS', 'FAIL': 'BLOCKED'}.get(status, 'UNKNOWN')

    # Floorplan snapshot — DEF + LEF macro dimensions. Parsers are
    # defensive and return empty on missing / stub files, so we always
    # include the block (the row is only inserted when there's real data).
    try:
        import floorplan as _fp
        payload['floorplan'] = _fp.extract_from_release(
            release_dir, primary_run_dir, block)
    except dash_config.RegistryError:
        raise                                    # config problem: report it
    except Exception:
        payload['floorplan'] = {
            'def_path': '', 'lef_paths': [],
            'def': {'boundary': {}, 'rows': [], 'cells': [], 'units': 1000},
            'macros': {},
        }

    # Timing snapshot — first 100 paths per clock group. Real STA report
    # parsers live in the STA flow; here we just pass through a pre-built
    # JSON if one was dropped at one of release(file,timing_snapshot).
    # Shape must match tracker_db.set_timing().
    timing = _load_timing_snapshot(release_dir)
    if timing:
        payload['timing'] = timing
    return payload


def _read_metrics_report(path):
    """[{category, name, value, scenario}] from a metrics report; [] when
    absent. "# category: <c>" starts a group; "# scenario: <s>" tags the
    following lines with a scenario until the next category / scenario."""
    out, cat, scen = [], 'other', ''
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                m = re.match(r'#\s*category:\s*(\S+)', line)
                if m:
                    cat, scen = m.group(1), ''
                    continue
                m = re.match(r'#\s*scenario:\s*(\S+)', line)
                if m:
                    scen = m.group(1)
                    continue
                if not line or line.startswith('#') or ' : ' not in line:
                    continue
                k, v = line.split(' : ', 1)
                out.append({'category': cat, 'name': k.strip(), 'value': v.strip(),
                            'scenario': scen})
    except OSError:
        pass
    return out


def _load_timing_snapshot(release_dir):
    """Look for a pre-built timing snapshot next to the release. Returns
    the parsed payload or None. Silently ignores malformed files — timing
    is optional and shouldn't fail the publish."""
    import json
    for name in dash_config.release_names('file,timing_snapshot'):
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


def publish(project, payload, start_daemon=True):
    """Send the built payload to the daemon.

    start_daemon=True starts the daemon if it is not running. With
    start_daemon=False nothing is spawned: if no daemon is running the
    reply is {'ok': False, 'no_daemon': True, ...} — used by the default
    (best-effort) release publish so a release on a batch / CI host does
    not leave a web daemon behind.

    Returns the JSON reply dict.
    """
    if start_daemon:
        lifecycle.ensure_daemon(project)
    elif not lifecycle.is_running(project):
        return {'ok': False, 'no_daemon': True,
                'error': f'SmartGrid daemon is not running for project {project}'}
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
                'metric_value, threshold, severity, detail, check_id, description '
                'FROM checklist_results WHERE milestone=?',
                (milestone,)):
                checklist.append(dict(r))
        except sqlite3.Error:
            pass
        conn.close()
    except sqlite3.Error:
        return metrics, checklist, verdict, closability

    # Verdict + closability from mandatory checks (shared rule).
    verdict, closability = checklist_stats.verdict_of(checklist)
    return metrics, checklist, verdict, closability


# ─── Config reads (project + block) ─────────────────────────────────────────

def _read_project_info(project):
    """Header-tile values from the project config (core.registry)."""
    return dash_config.project_info(project)


def _read_block_info(project, block):
    """DL level / parent / description of the block from project(design_hierarchy)."""
    info = {'block_name': block}
    spec = dash_config.hierarchy(project).get(block)
    if spec:
        info.update({'dl_level': spec['level'], 'parent': spec['parent'],
                     'description': spec['description']})
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
