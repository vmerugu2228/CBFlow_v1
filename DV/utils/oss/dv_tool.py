#!/usr/bin/env python3
# =============================================================================
# dv_tool.py — CBflow open-source DV helper (UVM on Verilator)
#
#   tests    --vplan <xlsx> --milestone M2 -o tests.txt
#            tests of every vPlan feature up to the milestone (cumulative)
#   regress  --sim <bin> --tests t... --seeds N [--seed-base S] [--jobs J]
#            [--timeout-s T] -o <dir>
#            every test x seed (+verilator+seed, own coverage file), in
#            parallel; a run passes when the simulation exits 0, reaches the
#            UVM report summary and has 0 UVM_ERROR / UVM_FATAL
#            -> <dir>/results.csv, <dir>/<test>/s<seed>/{sim.log,cov.dat}
#   covmerge --results results.csv --dut-files f... --vplan <xlsx>
#            --milestone M2 -o <dir>
#            merges the coverage of the passing runs (verilator_coverage) and
#            measures: code coverage of the DUT sources (line, branch, expr,
#            toggle, FSM), functional coverage (covergroup bins; a vPlan
#            coverage item = the coverpoint / cross of that name), vPlan
#            closure per feature -> coverage.rpt, plan.csv, metrics.json
#   runsum   --results results.csv --title T -o <rpt>
#            runs / pass rate / failures; Status PASS when every run passed
#   triage   --results results.csv -o triage.rpt
#            failing runs bucketed by first UVM_ERROR / UVM_FATAL signature
#   signoff  --metrics metrics.json --milestone M2 --targets k=v... -o <rpt>
#            pass_rate / code_coverage / functional_coverage / plan_coverage
#            against the milestone's targets -> Status PASS | FAIL
# =============================================================================

import argparse
import concurrent.futures as cf
import csv
import json
import os
import re
import subprocess
import sys
import time

MILESTONES = ['M1', 'M2', 'M3', 'M4']
CODE_TYPES = ['line', 'branch', 'expr', 'toggle', 'fsm_state', 'fsm_arc']
IGNORED_BINS = {'default', 'ignore', 'illegal'}


def _die(msg):
    sys.exit(f'dv_tool: ERROR: {msg}')


def _ms_index(m):
    if m not in MILESTONES:
        _die(f'milestone {m!r}: one of {MILESTONES}')
    return MILESTONES.index(m)


# ── vPlan ────────────────────────────────────────────────────────────────────
def read_vplan(path):
    sys.path.insert(0, os.environ.get('CBFLOW_OSS_PYTHON', ''))
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    if 'vplan' not in wb.sheetnames:
        _die(f'{path}: no "vplan" sheet')
    rows = list(wb['vplan'].iter_rows(values_only=True))
    hdr = [str(h or '').strip().lower() for h in rows[0]]
    need = ['feature id', 'feature', 'milestone', 'tests', 'coverage items']
    miss = [c for c in need if c not in hdr]
    if miss:
        _die(f'{path}: vPlan columns missing: {miss}')
    ix = {c: hdr.index(c) for c in hdr}
    split = lambda v: [x.strip() for x in str(v or '').split(',') if x.strip()]
    out = []
    for r in rows[1:]:
        if not r[ix['feature id']]:
            continue
        out.append({'id': str(r[ix['feature id']]), 'name': str(r[ix['feature']] or ''),
                    'milestone': str(r[ix['milestone']] or '').strip(),
                    'tests': split(r[ix['tests']]), 'items': split(r[ix['coverage items']]),
                    'waiver': str(r[ix['waiver']] or '').strip() if 'waiver' in ix else ''})
    return out


def features_upto(plan, milestone):
    k = _ms_index(milestone)
    return [f for f in plan if f['milestone'] in MILESTONES and MILESTONES.index(f['milestone']) <= k]


def cmd_tests(a):
    tests = []
    for f in features_upto(read_vplan(a.vplan), a.milestone):
        tests += [t for t in f['tests'] if t not in tests]
    if not tests:
        _die(f'no vPlan tests up to {a.milestone}')
    open(a.output, 'w').write('\n'.join(tests) + '\n')
    print(f'tests: {len(tests)} up to {a.milestone}')


# ── regression ───────────────────────────────────────────────────────────────
_SUMMARY_RE = re.compile(r'UVM_(ERROR|FATAL|WARNING)\s*:\s*(\d+)')
_FIRST_RE = re.compile(r'^(UVM_(?:ERROR|FATAL))\s+(?:\S+\(\d+\)\s+)?@\s*\S+:\s*\S+\s*\[([^\]]+)\]\s*(.*)$', re.M)


