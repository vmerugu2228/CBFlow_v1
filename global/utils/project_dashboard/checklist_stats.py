"""Exit-checklist statistics for the SmartGrid project page.

Rolls up the checklist captured with each SmartGrid publish (tracker.db
run_checklist, one published run per (block, phase, exit)) per phase,
against the exits each phase has (project(phase_exits)) and the blocks of
project(design_hierarchy):

  * coverage   — published (block, exit) checklists / blocks x phase exits
  * status mix — PASS / FAIL / WAIVED / NA (no data) / SKIPPED (not active
                 in this phase) over all checks of the phase
  * pass rate  — PASS / (PASS + FAIL + WAIVED), i.e. of the evaluated checks
  * per exit and per (block, exit) — the same counts plus the publish verdict
"""

import os
import sqlite3

STATUSES = ('PASS', 'FAIL', 'WAIVED', 'NA', 'SKIPPED')


def _counts(conn, run_id):
    out = {s: 0 for s in STATUSES}
    mand_fail = []
    for st, ctype, name in conn.execute(
            'SELECT status, check_type, check_name FROM run_checklist '
            'WHERE published_run_id=?', (run_id,)):
        st = (st or 'NA').upper()
        if st == 'CONFIG_ERROR':
            st = 'FAIL'
        elif st == 'PENDING':
            st = 'NA'
        if st in out:
            out[st] += 1
        if ctype == 'mandatory' and st in ('FAIL', 'NA'):
            mand_fail.append((name, st))
    return out, mand_fail


def _rate(c):
    ev = c['PASS'] + c['FAIL'] + c['WAIVED']
    return int(round(100.0 * c['PASS'] / ev)) if ev else None


def _add(a, b):
    for s in STATUSES:
        a[s] += b[s]


def checklist_stats(db_path, published_rows, phases, phase_exits, hier):
    """{phases: [...], other: [...]} — `other` lists publishes whose exit
    the phase does not have (shown separately, not counted)."""
    rows = {}
    for r in published_rows:
        rows[(r.get('block'), r.get('phase'), (r.get('milestone') or '').upper())] = r
    conn = sqlite3.connect(f'file:{db_path}?mode=ro', uri=True) if os.path.exists(db_path) else None
    blocks = list(hier)
    out, other = [], []
    try:
        for ph in phases:
            exits = phase_exits.get(ph, [])
            tot = {s: 0 for s in STATUSES}
            by_exit, cells, mand = [], {}, []
            for ex in exits:
                ex_tot = {s: 0 for s in STATUSES}
                verdicts, n_pub = {}, 0
                for b in blocks:
                    r = rows.get((b, ph, ex))
                    if not r:
                        continue
                    n_pub += 1
                    c, mf = _counts(conn, r['id']) if conn else ({s: 0 for s in STATUSES}, [])
                    _add(ex_tot, c)
                    v = (r.get('verdict') or 'UNKNOWN').upper()
                    verdicts[v] = verdicts.get(v, 0) + 1
                    cells[(b, ex)] = {'id': r['id'], 'verdict': v, 'counts': c,
                                      'rate': _rate(c),
                                      'closability': r.get('closability_pct')}
                    mand += [(b, ex, n, s) for n, s in mf]
                _add(tot, ex_tot)
                by_exit.append({'exit': ex, 'published': n_pub, 'counts': ex_tot,
                                'rate': _rate(ex_tot), 'verdicts': verdicts})
            expected = len(blocks) * len(exits)
            n_pub = len(cells)
            out.append({'phase': ph, 'exits': exits, 'published': n_pub,
                        'expected': expected,
                        'coverage': int(round(100.0 * n_pub / expected)) if expected else 0,
                        'counts': tot, 'rate': _rate(tot), 'by_exit': by_exit,
                        'cells': cells, 'mandatory_open': mand})
        for (b, ph, ex), r in rows.items():
            if ph in phase_exits and ex not in phase_exits[ph]:
                other.append({'block': b, 'phase': ph, 'exit': ex, 'id': r['id'],
                              'verdict': (r.get('verdict') or 'UNKNOWN').upper()})
    finally:
        if conn:
            conn.close()
    return {'phases': out, 'other': other, 'blocks': blocks}
