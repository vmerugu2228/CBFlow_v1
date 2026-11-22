"""Release-area statistics for the SmartGrid project page.

Reads the project's release area on disk — the same layout
`release_utils.tcl` writes:

    <project(release,path)>/<phase>/<block>/<tag>/MANIFEST.json
                                              /RELEASE_COMPLETE

and rolls it up per phase against the project's design hierarchy and its
enabled PD flows:

  * blocks released   — hierarchy blocks with >=1 complete release
  * completeness      — released (block, flow) pairs / expected pairs,
                        expected = every hierarchy block x every enabled PD flow
  * per level         — the same, split by DL1 / DL2 / DL3
  * per subtree       — a block plus all its descendants (bottom-up readiness)

Only blocks declared in `project(design_hierarchy)` count; stray
directories in the release area (test blocks, other projects) are ignored.
"""

import json
import os
import re

_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     os.pardir, os.pardir, os.pardir))
_TAG_RE = re.compile(r'^(?P<phase>[A-Za-z0-9]+)_(?P<flow>[A-Z][A-Z0-9_]*?)_v(?P<ver>\d+)$')


def _project_config_text(project):
    """Global project config first, PD overlay after (later wins)."""
    version = os.environ.get('PROJECT_CONFIG_VERSION', 'v1.0.0')
    bodies = []
    for disc_dir in ('global', 'PD'):
        d = os.path.join(_ROOT, disc_dir, 'config', 'project', project, version)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name.endswith('.tcl') and not name.startswith('mmmc_'):
                try:
                    with open(os.path.join(d, name), encoding='utf-8',
                              errors='replace') as f:
                        bodies.append(f.read())
                except OSError:
                    pass
    return bodies


def _grab(bodies, key):
    val = None
    for text in bodies:
        m = re.search(r'^\s*set\s+project\(' + re.escape(key)
                      + r'\)\s+(?:"([^"]*)"|\{([^}]*)\})', text, re.MULTILINE)
        if m:
            val = m.group(1) if m.group(1) is not None else m.group(2)
    return val


