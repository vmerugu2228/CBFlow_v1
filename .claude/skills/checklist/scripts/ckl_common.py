#!/usr/bin/env python3
"""Shared read-only helpers of the checklist skill scripts.

Not a CLI. Reuses the framework's own checklist resolution
(PD/utils/commands/checklist_cmd.py: milestone config + the run's tool-overlay
checklist map) so the scripts see exactly the checks `cbflow flow checklist
status` evaluates, and reads the run's RACE DB, status JSONs, the exit-policy
Tcl files (remediation / threshold overrides / waivers) and the learned store.
Nothing here writes outside the learned store (learn.py does that).
"""
import glob
import json
import os
import re
import sqlite3
import subprocess
import sys

SK = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
ROOT = os.path.abspath(os.path.join(SK, '..', '..', '..'))
EXIT_DIR = os.path.join(ROOT, 'global', 'config', 'exit', 'v1.0.0')
RELEASE_CFG = os.path.join(ROOT, 'PD', 'config', 'flow', 'v1.0.0', 'release_config.tcl')
LEARNED = os.path.join(SK, 'learned')

_CC = None


def cc():
    """The framework checklist module (imported once, functions used read-only)."""
    global _CC
    if _CC is None:
        sys.path.insert(0, os.path.join(ROOT, 'PD', 'utils', 'commands'))
        os.environ.setdefault('CBFLOW_ROOT', ROOT)
        os.environ.setdefault('CBFLOW_GLOBAL_DIR', os.path.join(ROOT, 'global'))
        import logging
        import checklist_cmd  # noqa: E402
        logging.getLogger('cbflow.checklist').setLevel(logging.ERROR)
        _CC = checklist_cmd
    return _CC


# ── run context ──────────────────────────────────────────────────────────────
def run_db(run_dir):
    return cc()._find_run_db(run_dir)


def _q(db, sql, args=()):
    if not db:
        return []
    try:
        con = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
        rows = con.execute(sql, args).fetchall()
        con.close()
        return rows
    except sqlite3.Error:
        return []


def run_context(run_dir):
    """flow / phase / project / block / design / tech of a run (DB first,
    .run.cbflow.tcl as fallback)."""
    run_dir = os.path.abspath(run_dir)
    db = run_db(run_dir)
    env = dict(_q(db, "SELECT key, value FROM run_config WHERE key LIKE 'env.%'"))
    info = dict(_q(db, 'SELECT key, value FROM run_info'))
    rc = os.path.join(run_dir, '.run.cbflow.tcl')
    if os.path.exists(rc):
        for k, v in re.findall(r'set ::env\((\w+)\) "([^"]*)"', open(rc).read()):
            env.setdefault('env.' + k, v)
    g = lambda k: env.get('env.' + k, '')  # noqa: E731
    ctx = {
        'run_dir': run_dir, 'run': os.path.basename(run_dir), 'db': db,
        'flow': info.get('flow_type') or g('CBFLOW_FLOW_TYPE') or cc()._detect_flow_type(run_dir),
        'phase': g('CBFLOW_PROJECT_PHASE') or cc()._detect_phase(run_dir),
        'project': info.get('project') or g('CBFLOW_PROJECT_NAME'),
        'block': g('CBFLOW_BLOCK_NAME') or g('CBFLOW_DESIGN_NAME'),
        'design': g('CBFLOW_DESIGN_NAME') or g('CBFLOW_BLOCK_NAME'),
        'tech': g('TECH_NAME') or '_unknown_tech',
    }
    # checklist_cmd expands ${design_name} from the environment
    if ctx['design']:
        os.environ['CBFLOW_DESIGN_NAME'] = ctx['design']
    os.environ['CBFLOW_FLOW_TYPE'] = ctx['flow'] or ''
    return ctx


