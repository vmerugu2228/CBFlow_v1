"""HTTP routing for the dashboard daemon.

Routes:
  GET  /                          Index page (list of registered runs)
  GET  /api/runs                  JSON list of runs
  GET  /static/<...>              Shared static assets
  GET  /run/<id>/<suffix>         Delegate to DashboardHandler with self.path=/<suffix>
  POST /run/<id>/<suffix>         Same delegation; ownership check preserved
"""

import http.server
import json
import os
import re
import sqlite3
import threading
from collections import OrderedDict
from pathlib import Path
from urllib.parse import urlparse

import race_dashboard
import registry
import state_paths

_PD_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# ── Pool ────────────────────────────────────────────────────────────────────

class DashboardPool:
    """LRU cache of RaceDashboard instances keyed on run_id.

    RaceDashboard holds no expensive resources (a string + a cached env dict +
    a db_path), so eviction = drop reference. The pool exists to avoid
    re-reading run_info on every request.
    """

    def __init__(self, max_size=20):
        self._lock = threading.Lock()
        self._cache = OrderedDict()
        self._max = max_size

    def get(self, run_id):
        """Return a RaceDashboard for run_id, or None if no such run is
        registered or its run_dir has vanished."""
        rec = registry.get(run_id)
        if not rec:
            return None
        run_dir = rec['run_dir']
        if not os.path.isdir(run_dir):
            return None
        with self._lock:
            if run_id in self._cache:
                self._cache.move_to_end(run_id)
                return self._cache[run_id]
            dash = race_dashboard.RaceDashboard(run_dir)
            self._cache[run_id] = dash
            if len(self._cache) > self._max:
                self._cache.popitem(last=False)
            return dash

    def evict(self, run_id):
        with self._lock:
            self._cache.pop(run_id, None)

    def cached_ids(self):
        with self._lock:
            return list(self._cache.keys())


# ── Handler factory ─────────────────────────────────────────────────────────

def make_daemon_handler(pool):
    """Return a request-handler class bound to the given pool. We build it
    fresh per server so each daemon instance has its own pool reference."""

    parent = race_dashboard.DashboardHandler

    class DaemonHandler(parent):
        # Override the class attribute so a stray request without /run/<id>/
        # prefix gets a clear 404 instead of NoneType on first .dashboard access.
        dashboard = None

        # Per-request: set by do_GET / do_POST after parsing /run/<id>/...
        # Used by the template-URL rewriter so absolute /api/... and nav links
        # in the existing HTML/JS get prefixed with /run/<id>/ before we ship
        # the response.
        _daemon_run_id = None

        # Quieter access log — Apache-style one line per request to the daemon log.
        def log_message(self, fmt, *args):
            try:
                msg = fmt % args
            except TypeError:
                msg = fmt
            print(f'[{self.address_string()}] {self.command} {self.path} -> {msg}', flush=True)

        # ── Pre-parse path prefix and dispatch ──────────────────────────────

        def _split_run_prefix(self):
            """If self.path starts with /run/<id>/<rest>, return (run_id, rest).
            Otherwise (None, None)."""
            parsed = urlparse(self.path)
            p = parsed.path
            if not p.startswith('/run/'):
                return None, None
            tail = p[len('/run/'):]
            if '/' not in tail:
                # /run/<id> with no trailing slash → treat as /run/<id>/
                run_id = tail
                rest = '/'
            else:
                run_id, rest = tail.split('/', 1)
                rest = '/' + rest
            if parsed.query:
                rest = f'{rest}?{parsed.query}'
            return run_id, rest

        def do_GET(self):
            parsed = urlparse(self.path)
            p = parsed.path.rstrip('/') or '/'

            if p == '/':
                self._serve_index()
                return
            if p == '/api/runs':
                self._serve_api_runs()
                return
            if p == '/api/daemon-status':
                self._serve_api_daemon_status()
                return
            if p == '/api/discover-runs':
                self._serve_api_discover_runs()
                return
            if p.startswith('/static/'):
                # Shared static assets — borrow the parent's _serve_static.
                # parent expects self.dashboard set (it only reads STATIC_DIR
                # via module-level constants), so a sentinel will do.
                self.dashboard = _NullDashboard()
                parent._serve_static(self, p[len('/static/'):])
                return

            run_id, rest = self._split_run_prefix()
            if not run_id:
                self.send_error(404)
                return

            dash = pool.get(run_id)
            if not dash:
                self.send_error(404, f'no such run: {run_id}')
                return

            registry.touch(run_id)
            self.dashboard = dash
            self._daemon_run_id = run_id
            self.path = rest
            parent.do_GET(self)

        def do_POST(self):
            parsed = urlparse(self.path)
            p = parsed.path.rstrip('/') or '/'

            # Daemon-only top-level endpoints (driven by the index UI).
            if p == '/api/register':
                self._serve_api_register()
                return
            if p == '/api/deregister':
                self._serve_api_deregister()
                return

            run_id, rest = self._split_run_prefix()
            if not run_id:
                self.send_error(404)
                return
            dash = pool.get(run_id)
            if not dash:
                self.send_error(404, f'no such run: {run_id}')
                return
            registry.touch(run_id)
            self.dashboard = dash
            self._daemon_run_id = run_id
            self.path = rest
            parent.do_POST(self)

        # ── Helpers for the new daemon-level endpoints ──────────────────────

        def _read_json_body(self):
            length = int(self.headers.get('Content-Length') or 0)
            if not length:
                return {}
            raw = self.rfile.read(length)
            try:
                return json.loads(raw.decode('utf-8'))
            except (ValueError, UnicodeDecodeError):
                return {}

        def _write_json(self, payload, status=200):
            body = json.dumps(payload).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _serve_api_register(self):
            body = self._read_json_body()
            run_dir = (body.get('run_dir') or '').strip()
            if not run_dir:
                self._write_json({'ok': False, 'error': 'run_dir is required'}, 400)
                return
            run_dir_abs = os.path.realpath(os.path.abspath(os.path.expanduser(run_dir)))
            if not os.path.isdir(run_dir_abs):
                self._write_json(
                    {'ok': False, 'error': f'not a directory: {run_dir_abs}'}, 400)
                return
            try:
                rec = registry.register(run_dir_abs)
            except ValueError as e:
                # Project-scope mismatch (or other registry validation).
                self._write_json({'ok': False, 'error': str(e)}, 400)
                return
            pool.evict(rec['run_id'])  # force re-instantiation against fresh disk state
            self._write_json({'ok': True, 'run_id': rec['run_id'],
                              'url': f'/run/{rec["run_id"]}/'})

        def _serve_api_deregister(self):
            body = self._read_json_body()
            target = (body.get('run_id') or body.get('run_dir') or '').strip()
            if not target:
                self._write_json({'ok': False, 'error': 'run_id or run_dir is required'}, 400)
                return
            rid = (target if not (os.sep in target or '/' in target)
                   else registry.run_id_for(target))
            removed = registry.deregister(rid)
            pool.evict(rid)
            self._write_json({'ok': removed,
                              'error': None if removed else 'not registered'})

        def _serve_api_discover_runs(self):
            registered = {r['run_dir'] for r in registry.list_all()}
            runs = _discover_runs(_PD_DIR)
            for r in runs:
                r['registered'] = r['run_dir'] in registered
            self._write_json({'runs': runs})

        def _serve_api_daemon_status(self):
            pid_text = ''
            port_text = ''
            try:
                with open(state_paths.pidfile()) as f:
                    pid_text = f.read().strip()
            except OSError:
                pass
            try:
                with open(state_paths.portfile()) as f:
                    port_text = f.read().strip()
            except OSError:
                pass
            self._write_json({
                'pid': pid_text,
                'port': port_text,
                'pool_size': len(pool.cached_ids()),
            })

        # ── HTML rewrite: absolute /api/... and nav links → /run/<id>/... ──

        def _serve_template(self, name):
            """Re-implement the parent's _serve_template so we can rewrite
            absolute URLs (/api/..., href="/", href="/dag", href="/grid")
            into daemon-scoped /run/<id>/... before shipping the response.

            Static <link href="/static/..."> stays as-is — the daemon already
            exposes /static/ at the root."""
            import os as _os
            from race_dashboard import TEMPLATES_DIR

            filepath = _os.path.join(TEMPLATES_DIR, name)
            if not _os.path.exists(filepath):
                self.send_error(404, f'Template not found: {name}')
                return

            with open(filepath, 'rb') as f:
                content = f.read()

            # Re-apply the same {{TOKEN}} substitutions the parent does.
            import state_paths
            run_info = self.dashboard.get_status().get('run_info', {}) or {}
            content = content.replace(b'{{FLOW_TYPE}}', run_info.get('flow_type', '').encode())
            content = content.replace(b'{{PROJECT}}', run_info.get('project', '').encode())
            content = content.replace(b'{{RUN_DIR}}', self.dashboard.run_dir.encode())
            content = content.replace(b'{{RESULT}}', run_info.get('result', '').encode())
            content = content.replace(b'{{DISCIPLINE}}', state_paths.get_discipline().encode())

            # Now the daemon-scope rewrites.
            if self._daemon_run_id:
                prefix = f'/run/{self._daemon_run_id}'.encode()
                # fetch('/api/...') and friends — prefix any quoted absolute /api/ path.
                content = content.replace(b"'/api/", b"'" + prefix + b"/api/")
                content = content.replace(b'"/api/', b'"' + prefix + b'/api/')
                # Nav links inside dashboard.html / dag.html / grid.html.
                content = content.replace(b'href="/"', b'href="' + prefix + b'/"')
                content = content.replace(b'href="/dag"', b'href="' + prefix + b'/dag"')
                content = content.replace(b'href="/grid"', b'href="' + prefix + b'/grid"')

            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)

        # ── Daemon-only endpoints ───────────────────────────────────────────

        def _serve_index(self):
            runs = registry.list_all()
            import state_paths
            html = _render_index(runs,
                                 discipline=state_paths.get_discipline(),
                                 project=state_paths.get_project())
            body = html.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _serve_api_runs(self):
            # On every list, also stamp a `run_dir_exists` field so the UI
            # can show "DELETED" before the 30 s sweeper persists it.
            # Also stamp current_node / current_status by reading each run's
            # .race_*.db read-only — drives the Current Status column.
            runs = registry.list_all()
            for r in runs:
                run_dir = r.get('run_dir') or ''
                r['run_dir_exists'] = bool(run_dir) and os.path.isdir(run_dir)
                if r['run_dir_exists']:
                    st = _current_status_for_run(run_dir)
                else:
                    st = {'node': '', 'status': 'NONE',
                          'start_time': '', 'runtime_sec': None}
                r['current_node']    = st['node']
                r['current_status']  = st['status']
                r['current_start']   = st['start_time']
                r['current_runtime'] = st['runtime_sec']
                _info = _project_info_for(r.get('project') or '')
                r['tapeout_date']    = _info['tapeout_date']
                r['project_info']    = _info
            body = json.dumps(runs, indent=2).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return DaemonHandler