def _parse_hierarchy(bodies):
    """project(design_hierarchy) → {block: {level, parent, children}} in
    declaration order."""
    for text in reversed(bodies):
        m = re.search(r'^\s*set\s+project\(design_hierarchy\)\s+\{(.*?)^\}',
                      text, re.MULTILINE | re.DOTALL)
        if not m:
            continue
        body, out, i = m.group(1), {}, 0
        while True:
            mb = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*\{').search(body, i)
            if not mb:
                break
            depth, j = 1, mb.end()
            while j < len(body) and depth:
                depth += {'{': 1, '}': -1}.get(body[j], 0)
                j += 1
            entry = body[mb.end():j - 1]
            spec = {}
            for k in ('level', 'parent'):
                mk = re.search(r'\b' + k + r'\s+"([^"]*)"', entry)
                spec[k] = mk.group(1) if mk else ''
            mc = re.search(r'\bchildren\s+\{([^}]*)\}', entry)
            spec['children'] = mc.group(1).split() if mc else []
            out[mb.group(1)] = spec
            i = j
        return out
    return {}


def _read_manifest(tag_dir, tag):
    """flow + timestamp from MANIFEST.json; tolerate a malformed file by
    regex-scanning it, then by parsing the tag name."""
    flow = ts = ''
    path = os.path.join(tag_dir, 'MANIFEST.json')
    text = ''
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            text = f.read()
        m = json.loads(text)
        flow, ts = m.get('flow') or '', m.get('timestamp') or ''
    except (OSError, ValueError):
        mf = re.search(r'"flow"\s*:\s*"([^"]*)"', text)
        mt = re.search(r'"timestamp"\s*:\s*"([^"]*)"', text)
        flow = mf.group(1) if mf else ''
        ts = mt.group(1) if mt else ''
    if not flow:
        mt = _TAG_RE.match(tag)
        flow = mt.group('flow') if mt else ''
    if not ts:
        try:
            from datetime import datetime
            ts = datetime.fromtimestamp(os.path.getmtime(tag_dir)).isoformat(
                timespec='seconds')
        except OSError:
            ts = ''
    return flow.upper(), ts


def _scan_block(phase_dir, block):
    """{flow: {tag, timestamp, complete, versions}} — latest complete
    release per flow (falls back to latest incomplete)."""
    bdir = os.path.join(phase_dir, block)
    flows = {}
    if not os.path.isdir(bdir):
        return flows
    for tag in sorted(os.listdir(bdir)):
        tdir = os.path.join(bdir, tag)
        if not os.path.isdir(tdir):
            continue
        # A tag dir without MANIFEST.json is an unfinished release: shown,
        # never counted complete (RELEASE_COMPLETE is written after it).
        flow, ts = _read_manifest(tdir, tag)
        if not flow:
            continue
        complete = os.path.isfile(os.path.join(tdir, 'RELEASE_COMPLETE'))
        cur = flows.get(flow)
        versions = (cur['versions'] if cur else 0) + 1
        better = (cur is None or (complete, ts) > (cur['complete'], cur['timestamp']))
        if better:
            flows[flow] = {'tag': tag, 'timestamp': ts, 'complete': complete}
        flows[flow]['versions'] = versions
    return flows


def _pct(done, total):
    return int(round(100.0 * done / total)) if total else 0


def release_stats(project, expected_flows):
    """Per-phase release rollup. Returns {} when the project declares no
    release path or hierarchy."""
    bodies = _project_config_text(project)
    rel_path = _grab(bodies, 'release,path') or ''
    phases = (_grab(bodies, 'phases') or '').split()
    current = _grab(bodies, 'current_phase') or _grab(bodies, 'release,phase') or ''
    hier = _parse_hierarchy(bodies)
    if not rel_path or not hier:
        return {}
    expected = [f.upper() for f in expected_flows]
    levels = sorted({s['level'] for s in hier.values() if s['level']})

    def descendants(b):
        out = []
        for c in hier.get(b, {}).get('children', []):
            if c in hier:
                out.append(c)
                out.extend(descendants(c))
        return out

    # Tree order: roots first, children depth-first
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

    out_phases = []
    for ph in phases:
        phase_dir = os.path.join(rel_path, ph)
        blocks = {}
        for b in hier:
            rel = _scan_block(phase_dir, b)
            done = [f for f in expected if f in rel and rel[f]['complete']]
            blocks[b] = {'flows': rel, 'done': done,
                         'extra': sorted(f for f in rel if f not in expected),
                         'pct': _pct(len(done), len(expected))}
        for b in hier:
            sub = [b] + descendants(b)
            d = sum(len(blocks[x]['done']) for x in sub)
            blocks[b]['subtree_pct'] = _pct(d, len(sub) * len(expected))
        by_level = []
        for lv in levels:
            lb = [b for b in hier if hier[b]['level'] == lv]
            d = sum(len(blocks[b]['done']) for b in lb)
            by_level.append({'level': lv, 'blocks': len(lb),
                             'released': sum(1 for b in lb if blocks[b]['done']),
                             'pct': _pct(d, len(lb) * len(expected))})
        flow_cov = [{'flow': f,
                     'released': sum(1 for b in hier if f in blocks[b]['done'])}
                    for f in expected]
        done_pairs = sum(len(v['done']) for v in blocks.values())
        n_tags = sum(v.get('versions', 0) for bl in blocks.values()
                     for v in bl['flows'].values())
        out_phases.append({
            'phase': ph,
            'blocks': blocks,
            'released_blocks': sum(1 for v in blocks.values() if v['done']),
            'total_blocks': len(hier),
            'pct': _pct(done_pairs, len(hier) * len(expected)),
            'by_level': by_level,
            'flow_coverage': flow_cov,
            'tags': n_tags,
        })
    return {'release_path': rel_path, 'current_phase': current,
            'expected_flows': expected, 'hierarchy': hier,
            'tree_order': order, 'phases': out_phases}
