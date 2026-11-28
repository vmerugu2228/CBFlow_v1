#!/usr/bin/env python3
"""QoR across MMMC scenarios of STA / PNR runs and releases, for the mmmc-manager skill.

    mmmc_qor.py <target> [<target> ...] [--stage <pnr stage>] [--inventory inv.json]
                [--tol 0.005] [-o qor.json]

A target is any of
  STA run      work/STA/<timing node>/<scenario>/reports/qor.tcl  (one table per timing node)
  STA release  metrics.rpt '# scenario:' sections (+ reports/sta/sta_power.rpt)
  PNR run      work/PNR/<node>/reports/checklist_metrics.rpt '# scenario:' sections
               (--stage, default: the last of signoff pro route cts_opt cts place present)
  PNR release  metrics.rpt '# stage: <stage>' blocks (same --stage default)
PNR per-scenario data is path-group timing + power (no per-scenario DRV).

Per scenario: setup / hold WNS · TNS · NVP, per-path-group WNS (R2R I2R R2O I2O),
DRV counts + worst tran slack (STA), leakage / total power. Analysis per table:
  dominant   the worst scenario per metric (setup / hold WNS and TNS, each path
             group, tran slack, leakage, total power); ties within --tol (ns)
  limiting   the metrics each scenario is (co-)worst for
  redundant  scenarios worst for nothing, with their margin to the worst setup /
             hold WNS (a met path group > --margin above the check's worst
             limits nothing)
  rc_sensitivity  per PVT, the WNS spread across RC corners (ns)
  temp_inversion  per process/voltage, whether the cold view is worse for setup
  gaps       (with --inventory from mmmc_inventory.py) signoff views not timed,
             timed views outside the signoff set, process corners / power view
             never timed, modes without a timed hold view
Prints the tables; -o writes the JSON mmmc_recommend.py reads. Read-only.
"""
import argparse
import glob
import json
import os
import re
import sys

# Shared report readers of the timing-eco skill (same STA run layout).
sys.dont_write_bytecode = True   # read-only: no __pycache__ in the timing-eco skill
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'timing-eco', 'scripts'))
from timing_summary import QOR_RE, drv_counts, read_tcl_sets  # noqa: E402

PNR_STAGES = ['signoff', 'pro', 'route', 'cts_opt', 'cts', 'place']
VIEW_RE = re.compile(r'^(?P<mode>[a-z0-9]+)_(?P<corner>[a-z]+)_(?P<voltage>\d+p\d+v)_(?P<rc>rc_[a-z0-9]+)_(?P<temp>m?\d+c)$')
GROUPS = ('R2R', 'I2R', 'R2O', 'I2O')
METRIC_KEYS = {
    'Setup WNS': 'setup_wns', 'Setup TNS': 'setup_tns', 'Setup NVP': 'setup_nvp',
    'Hold WNS': 'hold_wns', 'Hold TNS': 'hold_tns', 'Hold NVP': 'hold_nvp',
    'Tran violations': 'tran_viol', 'Cap violations': 'cap_viol', 'Fanout violations': 'fanout_viol',
    'Tran slack ns': 'tran_slack', 'Cap slack pF': 'cap_slack', 'Unannotated nets': 'unannotated',
    'Lkg power mW': 'leakage_mw', 'Total power mW': 'total_mw',
    'Internal power mW': 'internal_mw', 'Switching power mW': 'switching_mw',
}
QOR_KEYS = {'wns_setup': 'setup_wns', 'tns_setup': 'setup_tns', 'nvp_setup': 'setup_nvp',
            'wns_hold': 'hold_wns', 'tns_hold': 'hold_tns', 'nvp_hold': 'hold_nvp',
            'max_tran_violations': 'tran_viol', 'max_cap_violations': 'cap_viol',
            'max_fanout_violations': 'fanout_viol', 'tran_slack': 'tran_slack', 'cap_slack': 'cap_slack',
            'parasitic_unannotated': 'unannotated'}