# ── Discovery: scan workareas from project configs ──────────────────────────

_WORKAREA_RE = re.compile(r'set\s+project\(workarea_path\)\s+"([^"]+)"')
_RUN_DIR_RE = re.compile(r'^P\d+_run_')


def _project_workarea_paths(pd_dir):
    """All workarea paths declared in PD/config/project/*/*/*_config.tcl."""
    project_root = os.path.join(pd_dir, 'config', 'project')
    paths = set()
    if not os.path.isdir(project_root):
        return paths
    for entry in os.listdir(project_root):
        proj_dir = os.path.join(project_root, entry)
        if not os.path.isdir(proj_dir):
            continue
        for root, _dirs, files in os.walk(proj_dir):
            for f in files:
                if not f.endswith('_config.tcl'):
                    continue
                cfg = os.path.join(root, f)
                try:
                    with open(cfg) as fh:
                        for line in fh:
                            m = _WORKAREA_RE.search(line)
                            if m:
                                paths.add((entry, m.group(1)))
                                break
                except OSError:
                    continue
    return paths


_PROJECT_INFO_CACHE = {}  # {project_name: {technology, metal_stack, lib_config_tag, cbflow_release, tapeout_date}}

_PROJECT_KEYS_OF_INTEREST = (
    'technology',
    'metal_stack',
    'lib_config_tag',
    'cbflow_release',
    'tapeout_date',
)


def _project_info_for(project_name):
    """Read selected project(...) values from PD/config/project/<name>/v1.0.0/
    <name>_config.tcl in a single pass. Returns a dict with keys
    matching _PROJECT_KEYS_OF_INTEREST (missing values come back '').

    Cached per-process — project_config rarely changes during a daemon's
    lifetime, and the per-poll cost would otherwise be a file read per run."""
    if not project_name:
        return {k: '' for k in _PROJECT_KEYS_OF_INTEREST}
    if project_name in _PROJECT_INFO_CACHE:
        return _PROJECT_INFO_CACHE[project_name]
    cfg = os.path.join(_PD_DIR, 'config', 'project', project_name, 'v1.0.0',
                       f'{project_name}_config.tcl')
    out = {k: '' for k in _PROJECT_KEYS_OF_INTEREST}
    interest = set(_PROJECT_KEYS_OF_INTEREST)
    try:
        with open(cfg) as fh:
            for line in fh:
                m = re.match(r'^\s*set\s+project\(([^)]+)\)\s+"([^"]*)"', line)
                if not m:
                    continue
                key, val = m.group(1).strip(), m.group(2).strip()
                if key in interest:
                    out[key] = val
                    interest.discard(key)
                    if not interest:
                        break
    except OSError:
        pass
    _PROJECT_INFO_CACHE[project_name] = out
    return out


def _tapeout_date_for(project_name):
    """Back-compat wrapper — milestone-block JS still consumes tapeout_date
    as a top-level field on each run; the rest of project_info ships
    alongside it."""
    return _project_info_for(project_name).get('tapeout_date', '')


def _read_env_field(run_dir, key):
    """Read one `export KEY=VALUE` from a run's .run.cbflow.env. Empty on miss."""
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if not os.path.exists(env_file):
        return ''
    try:
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line.startswith('export ') and '=' in line:
                    k, v = line[7:].split('=', 1)
                    if k == key:
                        return v.strip('"').strip("'")
    except OSError:
        pass
    return ''


def _flow_type_for(run_dir):
    return _read_env_field(run_dir, 'CBFLOW_FLOW_TYPE')


def _discover_runs(pd_dir):
    """Return a list of run directories under any project's workarea_path.

    Each entry: {project, design, name, run_dir, flow_type}.

    project comes from the run's own .run.cbflow.env (CBFLOW_PROJECT_NAME)
    — NOT from the project iterator that found the workarea. Multiple
    projects often share one workarea_path (e.g. denali + ravendrive both
    point at workarea/, with their designs in workarea/tom/ and
    workarea/cpu_core/); using the iterator's project name would tag every
    discovered run with whichever project sorted first.

    Caller layers `registered` on top via the registry.
    """
    out = []
    seen = set()
    for _iter_project, wa in _project_workarea_paths(pd_dir):
        if not os.path.isdir(wa):
            continue
        for design in sorted(os.listdir(wa)):
            design_path = os.path.join(wa, design)
            if not os.path.isdir(design_path):
                continue
            for name in sorted(os.listdir(design_path)):
                if not _RUN_DIR_RE.match(name):
                    continue
                run_dir = os.path.join(design_path, name)
                if not os.path.isdir(run_dir) or run_dir in seen:
                    continue
                seen.add(run_dir)
                # Project comes from the run's own env (authoritative).
                # Fall back to the iterator's project only if env is missing,
                # which preserves something useful for runs that pre-date the
                # CBFLOW_PROJECT_NAME export.
                run_project = _read_env_field(run_dir, 'CBFLOW_PROJECT_NAME') \
                              or _iter_project
                out.append({
                    'project': run_project,
                    'design': design,
                    'name': name,
                    'run_dir': run_dir,
                    'flow_type': _flow_type_for(run_dir),
                })
    return out