def node_state(ctx, rel_path):
    """State of the node owning work/<FLOW>/<node>/... : BYPASSED marker,
    missing dir, or its latest RACE job status."""
    m = re.match(r'work/([^/]+)/([^/]+)/', rel_path or '')
    if not m:
        return '', ''
    flow, node = m.groups()
    ndir = os.path.join(ctx['run_dir'], 'work', flow, node)
    if os.path.exists(os.path.join(ndir, 'BYPASSED')):
        return node, 'BYPASSED (work/%s/%s/BYPASSED)' % (flow, node)
    row = _q(ctx['db'], 'SELECT status, error_msg FROM jobs WHERE job_name=? ORDER BY id DESC LIMIT 1', (node,))
    if not os.path.isdir(ndir):
        return node, 'node not in this run' + (f' (DB: {row[0][0]})' if row else '')
    if row:
        st, err = row[0]
        return node, f'job {st}' + (f': {err}' if err else '')
    return node, 'node dir present, no job record'


# ── checklist results / config ───────────────────────────────────────────────
def latest_status(run_dir, milestone, path=None):
    """(source, data) — the newest logs/checklist_status_<M>_*.json, else the
    RACE DB checklist_results rows shaped like the JSON."""
    if path:
        return path, json.load(open(path))
    files = sorted(glob.glob(os.path.join(run_dir, 'logs', f'checklist_status_{milestone}_*.json')))
    if files:
        return files[-1], json.load(open(files[-1]))
    rows = _q(run_db(run_dir), 'SELECT check_name, check_type, status, metric_value, detail, evaluated_at '
              'FROM checklist_results WHERE milestone=?', (milestone,))
    if not rows:
        return None, None
    data = {'milestone': milestone, 'timestamp': rows[0][5], 'mandatory_checks': [],
            'optional_checks': [], 'library_checks': [], 'file_status': [], 'blocking_items': []}
    for n, t, s, v, d, _ in rows:
        data.setdefault(f'{t}_checks', []).append({'name': n, 'status': s, 'value': v, 'detail': d})
    return 'RACE DB checklist_results', data


def resolved_config(milestone, run_dir):
    cfg, path = cc()._load_and_validate_config(milestone, run_dir)
    if not cfg:
        sys.exit(f'checklist: milestone {milestone} not found / not parseable')
    return cfg, path


def all_milestones():
    return sorted(os.path.basename(p)[:-11] for p in glob.glob(os.path.join(EXIT_DIR, '*_config.tcl'))
                  if not os.path.basename(p).startswith(('remediation', 'threshold', 'waiver')))


def release_lists():
    """MILESTONE_ORDER and TAPEOUT_MILESTONES from release_config.tcl."""
    t = open(RELEASE_CFG).read()
    get = lambda n: (re.search(r'set %s \{([^}]*)\}' % n, t) or [None, ''])[1].split()  # noqa: E731
    return get('MILESTONE_ORDER'), get('TAPEOUT_MILESTONES') or ['BTO', 'MTO']


# ── Tcl policy files ─────────────────────────────────────────────────────────
_DUMP = r'''
proc handle_info args {}; proc handle_warning args {}
rename puts _puts; proc puts args {}
if {[catch {source [lindex $argv 0]} e]} { _puts stderr $e }
foreach a [lrange $argv 1 end] {
  if {![array exists $a]} continue
  foreach k [array names $a] {
    set v [set ${a}($k)]
    if {[string match *,suggestions $k]} { set v [join $v "\x1e"] }
    _puts "$a\x1f$k\x1f[string map {\n { }} $v]"
  }
}
'''


def tcl_arrays(path, *names):
    """{array: {key: value}} of a Tcl data file sourced in tclsh."""
    out = {n: {} for n in names}
    if not os.path.exists(path):
        return out
    r = subprocess.run(['tclsh', '/dev/stdin', path, *names], input=_DUMP,
                       capture_output=True, text=True, timeout=60)
    for line in r.stdout.split("\n"):  # not splitlines(): it splits on \x1e
        p = line.split('\x1f')
        if len(p) == 3:
            out[p[0]][p[1]] = p[2]
    return out


def remediations():
    a = tcl_arrays(os.path.join(EXIT_DIR, 'remediation_config.tcl'), 'remediation')['remediation']
    res = {}
    for k, v in a.items():
        key, field = k.rsplit(',', 1)
        res.setdefault(key, {})[field] = v.split('\x1e') if field == 'suggestions' else v
    return res


def threshold_policy():
    return tcl_arrays(os.path.join(EXIT_DIR, 'threshold_overrides.tcl'),
                      'default_thresholds', 'phase_defaults', 'threshold_override', 'phase_override')


