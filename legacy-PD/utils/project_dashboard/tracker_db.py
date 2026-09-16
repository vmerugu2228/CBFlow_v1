"""Tracker DB for CBflow-ProjectDashboard.

SQLite schema — one DB per project at
`~/.cbflow/project-dashboard/<project>/tracker.db`.

Snapshot semantics: `publish()` writes a FROZEN copy of a run's metrics /
checklist / release info at the moment of publish. Nothing else updates
the tables — no polling, no auto-refresh — so what management sees is
exactly what was published.

Cell identity is `(project, block, phase, milestone)`. UNIQUE constraint
enforces one published run per cell; re-publish without `override=True`
raises ConflictError.
"""

import json
import os
import sqlite3
from datetime import datetime


class ConflictError(Exception):
    """Raised when publishing to an already-published cell without override."""


# ─── Schema ─────────────────────────────────────────────────────────────────

_SCHEMA = """
CREATE TABLE IF NOT EXISTS project_info (
    project        TEXT PRIMARY KEY,
    tapeout_date   TEXT,
    current_phase  TEXT,
    phases_json    TEXT,
    developed_by   TEXT,
    technology     TEXT,
    metal_stack    TEXT,
    lib_config_tag TEXT,
    cbflow_release TEXT,
    updated_at     TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS blocks (
    project     TEXT NOT NULL,
    block_name  TEXT NOT NULL,
    dl_level    TEXT,
    parent      TEXT,
    description TEXT,
    added_at    TEXT DEFAULT (datetime('now')),
    PRIMARY KEY (project, block_name)
);

CREATE TABLE IF NOT EXISTS published_runs (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    project          TEXT NOT NULL,
    block            TEXT NOT NULL,
    phase            TEXT NOT NULL,
    milestone        TEXT NOT NULL,
    run_id           TEXT,
    run_dir          TEXT,
    race_db_path     TEXT,
    release_tag      TEXT,
    release_dir      TEXT,
    released_by      TEXT,
    released_at      TEXT,
    published_by     TEXT NOT NULL,
    published_at     TEXT DEFAULT (datetime('now')),
    verdict          TEXT,               -- PASS / CONDITIONAL / BLOCKED / UNKNOWN
    closability_pct  REAL,
    UNIQUE (project, block, phase, milestone)
);

CREATE TABLE IF NOT EXISTS run_metrics (
    published_run_id INTEGER NOT NULL,
    category         TEXT,               -- timing / power / drc / area / util / ...
    name             TEXT,               -- WNS / TNS / total_power / ...
    value            TEXT,
    unit             TEXT,
    scenario         TEXT,
    corner           TEXT,
    FOREIGN KEY (published_run_id) REFERENCES published_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_run_metrics_pid ON run_metrics(published_run_id);

CREATE TABLE IF NOT EXISTS run_checklist (
    published_run_id INTEGER NOT NULL,
    milestone        TEXT,
    category         TEXT,
    check_name       TEXT,
    check_type       TEXT,               -- mandatory / optional / library
    status           TEXT,               -- PASS / FAIL / WAIVED / SKIPPED / PENDING
    metric_value     TEXT,
    threshold        TEXT,
    severity         TEXT,
    detail           TEXT,
    FOREIGN KEY (published_run_id) REFERENCES published_runs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_run_checklist_pid ON run_checklist(published_run_id);

CREATE TABLE IF NOT EXISTS run_files (
    published_run_id INTEGER NOT NULL,
    kind             TEXT,               -- MANIFEST / RELEASE_COMPLETE / CHANGELOG / manifest_entry
    rel_path         TEXT,
    sha256           TEXT,
    FOREIGN KEY (published_run_id) REFERENCES published_runs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS run_timing (
    published_run_id INTEGER PRIMARY KEY,
    units            INTEGER,       -- DBUs per micron (mirrors floorplan)
    n_groups         INTEGER,       -- number of clock groups captured
    n_paths          INTEGER,       -- total paths across all groups
    groups_json      TEXT,          -- {"clock_groups":[{"name","paths":[...]}]}
    FOREIGN KEY (published_run_id) REFERENCES published_runs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS run_floorplan (
    published_run_id INTEGER PRIMARY KEY,
    def_path         TEXT,               -- source DEF (informational)
    units            INTEGER,            -- DEF UNITS DISTANCE MICRONS (DBUs/um)
    boundary_json    TEXT,               -- {"x1":..,"y1":..,"x2":..,"y2":..}
    rows_json        TEXT,               -- [{name,site,x,y,orient,count_x,count_y,step_x,step_y}, ...]
    cells_json       TEXT,               -- [{name,macro,x,y,orient}, ...]  (may be downsampled)
    macros_json      TEXT,               -- {macro_name: {w,h}}
    lef_paths_json   TEXT,               -- [<lef file paths>, ...]
    downsampled      INTEGER,            -- 1 if cells list was capped
    density_json     TEXT,               -- density heatmap over ALL cells (pre-downsample)
    total_cells      INTEGER,            -- pre-downsample cell count (for the status line)
    FOREIGN KEY (published_run_id) REFERENCES published_runs(id) ON DELETE CASCADE
);
"""