# ── Helpers ─────────────────────────────────────────────────────────────────

class _NullDashboard:
    """Sentinel so the parent's _serve_static can run without a real dashboard."""
    db_path = ''
    run_dir = ''
    flow_type = ''


_FLOW_COLORS = {
    'SYNTH':     '#7c3aed', 'SYNTH_PNR': '#6366f1', 'PNR':       '#0ea5e9',
    'FP':        '#06b6d4', 'FCFP':      '#0891b2', 'STA':       '#10b981',
    'LEC':       '#f59e0b', 'CLP':       '#f97316', 'PV':        '#ef4444',
    'EMIR':      '#dc2626', 'POPT':      '#8b5cf6', 'ECO':       '#64748b',
}

# Status → (background, text) colors for the Current Status chip on the
# daemon index page. Single source consumed both server-side (cell render)
# and client-side (JS re-render via /api/runs).
_STATUS_COLORS = {
    'RUNNING':         ('#fde047', '#713f12'),   # bright yellow + dark text
    'FAIL':            ('#dc2626', '#ffffff'),   # red + white
    'DONE':            ('#10b981', '#ffffff'),   # green + white
    'BYPASSED':        ('#22c55e', '#052e16'),   # light green + dark text
    'FORCE_VALIDATED': ('#65a30d', '#ffffff'),   # olive + white
    'PENDING':         ('#94a3b8', '#0f172a'),   # gray + dark text
    'INVALIDATED':     ('#f97316', '#ffffff'),   # orange + white
    'READY':           ('#cbd5e1', '#475569'),   # light gray + slate text
    'NONE':            ('#e5e7eb', '#6b7280'),   # subtle gray for "no DB yet"
}

# Order in which we pick a representative status when many exist on a run.
# Highest priority wins — i.e. if anything is RUNNING, that's the "current"
# status; otherwise FAIL surfaces; etc.
_STATUS_PRIORITY = (
    'RUNNING', 'FAIL', 'INVALIDATED', 'PENDING',
    'DONE', 'BYPASSED', 'FORCE_VALIDATED', 'READY',
)


def _fmt_duration(sec):
    """Mirror of the JS fmtDuration() for SSR parity."""
    if sec is None or sec == '':
        return '—'
    try:
        s = max(0, int(round(float(sec))))
    except (TypeError, ValueError):
        return '—'
    h, rem = divmod(s, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f'{h}h {m:02d}m {s:02d}s'
    if m:
        return f'{m}m {s:02d}s'
    return f'{s}s'


def _find_run_db(run_dir):
    """Find the .race_*.db for a run. Mirrors race_dashboard._find_db's
    resolution order but read-only and side-effect-free: pointer file first,
    then local glob; returns None if neither yields an existing file."""
    pointer = os.path.join(run_dir, '.race_db_pointer')
    if os.path.isfile(pointer):
        try:
            with open(pointer) as fh:
                p = fh.read().strip()
            if p and os.path.isfile(p):
                return p
        except OSError:
            pass
    try:
        for f in Path(run_dir).glob('.race_*.db'):
            return str(f)
    except OSError:
        pass
    return None


def _current_status_for_run(run_dir):
    """Return {'node', 'status', 'start_time', 'runtime_sec'} for the run's
    most relevant job.

    Priority — first match wins:
      1. Any RUNNING subnode  → that's the live one
      2. Most recent FAIL     → user needs to see this
      3. Most recent DONE/BYPASSED/FORCE_VALIDATED → last activity
      4. Any PENDING / INVALIDATED → in queue
      5. All READY (never started) → 'Not started' / READY
      6. No DB / no jobs row / DB unreadable → returns NONE

    runtime_sec: for completed jobs the stored value; for RUNNING jobs None
    (the client computes live elapsed from start_time on each render).
    """
    none = {'node': '', 'status': 'NONE', 'start_time': '', 'runtime_sec': None}
    db_path = _find_run_db(run_dir)
    if not db_path:
        return none
    try:
        conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True, timeout=0.5)
    except sqlite3.Error:
        return none
    try:
        cur = conn.cursor()
        rows = cur.execute(
            "SELECT stage, COALESCE(subnode,''), status, "
            "COALESCE(start_time,'') AS st, "
            "COALESCE(end_time, start_time,'') AS ts, "
            "runtime_sec "
            "FROM jobs "
            "WHERE id IN (SELECT MAX(id) FROM jobs GROUP BY job_name) "
            "AND job_type = 'subnode'"
        ).fetchall()
    except sqlite3.Error:
        return none
    finally:
        conn.close()

    if not rows:
        return none

    by_status = {}
    for stage, subnode, status, start, ts, rtsec in rows:
        by_status.setdefault(status, []).append((stage, subnode, start, ts, rtsec))

    for st in _STATUS_PRIORITY:
        if st in by_status:
            stage, subnode, start, _ts, rtsec = max(
                by_status[st], key=lambda r: r[3] or '')
            node = f'{stage}/{subnode}' if subnode else stage
            return {'node': node, 'status': st,
                    'start_time': start or '', 'runtime_sec': rtsec}

    # Status outside known set — surface it as-is so we see it on the UI.
    stage, subnode, status, start, _ts, rtsec = rows[0]
    node = f'{stage}/{subnode}' if subnode else stage
    return {'node': node, 'status': status,
            'start_time': start or '', 'runtime_sec': rtsec}


def _render_index(runs, discipline='PD', project=''):
    """Index page for the per-user dashboard daemon.

    Stdlib-only (no JS framework). Vanilla CSS + a small client script that
    talks to /api/runs, /api/register, /api/deregister.

    `project` (when set) puts the daemon in per-project scope — narrows the
    visible runs to that project, shows the project name in the header pill,
    and changes the page title.
    """
    disc = (discipline or 'PD').upper()
    disc_label = disc
    project = (project or '').strip()
    disc_pill_bg = '#0d9488' if disc == 'DFT' else '#1565c0'
    disc_pill_border = '#0f766e' if disc == 'DFT' else '#0d47a1'
    disc_banner_grad = ('linear-gradient(135deg, #0d9488 0%, #0ea5e9 55%, #6366f1 100%)'
                        if disc == 'DFT'
                        else 'linear-gradient(135deg, #4f46e5 0%, #7c3aed 50%, #0ea5e9 100%)')
    if project:
        title_prefix = f'CBflow {disc} · {project} Dashboard'
    else:
        title_prefix = f'CBflow {disc} Dashboard'
    project_pill_html = (
        f'<span class="project-pill" title="Per-project daemon scope">'
        f'{project.upper()}</span>') if project else ''
    active = [r for r in runs if not r.get('archived')]
    archived = [r for r in runs if r.get('archived')]
    project_set = {r.get('project') for r in active if r.get('project')}
    design_set = {r.get('design') for r in active if r.get('design')}

    # SSR initial values for the project-metadata stat chips. Seeds from
    # the first active run that has a project tag — the JS poll at +5s
    # recomputes with the full nearest-tapeout logic. This avoids a flash
    # of em-dashes on first paint.
    _ssr_pick_project = next((r.get('project') for r in active if r.get('project')), '')
    _ssr_chip_initial = _project_info_for(_ssr_pick_project)

    # Stamp current_node / current_status server-side too so the initial
    # paint shows real status (otherwise every row would briefly read "NONE"
    # until the first JS poll fires at +5s).
    for _r in runs:
        _run_dir = _r.get('run_dir') or ''
        if _run_dir and os.path.isdir(_run_dir):
            _st = _current_status_for_run(_run_dir)
            _r['current_node']    = _st['node']
            _r['current_status']  = _st['status']
            _r['current_start']   = _st['start_time']
            _r['current_runtime'] = _st['runtime_sec']
            _info = _project_info_for(_r.get('project') or '')
            _r['tapeout_date']    = _info['tapeout_date']
            _r['project_info']    = _info
            _r['run_dir_exists']  = True
        else:
            _r.setdefault('current_node', '')
            _r.setdefault('current_status', 'NONE')
            _r.setdefault('current_start', '')
            _r.setdefault('current_runtime', None)
            _r.setdefault('tapeout_date', '')
            _r.setdefault('project_info', {k: '' for k in _PROJECT_KEYS_OF_INTEREST})
            _r['run_dir_exists']  = False

    rows_html = _render_run_rows(runs) or (
        '<tr><td colspan="6" class="empty">'
        'No runs registered. Add one above to get started.'
        '</td></tr>'
    )

    return f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<title>{title_prefix}</title>
