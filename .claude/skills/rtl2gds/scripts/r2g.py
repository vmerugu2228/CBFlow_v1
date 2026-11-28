#!/usr/bin/env python3
"""rtl2gds orchestrator (rtl2gds skill) — RTL to signed-off, released GDS across a
project's block hierarchy, bottom-up, on the open-source flow.

    r2g.py plan  --project P --phase PH --exit TAG [--blocks b ...] [--top b] [--run-name N]
                 [--signoff "STA PV LEC"] [--lib-tag T] [--base-tag B] [--no-lock] [--publish]
                 [--release-path DIR (sandbox)] [--out DIR]
    r2g.py run   --plan DIR [--max-parallel N] [--resume] [--dry]
    r2g.py board --plan DIR

plan   per block (children before parents): SYNTH -> FP -> PNR -> signoff (STA / PV /
       LEC in parallel, each reading the exit release) -> checklist; for a block whose
       parent is in the plan: lock its exit (cbflow flow release lock) and add its
       release to a new project library tag (library-manager project-tag create
       --from + add --category block) that the parents' runs use. User configs per
       step are written as workarea/<b>/uc_<FLOW>[_tool]_<PH>_<run>.tcl from the
       block's own configs (phase-tuned first, then the generic template, then a
       block of the same kind), with run name, phase, library tag and input tags set.
       Preflight: exits locked against re-release, library tag, templates, exit plan.
run    executes the plan's dependency graph (parallel up to --max-parallel): workspace
       create (or retrace an existing run) + run all; a step passes on result=PASS and,
       for releasing flows, a RELEASE_COMPLETE newer than the step start; signoff
       verdicts from the release's metrics.rpt. A failed step stops its dependents.
       State: <plan>/state.json; events: <plan>/events.txt (one line per event — the
       skill streams it with Monitor); logs: <plan>/logs/.
board  the live grid: blocks x stages (✓ done, ⟳ running + elapsed, ✗ failed,
       ⊘ blocked, · pending, – skipped), signoff verdicts, the last events.
"""
import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys
import threading
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
CB = os.path.join(ROOT, 'bin', 'cbflow')
SIGNOFF = ('STA', 'PV', 'LEC')
TOOL = {'SYNTH': 'yosys', 'FP': 'openroad', 'PNR': 'openroad', 'STA': 'opensta', 'PV': 'magic', 'LEC': 'yosys'}
ICON = {'done': '✓', 'running': '⟳', 'failed': '✗', 'blocked': '⊘', 'pending': '·', 'skipped': '–'}


def die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def tcl(script):
    r = subprocess.run(['tclsh'], input=script, capture_output=True, text=True)
    if r.returncode:
        die(f'tclsh: {r.stderr.strip()}')
    return r.stdout


def project_cfg(p):
    g = os.path.join(ROOT, 'global', 'config', 'project', p, 'v1.0.0', f'{p}_config.tcl')
    if not os.path.exists(g):
        die(f'project {p}: no {g}')
    ov = sorted(glob.glob(os.path.join(ROOT, '*', 'config', 'project', p, 'v1.0.0', f'{p}_*_config.tcl')))
    srcs = ' '.join('{%s}' % f for f in [g] + ov)
    out = tcl(f'''foreach f {{{srcs}}} {{ catch {{ source $f }} }}
puts "release\\t$project(release,path)"
puts "workarea\\t$project(workarea_path)"
puts "tech\\t$project(technology)"
puts "libroot\\t$project(lib_tag_root)"
puts "libtag\\t$project(lib_config_tag)"
puts "phases\\t$project(phases)"
if {{[info exists project(phase_exits)]}} {{ dict for {{ph ex}} $project(phase_exits) {{ puts "exits\\t$ph\\t$ex" }} }}
dict for {{b d}} $project(design_hierarchy) {{ puts "block\\t$b\\t[dict get $d parent]\\t[dict get $d children]\\t[dict get $d level]" }}
''')
    c = {'blocks': {}, 'exits': {}}
    for line in out.splitlines():
        f = line.split('\t')
        if f[0] == 'block':
            c['blocks'][f[1]] = {'parent': f[2], 'children': f[3].split(), 'level': f[4]}
        elif f[0] == 'exits':
            c['exits'][f[1]] = f[2].split()
        elif f[0] == 'phases':
            c['phases'] = f[1].split()
        else:
            c[f[0]] = f[1] if len(f) > 1 else ''
    return c


