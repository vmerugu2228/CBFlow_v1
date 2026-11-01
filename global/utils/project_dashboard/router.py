"""HTTP router for CBflow-ProjectDashboard.

Serves a single-page grid + drill-in detail. No polling — the client
reloads only when the tab regains focus (nothing changes between publish
events).

Routes:
  GET /                        Landing grid (SSR)
  GET /api/published           JSON of all published rows
  GET /api/project             Project header info
  GET /published/<id>          Detail page for one published cell (SSR)
  GET /favicon.ico             204 no-content
"""

import http.server
import html
import json
import os
import sys
from datetime import date, datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import state_paths
import tracker_db


_MILESTONES = ('FP_EXIT', 'PLACE_EXIT', 'CTS_EXIT', 'PRO_EXIT', 'BTO', 'MTO')


def make_handler(project):
    """Build a request-handler class bound to a specific project."""
    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = 'CBflow-ProjectDashboard/1.0'

        def log_message(self, fmt, *args):
            # Route request logs to daemon.log via stdout (Popen redirect).
            print(f'[{self.log_date_time_string()}] '
                  f'{self.address_string()} - {fmt % args}', flush=True)

        def do_GET(self):
            try:
                self._route()
            except Exception as e:
                self._send(500, 'text/plain', f'internal error: {e}')

        def _route(self):
            from urllib.parse import unquote, parse_qs
            path = self.path.split('?', 1)[0]
            query = parse_qs(self.path.split('?', 1)[1]) if '?' in self.path else {}
            if path == '/' or path == '/index.html':
                return self._page_tier1(query)
            if path == '/api/published':
                return self._api_published()
            if path == '/api/project':
                return self._api_project()
            # ── Tier 2+ routes (PR1 skeleton — stubs; UI lands in PR2/PR3) ──
            # /project/<name>                       Tier 2
            # /project/<name>/<disc>                Tier 3
            # /project/<name>/<disc>/block/<b>      Tier 4
            if path.startswith('/project/'):
                segs = [s for s in path[len('/project/'):].split('/') if s]
                segs = [unquote(s) for s in segs]
                if not segs:
                    return self._send(404, 'text/plain', 'not found')
                tgt_project = segs[0]
                # Cross-project navigation: redirect to the sibling daemon
                # if the request isn't for our own project.
                if tgt_project != project:
                    url = state_paths.sibling_daemon_url(tgt_project)
                    if url:
                        # Preserve sub-path so e.g. /project/other/pd lands on
                        # /project/other/pd on the sibling.
                        suffix = '/'.join(segs[1:])
                        suffix = f'/project/{tgt_project}' + (f'/{suffix}' if suffix else '')
                        query = self.path.split('?', 1)[1] if '?' in self.path else ''
                        location = url.rstrip('/') + suffix + (f'?{query}' if query else '')
                        self.send_response(302)
                        self.send_header('Location', location)
                        self.end_headers()
                        return
                    # Sibling daemon not running — serve a local stub.
                    return self._page_tier2_offline(tgt_project)
                # Our own project — dispatch by sub-path.
                if len(segs) == 1:
                    return self._page_tier2(tgt_project)  # /project/<self>
                disc = segs[1].lower()
                if len(segs) == 2:
                    return self._page_tier3(tgt_project, disc)  # /project/<self>/<disc>
                if len(segs) == 4 and segs[2] == 'block':
                    return self._page_tier4(tgt_project, disc, segs[3])
                return self._send(404, 'text/plain', 'not found')
            if path == '/api/projects':
                return self._api_projects()
            if path.startswith('/api/project/'):
                segs = [s for s in path[len('/api/project/'):].split('/') if s]
                if len(segs) == 1:
                    return self._api_project_detail(unquote(segs[0]))
                if len(segs) == 2:
                    return self._api_discipline(unquote(segs[0]),
                                                unquote(segs[1]).lower())
                return self._send(404, 'text/plain', 'not found')
            if path == '/api/resources':
                from urllib.parse import parse_qs
                q = parse_qs(self.path.split('?', 1)[1] if '?' in self.path else '')
                tgt = (q.get('project') or [project])[0]
                return self._api_resources(tgt)
            if path.startswith('/api/floorplan/'):
                try:
                    pid = int(path[len('/api/floorplan/'):].rstrip('/'))
                except ValueError:
                    return self._send(404, 'text/plain', 'not found')
                return self._api_floorplan(pid)
            if path.startswith('/api/timing/'):
                try:
                    pid = int(path[len('/api/timing/'):].rstrip('/'))
                except ValueError:
                    return self._send(404, 'text/plain', 'not found')
                return self._api_timing(pid)
            if path.startswith('/published/'):
                try:
                    pid = int(path[len('/published/'):].rstrip('/'))
                except ValueError:
                    return self._send(404, 'text/plain', 'not found')
                return self._page_published(pid)
            if path.startswith('/block/'):
                name = path[len('/block/'):].rstrip('/')
                return self._page_block(unquote(name))
            if path.startswith('/image/'):
                # /image/<published_run_id>/<index_into_image_files>
                rest = path[len('/image/'):].rstrip('/').split('/')
                if len(rest) != 2:
                    return self._send(404, 'text/plain', 'not found')
                try:
                    pid, idx = int(rest[0]), int(rest[1])
                except ValueError:
                    return self._send(404, 'text/plain', 'not found')
                return self._serve_image(pid, idx)
            if path == '/favicon.ico':
                return self._send(204, 'text/plain', '')
            self._send(404, 'text/plain', 'not found')

        # ── SSR pages ────────────────────────────────────────────────────────

        def _page_index(self):
            db = state_paths.tracker_db(project)
            info = tracker_db.get_project_info(db, project)
            blocks = tracker_db.list_blocks(db, project)
            pubs = tracker_db.list_published(db, project)
            html_out = _render_index(project, info, blocks, pubs)
            self._send(200, 'text/html; charset=utf-8', html_out)

        def _page_published(self, pid):
            db = state_paths.tracker_db(project)
            info = tracker_db.get_project_info(db, project)
            detail = tracker_db.get_published(db, pid)
            if not detail:
                return self._send(404, 'text/plain', f'published run {pid} not found')
            html_out = _render_detail(project, info, detail)
            self._send(200, 'text/html; charset=utf-8', html_out)

        def _page_block(self, block_name):
            db = state_paths.tracker_db(project)
            info = tracker_db.get_project_info(db, project)
            all_blocks = tracker_db.list_blocks(db, project)
            all_pubs = tracker_db.list_published(db, project)
            block_meta = next(
                (b for b in all_blocks if b['block_name'] == block_name), None)
            block_pubs = [r for r in all_pubs if r['block'] == block_name]
            if not block_meta and not block_pubs:
                return self._send(404, 'text/plain',
                                  f'block {block_name} not found')
            html_out = _render_block(project, info, block_name,
                                     block_meta or {}, block_pubs)
            self._send(200, 'text/html; charset=utf-8', html_out)

        # ── Tier 1 — all-projects grid (NEW landing page) ─────────────

        def _page_tier1(self, query):
            """Render the Tier 1 all-projects grid.

            `query` is parse_qs output. `?status=active|archived|all`
            controls which cards are shown; default 'active'.
            """
            scope = (query.get('status') or ['active'])[0].lower()
            if scope not in ('active', 'archived', 'all'):
                scope = 'active'
            html_out = _render_tier1(project, scope)
            self._send(200, 'text/html; charset=utf-8', html_out)

        # ── Tier 2 — project landing (discipline + schedule + resource) ──

        def _page_tier2(self, tgt_project):
            """Project landing (own-project). Renders discipline cards +
            schedule card + resource card, with the published-runs table
            below for drill-in context."""
            db = state_paths.tracker_db(tgt_project)
            info = tracker_db.get_project_info(db, tgt_project)
            blocks = tracker_db.list_blocks(db, tgt_project)
            pubs = tracker_db.list_published(db, tgt_project)
            html_out = _render_tier2(tgt_project, info, blocks, pubs)
            self._send(200, 'text/html; charset=utf-8', html_out)

        def _page_tier2_offline(self, tgt_project):
            """Sibling-daemon offline fallback. Served from our own daemon
            when the user clicks another project card but that project's
            smartgrid isn't running."""
            html_out = _render_tier_stub(
                tgt_project,
                f"Daemon for '{tgt_project}' is not running",
                hint=f"Start it with: cbflow smartgrid start --project {tgt_project}",
                variant='offline')
            self._send(200, 'text/html; charset=utf-8', html_out)

        def _page_tier3(self, tgt_project, disc):
            """Discipline summary. PR3 renders verdict rollup + metrics +
            per-block table. PR1 stub."""
            html_out = _render_tier_stub(
                tgt_project,
                f'Tier 3 — {disc.upper()} discipline summary (coming in PR3)',
                hint='This page will show the discipline-level status: '
                     'verdict rollup, top-6 metrics with trends, and the '
                     'per-block mini-table.')
            self._send(200, 'text/html; charset=utf-8', html_out)

        def _page_tier4(self, tgt_project, disc, block_name):
            """Block drill-in (PR3 wires it to the existing _page_block
            renderer; PR1 stub)."""
            html_out = _render_tier_stub(
                tgt_project,
                f'Tier 4 — {disc.upper()} / block {block_name} (coming in PR3)',
                hint='This page will reuse the existing block drill-in with '
                     'a discipline filter + deep-link query params.')
            self._send(200, 'text/html; charset=utf-8', html_out)

        # ── JSON APIs (for JS reload) ────────────────────────────────────────

        def _api_projects(self):
            """Tier 1 feed — all projects from master_projects.json. PR2
            adds sibling tracker.db summary rows."""
            try:
                import sys as _sys, os as _os
                _utils = _os.path.dirname(_os.path.dirname(
                    _os.path.abspath(__file__)))
                _cmds = _os.path.join(_utils, 'commands')
                # tcl_config_parser imports core.paths — both _utils (for
                # core/) and _cmds (for tcl_config_parser.py) must be on
                # sys.path.
                for _p in (_utils, _cmds):
                    if _p not in _sys.path:
                        _sys.path.insert(0, _p)
                from tcl_config_parser import _load_master_projects
                data = _load_master_projects()
            except Exception as e:
                return self._json({'error': str(e), 'projects': []})
            return self._json({'projects': list(
                (data.get('projects') or {}).values())})

        def _api_project_detail(self, tgt_project):
            """Alias of /api/project but accepts the project in the URL
            path (used by Tier 2 async fetches)."""
            if tgt_project != project:
                # Sibling daemons own their own project data. We don't
                # cross-read tracker.db here — the caller should hit the
                # sibling daemon directly.
                return self._json({'error': f'project {tgt_project!r} not '
                                            'served by this daemon'})
            return self._api_project()

        def _api_discipline(self, tgt_project, disc):
            """Tier 3 feed — PR3 fills with rollup + per-block + metrics.
            PR1 stub returns the project+discipline echo."""
            return self._json({'project': tgt_project, 'discipline': disc,
                               'status': 'skeleton — PR3'})

        def _api_resources(self, tgt_project):
            """Tier 2 Resource card feed — aggregates lsf_details from
            recent published runs' RACE DBs. Capped to last 20 runs and
            serves whatever each race.db yields; missing/unreadable
            race.dbs are skipped silently."""
            if tgt_project != project:
                return self._json({'error': f'project {tgt_project!r} not '
                                            'served by this daemon'})
            db = state_paths.tracker_db(tgt_project)
            pubs = tracker_db.list_published(db, tgt_project)
            # Latest publishes first (approx — list_published orders by
            # block/phase/milestone; we pull up to 20 unique race_db_paths).
            seen = set()
            race_dbs = []
            for row in sorted(pubs, key=lambda r: r.get('published_at') or '',
                              reverse=True):
                rd = row.get('race_db_path') or ''
                if rd and rd not in seen and os.path.isfile(rd):
                    seen.add(rd)
                    race_dbs.append(rd)
                if len(race_dbs) >= 20:
                    break
            agg = _aggregate_resources(race_dbs)
            agg['project'] = tgt_project
            agg['run_count'] = len(race_dbs)
            return self._json(agg)

        def _api_project(self):
            db = state_paths.tracker_db(project)
            self._json({
                'project': project,
                'info': tracker_db.get_project_info(db, project),
                'blocks': tracker_db.list_blocks(db, project),
                'milestones': list(_MILESTONES),
            })

        def _api_published(self):
            db = state_paths.tracker_db(project)
            self._json({'published': tracker_db.list_published(db, project)})

        def _api_floorplan(self, pid):
            db = state_paths.tracker_db(project)
            fp = tracker_db.get_floorplan(db, pid)
            if not fp:
                return self._send(404, 'text/plain', 'no floorplan captured')
            self._json(fp)

        def _api_timing(self, pid):
            db = state_paths.tracker_db(project)
            t = tracker_db.get_timing(db, pid)
            if not t:
                return self._send(404, 'text/plain', 'no timing captured')
            self._json(t)

        def _serve_image(self, pid, idx):
            """Stream image bytes for an entry in this publish's run_files.

            Path resolution: release_dir + rel_path (join and re-canonicalize).
            Refuses to serve anything outside the recorded release_dir to
            keep this endpoint from being a path-traversal foothold.
            """
            db = state_paths.tracker_db(project)
            detail = tracker_db.get_published(db, pid)
            if not detail:
                return self._send(404, 'text/plain', 'unknown publish')
            image_files = [f for f in (detail.get('files') or [])
                           if (f.get('kind') or '').startswith('IMAGE_')]
            if idx < 0 or idx >= len(image_files):
                return self._send(404, 'text/plain', 'image index out of range')
            rel = image_files[idx].get('rel_path') or ''
            base = detail.get('release_dir') or ''
            if not base or not rel:
                return self._send(404, 'text/plain', 'no path')
            # Resolve BOTH candidate and base through realpath, so a
            # symlink inside release_dir pointing to e.g. /etc/hosts
            # or another project's secrets no longer escapes the
            # containment check. Pre-fix normpath did not resolve
            # symlinks, letting a publisher drop
            # `release_dir/leak -> /home/other_project/secret.png`
            # and serve arbitrary host files via /image/<pid>/<idx>.
            # Also enforce an extension allow-list — the pre-fix mime
            # fallback 'application/octet-stream' + 1-hour Cache-Control
            # compounded the symlink bypass into cacheable arbitrary-
            # file read with intermediate-proxy caching.
            candidate = os.path.join(base, rel)
            try:
                real_candidate = os.path.realpath(candidate)
                real_base = os.path.realpath(base)
            except OSError:
                return self._send(404, 'text/plain', 'path resolve failed')
            if not (real_candidate == real_base or
                    real_candidate.startswith(real_base + os.sep)):
                return self._send(403, 'text/plain', 'refused (outside release)')
            path = real_candidate
            if not os.path.isfile(path):
                return self._send(404, 'text/plain', 'file gone')
            ext = os.path.splitext(path)[1].lower()
            _ALLOWED_MIME = {'.png':'image/png', '.jpg':'image/jpeg', '.jpeg':'image/jpeg',
                             '.svg':'image/svg+xml', '.gif':'image/gif',
                             '.webp':'image/webp'}
            if ext not in _ALLOWED_MIME:
                return self._send(415, 'text/plain', f'unsupported image extension: {ext}')
            mime = _ALLOWED_MIME[ext]
            try:
                with open(path, 'rb') as f:
                    data = f.read()
            except OSError as e:
                return self._send(500, 'text/plain', f'read failed: {e}')
            self.send_response(200)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'public, max-age=3600')
            self.end_headers()
            self.wfile.write(data)

        # ── Helpers ──────────────────────────────────────────────────────────

        def _json(self, obj):
            body = json.dumps(obj, default=str).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _send(self, code, ctype, body):
            data = body.encode() if isinstance(body, str) else body
            self.send_response(code)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    return Handler


# ─── Templates ──────────────────────────────────────────────────────────────

