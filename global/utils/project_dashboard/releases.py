"""Release status for the SmartGrid project page — exit-centric.

Reads the project's release area on disk — the layout `release_utils.tcl`
writes:

    <project(release,path)>/<phase>/<block>/<FLOW>/<tag>/<release(marker,manifest)>
                                                     /<release(marker,complete)>

and rolls it up per phase against the project's design hierarchy and the
phase's exits (project(phase_exits)):

  * scan       — every release dir of a block: flow, tag, exit (the tag when it
                 is one of the phase's exits; <EXIT>_<VARIANT> e.g. PRO_EXIT_HIER
                 for a variant of it; anything else is an "other" release —
                 SYNTH tags, scratch), complete marker, timestamp, verdict
                 (metrics.rpt "Status :").
  * classify   — per block and exit: the implementation release (any of the
                 exit's implementation flows — release_tags(<exit>)
                 required_flows minus the signoff flows), the signoff releases
                 (STA / PV / LEC … — flow(release,signoff_flows)), which of the
                 signoff every exit needs (project(release,exit_signoff_flows))
                 are missing, and whether the exit was released in phase order.
  * roll up    — per phase: per exit how many blocks released it / have all
                 its signoff; per level; the highest exit each block reached.

Only blocks declared in `project(design_hierarchy)` count; stray directories
in the release area are ignored.
"""

import json
import os
import re

import dash_config
from core import release_exits

_STATUS_RE = re.compile(r'^Status\s*:\s*(\S+)', re.M)


# ── Scan ─────────────────────────────────────────────────────────────────────

def _manifest_ts(tag_dir):
    """Timestamp from MANIFEST.json, else the directory mtime."""
    path = os.path.join(tag_dir, dash_config.release_name('marker,manifest'))
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            ts = json.load(f).get('timestamp') or ''
        if ts:
            return ts
    except (OSError, ValueError):
        pass
    try:
        from datetime import datetime
        return datetime.fromtimestamp(os.path.getmtime(tag_dir)).isoformat(timespec='seconds')
    except OSError:
        return ''


def _verdict(tag_dir):
    """Signoff verdict a release recorded (metrics.rpt 'Status : X'), or ''."""
    try:
        with open(os.path.join(tag_dir, 'metrics.rpt'), errors='replace') as f:
            m = _STATUS_RE.search(f.read())
        return m.group(1).upper() if m else ''
    except OSError:
        return ''


def classify_tag(tag, phase_exits):
    """(exit, variant) of a release tag: (tag, '') for a phase exit,
    (EXIT, VARIANT) for <EXIT>_<VARIANT>, ('', '') for any other tag."""
    if tag in phase_exits:
        return tag, ''
    for e in sorted(phase_exits, key=len, reverse=True):
        if tag.startswith(e + '_') and len(tag) > len(e) + 1:
            return e, tag[len(e) + 1:]
    return '', ''


def scan_block(phase_dir, block, phase_exits):
    """Every release of a block in a phase: [{flow, tag, exit, variant,
    complete, timestamp, verdict, path}] (layout <block>/<FLOW>/<tag>)."""
    bdir = os.path.join(phase_dir, block)
    out = []
    if not os.path.isdir(bdir):
        return out
    complete_marker = dash_config.release_name('marker,complete')
    for flow in sorted(os.listdir(bdir)):
        fdir = os.path.join(bdir, flow)
        if not os.path.isdir(fdir) or os.path.islink(fdir):
            continue                        # links: old paths of moved releases
        for tag in sorted(os.listdir(fdir)):
            td = os.path.join(fdir, tag)
            if not os.path.isdir(td) or os.path.islink(td):
                continue
            ex, var = classify_tag(tag, phase_exits)
            out.append({'flow': flow.upper(), 'tag': tag, 'exit': ex, 'variant': var,
                        'complete': os.path.isfile(os.path.join(td, complete_marker)),
                        'timestamp': _manifest_ts(td), 'verdict': _verdict(td),
                        'path': td})
    return out


# ── Classify ─────────────────────────────────────────────────────────────────

def exit_requirements(exits, signoff_flows, exit_signoff):
    """{exit: {'impl': [flows], 'signoff': [flows], 'description'}} — the
    exit's implementation flows (any one releases it: release_tags(<exit>)
    required_flows minus the signoff flows) and the signoff every exit needs
    (project(release,exit_signoff_flows))."""
    tags = release_exits.release_tags()
    bad = [f for f in exit_signoff if f not in signoff_flows]
    if bad:
        raise ValueError(f"project(release,exit_signoff_flows): {' '.join(bad)} not in "
                         f"flow(release,signoff_flows) {' '.join(signoff_flows)}")
    out = {}
    for e in exits:
        req = tags.get(e, {}).get('required_flows', [])
        out[e] = {'impl': [f for f in req if f not in signoff_flows],
                  'signoff': list(exit_signoff),
                  'description': tags.get(e, {}).get('description', '')}
    return out