def init_db(db_path):
    """Create the DB and apply the schema. Idempotent + forward-compatible.

    Newly-introduced columns get added to existing tables via ALTER TABLE so
    an older tracker.db keeps working after an upgrade instead of raising
    'no such column' at first write. Keep the list narrow — full schema
    migrations belong in a migration file, not here.
    """
    d = os.path.dirname(db_path)
    if d:
        os.makedirs(d, mode=0o700, exist_ok=True)
    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(_SCHEMA)
        # Forward-compat: add columns introduced after v1.0.0.
        migrations = [
            ('run_floorplan', 'density_json', 'TEXT'),
            ('run_floorplan', 'total_cells',  'INTEGER'),
        ]
        for table, col, ctype in migrations:
            try:
                cols = {r[1] for r in conn.execute(
                    f'PRAGMA table_info({table})')}
                if col not in cols:
                    conn.execute(f'ALTER TABLE {table} ADD COLUMN {col} {ctype}')
            except sqlite3.OperationalError:
                pass
        conn.commit()
        os.chmod(db_path, 0o600)
    finally:
        conn.close()


# ─── Writers ────────────────────────────────────────────────────────────────

def _now():
    return datetime.now().isoformat(timespec='seconds')


def upsert_project_info(db_path, project, info):
    """Store or update the project-metadata row (tapeout, phases, byline...).

    `info` is a plain dict — missing keys are fine.
    """
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("""
            INSERT INTO project_info(project, tapeout_date, current_phase,
                phases_json, developed_by, technology, metal_stack,
                lib_config_tag, cbflow_release, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(project) DO UPDATE SET
              tapeout_date=excluded.tapeout_date,
              current_phase=excluded.current_phase,
              phases_json=excluded.phases_json,
              developed_by=excluded.developed_by,
              technology=excluded.technology,
              metal_stack=excluded.metal_stack,
              lib_config_tag=excluded.lib_config_tag,
              cbflow_release=excluded.cbflow_release,
              updated_at=excluded.updated_at
        """, (
            project, info.get('tapeout_date'), info.get('current_phase'),
            json.dumps(info.get('phases') or []),
            info.get('developed_by'), info.get('technology'),
            info.get('metal_stack'), info.get('lib_config_tag'),
            info.get('cbflow_release'), _now(),
        ))
        conn.commit()
    finally:
        conn.close()


def upsert_block(db_path, project, block_name, dl_level=None, parent=None,
                 description=None):
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("""
            INSERT INTO blocks(project, block_name, dl_level, parent, description)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(project, block_name) DO UPDATE SET
              dl_level=excluded.dl_level,
              parent=excluded.parent,
              description=excluded.description
        """, (project, block_name, dl_level, parent, description))
        conn.commit()
    finally:
        conn.close()


