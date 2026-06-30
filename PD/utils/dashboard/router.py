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
            rec = registry.register(run_dir_abs)
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
            html = _render_index(runs, discipline=state_paths.get_discipline())
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
                    st = {'node': '', 'status': 'NONE'}
                r['current_node'] = st['node']
                r['current_status'] = st['status']
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


def _flow_type_for(run_dir):
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if not os.path.exists(env_file):
        return ''
    try:
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line.startswith('export ') and '=' in line:
                    k, v = line[7:].split('=', 1)
                    if k == 'CBFLOW_FLOW_TYPE':
                        return v.strip('"').strip("'")
    except OSError:
        pass
    return ''


def _discover_runs(pd_dir):
    """Return a list of run directories under any project's workarea_path.

    Each entry: {project, design, name, run_dir, flow_type}.
    Caller layers `registered` on top via the registry.
    """
    out = []
    seen = set()
    for project, wa in _project_workarea_paths(pd_dir):
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
                out.append({
                    'project': project,
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
    """Return {'node': ..., 'status': ...} for the run's most relevant job.

    Priority — first match wins:
      1. Any RUNNING subnode  → that's the live one
      2. Most recent FAIL     → user needs to see this
      3. Most recent DONE/BYPASSED/FORCE_VALIDATED → last activity
      4. Any PENDING / INVALIDATED → in queue
      5. All READY (never started) → 'Not started' / READY
      6. No DB / no jobs row / DB unreadable → returns NONE
    """
    db_path = _find_run_db(run_dir)
    if not db_path:
        return {'node': '', 'status': 'NONE'}
    try:
        # uri=True + mode=ro so we never accidentally write or lock the DB
        conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True, timeout=0.5)
    except sqlite3.Error:
        return {'node': '', 'status': 'NONE'}
    try:
        cur = conn.cursor()
        # Latest row per job_name, subnodes only — the table is small enough
        # (low thousands of rows in the worst case) that this is sub-ms.
        rows = cur.execute(
            "SELECT stage, COALESCE(subnode,''), status, "
            "COALESCE(end_time, start_time, '') AS ts "
            "FROM jobs "
            "WHERE id IN (SELECT MAX(id) FROM jobs GROUP BY job_name) "
            "AND job_type = 'subnode'"
        ).fetchall()
    except sqlite3.Error:
        return {'node': '', 'status': 'NONE'}
    finally:
        conn.close()

    if not rows:
        return {'node': '', 'status': 'NONE'}

    by_status = {}
    for stage, subnode, status, ts in rows:
        by_status.setdefault(status, []).append((stage, subnode, ts))

    for st in _STATUS_PRIORITY:
        if st in by_status:
            # Within a status bucket pick the most-recent row by timestamp.
            stage, subnode, _ = max(by_status[st], key=lambda r: r[2] or '')
            node = f'{stage}/{subnode}' if subnode else stage
            return {'node': node, 'status': st}

    # Status outside our known set — surface it as-is so we see it on the UI.
    stage, subnode, status, _ts = rows[0]
    node = f'{stage}/{subnode}' if subnode else stage
    return {'node': node, 'status': status}


def _render_index(runs, discipline='PD'):
    """Index page for the per-user dashboard daemon.

    Stdlib-only (no JS framework). Vanilla CSS + a small client script that
    talks to /api/runs, /api/register, /api/deregister.
    """
    disc = (discipline or 'PD').upper()
    disc_label = disc
    disc_pill_bg = '#0d9488' if disc == 'DFT' else '#1565c0'
    disc_pill_border = '#0f766e' if disc == 'DFT' else '#0d47a1'
    disc_banner_grad = ('linear-gradient(135deg, #0d9488 0%, #0ea5e9 55%, #6366f1 100%)'
                        if disc == 'DFT'
                        else 'linear-gradient(135deg, #4f46e5 0%, #7c3aed 50%, #0ea5e9 100%)')
    title_prefix = f'CBflow {disc} Dashboard'
    active = [r for r in runs if not r.get('archived')]
    archived = [r for r in runs if r.get('archived')]
    project_set = {r.get('project') for r in active if r.get('project')}
    design_set = {r.get('design') for r in active if r.get('design')}
    project_counts = {}
    for r in active:
        proj = r.get('project') or '(unknown)'
        project_counts[proj] = project_counts.get(proj, 0) + 1
    if project_counts:
        proj_chips_html = '\n'.join(
            f'<span class="proj-chip">{p}<span class="count">{c}</span></span>'
            for p, c in sorted(project_counts.items())
        )
    else:
        proj_chips_html = '<span class="proj-chip empty">no runs registered</span>'

    # Stamp current_node / current_status server-side too so the initial
    # paint shows real status (otherwise every row would briefly read "NONE"
    # until the first JS poll fires at +5s).
    for _r in runs:
        _run_dir = _r.get('run_dir') or ''
        if _run_dir and os.path.isdir(_run_dir):
            _st = _current_status_for_run(_run_dir)
            _r['current_node'] = _st['node']
            _r['current_status'] = _st['status']
            _r['run_dir_exists'] = True
        else:
            _r.setdefault('current_node', '')
            _r.setdefault('current_status', 'NONE')
            _r['run_dir_exists'] = False

    rows_html = _render_run_rows(runs) or (
        '<tr><td colspan="7" class="empty">'
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
  header.banner .projects {{ display: flex; gap: 8px; margin-top: 14px; flex-wrap: wrap;
                              align-items: center; font-size: 12px; opacity: .92; }}
  header.banner .projects-label {{ opacity: .75; margin-right: 4px; }}
  header.banner .proj-chip {{ background: rgba(255,255,255,.15);
                               border: 1px solid rgba(255,255,255,.22);
                               padding: 3px 12px; border-radius: 999px;
                               font-weight: 500; font-size: 12px;
                               backdrop-filter: blur(6px); }}
  header.banner .proj-chip .count {{ opacity: .7; margin-left: 4px;
                                      font-variant-numeric: tabular-nums; }}
  header.banner .proj-chip.empty {{ opacity: .55; font-style: italic; }}

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
  .runid {{ display: block; margin-top: 2px; font-family: 'SF Mono', Menlo, Consolas, monospace;
            font-size: 11px; color: var(--muted); font-weight: 400; letter-spacing: 0; }}

  .flow-badge {{ display: inline-block; padding: 2px 10px; border-radius: 999px;
                  color: white; font-size: 11px; font-weight: 600;
                  letter-spacing: .04em; }}

  /* Per-flow section header row in the runs table */
  tr.flow-section td {{ background: #f1f3f9; padding: 8px 16px !important;
                        font-size: 11px; letter-spacing: .04em;
                        border-top: 2px solid #d1d5db; }}
  tr.flow-section .flow-section-count {{ margin-left: 10px; color: var(--muted);
                                          font-size: 11px; font-weight: 500;
                                          text-transform: none; letter-spacing: 0; }}

  /* Current Status column — colored chip + current node id */
  td.status-cell {{ white-space: nowrap; }}
  .status-chip {{ display: inline-block; padding: 2px 9px; border-radius: 999px;
                   font-size: 10.5px; font-weight: 700; letter-spacing: .05em;
                   text-transform: uppercase; font-variant-numeric: tabular-nums; }}
  .status-node {{ display: inline-block; margin-left: 8px; font-size: 12px;
                   color: var(--text); font-family: 'SF Mono', Menlo, Consolas, monospace; }}
  .status-node.muted {{ color: var(--muted); font-family: inherit; }}

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
  <div class="logo-row">
    <div class="logo">CBflow<span class="lite">Dashboard</span></div>
    <span class="discipline-pill" title="This dashboard serves the {disc} discipline">{disc_label}</span>
    <span class="engine-pill" title="Python-native DAG execution engine">RACE engine</span>
  </div>
  <div class="byline">Developed by SmartSoc</div>
  <div class="stats">
    <div class="stat">Active runs: <b id="stat-active">{len(active)}</b></div>
    <div class="stat">Archived: <b id="stat-archived">{len(archived)}</b></div>
    <div class="stat">Projects: <b id="stat-projects">{len(project_set)}</b></div>
    <div class="stat">Designs: <b id="stat-designs">{len(design_set)}</b></div>
    <div class="stat">PID: <b id="stat-pid">…</b></div>
    <div class="stat">Port: <b id="stat-port">…</b></div>
  </div>
  <div class="projects">
    <span class="projects-label">Projects:</span>
    <span id="proj-chips">{proj_chips_html}</span>
  </div>
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
      <div class="picker-count" id="picker-count">…</div>
      <div id="picker-body"></div>
    </div>
  </div>

  <div class="panel">
    <div class="panel-hd">
      <h2>Registered runs</h2>
      <div class="toolbar">
        <input type="search" id="filter" placeholder="Filter by flow, path, ID…">
        <button class="primary" id="refresh" title="Reload from registry">Refresh</button>
      </div>
    </div>
    <table class="runs">
      <thead>
        <tr><th>Run</th><th>Flow</th><th>Current Status</th><th>Run directory</th>
            <th>Registered</th><th>Last seen</th><th></th></tr>
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
    return `<tr class="${{classes.join(' ')}}" data-rid="${{r.run_id}}" data-flow="${{r.flow_type || '?'}}" data-search="${{[r.run_id,name,r.flow_type,r.run_dir,r.current_node,r.current_status].filter(Boolean).join(' ').toLowerCase()}}">
      <td>
        <a class="runlink" href="${{linkHref}}">${{name}}</a>${{deletedPill}}
        <span class="runid" title="run_id">${{r.run_id}}</span>
      </td>
      <td>${{flowBadge(r.flow_type || '?')}}</td>
      <td class="status-cell">${{statusChip(r.current_node, r.current_status)}}</td>
      <td class="dir">${{r.run_dir || ''}}</td>
      <td class="ts" title="${{r.registered_at || ''}}">${{fmtRelative(r.registered_at)}}</td>
      <td class="ts" title="${{r.last_seen_at || ''}}">${{fmtRelative(r.last_seen_at)}}</td>
      <td><button class="danger" onclick="deregisterRun('${{r.run_id}}')">Deregister</button></td>
    </tr>`;
  }}

  function renderGroupedRows(runs) {{
    // Bucket runs by flow_type. '?' goes last; everything else alpha.
    const groups = new Map();
    for (const r of runs) {{
      const f = r.flow_type || '?';
      if (!groups.has(f)) groups.set(f, []);
      groups.get(f).push(r);
    }}
    const flows = Array.from(groups.keys())
      .sort((a, b) => (a === '?' ? 1 : (b === '?' ? -1 : a.localeCompare(b))));
    const out = [];
    for (const flow of flows) {{
      const rows = groups.get(flow);
      const color = FLOW_COLORS[flow] || '#475569';
      const noun = rows.length === 1 ? 'run' : 'runs';
      out.push(`<tr class="flow-section" data-flow="${{flow}}">`
             + `<td colspan="7">`
             + `<span class="flow-badge" style="background:${{color}}">${{flow}}</span>`
             + `<span class="flow-section-count">${{rows.length}} ${{noun}}</span>`
             + `</td></tr>`);
      out.push(rows.map(renderRow).join(''));
    }}
    return out.join('');
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
      const [runs, status] = await Promise.all([
        fetch('/api/runs').then(r => r.json()),
        fetch('/api/daemon-status').then(r => r.json()).catch(() => ({{}})),
      ]);
      const tbody = document.getElementById('runs-tbody');
      if (!runs.length) {{
        tbody.innerHTML = '<tr><td colspan="7" class="empty">No runs registered. Add one above to get started.</td></tr>';
      }} else {{
        tbody.innerHTML = renderGroupedRows(runs);
      }}
      const activeRuns = runs.filter(r => !r.archived);
      const archivedCount = runs.length - activeRuns.length;
      const projectSet = new Set(activeRuns.map(r => r.project).filter(Boolean));
      const designSet = new Set(activeRuns.map(r => r.design).filter(Boolean));
      const projCounts = {{}};
      activeRuns.forEach(r => {{
        const p = r.project || '(unknown)';
        projCounts[p] = (projCounts[p] || 0) + 1;
      }});

      document.getElementById('stat-active').textContent = activeRuns.length;
      document.getElementById('stat-archived').textContent = archivedCount;
      document.getElementById('stat-projects').textContent = projectSet.size;
      document.getElementById('stat-designs').textContent = designSet.size;
      if (status.pid) document.getElementById('stat-pid').textContent = status.pid;
      if (status.port) document.getElementById('stat-port').textContent = status.port;

      const chipNames = Object.keys(projCounts).sort();
      document.getElementById('proj-chips').innerHTML = chipNames.length
        ? chipNames.map(p => `<span class="proj-chip">${{p}}<span class="count">${{projCounts[p]}}</span></span>`).join('')
        : '<span class="proj-chip empty">no runs registered</span>';

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
      renderPicker();
    }} catch (e) {{
      document.getElementById('picker-body').innerHTML =
        '<div class="picker-empty">Failed to load: ' + e.message + '</div>';
    }}
  }}

  function renderPicker() {{
    const body = document.getElementById('picker-body');
    const count = document.getElementById('picker-count');
    const q = document.getElementById('reg-input').value.toLowerCase().trim();

    const filtered = discovered.filter(r => {{
      if (!q) return true;
      const hay = (r.project + ' ' + r.design + ' ' + r.name + ' ' +
                   r.run_dir + ' ' + (r.flow_type || '')).toLowerCase();
      return hay.includes(q);
    }});

    if (!filtered.length) {{
      body.innerHTML = '<div class="picker-empty">No discovered runs match.</div>';
      count.textContent = discovered.length + ' discovered, 0 match filter';
      return;
    }}

    // Group by project / design
    const groups = {{}};
    filtered.forEach(r => {{
      const key = r.project + ' / ' + r.design;
      (groups[key] = groups[key] || []).push(r);
    }});

    const totalReg = filtered.filter(r => r.registered).length;
    count.textContent = `${{filtered.length}} of ${{discovered.length}} runs · ${{totalReg}} already registered`;

    body.innerHTML = Object.keys(groups).sort().map(g => {{
      const rows = groups[g].map(r => {{
        const regCls = r.registered ? 'registered' : '';
        const regPill = r.registered
          ? '<span class="reg-pill">REGISTERED</span>'
          : '<button class="primary" data-dir="' + escAttr(r.run_dir) + '" style="padding:4px 12px;font-size:12px">Register</button>';
        const onclick = r.registered ? '' :
          'onclick="useDirInForm(this.dataset.dir)" data-dir="' + escAttr(r.run_dir) + '"';
        return `<div class="picker-row ${{regCls}}" ${{onclick}}>
          <div>
            <div class="pname">${{escHtml(r.name)}}</div>
            <div class="pdir" title="${{escAttr(r.run_dir)}}">${{escHtml(r.run_dir)}}</div>
          </div>
          <div>${{flowBadge(r.flow_type || '?')}}</div>
          <div>${{regPill}}</div>
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

  // Live-filter picker when typing in the registration input
  document.getElementById('reg-input').addEventListener('input', () => {{
    if (pickerEl.classList.contains('open')) renderPicker();
  }});

  function applyFilter() {{
    const q = document.getElementById('filter').value.toLowerCase().trim();
    // Pass 1: show/hide individual run rows; section headers stay visible
    // for now so we can compute their visible-children count in pass 2.
    document.querySelectorAll('#runs-tbody tr').forEach(tr => {{
      if (tr.classList.contains('flow-section')) return;
      const search = tr.dataset.search || '';
      tr.style.display = (!q || search.includes(q)) ? '' : 'none';
    }});
    // Pass 2: hide each flow-section header whose group has zero visible rows.
    document.querySelectorAll('#runs-tbody tr.flow-section').forEach(hdr => {{
      const flow = hdr.dataset.flow || '';
      const sibs = document.querySelectorAll(
        `#runs-tbody tr[data-flow="${{flow}}"]:not(.flow-section)`);
      let anyVisible = false;
      sibs.forEach(s => {{ if (s.style.display !== 'none') anyVisible = true; }});
      hdr.style.display = anyVisible ? '' : 'none';
    }});
  }}
  document.getElementById('filter').addEventListener('input', applyFilter);
  document.getElementById('refresh').addEventListener('click', loadRuns);

  loadRuns();
  setInterval(loadRuns, 5000);  // poll every 5s for live updates
</script>
</body></html>
"""


def _render_run_rows(runs):
    """Server-rendered initial rows (the script will re-render on load).
    Kept for no-JS fallback and faster first paint.

    Runs are grouped by flow_type into per-flow sections; each section is
    introduced by a header row. Order: alphabetical by flow name, '?' last.
    """
    import os as _os
    if not runs:
        return ''

    groups = {}
    for r in runs:
        flow = r.get('flow_type') or '?'
        groups.setdefault(flow, []).append(r)
    ordered_flows = sorted(groups.keys(), key=lambda f: ('~~~' if f == '?' else f))

    out = []
    for flow in ordered_flows:
        flow_rows = groups[flow]
        color = _FLOW_COLORS.get(flow, '#475569')
        out.append(
            f'<tr class="flow-section" data-flow="{flow}">'
            f'<td colspan="7">'
            f'<span class="flow-badge" style="background:{color}">{flow}</span>'
            f'<span class="flow-section-count">{len(flow_rows)} run'
            f'{"s" if len(flow_rows) != 1 else ""}</span>'
            f'</td></tr>'
        )
        for r in flow_rows:
            cls = 'archived' if r.get('archived') else ''
            rid = r['run_id']
            run_dir = r.get('run_dir', '')
            name = _os.path.basename(run_dir.rstrip('/')) or rid
            status = r.get('current_status') or 'NONE'
            node = r.get('current_node') or ''
            search = ' '.join(filter(None, [rid, name, flow, run_dir, node, status])).lower().replace('"', '')
            bg, fg = _STATUS_COLORS.get(status, _STATUS_COLORS['NONE'])
            node_html = (f'<span class="status-node">{node}</span>'
                         if node else '<span class="status-node muted">—</span>')
            chip_html = (
                f'<span class="status-chip" '
                f'style="background:{bg};color:{fg}" '
                f'title="{node} ({status})">{status}</span>'
            )
            out.append(
                f'<tr class="{cls}" data-rid="{rid}" data-flow="{flow}" data-search="{search}">'
                f'<td><a class="runlink" href="/run/{rid}/">{name}</a>'
                f'<span class="runid" title="run_id">{rid}</span></td>'
                f'<td><span class="flow-badge" style="background:{color}">{flow}</span></td>'
                f'<td class="status-cell">{chip_html} {node_html}</td>'
                f'<td class="dir">{run_dir}</td>'
                f'<td class="ts">{r.get("registered_at", "")}</td>'
                f'<td class="ts">{r.get("last_seen_at", "")}</td>'
                f'<td><button class="danger" '
                f'onclick="deregisterRun(\'{rid}\')">Deregister</button></td>'
                f'</tr>'
            )
    return '\n'.join(out)