# metric -> (direction, unit scale): 'min' = smaller is worse, 'max' = larger is worse
DOMINANCE = {'setup_wns': 'min', 'setup_tns': 'min', 'hold_wns': 'min', 'hold_tns': 'min',
             'tran_slack': 'min', 'leakage_mw': 'max', 'total_mw': 'max'}
for _g in GROUPS:
    DOMINANCE[f'setup_{_g}_wns'] = 'min'
    DOMINANCE[f'hold_{_g}_wns'] = 'min'


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def parse_metrics(path):
    """{stage: {'design': {key: val}, 'scenarios': {scen: {key: val}}}} of a metrics.rpt /
    checklist_metrics.rpt. Lines before any '# stage:' go to stage ''."""
    out = {}
    stage, cat, scen = '', '', None
    cur = out.setdefault(stage, {'design': {}, 'scenarios': {}})
    with open(path, errors='replace') as f:
        for ln in f:
            ln = ln.rstrip('\n')
            m = re.match(r'^#\s*stage:\s*(\S+)', ln)
            if m:
                stage, cat, scen = m.group(1), '', None
                cur = out.setdefault(stage, {'design': {}, 'scenarios': {}})
                continue
            m = re.match(r'^#\s*category:\s*(\S+)', ln)
            if m:
                cat, scen = m.group(1), None
                continue
            m = re.match(r'^#\s*scenario:\s*(\S+)', ln)
            if m:
                scen = m.group(1)
                continue
            if ':' not in ln or ln.startswith('#'):
                continue
            k, _, v = ln.partition(':')
            k, v = k.strip(), v.strip()
            if cat == 'scenario' and scen:
                cur['scenarios'].setdefault(scen, {})[k] = v
            else:
                cur['design'][f'{cat}/{k}'] = v
    return out


def norm_metrics(raw):
    """metrics.rpt per-scenario key/values -> normalized row."""
    row = {}
    for k, v in raw.items():
        if k in METRIC_KEYS and num(v) is not None:
            row[METRIC_KEYS[k]] = num(v)
        m = re.match(r'^(Setup|Hold) (R2R|I2R|R2O|I2O) (WNS|TNS|NVP)$', k)
        if m and num(v) is not None:
            row[f'{m.group(1).lower()}_{m.group(2)}_{m.group(3).lower()}'] = num(v)
    for chk in ('setup', 'hold'):   # PNR sections: path groups only
        ws = [row[f'{chk}_{g}_wns'] for g in GROUPS if f'{chk}_{g}_wns' in row]
        if f'{chk}_wns' not in row and ws:
            row[f'{chk}_wns'] = min(ws)
            row[f'{chk}_tns'] = sum(row.get(f'{chk}_{g}_tns', 0.0) for g in GROUPS)
            row[f'{chk}_nvp'] = sum(row.get(f'{chk}_{g}_nvp', 0.0) for g in GROUPS)
    return row


def read_qor_tcl(path):
    q = {}
    with open(path, errors='replace') as f:
        for ln in f:
            m = QOR_RE.match(ln)
            if m:
                q[m.group(1)] = m.group(2)
    row = {QOR_KEYS[k]: num(v) for k, v in q.items() if k in QOR_KEYS and num(v) is not None}
    for k, scale in (('power_leakage', 1e3), ('power_total', 1e3)):   # W -> mW
        if num(q.get(k)) is not None:
            row['leakage_mw' if 'leak' in k else 'total_mw'] = num(q[k]) * scale
    for m in re.finditer(r'\{(Setup|Hold) (R2R|I2R|R2O|I2O) (WNS|TNS|NVP) : ([^}]*)\}', q.get('path_groups', '')):
        if num(m.group(4)) is not None:
            row[f'{m.group(1).lower()}_{m.group(2)}_{m.group(3).lower()}'] = num(m.group(4))
    return row


def pick_stage(available, wanted):
    if wanted:
        if wanted not in available:
            sys.exit(f'mmmc_qor: stage {wanted} not found (have: {" ".join(available)})')
        return wanted
    for s in PNR_STAGES:
        if s in available:
            return s
    sys.exit(f'mmmc_qor: no PNR stage with scenario data (have: {" ".join(available)})')


