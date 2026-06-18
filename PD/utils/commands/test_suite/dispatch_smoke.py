"""Dispatch smoke test runner.

Exercises `launch_utils.tcl::submit_job` directly with stubbed bsub + xterm
to surface the bug class that `test_mode=true` masks in the regular e2e
runner: missing or corrupt lsf/flow keys that submit_job reads but
`handler_run` never gets to.

Invoked via `cbflow test --dispatch-smoke`. Stand-alone — no workspace
required; everything runs inside a temp dir.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Flow / stage combinations to exercise. One per resource tier so a missing
# `lsf(queue_types,<tier>,*)` entry surfaces. SYNTH_PNR maps cleanly to all
# six tiers.
_FLOW_STAGE_MATRIX = [
    ('SYNTH_PNR', 'init_design', 'S'),
    ('SYNTH_PNR', 'synthesis', 'M'),
    ('SYNTH_PNR', 'place', 'L'),
    ('SYNTH_PNR', 'route', 'XL'),
    ('SYNTH_PNR', 'release_data', 'XS'),
]


def _here() -> Path:
    return Path(__file__).resolve().parent


def _pd_dir() -> Path:
    """PD/ root — assumes this file lives at PD/utils/commands/test_suite/."""
    return _here().parent.parent.parent


def _run_one(flow_type: str, stage_name: str, tier_hint: str) -> tuple:
    """Run the Tcl harness for one (flow, stage). Returns (ok, detail, bsub_line)."""
    harness = _here() / 'dispatch_smoke.tcl'
    stubs = _here() / 'stubs'
    pd_dir = _pd_dir()

    if not harness.exists():
        return False, f'harness missing: {harness}', ''
    if not stubs.exists():
        return False, f'stubs dir missing: {stubs}', ''

    with tempfile.TemporaryDirectory(prefix='cbflow_dispatch_smoke_') as tmp:
        stub_log = os.path.join(tmp, 'stub.log')
        env = dict(os.environ)
        env['PATH'] = f'{stubs}{os.pathsep}{env.get("PATH", "")}'
        env['CBFLOW_CORE_DIR'] = str(pd_dir)
        env['CBFLOW_STUB_LOG'] = stub_log
        try:
            proc = subprocess.run(
                ['tclsh', str(harness), flow_type, stage_name],
                cwd=tmp, env=env,
                capture_output=True, text=True, timeout=15,
            )
        except subprocess.SubprocessError as e:
            return False, f'subprocess error: {e}', ''

        if proc.returncode != 0:
            tail = (proc.stdout + proc.stderr).strip().splitlines()[-5:]
            return False, 'tclsh exit != 0:\n  ' + '\n  '.join(tail), ''

        # bsub stub MUST have been invoked.
        if not os.path.exists(stub_log):
            return False, ('bsub stub never invoked — submit_job took the '
                           'no-LSF branch or errored silently'), ''
        with open(stub_log) as f:
            bsub_lines = [ln.rstrip() for ln in f if ln.strip()]
        if not bsub_lines:
            return False, 'bsub stub log empty', ''

        bsub_cmd = bsub_lines[0]

        # Sanity-check the captured bsub command.
        # The L tier expects mem=128GB; verify the right tier resolved by
        # checking the rusage[mem=...] matches the expected tier hint.
        tier_to_mem = {
            'XS': '4GB', 'S': '16GB', 'M': '64GB',
            'L': '128GB', 'XL': '256GB', 'ultra': '512GB',
        }
        expected_mem = tier_to_mem.get(tier_hint)
        if expected_mem and f'rusage[mem={expected_mem}]' not in bsub_cmd:
            return False, (
                f'bsub command resolved to wrong tier — expected '
                f'rusage[mem={expected_mem}] (tier {tier_hint}), got:\n  '
                + bsub_cmd[:200]
            ), bsub_cmd

        # Flow/stage name must appear in the -J job name.
        expected_job = f'cbflow_{flow_type}_{stage_name}'
        if expected_job not in bsub_cmd:
            return False, (
                f'bsub command missing job name {expected_job!r}:\n  '
                + bsub_cmd[:200]
            ), bsub_cmd

        return True, f'bsub built with tier={tier_hint} (mem={expected_mem})', bsub_cmd


def run(results) -> None:
    """Run every (flow, stage, tier) in the matrix. Aggregate into results."""
    suite = 'dispatch'
    for flow_type, stage_name, tier_hint in _FLOW_STAGE_MATRIX:
        category = f'{flow_type}/{stage_name}'
        ok, detail, bsub_cmd = _run_one(flow_type, stage_name, tier_hint)
        if ok:
            results.passed(suite, category, 'submit_job dispatch', detail)
        else:
            results.failed(suite, category, 'submit_job dispatch', detail)


def main(argv=None) -> int:
    """Stand-alone entry point for manual invocation."""
    from results import Results  # noqa
    r = Results()
    run(r)
    failed = r.has_failures()
    for entry in r.entries:
        flag = '[PASS]' if entry['status'] == 'PASS' else '[FAIL]'
        print(f"{flag} {entry['category']}: {entry['detail']}")
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
