"""Project schedule config — global/config/project/<proj>/<ver>/schedule_config.tcl

Data-only TCL (no procs), the source of the SmartGrid schedule page. It
holds dates only; which phases exist and which exits each phase has come
from the project config (project(phases), project(phase_exits)):

    set schedule(start_date)         "2026-11-21"
    set schedule(tapeout_date)       "2027-03-31"
    set schedule(block_lead_days)    7                 ;# each level releases this much before its parent
    set schedule(P0,FP_EXIT)         "2026-12-05"      ;# <phase>,<exit>

Block date = phase exit − block_lead_days × (levels below the top block).
Nothing here has a built-in default: missing values are reported, not filled.
"""

import os
import re
import shutil
from datetime import date, datetime, timedelta

import dash_config

registry = dash_config.registry
_SET_RE = re.compile(r'^\s*set\s+schedule\(([^)]+)\)\s+(?:"([^"]*)"|\{([^}]*)\}|(\S+))',
                     re.MULTILINE)


def path(project):
    return os.path.join(registry.root(), 'global', 'config', 'project', project,
                        registry.config_version('PROJECT_CONFIG_VERSION'),
                        'schedule_config.tcl')


def load(project):
    """{key: value} from schedule_config.tcl; {} when the file is absent."""
    p = path(project)
    if not os.path.isfile(p):
        return {}
    with open(p, encoding='utf-8', errors='replace') as f:
        text = f.read()
    out = {}
    for m in _SET_RE.finditer(text):
        val = next(g for g in m.groups()[1:] if g is not None)
        out[m.group(1).strip()] = val
    return out


def parse_date(v):
    try:
        return date.fromisoformat((v or '')[:10])
    except (TypeError, ValueError):
        return None


def lead_days(data):
    """schedule(block_lead_days) as int, or None when unset/invalid."""
    try:
        v = int(str(data.get('block_lead_days', '')).strip())
        return v if v >= 0 else None
    except ValueError:
        return None


def depths(hier):
    """Levels below the top block, per block."""
    def depth(b, seen=()):
        p = hier.get(b, {}).get('parent') or ''
        return 0 if (not p or p not in hier or p in seen) else 1 + depth(p, seen + (b,))
    return {b: depth(b) for b in hier}


def block_date(phase_exit, depth, lead):
    """Each hierarchy level releases `lead` days before its parent."""
    if phase_exit is None or lead is None:
        return None
    return phase_exit - timedelta(days=lead * depth)


def validate(data, phase_exits):
    """Errors (empty = OK). phase_exits = {phase: [exits]} in phase order.
    Every date present and valid; start < tapeout; exits increase within a
    phase; a phase starts after the previous one ends; nothing after
    tapeout; block_lead_days a whole number >= 0."""
    errs = []
    s, t = parse_date(data.get('start_date')), parse_date(data.get('tapeout_date'))
    if not s or not t:
        errs.append('start_date and tapeout_date must be YYYY-MM-DD')
    elif s >= t:
        errs.append('start_date must be before tapeout_date')
    if lead_days(data) is None:
        errs.append('block_lead_days must be a whole number of days >= 0')
    prev_last = None
    for ph, exits in phase_exits.items():
        prev = None
        for ex in exits:
            d = parse_date(data.get(f'{ph},{ex}'))
            if d is None:
                errs.append(f'{ph} {ex}: missing or invalid date')
                continue
            if prev and d < prev[1]:
                errs.append(f'{ph} {ex} ({d}) is before {ph} {prev[0]} ({prev[1]})')
            if prev is None and prev_last and d < prev_last:
                errs.append(f'{ph} {ex} ({d}) is before the end of the previous phase '
                            f'({prev_last})')
            if t and d > t:
                errs.append(f'{ph} {ex} ({d}) is after tapeout ({t})')
            prev = (ex, d)
        if prev:
            prev_last = prev[1]
    return errs


def tapeout_mismatch(project, data):
    """Warning text when schedule(tapeout_date) differs from the project's
    tapeout (project(tapeout_date), the single source for tapeout), else ''."""
    sched_t = (data or {}).get('tapeout_date') or ''
    proj_t = dash_config.project_value(project, 'tapeout_date') or ''
    if sched_t and sched_t != proj_t:
        return (f'schedule(tapeout_date) {sched_t} differs from project(tapeout_date) '
                f'{proj_t or "(not set)"} — the project config is the tapeout of record')
    return ''


def warnings(data, hier, phase_exits):
    """Non-blocking: auto-populated leaf dates before the project start."""
    out = []
    s, lead = parse_date(data.get('start_date')), lead_days(data)
    if not (s and hier and phase_exits) or lead is None:
        return out
    deepest = max(depths(hier).values())
    first_phase = next(iter(phase_exits))
    for ex in phase_exits[first_phase]:
        d = block_date(parse_date(data.get(f'{first_phase},{ex}')), deepest, lead)
        if d and d < s:
            out.append(f'{first_phase} {ex}: leaf blocks would be due {d}, before the '
                       f'project start {s} ({deepest} levels × {lead} days lead)')
    return out


def allowed_key(key, phase_exits):
    if key in ('start_date', 'tapeout_date', 'block_lead_days'):
        return True
    parts = key.split(',')
    return len(parts) == 2 and parts[1] in phase_exits.get(parts[0], ())


def save(project, data, phase_exits, user=''):
    """Write schedule_config.tcl (previous copy → backup/<name>.<ts>.bak).
    Only keys valid for the current phase_exits are written."""
    p = path(project)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if os.path.isfile(p):
        bdir = os.path.join(os.path.dirname(p), 'backup')
        os.makedirs(bdir, exist_ok=True)
        shutil.copy2(p, os.path.join(
            bdir, f'schedule_config.tcl.{datetime.now():%Y%m%d-%H%M%S}.bak'))

    def line(key, val, quote=True):
        return f'{"set schedule(" + key + ")":<36} ' + (f'"{val}"' if quote else str(val))
    out = [
        '#!/usr/bin/env tclsh',
        '# ' + '═' * 77,
        f'# CBflow schedule — {project}',
        '# Source of the SmartGrid schedule page. Data only (no procs).',
        '# Dates only: phases and the exits each phase has come from the project',
        '# config (project(phases), project(phase_exits)). Block dates are',
        '# auto-populated: each hierarchy level releases block_lead_days before its',
        '# parent (block date = phase exit − block_lead_days × levels below the top).',
        '# Edit here or in SmartGrid (Schedule → Edit); the previous version is kept',
        '# in backup/ on every SmartGrid save.',
        f'# Last written {datetime.now():%Y-%m-%d %H:%M:%S}' + (f' by {user}' if user else ''),
        '# ' + '═' * 77,
        '',
        line('start_date', data.get('start_date', '')),
        line('tapeout_date', data.get('tapeout_date', '')),
        line('block_lead_days', lead_days(data), quote=False),
        '',
        '# ── Phase exits: schedule(<phase>,<exit>) ──────────────────────────────',
    ]
    for ph, exits in phase_exits.items():
        out += [line(f'{ph},{ex}', data.get(f'{ph},{ex}', '')) for ex in exits]
        out.append('')
    tmp = p + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out).rstrip() + '\n')
    os.replace(tmp, p)
    return p
