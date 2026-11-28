#!/usr/bin/env python3
"""Recommended MMMC scenario sets from QoR + inventory, for the mmmc-manager skill.

    mmmc_recommend.py --qor qor.json [--qor more.json ...] --inventory inv.json
                      [--near 0.10] [--max-candidates 6] [-o rec.json]

Inputs: mmmc_qor.py -o JSON(s) and mmmc_inventory.py -o JSON. The first --qor
is the design under analysis (its STA tables, else its PNR tables); later
--qor files (older runs / phases of the block) only add RC-sensitivity evidence
and a consistency line.

Recommends, with the reason for each view:
  pnr.setup / pnr.hold  the views PNR optimizes: every view that is (co-)worst for
        a setup (hold) metric in any table, plus views within --near ns of the
        worst WNS; RC-corner ties collapse to rc_max (setup) / rc_min (hold)
  sta.signoff           the declared signoff set + every limiting view (+ the
        validated candidates once timed); redundant views are listed — they may
        leave the PNR sets, not the signoff set
  power                 the typical view (mmmc_scenario_sets(power)); the worst
        leakage / total-power view for EMIR and leakage signoff
  library models        a block with a parent: its PNR `signoff` node must time
        every lib set the parent's signoff + power sets use (the release's
        timing models are generated per signoff-node view)
  validate              untimed views worth one STA run (power view, process
        corners never timed, hold in a slow corner, RC alternates of the
        dominant PVTs unless RC sensitivity is already known), each marked
        runnable or blocked (lib set missing from the tag, child models missing)
Prints the reasoning and PROPOSAL snippets (override_config.timing1.tcl for a
validation STA run, mmmc_node_scenarios.tcl, mmmc_scenario_sets, a per-run PNR
override) — text only; nothing is written but the optional -o JSON.
"""
import argparse
import json
import re
import sys

VIEW_RE = re.compile(r'^(?P<mode>[a-z0-9]+)_(?P<corner>[a-z]+)_(?P<voltage>\d+p\d+v)_(?P<rc>rc_[a-z0-9]+)_(?P<temp>m?\d+c)$')
PNR_NODES = ['init_design', 'place', 'cts', 'cts_opt', 'route', 'pro', 'extraction', 'signoff', 'timing', 'eco']


def pvt_key(v):
    m = VIEW_RE.match(v)
    return (m['mode'], m['corner'], m['voltage'], m['temp']) if m else (v,)


def collapse_rc(views, prefer):
    """Keep one view per PVT among RC-corner ties, preferring rc <prefer>."""
    by = {}
    for v in views:
        by.setdefault(pvt_key(v), []).append(v)
    out = []
    for k, vs in by.items():
        pick = next((v for v in vs if VIEW_RE.match(v) and VIEW_RE.match(v)['rc'] == prefer), sorted(vs)[0])
        out.append(pick)
    return sorted(out)


