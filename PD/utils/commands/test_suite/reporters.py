"""Reporters for the test suite: console, JSON, JUnit XML."""

import json
import os
import xml.etree.ElementTree as ET


# ── Console ─────────────────────────────────────────────────────────────────

class Console:
    """Simple section-aware console reporter. Driven incrementally by the
    runner: section()/line() called as work progresses, summary() at end.
    """

    def __init__(self, verbose=False, quiet=False, color=True):
        self.verbose = verbose
        self.quiet = quiet
        self.color = color and os.environ.get('NO_COLOR') is None

    def _c(self, text, code):
        if not self.color:
            return text
        return f'\033[{code}m{text}\033[0m'

    def section(self, title):
        if self.quiet:
            return
        print()
        print('=' * 70)
        print(f'  {title}')
        print('=' * 70)

    def event(self, status, test, detail=''):
        if self.quiet:
            return
        if status == 'PASS' and not self.verbose:
            return
        tag = {
            'PASS': self._c('PASS', '32'),
            'FAIL': self._c('FAIL', '31'),
            'SKIP': self._c('SKIP', '33'),
        }.get(status, status)
        suffix = f': {detail}' if detail else ''
        print(f'  [{tag}] {test}{suffix}')

    def info(self, msg):
        if self.quiet:
            return
        print(f'  {msg}')

    def summary(self, results):
        counts = results.counts()
        total = sum(counts.values())
        elapsed = results.duration_s()
        outcome = 'ALL PASS' if not results.has_failures() else 'FAILURES FOUND'
        outcome_c = self._c(outcome, '32' if not results.has_failures() else '31')
        print()
        print('#' * 70)
        print('  CBFLOW TEST SUITE — SUMMARY')
        print('#' * 70)
        print(f'  Total       : {total}')
        print(f'  PASS        : {counts["PASS"]}')
        print(f'  FAIL        : {counts["FAIL"]}')
        print(f'  SKIP        : {counts["SKIP"]}')
        print(f'  Duration    : {elapsed:.1f}s')
        print(f'  Result      : {outcome_c}')
        if results.has_failures():
            print()
            print('  FAILURES:')
            for e in results.failures():
                where = f'{e["suite"]}/{e["category"]}'
                detail = f' ({e["detail"]})' if e['detail'] else ''
                print(f'    - [{where}] {e["test"]}{detail}')
        print('#' * 70)


# ── JSON ────────────────────────────────────────────────────────────────────

def write_json(path, results):
    counts = results.counts()
    payload = {
        'summary': {
            'pass': counts['PASS'],
            'fail': counts['FAIL'],
            'skip': counts['SKIP'],
            'duration_s': results.duration_s(),
            'has_failures': results.has_failures(),
        },
        'entries': results.entries,
    }
    with open(path, 'w') as f:
        json.dump(payload, f, indent=2, sort_keys=True)


# ── JUnit XML ───────────────────────────────────────────────────────────────

def write_junit(path, results):
    grouped = {}
    for e in results.entries:
        key = f'{e["suite"]}.{e["category"]}'
        grouped.setdefault(key, []).append(e)

    counts = results.counts()
    suites = ET.Element('testsuites', {
        'name': 'cbflow-test-suite',
        'tests': str(sum(counts.values())),
        'failures': str(counts['FAIL']),
        'skipped': str(counts['SKIP']),
        'time': f'{results.duration_s():.3f}',
    })
    for key, entries in sorted(grouped.items()):
        ts = ET.SubElement(suites, 'testsuite', {
            'name': key,
            'tests': str(len(entries)),
            'failures': str(sum(1 for e in entries if e['status'] == 'FAIL')),
            'skipped': str(sum(1 for e in entries if e['status'] == 'SKIP')),
        })
        for e in entries:
            tc = ET.SubElement(ts, 'testcase', {
                'classname': key,
                'name': e['test'],
                'time': f'{e["duration_ms"] / 1000.0:.3f}',
            })
            if e['status'] == 'FAIL':
                f = ET.SubElement(tc, 'failure', {'message': e['detail'] or 'failed'})
                f.text = e['detail']
            elif e['status'] == 'SKIP':
                ET.SubElement(tc, 'skipped', {'message': e['detail'] or 'skipped'})
    tree = ET.ElementTree(suites)
    tree.write(path, encoding='utf-8', xml_declaration=True)