<style>
  :root {{
    --bg:         #f6f7fb;
    --panel:      #ffffff;
    --border:     #e5e7eb;
    --text:       #1f2937;
    --muted:      #6b7280;
    --accent:     #4f46e5;
    --accent-d:   #4338ca;
    --danger:     #dc2626;
    --danger-d:   #b91c1c;
    --success:    #10b981;
    --shadow:     0 1px 3px rgba(0,0,0,.06), 0 1px 2px rgba(0,0,0,.04);
  }}
  * {{ box-sizing: border-box; }}
  html, body {{ margin: 0; padding: 0; background: var(--bg); color: var(--text);
                font: 14px/1.5 -apple-system, BlinkMacSystemFont, 'Segoe UI',
                Roboto, Oxygen, Ubuntu, sans-serif; }}

  header.banner {{
    background: {disc_banner_grad};
    color: white;
    padding: 28px 36px 28px;
    box-shadow: 0 4px 12px rgba(79,70,229,.18);
  }}
  header.banner .discipline-pill {{
    display:inline-block;
    background: {disc_pill_bg};
    border: 1px solid {disc_pill_border};
    color: #fff;
    padding: 4px 14px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: .08em;
    text-transform: uppercase;
    box-shadow: 0 2px 6px rgba(0,0,0,.18);
  }}
  header.banner .project-pill {{
    display:inline-block;
    background: rgba(0,0,0,.32);
    border: 1px solid rgba(255,255,255,.30);
    color: #fff;
    padding: 4px 14px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: .08em;
    text-transform: uppercase;
    box-shadow: 0 2px 6px rgba(0,0,0,.18);
  }}
  header.banner .logo-row {{ display: flex; align-items: center; gap: 14px; }}
  header.banner .logo {{ font-size: 26px; font-weight: 700; letter-spacing: -.02em; }}
  header.banner .logo .lite {{ font-weight: 400; opacity: .85; margin-left: 6px; }}
  header.banner .engine-pill {{ background: rgba(255,255,255,.18);
                                 border: 1px solid rgba(255,255,255,.28);
                                 padding: 3px 10px; border-radius: 999px;
                                 font-size: 11px; font-weight: 600;
                                 letter-spacing: .06em; text-transform: uppercase;
                                 backdrop-filter: blur(6px); }}
  header.banner .byline {{ margin-top: 4px; font-size: 12px; opacity: .82;
                            letter-spacing: .01em; }}
  header.banner .stats {{ display: flex; gap: 12px; margin-top: 18px; flex-wrap: wrap; }}
  header.banner .stat {{ background: rgba(255,255,255,.13); padding: 8px 14px;
                         border-radius: 8px; font-size: 13px; backdrop-filter: blur(6px);
                         border: 1px solid rgba(255,255,255,.15); }}
  header.banner .stat b {{ font-weight: 600; }}

  main {{ max-width: 1280px; margin: 0 auto; padding: 24px 24px 64px; }}

  .panel {{ background: var(--panel); border: 1px solid var(--border);
            border-radius: 12px; box-shadow: var(--shadow); margin-bottom: 20px; }}
  .panel-hd {{ padding: 14px 20px; border-bottom: 1px solid var(--border);
               display: flex; align-items: center; justify-content: space-between; gap: 12px; }}
  .panel-hd h2 {{ margin: 0; font-size: 15px; font-weight: 600; }}
  .panel-hd .toolbar {{ display: flex; gap: 8px; align-items: center; }}

  input[type="text"], input[type="search"] {{
    border: 1px solid var(--border); border-radius: 8px;
    padding: 8px 12px; font: inherit; outline: none; min-width: 240px;
    transition: border-color .15s, box-shadow .15s;
  }}
  input[type="text"]:focus, input[type="search"]:focus {{
    border-color: var(--accent);
    box-shadow: 0 0 0 3px rgba(79,70,229,.18);
  }}

  button {{ border: 0; padding: 8px 14px; border-radius: 8px; font: inherit;
            font-weight: 500; cursor: pointer; transition: background .15s, transform .05s; }}
  button:active {{ transform: translateY(1px); }}
  button.primary {{ background: var(--accent); color: white; }}
  button.primary:hover {{ background: var(--accent-d); }}
  button.danger {{ background: transparent; color: var(--danger); padding: 4px 10px; font-size: 12px;
                   border: 1px solid var(--danger); border-radius: 6px; }}
  button.danger:hover {{ background: var(--danger); color: white; }}

  form.register {{ display: flex; gap: 10px; padding: 16px 20px; align-items: center;
                   flex-wrap: wrap; }}
  form.register label {{ font-size: 12px; color: var(--muted); }}
  form.register input[type="text"] {{ flex: 1; min-width: 320px; }}

  button.ghost {{ background: transparent; color: var(--muted);
                  border: 1px solid var(--border); }}
  button.ghost:hover {{ background: #f9fafb; color: var(--text); }}
  button.ghost.open {{ background: var(--accent); color: white; border-color: var(--accent); }}

  .picker {{ display: none; border-top: 1px solid var(--border);
             max-height: 320px; overflow-y: auto; background: #fafbff; }}
  .picker.open {{ display: block; }}
  .picker-group {{ padding: 4px 0; }}
  .picker-group-hd {{ position: sticky; top: 0; background: #eef1f9;
                       padding: 4px 20px; font-size: 11px; color: var(--muted);
                       font-weight: 600; text-transform: uppercase;
                       letter-spacing: .05em; z-index: 1; }}
  .picker-row {{ display: grid; grid-template-columns: 1fr auto auto auto;
                  gap: 12px; align-items: center; padding: 8px 20px;
                  cursor: pointer; transition: background .12s;
                  border-top: 1px solid #f1f2f6; }}
  .picker-row:hover {{ background: rgba(79,70,229,.07); }}
  .picker-row.registered {{ cursor: default; opacity: .55; }}
  .picker-row.registered:hover {{ background: transparent; }}
  .picker-row .pname {{ font-weight: 500; font-size: 13px; }}
  .picker-row .pdir  {{ font-family: 'SF Mono', Menlo, Consolas, monospace;
                         font-size: 11px; color: var(--muted);
                         white-space: nowrap; overflow: hidden;
                         text-overflow: ellipsis; max-width: 360px; }}
  .picker-row .reg-pill {{ background: var(--success); color: white;
                            padding: 1px 8px; border-radius: 999px;
                            font-size: 10px; font-weight: 600; letter-spacing: .04em; }}
  .picker-empty {{ padding: 16px 20px; color: var(--muted); text-align: center;
                    font-style: italic; }}
  .picker-count {{ padding: 6px 20px; font-size: 11px; color: var(--muted);
                    background: white; border-bottom: 1px solid var(--border); }}
  .picker-toolbar {{ display: flex; gap: 8px; padding: 8px 20px;
                      background: white; border-bottom: 1px solid var(--border);
                      flex-wrap: wrap; }}
  .picker-toolbar select.flow-filter {{ font-size: 12px; padding: 5px 26px 5px 10px; }}

  table.runs {{ width: 100%; border-collapse: collapse; }}
  table.runs thead th {{ text-align: left; font-weight: 600; font-size: 12px;
                          color: var(--muted); text-transform: uppercase; letter-spacing: .04em;
                          padding: 10px 16px; border-bottom: 1px solid var(--border);
                          background: #fafbff; }}
  table.runs tbody td {{ padding: 12px 16px; border-bottom: 1px solid #f1f2f6;
                          vertical-align: middle; }}
  table.runs tbody tr:hover {{ background: #f9fafb; }}
  table.runs tbody tr.archived td {{ color: var(--muted); }}
  table.runs tbody tr.archived td:first-child {{ opacity: .7; }}

  td.empty {{ text-align: center; color: var(--muted); padding: 32px !important; }}

  a.runlink {{ color: var(--accent); text-decoration: none; font-weight: 600;
               font-size: 13.5px; letter-spacing: -0.01em; }}
  a.runlink:hover {{ text-decoration: underline; }}

  .flow-badge {{ display: inline-block; padding: 2px 10px; border-radius: 999px;
                  color: white; font-size: 11px; font-weight: 600;
                  letter-spacing: .04em; }}

  /* Flow filter dropdown in the toolbar */
  select.flow-filter {{ border: 1px solid var(--border); border-radius: 8px;
                         padding: 7px 28px 7px 12px; font: inherit; font-size: 13px;
                         background: white url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="10" height="6" viewBox="0 0 10 6"><polygon points="0,0 10,0 5,6" fill="%236b7280"/></svg>') no-repeat right 10px center;
                         appearance: none; -webkit-appearance: none; cursor: pointer; }}
  select.flow-filter:focus {{ outline: none; border-color: var(--accent);
                              box-shadow: 0 0 0 3px rgba(79,70,229,.18); }}

  /* Current Status column — colored chip + current node id */
  td.status-cell {{ white-space: nowrap; }}
  .status-chip {{ display: inline-block; padding: 2px 9px; border-radius: 999px;
                   font-size: 10.5px; font-weight: 700; letter-spacing: .05em;
                   text-transform: uppercase; font-variant-numeric: tabular-nums; }}
  .status-node {{ display: inline-block; margin-left: 8px; font-size: 12px;
                   color: var(--text); font-family: 'SF Mono', Menlo, Consolas, monospace; }}
  .status-node.muted {{ color: var(--muted); font-family: inherit; }}

  /* Runtime cell */
  td.rt-cell {{ white-space: nowrap; font-variant-numeric: tabular-nums;
                font-family: 'SF Mono', Menlo, Consolas, monospace; font-size: 12px; }}
  .rt.muted {{ color: var(--muted); font-family: inherit; }}
  .rt.running {{ color: #b45309; font-weight: 600; }}    /* amber for live elapsed */

  /* Banner layout — left column for stats, right column for milestone */
  header.banner {{ display: flex; align-items: flex-start;
                   justify-content: space-between; gap: 32px; }}
  header.banner .banner-left {{ flex: 1 1 auto; min-width: 0; }}

  /* Right-side milestone block — project + phase + tapeout aggregate */
  .milestone-block {{ flex: 0 0 auto; align-self: flex-start;
                       background: rgba(255,255,255,.16);
                       border: 1px solid rgba(255,255,255,.30);
                       padding: 18px 24px; border-radius: 14px;
                       backdrop-filter: blur(10px); color: #fff;
                       min-width: 260px; box-shadow: 0 4px 14px rgba(0,0,0,.18); }}
  .milestone-block .ms-project {{ font-size: 22px; font-weight: 800;
                                    letter-spacing: -0.01em; line-height: 1.15;
                                    text-transform: uppercase;
                                    padding-bottom: 10px; margin-bottom: 10px;
                                    border-bottom: 1px solid rgba(255,255,255,.22); }}
  .milestone-block .ms-row {{ display: flex; justify-content: space-between;
                                align-items: baseline; gap: 18px;
                                font-size: 14px; line-height: 1.7; }}
  .milestone-block .ms-label {{ opacity: .72; text-transform: uppercase;
                                  font-size: 11px; letter-spacing: .10em;
                                  font-weight: 600; }}
  .milestone-block .ms-phase {{ font-weight: 800; font-size: 18px;
                                  font-variant-numeric: tabular-nums; }}
  .milestone-block .ms-tapeout {{ font-family: 'SF Mono', Menlo, Consolas, monospace;
                                    font-size: 15px; font-weight: 600;
                                    letter-spacing: -0.01em; }}
  .milestone-block .ms-weeks-line {{ margin-top: 10px; padding-top: 10px;
                                       border-top: 1px solid rgba(255,255,255,.22);
                                       font-size: 13px; font-weight: 700;
                                       letter-spacing: .03em; text-align: right; }}
  .milestone-block .ms-weeks-line.ovd  {{ color: #fecaca; }}
  .milestone-block .ms-weeks-line.soon {{ color: #fed7aa; }}
  .milestone-block .ms-weeks-line.mid  {{ color: #fef3c7; }}
  .milestone-block .ms-weeks-line.far  {{ color: #d1fae5; }}

  .state {{ display: inline-flex; align-items: center; gap: 6px; font-size: 12px;
            color: var(--muted); }}
  .state .dot {{ width: 8px; height: 8px; border-radius: 50%; background: var(--success); }}
  .state.archived .dot {{ background: #9ca3af; }}

  /* Deleted-on-disk badge */
  .deleted-pill {{ background: var(--danger); color: white; padding: 1px 8px;
                   border-radius: 999px; font-size: 10px; font-weight: 600;
                   letter-spacing: .04em; margin-left: 8px; }}
  tr.deleted td:first-child {{ opacity: .55; }}
  tr.deleted .dir {{ text-decoration: line-through; }}

  .dir {{ font-family: 'SF Mono', Menlo, Consolas, monospace; font-size: 12px;
          color: var(--muted); word-break: break-all; }}

  .ts {{ font-size: 12px; color: var(--muted); white-space: nowrap; }}

  .toast {{ position: fixed; right: 20px; bottom: 20px; background: var(--text);
            color: white; padding: 12px 16px; border-radius: 8px;
            box-shadow: 0 8px 24px rgba(0,0,0,.16); opacity: 0;
            transition: opacity .2s, transform .2s; transform: translateY(8px); }}
  .toast.show {{ opacity: 1; transform: translateY(0); }}
  .toast.error {{ background: var(--danger); }}

  footer {{ text-align: center; color: var(--muted); font-size: 12px; padding: 24px 0 0; }}
  footer code {{ background: #eef1f6; padding: 2px 6px; border-radius: 4px; font-size: 11px; }}
</style>
</head><body>

<header class="banner">
  <div class="banner-left">
    <div class="logo-row">
      <div class="logo">CBflow<span class="lite">Dashboard</span></div>
      <span class="discipline-pill" title="This dashboard serves the {disc} discipline">{disc_label}</span>
      {project_pill_html}
      <span class="engine-pill" title="Python-native DAG execution engine">RACE engine</span>
    </div>
    <div class="byline">Developed by SmartSoc</div>
    <div class="stats">
      <div class="stat">Active runs: <b id="stat-active">{len(active)}</b></div>
      <div class="stat">Tech: <b id="stat-tech">{_ssr_chip_initial.get('technology') or '—'}</b></div>
      <div class="stat">Metal stack: <b id="stat-metalstack">{_ssr_chip_initial.get('metal_stack') or '—'}</b></div>
      <div class="stat">Lib tag: <b id="stat-libtag">{_ssr_chip_initial.get('lib_config_tag') or '—'}</b></div>
      <div class="stat">CBflow: <b id="stat-cbflow">{_ssr_chip_initial.get('cbflow_release') or '—'}</b></div>
    </div>
  </div>
  <aside class="milestone-block" id="milestone-block"
         title="Project milestone — phase + nearest tapeout across active runs">
    <div class="ms-project" id="ms-project">—</div>
    <div class="ms-row">
      <span class="ms-label">Phase</span>
      <span class="ms-phase" id="ms-phase">—</span>
    </div>
    <div class="ms-row">
      <span class="ms-label">Tapeout</span>
      <span class="ms-tapeout" id="ms-tapeout-date">—</span>
    </div>
    <div class="ms-weeks-line" id="ms-weeks-line">—</div>
  </aside>
</header>

<main>
  <div class="panel">
    <div class="panel-hd">
      <h2>Register a run</h2>
    </div>
    <form class="register" id="register-form" autocomplete="off">
      <label for="reg-input">Run directory:</label>
      <input id="reg-input" type="text" placeholder="/absolute/path or type to filter discovered runs" required>
      <button type="button" class="ghost" id="picker-toggle" aria-expanded="false">Browse</button>
      <button type="submit" class="primary">Register</button>
    </form>
    <div id="picker" class="picker" aria-hidden="true">
      <div class="picker-toolbar">
        <select id="picker-project-filter" class="flow-filter" title="Filter by project">
          <option value="">All projects</option>
        </select>
        <select id="picker-design-filter"  class="flow-filter" title="Filter by block / design">
          <option value="">All blocks</option>
        </select>
        <select id="picker-flow-filter"    class="flow-filter" title="Filter by flow">
          <option value="">All flows</option>
        </select>
      </div>
      <div class="picker-count" id="picker-count">…</div>
      <div id="picker-body"></div>
    </div>
  </div>

  <div class="panel">
    <div class="panel-hd">
      <h2>Registered runs</h2>
      <div class="toolbar">
        <select id="project-filter" class="flow-filter" title="Filter by project">
          <option value="">All projects</option>
        </select>
        <select id="design-filter" class="flow-filter" title="Filter by block / design">
          <option value="">All blocks</option>
        </select>
        <select id="flow-filter" class="flow-filter" title="Filter by flow type">
          <option value="">All flows</option>
        </select>
        <input type="search" id="filter" placeholder="Filter by path, status, node…">
        <button class="primary" id="refresh" title="Reload from registry">Refresh</button>
      </div>
    </div>
    <table class="runs">
      <thead>
        <tr><th>Run</th><th>Flow</th><th>Current Status</th><th>Runtime</th><th>Run directory</th>
            <th></th></tr>
      </thead>
      <tbody id="runs-tbody">
{rows_html}
      </tbody>
    </table>
  </div>

  <footer>
    Runs also register themselves on <code>cbflow run gui --daemon</code>.
    CLI view: <code>cbflow dashboard list</code>.
  </footer>
</main>

<div id="toast" class="toast"></div>

<script>
  const FLOW_COLORS = {json.dumps(_FLOW_COLORS)};
  const STATUS_COLORS = {json.dumps(_STATUS_COLORS)};

  function flowBadge(flow) {{
    const color = FLOW_COLORS[flow] || '#475569';
    const txt = flow || '?';
    return `<span class="flow-badge" style="background:${{color}}">${{txt}}</span>`;
  }}

  function statusChip(node, status) {{
    const st = status || 'NONE';
    const pair = STATUS_COLORS[st] || STATUS_COLORS['NONE'];
    const bg = pair[0], fg = pair[1];
    const nodeHtml = node
      ? `<span class="status-node">${{node}}</span>`
      : `<span class="status-node muted">—</span>`;
    return `<span class="status-chip" style="background:${{bg}};color:${{fg}}" `
         + `title="${{node}} (${{st}})">${{st}}</span> ${{nodeHtml}}`;
  }}

  function _pickPrimaryRun(runs) {{
    // Same logic the milestone block uses to choose which run drives the
    // header chips: among active runs, prefer the nearest UPCOMING tapeout;
    // fall back to most-recently-past; then to any first active run.
    const active = runs.filter(r => !r.archived && r.run_dir_exists !== false);
    if (!active.length) return null;
    const dated = active
      .map(r => ({{r, t: r.tapeout_date ? Date.parse(r.tapeout_date) : NaN}}))
      .filter(x => !Number.isNaN(x.t));
    if (!dated.length) return active[0];
    const now      = Date.now();
    const upcoming = dated.filter(x => x.t >= now).sort((a, b) => a.t - b.t);
    return (upcoming.length ? upcoming[0]
                            : dated.sort((a, b) => b.t - a.t)[0]).r;
  }}

  function updateProjectMetaChips(runs) {{
    // Populate the project-metadata stat chips (Tech / Metal stack / Lib
    // tag / CBflow release) from the same primary run the milestone block
    // picks. Falls back to "—" when the chosen run lacks project_info.
    const pick = _pickPrimaryRun(runs);
    const info = (pick && pick.project_info) || {{}};
    document.getElementById('stat-tech').textContent       = info.technology     || '—';
    document.getElementById('stat-metalstack').textContent = info.metal_stack    || '—';
    document.getElementById('stat-libtag').textContent     = info.lib_config_tag || '—';
    document.getElementById('stat-cbflow').textContent     = info.cbflow_release || '—';
  }}

  function updateMilestoneBlock(runs) {{
    // Active runs only — archived/deleted shouldn't drive the milestone view.
    const active = runs.filter(r => !r.archived && r.run_dir_exists !== false);

    // Pick the run with the nearest upcoming tapeout. That run's project
    // is the title; its phase is the displayed phase.
    const dated = active
      .map(r => ({{r, t: r.tapeout_date ? Date.parse(r.tapeout_date) : NaN}}))
      .filter(x => !Number.isNaN(x.t));

    const elProject = document.getElementById('ms-project');
    const elPhase   = document.getElementById('ms-phase');
    const elTape    = document.getElementById('ms-tapeout-date');
    const elWeeks   = document.getElementById('ms-weeks-line');

    if (!dated.length) {{
      // No tapeouts → still show first project + its phase if available.
      const first = active.find(r => r.project) || {{}};
      elProject.textContent = first.project || '—';
      elPhase.textContent   = first.phase   || '—';
      elTape.textContent    = '—';
      elWeeks.textContent   = '—';
      elWeeks.className     = 'ms-weeks-line';
      return;
    }}

    const now      = Date.now();
    const upcoming = dated.filter(x => x.t >= now).sort((a, b) => a.t - b.t);
    const pick     = upcoming.length ? upcoming[0]
                                     : dated.sort((a, b) => b.t - a.t)[0];
    const days     = Math.floor((pick.t - now) / 86400000);
    const weeks    = days >= 0 ? Math.ceil(days / 7) : Math.floor(days / 7);

    elProject.textContent = pick.r.project || '—';
    elPhase.textContent   = pick.r.phase   || '—';

    elTape.textContent = pick.r.tapeout_date;

    let label, cls;
    if (days < 0)         {{ label = `${{-weeks}} week(s) overdue`; cls = 'ovd'; }}
    else if (weeks <= 4)  {{ label = `${{weeks}} week(s) remaining`; cls = 'soon'; }}
    else if (weeks <= 12) {{ label = `${{weeks}} week(s) remaining`; cls = 'mid'; }}
    else                  {{ label = `${{weeks}} week(s) remaining`; cls = 'far'; }}
    elWeeks.textContent = label;
    elWeeks.className   = `ms-weeks-line ${{cls}}`;
  }}

  function fmtDuration(sec) {{
    if (sec == null || sec === '' || Number.isNaN(sec)) return '—';
    sec = Math.max(0, Math.round(sec));
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    const s = sec % 60;
    if (h > 0) return `${{h}}h ${{String(m).padStart(2,'0')}}m ${{String(s).padStart(2,'0')}}s`;
    if (m > 0) return `${{m}}m ${{String(s).padStart(2,'0')}}s`;
    return `${{s}}s`;
  }}

  function runtimeCellHtml(r) {{
    // Live elapsed for RUNNING jobs (now - start_time); stored runtime_sec
    // for completed; em-dash otherwise.
    if (r.current_status === 'RUNNING' && r.current_start) {{
      const t0 = Date.parse(r.current_start);
      if (!Number.isNaN(t0)) {{
        const elapsed = (Date.now() - t0) / 1000;
        return `<span class="rt running">${{fmtDuration(elapsed)}}</span>`;
      }}
    }}
    if (r.current_runtime != null && r.current_runtime !== '') {{
      return `<span class="rt">${{fmtDuration(Number(r.current_runtime))}}</span>`;
    }}
    return `<span class="rt muted">—</span>`;
  }}

  // Tick once per second to update live RUNNING runtimes without a full refetch.
  function tickRunningRuntimes() {{
    document.querySelectorAll('#runs-tbody tr[data-status="RUNNING"]').forEach(tr => {{
      const cell = tr.querySelector('td.rt-cell');
      if (!cell) return;
      const start = tr.dataset.start;
      if (!start) return;
      const t0 = Date.parse(start);
      if (Number.isNaN(t0)) return;
      const elapsed = (Date.now() - t0) / 1000;
      cell.innerHTML = `<span class="rt running">${{fmtDuration(elapsed)}}</span>`;
    }});
  }}

  function fmtRelative(iso) {{
    if (!iso) return '';
    const t = Date.parse(iso);
    if (Number.isNaN(t)) return iso;
    const sec = Math.round((Date.now() - t) / 1000);
    if (sec < 60)   return sec + 's ago';
    if (sec < 3600) return Math.round(sec / 60) + 'm ago';
    if (sec < 86400) return Math.round(sec / 3600) + 'h ago';
    return Math.round(sec / 86400) + 'd ago';
  }}

  function runNameOf(r) {{
    // Display name = basename of run_dir. Keep run_id as a small sub-label.
    const dir = r.run_dir || '';
    const i = dir.lastIndexOf('/');
    return (i >= 0 ? dir.slice(i + 1) : dir) || r.run_id;
  }}

  function renderRow(r) {{
    // run_dir_exists is stamped by /api/runs on each request — captures
    // user-side `rm -rf` faster than the 30s daemon sweeper.
    const missing = (r.run_dir_exists === false);
    const archived = r.archived || missing;
    const classes = [];
    if (archived) classes.push('archived');
    if (missing) classes.push('deleted');
    const name = runNameOf(r);
    const deletedPill = missing
      ? '<span class="deleted-pill" title="Run directory was deleted from disk">DELETED</span>'
      : '';
    const linkHref = missing ? '#' : `/run/${{r.run_id}}/`;
    return `<tr class="${{classes.join(' ')}}" data-rid="${{r.run_id}}" data-flow="${{r.flow_type || '?'}}" data-project="${{r.project || ''}}" data-design="${{r.design || ''}}" data-status="${{r.current_status || ''}}" data-start="${{r.current_start || ''}}" data-runtime="${{r.current_runtime != null ? r.current_runtime : ''}}" data-search="${{[name,r.flow_type,r.run_dir,r.current_node,r.current_status,r.project,r.design].filter(Boolean).join(' ').toLowerCase()}}">
      <td>
        <a class="runlink" href="${{linkHref}}">${{name}}</a>${{deletedPill}}
      </td>
      <td>${{flowBadge(r.flow_type || '?')}}</td>
      <td class="status-cell">${{statusChip(r.current_node, r.current_status)}}</td>
      <td class="rt-cell">${{runtimeCellHtml(r)}}</td>
      <td class="dir">${{r.run_dir || ''}}</td>
      <td><button class="danger" onclick="deregisterRun('${{r.run_id}}')">Deregister</button></td>
    </tr>`;
  }}

  function _refreshSelect(selId, allLabel, keyOf, runs) {{
    // Populate a <select> with one option per observed value of keyOf(run).
    // "All <thing>s (N)" → N is the count of DISTINCT values (i.e. how many
    // projects / blocks / flows exist), not the row count.
    // Per-option "<value> (n)" → n is the row count for that value.
    // Preserve the user's selection if the value still exists.
    const sel = document.getElementById(selId);
    if (!sel) return;
    const current = sel.value;
    const values = Array.from(new Set(runs.map(r => keyOf(r) || '?')))
      .sort((a, b) => (a === '?' ? 1 : (b === '?' ? -1 : a.localeCompare(b))));
    sel.innerHTML = `<option value="">${{allLabel}} (${{values.length}})</option>`
      + values.map(v => {{
          const n = runs.filter(r => (keyOf(r) || '?') === v).length;
          return `<option value="${{v}}">${{v}} (${{n}})</option>`;
        }}).join('');
    if (current && values.includes(current)) sel.value = current;
  }}

  function refreshAllFilterOptions(runs) {{
    _refreshSelect('project-filter', 'All projects', r => r.project,   runs);
    _refreshSelect('design-filter',  'All blocks',   r => r.design,    runs);
    _refreshSelect('flow-filter',    'All flows',    r => r.flow_type, runs);
  }}

  function toast(msg, isError) {{
    const el = document.getElementById('toast');
    el.textContent = msg;
    el.classList.toggle('error', !!isError);
    el.classList.add('show');
    setTimeout(() => el.classList.remove('show'), 2400);
  }}

  async function loadRuns() {{
    try {{
      const runs = await fetch('/api/runs').then(r => r.json());
      const tbody = document.getElementById('runs-tbody');
      if (!runs.length) {{
        tbody.innerHTML = '<tr><td colspan="6" class="empty">No runs registered. Add one above to get started.</td></tr>';
      }} else {{
        tbody.innerHTML = runs.map(renderRow).join('');
      }}
      refreshAllFilterOptions(runs);
      updateMilestoneBlock(runs);
      updateProjectMetaChips(runs);
      const activeRuns = runs.filter(r => !r.archived);
      document.getElementById('stat-active').textContent = activeRuns.length;

      applyFilter();
    }} catch (e) {{
      toast('Failed to load runs: ' + e.message, true);
    }}
  }}

  async function deregisterRun(rid) {{
    if (!confirm('Deregister run ' + rid + '?')) return;
    try {{
      const r = await fetch('/api/deregister', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify({{ run_id: rid }}),
      }}).then(r => r.json());
      if (r.ok) {{ toast('Deregistered ' + rid); loadRuns(); }}
      else      {{ toast(r.error || 'deregister failed', true); }}
    }} catch (e) {{
      toast('Network error: ' + e.message, true);
    }}
  }}

  async function registerDir(run_dir) {{
    try {{
      const r = await fetch('/api/register', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify({{ run_dir: run_dir }}),
      }}).then(r => r.json());
      if (r.ok) {{
        document.getElementById('reg-input').value = '';
        toast('Registered as ' + r.run_id);
        loadRuns();
        loadDiscovered();          // refresh picker so the row flips to "registered"
      }} else {{
        toast(r.error || 'register failed', true);
      }}
    }} catch (e) {{
      toast('Network error: ' + e.message, true);
    }}
  }}

  document.getElementById('register-form').addEventListener('submit', async (ev) => {{
    ev.preventDefault();
    const run_dir = document.getElementById('reg-input').value.trim();
    if (!run_dir) return;
    await registerDir(run_dir);
  }});

  // ── Picker: discover existing runs from project workareas ───────────────

  let discovered = [];   // cached fetch result

  async function loadDiscovered() {{
    try {{
      const data = await fetch('/api/discover-runs').then(r => r.json());
      discovered = data.runs || [];
      refreshPickerFilterOptions();
      renderPicker();
    }} catch (e) {{
      document.getElementById('picker-body').innerHTML =
        '<div class="picker-empty">Failed to load: ' + e.message + '</div>';
    }}
  }}

  function refreshPickerFilterOptions() {{
    // Filter dropdowns reflect ONLY the unregistered pool — once a run is
    // registered it disappears from the picker, so its project/block/flow
    // shouldn't keep occupying a slot in the dropdowns either.
    const pool = discovered.filter(r => !r.registered);
    _refreshSelect('picker-project-filter', 'All projects', r => r.project,   pool);
    _refreshSelect('picker-design-filter',  'All blocks',   r => r.design,    pool);
    _refreshSelect('picker-flow-filter',    'All flows',    r => r.flow_type, pool);
  }}

  function renderPicker() {{
    const body = document.getElementById('picker-body');
    const count = document.getElementById('picker-count');
    const q       = document.getElementById('reg-input').value.toLowerCase().trim();
    const fProj   = document.getElementById('picker-project-filter').value;
    const fDes    = document.getElementById('picker-design-filter').value;
    const fFlow   = document.getElementById('picker-flow-filter').value;

    const filtered = discovered.filter(r => {{
      if (r.registered) return false;     // already registered — hide from picker
      if (fProj && (r.project   || '?') !== fProj) return false;
      if (fDes  && (r.design    || '?') !== fDes ) return false;
      if (fFlow && (r.flow_type || '?') !== fFlow) return false;
      if (!q) return true;
      const hay = (r.project + ' ' + r.design + ' ' + r.name + ' ' +
                   r.run_dir + ' ' + (r.flow_type || '')).toLowerCase();
      return hay.includes(q);
    }});

    const pool = discovered.filter(r => !r.registered);
    const registeredCount = discovered.length - pool.length;

    if (!filtered.length) {{
      body.innerHTML = pool.length
        ? '<div class="picker-empty">No unregistered runs match the current filters.</div>'
        : '<div class="picker-empty">All discovered runs are already registered.</div>';
      count.textContent = `${{pool.length}} unregistered · ${{registeredCount}} already registered (hidden)`;
      return;
    }}

    // Group by project / design
    const groups = {{}};
    filtered.forEach(r => {{
      const key = r.project + ' / ' + r.design;
      (groups[key] = groups[key] || []).push(r);
    }});

    const totalReg = registeredCount;
    count.textContent = `${{filtered.length}} of ${{pool.length}} unregistered runs match · ${{totalReg}} already registered (hidden)`;

    body.innerHTML = Object.keys(groups).sort().map(g => {{
      const rows = groups[g].map(r => {{
        return `<div class="picker-row"
          onclick="useDirInForm('${{escAttr(r.run_dir)}}')" data-dir="${{escAttr(r.run_dir)}}">
          <div>
            <div class="pname">${{escHtml(r.name)}}</div>
            <div class="pdir" title="${{escAttr(r.run_dir)}}">${{escHtml(r.run_dir)}}</div>
          </div>
          <div>${{flowBadge(r.flow_type || '?')}}</div>
          <div><button class="primary" data-dir="${{escAttr(r.run_dir)}}" style="padding:4px 12px;font-size:12px">Register</button></div>
        </div>`;
      }}).join('');
      return `<div class="picker-group">
        <div class="picker-group-hd">${{escHtml(g)}}</div>
        ${{rows}}
      </div>`;
    }}).join('');

    // Wire the Register buttons inside picker rows
    body.querySelectorAll('button[data-dir]').forEach(btn => {{
      btn.addEventListener('click', (ev) => {{
        ev.stopPropagation();
        registerDir(btn.dataset.dir);
      }});
    }});
  }}

  function escHtml(s) {{
    return String(s).replace(/[&<>"']/g,
      c => ({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));
  }}
  function escAttr(s) {{ return escHtml(s); }}

  function useDirInForm(dir) {{
    document.getElementById('reg-input').value = dir;
    document.getElementById('reg-input').focus();
  }}

  const pickerToggle = document.getElementById('picker-toggle');
  const pickerEl = document.getElementById('picker');
  pickerToggle.addEventListener('click', () => {{
    const open = !pickerEl.classList.contains('open');
    pickerEl.classList.toggle('open', open);
    pickerToggle.classList.toggle('open', open);
    pickerToggle.setAttribute('aria-expanded', open);
    pickerEl.setAttribute('aria-hidden', !open);
    pickerToggle.textContent = open ? 'Hide' : 'Browse';
    if (open && !discovered.length) loadDiscovered();
  }});

  // Re-render the picker whenever a filter changes
  ['picker-project-filter', 'picker-design-filter', 'picker-flow-filter']
    .forEach(id => document.getElementById(id)
      .addEventListener('change', () => {{
        if (pickerEl.classList.contains('open')) renderPicker();
      }}));

  // Live-filter picker when typing in the registration input
  document.getElementById('reg-input').addEventListener('input', () => {{
    if (pickerEl.classList.contains('open')) renderPicker();
  }});

  function applyFilter() {{
    const q       = document.getElementById('filter').value.toLowerCase().trim();
    const project = document.getElementById('project-filter').value;
    const design  = document.getElementById('design-filter').value;
    const flow    = document.getElementById('flow-filter').value;
    document.querySelectorAll('#runs-tbody tr').forEach(tr => {{
      const search   = tr.dataset.search || '';
      const rowProj  = tr.dataset.project || '';
      const rowDes   = tr.dataset.design  || '';
      const rowFlow  = tr.dataset.flow    || '';
      const matchesText    = !q       || search.includes(q);
      const matchesProject = !project || rowProj === project;
      const matchesDesign  = !design  || rowDes  === design;
      const matchesFlow    = !flow    || rowFlow === flow;
      tr.style.display = (matchesText && matchesProject && matchesDesign && matchesFlow) ? '' : 'none';
    }});
  }}
  document.getElementById('filter').addEventListener('input', applyFilter);
  document.getElementById('project-filter').addEventListener('change', applyFilter);
  document.getElementById('design-filter').addEventListener('change', applyFilter);
  document.getElementById('flow-filter').addEventListener('change', applyFilter);
  document.getElementById('refresh').addEventListener('click', loadRuns);

  loadRuns();
  setInterval(loadRuns, 5000);            // poll every 5s for live updates
  setInterval(tickRunningRuntimes, 1000); // refresh RUNNING runtimes every 1s
</script>
</body></html>
"""


def _render_run_rows(runs):
    """Server-rendered initial rows (the script will re-render on load).
    Kept for no-JS fallback and faster first paint. Flat table; the flow
    filter in the toolbar narrows on demand."""
    import os as _os
    if not runs:
        return ''

    out = []
    for r in runs:
        flow = r.get('flow_type') or '?'
        color = _FLOW_COLORS.get(flow, '#475569')
        cls = 'archived' if r.get('archived') else ''
        rid = r['run_id']
        run_dir = r.get('run_dir', '')
        name = _os.path.basename(run_dir.rstrip('/')) or rid
        status = r.get('current_status') or 'NONE'
        node = r.get('current_node') or ''
        search = ' '.join(filter(None, [name, flow, run_dir, node, status])).lower().replace('"', '')
        bg, fg = _STATUS_COLORS.get(status, _STATUS_COLORS['NONE'])
        node_html = (f'<span class="status-node">{node}</span>'
                     if node else '<span class="status-node muted">—</span>')
        chip_html = (
            f'<span class="status-chip" '
            f'style="background:{bg};color:{fg}" '
            f'title="{node} ({status})">{status}</span>'
        )
        # SSR runtime: render the stored value if any; JS overrides to live
        # elapsed for RUNNING jobs each second.
        _rt = r.get('current_runtime')
        if status == 'RUNNING':
            _start = r.get('current_start') or ''
            _elapsed = None
            if _start:
                from datetime import datetime as _dt
                try:
                    _t0 = _dt.fromisoformat(_start)
                    _elapsed = (_dt.now() - _t0).total_seconds()
                except ValueError:
                    _elapsed = None
            if _elapsed is not None and _elapsed >= 0:
                runtime_html = f'<span class="rt running">{_fmt_duration(_elapsed)}</span>'
            else:
                runtime_html = '<span class="rt muted">—</span>'
        elif _rt not in (None, ''):
            runtime_html = f'<span class="rt">{_fmt_duration(_rt)}</span>'
        else:
            runtime_html = '<span class="rt muted">—</span>'
        proj = r.get('project') or ''
        design = r.get('design') or ''
        out.append(
            f'<tr class="{cls}" data-rid="{rid}" data-flow="{flow}" '
            f'data-project="{proj}" data-design="{design}" '
            f'data-status="{status}" '
            f'data-start="{r.get("current_start") or ""}" '
            f'data-runtime="{r.get("current_runtime") if r.get("current_runtime") is not None else ""}" '
            f'data-search="{search}">'
            f'<td><a class="runlink" href="/run/{rid}/">{name}</a></td>'
            f'<td><span class="flow-badge" style="background:{color}">{flow}</span></td>'
            f'<td class="status-cell">{chip_html} {node_html}</td>'
            f'<td class="rt-cell">{runtime_html}</td>'
            f'<td class="dir">{run_dir}</td>'
            f'<td><button class="danger" '
            f'onclick="deregisterRun(\'{rid}\')">Deregister</button></td>'
            f'</tr>'
        )
    return '\n'.join(out)