def publish(db_path, payload, project):
    """Write a snapshot for one cell.

    `payload` fields:
      block, phase, milestone           REQUIRED — cell identity
      published_by                       REQUIRED — user running publish
      override                           bool — allow replacing existing cell
      run_id, run_dir, race_db_path      run context
      release_tag, release_dir, released_by, released_at
      verdict, closability_pct           computed by the client
      project_info                       dict — pushed via upsert_project_info
      block_info                         dict — pushed via upsert_block
      metrics                            list of {category, name, value, unit,
                                                  scenario, corner}
      checklist                          list of {milestone, category, check_name,
                                                  check_type, status, metric_value,
                                                  threshold, severity, detail}
      files                              list of {kind, rel_path, sha256}
    """
    for k in ('block', 'phase', 'milestone', 'published_by'):
        if not payload.get(k):
            raise ValueError(f'publish payload missing required field: {k}')
    block = payload['block']
    phase = payload['phase']
    milestone = payload['milestone']
    override = bool(payload.get('override'))

    # Housekeeping upserts happen even on conflict so the UI stays fresh.
    pi = payload.get('project_info') or {}
    if pi:
        upsert_project_info(db_path, project, pi)
    bi = payload.get('block_info') or {}
    if bi.get('block_name') or bi.get('name'):
        upsert_block(
            db_path, project,
            bi.get('block_name') or bi.get('name'),
            dl_level=bi.get('dl_level'),
            parent=bi.get('parent'),
            description=bi.get('description'))

    conn = sqlite3.connect(db_path)
    conn.execute('PRAGMA foreign_keys = ON')
    try:
        cur = conn.execute(
            'SELECT id, published_by, published_at FROM published_runs '
            'WHERE project=? AND block=? AND phase=? AND milestone=?',
            (project, block, phase, milestone))
        existing = cur.fetchone()
        if existing and not override:
            raise ConflictError(
                f'({project}, {block}, {phase}, {milestone}) is already '
                f'published by {existing[1]} at {existing[2]}. '
                f'Use --override to replace.')

        if existing:
            # CASCADE deletes children of the old row.
            conn.execute('DELETE FROM published_runs WHERE id=?', (existing[0],))

        cur = conn.execute("""
            INSERT INTO published_runs(
                project, block, phase, milestone,
                run_id, run_dir, race_db_path,
                release_tag, release_dir,
                released_by, released_at,
                published_by, published_at,
                verdict, closability_pct)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            project, block, phase, milestone,
            payload.get('run_id'), payload.get('run_dir'),
            payload.get('race_db_path'),
            payload.get('release_tag'), payload.get('release_dir'),
            payload.get('released_by'), payload.get('released_at'),
            payload['published_by'], _now(),
            payload.get('verdict', 'UNKNOWN'),
            payload.get('closability_pct'),
        ))
        pid = cur.lastrowid

        for m in payload.get('metrics') or []:
            conn.execute("""
                INSERT INTO run_metrics(published_run_id, category, name,
                    value, unit, scenario, corner)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (pid, m.get('category'), m.get('name'), _to_str(m.get('value')),
                  m.get('unit'), m.get('scenario'), m.get('corner')))

        for c in payload.get('checklist') or []:
            conn.execute("""
                INSERT INTO run_checklist(published_run_id, milestone, category,
                    check_name, check_type, status, metric_value, threshold,
                    severity, detail)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (pid, c.get('milestone'), c.get('category'), c.get('check_name'),
                  c.get('check_type'), c.get('status'),
                  _to_str(c.get('metric_value')), _to_str(c.get('threshold')),
                  c.get('severity'), c.get('detail')))

        for f in payload.get('files') or []:
            conn.execute("""
                INSERT INTO run_files(published_run_id, kind, rel_path, sha256)
                VALUES (?, ?, ?, ?)
            """, (pid, f.get('kind'), f.get('rel_path'), f.get('sha256')))

        # Timing snapshot — first N paths per clock group. Self-contained
        # (each instance carries its own x/y) so rendering doesn't depend
        # on the cells layer surviving the downsample.
        timing = payload.get('timing') or {}
        if timing.get('clock_groups'):
            # Reuse writer for consistency (no ON CONFLICT since we just
            # inserted the row above, so DELETE is a cheap no-op).
            set_timing(db_path, pid, timing)

        # Floorplan snapshot (DEF + LEF macro dims). Stored as JSON blobs
        # because canvas-side rendering doesn't need relational queries.
        fp = payload.get('floorplan') or {}
        d = fp.get('def') or {}
        if fp.get('def_path') or d.get('boundary') or d.get('cells'):
            density = d.get('density') or {}
            total_cells = density.get('total') or len(d.get('cells') or [])
            conn.execute("""
                INSERT INTO run_floorplan(published_run_id, def_path, units,
                    boundary_json, rows_json, cells_json, macros_json,
                    lef_paths_json, downsampled, density_json, total_cells)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                pid, fp.get('def_path'), d.get('units'),
                json.dumps(d.get('boundary') or {}),
                json.dumps(d.get('rows') or []),
                json.dumps(d.get('cells') or []),
                json.dumps(fp.get('macros') or {}),
                json.dumps(fp.get('lef_paths') or []),
                1 if d.get('downsampled') else 0,
                json.dumps(density),
                total_cells,
            ))

        conn.commit()
        return pid
    finally:
        conn.close()


def unpublish(db_path, project, block, phase, milestone):
    """Remove a single cell (cascades child tables). Returns count removed."""
    conn = sqlite3.connect(db_path)
    conn.execute('PRAGMA foreign_keys = ON')
    try:
        cur = conn.execute(
            'DELETE FROM published_runs '
            'WHERE project=? AND block=? AND phase=? AND milestone=?',
            (project, block, phase, milestone))
        conn.commit()
        return cur.rowcount
    finally:
        conn.close()


# ─── Readers ────────────────────────────────────────────────────────────────

def get_project_info(db_path, project):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        row = conn.execute('SELECT * FROM project_info WHERE project=?',
                           (project,)).fetchone()
        return dict(row) if row else {}
    finally:
        conn.close()