def _run_one(sim, test, seed, rdir, timeout, plusargs):
    os.makedirs(rdir, exist_ok=True)
    log, cov = os.path.join(rdir, 'sim.log'), os.path.join(rdir, 'cov.dat')
    cmd = [sim, f'+UVM_TESTNAME={test}', f'+verilator+seed+{seed}', '+UVM_NO_RELNOTES',
           f'+verilator+coverage+file+{cov}'] + plusargs
    t0 = time.time()
    status = None
    with open(log, 'w') as fh:
        try:
            rc = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            rc, status = -1, 'TIMEOUT'
    wall = time.time() - t0
    text = open(log, errors='replace').read()
    counts = {k: 0 for k in ('ERROR', 'FATAL', 'WARNING')}
    summary = '--- UVM Report Summary ---' in text
    for k, n in _SUMMARY_RE.findall(text[text.find('--- UVM Report Summary ---'):] if summary else ''):
        counts[k] = int(n)
    m = _FIRST_RE.search(text)
    first = f'{m.group(1)} [{m.group(2)}] {m.group(3).strip()}' if m else ''
    if status is None:
        status = 'PASS' if (rc == 0 and summary and counts['ERROR'] == 0 and counts['FATAL'] == 0) else 'FAIL'
        if status == 'FAIL' and not first:
            first = f'exit {rc}' + ('' if summary else ', no UVM report summary')
    sim_t = re.search(r'\$finish at (\S+);', text)
    return {'test': test, 'seed': seed, 'status': status, 'uvm_errors': counts['ERROR'],
            'uvm_fatals': counts['FATAL'], 'uvm_warnings': counts['WARNING'],
            'sim_time': sim_t.group(1) if sim_t else '', 'wall_s': f'{wall:.1f}',
            'first_error': first[:300], 'log': log, 'cov': cov if os.path.isfile(cov) else ''}


