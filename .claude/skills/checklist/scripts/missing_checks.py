#!/usr/bin/env python3
"""Find checks a milestone is missing for what a run actually produces (read-only).

    python3 missing_checks.py <run_dir> --milestone <M> [--max N] [--json out.json]

Compares the milestone's resolved checks (milestone config + the run's
<arr>(checklist,*) tool map, as `cbflow flow checklist status` sees them) with
the run, and lists, ranked:
  A. lax checks   - a check PASSes while the report it reads says NOT MET /
                    FAIL / VIOLATED / OPEN, or a %-metric with a vacuous
                    threshold (>= 0) whose report states a target;
  B. peer gaps    - check kinds an earlier PD exit (MILESTONE_ORDER) or any
                    peer milestone of the same discipline has and this one lacks;
  C. unchecked metrics - "Key : value" lines of the exit node's metric reports
                    (checklist_metrics.rpt, milestone_checks.rpt, *checklist*.rpt,
                    dv_signoff.rpt, coverage.rpt, ...) that no check reads;
  D. library checks measurable here (tool-map metric matches the exit report)
                    but not applicable to this milestone;
  E. unread reports in the exit node (count + names).
Each suggestion carries a ready `bin/cbflow flow checklist add-check ...`
command when add-check can express it (grep / file checks), else the
framework-config change it needs (metric threshold -> milestone config
operator/default_threshold + tool overlay <arr>(checklist,metric,<check>)).
Suggestions only: add-check edits global/config/exit/ (framework config).
Suggestions the learned store records as rejected are flagged.
"""
import argparse
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ckl_common as C  # noqa: E402

METRIC_FILES = ('checklist_metrics.rpt', 'milestone_checks.rpt', 'metrics.rpt', 'sta_checklist.rpt',
                'dv_signoff.rpt', 'coverage.rpt', 'signoff.rpt', 'sta_summary.rpt')
BAD_WORDS = re.compile(r'\b(NOT MET|FAIL(ED)?|VIOLATED|OPEN|NOT IMPLEMENTED|MISMATCH(ES)?)\b')
INFO_KEYS = re.compile(r'^(design|stage|instances|block|top|tool|date|version|scenario|corner|mode|'
                       r'patterns?|runs|tests passing|io pins|hard macros|routable nets|plan features|.*cpu time|.*runtime)\b', re.I)
KV = re.compile(r'^\s*([A-Za-z][A-Za-z0-9 _/+()\-.]*?)\s*:\s*(-?[0-9.]+(?:[eE][-+]?\d+)?|N/A)\s*(%|ps|ns|mW|um2)?(?![A-Za-z])(.*)$')


def slug(s):
    return re.sub(r'_+', '_', re.sub(r'[^a-z0-9]+', '_', s.lower())).strip('_')


def kind_of(name, prefixes):
    tok = name.split('_', 1)
    if len(tok) == 2 and (tok[0] in prefixes or re.fullmatch(r'm\d', tok[0])):
        return tok[1]
    return name


def milestone_prefixes(m, cfg):
    names = list(cfg.get('mandatory_checks', {})) + list(cfg.get('optional_checks', {}))
    firsts = [n.split('_', 1)[0] for n in names if '_' in n]
    p = {m.lower().split('_')[0]}
    if firsts:
        p.add(max(set(firsts), key=firsts.count))
    return p


def toks(s):
    return set(t for t in re.split(r'[^a-z0-9]+', s.lower()) if t)


def covered(name, names):
    """True when the tokens of name are a subset of some existing check name's tokens."""
    t = toks(name)
    return bool(t) and any(t <= toks(n) for n in names)


