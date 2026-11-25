#!/usr/bin/env python3
"""RTL checks for the CBflow open-source RTL flows (RTL_LINT / RTL_CDC /
UPF_CHECK). Runs inside the CBflow tool container (python3, PyYAML).

Every check writes the same violations CSV (rule,severity,file,line,message,
tool,status) — status open | waived | excluded — that release_utils counts
(`violations_final.csv`), and the same sign-off summary.

  lint-collect  --verilator-sarif <f> [--slang-log <f>] [--verible-log <f>]
                [--verible-severity warning|info] [--exclude <glob> …]
                [--generated <glob> …] -o violations.csv
                slang elaboration diagnostics, Verilator -Wall (SARIF), Verible
                style lint -> one CSV. --exclude: files whose findings are
                dropped (simulation stubs); --generated: tool-generated RTL —
                findings kept, status excluded (reported, not signed off on).
  cdc-collect   --json <opencdc json> [--log <opencdc stderr>] -o violations.csv
                opencdc findings (+ blocks it could not analyse, as warnings)
  upf-check     --upf <upf> --design <yosys json> --top <t> [--spec <spec.json>]
                -o violations.csv --report <rpt>
                UPF (IEEE 1801 subset) checked against the elaborated design and
                the block spec: domains / elements, supply ports / nets /
                connections, primary supplies, port states, PST states,
                isolation on crossings out of switchable domains
  waive         --violations <csv> [--waivers <yaml>] [--today YYYY-MM-DD]
                -o violations_final.csv --report <rpt>
                waivers: [{rule, file (glob), line?, message? (regex), reason,
                owner, expires (YYYY-MM-DD)}] — reason / owner / expires
                mandatory; expired waivers do not apply (listed)
  summary       --violations <violations_final.csv> --check <LINT|CDC|UPF>
                --design <d> [--fail-on-warning true|false] -o <signoff.rpt>
                counts per severity / tool / status; PASS = 0 open errors
                (+ 0 open warnings with --fail-on-warning true)
"""
import argparse
import csv
import datetime
import fnmatch
import json
import os
import re
import sys

COLS = ['rule', 'severity', 'file', 'line', 'message', 'tool', 'status']


def _die(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


def _write(rows, path):
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=COLS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, '') for k in COLS})


def _read(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))


def _match_any(path, globs):
    return any(fnmatch.fnmatch(path, g) or fnmatch.fnmatch(os.path.basename(path), g) for g in globs or [])