def milestone_order():
    t = open(os.path.join(ROOT, 'PD', 'config', 'flow', 'v1.0.0', 'release_config.tcl')).read()
    m = re.search(r'set MILESTONE_ORDER \{([^}]*)\}', t)
    return m.group(1).split() if m else []


# ── plan ────────────────────────────────────────────────────────────────────
def pick_template(c, block, flow, phase):
    """User config to derive the step's from: the block's phase-tuned one, its
    generic template, else the same flow's template of a block of the same kind."""
    wa = c['workarea']
    leaf = not c['blocks'][block]['children']

    def cands(b):
        d = os.path.join(wa, b)
        tuned = [f for f in glob.glob(os.path.join(d, f'uc_{flow}*_{phase}.tcl'))
                 if re.match(rf'uc_{flow}(_{TOOL[flow]}|_signoff)?_{phase}\.tcl$', os.path.basename(f))]
        generic = [os.path.join(d, n) for n in (f'uc_{flow}_{TOOL[flow]}.tcl', f'uc_{flow}_signoff.tcl')
                   if os.path.exists(os.path.join(d, n))]
        return tuned, generic
    t, g = cands(block)
    if t:
        return t[0], 'tuned'
    if g:
        return g[0], 'generic'
    for b, d in c['blocks'].items():
        if b != block and (not d['children']) == leaf:
            t, g = cands(b)
            if g:
                return g[0], f'from {b}'
    return None, 'none'


def set_line(text, var, value):
    line = f'set {var:<30s} {value}'
    if re.search(rf'^set\s+{re.escape(var)}\s', text, re.M):
        return re.sub(rf'^set\s+{re.escape(var)}\s.*$', line.replace('\\', '\\\\'), text, flags=re.M)
    return text.rstrip('\n') + '\n' + line + '\n'


def drop_line(text, var):
    return re.sub(rf'^set\s+{re.escape(var)}\s.*\n?', '', text, flags=re.M)