def load_target(target, stage):
    """[table] — one per timing node (STA run) or one (release / PNR)."""
    t = os.path.abspath(target)
    uc = read_tcl_sets(os.path.join(t, 'setup', 'user_config.tcl'))
    meta = {'dir': t, 'design': uc.get('flow(design_name)', ''), 'phase': uc.get('project(phase)', ''),
            'lib_tag': uc.get('project(lib_config_tag)', '')}
    tables = []
    sta_q = sorted(glob.glob(os.path.join(t, 'work', 'STA', '*', '*', 'reports', 'qor.tcl')))
    pnr_m = sorted(glob.glob(os.path.join(t, 'work', 'PNR', '*', 'reports', 'checklist_metrics.rpt')))
    rel_m = os.path.join(t, 'metrics.rpt')
    if sta_q:
        by_node = {}
        for q in sta_q:
            scen_dir = os.path.dirname(os.path.dirname(q))
            node = os.path.basename(os.path.dirname(scen_dir))
            row = read_qor_tcl(q)
            drv = drv_counts(os.path.join(os.path.dirname(q), 'drv.rpt'))
            for k, key in (('max_tran', 'tran_viol'), ('max_cap', 'cap_viol'), ('max_fanout', 'fanout_viol')):
                row.setdefault(key, drv.get(k, 0))
            by_node.setdefault(node, {})[os.path.basename(scen_dir)] = row
        for node, rows in sorted(by_node.items()):
            tables.append(dict(meta, kind='sta_run', flow='STA', stage=node,
                               release_tag=uc.get('sta(input,release_tag)', ''), rows=rows))
    elif pnr_m:
        nodes = {os.path.basename(os.path.dirname(os.path.dirname(p))): p for p in pnr_m}
        by_stage = {}
        for n, p in nodes.items():
            st = re.sub(r'\d+$', '', n)
            if parse_metrics(p).get('', {}).get('scenarios'):
                by_stage.setdefault(st, []).append(n)
        st = pick_stage(list(by_stage), stage)
        node = sorted(by_stage[st])[-1]
        raw = parse_metrics(nodes[node])['']['scenarios']
        tables.append(dict(meta, kind='pnr_run', flow='PNR', stage=node,
                           rows={s: norm_metrics(r) for s, r in raw.items()}))
    elif os.path.isfile(rel_m):
        parts = t.rstrip('/').split(os.sep)
        meta.update({'design': parts[-3], 'phase': parts[-4], 'release_tag': parts[-1]})
        flow = parts[-2]
        mt = parse_metrics(rel_m)
        if '' in mt and mt['']['scenarios'] and flow != 'PNR':
            tables.append(dict(meta, kind='release', flow=flow, stage='', rows={s: norm_metrics(r) for s, r in mt['']['scenarios'].items()}))
        else:
            avail = [s for s in mt if s and s != '-' and mt[s]['scenarios']]
            st = pick_stage(avail, stage)
            tables.append(dict(meta, kind='release', flow=flow, stage=st,
                               rows={s: norm_metrics(r) for s, r in mt[st]['scenarios'].items()}))
    else:
        sys.exit(f'mmmc_qor: {target}: no work/STA/*/<scenario>/reports/qor.tcl, '
                 'work/PNR/*/reports/checklist_metrics.rpt or metrics.rpt')
    return tables