def block_exits(records, exits, reqs, signoff_flows):
    """Per exit of a block: {impl, signoff, missing, extra, variants, state,
    order_ok}; plus the block's highest released exit and its other releases.

    state: full    — implementation released and every expected signoff
           impl    — implementation released, expected signoff missing
           signoff — signoff releases without an implementation release
           none    — nothing released for this exit
    order_ok: False when the implementation release exists while an earlier
    exit of the phase has none (released out of order)."""
    cells = {}
    for e in exits:
        rs = [r for r in records if r['exit'] == e and not r['variant']]
        impl = [r for r in rs if r['flow'] not in signoff_flows]
        impl_rel = max(impl, key=lambda r: (r['complete'], r['timestamp'])) if impl else None
        sign = {r['flow']: r for r in rs if r['flow'] in signoff_flows}
        missing = [f for f in reqs[e]['signoff'] if f not in sign]
        extra = [f for f in sign if f not in reqs[e]['signoff']]
        variants = [r for r in records if r['exit'] == e and r['variant']]
        if impl_rel and impl_rel['complete']:
            state = 'impl' if missing else 'full'
        elif sign:
            state = 'signoff'
        else:
            state = 'none'
        cells[e] = {'impl': impl_rel, 'signoff': sign, 'missing': missing,
                    'extra': extra, 'variants': variants, 'state': state, 'order_ok': True}
    released = [e for e in exits if cells[e]['impl'] and cells[e]['impl']['complete']]
    for i, e in enumerate(exits):
        if e in released and any(x not in released for x in exits[:i]):
            cells[e]['order_ok'] = False
    highest = released[-1] if released else ''
    nxt = next((e for e in exits if e not in released), '')
    others = [r for r in records if not r['exit']]
    return {'exits': cells, 'highest': highest, 'next': nxt,
            'released': released, 'others': others}


# ── Roll up ──────────────────────────────────────────────────────────────────

def _pct(done, total):
    return int(round(100.0 * done / total)) if total else 0


def _tree_order(hier):
    """[(block, depth)] — roots first, children depth-first."""
    order, seen = [], set()

    def walk(b, depth):
        if b in seen:
            return
        seen.add(b)
        order.append((b, depth))
        for c in hier[b]['children']:
            if c in hier:
                walk(c, depth + 1)
    for b, s in hier.items():
        if not s['parent'] or s['parent'] not in hier:
            walk(b, 0)
    for b in hier:
        walk(b, 0)
    return order


def release_stats(project, expected_flows):
    """Per-phase exit-centric release rollup. Returns {} when the project
    declares no release path or hierarchy (the page says which keys to set).
    The current phase is project(current_phase) — required."""
    rel_path = dash_config.project_value(project, 'release,path') or ''
    hier = dash_config.hierarchy(project)
    if not rel_path or not hier:
        return {}
    phases = dash_config.registry.tcl_list(dash_config.project_value(project, 'phases') or '')
    current = dash_config.require_project_value(project, 'current_phase')
    signoff_flows = dash_config.release_signoff_flows()
    exit_signoff = [f.upper() for f in dash_config.registry.tcl_list(
        dash_config.require_project_value(project, 'release,exit_signoff_flows'))]
    enabled = [f.upper() for f in (expected_flows or dash_config.expected_flows(project))]
    levels = sorted({s['level'] for s in hier.values() if s['level']})
    order = _tree_order(hier)

    out_phases = []
    for ph in phases:
        try:
            exits = release_exits.exits_for_phase(project, ph)
        except release_exits.PhaseExitsError:
            exits = []
        reqs = exit_requirements(exits, signoff_flows, exit_signoff)
        phase_dir = os.path.join(rel_path, ph)
        blocks = {}
        n_tags = 0
        for b in hier:
            recs = scan_block(phase_dir, b, exits)
            n_tags += len(recs)
            blocks[b] = block_exits(recs, exits, reqs, signoff_flows)
            blocks[b]['pct'] = _pct(len(blocks[b]['released']), len(exits))
        by_exit = [{'exit': e, 'description': reqs[e]['description'],
                    'signoff_expected': reqs[e]['signoff'],
                    'released': sum(1 for b in hier if e in blocks[b]['released']),
                    'full': sum(1 for b in hier if blocks[b]['exits'][e]['state'] == 'full'),
                    'out_of_order': sum(1 for b in hier if not blocks[b]['exits'][e]['order_ok'])}
                   for e in exits]
        by_level = []
        for lv in levels:
            lb = [b for b in hier if hier[b]['level'] == lv]
            d = sum(len(blocks[b]['released']) for b in lb)
            by_level.append({'level': lv, 'blocks': len(lb),
                             'released': sum(1 for b in lb if blocks[b]['released']),
                             'pct': _pct(d, len(lb) * len(exits))})
        done = sum(len(v['released']) for v in blocks.values())
        out_phases.append({
            'phase': ph,
            'exits': exits,
            'blocks': blocks,
            'by_exit': by_exit,
            'by_level': by_level,
            'released_blocks': sum(1 for v in blocks.values() if v['released']),
            'total_blocks': len(hier),
            'pct': _pct(done, len(hier) * len(exits)),
            'tags': n_tags,
        })
    return {'release_path': rel_path, 'current_phase': current,
            'signoff_flows': signoff_flows, 'exit_signoff': exit_signoff,
            'enabled_flows': enabled,
            'hierarchy': hier, 'tree_order': order, 'phases': out_phases}