_STYLE = """
<style>
  /* SmartSoC brand palette — green primary, blue secondary, white bg,
     Montserrat. Matches sales deck + brand guidelines. */
  :root {
    --bg:         #ffffff;
    --panel:      #ffffff;
    --border:     #e5e7eb;
    --text:       #0f141b;
    --muted:      #6b7280;
    --accent:     #00D700;   /* SmartSoC green — primary */
    --accent2:    #0000FF;   /* SmartSoC blue  — secondary */
    --accent-ink: #007a00;   /* darker green for text-on-light */
    --accent-bg:  #f3fff3;   /* green tint */
    --accent2-bg: #ebebff;   /* blue tint */
    --header:     #f7faf7;
    --hover:      #f3fff3;
  }
  * { box-sizing: border-box; }
  html, body { margin:0; background:var(--bg); color:var(--text);
               font-family: "Montserrat", -apple-system, "Segoe UI", Roboto,
                            Helvetica, Arial, sans-serif;
               font-size: 13px; line-height: 1.35; }
  /* Green underline brand marker under the header */
  header.bar { border-top: 4px solid var(--accent); }
  a { color: var(--accent); text-decoration:none; }
  a:hover { text-decoration:underline; }
  code, .mono, .num { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }

  /* Top bar — light, tight single row */
  header.bar { background: var(--panel); border-bottom: 1px solid var(--border);
               padding:8px 14px; display:flex; flex-wrap:wrap;
               align-items:center; gap:14px; }
  header.bar .brand { font-weight:800; font-size:14px; color:var(--text);
                      letter-spacing:.01em; }
  header.bar .brand .lite { color: var(--muted); font-weight:500; margin-left:4px; }
  header.bar .brand::before {
    content:""; display:inline-block; vertical-align:middle;
    width:14px; height:14px; margin-right:8px; border-radius:3px;
    background: linear-gradient(135deg, var(--accent) 0 55%,
                                        var(--accent2) 55% 100%);
  }
  header.bar .proj { color: var(--accent-ink); font-weight:800;
                     text-transform:uppercase; letter-spacing:.03em; }
  header.bar .kv { color: var(--muted); font-size:12px; }
  header.bar .kv b { color: var(--text); font-weight:600; margin-left:4px; }
  header.bar .byline { color: var(--muted); font-size:11px; margin-left:auto; }

  /* ───── Tier 1 — all-projects grid ───── */
  body.tier1 { background: #fafbfc; }
  .tier1-ctrl { padding:18px 20px 10px; display:flex; align-items:center;
                justify-content:space-between; gap:16px; flex-wrap:wrap;
                background: var(--panel); border-bottom:1px solid var(--border); }
  .tier1-h1 { margin:0; font-size:18px; font-weight:800; letter-spacing:.01em;
              color: var(--text); }
  .scope-pills { display:flex; gap:6px; }
  .scope-pill { display:inline-flex; align-items:center; gap:6px;
                padding:7px 14px; font-size:12px; font-weight:700;
                letter-spacing:.03em; border:1px solid var(--border);
                border-radius:3px; color: var(--muted); background: var(--panel);
                text-decoration:none; }
  .scope-pill:hover { color: var(--accent-ink); border-color: var(--accent-ink);
                      text-decoration:none; }
  .scope-pill.on   { color:#fff; background: var(--accent-ink);
                     border-color: var(--accent-ink); }
  .scope-pill .n   { background: rgba(0,0,0,.1); padding:1px 7px;
                     border-radius:10px; font-variant-numeric: tabular-nums;
                     font-size:11px; }
  .scope-pill.on .n{ background: rgba(255,255,255,.25); }

  .proj-cards { display:grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
                gap:14px; padding:16px 20px; }
  .proj-card { display:block; background: var(--panel); border:1px solid var(--border);
               border-left:4px solid var(--accent); border-radius:6px;
               padding:16px 18px; color: var(--text); text-decoration:none;
               transition: box-shadow .15s, transform .15s; }
  .proj-card:hover { box-shadow: 0 4px 16px rgba(0,0,0,.08);
                     text-decoration:none; }
  .proj-card[data-status="archived"] { border-left-color: #9ca3af; opacity:.78; }
  .proj-card[data-status="paused"]   { border-left-color: #d97706; }
  .proj-head { display:flex; align-items:center; justify-content:space-between;
               gap:10px; margin-bottom:4px; }
  .proj-name { font-size:17px; font-weight:800; color: var(--text);
               letter-spacing:-.01em; }
  .proj-desc { color: var(--muted); font-size:12px; min-height:18px;
               margin-bottom:10px; }
  .proj-meta { font-size:11px; margin-top:4px; color: var(--muted); }
  .proj-meta-key { color: var(--muted); }
  .proj-meta-val { color: var(--text); font-weight:600; }
  .proj-meta-dot { color: var(--border); margin:0 6px; }
  .proj-discs { margin-top:10px; display:flex; gap:4px; flex-wrap:wrap; }
  .disc-chip { font-size:10px; font-weight:800; letter-spacing:.05em;
               padding:2px 7px; border-radius:3px; color:#fff; }
  .disc-chip.disc-pd  { background:#1565c0; }
  .disc-chip.disc-dft { background:#0d9488; }
  .disc-chip.disc-dv  { background:#be185d; }
  .proj-verdicts { margin-top:10px; display:flex; align-items:center;
                   gap:4px; font-size:12px; }
  .proj-verdicts .vdot { font-size:14px; line-height:1; }
  .proj-verdicts .vn   { color: var(--text); font-weight:700;
                         margin-right:8px; font-variant-numeric: tabular-nums; }
  .vdot.vp { color:#059669; }     /* PASS */
  .vdot.vc { color:#b45309; }     /* CONDITIONAL */
  .vdot.vb { color:#b91c1c; }     /* BLOCKED */
  .vdot.vu { color:#6b7280; }     /* UNKNOWN */
  .proj-foot { margin-top:10px; padding-top:8px; border-top:1px solid var(--border);
               font-size:11px; color: var(--muted); font-variant-numeric: tabular-nums; }

  .status-pill { display:inline-block; padding:3px 10px; border-radius:3px;
                 font-size:10px; font-weight:800; letter-spacing:.05em; }
  .status-pill.pill-active   { background: var(--accent-bg); color: var(--accent-ink); }
  .status-pill.pill-archived { background:#f3f4f6; color:#4b5563; }
  .status-pill.pill-paused   { background:#fff3e0; color:#92400e; }

  /* ───── Tier 2 — project landing (cards grid above KPI strip) ───── */
  .tier2-cards { padding:14px 20px 0; display:flex; flex-direction:column;
                 gap:12px; background: var(--panel); }
  .sched-card, .resource-card { background: var(--panel); border:1px solid var(--border);
                                border-radius:6px; padding:14px 16px; }
  .card-h { display:flex; align-items:baseline; justify-content:space-between;
            gap:12px; margin-bottom:10px; }
  .card-title { font-size:13px; font-weight:800; letter-spacing:.03em;
                color: var(--text); text-transform:uppercase; }
  .card-sub { font-size:11px; color: var(--muted); }
  .sched-timeline { display:grid; grid-template-columns: repeat(6, 1fr);
                    gap:6px; margin-top:4px; }
  .sched-pip { padding:10px 8px; border-radius:4px; text-align:center;
               border:1px solid var(--border); background: var(--panel); }
  .sched-pip-name { font-size:10px; font-weight:800; letter-spacing:.05em;
                    color: var(--text); }
  .sched-pip-date { font-size:11px; color: var(--muted); margin-top:3px;
                    font-variant-numeric: tabular-nums; }
  .sched-pip.sched-past   { background: var(--accent-bg); border-color: var(--accent-ink); }
  .sched-pip.sched-past   .sched-pip-name { color: var(--accent-ink); }
  .sched-pip.sched-future { background:#f8fafc; }
  .sched-note { margin-top:10px; padding:8px 10px; font-size:11px;
                color: var(--muted); background:#fffbeb; border-left:3px solid #d97706;
                border-radius:3px; }
  .resource-grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
                   gap:12px; margin-top:4px; }
  .resource-stat { padding:10px 12px; background: var(--header);
                   border-radius:4px; }
  .resource-stat-val { font-size:20px; font-weight:800;
                       color: var(--text); font-variant-numeric: tabular-nums; }
  .resource-stat-lbl { font-size:10px; color: var(--muted); text-transform:uppercase;
                       letter-spacing:.04em; margin-top:2px; }
  .resource-note { margin-top:8px; font-size:11px; color: var(--muted); }
  .muted { color: var(--muted); }

  @media print {
    .scope-pills, .filter-pills, .filters { display:none; }
    body { background:#fff; }
    .proj-card { break-inside: avoid; }
  }

  /* Discipline cards — one per enabled discipline (PD / DFT / DV).
     Cards sit above the KPI strip and link to each discipline's running
     daemon URL (or render an inline hint when the daemon is offline).
     Disciplines the project doesn't declare are omitted entirely. */
  .disc-cards { display:grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
                gap:12px; padding:14px; background: var(--header);
                border-bottom:1px solid var(--border); }
  .disc-card { background: var(--panel); border:1px solid var(--border);
               border-radius:6px; padding:14px 16px; display:flex;
               flex-direction:column; gap:8px; position:relative;
               border-left:4px solid var(--disc-accent, var(--accent)); }
  .disc-card.pd  { --disc-accent:#1565c0; }
  .disc-card.dft { --disc-accent:#0d9488; }
  .disc-card.dv  { --disc-accent:#be185d; }
  .disc-card .disc-h { display:flex; align-items:center; gap:10px; }
  .disc-card .disc-badge { width:36px; height:36px; border-radius:6px;
                           background: var(--disc-accent); color:#fff;
                           display:flex; align-items:center;
                           justify-content:center; font-weight:800;
                           font-size:13px; letter-spacing:.03em; }
  .disc-card .disc-name { font-weight:800; font-size:15px;
                          color: var(--disc-accent); letter-spacing:.02em; }
  .disc-card .disc-meta { color: var(--muted); font-size:11px;
                          font-variant-numeric: tabular-nums; }
  .disc-card .disc-open { display:inline-block; margin-top:2px;
                          padding:7px 14px; background: var(--disc-accent);
                          color:#fff !important; border-radius:4px;
                          font-weight:700; font-size:12px;
                          text-align:center; text-decoration:none;
                          letter-spacing:.02em; }
  .disc-card .disc-open:hover { opacity:.9; text-decoration:none; }
  .disc-card .disc-hint { color: var(--muted); font-size:11px;
                          background: var(--header); padding:7px 10px;
                          border-radius:3px; border:1px dashed var(--border);
                          font-family: ui-monospace, "SF Mono", Menlo,
                                       Consolas, monospace; }

  /* KPI strip */
  .kpi { display:flex; gap:0; background: var(--panel);
         border-bottom:1px solid var(--border); }
  .kpi > div { flex:1; padding:10px 14px; border-right:1px solid var(--border); }
  .kpi > div:last-child { border-right:0; }
  .kpi .lbl { color: var(--muted); font-size:11px; text-transform:uppercase;
              letter-spacing:.04em; }
  .kpi .val { color: var(--text); font-size:20px; font-weight:700; margin-top:2px;
              font-variant-numeric:tabular-nums; }
  .kpi .sub { color: var(--muted); font-size:11px; }
  .kpi .val .pass { color:#059669; }
  .kpi .val .cond { color:#b45309; }
  .kpi .val .blk  { color:#b91c1c; }

  /* Filters row */
  .filters { display:flex; flex-wrap:wrap; gap:10px; align-items:center;
             padding:8px 14px; background: var(--panel);
             border-bottom:1px solid var(--border); font-size:12px; }
  .filters label { color: var(--muted); }
  .filters input, .filters select {
    background: #fff; color: var(--text); border:1px solid var(--border);
    border-radius:3px; padding:3px 8px; font-family:inherit; font-size:12px;
  }
  .filters input[type=search] { min-width:220px; }
  .filters .spacer { flex:1; }
  .filters .count  { color: var(--muted); font-family: ui-monospace, monospace; }

  main { padding: 0; }

  /* Section header row */
  .sec-h { display:flex; align-items:baseline; padding:6px 14px;
           background: var(--header); border-bottom:1px solid var(--border);
           color: var(--text); font-size:12px; text-transform:uppercase;
           letter-spacing:.05em; font-weight:600; }
  .sec-h .hint { color: var(--muted); font-size:11px; margin-left:10px;
                 text-transform:none; letter-spacing:0; font-weight:400; }

  /* Dense tables */
  table.d { width:100%; border-collapse:collapse; font-size:12px;
            background: var(--panel); }
  table.d th, table.d td { padding:5px 10px; border-bottom:1px solid var(--border);
                           text-align:left; vertical-align:top; white-space:nowrap; }
  table.d th { position:sticky; top:0; background: var(--header); color: var(--text);
               font-weight:600; cursor:pointer; user-select:none;
               border-bottom:1px solid var(--border); }
  table.d th:hover { background:#e5e7eb; }
  table.d th.sorted-asc::after  { content:' ▲'; color: var(--accent); }
  table.d th.sorted-desc::after { content:' ▼'; color: var(--accent); }
  table.d td.num { font-family: ui-monospace, monospace;
                   font-variant-numeric:tabular-nums; text-align:right; }
  table.d tr:hover td { background: var(--hover); }

  /* Detail — property list, tight */
  .kv-grid { display:grid; grid-template-columns:auto 1fr;
             column-gap:16px; row-gap:2px; padding:8px 14px;
             font-size:12px; background: var(--panel);
             border-bottom:1px solid var(--border); }
  .kv-grid dt { color: var(--muted); }
  .kv-grid dd { margin:0; color: var(--text); font-family: ui-monospace, monospace; }

  .empty { padding:12px 14px; color: var(--muted); font-style:italic; font-size:12px;
           background: var(--panel); border-bottom: 1px solid var(--border); }
  .back { padding:6px 14px; background: var(--panel);
          border-bottom:1px solid var(--border); font-size:12px; }

  /* Tab bar */
  nav.tabs { background: var(--panel); border-bottom: 1px solid var(--border);
             padding: 0 14px; display: flex; gap: 0; overflow-x: auto; }
  nav.tabs a { display: inline-block; padding: 9px 16px; font-size: 12px;
               color: var(--muted); border-bottom: 2px solid transparent;
               font-weight: 500; text-decoration: none; white-space: nowrap; }
  nav.tabs a:hover { color: var(--text); background: var(--hover); }
  nav.tabs a.active { color: var(--accent); border-bottom-color: var(--accent);
                      font-weight: 600; }
  nav.tabs a .badge { display: inline-block; margin-left: 6px;
                      background: var(--hover); color: var(--muted);
                      padding: 0 6px; border-radius: 8px; font-size: 11px;
                      font-family: ui-monospace, monospace; }
  nav.tabs a.active .badge { background: var(--accent); color: white; }
  .tab-body { display: none; }
  .tab-body.active { display: block; }

  /* Timing debugger — path list */
  #td-list table { width:100%; border-collapse:collapse; font-size:12px; }
  #td-list th, #td-list td { padding:5px 6px; border-bottom:1px solid var(--border);
                             text-align:left; vertical-align:top; }
  #td-list th { background:var(--header); position:sticky; top:0;
                font-weight:600; color:var(--muted); font-size:11px;
                text-transform:uppercase; letter-spacing:.03em; }
  #td-list td.slack { text-align:right; font-family:ui-monospace,monospace;
                      font-variant-numeric:tabular-nums; }
  #td-list td.neg { color:#dc2626; font-weight:600; }
  #td-list td.pos { color:#059669; }
  #td-list tr { cursor:pointer; }
  #td-list tr:hover td { background:var(--hover); }
  #td-list tr.active td { background:var(--accent2-bg); }   /* brand blue tint */
  #td-list .tsub { font-family:ui-monospace,monospace; font-size:11px;
                   color:var(--muted); font-weight:normal; margin-top:2px;
                   text-overflow:ellipsis; overflow:hidden; max-width:180px; }
  #td-list .ttag { display:inline-block; padding:0 5px; margin-left:4px;
                   font-size:10px; background:var(--accent-bg); color:var(--accent-ink);
                   border-radius:8px; font-weight:600; vertical-align:middle; }
  #td-list .scentag { display:inline-block; padding:0 5px; margin-left:4px;
                      font-size:10px; background:#fef3c7; color:#92400e;
                      border-radius:8px; font-weight:600; vertical-align:middle;
                      font-family:ui-monospace,monospace; cursor:help; }
  .pchip { display:inline-block; padding:1px 6px; margin:1px 2px 1px 0;
           font-size:10px; background:var(--accent-bg); color:var(--accent-ink);
           border-radius:8px; font-family:ui-monospace,monospace; }
  .pchip b { color:var(--accent-ink); font-weight:700; margin-right:2px; }
  .segdot { display:inline-block; width:9px; height:9px; border-radius:2px;
            margin-right:4px; vertical-align:middle; }
  .td-selbtn { padding:3px 8px; background:#fff; color:var(--text);
               border:1px solid var(--border); border-radius:3px;
               cursor:pointer; font-size:11px; flex:1; min-width:0;
               white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .td-selbtn:hover { background:var(--hover); }
  .td-selbtn.active { background:#dbeafe; border-color:#93c5fd;
                      color:#1e40af; font-weight:600; }
  .td-selbtn { display:inline-flex; align-items:center; gap:6px;
               justify-content:center; }
  .cbadge { display:inline-block; padding:1px 6px; font-size:10px;
            font-family:ui-monospace,monospace; background:var(--accent-bg);
            color:var(--accent-ink); border-radius:8px; min-width:18px;
            text-align:center; }
  .td-modebtn { padding:3px 10px; background:#fff; color:var(--muted);
                border:none; cursor:pointer; font-size:11px;
                font-family:inherit; }
  .td-modebtn + .td-modebtn { border-left:1px solid var(--border); }
  .td-modebtn:hover { background:var(--hover); }
  .td-modebtn.active[data-mode="include"] {
    background:#dcfce7; color:#166534; font-weight:600;
  }
  .td-modebtn.active[data-mode="exclude"] {
    background:#fee2e2; color:#991b1b; font-weight:600;
  }
  /* Detailed-path modal table */
  .pdet { width:100%; border-collapse:collapse; font-size:12px;
          font-family:ui-monospace,monospace; }
  .pdet th { background:var(--header); position:sticky; top:0;
             font-weight:600; color:var(--muted); font-size:10px;
             text-transform:uppercase; letter-spacing:.04em;
             text-align:left; padding:8px 10px; border-bottom:1px solid var(--border); }
  .pdet th .unit { color:#94a3b8; font-weight:400; font-size:9px; }
  .pdet td { padding:5px 10px; border-bottom:1px solid #f1f5f9; }
  .pdet td.num { text-align:right; font-variant-numeric:tabular-nums; }
  .pdet td.num.strong { font-weight:600; color:var(--text); }
  .pdet tr.segrow td { border-bottom:1px solid var(--border);
                       border-top:1px solid var(--border); }
  .pdet .pinsuf { color:var(--muted); }
  .pdet .slack.neg { color:#dc2626; font-weight:600; }
  .pdet .slack.pos { color:#059669; font-weight:600; }
  /* Raw report_timing display */
  .rpt-toolbar { display:flex; align-items:center; gap:10px;
                 padding:6px 12px; border-bottom:1px solid var(--border);
                 background:var(--header); }
  .rpt-btn { padding:3px 10px; background:#fff; color:var(--text);
             border:1px solid var(--border); border-radius:3px;
             cursor:pointer; font-size:11px; }
  .rpt-hint { color:var(--muted); font-size:11px; font-style:italic; }
  .rpt { margin:0; padding:14px 18px; font-family:ui-monospace,Menlo,monospace;
         font-size:12px; line-height:1.45; color:#0f172a; white-space:pre;
         overflow-x:auto; background:#fff; }

  /* Image gallery */
  .img-grid { display:grid; gap:10px;
              grid-template-columns:repeat(auto-fit,minmax(300px,1fr));
              padding:12px 14px; background: var(--panel);
              border-bottom:1px solid var(--border); }
  .img-card { border:1px solid var(--border); border-radius:3px;
              background:#fff; overflow:hidden; }
  .img-card .caption { padding:6px 10px; font-size:11px; color:var(--muted);
                       background:var(--header); border-top:1px solid var(--border);
                       font-family:ui-monospace,monospace; }
  .img-card img { display:block; width:100%; height:auto; }
</style>
"""

_SCRIPT_RELOAD_ON_FOCUS = """
<script>
  // Reload only when the tab regains focus — snapshots only change via
  // publish, so polling wastes cycles.
  window.addEventListener('focus', () => { location.reload(); });
</script>
"""