def write_uc(c, plan, block, flow, lib_tag):
    tmpl, how = pick_template(c, block, flow, plan['phase'])
    if not tmpl:
        return None, f'no user config template for {flow} (workarea/{block}/uc_{flow}_{TOOL[flow]}.tcl)'
    t = open(tmpl).read()
    src_block = os.path.basename(os.path.dirname(tmpl))
    if src_block != block:
        t = re.sub(rf'\b{re.escape(src_block)}\b', block, t)
    ph, ex, syn = plan['phase'], plan['exit'], plan['synth_tag']
    arr = flow.lower()
    t = set_line(t, 'flow(design_name)', f'"{block}"')
    t = set_line(t, 'flow(run_name)', f'"{plan["run_name"]}"')
    t = set_line(t, 'project(phase)', f'"{ph}"')
    t = set_line(t, 'project(release,phase)', f'"{ph}"')
    t = set_line(t, 'project(lib_config_tag)', f'"{lib_tag}"')
    t = set_line(t, 'flow(test_mode)', '"false"')
    if plan.get('release_override'):
        t = set_line(t, 'project(release,path)', f'"{plan["release"]}"')
    t = drop_line(t, 'project(release,tag)')
    for k in [k for k in re.findall(rf'^set\s+({arr}\(input,[\w]*release_tag\))', t, re.M)]:
        t = drop_line(t, k)
    if flow == 'SYNTH':
        t = set_line(t, 'project(release,tag)', f'"{syn}"')
        rtl = os.path.join(c['release'], ph, block, 'RTL_LINT', 'LINT_SIGNOFF', 'rtl', f'{block}.f')
        if plan.get('rtl_from_lint') and os.path.exists(rtl):
            t = set_line(t, 'synth(input,rtl_filelist)', f'"{rtl}"')
            t = set_line(t, 'synth(input,rtl_format)', '"sverilog"')
    elif flow == 'FP':
        t = set_line(t, 'fp(input,release_tag)', f'"{syn}"')
    elif flow == 'PNR':
        t = set_line(t, 'pnr(input,release_tag)', f'"{syn}"')
        t = set_line(t, 'pnr(input,def_file_release_tag)', '"FP_EXIT"')
    elif flow == 'STA':
        t = set_line(t, 'sta(input,release_tag)', f'"{plan["pnr_exit"]}"')
    elif flow == 'PV':
        t = set_line(t, 'pv(input,release_tag)', f'"{plan["pnr_exit"]}"')
    elif flow == 'LEC':
        t = set_line(t, 'lec(input,netlist_golden_release_tag)', f'"{syn}"')
        t = set_line(t, 'lec(input,netlist_revised_release_tag)', f'"{plan["pnr_exit"]}"')
    name = f'uc_{flow}_{TOOL[flow]}_{ph}_{plan["run_name"]}.tcl'
    hdr = (f'# rtl2gds {plan["id"]}: {block} {flow} {ph} -> {ex}; from {os.path.relpath(tmpl, ROOT)} ({how})\n')
    os.makedirs(os.path.join(plan['dir'], 'ucs', block), exist_ok=True)
    path = os.path.join(plan['dir'], 'ucs', block, name)
    with open(path, 'w') as fh:
        fh.write(hdr + t)
    return path, how


def read_locks(c, phase, block):
    p = os.path.join(c['release'], phase, block, 'RELEASE_LOCKS')
    out = {}
    if os.path.exists(p):
        for l in open(p):
            if l.strip() and not l.startswith('#'):
                f = l.rstrip('\n').split('\t')
                out[f[0]] = f
    return out


def tag_kind(c, tag):
    d = os.path.join(c['libroot'], c['tech'])
    if os.path.isfile(os.path.join(d, tag, 'lib_config.tcl')):
        return ('combined' if os.path.isfile(os.path.join(d, tag, 'blocks_config.tcl')) else 'base'), tag
    if os.path.isfile(os.path.join(d, 'projects', c['project'], tag, 'lib_config.tcl')):
        b = os.path.join(d, 'projects', c['project'], tag, 'BASE')
        return 'project', open(b).read().strip() if os.path.exists(b) else ''
    return None, ''


