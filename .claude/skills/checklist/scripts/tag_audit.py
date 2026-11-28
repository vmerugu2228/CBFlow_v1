#!/usr/bin/env python3
"""Tag / dependency audit of a project's releases (read-only).

    python3 tag_audit.py --project opensky [--phase P3] [--blocks gcd ctrl_subsys]
                         [--json out.json] [--quiet]

Every release <project(release,path)>/<phase>/<block>/<FLOW>/<tag>/RELEASE_COMPLETE
is traced to the releases it consumed. Inputs come from the release's run
(MANIFEST.json run_dir -> setup/user_config.tcl + override_config*.tcl):
  <arr>(input,<x>_release_tag) / <arr>(input,release_tag)  -> source flow from
      flow_input_handshake(<FLOW>,<x>) (release_config.tcl; ANY = the
      implementation flow that carries the tag), else the one flow holding the tag;
  <arr>(input,<x>) paths into the release area           -> that release;
  <arr>(input,from_run)                                     -> a run, not a release;
  project(lib_config_tag)                                   -> the library tag.
Without a run, MANIFEST signoff_status.upstream_tags are used (flow guessed).

Checks (ERROR blocks the exit, WARN needs a decision, INFO is context):
  MISSING_INPUT    consumed tag / path not released                   ERROR
  STALE_INPUT      upstream re-released after this release was built   ERROR
  STALE_UPSTREAM   an upstream is itself stale (transitive)            ERROR
  NEWER_VERSION    a newer release of the same exit exists in the phase
                   (PNR/PRO_EXIT -> ECO/PRO_EXIT_ECO1, _v1 -> _v2)       WARN
  VERSION_PINNED   the release's current version is not its latest
                   (cbflow flow release candidate set)                 INFO
  LATER_PHASE      the same exit is released in a later phase          INFO
  RTL_NOT_SIGNED   RTL / filelist read outside a signed-off release    WARN
  FROM_RUN         input read from a run dir (not reproducible)        WARN
  PHASE_MIX        input from another phase                            INFO
  LIBTAG_MISSING   project(lib_config_tag) has no tag dir              ERROR
  LIBTAG_MIX       PD / DFT releases of one block's chain use
                   different library tags                              WARN
  LIBTAG_OLD       a newer library tag exists                          INFO
  SIGNOFF_SPLIT    signoff flows of one exit read different
                   implementation releases                             ERROR
  CHILD_MISSING    a child block is not in the parent's library tag    ERROR
  CHILD_STALE      the tag's copy of a child is older than the child's
                   release (re-released after the tag copied it)       ERROR
  CHILD_OLD        the tag carries a child release with a newer release
                   of the same exit in that phase                      WARN
  CHILD_LATER      the child is released in the parent's phase, the
                   tag carries an earlier phase                        INFO
  CHILD_PV_PENDING the tag's child gds / cdl come from PNR (no PV)     WARN
Hierarchy (CHILD_*) and library-tag mix findings are reported once per block.
Then a resolution plan: affected releases in dependency order with the run to
retrace, and the config lines to change (shown, never written).
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
RELEASE_CFG = os.path.join(ROOT, 'PD', 'config', 'flow', 'v1.0.0', 'release_config.tcl')
REGISTRY = os.path.join(ROOT, 'global', 'config', 'flow', 'v1.0.0', 'flow_registry.tcl')
IMPL_FLOWS = ['ECO', 'PNR', 'SYNTH_PNR']          # block implementation releases
ANY_ORDER = IMPL_FLOWS + ['SYNTH', 'FP', 'FCFP']  # ANY handshake: preferred sources
SEV = {'ERROR': 0, 'WARN': 1, 'INFO': 2}
sys.path.insert(0, os.path.join(ROOT, 'global', 'utils', 'commands'))
import candidate_cmd  # noqa: E402  (release versions: current / latest)


def tcl(script):
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f'tag_audit: tclsh failed: {r.stderr.strip()}')
    return r.stdout


def project_values(project):
    g = os.path.join(ROOT, 'global', 'config', 'project', project, 'v1.0.0', f'{project}_config.tcl')
    if not os.path.exists(g):
        sys.exit(f'tag_audit: no project config {g}')
    overlays = sorted(glob.glob(os.path.join(ROOT, '*', 'config', 'project', project, 'v1.0.0',
                                             f'{project}_*_config.tcl')))
    files = ' '.join('{%s}' % f for f in [g] + overlays)
    out = tcl(f'''
foreach f {{{files}}} {{ catch {{ source $f }} }}
set MILESTONE_ORDER {{}}
set fh [open {{{RELEASE_CFG}}}]; set t [read $fh]; close $fh
regexp {{set MILESTONE_ORDER \\{{([^}}]*)\\}}}} $t -> MILESTONE_ORDER
catch {{ source {{{REGISTRY}}} }}
puts "phases\\t$project(phases)"
puts "release\\t$project(release,path)"
puts "order\\t$MILESTONE_ORDER"
puts "tech\\t$project(technology)"
puts "libroot\\t[expr {{[info exists project(lib_tag_root)] ? $project(lib_tag_root) : ""}}]"
puts "libdefault\\t[expr {{[info exists project(lib_config_tag)] ? $project(lib_config_tag) : ""}}]"
puts "signoff\\t[expr {{[info exists flow(release,signoff_flows)] ? $flow(release,signoff_flows) : ""}}]"
foreach k [array names flow discipline,*] {{ puts "disc\\t[lindex [split $k ,] 1]\\t$flow($k)" }}
dict for {{b d}} $project(design_hierarchy) {{
    puts "block\\t$b\\t[dict get $d parent]\\t[dict get $d children]"
}}
''')
    cfg = {'blocks': {}, 'disc': {}}
    for line in out.splitlines():
        f = line.split('\t')
        if f[0] == 'block':
            cfg['blocks'][f[1]] = {'parent': f[2], 'children': f[3].split()}
        elif f[0] == 'disc':
            cfg['disc'][f[1]] = f[2]
        elif f[0] in ('phases', 'order', 'signoff'):
            cfg[f[0]] = f[1].split()
        else:
            cfg[f[0]] = f[1] if len(f) > 1 else ''
    return cfg


def handshake():
    """{(flow, input): source_flow} from release_config.tcl section 6."""
    hs = {}
    for f, i, s in re.findall(r'set flow_input_handshake\((\w+),(\w+)\)\s+\{(\S+)',
                              open(RELEASE_CFG).read()):
        hs.setdefault((f, i), s)
    return hs


# ── releases ────────────────────────────────────────────────────────────────
class Rel:
    def __init__(self, phase, block, flow, tag, path):
        self.phase, self.block, self.flow, self.tag, self.path = phase, block, flow, tag, path
        self.time = os.path.getmtime(os.path.join(path, 'RELEASE_COMPLETE'))
        self.manifest = {}
        mf = os.path.join(path, 'MANIFEST.json')
        if os.path.exists(mf):
            try:
                self.manifest = json.load(open(mf))
            except ValueError:
                pass
        self.run_dir = self.manifest.get('run_dir', '')
        self.inputs = []      # (key, value, upstream Rel | None, note)
        self.lib_tag = ''
        self.findings = []

    @property
    def id(self):
        return f'{self.phase}/{self.block}/{self.flow}/{self.tag}'


def scan_releases(cfg, phases, blocks):
    rels = {}
    for ph in phases:
        for rc in glob.glob(os.path.join(cfg['release'], ph, '*', '*', '*', 'RELEASE_COMPLETE')):
            path = os.path.dirname(rc)
            tag = os.path.basename(path)
            flow = os.path.basename(os.path.dirname(path))
            block = os.path.basename(os.path.dirname(os.path.dirname(path)))
            if blocks and block not in blocks:
                continue
            r = Rel(ph, block, flow, tag, path)
            rels[r.id] = r
    return rels


def all_releases(cfg):
    """Every release of every phase (upstreams may sit outside the audited set)."""
    return scan_releases(cfg, cfg['phases'], None)


def run_inputs(run_dir):
    """input keys + lib tag + release phase of a run (user_config + overrides)."""
    files = [os.path.join(run_dir, 'setup', 'user_config.tcl')]
    files += sorted(glob.glob(os.path.join(run_dir, 'setup', 'override_config*.tcl')))
    files = [f for f in files if os.path.exists(f)]
    if not files:
        return None
    src = ' '.join('{%s}' % f for f in files)
    out = tcl(f'''
foreach f {{{src}}} {{ catch {{ source $f }} }}
foreach a [info vars] {{
    if {{![array exists $a]}} continue
    foreach k [array names $a input,*] {{ puts "in\\t$a\\t$k\\t[set ${{a}}($k)]" }}
}}
foreach k {{lib_config_tag release,phase phase}} {{
    if {{[info exists project($k)]}} {{ puts "p\\t$k\\t$project($k)" }}
}}
''')
    res = {'inputs': [], 'project': {}}
    for line in out.splitlines():
        f = line.split('\t')
        if f[0] == 'in' and len(f) == 4:
            res['inputs'].append((f[1], f[2][len('input,'):], f[3]))
        elif f[0] == 'p' and len(f) == 3:
            res['project'][f[1]] = f[2]
    return res


def rel_of_path(cfg, everything, path):
    """Release a file path points into (<release>/<phase>/<block>/<FLOW>/<tag>/...)."""
    base = os.path.realpath(cfg['release']) + os.sep
    p = os.path.realpath(path)
    if not p.startswith(base):
        return None, False
    parts = p[len(base):].split(os.sep)
    if len(parts) < 4:
        return None, True
    return everything.get('/'.join(parts[:4])), True


def find_tag(everything, phase, block, tag, flows, exclude):
    """Upstream release <phase>/<block>/<flow>/<tag> among candidate flows."""
    for fl in flows:
        if fl == exclude:
            continue
        r = everything.get(f'{phase}/{block}/{fl}/{tag}')
        if r:
            return r
    return None


def resolve(cfg, everything, hs, r):
    info = run_inputs(r.run_dir) if r.run_dir and os.path.isdir(r.run_dir) else None
    flows_with = lambda tag: sorted({x.flow for x in everything.values()  # noqa: E731
                                     if x.block == r.block and x.phase == r.phase and x.tag == tag
                                     and x.flow != r.flow})
    if info is None:
        r.findings.append(('INFO', 'NO_RUN', f'run dir {r.run_dir or "(none)"} not found — '
                                              'inputs from MANIFEST upstream_tags'))
        for t in r.manifest.get('signoff_status', {}).get('upstream_tags', []):
            cands = flows_with(t)
            pick = find_tag(everything, r.phase, r.block, t, ANY_ORDER + cands, r.flow)
            r.inputs.append(('upstream_tags', t, pick, '' if pick else 'not released'))
        return
    r.lib_tag = info['project'].get('lib_config_tag', cfg.get('libdefault', ''))
    phase = info['project'].get('release,phase') or r.phase
    for arr, key, val in info['inputs']:
        if not val:
            continue
        if key == 'from_run':
            r.inputs.append((f'{arr}(input,{key})', val, None, 'run dir'))
            r.findings.append(('WARN', 'FROM_RUN', f'{arr}(input,from_run) = {val} — not a release'))
            continue
        if key.endswith('release_tag'):
            inp = key[:-len('release_tag')].rstrip('_')
            if inp:
                srcs = [hs.get((r.flow, inp))] if hs.get((r.flow, inp)) else []
            else:
                srcs = sorted({s for (f, _), s in hs.items() if f == r.flow})
            flows = []
            for s in srcs:
                flows += ANY_ORDER if s == 'ANY' else ([] if s == 'INPUTS' else [s])
            flows += flows_with(val)
            pick = find_tag(everything, phase, r.block, val, flows, r.flow)
            r.inputs.append((f'{arr}(input,{key})', val, pick, '' if pick else 'not released'))
            continue
        # explicit path(s)
        for v in str(val).split():
            if not os.path.isabs(v):
                continue
            up, inside = rel_of_path(cfg, everything, v)
            if inside:
                r.inputs.append((f'{arr}(input,{key})', v, up, '' if up else 'not released'))
            elif re.search(r'rtl|filelist', key):
                r.inputs.append((f'{arr}(input,{key})', v, None, 'outside release area'))
                r.findings.append(('WARN', 'RTL_NOT_SIGNED',
                                   f'{arr}(input,{key}) = {v} — RTL not from a signed-off '
                                   'release (LINT_SIGNOFF rtl/<d>.f)'))


# ── checks ──────────────────────────────────────────────────────────────────
def family(tag):
    """(family, version): BTO_ECO2 -> (BTO, 2); P3_SYNTH_v2 -> (P3_SYNTH, 2)."""
    m = re.match(r'^(.*)_ECO(\d+)$', tag) or re.match(r'^(.*)_v(\d+)$', tag)
    return (m.group(1), int(m.group(2))) if m else (tag, 0)


def newer_in_family(everything, cfg, up):
    fam, ver = family(up.tag)
    best = None
    for x in everything.values():
        if x.block != up.block or x.flow != up.flow or x is up:
            continue
        f2, v2 = family(x.tag)
        later_phase = cfg['phases'].index(x.phase) > cfg['phases'].index(up.phase)
        if (f2 == fam and x.phase == up.phase and v2 > ver) or (later_phase and f2 == fam):
            if best is None or (cfg['phases'].index(x.phase), family(x.tag)[1]) > \
                    (cfg['phases'].index(best.phase), family(best.tag)[1]):
                best = x
    return best


def verifies(r):
    """A release that verified the exit it is tagged with (its own tag among
    its MANIFEST upstream_tags: STA / PV / LEC / GLS BTO) — not a version."""
    return r.tag in r.manifest.get('signoff_status', {}).get('upstream_tags', [])


def newer_version(everything, up):
    """Newest release of the same exit family, phase and block produced after
    `up` (PNR/PRO_EXIT -> ECO/PRO_EXIT_ECO1, P3_SYNTH_v1 -> v2); verifiers excluded."""
    fam = family(up.tag)[0]
    c = [x for x in everything.values() if x.block == up.block and x.phase == up.phase
         and x.tag != up.tag and family(x.tag)[0] == fam and x.time > up.time + 1 and not verifies(x)]
    return max(c, key=lambda x: x.time) if c else None


def latest_impl(everything, cfg, block):
    order = cfg['order']

    def key(x):
        fam, eco = family(x.tag)
        return (cfg['phases'].index(x.phase), order.index(fam) if fam in order else -1, eco, x.time)
    c = [x for x in everything.values() if x.block == block and x.flow in IMPL_FLOWS]
    return max(c, key=key) if c else None


def lib_tag_blocks(cfg, tag):
    """{child: (release path, pv_release, tag copy mtime)} from <tag>/blocks_config.tcl."""
    d = os.path.join(cfg['libroot'], cfg['tech'], tag)
    bc = os.path.join(d, 'blocks_config.tcl')
    out = {}
    if not os.path.exists(bc):
        return out
    t = open(bc).read()
    for b, p in re.findall(r'set tech\(block,(\w+),release\)\s+"([^"]*)"', t):
        pv = re.search(r'set tech\(block,%s,pv_release\)\s+"([^"]*)"' % b, t)
        src = os.path.join(d, 'block', b, 'SOURCE')
        out[b] = (p, pv.group(1) if pv else '', os.path.getmtime(src) if os.path.exists(src) else 0)
    return out


def lib_tags_available(cfg):
    d = os.path.join(cfg['libroot'], cfg['tech'])
    tags = [os.path.basename(os.path.dirname(f)) for f in glob.glob(os.path.join(d, '*', 'lib_config.tcl'))]
    nat = lambda s: [int(x) if x.isdigit() else x for x in re.split(r'(\d+)', s)]  # noqa: E731
    return sorted(tags, key=nat)


def audit(cfg, everything, audited, block_findings):
    hs = handshake()
    for r in audited.values():
        resolve(cfg, everything, hs, r)
    for r in everything.values():
        if r.id not in audited and r.run_dir:
            r.lib_tag = r.lib_tag or ''
    tags = lib_tags_available(cfg)
    newest_tag = tags[-1] if tags else ''
    lib_disc = ('PD', 'DFT')

    for r in audited.values():
        for key, val, up, note in r.inputs:
            if up is None:
                if note == 'not released':
                    r.findings.append(('ERROR', 'MISSING_INPUT', f'{key} = {val}: not released'))
                continue
            if up.time > r.time + 1:
                r.findings.append(('ERROR', 'STALE_INPUT',
                                   f'{key} -> {up.id} re-released after this release '
                                   f'({_ts(up.time)} > {_ts(r.time)})'))
            if not verifies(up):
                fam = family(up.tag)[0]
                # an ECO of the exit (PRO_EXIT -> PRO_EXIT_ECO1) builds on the base version
                producer = family(r.tag)[0] == fam and r.tag != up.tag
                nv = newer_version(everything, up)
                if nv and not producer:
                    r.findings.append(('WARN', 'NEWER_VERSION', f'{key} -> {up.id}; newer {fam}: {nv.id}'))
                nw = newer_in_family(everything, cfg, up)
                if nw and nw.phase != up.phase:
                    r.findings.append(('INFO', 'LATER_PHASE', f'{key} -> {up.id}; also released in {nw.id}'))
            if up.phase != r.phase:
                r.findings.append(('INFO', 'PHASE_MIX', f'{key} -> {up.id} (phase {up.phase})'))
        cur, kind = candidate_cmd.current(cfg, r.phase, r.block, r.flow, r.tag)
        if kind == 'versioned':
            lp = candidate_cmd.latest_pass(candidate_cmd.versions(cfg, r.phase, r.block, r.flow, r.tag))
            if lp and lp['v'] != cur:
                r.findings.append(('INFO', 'VERSION_PINNED', f'current {cur}, latest {lp["v"]}'))
        disc = cfg['disc'].get(r.flow, '')
        if r.lib_tag and disc in lib_disc:
            if r.lib_tag not in tags:
                r.findings.append(('ERROR', 'LIBTAG_MISSING', f'project(lib_config_tag) {r.lib_tag}: '
                                   f'no {cfg["libroot"]}/{cfg["tech"]}/{r.lib_tag}/lib_config.tcl'))
            elif newest_tag and r.lib_tag != newest_tag:
                r.findings.append(('INFO', 'LIBTAG_OLD', f'library tag {r.lib_tag}; newest {newest_tag}'))

    # transitive staleness (upstream of an upstream)
    def bad(r, seen):
        if r.id in seen:
            return seen[r.id]
        seen[r.id] = None
        res = None
        for key, val, up, note in r.inputs:
            if up is None:
                continue
            if up.time > r.time + 1:
                res = up
            elif up.id in audited and bad(audited[up.id], seen):
                res = res or bad(audited[up.id], seen)
        seen[r.id] = res
        return res
    seen = {}
    for r in audited.values():
        for key, val, up, note in r.inputs:
            if up is not None and up.id in audited and up.time <= r.time + 1:
                root = bad(audited[up.id], seen)
                if root:
                    r.findings.append(('ERROR', 'STALE_UPSTREAM', f'{key} -> {up.id} is stale '
                                       f'(its input {root.id} was re-released)'))

    # library tag consistency along each block's chain (PD / DFT)
    by_block = defaultdict(list)
    for r in audited.values():
        if r.lib_tag and cfg['disc'].get(r.flow, '') in lib_disc:
            by_block[(r.phase, r.block)].append(r)
    for (ph, b), rs in by_block.items():
        used = defaultdict(list)
        for r in rs:
            used[r.lib_tag].append(f'{r.flow}/{r.tag}')
        if len(used) > 1:
            txt = '; '.join(f'{t}: {", ".join(sorted(v))}' for t, v in sorted(used.items()))
            block_findings[(ph, b)].add(('WARN', 'LIBTAG_MIX', f'releases use different library tags — {txt}'))

    # signoff flows of one exit must read the same implementation release
    groups = defaultdict(dict)
    for r in audited.values():
        if r.flow in cfg.get('signoff', []) and r.flow not in IMPL_FLOWS:
            for key, val, up, note in r.inputs:
                if up is not None and up.flow in IMPL_FLOWS:
                    groups[(r.phase, r.block, r.tag)][r.flow] = up.id
    for (ph, b, t), m in groups.items():
        if len(set(m.values())) > 1:
            txt = ', '.join(f'{f} <- {u}' for f, u in sorted(m.items()))
            for f in m:
                audited[f'{ph}/{b}/{f}/{t}'].findings.append(
                    ('ERROR', 'SIGNOFF_SPLIT', f'{t} signoff on different implementation data: {txt}'))

    # hierarchy: the parent's library tag carries its children (once per block / tag)
    tag_cache = {}
    for r in audited.values():
        kids = cfg['blocks'].get(r.block, {}).get('children', [])
        if not kids or not r.lib_tag or cfg['disc'].get(r.flow, '') != 'PD':
            continue
        if r.lib_tag not in tag_cache:
            tag_cache[r.lib_tag] = lib_tag_blocks(cfg, r.lib_tag)
        tb = tag_cache[r.lib_tag]
        bf = block_findings[(r.phase, r.block)]
        for k in kids:
            if k not in tb:
                bf.add(('ERROR', 'CHILD_MISSING', f'child {k} not in library tag {r.lib_tag}'))
                continue
            path, pv, copied = tb[k]
            src = os.path.join(path, 'RELEASE_COMPLETE')
            if not os.path.exists(src):
                bf.add(('ERROR', 'CHILD_MISSING', f'{r.lib_tag} {k} source {path} no longer released'))
                continue
            if copied and os.path.getmtime(src) > copied + 1:
                bf.add(('ERROR', 'CHILD_STALE',
                        f'{r.lib_tag} copied {k} from {_short(cfg, path)} before it was re-released '
                        f'({_ts(os.path.getmtime(src))}) — re-add the block to a new tag'))
            parts = _short(cfg, path).split('/')
            if len(parts) >= 4:
                cph, cfl, ctag = parts[0], parts[2], parts[3]
                src_rel = everything.get(f'{cph}/{k}/{cfl}/{ctag}')
                nv = newer_version(everything, src_rel) if src_rel else None
                if nv:
                    bf.add(('WARN', 'CHILD_OLD', f'{r.lib_tag} carries {k} {cph}/{cfl}/{ctag}; newer '
                            f'{family(ctag)[0]}: {nv.id}'))
                if cph != r.phase and cph in cfg['phases'] and \
                        cfg['phases'].index(cph) < cfg['phases'].index(r.phase) and \
                        any(x.block == k and x.phase == r.phase and x.flow in IMPL_FLOWS for x in everything.values()):
                    bf.add(('INFO', 'CHILD_LATER', f'{r.lib_tag} carries {k} from {cph}; {k} has {r.phase} releases'))
            if pv == 'PENDING':
                bf.add(('WARN', 'CHILD_PV_PENDING', f'{r.lib_tag} {k}: gds / cdl from PNR (no PV release)'))
    return newest_tag


def _ts(t):
    import time
    return time.strftime('%m-%d %H:%M', time.localtime(t))


def _short(cfg, p):
    base = os.path.realpath(cfg['release']) + os.sep
    rp = os.path.realpath(p)
    return rp[len(base):] if rp.startswith(base) else p


# ── resolution plan ─────────────────────────────────────────────────────────
def first_node(run_dir):
    """First node of a run (what `run retrace --from` takes), from `run status`."""
    try:
        out = subprocess.run([os.path.join(ROOT, 'bin', 'cbflow'), 'run', 'status'], cwd=run_dir,
                             capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return '<first node>'
    m = re.search(r'^\[INFO\]\s+\[[A-Z ]+\]\s+(\S+)', out.stdout + out.stderr, re.M)
    return m.group(1) if m else '<first node>'


def uc_file(r):
    """workarea/<block>/uc_<FLOW>[_<tool>]_<phase>.tcl the run was created from."""
    c = sorted(glob.glob(os.path.join(ROOT, 'workarea', r.block, f'uc_{r.flow}_*{r.phase}.tcl')) +
               glob.glob(os.path.join(ROOT, 'workarea', r.block, f'uc_{r.flow}_{r.phase}.tcl')))
    return os.path.relpath(c[0], ROOT) if c else f'{r.run_dir}/setup/user_config.tcl'


def plan(cfg, audited, newest_tag, block_findings):
    """Releases to rebuild in dependency order + config lines to change."""
    redo = {r.id for r in audited.values()
            if any(c in ('STALE_INPUT', 'STALE_UPSTREAM', 'MISSING_INPUT', 'SIGNOFF_SPLIT', 'CHILD_STALE')
                   for _, c, _ in r.findings)}
    # everything downstream of a release that is redone is redone too
    changed = True
    while changed:
        changed = False
        for r in audited.values():
            if r.id in redo:
                continue
            if any(up is not None and up.id in redo for _, _, up, _ in r.inputs):
                redo.add(r.id)
                changed = True
    order, done = [], set()

    def visit(rid):
        if rid in done:
            return
        done.add(rid)
        for _, _, up, _ in audited[rid].inputs:
            if up is not None and up.id in redo:
                visit(up.id)
        order.append(rid)
    for rid in sorted(redo):
        visit(rid)
    steps = []
    for rid in order:
        r = audited[rid]
        steps.append({'release': rid, 'run_dir': r.run_dir,
                      'cmd': (f'cd {r.run_dir} && $CB/bin/cbflow run retrace --from {first_node(r.run_dir)} '
                              f'&& $CB/bin/cbflow run all') if r.run_dir else '(no run recorded)'})
    edits = []
    for r in audited.values():
        for sev, code, msg in r.findings:
            if code == 'NEWER_VERSION':
                m = re.match(r'(\S+) -> (\S+); newer \S+: (\S+)', msg)
                if m and m.group(1).endswith('release_tag)'):
                    edits.append((uc_file(r), f'set {m.group(1)} "{m.group(3).split("/")[-1]}"   '
                                  f';# was {m.group(2).split("/")[-1]} (newer release of the exit)'))
            if code == 'LIBTAG_OLD' and newest_tag:
                edits.append((uc_file(r), f'set project(lib_config_tag) "{newest_tag}"   ;# was {r.lib_tag}; '
                              f'first: library-manager check --lib_tag {newest_tag} --design {r.block}'))
    for (ph, b), fs in block_findings.items():
        for sev, code, msg in fs:
            if code == 'CHILD_STALE':
                edits.append((f'{ph} {b}', 'library-manager: new tag with the child re-added, then rerun '
                              f'{b} against it ({msg.split(" before")[0]})'))
    return steps, sorted(set(edits))


# ── report ──────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--project', required=True)
    ap.add_argument('--phase', help='phase to audit (default: every phase with releases)')
    ap.add_argument('--blocks', nargs='*')
    ap.add_argument('--json')
    ap.add_argument('--quiet', action='store_true', help='findings and plan only')
    a = ap.parse_args()
    cfg = project_values(a.project)
    if a.phase and a.phase not in cfg['phases']:
        sys.exit(f'tag_audit: phase {a.phase} not in project(phases) {cfg["phases"]}')
    if a.blocks:
        unknown = [b for b in a.blocks if b not in cfg['blocks']]
        if unknown:
            sys.exit(f'tag_audit: {unknown} not in project(design_hierarchy)')
    everything = all_releases(cfg)
    audited = {k: v for k, v in everything.items()
               if (not a.phase or v.phase == a.phase) and (not a.blocks or v.block in a.blocks)}
    if not audited:
        sys.exit('tag_audit: no releases match')
    block_findings = defaultdict(set)
    newest_tag = audit(cfg, everything, audited, block_findings)
    steps, edits = plan(cfg, audited, newest_tag, block_findings)

    counts = defaultdict(int)
    for r in audited.values():
        for s, _, _ in r.findings:
            counts[s] += 1
    for fs in block_findings.values():
        for s, _, _ in fs:
            counts[s] += 1
    print(f'Tag / dependency audit — project {a.project}'
          + (f', phase {a.phase}' if a.phase else '') + f': {len(audited)} releases, '
          f'library tags {", ".join(lib_tags_available(cfg)) or "-"}')
    print(f'ERROR {counts["ERROR"]}  WARN {counts["WARN"]}  INFO {counts["INFO"]}\n')
    for (ph, b) in sorted({(r.phase, r.block) for r in audited.values()},
                          key=lambda x: (cfg['phases'].index(x[0]), x[1])):
        rs = sorted([r for r in audited.values() if r.phase == ph and r.block == b], key=lambda r: r.time)
        print(f'== {ph} {b}')
        for s, c, m in sorted(block_findings.get((ph, b), ()), key=lambda f: (SEV[f[0]], f[1], f[2])):
            if not (a.quiet and s == 'INFO'):
                print(f'   block {s:5s} {c:19s} {m}')
        for r in rs:
            worst = min((SEV[s] for s, _, _ in r.findings), default=3)
            mark = {0: 'ERROR', 1: 'WARN ', 2: 'ok   ', 3: 'ok   '}[worst]
            ups = ', '.join(sorted({up.id.split('/', 2)[2] if up.phase == ph else up.id
                                    for _, _, up, _ in r.inputs if up is not None})) or '-'
            print(f'  [{mark}] {r.flow + "/" + r.tag:32s} {_ts(r.time)}  lib {r.lib_tag or "-":5s}  <- {ups}')
            for s, c, m in sorted(r.findings, key=lambda f: SEV[f[0]]):
                if a.quiet and s == 'INFO':
                    continue
                print(f'          {s:5s} {c:19s} {m}')
        print()
    print('Resolution plan')
    if steps:
        print('  ($CB = repo root)')
        print('  Rebuild in this order (each consumes the one before; spec-to-GDS blocks:')
        print('  workarea/run_spec2gds.sh <block> <phase> FROM=<first step> does the same):')
        for i, s in enumerate(steps, 1):
            print(f'  {i:2d}. {s["release"]}\n      {s["cmd"]}')
    else:
        print('  Nothing stale — no rebuild needed.')
    if edits:
        print('\n  Config lines to consider (setup/user_config.tcl of the run / workarea uc_*.tcl; not applied):')
        for rid, line in edits:
            print(f'    {rid:44s} {line}')
    if a.json:
        json.dump({'releases': {r.id: {'time': r.time, 'lib_tag': r.lib_tag, 'run_dir': r.run_dir,
                                       'inputs': [(k, v, up.id if up else None, n) for k, v, up, n in r.inputs],
                                       'findings': r.findings} for r in audited.values()},
                   'block_findings': {f'{p}/{b}': sorted(v) for (p, b), v in block_findings.items()},
                   'plan': steps, 'edits': edits}, open(a.json, 'w'), indent=1)
        print(f'\nJSON: {a.json}')
    sys.exit(1 if counts['ERROR'] else 0)


if __name__ == '__main__':
    main()