# The floorplan pane is inserted only when has_floorplan is true. The JS
# fetches /api/floorplan/<PID>, scales the DIEAREA to fit the canvas, and
# draws rows as light guides + cells as dim rectangles. No cell geometry,
# just macro width/height from LEF applied at the cell's placed x/y.
_FLOORPLAN_PANE = """
  <section style="background:var(--panel);padding:10px 14px;
                  border-bottom:1px solid var(--border)">
    <div id="fp-status" style="color:var(--muted);font-size:12px;margin-bottom:8px">
      loading…
    </div>
    <div style="display:flex;gap:8px;margin-bottom:8px;font-size:12px;flex-wrap:wrap;
                align-items:center">
      <button id="fp-zin"  style="padding:4px 10px;background:#fff;color:var(--text);
                                  border:1px solid var(--border);border-radius:3px;cursor:pointer">
        + zoom in
      </button>
      <button id="fp-zout" style="padding:4px 10px;background:#fff;color:var(--text);
                                  border:1px solid var(--border);border-radius:3px;cursor:pointer">
        &minus; zoom out
      </button>
      <button id="fp-fit"  style="padding:4px 10px;background:#fff;color:var(--text);
                                  border:1px solid var(--border);border-radius:3px;cursor:pointer">
        ⊕ fit
      </button>
      <span style="width:16px"></span>
      <input id="fp-search" type="search" placeholder="Search instance / cell name…"
             style="padding:4px 8px;min-width:240px;background:#0b1220;color:#e2e8f0;
                    border:1px solid #475569;border-radius:4px;font-family:inherit">
      <select id="fp-scope"
              style="padding:4px 8px;background:#0b1220;color:#e2e8f0;
                     border:1px solid #475569;border-radius:4px">
        <option value="both">both</option>
        <option value="instance">instance name</option>
        <option value="macro">cell (macro) name</option>
      </select>
      <label style="display:flex;align-items:center;gap:4px;color:#94a3b8">
        color
        <input id="fp-color" type="color" value="#f97316"
               style="width:28px;height:24px;padding:0;border:1px solid #475569;
                      border-radius:4px;background:none;cursor:pointer">
      </label>
      <button id="fp-clear" style="padding:4px 10px;background:#fff;color:var(--text);
                                   border:1px solid var(--border);border-radius:3px;cursor:pointer">
        clear
      </button>
      <button id="fp-zoomto" style="padding:4px 10px;background:#fff;color:var(--text);
                                    border:1px solid var(--border);border-radius:3px;cursor:pointer">
        zoom to matches
      </button>
      <span id="fp-count" style="color:var(--muted);font-family:monospace"></span>
      <span style="color:var(--muted);flex-basis:100%">
        wheel = zoom · drag = pan · click a cell = show instance · type in the box to highlight
      </span>
    </div>
    <div id="fp-body" style="display:flex;gap:8px;align-items:stretch;
                             min-height:70vh">
      <aside id="td-panel" style="display:none;width:340px;flex:0 0 340px;
                                 padding:10px 12px;background:var(--panel);
                                 border:1px solid var(--border);border-radius:3px;
                                 flex-direction:column;gap:8px">
        <div style="display:flex;align-items:center;justify-content:space-between;gap:6px">
          <b style="color:var(--text);font-size:13px">Timing debugger</b>
          <div style="display:flex;gap:4px">
            <button id="td-detail" disabled style="padding:2px 8px;background:#fff;
                    color:var(--text);border:1px solid var(--border);
                    border-radius:3px;cursor:pointer;font-size:11px;opacity:0.5">
              detailed path
            </button>
            <button id="td-clear" style="padding:2px 8px;background:#fff;
                    color:var(--text);border:1px solid var(--border);
                    border-radius:3px;cursor:pointer;font-size:11px">clear</button>
          </div>
        </div>
        <label style="display:flex;flex-direction:column;gap:2px;font-size:11px;
                      color:var(--muted)">
          Scenario (PVT)
          <select id="td-scenario" style="padding:4px 6px;background:#fff;
                    color:var(--text);border:1px solid var(--border);
                    border-radius:3px;font-family:inherit;font-size:12px">
            <option value="__all__">all scenarios</option>
          </select>
        </label>
        <label style="display:flex;flex-direction:column;gap:2px;font-size:11px;
                      color:var(--muted)">
          Clock group (failing only)
          <select id="td-group" style="padding:4px 6px;background:#fff;
                    color:var(--text);border:1px solid var(--border);
                    border-radius:3px;font-family:inherit;font-size:12px">
          </select>
        </label>
        <label style="display:flex;flex-direction:column;gap:2px;font-size:11px;
                      color:var(--muted)">
          Path type
          <select id="td-type" style="padding:4px 6px;background:#fff;
                    color:var(--text);border:1px solid var(--border);
                    border-radius:3px;font-family:inherit;font-size:12px">
            <option value="all">all</option>
            <option value="max">max (setup)</option>
            <option value="min">min (hold)</option>
          </select>
        </label>
        <label style="display:flex;flex-direction:column;gap:2px;font-size:11px;
                      color:var(--muted)">
          Search
          <div style="display:flex;gap:4px">
            <select id="td-scope" style="padding:4px 6px;background:#fff;
                    color:var(--text);border:1px solid var(--border);
                    border-radius:3px;font-family:inherit;font-size:12px;
                    flex:0 0 92px">
              <option value="any">any</option>
              <option value="cell">cell</option>
              <option value="start">start</option>
              <option value="end">end</option>
              <option value="clock">clock path</option>
              <option value="data">data path</option>
            </select>
            <input id="td-search" type="search"
                   autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false"
                   placeholder="type to filter…"
                   style="padding:4px 6px;background:#fff;color:var(--text);
                          border:1px solid var(--border);border-radius:3px;
                          font-family:inherit;font-size:12px;flex:1;min-width:0">
          </div>
          <div id="td-mode" role="radiogroup"
               style="display:inline-flex;border:1px solid var(--border);
                      border-radius:3px;overflow:hidden;font-size:11px;
                      align-self:flex-start">
            <button id="td-mode-include" class="td-modebtn active"
                    data-mode="include" type="button"
                    title="Show only paths that match the search pattern.">
              include
            </button>
            <button id="td-mode-exclude" class="td-modebtn"
                    data-mode="exclude" type="button"
                    title="Show only paths that do NOT match the search pattern.">
              exclude
            </button>
          </div>
          <span id="td-parsed" style="color:var(--muted);font-size:10px;
                min-height:14px;line-height:1.4"></span>
        </label>
        <div style="display:flex;gap:8px;flex-wrap:wrap;font-size:11px;
                    color:var(--muted);align-items:center">
          <span><span class="segdot" style="background:#06b6d4"></span>launch clk</span>
          <span><span class="segdot" style="background:#f472b6"></span>data</span>
          <span><span class="segdot" style="background:#f59e0b"></span>capture clk</span>
          <span>&rarr; = direction</span>
        </div>
        <div style="display:flex;gap:4px;flex-wrap:wrap;font-size:11px">
          <button id="td-select-group" class="td-selbtn"
                  title="Draw every failing path in the current clock group.">
            <span>group</span>
            <span class="cbadge" id="td-selgroup-n">0</span>
          </button>
          <button id="td-select-matches" class="td-selbtn"
                  title="Draw only the paths that survive the current search/type filter.">
            <span>matches</span>
            <span class="cbadge" id="td-selmatch-n">0</span>
          </button>
        </div>
        <span id="td-count" style="color:var(--muted);
              font-family:monospace;font-size:11px"></span>
        <div id="td-list" style="flex:1;min-height:0;overflow-y:auto;
                border:1px solid var(--border);border-radius:3px;
                background:#fff"></div>
        <div id="td-pager" style="display:flex;align-items:center;
                justify-content:space-between;font-size:12px;color:var(--muted);
                font-family:ui-monospace,monospace">
          <button id="td-prev" style="padding:2px 10px;background:#fff;
                  color:var(--text);border:1px solid var(--border);
                  border-radius:3px;cursor:pointer;font-size:14px"
                  aria-label="previous page">&lsaquo;</button>
          <span id="td-page">1 / 1</span>
          <button id="td-next" style="padding:2px 10px;background:#fff;
                  color:var(--text);border:1px solid var(--border);
                  border-radius:3px;cursor:pointer;font-size:14px"
                  aria-label="next page">&rsaquo;</button>
        </div>
      </aside>
      <div id="fp-wrap" style="flex:1;min-width:0;position:relative;
                               background:#0b1220;border:1px solid var(--border);
                               border-radius:3px;padding:6px">
        <canvas id="fp-canvas"
                style="width:100%;height:70vh;display:block;
                       cursor:grab;user-select:none"></canvas>
        <div id="fp-tip" style="display:none;position:absolute;pointer-events:none;
                                background:#fff;border:1px solid var(--border);
                                border-radius:3px;padding:6px 10px;font-size:12px;
                                color:var(--text);font-family:monospace;
                                box-shadow:0 4px 12px rgba(0,0,0,.10);z-index:10">
        </div>
      </div>
    </div>
    <div style="margin-top:8px;font-size:12px;color:var(--muted)">
      <span style="display:inline-block;width:12px;height:12px;background:#22c55e;
                   vertical-align:middle;margin-right:4px"></span> Std cells
      &nbsp;·&nbsp;
      <span style="display:inline-block;width:14px;height:10px;background:#3b82f6;
                   border:1px solid #60a5fa;
                   vertical-align:middle;margin-right:4px"></span> Hard macros (SRAM / block)
      &nbsp;·&nbsp;
      <span style="display:inline-block;width:12px;height:8px;
                   background:rgba(148,163,184,0.15);
                   border-top:1px solid #475569;border-bottom:1px solid #475569;
                   vertical-align:middle;margin-right:4px"></span> Rows
      &nbsp;·&nbsp;
      <span style="display:inline-block;width:12px;height:2px;
                   border:1px solid #f59e0b;vertical-align:middle;margin-right:4px">
      </span> Die area
    </div>

    <!-- Detailed-path modal — hidden until the user opens it. -->
    <div id="td-modal" style="display:none;position:fixed;inset:0;z-index:100;
                              background:rgba(15,23,42,0.55);
                              align-items:center;justify-content:center">
      <div style="background:#fff;border-radius:6px;box-shadow:0 20px 60px rgba(0,0,0,.35);
                  width:min(920px,92vw);max-height:88vh;display:flex;flex-direction:column;
                  overflow:hidden">
        <header style="display:flex;align-items:center;justify-content:space-between;
                       padding:12px 16px;border-bottom:1px solid var(--border);
                       background:var(--header)">
          <div>
            <div style="font-size:14px;font-weight:600;color:var(--text)">
              Detailed timing path
            </div>
            <div id="td-modal-sub" style="font-size:11px;color:var(--muted);
                    font-family:ui-monospace,monospace;margin-top:2px"></div>
          </div>
          <button id="td-modal-close" style="padding:4px 12px;background:#fff;
                  color:var(--text);border:1px solid var(--border);
                  border-radius:3px;cursor:pointer;font-size:12px">close</button>
        </header>
        <div id="td-modal-body" style="flex:1;overflow:auto;padding:0"></div>
        <footer style="padding:8px 16px;border-top:1px solid var(--border);
                       font-size:11px;color:var(--muted);
                       display:flex;gap:12px;flex-wrap:wrap">
          <span>path highlight uses launch/data/capture colors on the canvas</span>
          <span style="margin-left:auto">Esc or click backdrop to close</span>
        </footer>
      </div>
    </div>
  </section>
  <script>
    (function() {
      const status = document.getElementById('fp-status');
      const canvas = document.getElementById('fp-canvas');
      const tip    = document.getElementById('fp-tip');
      fetch('/api/floorplan/{PID}')
        .then(r => r.ok ? r.json() : Promise.reject(r.status))
        .then(fp => {
          const inst = setupFloorplan(fp, canvas, status, tip);
          // Kick off timing fetch — if there is any, mount the debugger.
          return fetch('/api/timing/{PID}').then(r => r.ok ? r.json() : null)
                 .then(t => t && setupTiming(t, inst));
        })
        .catch(err => { status.textContent = 'floorplan unavailable (' + err + ')'; });
    })();

    // Compact scenario tag — take the corner+voltage+temp middle chunk
    // and drop the mode prefix + rc suffix so it fits in the path row.
    // "func_ss_0p76v_rcmax_125c" → "ss/0p76v/125c". Full name in tooltip.
    function _scenAbbrev(name) {
      if (!name) return '';
      const parts = name.split('_');
      // Heuristic: first token = mode, second = corner, third = voltage,
      // fourth = rc, fifth = temperature. Missing pieces are ignored.
      if (parts.length >= 5) {
        return `${parts[1]}/${parts[2]}/${parts[4]}`;
      }
      return name.length > 14 ? name.slice(0, 12) + '…' : name;
    }

    // Front-elide a hierarchical instance name so the leaf stays visible.
    // "u_core/u_exec/u_alu/U124" with maxLen=22 → "…/u_alu/U124".
    // If the name is already short enough, return it unchanged.
    function elideHier(name, maxLen) {
      if (!name) return '';
      if (name.length <= maxLen) return name;
      const parts = name.split('/');
      // Grow the leaf-suffix from the right until we hit the budget.
      let acc = parts[parts.length - 1];
      for (let i = parts.length - 2; i >= 0; i--) {
        const next = parts[i] + '/' + acc;
        if (next.length + 2 > maxLen) break;   // +2 for the "…/"
        acc = next;
      }
      return '…/' + acc;
    }

    function setupTiming(timing, fp) {
      const panel   = document.getElementById('td-panel');
      const grp     = document.getElementById('td-group');
      const typ     = document.getElementById('td-type');
      const search  = document.getElementById('td-search');
      const scope   = document.getElementById('td-scope');
      const scen    = document.getElementById('td-scenario');
      const modeInc = document.getElementById('td-mode-include');
      const modeExc = document.getElementById('td-mode-exclude');
      const parsed  = document.getElementById('td-parsed');
      const clearBtn= document.getElementById('td-clear');
      const detailBtn=document.getElementById('td-detail');
      const selGroupBtn=document.getElementById('td-select-group');
      const selMatchesBtn=document.getElementById('td-select-matches');
      const selGroupN=document.getElementById('td-selgroup-n');
      const selMatchN=document.getElementById('td-selmatch-n');
      const list    = document.getElementById('td-list');
      const cnt     = document.getElementById('td-count');
      const pager   = document.getElementById('td-pager');
      const prevBtn = document.getElementById('td-prev');
      const nextBtn = document.getElementById('td-next');
      const pageLbl = document.getElementById('td-page');
      const modal   = document.getElementById('td-modal');
      const modalSub= document.getElementById('td-modal-sub');
      const modalBody=document.getElementById('td-modal-body');
      const modalClose=document.getElementById('td-modal-close');
      let selectedPath = null;
      if (!panel || !timing.clock_groups || !timing.clock_groups.length) return;

      const PAGE_SIZE = 10;
      const PER_GROUP_CAP = 100;

      // Collect all scenarios present in the payload (across every group,
      // every path). Sort so the dropdown is stable across reloads.
      const scenarioSet = new Set();
      for (const g of timing.clock_groups) {
        for (const p of (g.paths || [])) {
          if (p.scenario) scenarioSet.add(p.scenario);
        }
      }
      const scenarios = Array.from(scenarioSet).sort();

      // Compute failing groups PER scenario slice. Recomputes when the
      // scenario dropdown changes. When "all scenarios" is selected, the
      // slice is the union of all paths (matching pre-scenario behavior).
      function computeFailingGroups(scenName) {
        const out = [];
        for (const g of timing.clock_groups) {
          const paths = (g.paths || []).filter(p =>
            (scenName === '__all__' || p.scenario === scenName) &&
            p.slack !== undefined && p.slack < 0
          );
          if (paths.length === 0) continue;
          const violators = paths
            .sort((a, b) => a.slack - b.slack)
            .slice(0, PER_GROUP_CAP);
          violators.forEach((p, i) => { p._rank = i + 1; });
          out.push({
            name: g.name,
            wns: violators[0].slack,
            violators: violators,
          });
        }
        out.sort((a, b) => a.wns - b.wns);
        return out;
      }

      // Initial group state — under "all scenarios". If no failing paths
      // exist anywhere in any scenario, hide the panel entirely.
      let failingGroups = computeFailingGroups('__all__');
      if (failingGroups.length === 0) {
        panel.style.display = 'none';
        return;
      }
      panel.style.display = 'flex';

      // Populate scenario dropdown. Each option shows the per-scenario
      // failing-group count + worst WNS across all groups so the user can
      // pick "the corner with the most damage" at a glance.
      scen.innerHTML = '';
      {
        const optAll = document.createElement('option');
        optAll.value = '__all__';
        const anyGroups = failingGroups.length;
        const anyWns = failingGroups[0] ? failingGroups[0].wns : 0;
        optAll.textContent = `all scenarios  (${anyGroups} failing groups · WNS ${anyWns.toFixed(3)})`;
        scen.appendChild(optAll);
      }
      for (const s of scenarios) {
        const gs = computeFailingGroups(s);
        if (gs.length === 0) continue;         // scenario is clean — skip it
        const o = document.createElement('option');
        o.value = s;
        o.textContent = `${s}  (${gs.length} failing groups · WNS ${gs[0].wns.toFixed(3)})`;
        scen.appendChild(o);
      }

      function rebuildGroups() {
        failingGroups = computeFailingGroups(scen.value);
        grp.innerHTML = '';
        for (const g of failingGroups) {
          const o = document.createElement('option');
          o.value = g.name;
          o.textContent = `${g.name}  (${g.violators.length} viol · WNS ${g.wns.toFixed(3)})`;
          grp.appendChild(o);
        }
      }
      rebuildGroups();

      // Two ways to filter: pick a scope from the dropdown, or type
      // "scope:term" prefixes in the search box. The two combine — every
      // scoped term must match somewhere in the path.
      // Supported scopes: cell, start, end, clock, data. Prefix syntax is
      // forgiving: "cell:foo", "cell: foo", "Cell: foo" all parse.
      const SCOPES = ['cell', 'start', 'end', 'clock', 'data'];
      // Regex literal so backslash escapes survive Python string interpolation.
      const PREFIX_RE = /^(cell|start|end|clock|data)\s*:\s*(.*)$/i;

      function parseQuery(rawQ, dropdownScope) {
        const q = {general: [], cell: [], start: [], end: [], clock: [], data: []};
        // Prefix parsing walks the raw string (not toLowerCase'd yet) so we
        // can preserve boundaries. Split on whitespace but re-glue when a
        // bare "cell:" is followed by a plain token.
        const raw = (rawQ || '').trim();
        if (!raw && dropdownScope === 'any') return q;
        const parts = raw.split(/\s+/).filter(Boolean);
        for (let i = 0; i < parts.length; i++) {
          const t = parts[i];
          const m = t.match(PREFIX_RE);
          if (m) {
            let val = m[2];
            // "cell:" alone — pull the next token as the value.
            if (!val && i + 1 < parts.length && !parts[i+1].match(PREFIX_RE)) {
              val = parts[i+1];
              i++;
            }
            if (val) q[m[1].toLowerCase()].push(val.toLowerCase());
          } else {
            q.general.push(t.toLowerCase());
          }
        }
        // If a dropdown scope is set, ALL bare terms migrate to that scope.
        if (dropdownScope && dropdownScope !== 'any' && q.general.length) {
          q[dropdownScope].push(...q.general);
          q.general = [];
        }
        return q;
      }

      function matchPath(p, q) {
        const has = (arr, needles) =>
          needles.every(n => (arr || []).some(s => (s || '').toLowerCase().includes(n)));
        // Pre-collect segment lists so scoped searches don't rescan repeatedly.
        const start = p.start || '';
        const end   = p.end   || '';
        const insts = p.instances || [];
        const names   = insts.map(i => i.name || '');
        const macros  = insts.map(i => i.macro || '');
        // 'clock' scope covers legacy 'clock' + new 'launch_clock' / 'capture_clock'.
        const isClk = s => s === 'clock' || s === 'launch_clock' || s === 'capture_clock';
        const clockNs = insts.filter(i => isClk(i.seg)).map(i => i.name || '');
        const clockMs = insts.filter(i => isClk(i.seg)).map(i => i.macro || '');
        const dataNs  = insts.filter(i => i.seg === 'data' ).map(i => i.name || '');
        const dataMs  = insts.filter(i => i.seg === 'data' ).map(i => i.macro || '');
        if (!has([start], q.start))               return false;
        if (!has([end],   q.end))                 return false;
        if (!has([...names, ...macros], q.cell))  return false;
        if (!has([...clockNs, ...clockMs], q.clock)) return false;
        if (!has([...dataNs,  ...dataMs],  q.data))  return false;
        if (q.general.length) {
          const pool = [start, end, ...names, ...macros];
          if (!q.general.every(n => pool.some(s => (s || '').toLowerCase().includes(n))))
            return false;
        }
        return true;
      }

      function queryIsEmpty(q) {
        if (q.general.length) return false;
        for (const s of SCOPES) if (q[s].length) return false;
        return true;
      }

      function currentMode() {
        return modeExc.classList.contains('active') ? 'exclude' : 'include';
      }

      function renderParsedChips(q) {
        // Visible feedback: chips for every active filter so the user can
        // see what actually got applied. Leading mode chip in red/green so
        // it's obvious whether the search includes or excludes.
        const chips = [];
        const empty = queryIsEmpty(q);
        const mode  = currentMode();
        if (scen.value !== '__all__') {
          chips.push(
            `<span class="pchip" style="background:#fef3c7;color:#78350f">` +
            `<b>scenario:</b>${scen.value}</span>`);
        }
        if (!empty) {
          const styleFg = mode === 'exclude' ? '#991b1b' : '#166534';
          const styleBg = mode === 'exclude' ? '#fee2e2' : '#dcfce7';
          chips.push(
            `<span class="pchip" style="background:${styleBg};color:${styleFg}">` +
            `<b>${mode.toUpperCase()}</b></span>`);
        }
        for (const s of SCOPES) {
          for (const v of q[s]) chips.push(
            `<span class="pchip"><b>${s}:</b>${v}</span>`);
        }
        for (const v of q.general) chips.push(
          `<span class="pchip"><b>any:</b>${v}</span>`);
        parsed.innerHTML = chips.length
          ? chips.join(' ')
          : '<i style="color:var(--muted)">no filter</i>';
      }

      const state = {page: 0};
      function currentGroup() {
        return failingGroups.find(x => x.name === grp.value) || failingGroups[0];
      }
      function filteredRows() {
        const g = currentGroup();
        if (!g) return [];
        const q = parseQuery(search.value, scope.value);
        renderParsedChips(q);
        const typeFilt = typ.value;
        const empty    = queryIsEmpty(q);
        const excluding = currentMode() === 'exclude';
        return g.violators.filter(p => {
          if (typeFilt !== 'all' && p.type !== typeFilt) return false;
          if (empty) return true;                       // empty pattern = no filter
          const hit = matchPath(p, q);
          return excluding ? !hit : hit;
        });
      }

      function render() {
        const g = currentGroup();
        const rows = filteredRows();
        const totalPages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
        if (state.page >= totalPages) state.page = totalPages - 1;
        if (state.page < 0) state.page = 0;
        const startIdx = state.page * PAGE_SIZE;
        const pageRows = rows.slice(startIdx, startIdx + PAGE_SIZE);

        cnt.textContent =
          `${rows.length} / ${g.violators.length} violators shown  ·  WNS ${g.wns.toFixed(3)} ns`;
        pageLbl.textContent = `${state.page + 1} / ${totalPages}  (${rows.length})`;
        prevBtn.disabled = state.page === 0;
        nextBtn.disabled = state.page >= totalPages - 1;
        prevBtn.style.opacity = prevBtn.disabled ? 0.4 : 1;
        nextBtn.style.opacity = nextBtn.disabled ? 0.4 : 1;

        // Live counts on the bulk-select buttons so the user sees the
        // filter actually applying (or not) BEFORE clicking.
        selGroupN.textContent = g.violators.length;
        selMatchN.textContent = rows.length;
        // Detect group change — re-frame on group change so the new group's
        // bbox comes into view, but SKIP framing on search/type churn so
        // typing in the search box doesn't jerk the zoom on every keystroke.
        const groupChanged = state.lastGroup !== g.name;
        state.lastGroup = g.name;
        if (selMatchesBtn.classList.contains('active')) {
          fp.setPaths(rows, {skipFrame: !groupChanged});
        } else if (selGroupBtn.classList.contains('active')) {
          fp.setPaths(g.violators, {skipFrame: !groupChanged});
        } else if (groupChanged) {
          // Group changed but no bulk selection active — clear any stale
          // bulk paths from the previous group so the canvas doesn't show
          // both groups' flight lines overlaid.
          fp.setPaths([], {skipFrame: true});
        }

        let html = '<table><thead><tr>' +
                   '<th style="width:34px">#</th>' +
                   '<th>Slack (ns)</th>' +
                   '<th style="width:32px">hops</th>' +
                   '</tr></thead><tbody>';
        if (pageRows.length === 0) {
          html += '<tr><td colspan="3" style="color:var(--muted);' +
                  'text-align:center;padding:14px 6px">no paths match</td></tr>';
        }
        // Show scenario tag on each row when "all scenarios" is active
        // (so the user can tell which corner produced each violation);
        // hide when a specific scenario is picked (it'd be redundant).
        const showScen = scen.value === '__all__';
        pageRows.forEach(p => {
          const s = p.slack;
          const cls = s === undefined ? '' : (s < 0 ? 'neg' : 'pos');
          const typeTag = p.type ? ` <span class="ttag">${p.type}</span>` : '';
          const scenTag = (showScen && p.scenario)
            ? ` <span class="scentag" title="${p.scenario}">${_scenAbbrev(p.scenario)}</span>`
            : '';
          // Front-elide hierarchical names so the leaf stays visible inside
          // the narrow subrow. Full names live in the row's title tooltip.
          const shortStart = elideHier(p.start || '?', 14);
          const shortEnd   = elideHier(p.end   || '?', 14);
          const fullTip    = `${p.start || '?'}\n→ ${p.end || '?'}` +
                             (p.scenario ? `\nscenario: ${p.scenario}` : '');
          html += `<tr data-pi="${g.violators.indexOf(p)}" title="${fullTip.replace(/"/g,'&quot;')}">` +
                  `<td>${p._rank}</td>` +
                  `<td class="slack ${cls}">${s === undefined ? '—' : s.toFixed(3)}${typeTag}${scenTag}` +
                    `<div class="tsub">${shortStart} &rarr; ${shortEnd}</div></td>` +
                  `<td class="mono">${(p.instances || []).length}</td></tr>`;
        });
        html += '</tbody></table>';
        list.innerHTML = html;
        list.querySelectorAll('tr[data-pi]').forEach(tr => {
          tr.addEventListener('click', ev => {
            list.querySelectorAll('tr').forEach(x => x.classList.remove('active'));
            tr.classList.add('active');
            const pi = parseInt(tr.dataset.pi, 10);
            selectedPath = g.violators[pi];
            selectedPath._groupName = g.name;
            fp.setPath(selectedPath);
            detailBtn.disabled = false;
            detailBtn.style.opacity = 1;
            // Double-click a row = open detailed view directly.
            if (ev.detail === 2) openDetail();
          });
        });
      }

      // ── Detailed-path modal ────────────────────────────────────────
      // Renders the exact `report_timing` text captured for the path.
      // In a real STA integration the flow drops the PT/Tempus text into
      // path.report; the client just displays it verbatim.
      function openDetail() {
        if (!selectedPath) return;
        const p = selectedPath;
        const s = p.slack;
        const slackStr = s === undefined ? '—' : s.toFixed(3);
        const cls = s === undefined ? '' : (s < 0 ? 'neg' : 'pos');
        // Modal is wider than the panel so we can afford a longer elide,
        // but still cap so start/end don't dominate.
        const scenPiece = p.scenario ? `  ·  scenario <b>${p.scenario}</b>` : '';
        modalSub.innerHTML =
          `<b>${p._groupName || '?'}</b>${scenPiece}  ·  ` +
          `type <b>${p.type || '—'}</b>  ·  ` +
          `slack <span class="slack ${cls}">${slackStr} ns</span>  ·  ` +
          `hops <b>${(p.instances || []).length}</b>  ·  ` +
          `<span title="${(p.start||'').replace(/"/g,'&quot;')}">` +
          `  ${elideHier(p.start || '?', 40)}</span> &rarr; ` +
          `<span title="${(p.end||'').replace(/"/g,'&quot;')}">` +
          `  ${elideHier(p.end || '?', 40)}</span>`;

        const report = p.report;
        if (report && report.trim().length) {
          const esc = report
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
          modalBody.innerHTML =
            `<div class="rpt-toolbar">` +
            `  <button id="rpt-copy" class="rpt-btn">copy</button>` +
            `  <span class="rpt-hint">verbatim report_timing output</span>` +
            `</div>` +
            `<pre class="rpt">${esc}</pre>`;
          const copyBtn = document.getElementById('rpt-copy');
          copyBtn.addEventListener('click', () => {
            navigator.clipboard.writeText(report).then(() => {
              copyBtn.textContent = 'copied';
              setTimeout(() => { copyBtn.textContent = 'copy'; }, 1400);
            });
          });
        } else {
          modalBody.innerHTML =
            `<div style="padding:20px;color:var(--muted);font-size:12px">` +
            `No report_timing text captured for this path. The STA flow ` +
            `did not attach a raw report to the timing snapshot.` +
            `</div>`;
        }
        modal.style.display = 'flex';
      }
      function closeDetail() { modal.style.display = 'none'; }
      detailBtn.addEventListener('click', openDetail);
      modalClose.addEventListener('click', closeDetail);
      modal.addEventListener('click', ev => {
        if (ev.target === modal) closeDetail();      // backdrop click
      });
      document.addEventListener('keydown', ev => {
        if (ev.key === 'Escape' && modal.style.display === 'flex') closeDetail();
      });

      grp.addEventListener('change', () => {
        state.page = 0;
        // The focus path lives inside the OLD group's violators; drop it
        // so the pink FOCUS banner and highlighted flight lines don't
        // linger from another clock.
        selectedPath = null;
        fp.setPath(null);
        detailBtn.disabled = true;
        detailBtn.style.opacity = 0.5;
        render();
      });
      scen.addEventListener('change', () => {
        // Scenario changes the underlying violator set — recompute the
        // failing-groups list, reset focus + bulk selections, and rerender.
        rebuildGroups();
        state.page = 0;
        state.lastGroup = null;          // force group re-frame on next render
        selectedPath = null;
        fp.setPath(null);
        selGroupBtn.classList.remove('active');
        selMatchesBtn.classList.remove('active');
        fp.clearPaths();
        detailBtn.disabled = true;
        detailBtn.style.opacity = 0.5;
        if (failingGroups.length === 0) {
          // The picked scenario has zero violations across the whole
          // design — surface that clearly instead of an empty list.
          list.innerHTML =
            '<div style="padding:20px;color:var(--muted);' +
            'font-size:12px;text-align:center">' +
            `no failing paths in scenario <b>${scen.value}</b></div>`;
          cnt.textContent = 'clean';
          pageLbl.textContent = '0 / 0  (0)';
          selGroupN.textContent = '0';
          selMatchN.textContent = '0';
          return;
        }
        render();
      });
      typ.addEventListener('change', () => { state.page = 0; render(); });
      search.addEventListener('input', () => { state.page = 0; render(); });
      scope.addEventListener('change', () => { state.page = 0; render(); });
      function setMode(mode) {
        modeInc.classList.toggle('active', mode === 'include');
        modeExc.classList.toggle('active', mode === 'exclude');
        state.page = 0;
        render();
      }
      modeInc.addEventListener('click', () => setMode('include'));
      modeExc.addEventListener('click', () => setMode('exclude'));
      prevBtn.addEventListener('click', () => { state.page--; render(); });
      nextBtn.addEventListener('click', () => { state.page++; render(); });
      clearBtn.addEventListener('click', () => {
        list.querySelectorAll('tr').forEach(x => x.classList.remove('active'));
        selGroupBtn.classList.remove('active');
        selMatchesBtn.classList.remove('active');
        fp.clearPaths();
        selectedPath = null;
        detailBtn.disabled = true;
        detailBtn.style.opacity = 0.5;
      });

      // Bulk selection — the two buttons are mutually exclusive with each
      // other, but do NOT clear the focus path (user can still click a row
      // to highlight one within the bulk cloud).
      selGroupBtn.addEventListener('click', () => {
        const g = currentGroup();
        if (!g) return;
        fp.setPaths(g.violators);
        selGroupBtn.classList.add('active');
        selMatchesBtn.classList.remove('active');
      });
      selMatchesBtn.addEventListener('click', () => {
        const rows = filteredRows();
        fp.setPaths(rows);
        selMatchesBtn.classList.add('active');
        selGroupBtn.classList.remove('active');
      });

      render();
    }

    // Convert `#rrggbb` (or `#rgb`) to `rgba(r,g,b,a)` for the highlight fill.
    function _rgba(hex, a) {
      let h = (hex || '').replace('#', '');
      if (h.length === 3) h = h.split('').map(c => c+c).join('');
      const n = parseInt(h, 16);
      if (isNaN(n)) return 'rgba(249,115,22,'+a+')';
      const r = (n >> 16) & 0xff, g = (n >> 8) & 0xff, bl = n & 0xff;
      return `rgba(${r},${g},${bl},${a})`;
    }

    function setupFloorplan(fp, canvas, status, tip) {
      const b = fp.boundary || {};
      const cells = fp.cells || [];
      const rows = fp.rows || [];
      const macros = fp.macros || {};
      const density = fp.density || {};
      const units = fp.units || 1000;                     // DBUs per micron
      const totalCells = fp.total_cells || cells.length;
      if (!b.x2 || b.x2 === b.x1) {
        status.textContent = 'no DIEAREA in the captured DEF';
        return;
      }
      const dW = b.x2 - b.x1, dH = b.y2 - b.y1;

      // Row band height = min positive delta between successive row Y coords.
      const rowYs = rows.map(r => r.y).sort((a,b)=>a-b);
      let rowStep = 0;
      for (let i = 1; i < rowYs.length; i++) {
        const d = rowYs[i] - rowYs[i-1];
        if (d > 0 && (rowStep === 0 || d < rowStep)) rowStep = d;
      }
      if (!rowStep && rows.length) rowStep = 2000;

      // Precompute density heatmap once — a canvas-sized offscreen buffer
      // colored by cell count. Drawing this every frame is a single drawImage.
      let densityImg = null;
      if (density && density.cols && density.rows && density.counts) {
        const off = document.createElement('canvas');
        off.width = density.cols;
        off.height = density.rows;
        const octx = off.getContext('2d');
        const img = octx.createImageData(off.width, off.height);
        const maxC = Math.max(1, density.max);
        for (let i = 0; i < density.counts.length; i++) {
          const c = density.counts[i];
          // gamma-corrected intensity so sparse regions are still visible
          const t = c === 0 ? 0 : Math.pow(c / maxC, 0.55);
          const px = (density.rows - 1 - Math.floor(i / density.cols))
                     * density.cols + (i % density.cols);
          const p = px * 4;
          if (c === 0) {
            img.data[p]=11; img.data[p+1]=18; img.data[p+2]=32; img.data[p+3]=0;
          } else {
            // green → yellow → red gradient (tools' standard heat scale)
            const r = Math.min(255, Math.round(255 * Math.max(0, (t - 0.5) * 2)));
            const g = Math.min(255, Math.round(255 * (1 - Math.max(0, (t - 0.5) * 2)) * (t > 0.05 ? 1 : t * 20)));
            const bl = Math.round(60 * (1 - t));
            img.data[p] = r; img.data[p+1] = g;
            img.data[p+2] = bl; img.data[p+3] = 220;
          }
        }
        octx.putImageData(img, 0, 0);
        densityImg = off;
      }

      // ── Sizing: fluid canvas that fills the container (fit-to-window).
      // We size the backing buffer at devicePixelRatio for sharp rendering,
      // and re-fit on any container resize.
      const wrap = document.getElementById('fp-wrap');
      const pad = 12;
      const state = {
        cssW: 0, cssH: 0,
        scale: 1, panX: 0, panY: 0,
        fitS: 1,
        selected: null,
        searchQuery: '',
        searchScope: 'both',        // 'both' | 'instance' | 'macro'
        highlightColor: '#f97316',  // orange-500
        matches: [],                // list of cells matching the query
        activePath: null,           // focus path — drawn on top with full detail
        activePaths: [],            // bulk selection — thin lines, no arrows
      };
      function fitScale() {
        return Math.min((state.cssW - 2*pad) / dW,
                        (state.cssH - 2*pad) / dH);
      }
      function toPx(dbuX, dbuY) {
        const s = state.scale;
        const originX = pad + (state.cssW - 2*pad - s*dW) / 2 - s*b.x1 + state.panX;
        const originY = pad + (state.cssH - 2*pad - s*dH) / 2 + s*b.y2 + state.panY;
        return [originX + s*dbuX, originY - s*dbuY];
      }
      function fromPx(px, py) {
        const s = state.scale;
        const originX = pad + (state.cssW - 2*pad - s*dW) / 2 - s*b.x1 + state.panX;
        const originY = pad + (state.cssH - 2*pad - s*dH) / 2 + s*b.y2 + state.panY;
        return [(px - originX) / s, (originY - py) / s];
      }
      function cellHeight(c) {
        const m = macros[c.macro];
        const lefH = m && m.h ? m.h * units : 0;
        return lefH >= rowStep ? lefH : rowStep;
      }
      function cellWidth(c) {
        const m = macros[c.macro];
        return m && m.w ? m.w * units : 100;
      }

      const ctx = canvas.getContext('2d');
      let raf = null;
      function scheduleRender() {
        if (raf) return;
        raf = requestAnimationFrame(() => { raf = null; render(); });
      }
      function render() {
        const cw = state.cssW, ch = state.cssH;
        ctx.clearRect(0, 0, cw, ch);

        // Die outline
        const [dx1, dy1] = toPx(b.x1, b.y2);
        const [dx2, dy2] = toPx(b.x2, b.y1);

        // ── LOD choice ──────────────────────────────────────────────
        // Effective cell pixel size at current zoom. Below ~1.5px we draw
        // the precomputed density heatmap (constant cost) instead of
        // iterating cells (would fillRect() 5M rectangles).
        const effCellPx = state.scale * rowStep;
        const useDensity = effCellPx < 1.5 && densityImg;

        if (useDensity) {
          ctx.save();
          ctx.imageSmoothingEnabled = true;
          ctx.drawImage(densityImg, dx1, dy1, dx2 - dx1, dy2 - dy1);
          ctx.restore();
        } else {
          // Row bands
          ctx.fillStyle = 'rgba(148,163,184,0.10)';
          ctx.strokeStyle = 'rgba(71,85,105,0.7)';
          ctx.lineWidth = 0.3;
          rows.forEach(r => {
            const w = r.count_x * r.step_x || dW;
            const [rx0, ry1] = toPx(r.x, r.y + rowStep);
            const [rx1, ry0] = toPx(r.x + w, r.y);
            if (rx1 < 0 || rx0 > cw || ry0 < 0 || ry1 > ch) return;
            ctx.fillRect(rx0, ry1, rx1 - rx0, ry0 - ry1);
            ctx.strokeRect(rx0, ry1, rx1 - rx0, ry0 - ry1);
          });

          // Viewport-culled cells. Convert canvas corners to world space
          // and only iterate cells whose bbox intersects that rect.
          const [wxL, wyT] = fromPx(0, 0);
          const [wxR, wyB] = fromPx(cw, ch);
          const wx1 = Math.min(wxL, wxR), wx2 = Math.max(wxL, wxR);
          const wy1 = Math.min(wyT, wyB), wy2 = Math.max(wyT, wyB);
          // Classify cell as "hard macro" (memory / block) when its LEF
          // height is more than 1.5 × the row band. Draw macros in blue
          // and on a second pass so they always sit on top of the
          // stdcell sea and are visible even at fit-zoom.
          function isMacro(c) {
            const m = macros[c.macro];
            return !!(m && m.h && m.h * units >= rowStep * 1.5);
          }
          const macroList = [];
          ctx.fillStyle   = 'rgba(34,197,94,0.6)';
          ctx.strokeStyle = 'rgba(34,197,94,0.9)';
          ctx.lineWidth   = 0.3;
          let drawn = 0, dots = 0, macroCount = 0;
          for (let i = 0; i < cells.length; i++) {
            const c = cells[i];
            const w = cellWidth(c), h = cellHeight(c);
            if (c.x > wx2 || c.x + w < wx1 || c.y > wy2 || c.y + h < wy1) continue;
            if (isMacro(c)) { macroList.push(c); continue; }
            const [px, py] = toPx(c.x, c.y + h);
            const pw = state.scale * w, ph = state.scale * h;
            ctx.fillRect(px, py, Math.max(pw, 0.5), Math.max(ph, 0.5));
            if (pw > 3 && ph > 3) ctx.strokeRect(px, py, pw, ph);
            drawn++;
            if (!macros[c.macro] || !macros[c.macro].w) dots++;
            if (drawn > 500000) break;
          }

          // Macros — blue, always drawn on top of stdcells with a visible
          // outline + macro name label when they fit on screen.
          ctx.font = '11px Menlo, monospace';
          for (const c of macroList) {
            const w = cellWidth(c), h = cellHeight(c);
            const [px, py] = toPx(c.x, c.y + h);
            const pw = state.scale * w, ph = state.scale * h;
            if (c === state.selected) {
              ctx.fillStyle = 'rgba(250,204,21,0.9)';
              ctx.strokeStyle = '#fbbf24';
              ctx.lineWidth = 2;
            } else {
              ctx.fillStyle = 'rgba(59,130,246,0.55)';    // blue-500
              ctx.strokeStyle = 'rgba(96,165,250,0.95)';
              ctx.lineWidth = 1.2;
            }
            ctx.fillRect(px, py, pw, ph);
            ctx.strokeRect(px, py, pw, ph);
            if (pw > 60 && ph > 20) {
              ctx.fillStyle = '#e0f2fe';
              ctx.fillText(c.name, px + 4, py + 14);
            }
            macroCount++;
          }

          state._lastDrawn = drawn;
          state._lastMacros = macroCount;
          state._lastDots = dots;
        }

        // ── Highlight pass — matches from the search box, drawn on top of
        // everything with the user-picked color. Works in both density and
        // cells modes (matches always visible regardless of zoom).
        if (state.matches && state.matches.length) {
          const [wxL, wyT] = fromPx(0, 0);
          const [wxR, wyB] = fromPx(cw, ch);
          const wx1 = Math.min(wxL, wxR), wx2 = Math.max(wxL, wxR);
          const wy1 = Math.min(wyT, wyB), wy2 = Math.max(wyT, wyB);
          const col = state.highlightColor || '#f97316';
          ctx.strokeStyle = col;
          ctx.fillStyle = _rgba(col, 0.55);
          let visibleMatches = 0;
          for (let i = 0; i < state.matches.length; i++) {
            const c = state.matches[i];
            const w = cellWidth(c), h = cellHeight(c);
            if (c.x > wx2 || c.x + w < wx1 || c.y > wy2 || c.y + h < wy1) continue;
            const [px, py] = toPx(c.x, c.y + h);
            const pw = state.scale * w, ph = state.scale * h;
            // Guarantee minimum visibility even when zoomed way out.
            const drawW = Math.max(pw, 4);
            const drawH = Math.max(ph, 4);
            const drawX = px - (drawW - pw) / 2;
            const drawY = py - (drawH - ph) / 2;
            ctx.fillRect(drawX, drawY, drawW, drawH);
            ctx.lineWidth = 1.5;
            ctx.strokeRect(drawX, drawY, drawW, drawH);
            visibleMatches++;
            if (visibleMatches > 20000) break;   // draw cap for performance
          }
          state._lastHighlighted = visibleMatches;
        } else {
          state._lastHighlighted = 0;
        }

        // ── Bulk timing paths (multi-select) ────────────────────────
        // Thin translucent lines per hop, colored by segment. No boxes,
        // no arrows — just a cloud of routes so the manager can see where
        // the failing traffic concentrates. Focus path (if any) draws on
        // top with full detail.
        const SEG_LINE_BULK = {
          launch_clock:  'rgba(6,182,212,0.35)',
          clock:         'rgba(6,182,212,0.35)',
          data:          'rgba(236,72,153,0.35)',
          capture_clock: 'rgba(245,158,11,0.35)',
        };
        if (state.activePaths && state.activePaths.length) {
          ctx.lineWidth = 1;
          ctx.setLineDash([]);
          // Group segments by color and stroke once per color to cut
          // fillStyle/strokeStyle churn. Path counts can be 100+ per group.
          const bySeg = {launch_clock: [], data: [], capture_clock: [], clock: []};
          for (const p of state.activePaths) {
            const insts = p.instances || [];
            for (let i = 1; i < insts.length; i++) {
              const from = insts[i-1];
              const to   = insts[i];
              const [x1, y1] = toPx(from.x + 200, from.y + rowStep/2);
              const [x2, y2] = toPx(to.x   + 200, to.y   + rowStep/2);
              (bySeg[from.seg || 'data'] || bySeg.data).push([x1, y1, x2, y2]);
            }
          }
          for (const seg of ['launch_clock','clock','capture_clock','data']) {
            const lines = bySeg[seg];
            if (!lines.length) continue;
            ctx.strokeStyle = SEG_LINE_BULK[seg] || SEG_LINE_BULK.data;
            ctx.beginPath();
            for (const [x1, y1, x2, y2] of lines) {
              ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
            }
            ctx.stroke();
          }
        }

        // ── Timing path pass ─────────────────────────────────────────
        // Three-segment rendering: launch clock (cyan) → data path (pink)
        // → capture clock (amber). Each hop-to-hop segment is drawn in the
        // *source* hop's color, with an arrowhead at the destination end
        // so direction is unambiguous.
        if (state.activePath && state.activePath.instances &&
            state.activePath.instances.length) {
          const insts = state.activePath.instances;
          // Color table per segment. 'clock' is the legacy value from
          // pre-split payloads — treat it as launch clock.
          const SEG_FILL = {
            launch_clock:  'rgba(6,182,212,0.55)',    // cyan-500 @ 55%
            clock:         'rgba(6,182,212,0.55)',
            data:          'rgba(236,72,153,0.55)',   // pink-500 @ 55%
            capture_clock: 'rgba(245,158,11,0.55)',   // amber-500 @ 55%
          };
          const SEG_LINE = {
            launch_clock:  '#06b6d4',
            clock:         '#06b6d4',
            data:          '#f472b6',
            capture_clock: '#f59e0b',
          };
          const centers = [];
          // Pass 1 — segment-colored highlight boxes.
          for (let i = 0; i < insts.length; i++) {
            const inst = insts[i];
            const seg  = inst.seg || 'data';
            const w = 400, h = rowStep;
            const [px, py] = toPx(inst.x, inst.y + h);
            const pw = state.scale * w, ph = state.scale * h;
            const drawW = Math.max(pw, 10);
            const drawH = Math.max(ph, 8);
            const drawX = px - (drawW - pw) / 2;
            const drawY = py - (drawH - ph) / 2;
            ctx.fillStyle   = SEG_FILL[seg]  || SEG_FILL.data;
            ctx.strokeStyle = SEG_LINE[seg]  || SEG_LINE.data;
            ctx.lineWidth = 1.5;
            ctx.fillRect(drawX, drawY, drawW, drawH);
            ctx.strokeRect(drawX, drawY, drawW, drawH);
            centers.push([px + pw/2, py + ph/2]);
          }
          // Pass 2 — directional segments with arrowheads at each hop.
          for (let i = 1; i < centers.length; i++) {
            const [x1, y1] = centers[i-1];
            const [x2, y2] = centers[i];
            const seg = insts[i-1].seg || 'data';
            const color = SEG_LINE[seg] || SEG_LINE.data;
            // Line: dashed for clock, solid for data — matches SDF display.
            ctx.strokeStyle = color;
            ctx.lineWidth = 2;
            ctx.setLineDash(seg === 'data' ? [] : [5, 3]);
            ctx.beginPath();
            ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
            ctx.setLineDash([]);
            // Arrowhead — filled triangle at the destination end, offset
            // slightly inside the destination box.
            const dx = x2 - x1, dy = y2 - y1;
            const len = Math.hypot(dx, dy);
            if (len > 4) {
              const ux = dx / len, uy = dy / len;
              // Back off from the exact center so the arrow tip sits at
              // the edge of the destination box.
              const back = Math.min(len * 0.35, 12);
              const tipX = x2 - ux * back;
              const tipY = y2 - uy * back;
              const size = 7;                     // arrowhead length
              const wideX = -uy, wideY = ux;      // perpendicular
              ctx.fillStyle = color;
              ctx.beginPath();
              ctx.moveTo(tipX, tipY);
              ctx.lineTo(tipX - ux * size + wideX * (size*0.55),
                         tipY - uy * size + wideY * (size*0.55));
              ctx.lineTo(tipX - ux * size - wideX * (size*0.55),
                         tipY - uy * size - wideY * (size*0.55));
              ctx.closePath();
              ctx.fill();
            }
          }
          // Pass 3 — endpoint markers. Launch endpoint (red) and capture
          // endpoint (red) so start/end pop even on long paths.
          if (centers.length) {
            const drawEnd = ([cx, cy], color, r) => {
              ctx.beginPath();
              ctx.fillStyle   = '#fff';
              ctx.strokeStyle = color;
              ctx.lineWidth = 2;
              ctx.arc(cx, cy, r, 0, Math.PI*2);
              ctx.fill(); ctx.stroke();
            };
            drawEnd(centers[0], '#dc2626', 6);
            if (centers.length > 1)
              drawEnd(centers[centers.length-1], '#dc2626', 6);
          }
        }

        // Die area outline (always on top)
        ctx.strokeStyle = '#f59e0b';
        ctx.lineWidth = 1.5;
        ctx.strokeRect(dx1, dy1, dx2 - dx1, dy2 - dy1);

        // Timing path label(s) — stacked banner: bulk count first, then
        // the focus path detail below it.
        const banners = [];
        if (state.activePaths && state.activePaths.length) {
          banners.push({
            text: `SHOWING ${state.activePaths.length} PATHS ` +
                  `(${state.activePaths.reduce((n,p)=>n+((p.instances||[]).length-1),0)} hops)`,
            fill: 'rgba(30,58,138,0.90)',                // blue-900
            border: '#93c5fd',
            txt:    '#eff6ff',
          });
        }
        if (state.activePath) {
          const p = state.activePath;
          const s = p.slack;
          const slackStr = s === undefined ? '—' : s.toFixed(3) + ' ns';
          // Hierarchical names blow up the banner — elide start/end at ~28
          // chars each so they never push the label off-screen.
          const st = elideHier(p.start||'?', 28);
          const en = elideHier(p.end  ||'?', 28);
          const scenPart = p.scenario ? `   ${p.scenario}` : '';
          banners.push({
            text: `FOCUS  ${st} → ${en}   ` +
                  `slack ${slackStr}   ${(p.instances||[]).length} hops   ` +
                  `[${p.type||'—'}]${scenPart}`,
            fill: 'rgba(190,24,93,0.95)',                // pink-700
            border: '#f9a8d4',
            txt:    '#fdf2f8',
          });
        }
        ctx.font = '13px Menlo, monospace';
        banners.forEach((bn, i) => {
          const y = 6 + i * 24;
          const tw = ctx.measureText(bn.text).width + 12;
          ctx.fillStyle   = bn.fill;
          ctx.fillRect(6, y, tw, 20);
          ctx.strokeStyle = bn.border;
          ctx.strokeRect(6, y, tw, 20);
          ctx.fillStyle   = bn.txt;
          ctx.fillText(bn.text, 12, y + 14);
        });

        // Selection label — elide hierarchical instance name so it never
        // pushes the coordinates off-screen.
        if (state.selected) {
          const c = state.selected;
          const nameShort = elideHier(c.name, 40);
          const label =
            `${nameShort}  (${c.macro})   @ ${(c.x/units).toFixed(2)}, ${(c.y/units).toFixed(2)} µm   ${c.orient||''}`;
          ctx.font = '13px Menlo, monospace';
          const tw = ctx.measureText(label).width + 12;
          ctx.fillStyle = 'rgba(30,41,59,0.95)';
          ctx.fillRect(6, ch - 26, tw, 20);
          ctx.strokeStyle = '#fbbf24';
          ctx.strokeRect(6, ch - 26, tw, 20);
          ctx.fillStyle = '#fef3c7';
          ctx.fillText(label, 12, ch - 12);
        }

        // Status
        const zoomPct = Math.round(100 * state.scale / state.fitS);
        const macroPart = (state._lastMacros||0) > 0
            ? ` (+${state._lastMacros} macros)` : '';
        const mode = useDensity
            ? 'density'
            : `cells (drew ${(state._lastDrawn||0).toLocaleString()}${macroPart})`;
        const dsNote = fp.downsampled ?
            `  ·  cells layer downsampled from ${totalCells.toLocaleString()} to ${cells.length.toLocaleString()}`
          : '';
        status.textContent =
          `${totalCells.toLocaleString()} total cells  ·  ${rows.length.toLocaleString()} rows` +
          `  ·  die ${(dW/units).toFixed(1)} × ${(dH/units).toFixed(1)} µm` +
          `  ·  zoom ${zoomPct}%  ·  ${mode}` + dsNote;
      }

      // ── Resize: fit canvas to its container. ResizeObserver fires on
      // window resize + pane resize (e.g. when the browser zooms).
      function resize() {
        const rect = wrap.getBoundingClientRect();
        const cssW = Math.max(200, rect.width - 16);       // minus padding
        const cssH = Math.max(200, canvas.clientHeight || rect.height * 0.7);
        state.cssW = cssW; state.cssH = cssH;
        const dpr = window.devicePixelRatio || 1;
        canvas.width  = Math.round(cssW * dpr);
        canvas.height = Math.round(cssH * dpr);
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        const newFit = fitScale();
        // On first resize (state.scale===1) or if user hasn't zoomed, snap to fit.
        if (!state._userZoom) {
          state.scale = newFit;
          state.panX = state.panY = 0;
        }
        state.fitS = newFit;
        scheduleRender();
      }
      new ResizeObserver(resize).observe(wrap);
      window.addEventListener('resize', resize);
      resize();

      // ── Zoom + pan ────────────────────────────────────────────────
      function zoomAt(px, py, factor) {
        const [wx, wy] = fromPx(px, py);
        state.scale *= factor;
        const [nx, ny] = toPx(wx, wy);
        state.panX += px - nx;
        state.panY += py - ny;
        state._userZoom = true;
        scheduleRender();
      }
      document.getElementById('fp-zin').onclick  = () => zoomAt(state.cssW/2, state.cssH/2, 1.4);
      document.getElementById('fp-zout').onclick = () => zoomAt(state.cssW/2, state.cssH/2, 1/1.4);
      document.getElementById('fp-fit').onclick  = () => {
        state.scale = state.fitS; state.panX = 0; state.panY = 0;
        state._userZoom = false;
        scheduleRender();
      };
      canvas.addEventListener('wheel', e => {
        e.preventDefault();
        const r = canvas.getBoundingClientRect();
        const px = (e.clientX - r.left) * state.cssW / r.width;
        const py = (e.clientY - r.top ) * state.cssH / r.height;
        zoomAt(px, py, e.deltaY < 0 ? 1.15 : 1/1.15);
      }, { passive: false });

      let dragging = false, lastX = 0, lastY = 0, movedPx = 0;
      canvas.addEventListener('mousedown', e => {
        dragging = true; movedPx = 0;
        lastX = e.clientX; lastY = e.clientY;
        canvas.style.cursor = 'grabbing';
      });
      window.addEventListener('mousemove', e => {
        if (!dragging) return;
        const r = canvas.getBoundingClientRect();
        const dx = (e.clientX - lastX) * state.cssW / r.width;
        const dy = (e.clientY - lastY) * state.cssH / r.height;
        state.panX += dx; state.panY += dy;
        movedPx += Math.abs(dx) + Math.abs(dy);
        lastX = e.clientX; lastY = e.clientY;
        state._userZoom = true;
        scheduleRender();
      });
      window.addEventListener('mouseup', () => {
        dragging = false;
        canvas.style.cursor = 'grab';
      });

      // ── Search + highlight ─────────────────────────────────────────
      const inpSearch = document.getElementById('fp-search');
      const selScope  = document.getElementById('fp-scope');
      const inpColor  = document.getElementById('fp-color');
      const btnClear  = document.getElementById('fp-clear');
      const btnZoomTo = document.getElementById('fp-zoomto');
      const spanCount = document.getElementById('fp-count');

      function updateMatches() {
        const q = state.searchQuery.trim().toLowerCase();
        if (!q) {
          state.matches = [];
          spanCount.textContent = '';
          scheduleRender();
          return;
        }
        // Support simple `*` glob (case-insensitive substring by default,
        // or anchored pattern when `*` or `?` present).
        let re;
        if (q.includes('*') || q.includes('?')) {
          const pat = '^' + q.replace(/[.+^${}()|[\\]\\\\]/g, '\\\\$&')
                              .replace(/\\*/g, '.*').replace(/\\?/g, '.') + '$';
          try { re = new RegExp(pat, 'i'); } catch (_) { re = null; }
        }
        const scope = state.searchScope;
        const out = [];
        for (let i = 0; i < cells.length && out.length < 100000; i++) {
          const c = cells[i];
          const nm = (c.name  || '').toLowerCase();
          const mc = (c.macro || '').toLowerCase();
          let hit;
          if (re) {
            hit = (scope !== 'macro' && re.test(nm)) ||
                  (scope !== 'instance' && re.test(mc));
          } else {
            hit = (scope !== 'macro' && nm.includes(q)) ||
                  (scope !== 'instance' && mc.includes(q));
          }
          if (hit) out.push(c);
        }
        state.matches = out;
        spanCount.textContent =
          out.length === 0 ? 'no matches'
          : out.length === 100000 ? '≥100,000 matches (refine)'
          : `${out.length.toLocaleString()} match${out.length===1?'':'es'}`;
        scheduleRender();
      }

      let searchTimer = null;
      inpSearch.addEventListener('input', e => {
        state.searchQuery = e.target.value;
        clearTimeout(searchTimer);
        searchTimer = setTimeout(updateMatches, 120);
      });
      inpSearch.addEventListener('keydown', e => {
        if (e.key === 'Enter') { clearTimeout(searchTimer); updateMatches(); }
      });
      selScope.addEventListener('change', e => {
        state.searchScope = e.target.value; updateMatches();
      });
      inpColor.addEventListener('input', e => {
        state.highlightColor = e.target.value; scheduleRender();
      });
      btnClear.addEventListener('click', () => {
        inpSearch.value = ''; state.searchQuery = ''; state.matches = [];
        spanCount.textContent = ''; scheduleRender();
      });
      btnZoomTo.addEventListener('click', () => {
        if (!state.matches.length) return;
        // Compute the bbox of matches, zoom+pan so it fills the canvas.
        let mnX =  Infinity, mnY =  Infinity;
        let mxX = -Infinity, mxY = -Infinity;
        for (const c of state.matches) {
          const w = cellWidth(c), h = cellHeight(c);
          if (c.x < mnX) mnX = c.x;
          if (c.y < mnY) mnY = c.y;
          if (c.x + w > mxX) mxX = c.x + w;
          if (c.y + h > mxY) mxY = c.y + h;
        }
        // Add a 15% margin so highlights aren't glued to the edge.
        const mgn = 0.15;
        const bw = mxX - mnX, bh = mxY - mnY;
        const eW = bw * (1 + 2*mgn), eH = bh * (1 + 2*mgn);
        const s = Math.min((state.cssW - 2*pad) / eW,
                           (state.cssH - 2*pad) / eH);
        state.scale = s;
        state._userZoom = true;
        // Center the bbox in the canvas.
        const cx = (mnX + mxX) / 2, cy = (mnY + mxY) / 2;
        const dieCx = (b.x1 + b.x2) / 2, dieCy = (b.y1 + b.y2) / 2;
        state.panX = -s * (cx - dieCx);
        state.panY =  s * (cy - dieCy);
        scheduleRender();
      });

      // ── Click-to-select — viewport-culled + effective-size gate so we
      // don't scan 5M cells at density-mode zoom where individual cells
      // aren't visible anyway.
      canvas.addEventListener('click', e => {
        if (movedPx > 5) return;
        if (state.scale * rowStep < 1.5) return;           // density mode: no cell hits
        const r = canvas.getBoundingClientRect();
        const px = (e.clientX - r.left) * state.cssW / r.width;
        const py = (e.clientY - r.top ) * state.cssH / r.height;
        const [wx, wy] = fromPx(px, py);
        let found = null;
        for (let i = cells.length - 1; i >= 0; i--) {
          const c = cells[i];
          const w = cellWidth(c), h = cellHeight(c);
          if (wx >= c.x && wx <= c.x + w && wy >= c.y && wy <= c.y + h) {
            found = c; break;
          }
        }
        state.selected = found;
        scheduleRender();
      });

      // Frame a set of paths — auto-zoom to fit their combined bbox.
      function frameToPaths(paths, marginPx) {
        let x1 =  Infinity, y1 =  Infinity;
        let x2 = -Infinity, y2 = -Infinity;
        let any = false;
        for (const p of paths) {
          for (const inst of (p.instances || [])) {
            any = true;
            if (inst.x < x1) x1 = inst.x;
            if (inst.y < y1) y1 = inst.y;
            if (inst.x > x2) x2 = inst.x;
            if (inst.y > y2) y2 = inst.y;
          }
        }
        if (!any) return;
        const bw = Math.max(x2 - x1, rowStep*4);
        const bh = Math.max(y2 - y1, rowStep*4);
        const m = marginPx || 60;
        const fitS = Math.min((state.cssW - 2*m) / bw,
                              (state.cssH - 2*m) / bh);
        state.scale = Math.min(fitS, state.fitS * 30);
        const cx = (x1 + x2) / 2, cy = (y1 + y2) / 2;
        const [px, py] = toPx(cx, cy);
        state.panX += state.cssW/2 - px;
        state.panY += state.cssH/2 - py;
        state._userZoom = true;
      }

      // Expose a tiny API for the timing debugger.
      return {
        setPath: function(p) {
          state.activePath = p;
          if (p && p.instances && p.instances.length) frameToPaths([p]);
          scheduleRender();
        },
        setPaths: function(arr, opts) {
          state.activePaths = Array.isArray(arr) ? arr : [];
          if (state.activePaths.length && !(opts && opts.skipFrame)) {
            frameToPaths(state.activePaths, 30);
          }
          scheduleRender();
        },
        clearPaths: function() {
          state.activePath  = null;
          state.activePaths = [];
          scheduleRender();
        }
      };
    }
  </script>
"""


