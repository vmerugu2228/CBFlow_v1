"""Shared result collector for the CBflow test suite.

Both static checks and e2e checks push outcomes here. Reporters consume it.
"""

import time


class Results:
    PASS = 'PASS'
    FAIL = 'FAIL'
    SKIP = 'SKIP'

    def __init__(self):
        self.entries = []
        self.started_at = time.time()

    def add(self, suite, category, test, status, detail='', duration_ms=0):
        self.entries.append({
            'suite': suite,
            'category': category,
            'test': test,
            'status': status,
            'detail': detail,
            'duration_ms': duration_ms,
        })

    def passed(self, suite, category, test, detail='', duration_ms=0):
        self.add(suite, category, test, self.PASS, detail, duration_ms)

    def failed(self, suite, category, test, detail='', duration_ms=0):
        self.add(suite, category, test, self.FAIL, detail, duration_ms)

    def skipped(self, suite, category, test, detail='', duration_ms=0):
        self.add(suite, category, test, self.SKIP, detail, duration_ms)

    def counts(self):
        c = {self.PASS: 0, self.FAIL: 0, self.SKIP: 0}
        for e in self.entries:
            c[e['status']] += 1
        return c

    def duration_s(self):
        return time.time() - self.started_at

    def has_failures(self):
        return any(e['status'] == self.FAIL for e in self.entries)

    def failures(self):
        return [e for e in self.entries if e['status'] == self.FAIL]
