"""Dispatch smoke test runner.

Exercises `launch_utils.tcl::{generate_launch_wrapper, submit_job}` directly
with stubbed bsub + xterm + every EDA tool shell to surface the bug class
that `test_mode=true` masks in the regular e2e runner: missing or corrupt
lsf/flow keys that the dispatch path reads but `handler_run` never gets to.

Invoked via `cbflow test --dispatch-smoke`. Stand-alone — no workspace
required; each row runs inside its own temp dir.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

# (flow, stage, tier_hint, tool) — tier_hint is the expected lsf
# flow_mapping tier so we can verify the bsub command resolved the right
# memory/cpu quartet. tool covers the PD discipline today.
_PD_MATRIX = [
    # SYNTH_PNR's only shipped tool today is fc. The other tools below
    # don't actually ship handlers under cmds/SYNTH_PNR/, but the smoke
    # harness only exercises the dispatch path (lsf flow_mapping lookup,
    # tool_shell binary resolution, wrapper exec, bsub fire) — using
    # SYNTH_PNR as the flow_mapping lookup vehicle here is enough to
    # cover each tool's tool_shell entry. When a flow grows a new tool,
    # add a row with the right (flow, stage) instead.
    ('SYNTH_PNR', 'init_design',  'S',     'fc'),
    ('SYNTH_PNR', 'synthesis',    'M',     'fc'),
    ('SYNTH_PNR', 'synthesis',    'M',     'genus'),
    ('SYNTH_PNR', 'place',        'L',     'fc'),
    ('SYNTH_PNR', 'release_data', 'XS',    'fc'),
    ('SYNTH_PNR', 'release_data', 'XS',    'pt'),
    # tools whose tool_shell mapping we still want to verify, even
    # though they're not bound to SYNTH_PNR handlers:
    ('SYNTH_PNR', 'init_design',  'S',     'innovus'),
    ('SYNTH_PNR', 'place',        'L',     'innovus'),
    ('SYNTH_PNR', 'route',        'XL',    'innovus'),
    ('SYNTH_PNR', 'signoff',      'M',     'tempus'),
    ('SYNTH_PNR', 'signoff',      'M',     'formality'),
    ('SYNTH_PNR', 'signoff',      'M',     'fm'),
    ('SYNTH_PNR', 'signoff',      'M',     'vc_lp'),
    ('SYNTH_PNR', 'signoff',      'M',     'icv'),
    ('SYNTH_PNR', 'signoff',      'M',     'calibre'),
    ('SYNTH_PNR', 'signoff',      'M',     'redhawk'),
    ('SYNTH_PNR', 'signoff',      'M',     'voltus'),
    ('SYNTH_PNR', 'signoff',      'M',     'conformal_lp'),
    ('SYNTH_PNR', 'signoff',      'M',     'conformal'),
    ('SYNTH_PNR', 'signoff',      'M',     'joules'),
]

# DFT tools — same shape, exercised under SYNTH_PNR's flow_mapping (the
# resource tier is the same idea; we're only validating the tool_shell
# lookup path here). When DFT_INSERT etc. land in tool_launch_config's
# flow_mapping table, the (flow, stage) pair can be swapped to match.
_DFT_MATRIX = [
    ('SYNTH_PNR', 'synthesis', 'M', 'tessent'),
    ('SYNTH_PNR', 'synthesis', 'M', 'dft_compiler'),
    ('SYNTH_PNR', 'synthesis', 'M', 'testmax'),
    ('SYNTH_PNR', 'synthesis', 'M', 'vcs'),
    ('SYNTH_PNR', 'synthesis', 'M', 'questa'),
]

_TIER_TO_MEM = {
    'XS': '4GB', 'S': '16GB', 'M': '64GB',
    'L': '128GB', 'XL': '256GB', 'ultra': '512GB',
}


def _here() -> Path:
    return Path(__file__).resolve().parent


def _pd_dir() -> Path:
    return _here().parent.parent.parent


def _run_one(flow_type: str, stage_name: str, tier_hint: str, tool: str) -> tuple:
    """Run the Tcl harness for one (flow, stage, tier, tool). Returns
    (ok, detail) — the test assertion result."""
    harness = _here() / 'dispatch_smoke.tcl'
    stubs = _here() / 'stubs'
    pd_dir = _pd_dir()

    if not harness.exists():
        return False, f'harness missing: {harness}'
    if not stubs.exists():
        return False, f'stubs dir missing: {stubs}'

    with tempfile.TemporaryDirectory(prefix='cbflow_dispatch_smoke_') as tmp:
        stub_log = os.path.join(tmp, 'stub.log')
        env = dict(os.environ)
        env['PATH'] = f'{stubs}{os.pathsep}{env.get("PATH", "")}'
        env['CBFLOW_CORE_DIR'] = str(pd_dir)
        env['CBFLOW_STUB_LOG'] = stub_log
        try:
            proc = subprocess.run(
                ['tclsh', str(harness), flow_type, stage_name, tool],
                cwd=tmp, env=env,
                capture_output=True, text=True, timeout=15,
            )
        except subprocess.SubprocessError as e:
            return False, f'subprocess error: {e}'

        if proc.returncode != 0:
            tail = (proc.stdout + proc.stderr).strip().splitlines()[-5:]
            return False, 'tclsh exit != 0:\n  ' + '\n  '.join(tail)

        # Parse WRAPPER_PATH / TOOL_SHELL out of harness stdout.
        wrapper_path = None
        tool_shell = None
        for line in proc.stdout.splitlines():
            if line.startswith('WRAPPER_PATH='):
                wrapper_path = line.split('=', 1)[1].strip()
            elif line.startswith('TOOL_SHELL='):
                tool_shell = line.split('=', 1)[1].strip()
        if not wrapper_path or not tool_shell:
            return False, ('harness did not emit WRAPPER_PATH/TOOL_SHELL — '
                           'output:\n  ' + '\n  '.join(proc.stdout.splitlines()[:5]))

        # ── Wrapper-content assertions ──────────────────────────────────────
        if not os.path.exists(wrapper_path):
            return False, f'wrapper file missing: {wrapper_path}'
        with open(wrapper_path) as f:
            wrapper_body = f.read()
        if not wrapper_body.startswith('#!'):
            return False, f'wrapper missing shebang:\n{wrapper_body[:200]}'
        if tool_shell not in wrapper_body:
            return False, (
                f'wrapper does not invoke expected tool_shell {tool_shell!r}:\n'
                f'  {wrapper_body[:300]}'
            )

        # ── bsub-stub assertions ────────────────────────────────────────────
        if not os.path.exists(stub_log):
            return False, 'bsub stub never invoked'
        with open(stub_log) as f:
            stub_lines = [ln.rstrip() for ln in f if ln.strip()]
        bsub_lines = [ln for ln in stub_lines if ln.startswith('bsub ')]
        if not bsub_lines:
            return False, ('stub log has no bsub line — submit_job took '
                           'the no-LSF branch or errored silently')
        bsub_cmd = bsub_lines[0]
        expected_mem = _TIER_TO_MEM.get(tier_hint)
        if expected_mem and f'rusage[mem={expected_mem}]' not in bsub_cmd:
            return False, (
                f'bsub resolved to wrong tier — expected '
                f'rusage[mem={expected_mem}] (tier {tier_hint}), got:\n  '
                + bsub_cmd[:200]
            )
        expected_job = f'cbflow_{flow_type}_{stage_name}'
        if expected_job not in bsub_cmd:
            return False, (
                f'bsub missing job name {expected_job!r}:\n  '
                + bsub_cmd[:200]
            )

        # ── tool-shell exec evidence ────────────────────────────────────────
        # The bsub stub chains: it execs `-e <wrapper>` so the wrapper runs,
        # which in turn execs the tool_shell binary (also stubbed). A line
        # starting with the tool_shell name confirms the whole chain fired:
        # bsub → wrapper → tool_shell. Missing → wrapper didn't actually
        # invoke the tool (broken launch line, wrong shell, etc.).
        tool_lines = [ln for ln in stub_lines if ln.startswith(f'{tool_shell} ')]
        if not tool_lines:
            return False, (
                f'tool_shell {tool_shell!r} stub never invoked — wrapper '
                f'chain broke between bsub and the EDA tool. Stub log:\n  '
                + '\n  '.join(stub_lines[:5])
            )

        return True, (
            f'tool_shell={tool_shell} tier={tier_hint} '
            f'mem={expected_mem} bsub_jobname={expected_job}'
        )


def _check_tool_shell_coverage() -> tuple:
    """Static cross-reference: every tool that ships a `<FLOW>_<tool>_config.tcl`
    must have a corresponding `lsf(tool_shell,<tool>)` defined OR the tool
    name must be a valid bare binary the wrapper can exec. We can only
    reason about the first half here; flag the others as 'fallback'."""
    node_configs_dir = _pd_dir() / 'config' / 'flow' / 'v1.0.0' / 'node_configs'
    tlc = _pd_dir() / 'config' / 'flow' / 'v1.0.0' / 'tool_launch_config.tcl'
    if not node_configs_dir.exists() or not tlc.exists():
        return True, 'config dirs missing (skip)'

    # Discover every `_<tool>_config.tcl` filename suffix.
    tools_shipped = set()
    pat = re.compile(r'^[A-Z_]+_([a-z_]+)_config\.tcl$')
    for fname in os.listdir(node_configs_dir):
        m = pat.match(fname)
        if m:
            tools_shipped.add(m.group(1))

    # Find every `set lsf(tool_shell,<tool>) "..."` in tool_launch_config.
    # Anchor at line start (after optional whitespace) so commented-out
    # entries (`# set lsf(tool_shell,X)`) don't get counted.
    with open(tlc) as f:
        tlc_content = f.read()
    tools_with_shell = set(
        re.findall(
            r'^\s*set\s+lsf\(tool_shell,(\w+)\)',
            tlc_content,
            re.MULTILINE,
        )
    )

    missing = sorted(tools_shipped - tools_with_shell)
    if missing:
        return False, (
            f'{len(missing)} tool(s) ship a node_config but no '
            f'lsf(tool_shell,<tool>) — wrapper will fall back to the bare '
            f'tool name on PATH. Add entries to tool_launch_config.tcl: '
            + ', '.join(missing)
        )
    return True, f'all {len(tools_shipped)} shipped tools have lsf(tool_shell,*) defined'


def run(results) -> None:
    """Run every (flow, stage, tier, tool) in the matrix. Aggregate into
    results."""
    suite = 'dispatch'

    # 1. Tool-shell coverage cross-reference (one PASS or one FAIL).
    ok, detail = _check_tool_shell_coverage()
    cat = 'coverage'
    if ok:
        results.passed(suite, cat, 'tool_shell coverage', detail)
    else:
        results.failed(suite, cat, 'tool_shell coverage', detail)

    # 2. Per-tool dispatch smoke.
    for flow_type, stage_name, tier_hint, tool in _PD_MATRIX + _DFT_MATRIX:
        category = f'{flow_type}/{stage_name}/{tool}'
        ok, detail = _run_one(flow_type, stage_name, tier_hint, tool)
        if ok:
            results.passed(suite, category, 'submit_job + wrapper', detail)
        else:
            results.failed(suite, category, 'submit_job + wrapper', detail)


def main(argv=None) -> int:
    """Stand-alone entry point for manual invocation."""
    from results import Results  # noqa
    r = Results()
    run(r)
    for entry in r.entries:
        flag = '[PASS]' if entry['status'] == 'PASS' else '[FAIL]'
        print(f"{flag} {entry['category']}: {entry['detail']}")
    return 1 if r.has_failures() else 0


if __name__ == '__main__':
    sys.exit(main())