# ═══════════════════════════════════════════════════════════════════════════
# lint
# ═══════════════════════════════════════════════════════════════════════════
def cmd_lint_collect(a):
    rows = []
    # Verilator SARIF 2.1.0
    sar = json.load(open(a.verilator_sarif))
    for run in sar.get('runs', []):
        for res in run.get('results', []):
            lvl = res.get('level', 'warning')
            if not res.get('locations'):
                continue            # the run summary ("Exiting due to N warning(s)")
            loc = res['locations'][0].get('physicalLocation', {})
            rows.append({'rule': res.get('ruleId', ''), 'severity': 'error' if lvl == 'error' else 'warning',
                         'file': loc.get('artifactLocation', {}).get('uri', '').replace('file://', ''),
                         'line': loc.get('region', {}).get('startLine', ''),
                         'message': ' '.join(res.get('message', {}).get('text', '').split(' ... ')[0].split()),
                         'tool': 'verilator'})
    # slang: <file>:<line>:<col>: <severity>: <message> [-W<rule>]
    if a.slang_log and os.path.isfile(a.slang_log):
        for ln in open(a.slang_log, errors='replace'):
            m = re.match(r'^(.+?):(\d+):\d+: (error|warning): (.*?)(?: \[-W([\w-]+)\])?\s*$', ln)
            if m:
                rows.append({'rule': m.group(5) or ('elab-error' if m.group(3) == 'error' else 'elab-warning'),
                             'severity': m.group(3), 'file': m.group(1), 'line': m.group(2),
                             'message': m.group(4), 'tool': 'slang'})
            elif re.match(r'^error: ', ln):
                rows.append({'rule': 'elab-error', 'severity': 'error', 'file': '', 'line': '',
                             'message': ln.strip()[7:], 'tool': 'slang'})
    # verible: <file>:<line>:<col>[-<col>]: <message> [Style: …] [<rule>]
    if a.verible_log and os.path.isfile(a.verible_log):
        for ln in open(a.verible_log, errors='replace'):
            m = re.match(r'^(.+?):(\d+):[\d-]+: (.*?)\s*(?:\[Style:[^\]]*\]\s*)?\[([\w-]+)\]\s*$', ln)
            if m:
                rows.append({'rule': m.group(4), 'severity': a.verible_severity, 'file': m.group(1),
                             'line': m.group(2), 'message': m.group(3), 'tool': 'verible'})
            elif re.match(r'^(.+?):(\d+):[\d-]+: syntax error', ln):
                rows.append({'rule': 'syntax', 'severity': 'error', 'file': ln.split(':')[0], 'line': ln.split(':')[1],
                             'message': ln.strip(), 'tool': 'verible'})
    out = []
    for r in rows:
        if _match_any(r['file'], a.exclude):
            continue
        r['status'] = 'excluded' if _match_any(r['file'], a.generated) else 'open'
        out.append(r)
    _write(out, a.output)
    print(f'lint-collect: {len(out)} findings ({sum(r["status"] == "open" for r in out)} open)', file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# CDC
# ═══════════════════════════════════════════════════════════════════════════
def cmd_cdc_collect(a):
    d = json.load(open(a.json))
    rows = []
    for f in d.get('findings', []):
        loc = f.get('location') or {}
        rows.append({'rule': f.get('rule') or f.get('id') or f.get('rule_id', 'CDC'),
                     'severity': (f.get('severity') or 'error').lower(),
                     'file': loc.get('file', f.get('file', '')), 'line': loc.get('line', f.get('line', '')),
                     'message': ' '.join(str(f.get('reason') or f.get('message') or f.get('description', '')).split())
                                + (f' [{f["source_domain"]} -> {f["dest_domain"]}]' if f.get('source_domain') else ''),
                     'tool': 'opencdc', 'status': 'open'})
    skipped = 0
    if a.log and os.path.isfile(a.log):
        for ln in open(a.log, errors='replace'):
            m = re.match(r'^Warning: Skipped procedural block with unrecoverable clock at (.+?):(\d+)', ln)
            if m:
                skipped += 1
                rows.append({'rule': 'CDC-SKIPPED-BLOCK', 'severity': 'info', 'file': m.group(1), 'line': m.group(2),
                             'message': 'procedural block not analysed (no clock recovered — combinational always @(*))',
                             'tool': 'opencdc', 'status': 'open'})
            elif ln.startswith('Error:'):
                rows.append({'rule': 'CDC-ANALYSIS-ERROR', 'severity': 'error', 'file': '', 'line': '',
                             'message': ln.strip(), 'tool': 'opencdc', 'status': 'open'})
    if d.get('analysis_status') not in ('complete', None):
        rows.append({'rule': 'CDC-INCOMPLETE', 'severity': 'error', 'file': '', 'line': '',
                     'message': f'opencdc analysis_status {d.get("analysis_status")}', 'tool': 'opencdc', 'status': 'open'})
    _write(rows, a.output)
    print(f'cdc-collect: {len(d.get("findings", []))} findings, {skipped} blocks not analysed', file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# UPF
# ═══════════════════════════════════════════════════════════════════════════
def _upf_cmds(path):
    """UPF commands as (name, args) with continuation lines joined; Tcl-ish
    tokenization ({…} groups kept as one token)."""
    text = re.sub(r'\\\n', ' ', open(path).read())
    cmds = []
    for n, ln in enumerate(text.split('\n'), 1):
        ln = ln.split('#', 1)[0].strip() if not ln.strip().startswith('#') else ''
        if not ln:
            continue
        toks, cur, depth = [], '', 0
        for ch in ln:
            if ch == '{':
                depth += 1
                if depth == 1:
                    continue
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    toks.append(cur)
                    cur = ''
                    continue
            if ch.isspace() and depth == 0:
                if cur:
                    toks.append(cur)
                    cur = ''
                continue
            cur += ch
        if cur:
            toks.append(cur)
        cmds.append((n, toks[0], toks[1:]))
    return cmds


def _opt(args, name, many=False):
    out = []
    for i, t in enumerate(args):
        if t == name and i + 1 < len(args):
            out.append(args[i + 1])
    return out if many else (out[0] if out else None)


def cmd_upf_check(a):
    cmds = _upf_cmds(a.upf)
    design = json.load(open(a.design))
    if a.top not in design['modules']:
        _die(f'top {a.top} not in {a.design}')
    insts = set()

    def walk(mod, prefix):
        for cn, c in design['modules'][mod].get('cells', {}).items():
            path = f'{prefix}{cn}'
            insts.add(path)
            if c['type'] in design['modules'] and not design['modules'][c['type']].get('attributes', {}).get('blackbox'):
                walk(c['type'], path + '/')
    walk(a.top, '')
    ports = set(design['modules'][a.top]['ports'])
    domains, sports, snets, conns, dsup, pstates, psts, isos = {}, set(), set(), {}, {}, {}, {}, []
    rows = []

    def v(rule, sev, line, msg):
        rows.append({'rule': rule, 'severity': sev, 'file': a.upf, 'line': line, 'message': msg,
                     'tool': 'upf_check', 'status': 'open'})
    for n, c, args in cmds:
        if c == 'create_power_domain':
            dn = args[0]
            els = (_opt(args, '-elements') or '').split()
            domains[dn] = {'line': n, 'scope': '-include_scope' in args, 'elements': els}
            for e in els:
                if e not in ('.',) and e not in insts:
                    v('UPF-ELEMENT', 'error', n, f'{dn}: element {e} is not an instance of {a.top}')
        elif c == 'create_supply_port':
            sports.add(args[0])
            if args[0] not in ports:
                v('UPF-SUPPLY-PORT', 'info', n, f'supply port {args[0]} (not an RTL port — inserted by PD)')
        elif c == 'create_supply_net':
            snets.add(args[0])
        elif c == 'connect_supply_net':
            conns[args[0]] = _opt(args, '-ports')
        elif c == 'set_domain_supply_net':
            dsup[args[0]] = (_opt(args, '-primary_power_net'), _opt(args, '-primary_ground_net'), n)
        elif c == 'add_port_state':
            pstates[args[0]] = [s.split()[0] for s in _opt(args, '-state', True)]
        elif c == 'create_pst':
            psts[args[0]] = {'supplies': (_opt(args, '-supplies') or '').split(), 'line': n}
        elif c == 'add_pst_state':
            pst = _opt(args, '-pst')
            st = (_opt(args, '-state') or '').split()
            if pst not in psts:
                v('UPF-PST', 'error', n, f'add_pst_state {args[0]}: pst {pst} not created')
            else:
                for sup, sv in zip(psts[pst]['supplies'], st):
                    if sv not in pstates.get(sup, []):
                        v('UPF-PST-STATE', 'error', n, f'pst {pst} state {args[0]}: {sup} has no port state {sv}')
        elif c == 'set_isolation':
            isos.append((n, _opt(args, '-domain'), args[0]))
        elif c in ('upf_version', 'set_scope', 'set_retention', 'set_level_shifter', 'map_isolation_cell',
                   'use_interface_cell', 'create_logic_port', 'create_logic_net', 'connect_logic_net',
                   'set_retention_control', 'set_isolation_control', 'create_power_switch', 'set_port_attributes',
                   'add_power_state', 'load_upf'):
            pass
        else:
            v('UPF-UNKNOWN-CMD', 'warning', n, f'command {c} not checked by the open-source UPF checker')
    if not domains:
        v('UPF-NO-DOMAIN', 'error', 0, 'no create_power_domain')
    for dn, d in domains.items():
        if dn not in dsup:
            v('UPF-PRIMARY', 'error', d['line'], f'{dn}: no set_domain_supply_net')
            continue
        p, g, ln = dsup[dn]
        for net in (p, g):
            if net not in snets:
                v('UPF-SUPPLY-NET', 'error', ln, f'{dn}: supply net {net} not created')
            elif net not in conns and net not in sports:
                v('UPF-CONNECT', 'error', ln, f'{dn}: supply net {net} not connected to a supply port')
    for sp in sports:
        if sp not in pstates:
            v('UPF-PORT-STATE', 'warning', 0, f'supply port {sp} has no add_port_state')
    scoped = [dn for dn, d in domains.items() if d['scope']]
    if len(scoped) > 1:
        v('UPF-SCOPE', 'error', 0, f'more than one domain includes the scope: {scoped}')
    # crossings: a switchable (OFF state) domain with elements driving another
    # domain needs isolation
    sw = {dn for dn in domains if any('OFF' in s.upper() for s in pstates.get(dsup.get(dn, (None,))[0], []))}
    if len(domains) > 1:
        for dn in sw:
            if not any(d == dn for _, d, _ in isos):
                v('UPF-ISOLATION', 'error', domains[dn]['line'], f'{dn} can be OFF and has no set_isolation for its outputs')
    # spec comparison
    if a.spec:
        if a.spec.endswith(('.yaml', '.yml')):
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            from spec_tool import _yaml_load      # YAML 1.2 booleans (ON / OFF power states)
            s = _yaml_load(a.spec)
        else:
            s = json.load(open(a.spec))
        pw = s.get('power') or {}
        sd = {d['name']: d for d in pw.get('domains', [])}
        for dn in sd:
            if dn not in domains:
                v('UPF-SPEC-DOMAIN', 'error', 0, f'spec domain {dn} not in the UPF')
        for dn in domains:
            if dn not in sd:
                v('UPF-SPEC-DOMAIN', 'error', domains[dn]['line'], f'UPF domain {dn} not in the spec')
            elif dn in dsup:
                sp = sd[dn]['supply']
                if (dsup[dn][0], dsup[dn][1]) != (sp['power'], sp['ground']):
                    v('UPF-SPEC-SUPPLY', 'error', dsup[dn][2],
                      f'{dn}: UPF supplies {dsup[dn][0]}/{dsup[dn][1]} vs spec {sp["power"]}/{sp["ground"]}')
    _write(rows, a.output)
    lines = [f'UPF check — {a.top} ({a.upf})', f'  Power domains   : {len(domains)}', f'  Supply ports    : {len(sports)}',
             f'  Supply nets     : {len(snets)}', f'  PSTs            : {len(psts)}', f'  Isolation       : {len(isos)}',
             f'  Switchable      : {len(sw)}', f'  Spec compared   : {"yes" if a.spec else "no"}',
             f'  Findings        : {len(rows)}'] + [f'  {r["severity"].upper()}: {r["rule"]}: {r["message"]}' for r in rows]
    open(a.report, 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines[:9]), file=sys.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# waivers / summary
# ═══════════════════════════════════════════════════════════════════════════
def cmd_waive(a):
    rows = _read(a.violations)
    today = datetime.date.fromisoformat(a.today) if a.today else datetime.date.today()
    waivers, bad, expired = [], [], []
    if a.waivers:
        import yaml
        w = yaml.safe_load(open(a.waivers)) or {}
        lst = w.get('waivers', w) if isinstance(w, dict) else w
        for i, x in enumerate(lst or []):
            miss = [k for k in ('rule', 'file', 'reason', 'owner', 'expires') if not x.get(k)]
            if miss:
                bad.append(f'waiver {i}: missing {miss}')
                continue
            exp = x['expires'] if isinstance(x['expires'], datetime.date) else datetime.date.fromisoformat(str(x['expires']))
            if exp < today:
                expired.append(f'waiver {i} ({x["rule"]} {x["file"]}) expired {exp}')
                continue
            x['_used'] = 0
            waivers.append(x)
    for r in rows:
        if r['status'] != 'open':
            continue
        for x in waivers:
            if not fnmatch.fnmatch(r['rule'], str(x['rule'])):
                continue
            if not (fnmatch.fnmatch(r['file'], x['file']) or fnmatch.fnmatch(os.path.basename(r['file']), x['file'])):
                continue
            if x.get('line') and str(x['line']) != str(r['line']):
                continue
            if x.get('message') and not re.search(x['message'], r['message']):
                continue
            r['status'] = 'waived'
            x['_used'] += 1
            break
    _write(rows, a.output)
    unused = [f'{x["rule"]} {x["file"]}' for x in waivers if not x['_used']]
    lines = [f'Waivers — {a.waivers or "(none)"}', f'  Active waivers  : {len(waivers)}',
             f'  Applied to      : {sum(r["status"] == "waived" for r in rows)} finding(s)',
             f'  Expired         : {len(expired)}', f'  Malformed       : {len(bad)}', f'  Unused          : {len(unused)}']
    lines += [f'  EXPIRED: {e}' for e in expired] + [f'  MALFORMED: {b}' for b in bad] + [f'  UNUSED: {u}' for u in unused]
    open(a.report, 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines[:6]), file=sys.stderr)
    if bad:
        sys.exit(1)


def cmd_summary(a):
    rows = _read(a.violations)
    cnt = {}
    for r in rows:
        k = (r['severity'], r['status'])
        cnt[k] = cnt.get(k, 0) + 1
    oe = cnt.get(('error', 'open'), 0)
    ow = cnt.get(('warning', 'open'), 0)
    fail_w = a.fail_on_warning == 'true'
    ok = oe == 0 and (ow == 0 or not fail_w)
    tools = sorted({r['tool'] for r in rows})
    lines = [f'{a.check} sign-off — {a.design}',
             f'  Findings        : {len(rows)}',
             f'  Open errors     : {oe}',
             f'  Open warnings   : {ow}',
             f'  Open info       : {cnt.get(("info", "open"), 0)}',
             f'  Waived          : {sum(v for (s, st), v in cnt.items() if st == "waived")}',
             f'  Excluded        : {sum(v for (s, st), v in cnt.items() if st == "excluded")}  (generated RTL — reported, not signed off)',
             f'  Policy          : 0 open errors{" + 0 open warnings" if fail_w else ""}',
             f'  Tools           : {", ".join(tools) or "-"}',
             f'  Status          : {"PASS" if ok else "FAIL"}', '']
    by_rule = {}
    for r in rows:
        if r['status'] == 'open' and r['severity'] in ('error', 'warning'):
            by_rule.setdefault((r['severity'], r['tool'], r['rule']), []).append(r)
    if by_rule:
        lines.append('  Open findings by rule:')
        for (sev, tool, rule), rs in sorted(by_rule.items()):
            lines.append(f'    {sev:<7} {tool:<9} {rule:<28} {len(rs):>4}   e.g. {os.path.basename(rs[0]["file"])}:{rs[0]["line"]} {rs[0]["message"][:90]}')
    open(a.output, 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines[:10]), file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('lint-collect'); p.add_argument('--verilator-sarif', required=True)
    p.add_argument('--slang-log'); p.add_argument('--verible-log'); p.add_argument('--verible-severity', default='warning')
    p.add_argument('--exclude', nargs='*'); p.add_argument('--generated', nargs='*'); p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('cdc-collect'); p.add_argument('--json', required=True); p.add_argument('--log')
    p.add_argument('-o', '--output', required=True)
    p = sp.add_parser('upf-check'); p.add_argument('--upf', required=True); p.add_argument('--design', required=True)
    p.add_argument('--top', required=True); p.add_argument('--spec'); p.add_argument('-o', '--output', required=True)
    p.add_argument('--report', required=True)
    p = sp.add_parser('waive'); p.add_argument('--violations', required=True); p.add_argument('--waivers')
    p.add_argument('--today'); p.add_argument('-o', '--output', required=True); p.add_argument('--report', required=True)
    p = sp.add_parser('summary'); p.add_argument('--violations', required=True); p.add_argument('--check', required=True)
    p.add_argument('--design', required=True); p.add_argument('--fail-on-warning', default='true')
    p.add_argument('-o', '--output', required=True)
    a = ap.parse_args()
    {'lint-collect': cmd_lint_collect, 'cdc-collect': cmd_cdc_collect, 'upf-check': cmd_upf_check,
     'waive': cmd_waive, 'summary': cmd_summary}[a.cmd](a)


if __name__ == '__main__':
    main()