def policy_threshold(pol, project, phase, milestone, metric):
    """Layered default -> phase_defaults -> project -> project+phase; returns
    (value, layer) or (None, '')."""
    val, layer = None, ''
    for arr, key in (('default_thresholds', f'{milestone},{metric}'),
                     ('phase_defaults', f'{phase},{milestone},{metric}'),
                     ('threshold_override', f'{project},{milestone},{metric}'),
                     ('phase_override', f'{project},{phase},{milestone},{metric}')):
        if key in pol.get(arr, {}):
            val, layer = pol[arr][key], f'{arr}({key})'
    return val, layer


def waiver_policy():
    return tcl_arrays(os.path.join(EXIT_DIR, 'waiver_config.tcl'), 'waiver_policy')['waiver_policy']


def literal_head(rx):
    """Leading literal text of a regex ('^Setup WNS\\s*:' -> 'Setup WNS')."""
    out, i = [], 0
    rx = re.sub(r'^\(\?\w+\)', '', rx).lstrip('^')
    while i < len(rx):
        ch = rx[i]
        if ch == '\\' and i + 1 < len(rx):
            if rx[i + 1].isalnum():
                break
            out.append(rx[i + 1]); i += 2; continue
        if ch in '[](){}*+?.|$^':
            break
        out.append(ch); i += 1
    return ''.join(out).strip()


# ── check-name → remediation / threshold metric ──────────────────────────────
_KEYS = [  # (regex on check name, remediation key, threshold metric)
    (r'hold.*tns', 'hold_wns', 'hold_tns'),
    (r'tns', 'setup_tns', 'setup_tns'),
    (r'hold', 'hold_wns', 'hold_wns'),
    (r'setup|wns|timing$|reg2reg|cross_corner', 'setup_wns', 'setup_wns'),
    (r'skew', 'clock_skew', 'clock_skew'),
    (r'clock_cov|coverage_clock', 'clock_coverage', 'clock_coverage'),
    (r'clock_power', 'clock_power', ''),
    (r'congest|overflow', 'congestion', 'max_congestion'),
    (r'antenna', 'antenna_violations', ''),
    (r'density', 'metal_density', ''),
    (r'drc', 'drc_violations', 'drc_violations'),
    (r'\bir_|ir_drop', 'ir_drop', 'max_ir_drop'),
    (r'(^|_)em(_|$)|electromig', 'em_violations', ''),
    (r'lvs', 'lvs_mismatch', ''),
    (r'gds', 'gds_errors', ''),
    (r'util', 'utilization_high', 'utilization_max'),
]


POLICY_UNIT = {'setup_wns': 'ps', 'setup_tns': 'ps', 'hold_wns': 'ps', 'hold_tns': 'ps', 'clock_skew': 'ps',
               'max_ir_drop': 'mV', 'utilization_max': 'ratio', 'max_congestion': 'ratio',
               'clock_coverage': '%', 'drc_violations': 'count'}


def check_keys(name):
    for rx, rem, met in _KEYS:
        if re.search(rx, name):
            return rem, met
    return '', ''


# ── learned store ────────────────────────────────────────────────────────────
ENTRY_RX = re.compile(r'^- (\d{4}-\d{2}-\d{2}) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| (.*)$')
FIELDS = ('date', 'phase', 'milestone', 'check', 'kind', 'run', 'text')


def learned_entries(tech, block=None):
    """Entries of learned/<tech>/_tech.md (+ <block>.md) as dicts (scope added)."""
    files = [('tech', os.path.join(LEARNED, tech, '_tech.md'))]
    if block:
        files.append(('block', os.path.join(LEARNED, tech, f'{block}.md')))
    out = []
    for scope, f in files:
        if not os.path.exists(f):
            continue
        for line in open(f):
            m = ENTRY_RX.match(line.rstrip('\n'))
            if m:
                e = dict(zip(FIELDS, (x.strip() for x in m.groups())))
                e['scope'] = scope
                out.append(e)
    return out


def rel(ctx, path):
    if not path:
        return ''
    return os.path.relpath(path, ctx['run_dir']) if os.path.isabs(path) else path