def view_ok(v, inv):
    """(runnable, blocker) of a view for the inventory's design."""
    views = inv.get('views', {})
    if v not in views:
        return False, 'not an analysis view (add it with mmmc-manager add-pvt / add-rc first)'
    ls, rc = views[v]['lib_set'], views[v]['rc_corner']
    tag_ls = set(inv.get('tag', {}).get('stdcell_lib_sets', []))
    if tag_ls and ls not in tag_ls:
        return False, f'lib set {ls} missing from tag {inv.get("lib_tag")}'
    if inv.get('tag', {}).get('has_memory') and ls not in inv.get('tech_cfg', {}).get('memory_lib_set_map', {}):
        return False, f'tech(memory,lib_set_map) has no {ls}'
    for ch in (inv.get('hierarchy') or {}).get('children', []):
        b = inv.get('tag', {}).get('blocks', {}).get(ch)
        if not b or ls not in b.get('lib_sets', []):
            return False, f'child {ch} has no timing model at {ls} in tag {inv.get("lib_tag")}'
        if rc not in b.get('spef_corners', []):
            return False, f'child {ch} has no SPEF at {rc}'
    return True, ''


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--qor', action='append', required=True,
                    help='mmmc_qor.py JSON; the first is the design under analysis, later ones (older runs) '
                         'only add RC-sensitivity evidence and a consistency line')
    ap.add_argument('--inventory', required=True, help='mmmc_inventory.py JSON')
    ap.add_argument('--near', type=float, default=0.10, help='also optimize views within this many ns of the worst WNS')
    ap.add_argument('--max-candidates', type=int, default=6)
    ap.add_argument('-o', '--output')
    a = ap.parse_args()
    inv = json.load(open(a.inventory))
    design = inv.get('design')
    def load(paths):
        out = []
        for q in paths:
            out += [t for t in json.load(open(q))['tables'] if not design or t.get('design') in (design, '')]
        sta_t = [t for t in out if t['flow'] == 'STA']
        return sta_t or out
    use = load(a.qor[:1])            # the design under analysis
    history = load(a.qor[1:])        # older runs / phases: RC sensitivity + consistency only
    if not use:
        sys.exit(f'mmmc_recommend: no QoR table for design {design} in {a.qor[0]}')
    sta = [t for t in use if t['flow'] == 'STA']
    views, sets = inv['views'], inv['sets']
    signoff = sets.get('signoff') or sets.get('sta_signoff') or []
    reasons = {}

    def why(v, r, src):
        lst = reasons.setdefault(v, {}).setdefault(src, [])
        if r not in lst:
            lst.append(r)

    setup, hold, limiting_any, timed = set(), set(), set(), set()
    worst_power, worst_leak = set(), set()
    slow_hold = []
    rc_known = False
    for t in use:
        an, rows = t['analysis'], t['rows']
        src = t['dir'].rstrip('/').split('/')[-1]
        timed |= set(rows)
        for m, d in an['dominant'].items():
            for v in d['scenarios']:
                limiting_any.add(v)
                if m.startswith('setup') or m == 'tran_slack':
                    setup.add(v)
                    why(v, f'worst {m} {d["value"]:.3f}', src)
                elif m.startswith('hold'):
                    hold.add(v)
                    why(v, f'worst {m} {d["value"]:.3f}', src)
                    if VIEW_RE.match(v) and VIEW_RE.match(v)['corner'] == 'ss':
                        slow_hold.append(v)
                elif m == 'total_mw':
                    worst_power.add(v)
                elif m == 'leakage_mw':
                    worst_leak.add(v)
        for c, tgt in (('setup', setup), ('hold', hold)):
            w = an['dominant'].get(f'{c}_wns', {}).get('value')
            if w is None:
                continue
            for v, r in rows.items():
                if r.get(f'{c}_wns') is not None and r[f'{c}_wns'] - w <= a.near and v not in tgt:
                    tgt.add(v)
                    why(v, f'{c} WNS {r[f"{c}_wns"]:.3f} within {a.near} ns of the worst', src)
        if an.get('rc_sensitivity'):
            rc_known = True
    for t in history:
        if t['analysis'].get('rc_sensitivity'):
            rc_known = True
    rc_spread = max((x for t in use + history for d in t['analysis'].get('rc_sensitivity', {}).values()
                     for x in d.values()), default=None)
    pnr_setup = collapse_rc(setup, 'rc_max') if rc_known else sorted(setup)
    pnr_hold = collapse_rc(hold, 'rc_min') if rc_known else sorted(hold)
    redundant = sorted(v for t in use for v in t['analysis']['redundant'] if v not in limiting_any)
    sta_signoff = sorted(set(signoff) | set(pnr_setup) | set(pnr_hold))

    # ── validation candidates ──
    cands = []

    def cand(v, reason):
        if v in timed or any(c['view'] == v for c in cands):
            return
        ok, block = view_ok(v, inv)
        cands.append({'view': v, 'reason': reason, 'runnable': ok, 'blocker': block,
                      'role': 'hold' if 'hold' in reason else 'setup'})

    for v in sets.get('power', []):
        cand(v, 'typical power view (mmmc_scenario_sets(power)) never timed')
    tc = {views[v]['corner'] for v in timed | {c['view'] for c in cands} if v in views}
    for p in inv.get('pvt', []):
        if p['corner'] not in tc:
            tc.add(p['corner'])
            for rc in ('rc_typ',):
                for m in inv.get('modes', {}):
                    cand(f"{m}_{p['corner']}_{p['voltage']}_{rc}_{p['temperature']}",
                         f"process corner {p['corner']} never timed")
    for v in slow_hold:
        mm = VIEW_RE.match(v)
        cand(f"{mm['mode']}_{mm['corner']}_{mm['voltage']}_rc_min_{mm['temp']}",
             f'hold is limited in a slow corner ({v}) — the rc_min variant may be worse for hold')
    if not rc_known:
        for v in pnr_setup:
            mm = VIEW_RE.match(v)
            if mm:
                for rc in sorted(inv.get('rc_corners', {})):
                    if rc != mm['rc']:
                        cand(f"{mm['mode']}_{mm['corner']}_{mm['voltage']}_{rc}_{mm['temp']}",
                             f'RC alternate of the setup-dominant {v} (RC sensitivity unknown)')
        for v in pnr_hold:
            mm = VIEW_RE.match(v)
            if mm:
                for rc in sorted(inv.get('rc_corners', {})):
                    if rc != mm['rc']:
                        cand(f"{mm['mode']}_{mm['corner']}_{mm['voltage']}_{rc}_{mm['temp']}",
                             f'RC alternate of the hold-dominant {v} (RC sensitivity unknown)')
    cands = cands[:a.max_candidates]

    # ── library models a parent needs ──
    hier = inv.get('hierarchy') or {}
    lib_note = None
    if hier.get('parent'):
        need = sorted({views[v]['lib_set'] for v in set(signoff) | set(sets.get('power', [])) if v in views})
        have = sorted({views[v]['lib_set'] for v in (inv.get('nodes', {}).get('signoff', {}).get('setup', []) +
                                                    inv.get('nodes', {}).get('signoff', {}).get('hold', [])) if v in views})
        lib_note = {'parent': hier['parent'], 'needed_lib_sets': need, 'signoff_node_lib_sets': have,
                    'missing': [x for x in need if x not in have]}

    rec = {'design': design, 'lib_tag': inv.get('lib_tag'), 'sources': [t['dir'] for t in use],
           'pnr': {'setup': pnr_setup, 'hold': pnr_hold}, 'sta_signoff': sta_signoff,
           'power': {'typical': sets.get('power', []), 'worst_total': sorted(worst_power), 'worst_leakage': sorted(worst_leak)},
           'redundant_for_pnr': redundant, 'rc_spread_ns': rc_spread, 'validate': cands,
           'library_models': lib_note, 'reasons': reasons}

    # ── report ──
    P = print
    P(f"MMMC recommendation — {design}  (tag {inv.get('lib_tag')}, from {len(use)} {'STA' if sta else 'PNR'} table(s))")
    for s in rec['sources']:
        P(f'  source: {s}')
    for t in history:
        d = t['analysis']['dominant']
        P(f"  history: {t['dir'].rstrip('/').split('/')[-1]}: worst setup "
          f"{' '.join(d.get('setup_wns', {}).get('scenarios', []))} / hold {' '.join(d.get('hold_wns', {}).get('scenarios', []))}")
    P('\nPNR optimization (mmmc_node_scenarios: place … eco)')
    for role, vs in (('setup', pnr_setup), ('hold', pnr_hold)):
        for v in vs:
            keep = (lambda r: 'hold' in r) if role == 'hold' else (lambda r: 'hold' not in r)
            P(f'  {role:5} {v:30} ' + ' | '.join(f'{", ".join(x for x in r if keep(x))} [{src}]'
                                                for src, r in reasons.get(v, {}).items() if any(keep(x) for x in r)))
    if rc_spread is not None:
        P(f'  RC-corner spread measured: {rc_spread:.4f} ns' +
          (' — RC ties collapsed (rc_max setup / rc_min hold)' if rc_known else ''))
    if slow_hold:
        P(f'  NOTE hold is limited in a slow corner ({" ".join(sorted(set(slow_hold)))}): keep it in the hold set '
          '(usually clock skew or interface / child-model paths, not cell speed — read its hold paths)')
    if redundant:
        P('\nLimit nothing (candidates to drop from the PNR sets; keep them in signoff):')
        for t in use:
            for v, mg in t['analysis']['redundant'].items():
                if v in redundant:
                    P(f'  {v:30} margin ' + ' '.join(f'{c} +{x:.3f} ns' for c, x in mg.items()) +
                      f'  [{t["dir"].split("/")[-1]}]')
    P('\nSignoff STA (mmmc_scenario_sets(signoff))')
    P('  ' + ' '.join(sta_signoff))
    extra = [v for v in sta_signoff if v not in signoff]
    if extra:
        P(f'  add to the declared signoff set: {" ".join(extra)}')
    P('\nPower')
    P(f"  typical (power analysis): {' '.join(sets.get('power', [])) or '-- none declared --'}"
      f"{'  [NOT timed yet]' if any(v not in timed for v in sets.get('power', [])) else ''}")
    P(f"  worst total power (EMIR / IR): {' '.join(sorted(worst_power))}")
    P(f"  worst leakage: {' '.join(sorted(worst_leak))}")
    if lib_note:
        P(f"\nTiming models for the parent {lib_note['parent']}: signoff node times lib sets "
          f"{' '.join(lib_note['signoff_node_lib_sets'])}; parent signoff+power need {' '.join(lib_note['needed_lib_sets'])}")
        if lib_note['missing']:
            P(f"  MISSING: {' '.join(lib_note['missing'])} — add a view with that lib set to the signoff node, "
              'or the parent cannot time it (dropping a view from signoff removes its .lib from the release)')
    if cands:
        P('\nValidate with an STA run (ask the user first):')
        for c in cands:
            P(f"  {c['view']:30} {c['reason']}" + ('' if c['runnable'] else f"   BLOCKED: {c['blocker']}"))
    run = [c['view'] for c in cands if c['runnable']]

    # declared role (never inferred from the corner name) + what the QoR says limits
    decl_setup = set(sets.get('setup', [])) | set(pnr_setup)
    decl_hold = set(sets.get('hold', [])) | set(pnr_hold)
    P('\n# ---- PROPOSAL (text only — do not write without the user\'s approval) ----')
    if run:
        s_list = sorted(decl_setup | {c['view'] for c in cands if c['runnable'] and c['role'] == 'setup'})
        h_list = sorted(decl_hold | {c['view'] for c in cands if c['runnable'] and c['role'] == 'hold'})
        P('# 1) validation STA run: <new run>/setup/override_config.timing1.tcl')
        P('#    (every listed view is timed for setup AND hold; the lists only select the scenarios)')
        P(f'set sta(mmmc,setup_scenarios) "{" ".join(s_list)}"')
        P(f'set sta(mmmc,hold_scenarios)  "{" ".join(h_list)}"')
    P('# 2) mmmc_node_scenarios.tcl — PNR nodes (edit with: cbflow flow mmmc-manager set-node --node <n> --setup "…" --hold "…")')
    so_node_setup, so_node_hold = sorted(decl_setup), sorted(decl_hold)
    if lib_note and lib_note['missing']:   # one view per missing lib set (the power view first)
        for ls in lib_note['missing']:
            v = next((x for x in sets.get('power', []) + sorted(views) if views.get(x, {}).get('lib_set') == ls), None)
            if v:
                so_node_setup.append(v)
    for n in ('place', 'cts', 'cts_opt', 'route', 'pro', 'eco'):
        P(f'#   {n:8} setup {{{" ".join(pnr_setup)}}}  hold {{{" ".join(pnr_hold)}}}')
    P(f'#   signoff / extraction / timing  setup {{{" ".join(so_node_setup)}}}  hold {{{" ".join(so_node_hold)}}}'
      '   (keeps every lib set the parent and the release need)')
    P('# 3) one PNR run only: <run>/setup/override_config.<node>1.tcl  (the key get_node_scenarios reads)')
    P(f'set mmmc(cts_opt1) {{setup {{{" ".join(pnr_setup)}}} hold {{{" ".join(pnr_hold)}}}}}')
    P('# 4) mmmc_config.tcl scenario sets')
    P(f'#   setup   {{{" ".join(sorted(decl_setup))}}}')
    P(f'#   hold    {{{" ".join(sorted(decl_hold))}}}')
    P(f'#   power   {{{" ".join(sets.get("power", []))}}}')
    P('#   signoff [concat setup hold]  — add the validated candidates that turn out limiting')
    if a.output:
        with open(a.output, 'w') as f:
            json.dump(rec, f, indent=1)
            f.write('\n')


if __name__ == '__main__':
    main()