def cmd_plan(a):
    c = project_cfg(a.project)
    c['project'] = a.project
    if a.phase not in c['phases']:
        die(f'phase {a.phase} not in project(phases) {c["phases"]}')
    order = milestone_order()
    pex = c['exits'].get(a.phase, [])
    if a.exit not in pex and a.exit not in order:
        die(f'exit {a.exit}: not an exit of {a.phase} (project(phase_exits): {" ".join(pex)})')
    # what PNR releases for the target: the latest phase exit at or before min(target, BTO)
    cap = 'BTO' if a.exit in ('BTO', 'MTO') else a.exit
    pnr_exit = max((e for e in pex if e in order and order.index(e) <= order.index(cap)),
                   key=order.index, default=None)
    if not pnr_exit:
        die(f'{a.phase} has no exit at or before {cap} for PNR to release (project(phase_exits))')
    # blocks: --blocks, else the subtree of --top, else the whole hierarchy
    if a.blocks:
        blocks = a.blocks
    else:
        top = a.top or next(b for b, d in c['blocks'].items() if not d['parent'])
        blocks, todo = [], [top]
        while todo:
            b = todo.pop()
            blocks.append(b)
            todo += c['blocks'][b]['children']
    for b in blocks:
        if b not in c['blocks']:
            die(f'{b} not in project(design_hierarchy)')
    lvl = {}

    def depth(b):
        kids = [k for k in c['blocks'][b]['children'] if k in blocks]
        lvl[b] = 1 + max((depth(k) for k in kids), default=0)
        return lvl[b]
    for b in blocks:
        depth(b)
    run_name = a.run_name or f'r2g_{a.phase.lower()}'
    pid = datetime.datetime.now().strftime('%Y%m%d_%H%M')
    out = os.path.abspath(a.out or os.path.join(c['workarea'], '.rtl2gds', f'{a.phase}_{a.exit}_{pid}'))
    os.makedirs(os.path.join(out, 'logs'), exist_ok=True)
    signoff = [f for f in (a.signoff or 'STA PV LEC').split() if f in SIGNOFF]
    lib_tag = a.lib_tag or c['libtag']
    kind, base = tag_kind(c, lib_tag)
    problems, notes = [], []
    if kind is None:
        problems.append(f'library tag {lib_tag} not found (base or project tag of {a.project})')
    levels = sorted(set(lvl.values()))
    need_new_tags = any(any(k in blocks for k in c['blocks'][b]['children']) for b in blocks)
    if need_new_tags:
        base = a.base_tag or (base if kind == 'project' else '')
        if not base:
            problems.append(f'parents in the plan need new project tags with their children\'s releases, and '
                            f'{lib_tag} is a {kind} tag — pass --base-tag <cells-only base tag> (e.g. OSS4)')
    plan = {'id': pid, 'project': a.project, 'phase': a.phase, 'exit': a.exit, 'pnr_exit': pnr_exit,
            'run_name': run_name, 'synth_tag': f'{a.phase}_SYNTH_{run_name}', 'signoff': signoff,
            'blocks': {b: lvl[b] for b in blocks}, 'lib_tag_start': lib_tag, 'base_tag': base,
            'lock': not a.no_lock, 'publish': a.publish, 'rtl_from_lint': True, 'dir': out,
            'workarea': c['workarea'], 'release': os.path.abspath(a.release_path) if a.release_path else c['release'],
            'release_override': bool(a.release_path), 'steps': {}}
    c['release'] = plan['release']
    # library tag per level: level 1 blocks use the start tag; level n+1 uses a new
    # project tag = previous + the level-n releases of blocks whose parent is planned
    tag_of_level = {1: lib_tag}
    for i, L in enumerate(levels[1:], start=2):
        tag_of_level[L] = f'{a.project.upper()}_{a.phase}_{run_name.upper()}_L{L}'
    steps = plan['steps']

    def add(sid, kind_, block, deps, **kw):
        steps[sid] = dict(kind=kind_, block=block, deps=deps, **kw)

    for b in sorted(blocks, key=lambda x: (lvl[x], x)):
        L = lvl[b]
        tag = tag_of_level[L]
        kid_steps = [f'{k}:LIB' for k in c['blocks'][b]['children'] if k in blocks]
        for f in ('SYNTH', 'FP', 'PNR') + tuple(signoff):
            uc, how = write_uc(c, plan, b, f, tag)
            if not uc:
                problems.append(f'{b} {f}: {how}')
                continue
            if how.startswith('from'):
                notes.append(f'{b} {f}: user config derived {how} — review {os.path.relpath(uc, ROOT)}')
            deps = {'SYNTH': kid_steps, 'FP': [f'{b}:SYNTH'], 'PNR': [f'{b}:FP']}.get(f, [f'{b}:PNR'])
            rel = {'SYNTH': plan['synth_tag'], 'FP': 'FP_EXIT', 'PNR': pnr_exit}.get(f, pnr_exit)
            add(f'{b}:{f}', 'flow', b, deps, flow=f, uc=uc, lib_tag=tag, release=rel,
                run_dir=os.path.join(c['workarea'], b, f'{a.phase}_run_{f}_{b}_{run_name}'))
        so = [f'{b}:{f}' for f in signoff if f'{b}:{f}' in steps]
        if a.exit == 'MTO' and pnr_exit == 'BTO':
            add(f'{b}:MTO', 'clone', b, [f'{b}:PNR'] + so)
        add(f'{b}:CKL', 'checklist', b, [s for s in [f'{b}:PNR'] + so if s in steps]
            + ([f'{b}:MTO'] if f'{b}:MTO' in steps else []))
        parent = c['blocks'][b]['parent']
        if parent in blocks:
            nxt = tag_of_level[lvl[parent]]
            pre = [s for s in [f'{b}:PNR'] + so if s in steps]
            if plan['lock']:
                add(f'{b}:LOCK', 'lock', b, pre, reason=f'rtl2gds {pid}: {a.exit} in {parent} {a.phase}')
                pre = pre + [f'{b}:LOCK']
            add(f'{b}:LIB', 'libtag', b, pre, tag=nxt, prev=tag_of_level.get(L) if L > 1 or kind == 'project' else '',
                base=base, path=os.path.join(c['release'], a.phase, b, 'PNR', pnr_exit))
        # exits this plan re-releases must not be locked
        for e in {plan['synth_tag'], 'FP_EXIT', pnr_exit, a.exit} | (set() if a.exit != 'MTO' else {'BTO'}):
            fam = re.sub(r'_(ECO|v)\d+$', '', e)
            lk = read_locks(c, a.phase, b).get(fam)
            if lk:
                problems.append(f'{b}: exit {fam} is LOCKED by {lk[2]} ({lk[3]}): {lk[4]} — unlock or leave {b} out')
    with open(os.path.join(out, 'plan.json'), 'w') as fh:
        json.dump(plan, fh, indent=1)
    print(f'rtl2gds plan {pid}: {a.project} {a.phase} -> {a.exit} (PNR releases {pnr_exit}); '
          f'{len(blocks)} block(s), {len(steps)} steps; signoff {" ".join(signoff)}')
    for L in levels:
        bl = sorted(b for b in blocks if lvl[b] == L)
        print(f'  level {L}: {", ".join(bl)}   library tag {tag_of_level[L]}'
              + ('' if L == levels[0] else ' (new: previous + level-below releases)'))
    print(f'  plan dir: {out}')
    for n in notes:
        print(f'NOTE  {n}')
    for p_ in problems:
        print(f'PROBLEM  {p_}')
    return 1 if problems else 0