def _render_tier_stub(project, title, hint='', variant='stub'):
    """Minimal 'coming soon' page used by PR1 route stubs.

    PR2/PR3 replace each _page_tier{2,3,4} with a real renderer. This
    helper keeps the chrome consistent so customers never see a bare
    text/plain stub during the rollout window.
    """
    variant_badge = {
        'stub':    '<span class="pill pill-info">PR1 skeleton</span>',
        'offline': '<span class="pill pill-warn">Daemon offline</span>',
    }.get(variant, '')
    return ''.join([
        '<!DOCTYPE html><html><head>',
        '<meta charset="utf-8">',
        f'<title>CBflow-SmartGrid — {html.escape(project)}</title>',
        _STYLE,
        '<style>',
        '  .pill{display:inline-block;padding:2px 8px;border-radius:3px;'
        '        font-size:11px;font-weight:700;letter-spacing:.03em;'
        '        text-transform:uppercase;vertical-align:middle;'
        '        margin-left:8px}',
        '  .pill-info{background:#ebebff;color:#1a1a9a}',
        '  .pill-warn{background:#fff3e0;color:#9a4500}',
        '  .stub-wrap{padding:36px 24px;max-width:760px;margin:0 auto}',
        '  .stub-wrap h1{font-size:22px;color:var(--text);margin:0 0 14px}',
        '  .stub-wrap p{color:var(--muted);line-height:1.5}',
        '  .stub-wrap .cta{margin-top:20px;padding:12px 16px;'
        '                 background:var(--accent-bg);'
        '                 border-left:3px solid var(--accent-ink);'
        '                 border-radius:3px;font-family:ui-monospace,'
        '                 "SF Mono",Menlo,Consolas,monospace;font-size:12px}',
        '</style>',
        '</head><body>',
        '<header class="bar">',
        '  <div class="brand">CBflow<span class="lite">-SmartGrid</span>'
        '       <span class="lite" style="margin-left:8px;color:#0000FF;'
        '             font-weight:700;">· SmartSoC</span></div>',
        f'  <div class="proj"><a href="/">{html.escape(project)}</a></div>',
        '</header>',
        '<div class="stub-wrap">',
        f'  <h1>{html.escape(title)}{variant_badge}</h1>',
        f'  <p>{html.escape(hint)}</p>' if hint else '',
        f'  <div class="cta">{html.escape(hint)}</div>' if variant == 'offline' else '',
        '</div>',
        '</body></html>',
    ])


