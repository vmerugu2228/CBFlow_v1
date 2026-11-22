"""Project schedule config — global/config/project/<proj>/<ver>/schedule_config.tcl

Data-only TCL (no procs), the single source of the SmartGrid schedule page.
Only the project and phase schedule is configured; block dates are
auto-populated from the design hierarchy:

    set schedule(start_date)         "2026-11-21"
    set schedule(tapeout_date)       "2027-03-31"
    set schedule(phases)             {P0 P1 P2 P3}
    set schedule(exits)              {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
    set schedule(block_lead_days)    7                 ;# each level releases this much before its parent
    set schedule(P0,FP_EXIT)         "2026-11-26"      ;# <phase>,<exit>

Block date = phase exit − block_lead_days × (levels below the top block).

`derive()` seeds a complete schedule (phases split start → tapeout, exits
evenly inside each phase); `validate()` enforces the ordering rules before
`save()` writes the file.
"""

import os
import re
import shutil
from datetime import date, datetime, timedelta

_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     os.pardir, os.pardir, os.pardir))
_SET_RE = re.compile(r'^\s*set\s+schedule\(([^)]+)\)\s+(?:"([^"]*)"|\{([^}]*)\}|(\S+))',
                     re.MULTILINE)
DEFAULT_LEAD_DAYS = 7


def path(project):
    version = os.environ.get('PROJECT_CONFIG_VERSION', 'v1.0.0')
    return os.path.join(_ROOT, 'global', 'config', 'project', project, version,
                        'schedule_config.tcl')


def load(project):
    """{key: value} from schedule_config.tcl; {} when the file is absent.
    List values (phases, exits) come back as Python lists."""
    p = path(project)
    if not os.path.isfile(p):
        return {}
    with open(p, encoding='utf-8', errors='replace') as f:
        text = f.read()
    out = {}
    for m in _SET_RE.finditer(text):
        key = m.group(1).strip()
        if m.group(3) is not None:
            out[key] = m.group(3).split()
        else:
            out[key] = m.group(2) if m.group(2) is not None else m.group(4)
    return out


def parse_date(v):
    try:
        return date.fromisoformat((v or '')[:10])
    except (TypeError, ValueError):
        return None


def lead_days(data):
    try:
        return max(0, int(data.get('block_lead_days', DEFAULT_LEAD_DAYS)))
    except (TypeError, ValueError):
        return DEFAULT_LEAD_DAYS


def depths(hier):
    """Levels below the top block, per block."""
    def depth(b, seen=()):
        p = hier.get(b, {}).get('parent') or ''
        return 0 if (not p or p not in hier or p in seen) else 1 + depth(p, seen + (b,))
    return {b: depth(b) for b in hier}


def block_date(phase_exit, depth, lead):
    """Auto-populated block date: each hierarchy level releases `lead`
    days before its parent."""
    return phase_exit - timedelta(days=lead * depth) if phase_exit else None


def derive(start, tapeout, phases, exits):
    """Complete project/phase schedule from start/tapeout.
    Phase i spans [start + span*i/n, start + span*(i+1)/n]; exit j sits at
    phase_start + phase_len*(j+1)/len(exits) (the last exit closes the phase)."""
    data = {'start_date': start.isoformat(), 'tapeout_date': tapeout.isoformat(),
            'phases': list(phases), 'exits': list(exits),
            'block_lead_days': str(DEFAULT_LEAD_DAYS)}
    span = (tapeout - start).days
    n = len(phases)
    for i, ph in enumerate(phases):
        p0 = start + timedelta(days=round(span * i / n))
        p1 = start + timedelta(days=round(span * (i + 1) / n))
        for j, ex in enumerate(exits):
            data[f'{ph},{ex}'] = (p0 + timedelta(
                days=round((p1 - p0).days * (j + 1) / len(exits)))).isoformat()
    return data


