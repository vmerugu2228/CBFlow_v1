"""File-backed registry of runs known to the dashboard daemon.

One JSON file per run under ~/.cbflow/dashboard/runs/<run_id>.json.

Schema:
  { "run_id":        "<md5(canonical run_dir)[:12]>",
    "run_dir":       "<absolute canonical path>",
    "registered_at": "<iso8601>",
    "last_seen_at":  "<iso8601>",
    "owner_uid":     <int>,
    "flow_type":     "<from .run.cbflow.env, cached for display only>",
    "archived":      false }

Atomic writes via tempfile + os.rename. No global lock — the per-file write
pattern keeps register/list races benign (workers and the daemon never write
to the same registry file concurrently in practice).
"""

import hashlib
import json
import os
import tempfile
from datetime import datetime
from pathlib import Path

import state_paths


def run_id_for(run_dir):
    """Canonicalize then hash. Same basis as race_dashboard._get_run_port."""
    canonical = os.path.realpath(os.path.abspath(run_dir))
    return hashlib.md5(canonical.encode()).hexdigest()[:12]


def _path_for(run_id):
    return os.path.join(state_paths.runs_dir(), f'{run_id}.json')


def _read_env_field(run_dir, key):
    env_file = os.path.join(run_dir, '.run.cbflow.env')
    if not os.path.exists(env_file):
        return ''
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line.startswith('export ') and '=' in line:
                k, v = line[7:].split('=', 1)
                if k == key:
                    return v.strip('"').strip("'")
    return ''


def register(run_dir):
    """Insert-or-update a run. Returns the registry record."""
    canonical = os.path.realpath(os.path.abspath(run_dir))
    rid = run_id_for(canonical)
    now = datetime.now().isoformat(timespec='seconds')

    existing = _load(rid) or {}
    record = {
        'run_id': rid,
        'run_dir': canonical,
        'registered_at': existing.get('registered_at', now),
        'last_seen_at': now,
        'owner_uid': existing.get('owner_uid', os.getuid()),
        'flow_type': _read_env_field(canonical, 'CBFLOW_FLOW_TYPE') or existing.get('flow_type', ''),
        'project': _read_env_field(canonical, 'CBFLOW_PROJECT_NAME') or existing.get('project', ''),
        'design': _read_env_field(canonical, 'CBFLOW_DESIGN_NAME') or existing.get('design', ''),
        'phase': _read_env_field(canonical, 'CBFLOW_PROJECT_PHASE') or existing.get('phase', ''),
        'tech': _read_env_field(canonical, 'TECH_NAME') or existing.get('tech', ''),
        'archived': False,
    }
    _atomic_write(rid, record)
    return record


def deregister(run_id_or_dir):
    """Remove a registry entry by run_id or run_dir. Returns True on delete."""
    rid = run_id_or_dir
    if os.sep in run_id_or_dir or '/' in run_id_or_dir:
        rid = run_id_for(run_id_or_dir)
    p = _path_for(rid)
    if os.path.exists(p):
        os.unlink(p)
        return True
    return False


def get(run_id):
    return _load(run_id)


def list_all():
    """Every registry record on disk (active + archived)."""
    out = []
    for f in sorted(Path(state_paths.runs_dir()).glob('*.json')):
        rec = _load(f.stem)
        if rec:
            out.append(rec)
    return out


def list_active():
    return [r for r in list_all() if not r.get('archived')]


def mark_archived(run_id, archived=True):
    rec = _load(run_id)
    if not rec:
        return False
    rec['archived'] = bool(archived)
    _atomic_write(run_id, rec)
    return True


def touch(run_id):
    """Bump last_seen_at."""
    rec = _load(run_id)
    if not rec:
        return False
    rec['last_seen_at'] = datetime.now().isoformat(timespec='seconds')
    _atomic_write(run_id, rec)
    return True


# ── internals ───────────────────────────────────────────────────────────────

def _load(run_id):
    p = _path_for(run_id)
    if not os.path.exists(p):
        return None
    try:
        with open(p) as f:
            rec = json.load(f)
    except (OSError, ValueError):
        return None
    # Lazy backfill for pre-schema records. Upgrade in place so subsequent
    # reads are cheap. Silent on any failure (best-effort).
    needed = ('project', 'design', 'phase', 'tech')
    if any(not rec.get(k) for k in needed):
        run_dir = rec.get('run_dir', '')
        if run_dir and os.path.isdir(run_dir):
            changed = False
            for key, env in (('project', 'CBFLOW_PROJECT_NAME'),
                             ('design',  'CBFLOW_DESIGN_NAME'),
                             ('phase',   'CBFLOW_PROJECT_PHASE'),
                             ('tech',    'TECH_NAME')):
                if not rec.get(key):
                    v = _read_env_field(run_dir, env)
                    if v:
                        rec[key] = v
                        changed = True
            if changed:
                try:
                    _atomic_write(run_id, rec)
                except OSError:
                    pass
    return rec


def _atomic_write(run_id, record):
    p = _path_for(run_id)
    d = os.path.dirname(p)
    fd, tmp = tempfile.mkstemp(prefix=f'.{run_id}.', suffix='.json', dir=d)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(record, f, indent=2, sort_keys=True)
        os.chmod(tmp, 0o600)
        os.rename(tmp, p)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
