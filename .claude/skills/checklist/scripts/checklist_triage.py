#!/usr/bin/env python3
"""Rank a milestone's checklist failures with their evidence (read-only).

    python3 checklist_triage.py <run_dir> --milestone <M> [--status <json>] [--all] [--json out.json]

Input: the newest logs/checklist_status_<M>_*.json written by
`cbflow flow checklist status` (or --status, else the RACE DB checklist_results
rows). The check definitions are resolved exactly as `status` resolves them
(milestone config + the run's <arr>(checklist,report|metric|grep|
mandatory_files,*) tool map, via PD/utils/commands/checklist_cmd.py).

Per non-passing check: tier (blocking first), severity, the report it read,
the matching / nearest report line, value vs threshold, the phase policy
threshold (threshold_overrides.tcl), the owning node's state (BYPASSED, job
status), a likely cause, the remediation_config.tcl suggestions, waiver
eligibility (waiver_config.tcl policy; BTO / MTO not waivable), and prior
learned entries for the check (learned/<tech>/{_tech,<block>}.md).
Tiers: 1 mandatory FAIL / CONFIG_ERROR, 2 missing mandatory file,
3 critical library FAIL, 4 mandatory not run (NA / PENDING),
5 non-blocking FAIL (TAPE-OUT REVIEW at BTO / MTO), 6 no data (NA / PENDING).
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ckl_common as C  # noqa: E402

SEV = {'critical': 0, 'major': 1, 'minor': 2}
BAD = re.compile(r'\b(NOT MET|FAIL(ED)?|VIOLATED|OPEN|NOT IMPLEMENTED|MISMATCH(ES)?)\b')
TIER_NAME = {1: 'BLOCKING - mandatory check failed', 2: 'BLOCKING - mandatory file missing',
             3: 'BLOCKING - critical library check failed', 4: 'BLOCKING - mandatory check not run',
             5: 'NON-BLOCKING - failed', 6: 'NO DATA - not measurable in this run'}


def evidence(report, cfg):
    """(lines, head_found) — report lines that show the checked value."""
    try:
        text = open(report, encoding='utf-8', errors='replace').read()
    except OSError:
        return [], False
    pat = cfg.get('metric_pattern') or cfg.get('grep_pattern') or ''
    if pat:
        try:
            m = re.search(pat, text, re.MULTILINE)
        except re.error:
            m = None
        if m:
            s = text.rfind('\n', 0, m.start()) + 1
            e = text.find('\n', m.end())
            return [text[s:e if e >= 0 else None].strip()[:160]], True
        head = C.literal_head(pat)
        hits = [ln.strip()[:160] for ln in text.splitlines() if head and head.lower() in ln.lower()][:3]
        if cfg.get('grep_pattern'):  # a verdict line failed: show why (NOT MET / FAIL / OPEN lines)
            why = [ln.strip()[:160] for ln in text.splitlines()
                   if BAD.search(ln) and ln.strip()[:160] not in hits]
            return hits + why[:5], bool(hits)
        return hits, bool(hits)
    hits = [ln.strip()[:160] for ln in text.splitlines() if re.search(r'\bFAIL(ED)?\b', ln, re.I)]
    return hits[:3], bool(hits)


def threshold_of(cfg):
    if cfg.get('operator') and str(cfg.get('default_threshold', '')) != '':
        return f"{cfg['operator']} {cfg['default_threshold']}" + (f" {cfg['unit']}" if cfg.get('unit') else '')
    if cfg.get('grep_pattern'):
        return f"grep {cfg.get('grep_pass_if', 'found')}: {cfg['grep_pattern']}"
    return cfg.get('criteria', '')


def likely_cause(r, cfg, ctx, report_rel, state, ev_found):
    st = r['status']
    path = report_rel or cfg.get('report_file') or cfg.get('report_pattern') or ''
    m = re.match(r'work/([^/]+)/', path)
    if st == 'CONFIG_ERROR':
        return 'check definition / phase config error: ' + r.get('detail', '')
    if st in ('NA', 'PENDING') and not ev_found:
        if m and m.group(1) != ctx['flow']:
            return (f'check reads work/{m.group(1)}/... but this is a {ctx["flow"]} run: the tool overlay has no '
                    f'<arr>(checklist,...) entry for it (definition does not fit this flow)')
        if state.startswith('BYPASSED'):
            return 'the stage that writes this report was bypassed; the exit needs it'
        if state.startswith('node not in this run'):
            return 'the check expects a node this run does not have (flow / tool-map mismatch)'
        if state.startswith('job FAIL'):
            return 'the stage failed before writing the report - fix the stage first'
        if state.startswith('job DONE') and st == 'NA':
            return 'the stage ran but the report is absent - tool handler did not write it or the path differs'
        if st == 'PENDING':
            return 'report present but the pattern does not match any line (tool output format vs check pattern)'
        return 'no report in the run (stage not run / not produced by this tool)'
    if st == 'FAIL':
        if cfg.get('grep_pattern') and not ev_found:
            return 'the pattern is not in the report at all - wrong report for this check or tool never writes it'
        if cfg.get('grep_pattern'):
            return 'the report line is present but its value does not satisfy the check'
        if cfg.get('metric_pattern'):
            return 'measured value outside the threshold'
        return 'the report carries a FAIL verdict'
    return ''


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('run_dir')
    ap.add_argument('--milestone', required=True)
    ap.add_argument('--status', help='status JSON (default: newest logs/checklist_status_<M>_*.json)')
    ap.add_argument('--all', action='store_true', help='detail no-data checks too')
    ap.add_argument('--json', help='write the ranked items as JSON')
    a = ap.parse_args()
    M = a.milestone
    ctx = C.run_context(a.run_dir)
    src, data = C.latest_status(ctx['run_dir'], M, a.status)
    if not data:
        sys.exit(f'triage: no status for {M} in {a.run_dir} - run first:\n'
                 f'  bin/cbflow flow checklist status --milestone {M} --run-dir {a.run_dir}')
    cfg, cfg_path = C.resolved_config(M, ctx['run_dir'])
    order, tapeout = C.release_lists()
    is_tapeout = M in tapeout
    wpol = C.waiver_policy()
    rems = C.remediations()
    pol = C.threshold_policy()
    learned = C.learned_entries(ctx['tech'], ctx['block'])
    kinds = {'mandatory': cfg.get('mandatory_checks', {}), 'optional': cfg.get('optional_checks', {}),
             'library': cfg.get('library_checks', {})}

    waivable = 'yes'
    if is_tapeout and str(wpol.get(f'allow_{M.lower()}_waivers', 'false')).lower() != 'true':
        waivable = f'no - waiver_config.tcl allow_{M.lower()}_waivers false (tape-out)'
    elif M in tapeout:
        waivable = 'yes (tape-out waivers enabled in policy)'
    max_days = wpol.get('max_waiver_duration_days', '90')

    items, counts, newest_rpt = [], {}, 0.0
    for kind, defs in kinds.items():
        for r in data.get(f'{kind}_checks', []):
            counts[r['status']] = counts.get(r['status'], 0) + 1
            if r['status'] in ('PASS', 'WAIVED', 'SKIPPED'):
                continue
            c = defs.get(r['name'], {})
            sev = c.get('severity', '') or ''
            if kind == 'mandatory':
                tier = 1 if r['status'] in ('FAIL', 'CONFIG_ERROR') else 4
            elif r['status'] in ('FAIL', 'CONFIG_ERROR'):
                tier = 3 if (kind == 'library' and sev == 'critical') else 5
            else:
                tier = 6
            report = C.cc()._find_check_report(ctx['run_dir'], r['name'], c)
            if report:
                newest_rpt = max(newest_rpt, os.path.getmtime(report))
            rrel = C.rel(ctx, report) if report else ''
            ev, found = evidence(report, c) if report else ([], False)
            want = rrel or C.cc()._expand_placeholders(c.get('report_file') or c.get('report_pattern') or '',
                                                        ctx['run_dir'])
            node, state = C.node_state(ctx, want)
            rem_key, metric = C.check_keys(r['name'])
            pval, player = C.policy_threshold(pol, ctx['project'], ctx['phase'], M, metric) if metric else (None, '')
            prior = [e for e in learned if e['check'] == r['name']]
            items.append({
                'tier': tier, 'kind': kind, 'name': r['name'], 'id': c.get('id', ''), 'status': r['status'],
                'severity': sev, 'category': c.get('category', c.get('source', '')),
                'description': c.get('description', ''), 'value': r.get('value', ''),
                'threshold': threshold_of(c), 'detail': r.get('detail', ''),
                'report': rrel or (want and f'{want} (absent)'), 'evidence': ev, 'node': node,
                'node_state': state, 'cause': likely_cause(r, c, ctx, rrel, state, found),
                'policy_threshold': (f'{pval} {C.POLICY_UNIT.get(metric, "")} ({player})'
                                     if pval is not None else ''),
                'remediation_key': rem_key if rem_key in rems else '',
                'remediation': rems.get(rem_key, {}) if tier < 6 else {},
                'waivable': waivable if tier < 6 else '',
                'learned': prior[-3:],
            })
    for fs in data.get('file_status', []):
        if fs.get('exists'):
            continue
        p = C.cc()._expand_placeholders(fs['path'], ctx['run_dir'])
        node, state = C.node_state(ctx, p)
        m = re.match(r'work/([^/]+)/', p)
        cause = ''
        if m and m.group(1) != ctx['flow']:
            cause = (f'path is under work/{m.group(1)}/ but this is a {ctx["flow"]} run: the tool overlay has no '
                     f'<arr>(checklist,mandatory_files,{M}) for this flow, so the milestone default applies')
        elif state.startswith('BYPASSED'):
            cause = 'the stage that writes it was bypassed'
        elif state.startswith('job FAIL'):
            cause = 'the stage failed'
        else:
            cause = 'file not produced'
        items.append({'tier': 2, 'kind': 'file', 'name': p, 'status': 'MISSING', 'severity': '',
                      'report': p, 'evidence': [], 'node': node, 'node_state': state, 'cause': cause,
                      'threshold': 'file exists', 'value': '', 'remediation': {}, 'waivable': '',
                      'learned': [e for e in learned if e['check'] == p][-3:]})
    items.sort(key=lambda i: (i['tier'], SEV.get(i['severity'], 3), i['name']))

    # ── report ──
    print(f"CHECKLIST TRIAGE  {M}  ({'tape-out: strictest' if is_tapeout else C.cc().get_milestone_discipline(M)})")
    print(f"run      : {ctx['run_dir']}")
    print(f"context  : flow {ctx['flow']}  phase {ctx['phase']}  project {ctx['project']}  block {ctx['block']}  "
          f"tech {ctx['tech']}")
    print(f"status   : {src}  ({data.get('timestamp', '?')})  verdict {data.get('verdict', '?')}  "
          f"completion {data.get('completion_pct', 0):.1f}%")
    print(f"config   : {os.path.relpath(cfg_path, C.ROOT) if cfg_path else ''}")
    print('counts   : ' + '  '.join(f'{k} {v}' for k, v in sorted(counts.items())))
    ts = data.get('timestamp', '')
    try:
        if newest_rpt and datetime.fromtimestamp(newest_rpt) > datetime.strptime(ts, '%Y-%m-%d %H:%M:%S'):
            print('WARNING  : reports are newer than this status - rerun `checklist status` first')
    except ValueError:
        pass
    if learned:
        print(f"learned  : {len(learned)} prior entries ({ctx['tech']}/_tech.md + {ctx['block']}.md)")
    w = data.get('active_waivers') or []
    if w:
        print('waivers  : ' + ', '.join(f"{x.get('id')}:{x.get('check')} (exp {x.get('expiry_date')})" for x in w))
    print(f"waivers allowed for {M}: {waivable}" + ('' if waivable.startswith('no') else f' (max {max_days} days)'))

    cur = None
    nodata = [i for i in items if i['tier'] == 6]
    for i in items:
        if i['tier'] == 6 and not a.all:
            continue
        if i['tier'] != cur:
            cur = i['tier']
            label = TIER_NAME[cur]
            if cur == 5 and is_tapeout:
                label += ' (TAPE-OUT REVIEW: every one needs a fix or an explicit owner decision)'
            print(f'\n== {cur}. {label}')
        sev = f" [{i['severity']}]" if i['severity'] else ''
        print(f"\n* {i['name']}{(' (' + i['id'] + ')') if i.get('id') else ''}{sev}  {i['status']}  "
              f"{i.get('kind', '')} {('- ' + i['description']) if i.get('description') else ''}")
        if i.get('value') or i.get('threshold'):
            print(f"    value    : {i.get('value') or '-'}   check: {i.get('threshold') or '-'}")
        if i.get('policy_threshold'):
            print(f"    policy   : {i['policy_threshold']}  (threshold_overrides.tcl; status does not apply it)")
        print(f"    report   : {i['report'] or '-'}")
        for ln in i['evidence']:
            print(f"      > {ln}")
        if i.get('node_state'):
            print(f"    node     : {i['node']}: {i['node_state']}")
        if i.get('cause'):
            print(f"    cause    : {i['cause']}")
        rem = i.get('remediation') or {}
        if rem:
            print(f"    remedy   : [{i['remediation_key']}] {rem.get('symptom', '')} (severity {rem.get('severity', '-')})")
            for s in rem.get('suggestions', [])[:4]:
                print(f"               {s}")
            if rem.get('escalation'):
                print(f"               escalation: {rem['escalation']}")
        for e in i['learned']:
            print(f"    learned  : {e['date']} {e['kind']} ({e['run']}): {e['text']}")
        if i.get('waivable') and i['tier'] <= 5:
            print(f"    waiver   : {i['waivable']}")
    if nodata and not a.all:
        by = {}
        for i in nodata:
            by.setdefault(i.get('category') or i['kind'], []).append(i['name'])
        print(f'\n== 6. {TIER_NAME[6]} ({len(nodata)}; --all for detail)')
        for k, v in sorted(by.items()):
            print(f"    {k:<18} {len(v):>3}: {' '.join(v[:8])}{' ...' if len(v) > 8 else ''}")
    if a.json:
        json.dump({'context': {k: v for k, v in ctx.items() if k != 'db'}, 'milestone': M,
                   'status_source': src, 'items': items}, open(a.json, 'w'), indent=1, default=str)


if __name__ == '__main__':
    main()
