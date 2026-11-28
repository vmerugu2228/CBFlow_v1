#!/usr/bin/env python3
"""Read / append the checklist skill's learned store (per tech node, per block).

    python3 learn.py context <run_dir>
    python3 learn.py read    (--run-dir <run> | --tech <t> [--block <b>]) [--milestone M] [--check C] [--kind K] [--summary]
    python3 learn.py add     (--run-dir <run> | --tech <t> --block <b> --phase <P> --run <run_name>)
                             [--tech-wide] --milestone M --check C --kind K --text "..." [--date YYYY-MM-DD]

Store: .claude/skills/checklist/learned/<tech>/<block>.md (block facts) and
learned/<tech>/_tech.md (tech-node facts, --tech-wide). One entry per line:

    - <date> | <phase> | <milestone> | <check> | <kind> | <run> | <text>

kinds: failure, cause, fix, fix-failed, waiver, missing-accepted, missing-rejected,
threshold, note. `check` is the check name (or the mandatory-file path, or `-`).
Only facts observed in a run or decided by the user go in; `add` refuses '|'
and newlines in fields and skips exact duplicates. `read --summary` counts
entries per (milestone, check, kind) and marks recurring ones (>= 2 runs).
This script writes only under learned/.
"""
import argparse
import os
import re
import sys
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ckl_common as C  # noqa: E402

KINDS = ('failure', 'cause', 'fix', 'fix-failed', 'waiver', 'missing-accepted', 'missing-rejected',
         'threshold', 'note')


def target(tech, block, tech_wide):
    d = os.path.join(C.LEARNED, tech)
    return os.path.join(d, '_tech.md' if tech_wide else f'{block}.md')


def header(tech, block, tech_wide):
    what = f'tech node {tech}' if tech_wide else f'block {block} ({tech})'
    return (f'# Checklist learnings - {what}\n\n'
            'Appended by `.claude/skills/checklist/scripts/learn.py`; format in ../README.md.\n'
            'Line format: `- date | phase | milestone | check | kind | run | text`\n\n## Entries\n')


def resolve(a):
    if a.run_dir:
        ctx = C.run_context(a.run_dir)
        return ctx['tech'], ctx['block'], ctx['phase'], ctx['run']
    if not a.tech:
        sys.exit('learn: give --run-dir or --tech')
    return a.tech, a.block, getattr(a, 'phase', '') or '-', getattr(a, 'run', '') or '-'


def cmd_context(a):
    ctx = C.run_context(a.run_dir)
    for k in ('run', 'flow', 'phase', 'project', 'block', 'design', 'tech'):
        print(f'{k:<8} {ctx[k]}')
    for f in (target(ctx['tech'], ctx['block'], True), target(ctx['tech'], ctx['block'], False)):
        n = len([1 for ln in open(f) if C.ENTRY_RX.match(ln)]) if os.path.exists(f) else 0
        print(f'store    {os.path.relpath(f, C.ROOT)}  ({n} entries{"" if os.path.exists(f) else ", not yet created"})')


def cmd_read(a):
    tech, block, _, _ = resolve(a)
    es = C.learned_entries(tech, block)
    es = [e for e in es if (not a.milestone or e['milestone'] == a.milestone)
          and (not a.check or e['check'] == a.check) and (not a.kind or e['kind'] == a.kind)]
    if not es:
        print(f'(no learned entries for {tech}' + (f' / {block}' if block else '') + ')')
        return
    if a.summary:
        agg = {}
        for e in es:
            k = (e['milestone'], e['check'], e['kind'])
            agg.setdefault(k, {'n': 0, 'runs': set(), 'last': e})
            agg[k]['n'] += 1
            agg[k]['runs'].add(e['run'])
            agg[k]['last'] = e
        print(f"{'milestone':<18} {'check':<34} {'kind':<17} {'n':>3}  last")
        for (m, c, k), v in sorted(agg.items(), key=lambda x: (-len(x[1]['runs']), x[0])):
            rec = ' RECURRING' if len(v['runs']) > 1 else ''
            print(f"{m:<18} {c[:34]:<34} {k:<17} {v['n']:>3}  {v['last']['date']} {v['last']['text'][:60]}{rec}")
        return
    for e in es:
        print(f"[{e['scope']}] {e['date']} | {e['phase']} | {e['milestone']} | {e['check']} | {e['kind']} | "
              f"{e['run']} | {e['text']}")


def clean(v, name):
    v = (v or '-').strip()
    if '|' in v or '\n' in v:
        sys.exit(f'learn: {name} must not contain "|" or newlines')
    return v


def cmd_add(a):
    tech, block, phase, run = resolve(a)
    if not a.tech_wide and not block:
        sys.exit('learn: block unknown - give --block or --tech-wide')
    if a.kind not in KINDS:
        sys.exit(f'learn: --kind one of {", ".join(KINDS)}')
    d = a.date or date.today().isoformat()
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', d):
        sys.exit('learn: --date YYYY-MM-DD')
    text = clean(a.text, 'text')
    if len(text) > 400:
        sys.exit('learn: keep --text under 400 characters (one fact per entry)')
    line = (f'- {d} | {clean(phase, "phase")} | {clean(a.milestone, "milestone")} | {clean(a.check, "check")} | '
            f'{a.kind} | {clean(run, "run")} | {text}')
    f = target(tech, block, a.tech_wide)
    os.makedirs(os.path.dirname(f), exist_ok=True)
    if os.path.exists(f):
        if line in (ln.rstrip('\n') for ln in open(f)):
            print(f'learn: duplicate, not added ({os.path.relpath(f, C.ROOT)})')
            return
    else:
        open(f, 'w').write(header(tech, block, a.tech_wide))
    with open(f, 'a') as fh:
        fh.write(line + '\n')
    print(f'learn: added to {os.path.relpath(f, C.ROOT)}\n  {line}')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('context', help='tech / block / store files of a run')
    c.add_argument('run_dir')
    for name in ('read', 'add'):
        p = sub.add_parser(name)
        p.add_argument('--run-dir')
        p.add_argument('--tech')
        p.add_argument('--block')
        p.add_argument('--milestone', required=(name == 'add'))
        p.add_argument('--check', required=(name == 'add'))
        p.add_argument('--kind', required=(name == 'add'))
        if name == 'read':
            p.add_argument('--summary', action='store_true')
        else:
            p.add_argument('--phase')
            p.add_argument('--run')
            p.add_argument('--tech-wide', action='store_true', help='write learned/<tech>/_tech.md')
            p.add_argument('--text', required=True)
            p.add_argument('--date')
    a = ap.parse_args()
    {'context': cmd_context, 'read': cmd_read, 'add': cmd_add}[a.cmd](a)


if __name__ == '__main__':
    main()