def _render_discipline_cards(project):
    """Render discipline-cards HTML for the project landing page.

    Reads disciplines the project enables from master_projects.json (via
    tcl_config_parser.get_project_disciplines). Disciplines the project
    doesn't declare are omitted entirely — no empty cards, no greyed
    boxes. Each enabled discipline gets a card that either links to a
    running project-scoped daemon or shows the operator how to start one.

    Returns '' when the project isn't in master_projects.json (which
    happens for ad-hoc / testing projects) — the smartgrid still works,
    cards just aren't shown.
    """
    import sys as _sys, os as _os
    _utils = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
    _cmds = _os.path.join(_utils, 'commands')
    # tcl_config_parser imports core.paths — both _utils (for core/) and
    # _cmds (for tcl_config_parser.py) must be on sys.path. The daemon
    # already adds _cmds in its own init, but _utils (parent of core/) may
    # be missing.
    for _p in (_utils, _cmds):
        if _p not in _sys.path:
            _sys.path.insert(0, _p)
    try:
        from tcl_config_parser import (
            get_project_disciplines, get_project_enabled_flows,
        )
    except Exception as _e:
        _sys.stderr.write(
            f"discipline-cards: cannot import tcl_config_parser: "
            f"{type(_e).__name__}: {_e}\n")
        return ''
    try:
        disciplines = get_project_disciplines(project)
    except Exception as _e:
        _sys.stderr.write(
            f"discipline-cards: get_project_disciplines({project!r}) failed: "
            f"{type(_e).__name__}: {_e}\n")
        return ''
    if not disciplines:
        _sys.stderr.write(
            f"discipline-cards: {project!r} has no enabled disciplines\n")
        return ''

    # daemon_url_for lives in global/utils/dashboard/state_paths.py, but the
    # daemon already imported project_dashboard's state_paths module into
    # sys.modules under that bare name. Load the dashboard sibling via
    # importlib under a disambiguated name so neither module shadows the
    # other.
    daemon_url_for = None
    try:
        import importlib.util as _ilu
        _spec_path = _os.path.join(
            _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
            'dashboard', 'state_paths.py')
        if _os.path.isfile(_spec_path):
            _spec = _ilu.spec_from_file_location(
                '_cbflow_dashboard_state_paths', _spec_path)
            _mod = _ilu.module_from_spec(_spec)
            _spec.loader.exec_module(_mod)
            daemon_url_for = getattr(_mod, 'daemon_url_for', None)
    except Exception as _e:
        _sys.stderr.write(
            f"discipline-cards: could not load daemon_url_for: "
            f"{type(_e).__name__}: {_e}\n")
    if daemon_url_for is None:
        def daemon_url_for(project, discipline):  # noqa: ARG001
            return ''

    out = ['<section class="disc-cards">']
    for disc in disciplines:
        try:
            flow_count = len(get_project_enabled_flows(project, disc))
        except Exception:
            flow_count = 0
        url = daemon_url_for(project, disc)
        css = disc.lower()
        out.append(f'  <div class="disc-card {css}">')
        out.append('    <div class="disc-h">')
        out.append(f'      <div class="disc-badge">{html.escape(disc)}</div>')
        out.append('      <div>')
        out.append(f'        <div class="disc-name">{html.escape(disc)} Dashboard</div>')
        _plural = 'flow' if flow_count == 1 else 'flows'
        out.append(f'        <div class="disc-meta">{flow_count} {_plural} enabled for {html.escape(project)}</div>')
        out.append('      </div>')
        out.append('    </div>')
        if url:
            out.append(f'    <a class="disc-open" href="{html.escape(url, quote=True)}" '
                       f'target="_blank" rel="noopener">Open {html.escape(disc)} Dashboard →</a>')
        else:
            out.append('    <div class="disc-hint">daemon offline — start with: '
                       f'<code>cbflow run gui --project {html.escape(project)}</code> '
                       f'from a {html.escape(disc)} run</div>')
        out.append('  </div>')
    out.append('</section>')
    return '\n'.join(out)