def cmd_regress(a):
    if not os.access(a.sim, os.X_OK):
        _die(f'simulator {a.sim} not executable')
    jobs = [(t, a.seed_base + i) for t in a.tests for i in range(a.seeds)]
    os.makedirs(a.output, exist_ok=True)
    res = []
    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = [ex.submit(_run_one, a.sim, t, s, os.path.join(a.output, t, f's{s}'), a.timeout_s, a.plusargs or [])
                for t, s in jobs]
        for f in cf.as_completed(futs):
            r = f.result()
            res.append(r)
            print(f'  {r["status"]:7s} {r["test"]} seed {r["seed"]} ({r["wall_s"]} s) {r["first_error"][:90]}', flush=True)
    res.sort(key=lambda r: (r['test'], r['seed']))
    cols = list(res[0].keys())
    with open(os.path.join(a.output, 'results.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader(); w.writerows(res)
    npass = sum(r['status'] == 'PASS' for r in res)
    print(f'regress: {npass}/{len(res)} runs passed ({len(a.tests)} tests x {a.seeds} seeds)')


def read_results(path):
    return list(csv.DictReader(open(path)))


# ── coverage ─────────────────────────────────────────────────────────────────
def read_cov(path):
    """[(fields, count)] of a Verilator coverage database."""
    out = []
    for line in open(path, encoding='latin1'):
        if not line.startswith("C '"):
            continue
        body, cnt = line[3:].rstrip('\n').rsplit("' ", 1)
        kv = dict(x.split('\x02', 1) for x in body.split('\x01') if '\x02' in x)
        out.append((kv, int(cnt)))
    return out


def _pct(h, t):
    return round(100.0 * h / t, 2) if t else 0.0


def cmd_covmerge(a):
    res = read_results(a.results)
    dats = [r['cov'] for r in res if r['status'] == 'PASS' and r['cov']]
    os.makedirs(a.output, exist_ok=True)
    merged = os.path.join(a.output, 'merged.dat')
    if dats:
        subprocess.run(['verilator_coverage', '--write', merged] + dats, check=True,
                       stdout=subprocess.DEVNULL)
        recs = read_cov(merged)
    else:
        open(merged, 'w').close()
        recs = []
    dut = {os.path.realpath(f) for f in a.dut_files}
    dut_names = {os.path.basename(f) for f in a.dut_files}
    code = {t: [0, 0] for t in CODE_TYPES}
    cps = {}
    for kv, n in recs:
        t = kv.get('t', '')
        if t in code:
            f = kv.get('f', '')
            if os.path.realpath(f) in dut or os.path.basename(f) in dut_names:
                code[t][1] += 1
                code[t][0] += (n > 0)
        elif t == 'covergroup':
            if kv.get('bin_type', '') in IGNORED_BINS:
                continue
            parts = kv.get('h', '').split('.')
            if len(parts) < 3:
                continue
            cp = parts[-2]
            c = cps.setdefault(cp, [0, 0])
            c[1] += 1
            c[0] += (n > 0)
    lb_h = code['line'][0] + code['branch'][0]
    lb_t = code['line'][1] + code['branch'][1]
    fc_h = sum(c[0] for c in cps.values()); fc_t = sum(c[1] for c in cps.values())
    # vPlan closure up to the milestone
    plan = read_vplan(a.vplan)
    feats = features_upto(plan, a.milestone)
    tstat = {}
    for r in res:
        s = tstat.setdefault(r['test'], {'runs': 0, 'pass': 0})
        s['runs'] += 1; s['pass'] += (r['status'] == 'PASS')
    rows, n_closed = [], 0
    for f in feats:
        tests = []
        for t in f['tests']:
            s = tstat.get(t)
            tests.append((t, 'NOT RUN' if not s else 'PASS' if s['pass'] == s['runs'] else
                          f'FAIL {s["runs"] - s["pass"]}/{s["runs"]}'))
        items = []
        for it in f['items']:
            c = cps.get(it)
            items.append((it, 'NOT IMPLEMENTED' if not c else f'{_pct(*c):g}%' + ('' if c[0] == c[1] else f' ({c[0]}/{c[1]} bins)')))
        ok = all(s == 'PASS' for _, s in tests) and all(c in cps and cps[c][0] == cps[c][1] for c in f['items'])
        status = 'CLOSED' if ok else ('WAIVED' if f['waiver'] else 'OPEN')
        n_closed += status in ('CLOSED', 'WAIVED')
        rows.append({'feature': f['id'], 'name': f['name'], 'milestone': f['milestone'],
                     'tests': '; '.join(f'{t} {s}' for t, s in tests),
                     'coverage': '; '.join(f'{i} {s}' for i, s in items),
                     'waiver': f['waiver'], 'status': status})
    with open(os.path.join(a.output, 'plan.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else ['feature'])
        w.writeheader(); w.writerows(rows)
    npass = sum(r['status'] == 'PASS' for r in res)
    m = {'milestone': a.milestone, 'runs': len(res), 'runs_passed': npass,
         'pass_rate': _pct(npass, len(res)),
         'tests': len(tstat), 'tests_passing': sum(s['pass'] == s['runs'] for s in tstat.values()),
         'code_coverage': _pct(lb_h, lb_t),
         'code': {t: {'hit': h, 'total': tt, 'pct': _pct(h, tt)} for t, (h, tt) in code.items()},
         'functional_coverage': _pct(fc_h, fc_t),
         'coverpoints': {k: {'hit': h, 'total': t, 'pct': _pct(h, t)} for k, (h, t) in sorted(cps.items())},
         'plan_features': len(feats), 'plan_closed': n_closed, 'plan_coverage': _pct(n_closed, len(feats))}
    json.dump(m, open(os.path.join(a.output, 'metrics.json'), 'w'), indent=1)
    L = [f'DV coverage — {a.milestone} ({len(dats)} passing run(s) merged)',
         f'  Runs              : {npass}/{len(res)} passed ({m["pass_rate"]}%)',
         f'  Tests passing     : {m["tests_passing"]}/{m["tests"]} (all seeds)',
         f'  Code coverage     : {m["code_coverage"]}%  (line + branch, DUT sources)']
    for t in CODE_TYPES:
        h, tt = code[t]
        L.append(f'    {t:10s}      : {_pct(h, tt):6.2f}%  ({h}/{tt})')
    L += [f'  Functional cov.   : {m["functional_coverage"]}%  ({len(cps)} coverpoints, {fc_h}/{fc_t} bins)',
          f'  vPlan coverage    : {m["plan_coverage"]}%  ({n_closed}/{len(feats)} features up to {a.milestone})', '',
          '  Features:']
    for r in rows:
        L.append(f'    {r["feature"]:4s} {r["milestone"]} {r["status"]:7s} {r["name"]}')
        L.append(f'         tests    : {r["tests"]}')
        L.append(f'         coverage : {r["coverage"]}')
    open(a.report, 'w').write('\n'.join(L) + '\n')
    print('\n'.join(L[:9]))


# ── run summary ──────────────────────────────────────────────────────────────
def cmd_runsum(a):
    res = read_results(a.results)
    npass = sum(r['status'] == 'PASS' for r in res)
    tests = sorted({r['test'] for r in res})
    L = [f'{a.title}', f'  Tests           : {" ".join(tests)}',
         f'  Runs            : {npass}/{len(res)} passed',
         f'  Pass rate       : {_pct(npass, len(res))}']
    for r in res:
        if r['status'] != 'PASS':
            L.append(f'  FAIL            : {r["test"]} seed {r["seed"]} — {r["first_error"]}')
    L += [f'  Status          : {"PASS" if res and npass == len(res) else "FAIL"}', '']
    open(a.output, 'w').write('\n'.join(L))
    print('\n'.join(L))


# ── triage ───────────────────────────────────────────────────────────────────
def _signature(first):
    s = re.sub(r'0x[0-9a-fA-F]+', '0x#', first)
    s = re.sub(r'\d+', '#', s)
    return s[:160]


def cmd_triage(a):
    res = read_results(a.results)
    fails = [r for r in res if r['status'] != 'PASS']
    buckets = {}
    for r in fails:
        buckets.setdefault(_signature(r['first_error'] or r['status']), []).append(r)
    L = [f'Triage — {len(fails)} failing run(s) of {len(res)}, {len(buckets)} signature(s)']
    for sig, rs in sorted(buckets.items(), key=lambda x: -len(x[1])):
        tests = sorted({r['test'] for r in rs})
        L += ['', f'  [{len(rs)} run(s)] {sig}', f'    tests : {", ".join(tests)}',
              f'    first : {rs[0]["test"]} seed {rs[0]["seed"]} — {rs[0]["log"]}']
    open(a.output, 'w').write('\n'.join(L) + '\n')
    print(L[0])


# ── sign-off ─────────────────────────────────────────────────────────────────
def cmd_signoff(a):
    m = json.load(open(a.metrics))
    targets = {}
    for kv in a.targets or []:
        k, v = kv.split('=', 1)
        if k not in ('pass_rate', 'code_coverage', 'functional_coverage', 'plan_coverage'):
            _die(f'target {k}: pass_rate | code_coverage | functional_coverage | plan_coverage')
        targets[k] = float(v)
    if not targets:
        _die(f'no targets for {a.milestone}')
    L = [f'DV sign-off — {a.milestone}', f'  Runs            : {m["runs_passed"]}/{m["runs"]}']
    ok = True
    for k in ('pass_rate', 'code_coverage', 'functional_coverage', 'plan_coverage'):
        v = m[k]
        if k in targets:
            good = v >= targets[k]
            ok &= good
            L.append(f'  {k:16s}: {v:6.2f}%  target {targets[k]:g}%  {"MET" if good else "NOT MET"}')
        else:
            # no target = not signed off: every metric needs one (project(dv,targets,<M>))
            ok = False
            L.append(f'  {k:16s}: {v:6.2f}%  NO TARGET — set project(dv,targets,{a.milestone}) {k} (DV overlay)')
    L += [f'  Plan features   : {m["plan_closed"]}/{m["plan_features"]} closed',
          f'  Status          : {"PASS" if ok else "FAIL"}', '']
    open(a.output, 'w').write('\n'.join(L))
    print('\n'.join(L))


def main():
    ap = argparse.ArgumentParser(description='CBflow open-source DV helper')
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('tests'); p.add_argument('--vplan', required=True); p.add_argument('--milestone', required=True)
    p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('regress'); p.add_argument('--sim', required=True); p.add_argument('--tests', nargs='+', required=True)
    p.add_argument('--seeds', type=int, required=True); p.add_argument('--seed-base', type=int, default=1)
    p.add_argument('--jobs', type=int, default=os.cpu_count() or 4); p.add_argument('--timeout-s', type=int, default=1800)
    p.add_argument('--plusargs', nargs='*'); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('covmerge'); p.add_argument('--results', required=True); p.add_argument('--dut-files', nargs='+', required=True)
    p.add_argument('--vplan', required=True); p.add_argument('--milestone', required=True)
    p.add_argument('-o', '--output', required=True); p.add_argument('--report', required=True)
    p = sp.add_parser('runsum'); p.add_argument('--results', required=True); p.add_argument('--title', required=True)
    p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('triage'); p.add_argument('--results', required=True); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('signoff'); p.add_argument('--metrics', required=True); p.add_argument('--milestone', required=True)
    p.add_argument('--targets', nargs='*'); p.add_argument('-o', '--output', required=True)
    a = ap.parse_args()
    {'tests': cmd_tests, 'regress': cmd_regress, 'covmerge': cmd_covmerge,
     'triage': cmd_triage, 'runsum': cmd_runsum, 'signoff': cmd_signoff}[a.cmd](a)


if __name__ == '__main__':
    main()