def analyze(tab, tol, inv, margin_ns=0.2):
    rows = tab['rows']
    dom, limiting = {}, {s: [] for s in rows}
    for m, d in DOMINANCE.items():
        vals = {s: r[m] for s, r in rows.items() if r.get(m) is not None}
        if len(vals) < 1:
            continue
        w = min(vals.values()) if d == 'min' else max(vals.values())
        if m.endswith('_tns') and w == 0:
            continue                    # nothing violates: TNS limits nobody
        chk = m.split('_')[0]
        allw = [r.get(f'{chk}_wns') for r in rows.values() if r.get(f'{chk}_wns') is not None]
        if m.count('_') == 2 and allw and w > 0 and w > min(allw) + margin_ns:
            continue                    # a path group met far above the check's worst limits nothing
        t = tol if m not in ('leakage_mw', 'total_mw') else abs(w) * 0.01
        ties = sorted(s for s, v in vals.items() if abs(v - w) <= t)
        dom[m] = {'value': w, 'scenarios': ties}
        for s in ties:
            limiting[s].append(m)
    # margin of each scenario to the worst setup / hold WNS; redundant = limits nothing
    margin = {}
    for s in rows:
        margin[s] = {c: round(rows[s][f'{c}_wns'] - dom[f'{c}_wns']['value'], 4)
                     for c in ('setup', 'hold') if rows[s].get(f'{c}_wns') is not None and f'{c}_wns' in dom}
    redundant = {s: margin[s] for s, lim in limiting.items() if not lim}
    # RC sensitivity / temperature inversion from the view names
    parsed = {s: VIEW_RE.match(s) for s in rows}
    pvt = {}
    for s, m in parsed.items():
        if m:
            pvt.setdefault((m['mode'], m['corner'], m['voltage'], m['temp']), []).append(s)
    rc_sens = {}
    for k, ss in pvt.items():
        if len(ss) > 1:
            for chk in ('setup_wns', 'hold_wns'):
                v = [rows[s][chk] for s in ss if rows[s].get(chk) is not None]
                if len(v) > 1:
                    rc_sens.setdefault('_'.join(k), {})[chk] = round(max(v) - min(v), 4)
    inversion = []
    pv = {}
    for s, m in parsed.items():
        if m and rows[s].get('setup_wns') is not None:
            pv.setdefault((m['mode'], m['corner'], m['voltage'], m['rc']), []).append((m['temp'], rows[s]['setup_wns'], s))
    for k, lst in pv.items():
        if len(lst) > 1:
            tval = lambda x: -int(x[0][1:-1]) if x[0].startswith('m') else int(x[0][:-1])   # noqa: E731
            lst.sort(key=tval)
            cold, hot = lst[0], lst[-1]
            inversion.append({'pvt': '_'.join(k), 'cold': cold[2], 'hot': hot[2],
                              'cold_wns': cold[1], 'hot_wns': hot[1], 'cold_worse': cold[1] < hot[1]})
    gaps = []
    if inv:
        views, sets = inv.get('views', {}), inv.get('sets', {})
        so = sets.get('signoff') or sets.get('sta_signoff') or []
        timed = set(rows)
        for v in so:
            if v not in timed:
                gaps.append(f'signoff view {v} not timed in this table')
        extra = sorted(timed - set(so))
        if extra:
            gaps.append(f'{len(extra)} timed view(s) not in mmmc_scenario_sets(signoff): {" ".join(extra)}')
        tcorners = {views[v]['corner'] for v in timed if v in views}
        for c in sorted({p['corner'] for p in inv.get('pvt', [])} - tcorners):
            gaps.append(f'process corner {c} never timed')
        for v in sets.get('power', []):
            if v not in timed:
                gaps.append(f'power view {v} not timed (power numbers here are at non-typical corners)')
        for mode in inv.get('modes', {}):
            if not [v for v in timed if views.get(v, {}).get('mode') == mode]:
                gaps.append(f'mode {mode} not timed')
        tlib = set(inv.get('tag', {}).get('stdcell_lib_sets', []))
        for v in timed:
            if v in views and tlib and views[v]['lib_set'] not in tlib:
                gaps.append(f'{v}: lib set {views[v]["lib_set"]} not in tag {inv.get("lib_tag")}')
    tab['analysis'] = {'dominant': dom, 'limiting': limiting, 'redundant': redundant, 'margin': margin,
                       'rc_sensitivity': rc_sens, 'temp_inversion': inversion, 'gaps': gaps, 'tol': tol}
    return tab


def fmt(v, w=8, p=3):
    if v is None:
        return '-'.rjust(w)
    if isinstance(v, float) and v.is_integer() and abs(v) >= 1 and p == 0:
        return str(int(v)).rjust(w)
    return f'{v:{w}.{p}f}'