# ─── Tier 1 — all-projects grid ──────────────────────────────────────────────
#
# The daemon is per-project, but Tier 1 shows every project from
# master_projects.json. For each project card we probe the sibling daemon
# (via state_paths.sibling_daemon_url) + the sibling tracker.db (read-only
# summary SELECT) to populate verdict counts + freshness. A short-TTL cache
# keeps hot-reloads from fanning out N × SQLite connects.

import time as _time
import threading as _threading
import sqlite3 as _sqlite3

_SIBLING_SUMMARY_CACHE = {}  # project -> (snapshot_dict, mtime, ts)
_SIBLING_SUMMARY_LOCK = _threading.Lock()
_SIBLING_SUMMARY_TTL = 5.0  # seconds


def _sibling_project_summary(project_name):
    """Return a dict of {run_count, pass, cond, blocked, unknown,
    latest_published_at} for `project_name`'s sibling tracker.db.
    Returns an empty dict when the DB doesn't exist. Caches 5s to avoid
    fan-out when the Tier 1 page is reloaded in a hot loop."""
    with _SIBLING_SUMMARY_LOCK:
        cached = _SIBLING_SUMMARY_CACHE.get(project_name)
    db_path = state_paths.sibling_tracker_db(project_name)
    if not db_path:
        return {}
    try:
        mtime = os.path.getmtime(db_path)
    except OSError:
        return {}
    now = _time.monotonic()
    if cached:
        snap, cached_mtime, cached_ts = cached
        if cached_mtime == mtime and (now - cached_ts) < _SIBLING_SUMMARY_TTL:
            return snap
    try:
        conn = _sqlite3.connect(f'file:{db_path}?mode=ro', uri=True)
    except _sqlite3.Error:
        return {}
    try:
        try:
            row = conn.execute("""
                SELECT COUNT(*) AS total,
                       SUM(verdict='PASS')        AS n_pass,
                       SUM(verdict='CONDITIONAL') AS n_cond,
                       SUM(verdict='BLOCKED')     AS n_blocked,
                       SUM(verdict='UNKNOWN' OR verdict IS NULL) AS n_unknown,
                       MAX(published_at)          AS latest
                FROM published_runs WHERE project=?
            """, (project_name,)).fetchone()
        except _sqlite3.OperationalError:
            return {}
    finally:
        conn.close()
    snap = {
        'run_count': int(row[0] or 0),
        'pass':      int(row[1] or 0),
        'cond':      int(row[2] or 0),
        'blocked':   int(row[3] or 0),
        'unknown':   int(row[4] or 0),
        'latest':    row[5] or '',
    }
    with _SIBLING_SUMMARY_LOCK:
        _SIBLING_SUMMARY_CACHE[project_name] = (snap, mtime, now)
    return snap


def _render_tier1(self_project, scope):
    """All-projects landing. `self_project` is the daemon's own project
    (used for the header link); `scope` is 'active' / 'archived' / 'all'."""
    try:
        import sys as _sys, os as _os
        _utils = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
        _cmds = _os.path.join(_utils, 'commands')
        for _p in (_utils, _cmds):
            if _p not in _sys.path:
                _sys.path.insert(0, _p)
        from tcl_config_parser import (
            _load_master_projects, get_project_disciplines,
        )
        data = _load_master_projects()
    except Exception as e:
        return _render_tier_stub(
            self_project,
            'Tier 1 — could not load master_projects.json',
            hint=str(e), variant='offline')
    all_projects = list((data.get('projects') or {}).values())

    def _status_of(entry):
        return (entry.get('status') or 'active').lower()

    counts = {'active': 0, 'archived': 0, 'all': len(all_projects)}
    for p in all_projects:
        s = _status_of(p)
        if s == 'active':   counts['active'] += 1
        if s == 'archived': counts['archived'] += 1

    if scope == 'all':
        visible = all_projects
    else:
        visible = [p for p in all_projects if _status_of(p) == scope]

    # Sort — active-first, then by nearest tapeout_date ascending
    def _sort_key(p):
        s = _status_of(p)
        order = {'active': 0, 'paused': 1, 'archived': 2}.get(s, 3)
        return (order, p.get('tapeout_date') or '9999-99-99', p.get('name'))
    visible.sort(key=_sort_key)

    cards_html = []
    for entry in visible:
        pname = entry.get('name') or ''
        status = _status_of(entry)
        tech = entry.get('technology') or '—'
        tapeout = entry.get('tapeout_date') or ''
        tapeout_str, tapeout_weeks = _tapeout_info_safe(tapeout)
        chip_lead = entry.get('chip_lead') or '—'
        description = entry.get('description') or ''
        try:
            discs = get_project_disciplines(pname)
        except Exception:
            discs = []
        summary = _sibling_project_summary(pname)
        pass_n = summary.get('pass', 0)
        cond_n = summary.get('cond', 0)
        block_n = summary.get('blocked', 0)
        unk_n = summary.get('unknown', 0)
        total_n = summary.get('run_count', 0)
        latest = summary.get('latest', '')
        daemon_url = state_paths.sibling_daemon_url(pname) if pname != self_project else '/'
        # Status pill styling
        pill_cls = {
            'active':   'pill-active',
            'archived': 'pill-archived',
            'paused':   'pill-paused',
        }.get(status, 'pill-active')
        card_disc_badges = ''.join(
            f'<span class="disc-chip disc-{d.lower()}">{html.escape(d)}</span>'
            for d in discs)
        verdict_mini = (
            '<span class="vdot vp" title="PASS">●</span>'
            f'<span class="vn">{pass_n}</span>'
            '<span class="vdot vc" title="CONDITIONAL">●</span>'
            f'<span class="vn">{cond_n}</span>'
            '<span class="vdot vb" title="BLOCKED">●</span>'
            f'<span class="vn">{block_n}</span>'
            '<span class="vdot vu" title="UNKNOWN">●</span>'
            f'<span class="vn">{unk_n}</span>'
        ) if total_n > 0 else '<span class="muted">No publishes yet</span>'
        href = f'/project/{html.escape(pname, quote=True)}'
        card_html = (
            f'<a class="proj-card" href="{href}" data-status="{status}">'
            f'  <div class="proj-head">'
            f'    <div class="proj-name">{html.escape(pname)}</div>'
            f'    <span class="status-pill {pill_cls}">{html.escape(status.upper())}</span>'
            f'  </div>'
            f'  <div class="proj-desc">{html.escape(description)}</div>'
            f'  <div class="proj-meta">'
            f'    <span class="proj-meta-key">Lead</span> '
            f'    <span class="proj-meta-val">{html.escape(chip_lead)}</span>'
            f'    <span class="proj-meta-dot">·</span>'
            f'    <span class="proj-meta-key">Tech</span> '
            f'    <span class="proj-meta-val">{html.escape(tech)}</span>'
            f'  </div>'
            f'  <div class="proj-meta">'
            f'    <span class="proj-meta-key">Tapeout</span> '
            f'    <span class="proj-meta-val">{html.escape(tapeout_str)}</span>'
            f'    <span class="proj-meta-dot">·</span>'
            f'    <span class="proj-meta-val">{html.escape(str(tapeout_weeks))} wks</span>'
            f'  </div>'
            f'  <div class="proj-discs">{card_disc_badges}</div>'
            f'  <div class="proj-verdicts">{verdict_mini}</div>'
            f'  <div class="proj-foot">'
            f'    <span class="proj-latest">Latest: {html.escape(latest[:19] or "—")}</span>'
            f'  </div>'
            f'</a>'
        )
        cards_html.append(card_html)

    # Toggle UI
    toggle_html = (
        '<nav class="scope-pills" aria-label="Project scope">'
        f'  <a href="?status=active"   class="scope-pill {"on" if scope=="active"   else ""}">Active <span class="n">{counts["active"]}</span></a>'
        f'  <a href="?status=archived" class="scope-pill {"on" if scope=="archived" else ""}">Archived <span class="n">{counts["archived"]}</span></a>'
        f'  <a href="?status=all"      class="scope-pill {"on" if scope=="all"      else ""}">All <span class="n">{counts["all"]}</span></a>'
        '</nav>'
    )

    body_class = 'tier1'
    heading = {
        'active':   'Active projects',
        'archived': 'Archived projects',
        'all':      'All projects',
    }.get(scope, 'Projects')

    empty_html = ''
    if not visible:
        empty_html = (
            '<div class="empty">'
            f'No {html.escape(scope)} projects to show. '
            'Toggle the pills above to switch scope.'
            '</div>')

    developed_by = 'SmartSoC CAD · Varun Reddy Merugu'

    return ''.join([
        '<!DOCTYPE html><html><head>',
        '<meta charset="utf-8">',
        f'<title>CBflow-SmartGrid — {html.escape(heading)}</title>',
        _STYLE,
        _SCRIPT_RELOAD_ON_FOCUS,
        '</head><body class="', body_class, '">',
        '<header class="bar">',
        f'  <div class="brand">CBflow<span class="lite">-SmartGrid</span>'
        f'       <span class="lite" style="margin-left:8px;color:#0000FF;'
        f'             font-weight:700;">· SmartSoC</span></div>',
        '  <div class="proj"><a href="/">All projects</a></div>',
        f'  <div class="byline">{html.escape(developed_by)} &middot; '
        f'<a href="mailto:varun@smartsocs.com" '
        f'style="color:inherit;text-decoration:underline">varun@smartsocs.com'
        f'</a></div>',
        '</header>',
        '<section class="tier1-ctrl">',
        f'  <h1 class="tier1-h1">{html.escape(heading)}</h1>',
        toggle_html,
        '</section>',
        empty_html,
        '<section class="proj-cards">', *cards_html, '</section>',
        '</body></html>',
    ])