# ── run ─────────────────────────────────────────────────────────────────────
class Runner:
    def __init__(self, pdir, max_par, dry):
        self.pdir = pdir
        self.plan = json.load(open(os.path.join(pdir, 'plan.json')))
        sp = os.path.join(pdir, 'state.json')
        self.state = json.load(open(sp)) if os.path.exists(sp) else {}
        self.lock = threading.Lock()
        self.sem = threading.Semaphore(max_par)
        self.dry = dry
        self.ev = open(os.path.join(pdir, 'events.txt'), 'a', buffering=1)

    def event(self, msg):
        line = f'[{time.strftime("%H:%M:%S")}] {msg}'
        with self.lock:
            self.ev.write(line + '\n')
        print(line, flush=True)

    def save(self):
        with self.lock:
            tmp = os.path.join(self.pdir, 'state.json.tmp')
            json.dump(self.state, open(tmp, 'w'), indent=1)
            os.replace(tmp, os.path.join(self.pdir, 'state.json'))

    def set(self, sid, **kw):
        with self.lock:
            self.state.setdefault(sid, {}).update(kw)
        self.save()

    def sh(self, cmd, cwd, log, timeout=None):
        with open(log, 'a') as fh:
            fh.write(f'\n$ (cd {cwd} && {" ".join(cmd)})\n')
            fh.flush()
            r = subprocess.run(cmd, cwd=cwd, stdout=fh, stderr=subprocess.STDOUT, timeout=timeout)
        return r.returncode

    def first_node(self, rd, log):
        r = subprocess.run([CB, 'run', 'status'], cwd=rd, capture_output=True, text=True)
        m = re.search(r'^\[INFO\]\s+\[[A-Z ]+\]\s+(\S+)', r.stdout + r.stderr, re.M)
        return m.group(1) if m else None

    def release_dir(self, st):
        return os.path.join(self.plan['release'], self.plan['phase'], st['block'], st['flow'], st['release'])

    def do_flow(self, sid, st):
        rd, log = st['run_dir'], os.path.join(self.pdir, 'logs', sid.replace(':', '_') + '.log')
        t0 = time.time()
        if os.path.isdir(rd):
            fn = self.first_node(rd, log)
            self.event(f'{sid}: retrace {os.path.basename(rd)} from {fn}')
            if not fn or self.sh([CB, 'run', 'retrace', '--from', fn], rd, log):
                return False, 'retrace failed'
        else:
            self.event(f'{sid}: workspace create ({os.path.basename(st["uc"])})')
            if self.sh([CB, 'workspace', 'create', '--config', st['uc']], os.path.dirname(rd), log) \
                    or not os.path.isdir(rd):
                return False, f'workspace create failed — {log}'
        self.event(f'{sid}: run all ({os.path.basename(rd)})')
        self.sh([CB, 'run', 'all'], rd, log)
        txt = open(log).read()
        if 'result=PASS' not in txt.split('run all')[-1]:
            return False, f'run failed — {log}'
        rc = os.path.join(self.release_dir(st), 'RELEASE_COMPLETE')
        if not os.path.exists(rc) or os.path.getmtime(rc) < t0:
            return False, f'run passed but {st["flow"]}/{st["release"]} was not released by it'
        verdict = ''
        m = os.path.join(self.release_dir(st), 'metrics.rpt')
        if st['flow'] in SIGNOFF and os.path.exists(m):
            mm = re.findall(r'^Status\s*:\s*(\S+)', open(m).read(), re.M)
            verdict = mm[-1] if mm else ''
        if self.plan['publish']:
            self.sh([CB, 'run', 'release', '--from-run', rd, '--publish'], os.path.dirname(rd), log)
        return True, (f'released {st["flow"]}/{st["release"]}' + (f', verdict {verdict}' if verdict else '')), verdict

    def do_step(self, sid):
        st = self.plan['steps'][sid]
        k = st['kind']
        log = os.path.join(self.pdir, 'logs', sid.replace(':', '_') + '.log')
        b, ph = st['block'], self.plan['phase']
        if self.dry:
            return True, 'dry run', ''
        if k == 'flow':
            r = self.do_flow(sid, st)
            return r if len(r) == 3 else (r[0], r[1], '')
        if k == 'clone':
            pnr = self.plan['steps'][f'{b}:PNR']['run_dir']
            ok = self.sh([CB, 'run', 'release', '--from-run', pnr, '--clone-from', 'BTO', '--tag', 'MTO'],
                         os.path.dirname(pnr), log) == 0
            return ok, 'cloned BTO -> MTO' if ok else f'clone failed — {log}', ''
        if k == 'checklist':
            pnr = self.plan['steps'][f'{b}:PNR']['run_dir']
            self.sh([CB, 'flow', 'checklist', 'status', '--run-dir', pnr], pnr, log)
            t = open(log).read()
            m = re.findall(r'(?:Verdict|Overall|Status)\s*[:=]\s*([A-Z_]+)', t)
            v = m[-1] if m else 'see log'
            return True, f'checklist {v}', v
        if k == 'lock':
            rc = self.sh([CB, 'flow', 'release', 'lock', '--project', self.plan['project'], '--phase', ph,
                          '--block', b, '--exit', self.plan['pnr_exit'], '--reason', st['reason']], ROOT, log)
            if rc and 'already locked' not in open(log).read():
                return False, f'lock failed — {log}', ''
            return True, f'locked {self.plan["pnr_exit"]}', ''
        if k == 'libtag':
            p = self.plan['project']
            tech = project_cfg(p)['tech']
            with self.lock:     # one tag writer at a time; the first child creates the tag
                tdir = os.path.join(project_cfg(p)['libroot'], tech, 'projects', p, st['tag'])
                if not os.path.exists(tdir):
                    cmd = [CB, 'flow', 'library-manager', 'project-tag', 'create', '--tech', tech, '--project', p,
                           '--tag', st['tag'], '--base', st['base']]
                    if st.get('prev'):
                        kind, _ = tag_kind(dict(project_cfg(p), project=p), st['prev'])
                        if kind == 'project':
                            cmd += ['--from', st['prev']]
                    if self.sh(cmd, ROOT, log):
                        return False, f'project-tag create failed — {log}', ''
                pv = os.path.join(self.plan['release'], ph, b, 'PV', self.plan['pnr_exit'], 'RELEASE_COMPLETE')
                cmd = [CB, 'flow', 'library-manager', 'add', '--tech', tech, '--project', p, '--tag', st['tag'],
                       '--category', 'block', '--path', st['path']] + ([] if os.path.exists(pv) else ['--pv-pending'])
                if self.sh(cmd, ROOT, log):
                    return False, f'library-manager add failed — {log}', ''
            return True, f'{b} {self.plan["pnr_exit"]} -> library tag {st["tag"]}', ''
        return False, f'unknown step kind {k}', ''

    def run(self, resume):
        steps = self.plan['steps']
        if not resume:
            self.state = {}
        for sid in steps:
            if self.state.get(sid, {}).get('status') not in ('done',):
                self.state[sid] = {'status': 'pending'}
        self.save()
        self.event(f'rtl2gds {self.plan["id"]}: {self.plan["project"]} {self.plan["phase"]} -> {self.plan["exit"]}, '
                   f'{len(steps)} steps' + (' (resume)' if resume else ''))
        threads = {}
        while True:
            with self.lock:
                status = {s: self.state[s]['status'] for s in steps}
            for sid, stv in status.items():
                if stv != 'pending':
                    continue
                deps = steps[sid]['deps']
                if any(status.get(d) in ('failed', 'blocked') for d in deps):
                    self.set(sid, status='blocked')
                    self.event(f'{sid}: blocked (dependency failed)')
                elif all(status.get(d) in ('done', 'skipped') for d in deps) and sid not in threads:
                    threads[sid] = threading.Thread(target=self.worker, args=(sid,), daemon=True)
                    threads[sid].start()
            with self.lock:
                left = [s for s in steps if self.state[s]['status'] in ('pending', 'running')]
            if not left:
                break
            time.sleep(2)
        done = sum(1 for s in steps if self.state[s]['status'] == 'done')
        bad = [s for s in steps if self.state[s]['status'] in ('failed', 'blocked')]
        self.event(f'rtl2gds {self.plan["id"]}: finished — {done}/{len(steps)} done'
                   + (f', failed/blocked: {", ".join(bad)}' if bad else ''))
        return 1 if bad else 0

    def worker(self, sid):
        with self.sem:
            self.set(sid, status='running', start=time.time())
            self.event(f'{sid}: start')
            try:
                ok, msg, verdict = self.do_step(sid)
            except Exception as e:  # noqa: BLE001 — record, keep the plan going
                ok, msg, verdict = False, f'{type(e).__name__}: {e}', ''
            self.set(sid, status='done' if ok else 'failed', end=time.time(), msg=msg, verdict=verdict)
            self.event(f'{sid}: {"DONE" if ok else "FAILED"} — {msg}')