def print_table(tab):
    a = tab['analysis']
    print(f"\n== {tab['flow']} {tab['kind']} {tab['design']} {tab.get('phase', '')} "
          f"{tab.get('release_tag', '')} stage={tab['stage'] or '-'}\n   {tab['dir']}")
    hdr = (f"{'scenario':32} {'sWNS':>8} {'sTNS':>8} {'sNVP':>5} {'hWNS':>8} {'hTNS':>8} {'hNVP':>5} "
           f"{'tran':>5} {'cap':>5} {'fan':>5} {'tranSlk':>8} {'lkg_mW':>8} {'tot_mW':>7}  limits")
    print(hdr)
    print('-' * len(hdr))
    for s in sorted(tab['rows'], key=lambda x: (tab['rows'][x].get('setup_wns') or 1e9)):
        r = tab['rows'][s]
        lim = ','.join(m.replace('_wns', '').replace('setup_', 's:').replace('hold_', 'h:') for m in a['limiting'][s]) or \
            ('REDUNDANT (' + ' '.join(f'd{c[0]}=+{v:.3f}' for c, v in a['margin'][s].items()) + ')')
        print(f"{s:32} {fmt(r.get('setup_wns'))} {fmt(r.get('setup_tns'))} {fmt(r.get('setup_nvp'), 5, 0)} "
              f"{fmt(r.get('hold_wns'))} {fmt(r.get('hold_tns'))} {fmt(r.get('hold_nvp'), 5, 0)} "
              f"{fmt(r.get('tran_viol'), 5, 0)} {fmt(r.get('cap_viol'), 5, 0)} {fmt(r.get('fanout_viol'), 5, 0)} "
              f"{fmt(r.get('tran_slack'))} {fmt(r.get('leakage_mw'), 8, 4)} {fmt(r.get('total_mw'), 7, 3)}  {lim}")
    d = a['dominant']
    for m in ('setup_wns', 'hold_wns', 'setup_tns', 'hold_tns', 'tran_slack', 'leakage_mw', 'total_mw'):
        if m in d:
            print(f"  worst {m:11}: {d[m]['value']:.4g}  {' '.join(d[m]['scenarios'])}")
    if a['rc_sensitivity']:
        mx = max((v for x in a['rc_sensitivity'].values() for v in x.values()), default=0)
        print(f"  RC-corner spread (max over PVTs): {mx:.4f} ns" +
              ('  -> RC corner barely matters for this design' if mx <= a['tol'] * 2 else ''))
    ws = set(a['dominant'].get('setup_wns', {}).get('scenarios', []))
    for i in a['temp_inversion']:
        if i['cold_worse'] and i['cold'] in ws:
            print(f"  temperature inversion: {i['cold']} setup {i['cold_wns']:.3f} < {i['hot']} {i['hot_wns']:.3f} "
                  "(the cold view is the setup corner — keep it)")
    for g in a['gaps']:
        print(f'  GAP: {g}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('targets', nargs='+', help='STA / PNR run dirs or release dirs')
    ap.add_argument('--stage', help='PNR stage for PNR runs / releases (default: latest of signoff pro route …)')
    ap.add_argument('--inventory', help='mmmc_inventory.py JSON — enables the coverage-gap checks')
    ap.add_argument('--tol', type=float, default=0.005, help='slack tie tolerance in ns (default 0.005)')
    ap.add_argument('--margin', type=float, default=0.2,
                    help='a met path group further than this (ns) above the check\'s worst WNS limits nothing (default 0.2)')
    ap.add_argument('-o', '--output', help='write the JSON here')
    ap.add_argument('-q', '--quiet', action='store_true', help='no tables (JSON only)')
    a = ap.parse_intermixed_args()
    inv = json.load(open(a.inventory)) if a.inventory else None
    tables = []
    for t in a.targets:
        for tab in load_target(t, a.stage):
            tables.append(analyze(tab, a.tol, inv, a.margin))
    if not a.quiet:
        for tab in tables:
            print_table(tab)
    if a.output:
        with open(a.output, 'w') as f:
            json.dump({'tables': tables, 'inventory': a.inventory}, f, indent=1)
            f.write('\n')


if __name__ == '__main__':
    main()