def validate(data, hier):
    """Ordering rules; returns a list of error strings (empty = OK):
    start < tapeout; exits increase within a phase; a phase starts after
    the previous one ends; the last exit is not after tapeout."""
    errs = []
    s, t = parse_date(data.get('start_date')), parse_date(data.get('tapeout_date'))
    if not s or not t:
        errs.append('start_date and tapeout_date must be YYYY-MM-DD')
    elif s >= t:
        errs.append('start_date must be before tapeout_date')
    try:
        if int(data.get('block_lead_days', DEFAULT_LEAD_DAYS)) < 0:
            errs.append('block_lead_days must be >= 0')
    except (TypeError, ValueError):
        errs.append('block_lead_days must be a whole number of days')
    phases, exits = data.get('phases') or [], data.get('exits') or []
    prev_last = None
    for ph in phases:
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
            prev = (ex, d)
        if prev:
            prev_last = prev[1]
    if t and phases and exits:
        last = parse_date(data.get(f'{phases[-1]},{exits[-1]}'))
        if last and last > t:
            errs.append(f'{phases[-1]} {exits[-1]} ({last}) is after tapeout ({t})')
    return errs


def warnings(data, hier):
    """Non-blocking schedule warnings: auto-populated leaf dates that fall
    before the project start."""
    out = []
    s = parse_date(data.get('start_date'))
    phases, exits = data.get('phases') or [], data.get('exits') or []
    if not (s and phases and exits and hier):
        return out
    deepest = max(depths(hier).values())
    lead = lead_days(data)
    for ex in exits:
        d = block_date(parse_date(data.get(f'{phases[0]},{ex}')), deepest, lead)
        if d and d < s:
            out.append(f'{phases[0]} {ex}: leaf blocks would be due {d}, before the '
                       f'project start {s} ({deepest} levels × {lead} days lead)')
    return out


def allowed_key(key, phases, exits):
    if key in ('start_date', 'tapeout_date', 'block_lead_days'):
        return True
    parts = key.split(',')
    return len(parts) == 2 and parts[0] in phases and parts[1] in exits


def save(project, data, user=''):
    """Write schedule_config.tcl (previous copy → backup/<name>.<ts>.bak)."""
    p = path(project)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    if os.path.isfile(p):
        bdir = os.path.join(os.path.dirname(p), 'backup')
        os.makedirs(bdir, exist_ok=True)
        shutil.copy2(p, os.path.join(
            bdir, f'schedule_config.tcl.{datetime.now():%Y%m%d-%H%M%S}.bak'))
    phases, exits = data.get('phases') or [], data.get('exits') or []

    def line(key, val, quote=True):
        k = f'set schedule({key})'
        if isinstance(val, list):
            v = '{' + ' '.join(val) + '}'
        else:
            v = f'"{val}"' if quote else str(val)
        return f'{k:<36} {v}'
    out = [
        '#!/usr/bin/env tclsh',
        '# ' + '═' * 77,
        f'# CBflow schedule — {project}',
        '# Source of the SmartGrid schedule page. Data only (no procs).',
        '# Only the project + phase schedule lives here; block dates are',
        '# auto-populated: each hierarchy level releases block_lead_days before its',
        '# parent (block date = phase exit − block_lead_days × levels below the top).',
        '# Edit here or in SmartGrid (Schedule → Edit); the previous version is kept',
        '# in backup/ on every SmartGrid save.',
        f'# Last written {datetime.now():%Y-%m-%d %H:%M:%S}' + (f' by {user}' if user else ''),
        '# ' + '═' * 77,
        '',
        line('start_date', data.get('start_date', '')),
        line('tapeout_date', data.get('tapeout_date', '')),
        line('phases', phases),
        line('exits', exits),
        line('block_lead_days', lead_days(data), quote=False),
        '',
        '# ── Phase exits: schedule(<phase>,<exit>) ──────────────────────────────',
    ]
    for ph in phases:
        out += [line(f'{ph},{ex}', data.get(f'{ph},{ex}', '')) for ex in exits]
        out.append('')
    tmp = p + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out).rstrip() + '\n')
    os.replace(tmp, p)
    return p