def cmd_run(a):
    r = Runner(os.path.abspath(a.plan), a.max_parallel, a.dry)
    return r.run(a.resume)


# ── board ───────────────────────────────────────────────────────────────────
def cmd_board(a):
    pdir = os.path.abspath(a.plan)
    plan = json.load(open(os.path.join(pdir, 'plan.json')))
    sp = os.path.join(pdir, 'state.json')
    state = json.load(open(sp)) if os.path.exists(sp) else {}
    cols = ['SYNTH', 'FP', 'PNR'] + plan['signoff'] + ['MTO', 'CKL', 'LOCK', 'LIB']
    cols = [c for c in cols if any(s.endswith(':' + c) for s in plan['steps'])]
    now = time.time()
    print(f'rtl2gds {plan["id"]} — {plan["project"]} {plan["phase"]} -> {plan["exit"]} '
          f'(PNR releases {plan["pnr_exit"]})   {time.strftime("%H:%M:%S")}')
    w = max(max(len(b) for b in plan['blocks']), 5) + 2
    print(f'{"block":{w}s}{"lvl":4s}' + ''.join(f'{c:^12s}' for c in cols))
    for b in sorted(plan['blocks'], key=lambda x: (plan['blocks'][x], x)):
        row = f'{b:{w}s}{plan["blocks"][b]:<4d}'
        for c in cols:
            sid = f'{b}:{c}'
            if sid not in plan['steps']:
                row += f'{"":^12s}'
                continue
            s = state.get(sid, {'status': 'pending'})
            cell = ICON[s['status']]
            if s['status'] == 'running' and s.get('start'):
                cell += f' {int((now - s["start"]) // 60)}m'
            elif s.get('verdict') and c not in ('CKL',):
                cell += f' {s["verdict"][:5]}'
            elif c == 'CKL' and s.get('verdict'):
                cell += f' {s["verdict"][:7]}'
            row += f'{cell:^12s}'
        print(row)
    tot = len(plan['steps'])
    n = {k: sum(1 for s in plan['steps'] if state.get(s, {}).get('status', 'pending') == k) for k in ICON}
    print(f'\n{n["done"]}/{tot} done, {n["running"]} running, {n["failed"]} failed, {n["blocked"]} blocked, '
          f'{n["pending"]} pending   (✓ done ⟳ running ✗ failed ⊘ blocked · pending)')
    for sid, s in state.items():
        if s.get('status') == 'failed':
            print(f'  ✗ {sid}: {s.get("msg", "")}')
    ev = os.path.join(pdir, 'events.txt')
    if os.path.exists(ev):
        print('\nlast events:')
        for l in open(ev).read().splitlines()[-6:]:
            print('  ' + l)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('plan')
    p.add_argument('--project', required=True)
    p.add_argument('--phase', required=True)
    p.add_argument('--exit', required=True, help='release tag to reach (e.g. PRO_EXIT, BTO, MTO)')
    p.add_argument('--blocks', nargs='*')
    p.add_argument('--top')
    p.add_argument('--run-name')
    p.add_argument('--signoff', help='"STA PV LEC" (default) or a subset')
    p.add_argument('--lib-tag', help='library tag of the bottom level (default project(lib_config_tag))')
    p.add_argument('--base-tag', help='cells-only base tag for the new project tags')
    p.add_argument('--no-lock', action='store_true')
    p.add_argument('--publish', action='store_true')
    p.add_argument('--release-path', help='sandbox: release into this dir instead of project(release,path)')
    p.add_argument('--out')
    p = sub.add_parser('run')
    p.add_argument('--plan', required=True)
    p.add_argument('--max-parallel', type=int, default=3)
    p.add_argument('--resume', action='store_true')
    p.add_argument('--dry', action='store_true')
    p = sub.add_parser('board')
    p.add_argument('--plan', required=True)
    a = ap.parse_args()
    return {'plan': cmd_plan, 'run': cmd_run, 'board': cmd_board}[a.cmd](a)


if __name__ == '__main__':
    sys.exit(main())