def _tapeout_info_safe(iso):
    """Best-effort tapeout countdown. Returns (display_str, weeks_int)."""
    if not iso:
        return ('no date', 0)
    try:
        from datetime import date
        t = date.fromisoformat(iso)
        delta = (t - date.today()).days
        weeks = max(0, (delta + 6) // 7)
        return (iso, weeks)
    except Exception:
        return (iso, 0)


# ─── Tier 2 — project landing (discipline + schedule + resource) ─────────────


def _render_schedule_card(project, info):
    """Schedule card for Tier 2.

    Reads milestone_targets from master_projects.json (preferred) or
    falls back to even-spacing across project_start_date → tapeout_date.
    Marks fallback dates as 'estimated' so customers don't mistake them
    for committed targets.
    """
    try:
        import sys as _sys, os as _os
        _utils = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
        _cmds = _os.path.join(_utils, 'commands')
        for _p in (_utils, _cmds):
            if _p not in _sys.path:
                _sys.path.insert(0, _p)
        from tcl_config_parser import _load_master_projects
        data = _load_master_projects()
        entry = (data.get('projects') or {}).get(project, {})
    except Exception:
        entry = {}
    tapeout_iso = entry.get('tapeout_date') or info.get('tapeout_date') or ''
    start_iso = entry.get('project_start_date') or ''
    tapeout_str, tapeout_weeks = _tapeout_info_safe(tapeout_iso)
    targets = entry.get('milestone_targets') or {}
    estimated = False
    if not targets and start_iso and tapeout_iso:
        try:
            from datetime import date, timedelta
            s = date.fromisoformat(start_iso)
            t = date.fromisoformat(tapeout_iso)
            step = (t - s).days / (len(_MILESTONES) + 1)
            targets = {m: (s + timedelta(days=round(step * (i + 1)))).isoformat()
                       for i, m in enumerate(_MILESTONES)}
            estimated = True
        except Exception:
            targets = {}

    from datetime import date as _d
    today = _d.today().isoformat()
    pips = []
    for m in _MILESTONES:
        tgt = targets.get(m) or ''
        state = 'future'
        if tgt and tgt < today:
            state = 'past'
        pips.append(
            f'<div class="sched-pip sched-{state}">'
            f'  <div class="sched-pip-name">{html.escape(m)}</div>'
            f'  <div class="sched-pip-date">{html.escape(tgt[:10] or "—")}</div>'
            '</div>')
    note = ''
    if estimated:
        note = (
            '<div class="sched-note">Target dates estimated from '
            '<code>project_start_date</code> + <code>tapeout_date</code> '
            '(even-spacing). Add <code>milestone_targets</code> to '
            '<code>master_projects.json</code> for authoritative dates.</div>')
    return (
        '<section class="sched-card">'
        '  <div class="card-h"><div class="card-title">Schedule</div>'
        f'  <div class="card-sub">Tapeout {html.escape(tapeout_str)} · '
        f'{html.escape(str(tapeout_weeks))} weeks</div></div>'
        '  <div class="sched-timeline">'
        f'    {"".join(pips)}'
        '  </div>'
        f'  {note}'
        '</section>')


def _render_resource_card(project):
    """Resource card for Tier 2.

    Renders a placeholder structure that the inline JS fills from
    /api/resources?project=<name> on first paint — the aggregation
    walks each recent RACE DB file, which may be slow (~10-50ms per
    DB). Loading async keeps first paint fast.
    """
    return (
        '<section class="resource-card">'
        '  <div class="card-h"><div class="card-title">Resources</div>'
        '  <div class="card-sub">LSF usage · last 20 published runs</div></div>'
        '  <div class="resource-grid" id="resource-grid">'
        '    <div class="resource-stat">'
        '      <div class="resource-stat-val" id="rs-jobs">…</div>'
        '      <div class="resource-stat-lbl">Jobs tracked</div>'
        '    </div>'
        '    <div class="resource-stat">'
        '      <div class="resource-stat-val" id="rs-cost">…</div>'
        '      <div class="resource-stat-lbl">Est. cost (USD)</div>'
        '    </div>'
        '    <div class="resource-stat">'
        '      <div class="resource-stat-val" id="rs-cpu">…</div>'
        '      <div class="resource-stat-lbl">CPU hours</div>'
        '    </div>'
        '    <div class="resource-stat">'
        '      <div class="resource-stat-val" id="rs-queues">…</div>'
        '      <div class="resource-stat-lbl">Queue tiers used</div>'
        '    </div>'
        '  </div>'
        '  <div class="resource-note" id="rs-note">Loading…</div>'
        '  <script>'
        '    (function() {'
        f'      var proj = {json.dumps(project)};'
        '      fetch("/api/resources?project=" + encodeURIComponent(proj))'
        '        .then(function(r){return r.json()})'
        '        .then(function(j){'
        '          document.getElementById("rs-jobs").textContent  = j.jobs ?? "0";'
        '          document.getElementById("rs-cost").textContent  = j.cost_est ? "$" + j.cost_est.toFixed(0) : "—";'
        '          document.getElementById("rs-cpu").textContent   = j.cpu_hours ? j.cpu_hours.toFixed(1) : "0";'
        '          document.getElementById("rs-queues").textContent = (j.queue_tiers || []).join(" · ") || "—";'
        '          document.getElementById("rs-note").textContent = '
        '            "Last " + (j.run_count || 0) + " runs tracked";'
        '        })'
        '        .catch(function(e){'
        '          document.getElementById("rs-note").textContent = "Resource data unavailable";'
        '        });'
        '    })();'
        '  </script>'
        '</section>')


def _aggregate_resources(race_db_paths):
    """SUM lsf_details across a list of RACE DB files, read-only, best-effort.

    Returns {jobs, cost_est, cpu_hours, queue_tiers}. Skips any DB that
    doesn't open or doesn't have the table. Used by _api_resources.
    """
    import sqlite3 as _sq3
    total_jobs = 0
    total_cost = 0.0
    total_cpu_sec = 0.0
    queue_tiers = set()
    for db_path in race_db_paths:
        try:
            conn = _sq3.connect(f'file:{db_path}?mode=ro', uri=True)
        except _sq3.Error:
            continue
        try:
            try:
                rows = conn.execute(
                    "SELECT COUNT(*), "
                    "       SUM(COALESCE(cost_estimate, 0)), "
                    "       SUM(COALESCE(actual_cpu_time_sec, 0)) "
                    "FROM lsf_details").fetchone()
                if rows:
                    total_jobs += int(rows[0] or 0)
                    total_cost += float(rows[1] or 0.0)
                    total_cpu_sec += float(rows[2] or 0.0)
                for r in conn.execute(
                        "SELECT DISTINCT resource_tier FROM lsf_details "
                        "WHERE resource_tier IS NOT NULL AND resource_tier != ''"):
                    queue_tiers.add(r[0])
            except _sq3.OperationalError:
                pass
        finally:
            conn.close()
    return {
        'jobs':         total_jobs,
        'cost_est':     round(total_cost, 2),
        'cpu_hours':    round(total_cpu_sec / 3600.0, 2),
        'queue_tiers':  sorted(queue_tiers),
    }


def _render_tier2(project, info, blocks, published_rows):
    """Project landing — Discipline + Schedule + Resource cards, with the
    existing published-runs grid below for drill-in context.

    Returns a full HTML page. Reuses the existing _render_index chrome +
    "Runs" table from the old index page; prepends the three cards.
    """
    disc_cards = _render_discipline_cards(project)
    sched_card = _render_schedule_card(project, info or {})
    res_card = _render_resource_card(project)
    # Delegate the published-runs table + KPI strip to the existing
    # _render_index — we just inject the three new cards before the KPI
    # strip. The chunk-stitching keeps the renderer monolithic without
    # duplicating 300 lines of table/filter rendering.
    inner = _render_index(project, info, blocks, published_rows)
    # Replace the title + inject the project cards after </header>.
    inner = inner.replace(
        '</header>',
        '</header>'
        + '<section class="tier2-cards">'
        + disc_cards + sched_card + res_card
        + '</section>', 1)
    inner = inner.replace(
        f'<title>CBflow-ProjectDashboard — {html.escape(project)}</title>',
        f'<title>CBflow-SmartGrid — {html.escape(project)}</title>', 1)
    return inner


def _render_index(project, info, blocks, published_rows):
    """Dense metrics-dashboard landing page.

    Three stacked sections:
      1. KPI strip — project totals + verdict counts + tapeout countdown
      2. Blocks × Phase heatmap — one row per block, one column per phase,
         each cell holds a pip per milestone. Scans 100+ blocks quickly.
      3. Published-runs table — flat list of every publish, filterable/sortable.
    """
    phases = _parse_phases(info)
    block_names = _resolve_block_names(blocks, published_rows)

    # Per-(block, phase, milestone) index for the heatmap.
    cells = {(r['block'], r['phase'], r['milestone']): r for r in published_rows}

    latest = max((r.get('published_at') or '' for r in published_rows), default='—')
    # Split runs by phase for a factual (non-judgmental) breakdown
    phase_counts = {ph: 0 for ph in phases}
    for r in published_rows:
        if r['phase'] in phase_counts:
            phase_counts[r['phase']] += 1
    # Same for milestones — informational only
    ms_counts = {ms: 0 for ms in _MILESTONES}
    for r in published_rows:
        if r['milestone'] in ms_counts:
            ms_counts[r['milestone']] += 1

    tapeout_iso = info.get('tapeout_date') or ''
    tapeout_str, tapeout_weeks = _tapeout_info(tapeout_iso)
    phase_now = info.get('current_phase') or '—'
    tech = info.get('technology') or '—'
    metal = info.get('metal_stack') or '—'
    lib  = info.get('lib_config_tag') or '—'
    developed_by = info.get('developed_by') or 'SmartSoC CAD · Varun Reddy Merugu'
    # Normalize legacy / stale labels so a prior-publish with the old
    # byline (persisted into tracker.db before this rename) renders as
    # the canonical current credit. The user asked for a single
    # consistent byline across every surface — hub, per-run, SmartGrid.
    _STALE_BYLINES = {
        'SmartSoC and MIPS', 'SmartSoc and MIPS',
        'SmartSoc Solutions Pvt Limited', 'SmartSoC Solutions Pvt Limited',
    }
    if developed_by in _STALE_BYLINES:
        developed_by = 'SmartSoC CAD · Varun Reddy Merugu'

    # Rows for the flat table — precomputed strings so the client-side JS just
    # filters/sorts existing DOM rather than reflowing.
    ms_col_idx = {m: i for i, m in enumerate(_MILESTONES)}

    parts = [
        '<!DOCTYPE html><html><head>',
        '<meta charset="utf-8">',
        f'<title>CBflow-ProjectDashboard — {html.escape(project)}</title>',
        _STYLE,
        _SCRIPT_RELOAD_ON_FOCUS,
        '</head><body>',
        # ── Top bar ────────────────────────────────────────────────────
        '<header class="bar">',
        f'  <div class="brand">CBflow<span class="lite">-ProjectDashboard</span><span class="lite" style="margin-left:8px;color:#0000FF;font-weight:700;">· SmartSoC</span></div>',
        f'  <div class="proj"><a href="/">{html.escape(project)}</a></div>',
        f'  <div class="kv">Phase <b>{html.escape(phase_now)}</b></div>',
        f'  <div class="kv">Tapeout <b>{html.escape(tapeout_str)}</b></div>',
        f'  <div class="kv">Tech <b>{html.escape(tech)}</b></div>',
        f'  <div class="kv">Metal <b>{html.escape(metal)}</b></div>',
        f'  <div class="kv">Lib <b>{html.escape(lib)}</b></div>',
        f'  <div class="byline">{html.escape(developed_by)} &middot; <a href="mailto:varun@smartsocs.com" style="color:inherit;text-decoration:underline">varun@smartsocs.com</a></div>',
        '</header>',

        # ── Discipline cards — PD / DFT / DV navigation ───────────────
        _render_discipline_cards(project),

        # ── KPI strip — pure counts, no verdicts ──────────────────────
        '<section class="kpi">',
        f'  <div><div class="lbl">Blocks</div><div class="val">{len(block_names)}</div>'
        f'      <div class="sub">{sum(1 for b in block_names if any((b,p,m) in cells for p in phases for m in _MILESTONES))} with any publish</div></div>',
        f'  <div><div class="lbl">Published runs</div><div class="val">{len(published_rows)}</div>'
        f'      <div class="sub">latest {html.escape(latest[:19])}</div></div>',
        f'  <div><div class="lbl">Phases active</div><div class="val">'
        f'      {sum(1 for c in phase_counts.values() if c)}/{len(phases)}</div>'
        f'      <div class="sub">phases with any publish</div></div>',
        f'  <div><div class="lbl">Weeks to tapeout</div><div class="val">{tapeout_weeks}</div>'
        f'      <div class="sub">{html.escape(tapeout_iso or "no date")}</div></div>',
        '</section>',
    ]

    if not published_rows:
        parts.append(
            '<div class="empty">'
            'No published runs yet.  Publish a release from a workspace with '
            '<code>cbflow run release --tag &lt;TAG&gt; --publish</code>'
            '</div>')
        parts.append('</body></html>')
        return ''.join(parts)

    # ── PRIMARY: Published runs table (each row = one run directory) ──
    parts.append('<div class="sec-h">Runs '
                 '<span class="hint">each row = one published run directory · '
                 'click column headers to sort · exit milestone &amp; phase are filters, '
                 'not identity</span></div>')
    parts.append('<div class="filters">')
    parts.append('  <label>Search <input type="search" id="f-q" '
                 'placeholder="run dir, block, released by…"></label>')
    parts.append('  <label>Block <select id="f-blk"><option value="">any</option>')
    for blk in block_names:
        parts.append(f'    <option>{html.escape(blk)}</option>')
    parts.append('  </select></label>')
    parts.append('  <label>Phase <select id="f-phase"><option value="">any</option>')
    for ph in phases:
        parts.append(f'    <option>{html.escape(ph)}</option>')
    parts.append('  </select></label>')
    parts.append('  <label>Exit milestone <select id="f-ms">'
                 '<option value="">any</option>')
    for ms in _MILESTONES:
        parts.append(f'    <option>{html.escape(ms)}</option>')
    parts.append('  </select></label>')
    parts.append('  <div class="spacer"></div>')
    parts.append('  <div class="count" id="f-count"></div>')
    parts.append('</div>')

    parts.append('<div style="overflow-x:auto"><table class="d" id="pub-tbl">'
                 '<thead><tr>')
    headers = [('run',         'Run directory'),
               ('block',       'Block'),
               ('phase',       'Phase'),
               ('milestone',   'Exit'),
               ('release_tag', 'Release tag'),
               ('released_by', 'Released by'),
               ('published_at','Published'),
               ('id',          'Detail')]
    for key, lbl in headers:
        parts.append(f'  <th data-sort="{key}">{html.escape(lbl)}</th>')
    parts.append('</tr></thead><tbody>')
    sorted_rows = sorted(published_rows,
                         key=lambda r: (r.get('published_at') or ''),
                         reverse=True)
    for r in sorted_rows:
        run_dir_full = r.get('run_dir') or ''
        run_name = os.path.basename(run_dir_full) or r.get('release_tag') or f'run-{r["id"]}'
        parts.append(
            f'  <tr data-phase="{html.escape(r["phase"])}" '
            f'data-ms="{html.escape(r["milestone"])}" data-blk="{html.escape(r["block"])}">'
            f'<td><a href="/published/{r["id"]}" title="{html.escape(run_dir_full)}">'
            f'<b>{html.escape(run_name)}</b></a></td>'
            f'<td><a href="/block/{html.escape(r["block"])}">'
            f'{html.escape(r["block"])}</a></td>'
            f'<td>{html.escape(r["phase"])}</td>'
            f'<td class="mono">{html.escape(r["milestone"])}</td>'
            f'<td class="mono">{html.escape(r.get("release_tag") or "—")}</td>'
            f'<td>{html.escape(r.get("released_by") or "—")}</td>'
            f'<td class="mono">{html.escape((r.get("published_at") or "")[:19])}</td>'
            f'<td><a href="/published/{r["id"]}">open →</a></td>'
            f'</tr>')
    parts.append('</tbody></table></div>')

    # ── SECONDARY: Compact blocks summary ─────────────────────────────
    parts.append('<div class="sec-h">Blocks '
                 f'<span class="hint">{len(block_names)} blocks in this project</span></div>')
    parts.append('<div style="overflow-x:auto"><table class="d"><thead><tr>'
                 '<th>Block</th><th>Runs</th><th>Phases used</th>'
                 '<th>Milestones used</th><th>Latest publish</th><th></th>'
                 '</tr></thead><tbody>')
    for blk in block_names:
        blk_rows = [r for r in published_rows if r['block'] == blk]
        phases_used = {r['phase']     for r in blk_rows}
        miles_used  = {r['milestone'] for r in blk_rows}
        latest_b = max((r.get('published_at') or '' for r in blk_rows), default='—')
        parts.append(
            f'<tr><td><a href="/block/{html.escape(blk)}"><b>{html.escape(blk)}</b></a></td>'
            f'<td class="num">{len(blk_rows)}</td>'
            f'<td class="mono">{html.escape(", ".join(sorted(phases_used)) or "—")}</td>'
            f'<td class="mono">{html.escape(", ".join(sorted(miles_used)) or "—")}</td>'
            f'<td class="mono">{html.escape(latest_b[:19])}</td>'
            f'<td><a href="/block/{html.escape(blk)}">open →</a></td></tr>')
    parts.append('</tbody></table></div>')

    parts.append(_SCRIPT_INDEX)
    parts.append('</body></html>')
    return ''.join(parts)


_SCRIPT_INDEX = """
<script>
  // Live filter + column sort for the published-runs table. No dependencies;
  // designed to stay smooth up to a few thousand rows (typical project).
  (function() {
    const q   = document.getElementById('f-q');
    const blk = document.getElementById('f-blk');
    const ph  = document.getElementById('f-phase');
    const ms  = document.getElementById('f-ms');
    const cnt = document.getElementById('f-count');
    const tbl = document.getElementById('pub-tbl');
    if (!tbl) return;
    const tbody = tbl.tBodies[0];
    const allRows = Array.from(tbody.querySelectorAll('tr'));
    let sortKey = 'published_at', sortDir = -1;

    function apply() {
      const s = (q.value || '').toLowerCase();
      const fblk = blk ? blk.value : '';
      const fph  = ph  ? ph.value  : '';
      const fms  = ms  ? ms.value  : '';
      let shown = 0;
      for (const r of allRows) {
        let hit = true;
        if (fblk && r.dataset.blk   !== fblk) hit = false;
        if (fph  && r.dataset.phase !== fph)  hit = false;
        if (fms  && r.dataset.ms    !== fms)  hit = false;
        if (hit && s && !r.textContent.toLowerCase().includes(s)) hit = false;
        r.style.display = hit ? '' : 'none';
        if (hit) shown++;
      }
      cnt.textContent = `${shown} / ${allRows.length} rows`;
    }
    [q, blk, ph, ms].filter(Boolean).forEach(el => el.addEventListener('input', apply));
    apply();

    // Column sort — click header. Numeric for id, string for everything else.
    tbl.tHead.addEventListener('click', e => {
      const th = e.target.closest('th');
      if (!th) return;
      const key = th.dataset.sort;
      if (!key) return;
      // toggle
      if (key === sortKey) sortDir = -sortDir;
      else { sortKey = key; sortDir = 1; }
      // Highlight
      tbl.tHead.querySelectorAll('th').forEach(x => x.classList.remove('sorted-asc','sorted-desc'));
      th.classList.add(sortDir > 0 ? 'sorted-asc' : 'sorted-desc');
      // Column index
      const idx = Array.from(th.parentNode.children).indexOf(th);
      const isNum = ['id'].includes(key);
      allRows.sort((a, b) => {
        const av = a.cells[idx].textContent.trim();
        const bv = b.cells[idx].textContent.trim();
        if (isNum) {
          const an = parseFloat(av.replace('%','')) || 0;
          const bn = parseFloat(bv.replace('%','')) || 0;
          return (an - bn) * sortDir;
        }
        return av.localeCompare(bv) * sortDir;
      });
      const frag = document.createDocumentFragment();
      allRows.forEach(r => frag.appendChild(r));
      tbody.appendChild(frag);
    });
  })();
</script>
"""


def _tapeout_info(iso):
    """(fmt_str, weeks_str) — weeks_str is a signed integer or '—'."""
    if not iso:
        return '—', '—'
    try:
        d = datetime.strptime(iso, '%Y-%m-%d').date()
    except ValueError:
        return iso, '—'
    delta = (d - date.today()).days
    if delta < 0:
        weeks = -((-delta + 6) // 7)
    else:
        weeks = (delta + 6) // 7
    return iso, str(weeks)


def _render_detail(project, info, d):
    developed_by = info.get('developed_by') or 'SmartSoC CAD · Varun Reddy Merugu'
    # Normalize legacy / stale labels so a prior-publish with the old
    # byline (persisted into tracker.db before this rename) renders as
    # the canonical current credit. The user asked for a single
    # consistent byline across every surface — hub, per-run, SmartGrid.
    _STALE_BYLINES = {
        'SmartSoC and MIPS', 'SmartSoc and MIPS',
        'SmartSoc Solutions Pvt Limited', 'SmartSoC Solutions Pvt Limited',
    }
    if developed_by in _STALE_BYLINES:
        developed_by = 'SmartSoC CAD · Varun Reddy Merugu'

    # Bucket metrics into "timing" vs "other" using category + name heuristics.
    all_metrics = d.get('metrics') or []
    timing_names = ('WNS', 'TNS', 'HOLD', 'SETUP', 'SLACK', 'FMAX', 'FREQ')
    timing_metrics, signoff_metrics, other_metrics = [], [], []
    for m in all_metrics:
        cat = (m.get('category') or '').lower()
        nm  = (m.get('name') or '').upper()
        if 'timing' in cat or any(t in nm for t in timing_names):
            timing_metrics.append(m)
        elif cat in ('power', 'em', 'ir', 'signoff', 'drc', 'lvs'):
            signoff_metrics.append(m)
        else:
            other_metrics.append(m)

    # Split files: images vs data. Images live under run_files with kinds
    # like IMAGE_CONGESTION / IMAGE_ROUTING (the client tags them at snapshot).
    all_files = d.get('files') or []
    image_files = [f for f in all_files
                   if (f.get('kind') or '').startswith('IMAGE_')]
    data_files  = [f for f in all_files
                   if not (f.get('kind') or '').startswith('IMAGE_')]

    checklist = d.get('checklist') or []

    # Tab counts drive the badges on the tab labels
    counts = {
        'timing':    len(timing_metrics),
        'floorplan': 1 if d.get('has_floorplan') else 0,
        'checklist': len(checklist),
        'routing':   len(image_files),
        'files':     len(data_files),
    }

    parts = [
        '<!DOCTYPE html><html><head>',
        '<meta charset="utf-8">',
        f'<title>{html.escape(d["block"])} · {html.escape(d["phase"])} · '
        f'{html.escape(d["milestone"])}</title>',
        _STYLE,
        _SCRIPT_RELOAD_ON_FOCUS,
        '</head><body>',
        '<header class="bar">',
        f'  <div class="brand">CBflow<span class="lite">-ProjectDashboard</span><span class="lite" style="margin-left:8px;color:#0000FF;font-weight:700;">· SmartSoC</span></div>',
        f'  <div class="proj"><a href="/">{html.escape(project)}</a></div>',
        f'  <div class="kv">Block <b><a href="/block/{html.escape(d["block"])}">'
        f'{html.escape(d["block"])}</a></b></div>',
        f'  <div class="kv">Phase <b>{html.escape(d["phase"])}</b></div>',
        f'  <div class="kv">Milestone <b>{html.escape(d["milestone"])}</b></div>',
        f'  <div class="byline">{html.escape(developed_by)} &middot; <a href="mailto:varun@smartsocs.com" style="color:inherit;text-decoration:underline">varun@smartsocs.com</a></div>',
        '</header>',
        '<div class="back"><a href="/">← back to project</a></div>',
        # ── Tab bar ───────────────────────────────────────────────────
        '<nav class="tabs" id="tabs">',
        '  <a data-tab="overview"  href="#overview">Overview</a>',
        f'  <a data-tab="timing"    href="#timing">Timing<span class="badge">{counts["timing"]}</span></a>',
        f'  <a data-tab="floorplan" href="#floorplan">Floorplan &amp; placement<span class="badge">{counts["floorplan"]}</span></a>',
        f'  <a data-tab="checklist" href="#checklist">Checklist<span class="badge">{counts["checklist"]}</span></a>',
        f'  <a data-tab="routing"   href="#routing">Routing / Congestion<span class="badge">{counts["routing"]}</span></a>',
        f'  <a data-tab="files"     href="#files">Files<span class="badge">{counts["files"]}</span></a>',
        '</nav>',
    ]

    # ── Overview tab ─────────────────────────────────────────────────
    parts.append('<div class="tab-body" data-tab="overview">')
    parts.append('<div class="sec-h">Release &amp; provenance</div>')
    parts.append('<dl class="kv-grid">')
    fields = [
        ('release_tag',  'Release tag'),
        ('release_dir',  'Release directory'),
        ('released_by',  'Released by'),
        ('released_at',  'Released at'),
        ('published_by', 'Published by'),
        ('published_at', 'Published at'),
        ('run_dir',      'Source run dir'),
        ('race_db_path', 'RACE DB'),
    ]
    for k, lbl in fields:
        v = d.get(k)
        if v is None or v == '': continue
        parts.append(f'  <dt>{html.escape(lbl)}</dt>'
                     f'  <dd>{html.escape(str(v))}</dd>')
    parts.append('</dl>')

    # Compact summary strip inside Overview — pure counts
    parts.append('<section class="kpi">')
    parts.append(f'  <div><div class="lbl">Timing rows</div>'
                 f'      <div class="val">{counts["timing"]}</div>'
                 f'      <div class="sub">WNS / TNS / slack</div></div>')
    parts.append(f'  <div><div class="lbl">Checklist rows</div>'
                 f'      <div class="val">{counts["checklist"]}</div>'
                 f'      <div class="sub">captured checks</div></div>')
    parts.append(f'  <div><div class="lbl">Images</div>'
                 f'      <div class="val">{counts["routing"]}</div>'
                 f'      <div class="sub">routing / congestion</div></div>')
    parts.append(f'  <div><div class="lbl">Files</div>'
                 f'      <div class="val">{counts["files"]}</div>'
                 f'      <div class="sub">release artifacts</div></div>')
    parts.append('</section>')
    parts.append('</div>')

    # ── Timing tab ───────────────────────────────────────────────────
    parts.append('<div class="tab-body" data-tab="timing">')
    parts.append('<div class="sec-h">Timing metrics '
                 f'<span class="hint">{len(timing_metrics)} rows</span></div>')
    parts.append(_metrics_table(timing_metrics))
    if other_metrics:
        parts.append(f'<div class="sec-h">Other metrics '
                     f'<span class="hint">{len(other_metrics)} rows</span></div>')
        parts.append(_metrics_table(other_metrics))
    parts.append('</div>')

    # ── Floorplan tab ────────────────────────────────────────────────
    parts.append('<div class="tab-body" data-tab="floorplan">')
    if d.get('has_floorplan'):
        parts.append('<div class="sec-h">Floorplan &amp; placement '
                     '<span class="hint">wheel = zoom · drag = pan · '
                     'click = show instance</span></div>')
        parts.append(_FLOORPLAN_PANE.replace('{PID}', str(d['id'])))
    else:
        parts.append('<div class="empty">No floorplan snapshot captured for this run.</div>')
    parts.append('</div>')

    # ── Checklist tab ────────────────────────────────────────────────
    parts.append('<div class="tab-body" data-tab="checklist">')
    parts.append('<div class="sec-h">Checklist '
                 f'<span class="hint">{len(checklist)} rows</span></div>')
    if not checklist:
        parts.append('<div class="empty">No checklist rows captured.</div>')
    else:
        parts.append('<div style="overflow-x:auto"><table class="d"><thead><tr>'
                     '<th>Check</th><th>Type</th><th>Category</th><th>Status</th>'
                     '<th>Value</th><th>Threshold</th><th>Detail</th></tr></thead><tbody>')
        for c in checklist:
            st = (c.get('status') or '—').upper()
            parts.append(
                f'<tr><td>{html.escape(c.get("check_name") or "")}</td>'
                f'<td>{html.escape(c.get("check_type") or "")}</td>'
                f'<td>{html.escape(c.get("category") or "")}</td>'
                f'<td class="mono">{html.escape(st)}</td>'
                f'<td class="mono">{html.escape(str(c.get("metric_value") or ""))}</td>'
                f'<td class="mono">{html.escape(str(c.get("threshold") or ""))}</td>'
                f'<td>{html.escape((c.get("detail") or "")[:200])}</td></tr>')
        parts.append('</tbody></table></div>')
    if signoff_metrics:
        parts.append(f'<div class="sec-h">Sign-off metrics '
                     f'<span class="hint">{len(signoff_metrics)} rows</span></div>')
        parts.append(_metrics_table(signoff_metrics))
    parts.append('</div>')

    # ── Routing / Congestion tab ─────────────────────────────────────
    parts.append('<div class="tab-body" data-tab="routing">')
    parts.append('<div class="sec-h">Routing &amp; congestion images '
                 f'<span class="hint">{len(image_files)} images</span></div>')
    if not image_files:
        parts.append('<div class="empty">'
                     'No routing / congestion images captured for this run.  '
                     'Drop PNG / JPG / SVG files into '
                     '<code>&lt;release_dir&gt;/images/</code> before publish '
                     '(the tag comes from the filename: '
                     '<code>congestion_*.png</code>, <code>routing_*.png</code>, '
                     '<code>drc_*.png</code>, …).'
                     '</div>')
    else:
        parts.append('<div class="img-grid">')
        for idx, f in enumerate(image_files):
            kind = f.get('kind') or 'IMAGE'
            rel  = f.get('rel_path') or ''
            parts.append(
                f'  <div class="img-card">'
                f'    <img loading="lazy" src="/image/{d["id"]}/{idx}" '
                f'         alt="{html.escape(rel)}">'
                f'    <div class="caption">'
                f'      <b>{html.escape(kind.replace("IMAGE_", ""))}</b>  {html.escape(rel)}'
                f'    </div>'
                f'  </div>')
        parts.append('</div>')
    parts.append('</div>')

    # ── Files tab ────────────────────────────────────────────────────
    parts.append('<div class="tab-body" data-tab="files">')
    parts.append(f'<div class="sec-h">Release files '
                 f'<span class="hint">{len(data_files)} rows</span></div>')
    if not data_files:
        parts.append('<div class="empty">No data files captured.</div>')
    else:
        parts.append('<div style="overflow-x:auto"><table class="d"><thead><tr>'
                     '<th>Kind</th><th>Path</th><th>SHA-256</th></tr></thead><tbody>')
        for f in data_files:
            sha = (f.get('sha256') or '')[:16]
            parts.append(
                f'<tr><td>{html.escape(f.get("kind") or "")}</td>'
                f'<td class="mono">{html.escape(f.get("rel_path") or "")}</td>'
                f'<td class="mono">{html.escape(sha)}…</td></tr>')
        parts.append('</tbody></table></div>')
    parts.append('</div>')

    parts.append(_SCRIPT_TABS)
    parts.append('</body></html>')
    return ''.join(parts)


def _metrics_table(rows):
    if not rows:
        return '<div class="empty">No metrics captured for this category.</div>'
    out = ['<div style="overflow-x:auto"><table class="d"><thead><tr>'
           '<th>Category</th><th>Name</th><th>Value</th><th>Unit</th>'
           '<th>Scenario</th><th>Corner</th></tr></thead><tbody>']
    for m in rows:
        out.append(
            f'<tr><td>{html.escape(m.get("category") or "")}</td>'
            f'<td>{html.escape(m.get("name") or "")}</td>'
            f'<td class="num">{html.escape(str(m.get("value") or ""))}</td>'
            f'<td>{html.escape(m.get("unit") or "")}</td>'
            f'<td>{html.escape(m.get("scenario") or "")}</td>'
            f'<td>{html.escape(m.get("corner") or "")}</td></tr>')
    out.append('</tbody></table></div>')
    return ''.join(out)


_SCRIPT_TABS = """
<script>
  // URL-hash-driven tab switcher. `#overview` (or no hash) = first tab.
  (function() {
    const tabs   = document.querySelectorAll('nav.tabs a');
    const bodies = document.querySelectorAll('.tab-body');
    if (!tabs.length) return;
    function show(name) {
      let matched = false;
      tabs.forEach(a => {
        const on = a.dataset.tab === name;
        a.classList.toggle('active', on);
        if (on) matched = true;
      });
      bodies.forEach(b => b.classList.toggle('active', b.dataset.tab === name));
      if (!matched) {
        tabs[0].classList.add('active');
        bodies[0].classList.add('active');
      }
    }
    const initial = (location.hash || '').replace('#', '') || tabs[0].dataset.tab;
    show(initial);
    window.addEventListener('hashchange',
      () => show((location.hash || '').replace('#','') || tabs[0].dataset.tab));
  })();
</script>
"""


def _render_block(project, info, block_name, block_meta, block_pubs):
    """Per-block page — everything published for this one block, in one view.

    Sections: block metadata (top bar), KPI strip for THIS block's publishes,
    phase × milestone matrix, and a flat published-runs table filtered
    to this block. Same visual language as the landing page so managers
    only learn one grammar.
    """
    phases = _parse_phases(info)
    cells = {(r['phase'], r['milestone']): r for r in block_pubs}

    latest = max((r.get('published_at') or '' for r in block_pubs), default='—')
    phases_used = {r['phase']     for r in block_pubs}
    miles_used  = {r['milestone'] for r in block_pubs}
    releasers   = {r.get('released_by') or '—' for r in block_pubs}

    developed_by = info.get('developed_by') or 'SmartSoC CAD · Varun Reddy Merugu'
    # Normalize legacy / stale labels so a prior-publish with the old
    # byline (persisted into tracker.db before this rename) renders as
    # the canonical current credit. The user asked for a single
    # consistent byline across every surface — hub, per-run, SmartGrid.
    _STALE_BYLINES = {
        'SmartSoC and MIPS', 'SmartSoc and MIPS',
        'SmartSoc Solutions Pvt Limited', 'SmartSoC Solutions Pvt Limited',
    }
    if developed_by in _STALE_BYLINES:
        developed_by = 'SmartSoC CAD · Varun Reddy Merugu'
    dl_level = block_meta.get('dl_level') or '—'
    parent   = block_meta.get('parent') or '—'
    desc     = block_meta.get('description') or ''

    parts = [
        '<!DOCTYPE html><html><head>',
        '<meta charset="utf-8">',
        f'<title>{html.escape(block_name)} — CBflow-ProjectDashboard</title>',
        _STYLE,
        _SCRIPT_RELOAD_ON_FOCUS,
        '</head><body>',
        # ── Header bar ───────────────────────────────────────────────
        '<header class="bar">',
        f'  <div class="brand">CBflow<span class="lite">-ProjectDashboard</span><span class="lite" style="margin-left:8px;color:#0000FF;font-weight:700;">· SmartSoC</span></div>',
        f'  <div class="proj"><a href="/">{html.escape(project)}</a></div>',
        f'  <div class="kv">Block <b>{html.escape(block_name)}</b></div>',
        f'  <div class="kv">Level <b>{html.escape(dl_level)}</b></div>',
        f'  <div class="kv">Parent <b>{html.escape(parent)}</b></div>',
        f'  <div class="byline">{html.escape(developed_by)} &middot; <a href="mailto:varun@smartsocs.com" style="color:inherit;text-decoration:underline">varun@smartsocs.com</a></div>',
        '</header>',
        '<div class="back">',
        '  <a href="/">← back to project</a>',
        '</div>',
    ]

    if desc:
        parts.append('<div class="sec-h">About</div>')
        parts.append(f'<div style="padding:8px 14px;background:var(--panel);'
                     f'border-bottom:1px solid var(--border);font-size:13px">'
                     f'{html.escape(desc)}</div>')

    # ── KPI strip (scoped to this block) ─────────────────────────────
    parts.append('<section class="kpi">')
    parts.append(
        f'  <div><div class="lbl">Published runs</div>'
        f'      <div class="val">{len(block_pubs)}</div>'
        f'      <div class="sub">latest {html.escape(latest[:19])}</div></div>')
    parts.append(
        f'  <div><div class="lbl">Phases used</div>'
        f'      <div class="val">{len(phases_used)}/{len(phases)}</div>'
        f'      <div class="sub">{html.escape(", ".join(sorted(phases_used)) or "—")}</div></div>')
    parts.append(
        f'  <div><div class="lbl">Milestones used</div>'
        f'      <div class="val">{len(miles_used)}/{len(_MILESTONES)}</div>'
        f'      <div class="sub">{html.escape(", ".join(sorted(miles_used)) or "—")}</div></div>')
    parts.append(
        f'  <div><div class="lbl">Contributors</div>'
        f'      <div class="val">{len(releasers)}</div>'
        f'      <div class="sub">unique release authors</div></div>')
    parts.append('</section>')

    # ── PRIMARY: Published runs for this block ────────────────────────
    parts.append('<div class="sec-h">Runs '
                 '<span class="hint">each row = one published run directory for this block · '
                 'phase &amp; exit milestone are filters</span></div>')
    parts.append('<div class="filters">')
    parts.append('  <label>Search <input type="search" id="f-q" '
                 'placeholder="run dir, milestone, released by…"></label>')
    parts.append('  <label>Phase <select id="f-phase"><option value="">any</option>')
    for ph in phases:
        parts.append(f'    <option>{html.escape(ph)}</option>')
    parts.append('  </select></label>')
    parts.append('  <label>Exit milestone <select id="f-ms"><option value="">any</option>')
    for ms in _MILESTONES:
        parts.append(f'    <option>{html.escape(ms)}</option>')
    parts.append('  </select></label>')
    parts.append('  <div class="spacer"></div>')
    parts.append('  <div class="count" id="f-count"></div>')
    parts.append('</div>')

    parts.append('<div style="overflow-x:auto"><table class="d" id="pub-tbl">'
                 '<thead><tr>')
    headers = [('run',          'Run directory'),
               ('phase',        'Phase'),
               ('milestone',    'Exit'),
               ('release_tag',  'Release tag'),
               ('released_by',  'Released by'),
               ('published_at', 'Published'),
               ('id',           'Detail')]
    for key, lbl in headers:
        parts.append(f'  <th data-sort="{key}">{html.escape(lbl)}</th>')
    parts.append('</tr></thead><tbody>')
    sorted_rows = sorted(block_pubs,
                         key=lambda r: (r.get('published_at') or ''),
                         reverse=True)
    for r in sorted_rows:
        run_dir_full = r.get('run_dir') or ''
        run_name = os.path.basename(run_dir_full) or r.get('release_tag') or f'run-{r["id"]}'
        parts.append(
            f'  <tr data-phase="{html.escape(r["phase"])}" '
            f'data-ms="{html.escape(r["milestone"])}">'
            f'<td><a href="/published/{r["id"]}" title="{html.escape(run_dir_full)}">'
            f'<b>{html.escape(run_name)}</b></a></td>'
            f'<td>{html.escape(r["phase"])}</td>'
            f'<td class="mono">{html.escape(r["milestone"])}</td>'
            f'<td class="mono">{html.escape(r.get("release_tag") or "—")}</td>'
            f'<td>{html.escape(r.get("released_by") or "—")}</td>'
            f'<td class="mono">{html.escape((r.get("published_at") or "")[:19])}</td>'
            f'<td><a href="/published/{r["id"]}">open →</a></td>'
            f'</tr>')
    parts.append('</tbody></table></div>')

    # ── SECONDARY: Phase × Milestone coverage grid (informational) ───
    parts.append('<div class="sec-h">Milestone coverage '
                 '<span class="hint">cells with a publish · click a dot to open its detail</span></div>')
    parts.append('<div style="overflow-x:auto"><table class="d"><thead><tr>'
                 '<th>Phase</th>')
    for ms in _MILESTONES:
        parts.append(f'  <th>{html.escape(ms)}</th>')
    parts.append('</tr></thead><tbody>')
    for ph in phases:
        parts.append(f'<tr><td><b>{html.escape(ph)}</b></td>')
        for ms in _MILESTONES:
            row = cells.get((ph, ms))
            if row:
                when = (row.get("published_at") or "")[:10]
                parts.append(
                    f'<td><a href="/published/{row["id"]}" '
                    f'title="{ms} · published {when}">✓</a> '
                    f'<span class="mono" style="font-size:11px;color:var(--muted)">'
                    f'{html.escape(when)}</span></td>')
            else:
                parts.append(f'<td><span style="color:var(--muted)" '
                             f'title="{ms} not published">·</span></td>')
        parts.append('</tr>')
    parts.append('</tbody></table></div>')

    parts.append(_SCRIPT_INDEX)
    parts.append('</body></html>')
    return ''.join(parts)


# ─── Helpers ────────────────────────────────────────────────────────────────

def _parse_phases(info):
    raw = info.get('phases_json')
    if not raw:
        return ['(unknown)']
    try:
        p = json.loads(raw)
        return p or ['(unknown)']
    except ValueError:
        return ['(unknown)']


def _resolve_block_names(blocks_rows, published_rows):
    """Union of blocks declared in the blocks table and blocks that have any
    published entry — the latter guarantees we surface a row even if the
    block isn't explicitly registered."""
    names = set(b['block_name'] for b in blocks_rows)
    names.update(r['block'] for r in published_rows)
    return sorted(names)


def _fmt_tapeout(tapeout_iso):
    if not tapeout_iso:
        return '—'
    try:
        d = datetime.strptime(tapeout_iso, '%Y-%m-%d').date()
    except ValueError:
        return tapeout_iso
    delta = (d - date.today()).days
    if delta < 0:
        return f'{tapeout_iso} ({-delta}d overdue)'
    weeks = (delta + 6) // 7
    return f'{tapeout_iso} ({weeks} wk)'