def classify(key, unit, rest):
    k = key.lower()
    if re.search(r'violation|error|opens|shorts|unannotated|missing|illegal|nvp|mismatch|overflow\b|undefined', k):
        return 'count'
    if re.search(r'wns|slack', k):
        return 'slack'
    if re.search(r'tns', k):
        return 'tns'
    if unit == '%' or re.search(r'coverage|pct|rate|ratio|utili', k) or 'target' in rest:
        return 'percent'
    return 'value'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('run_dir')
    ap.add_argument('--milestone', required=True)
    ap.add_argument('--max', type=int, default=25, help='max unchecked metrics listed')
    ap.add_argument('--json')
    a = ap.parse_args()
    M = a.milestone
    ctx = C.run_context(a.run_dir)
    rd = ctx['run_dir']
    cfg, _ = C.resolved_config(M, rd)
    cc = C.cc()
    tmap = cc._tool_checklist_map(rd, ctx['flow'])
    order, tapeout = C.release_lists()
    disc = cc.get_milestone_discipline(M)
    info = cfg.get('milestone_info', {})
    node = tmap.get(f'exit_node,{M}') or info.get('stage_node', '')
    ndir = os.path.join(rd, 'work', ctx['flow'], node) if node else ''
    rejected = {e['check']: e for e in C.learned_entries(ctx['tech'], ctx['block']) if e['kind'] == 'missing-rejected'}
    status = (C.latest_status(rd, M)[1] or {})
    st_of = {r['name']: r['status'] for k in ('mandatory', 'optional', 'library')
             for r in status.get(f'{k}_checks', [])}
    checks = {}
    for kind in ('mandatory_checks', 'optional_checks', 'library_checks'):
        for n, c in (cfg.get(kind) or {}).items():
            checks[n] = dict(c, _kind=kind.split('_')[0])
    pfx = milestone_prefixes(M, cfg)
    prefix = sorted(pfx, key=len)[-1] if pfx else M.lower()
    sugg = []

    def add(section, name, why, cmd='', change='', evidence=''):
        rj = rejected.get(name)
        sugg.append({'section': section, 'name': name, 'why': why, 'command': cmd, 'config_change': change,
                     'evidence': evidence,
                     'previously_rejected': f"{rj['date']} ({rj['run']}): {rj['text']}" if rj else ''})

    # resolved report per check + files read
    read, rpt_of = set(), {}
    for n, c in checks.items():
        p = cc._find_check_report(rd, n, c)
        if p:
            rpt_of[n] = p
            read.add(os.path.realpath(p))
    for f in cfg.get('mandatory_files', []):
        read.add(os.path.realpath(os.path.join(rd, cc._expand_placeholders(f, rd))))

    # A. lax checks
    by_rpt = {}
    for n, p in sorted(rpt_of.items()):
        by_rpt.setdefault(p, []).append(n)
    for p, names_ in sorted(by_rpt.items()):
        try:
            text = open(p, errors='replace').read()
        except OSError:
            continue
        passing = [n for n in names_ if st_of.get(n) == 'PASS']
        failing = [n for n in names_ if st_of.get(n) in ('FAIL', 'CONFIG_ERROR')]
        for n in passing:
            c = checks[n]
            pat = c.get('metric_pattern', '')
            if pat and c.get('operator') in ('>=', '>') and not re.search(r'wns|tns|slack|margin', n) and \
                    (c.get('unit') == '%' or re.search(r'coverage|rate|pct|ratio|percent', n)) and \
                    str(c.get('default_threshold', '')).strip() in ('0', '0.0'):
                m = re.search(pat, text, re.M)
                line = text[text.rfind('\n', 0, m.start()) + 1:text.find('\n', m.end())].strip() if m else ''
                tgt = re.search(r'target\s+([0-9.]+)\s*%?', line)
                add('A', n, f'vacuous threshold {c["operator"]} {c["default_threshold"]}'
                    + (f'; the report states target {tgt.group(1)} ({"NOT MET" if "NOT MET" in line else "met"})'
                       if tgt else ''),
                    change=f'default_threshold of {n} in global/config/exit/v1.0.0/{M}_config.tcl'
                    + (f' -> {tgt.group(1)} (the project target)' if tgt else ' -> a real target'), evidence=line)
        bad = [ln.strip() for ln in text.splitlines() if BAD_WORDS.search(ln)]
        if bad and passing:
            cov = f' (gate covered: {", ".join(failing)} FAIL)' if failing else ' (NO failing check reads it)'
            add('A', os.path.basename(p), f'{len(passing)} passing check(s) ({", ".join(passing)}) read '
                f'{C.rel(ctx, p)}, which reports {len(bad)} NOT MET / FAIL / OPEN line(s){cov}',
                evidence=' | '.join(bad[:3]))

    # A2. contradictions: a passing count check reads 0, another exit-node report has the same count > 0
    node_kv = []
    if ndir:
        for f in glob.glob(os.path.join(ndir, 'reports', '*.rpt')):
            for ln in open(f, errors='replace').read().split('\n'):
                m = KV.match(ln)
                if m and m.group(2) != 'N/A':
                    node_kv.append((f, m.group(1).strip(), float(m.group(2)), ln.strip()))
    for n, p in sorted(rpt_of.items()):
        c = checks[n]
        pat = c.get('metric_pattern') or c.get('grep_pattern')
        if st_of.get(n) != 'PASS' or not pat:
            continue
        head = C.literal_head(pat)
        if not head or not re.search(r'violation|error|short|open', head, re.I):
            continue
        for f, key, val, ln in node_kv:
            if val > 0 and os.path.realpath(f) != os.path.realpath(p) and toks(head) <= toks(key):
                add('A', n, f'PASSes on "{head}" in {os.path.basename(p)} but {os.path.basename(f)} reports '
                    f'{key} = {val:g} - the two reports disagree', evidence=ln)
                break

    # B. peer gaps
    own = list(checks)
    mine = set(own) | {kind_of(n, pfx) for n in own}
    peers = []
    for pm in C.all_milestones():
        if pm == M or cc.get_milestone_discipline(pm) != disc:
            continue
        if disc == 'PD' and M in order and (pm not in order or order.index(pm) > order.index(M)):
            continue  # PD: earlier exits of MILESTONE_ORDER only (signoff checklists are their own flow)
        if disc != 'PD' or M not in order:  # same family: same flow or shares a check
            pc_, _ = cc._load_and_validate_config(pm, rd)
            if (pc_ or {}).get('milestone_info', {}).get('flow_type') == info.get('flow_type'):
                peers.append(pm)
                continue
            pn = list((pc_ or {}).get('mandatory_checks', {})) + list((pc_ or {}).get('optional_checks', {}))
            pp = milestone_prefixes(pm, pc_ or {})
            if not any(n in mine or kind_of(n, pp) in mine or kind_of(n, pfx) in mine for n in pn):
                continue
        peers.append(pm)
    seen = set()
    for pm in peers:
        pc, _ = cc._load_and_validate_config(pm, rd)
        if not pc:
            continue
        ppfx = milestone_prefixes(pm, pc)
        for kind in ('mandatory_checks', 'optional_checks'):
            for n, c in (pc.get(kind) or {}).items():
                k = kind_of(n, ppfx)
                if n in mine or k in mine or kind_of(n, pfx) in mine or k in seen or covered(k, own):
                    continue
                seen.add(k)
                new = f'{prefix}_{k}'
                g = tmap.get(f'grep,{n}')
                rp = tmap.get(f'report,{n}', tmap.get('report', '')).replace('${exit_node}', node)
                cmd = ''
                if g and rp:
                    cmd = (f'bin/cbflow flow checklist add-check --milestone {M} --name {new} '
                           f'--type {kind.split("_")[0]} --description "{c.get("description", k)}" '
                           f'--grep-file "{rp}" --grep-pattern \'{g}\' --grep-pass-if '
                           f'{tmap.get("grep_pass_if," + n, "found")}')
                elif c.get('script') == 'check_file_exists.tcl' and c.get('report_file'):
                    fp = tmap.get(f'report,{n}', c['report_file']).replace('${exit_node}', node)
                    cmd = (f'bin/cbflow flow checklist add-check --milestone {M} --name {new} --type file '
                           f'--file-path "{fp}"   # {"exists" if os.path.exists(os.path.join(rd, fp)) else "ABSENT"}'
                           f' in this run')
                add('B', new, f'{pm} has {n} ({kind.split("_")[0]}: {c.get("description", "")}); {M} has no '
                    f'"{k}" check', cmd=cmd,
                    change='' if cmd else f'copy {n} from {pm}_config.tcl (adapt report path) + tool-map entry')

    # C. unchecked metrics
    carriers = []
    if ndir:
        for d in ('reports', 'outputs'):
            for f in METRIC_FILES:
                carriers += glob.glob(os.path.join(ndir, d, f))
    for p in rpt_of.values():
        if os.path.basename(p) in METRIC_FILES and p not in carriers:
            carriers.append(p)
    for mf in cfg.get('mandatory_files', []):
        p = os.path.join(rd, cc._expand_placeholders(mf, rd))
        if os.path.basename(p) in METRIC_FILES and os.path.exists(p) and p not in carriers:
            carriers.append(p)
    pats = [c.get('metric_pattern') or c.get('grep_pattern') for c in checks.values()
            if c.get('metric_pattern') or c.get('grep_pattern')]
    heads = {C.literal_head(pt).lower() for pt in pats} - {''}
    keys_done, nmet = set(), 0
    for p in carriers:
        relp = C.rel(ctx, p)
        for ln in open(p, errors='replace').read().split('\n'):
            m = KV.match(ln)
            if not m:
                continue
            key, val, unit, rest = m.group(1).strip(), m.group(2), m.group(3) or '', m.group(4)
            if INFO_KEYS.match(key) or slug(key) in keys_done:
                continue
            keys_done.add(slug(key))
            hit = False
            for pt in pats:
                try:
                    if re.search(pt, ln.strip()) or re.search(pt, ln):
                        hit = True
                        break
                except re.error:
                    pass
            if hit or key.lower() in heads or covered(key, own):
                continue
            nmet += 1
            cls = classify(key, unit, rest)
            try:
                num = float(val)
            except ValueError:
                num = None
            bad = num is not None and ((cls == 'count' and num > 0) or (cls in ('slack', 'tns') and num < 0))
            name = f'{prefix}_{slug(key)}'
            kpat = re.escape(key).replace('\\ ', ' ').replace(' ', r'\s+')
            cmd, change = '', ''
            if cls == 'count':
                cmd = (f'bin/cbflow flow checklist add-check --milestone {M} --name {name} --type optional '
                       f'--description "{key} must be 0" --grep-file "{relp}" '
                       f'--grep-pattern \'^\\s*{kpat}\\s*:\\s*0\\s*$\' --grep-pass-if found')
            elif cls == 'tns':
                cmd = (f'bin/cbflow flow checklist add-check --milestone {M} --name {name} --type optional '
                       f'--description "{key} zero" --grep-file "{relp}" '
                       f'--grep-pattern \'^\\s*{kpat}\\s*:\\s*(N/A|-?0(\\.0+)?)\\s*$\' --grep-pass-if found')
            elif cls == 'slack':
                cmd = (f'bin/cbflow flow checklist add-check --milestone {M} --name {name} --type optional '
                       f'--description "{key} non-negative" --grep-file "{relp}" '
                       f'--grep-pattern \'^\\s*{kpat}\\s*:\\s*(N/A|[0-9])\' --grep-pass-if found')
            else:
                change = (f'metric check (add-check cannot set a numeric threshold): {M}_config.tcl entry '
                          f'"{name}" with operator / default_threshold + tool overlay '
                          f'<arr>(checklist,metric,{name}) {{^\\s*{kpat}\\s*:\\s*([0-9.]+)}}')
            add('C', name, ('VIOLATING VALUE, unread: ' if bad else '') +
                f'{key} = {val}{unit} ({cls}) in {os.path.basename(p)} - no check reads it',
                cmd=cmd, change=change, evidence=ln.strip()[:140])
            sugg[-1]['_rank'] = (0 if bad else 1 if cls in ('count', 'slack', 'tns') else 2 if cls == 'percent' else 3)
    cs = sorted([x for x in sugg if x['section'] == 'C'], key=lambda x: x['_rank'])
    sugg = [x for x in sugg if x['section'] != 'C'] + cs[:a.max]

    # D. library checks measurable here but not applicable
    lib_dir = os.path.join(C.EXIT_DIR, 'checks')
    exit_rpt = os.path.join(rd, tmap.get('report', '').replace('${exit_node}', node)) if tmap.get('report') else ''
    etext = open(exit_rpt, errors='replace').read() if exit_rpt and os.path.exists(exit_rpt) else ''
    if etext:
        for f in sorted(glob.glob(os.path.join(lib_dir, '*_checks.tcl'))):
            cat = os.path.basename(f)[:-11]
            for n, c in cc.parse_tcl_array_block(open(f).read(), f'{cat}_checks').items():
                if n in checks or f'metric,{n}' not in tmap:
                    continue
                mm = re.search(tmap[f'metric,{n}'], etext, re.M)
                if mm:
                    add('D', n, f'{cat} library check ({c.get("severity", "-")}: {c.get("description", "")}) is '
                        f'measurable here ({mm.group(0).strip()}) but not applicable to {M}',
                        change=f'add {M} to applicable_milestones of {n} in global/config/exit/v1.0.0/checks/'
                        f'{cat}_checks.tcl (and {cat} in check_packs of {M}_config.tcl)')

    # E. unread reports in the exit node
    unread = []
    if ndir:
        for d in ('reports', 'outputs'):
            for p in sorted(glob.glob(os.path.join(ndir, d, '*'))):
                if os.path.isfile(p) and os.path.realpath(p) not in read and \
                        re.search(r'\.(rpt|log|json|txt)$', p):
                    unread.append(C.rel(ctx, p))

    # ── report ──
    print(f"MISSING-CHECK ANALYSIS  {M}  ({disc}{', tape-out' if M in tapeout else ''})  run {ctx['run']}")
    print(f"exit node {node or '-'}  checks: {sum(1 for c in checks.values() if c['_kind'] == 'mandatory')} "
          f"mandatory, {sum(1 for c in checks.values() if c['_kind'] == 'optional')} optional, "
          f"{sum(1 for c in checks.values() if c['_kind'] == 'library')} library; peers compared: "
          f"{' '.join(peers) or '-'}")
    names = {'A': 'A. Lax checks (pass while the report disagrees)', 'B': 'B. Peer-milestone gaps',
             'C': f'C. Unchecked metrics ({nmet} found, {min(nmet, a.max)} listed)',
             'D': 'D. Library checks measurable here, not applicable', 'E': 'E. Unread exit-node reports'}
    for sec in 'ABCD':
        rows = [s for s in sugg if s['section'] == sec]
        rows.sort(key=lambda s: (bool(s['previously_rejected']), s.get('_rank', 0)))
        print(f'\n== {names[sec]}: {len(rows)}')
        for s in rows:
            print(f"* {s['name']}: {s['why']}")
            if s['evidence']:
                print(f"    > {s['evidence']}")
            if s['command']:
                print(f"    cmd   : {s['command']}")
            if s['config_change']:
                print(f"    change: {s['config_change']}")
            if s['previously_rejected']:
                print(f"    NOTE  : previously rejected {s['previously_rejected']}")
    print(f'\n== {names["E"]}: {len(unread)}')
    groups = {}
    for u in unread:
        g = re.sub(r'_(I2O|I2R|R2O|R2R)(?=_)', '_<group>', u)
        g = re.sub(r'_[a-z]+_(ss|tt|ff|sf|fs)_[a-z0-9_]+(?=\.\w+$)', '_<scenario>', g)
        groups.setdefault(g, []).append(u)
    for g, us in sorted(groups.items()):
        print(f'    {g}' + (f'  (x{len(us)})' if len(us) > 1 else ''))
    if a.json:
        json.dump({'milestone': M, 'run': rd, 'exit_node': node, 'suggestions': sugg, 'unread_reports': unread},
                  open(a.json, 'w'), indent=1)


if __name__ == '__main__':
    main()