def list_blocks(db_path, project):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(
            'SELECT * FROM blocks WHERE project=? ORDER BY block_name',
            (project,)).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def list_published(db_path, project):
    """Every published cell — no children, use `get_published(id)` for detail."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute("""
            SELECT * FROM published_runs
            WHERE project=?
            ORDER BY block, phase, milestone
        """, (project,)).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_published(db_path, published_run_id):
    """Full detail: row + metrics + checklist + files."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        row = conn.execute('SELECT * FROM published_runs WHERE id=?',
                           (published_run_id,)).fetchone()
        if not row:
            return None
        pr = dict(row)
        pr['metrics'] = [dict(r) for r in conn.execute(
            'SELECT * FROM run_metrics WHERE published_run_id=?',
            (published_run_id,)).fetchall()]
        pr['checklist'] = [dict(r) for r in conn.execute(
            'SELECT * FROM run_checklist WHERE published_run_id=?',
            (published_run_id,)).fetchall()]
        pr['files'] = [dict(r) for r in conn.execute(
            'SELECT * FROM run_files WHERE published_run_id=?',
            (published_run_id,)).fetchall()]
        fp_row = conn.execute(
            'SELECT * FROM run_floorplan WHERE published_run_id=?',
            (published_run_id,)).fetchone()
        pr['has_floorplan'] = bool(fp_row)
        tim_row = conn.execute(
            'SELECT n_paths, n_groups FROM run_timing WHERE published_run_id=?',
            (published_run_id,)).fetchone()
        pr['has_timing'] = bool(tim_row)
        pr['n_paths']   = tim_row['n_paths']   if tim_row else 0
        pr['n_groups']  = tim_row['n_groups']  if tim_row else 0
        return pr
    finally:
        conn.close()


def get_timing(db_path, published_run_id):
    """Return {clock_groups: [...], units, n_groups, n_paths} or None."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        row = conn.execute(
            'SELECT * FROM run_timing WHERE published_run_id=?',
            (published_run_id,)).fetchone()
        if not row:
            return None
        payload = json.loads(row['groups_json'] or '{"clock_groups":[]}')
        payload['units']   = row['units'] or 1000
        payload['n_groups'] = row['n_groups'] or 0
        payload['n_paths']  = row['n_paths']  or 0
        return payload
    finally:
        conn.close()


def set_timing(db_path, published_run_id, timing):
    """Overwrite the timing snapshot for one publish.

    `timing` shape:
      {
        "units": 1000,
        "clock_groups": [
          {
            "name": "clk_core",
            "paths": [
              {"index": 1, "type": "max",
               "slack": -0.087, "arrival": 1.234, "required": 1.147,
               "start": "U01", "end": "U24",
               "instances": [
                  {"name": "U01", "x": 5000, "y": 0},
                  {"name": "U24", "x": 70000, "y": 0}
               ]},
              ...
            ]
          }
        ]
      }
    """
    if not timing or not timing.get('clock_groups'):
        return
    groups = timing['clock_groups']
    n_paths = sum(len(g.get('paths') or []) for g in groups)
    conn = sqlite3.connect(db_path)
    try:
        conn.execute(
            'DELETE FROM run_timing WHERE published_run_id=?',
            (published_run_id,))
        conn.execute(
            'INSERT INTO run_timing(published_run_id, units, n_groups, '
            'n_paths, groups_json) VALUES (?, ?, ?, ?, ?)',
            (published_run_id, timing.get('units') or 1000,
             len(groups), n_paths,
             json.dumps({'clock_groups': groups})))
        conn.commit()
    finally:
        conn.close()


def get_floorplan(db_path, published_run_id):
    """Return the parsed floorplan for a canvas — de-JSON'd blobs.

    Returns None if no floorplan was captured for this row.
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        row = conn.execute(
            'SELECT * FROM run_floorplan WHERE published_run_id=?',
            (published_run_id,)).fetchone()
        if not row:
            return None
        # Older rows may not have density_json / total_cells columns filled.
        density_raw = None
        total_cells = None
        try:
            density_raw = row['density_json']
        except (IndexError, KeyError):
            pass
        try:
            total_cells = row['total_cells']
        except (IndexError, KeyError):
            pass
        return {
            'def_path': row['def_path'] or '',
            'units': row['units'] or 1000,
            'downsampled': bool(row['downsampled']),
            'boundary': json.loads(row['boundary_json'] or '{}'),
            'rows':     json.loads(row['rows_json']     or '[]'),
            'cells':    json.loads(row['cells_json']    or '[]'),
            'macros':   json.loads(row['macros_json']   or '{}'),
            'lef_paths': json.loads(row['lef_paths_json'] or '[]'),
            'density':  json.loads(density_raw or '{}'),
            'total_cells': total_cells,
        }
    finally:
        conn.close()


# ─── Helpers ────────────────────────────────────────────────────────────────

def _to_str(v):
    """SQLite tolerates None/int/float/str; force everything else to str."""
    if v is None:
        return None
    if isinstance(v, (int, float, str)):
        return v
    return str(v)
