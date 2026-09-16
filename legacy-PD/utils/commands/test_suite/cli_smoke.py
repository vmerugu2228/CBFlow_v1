"""CLI smoke test runner.

Auto-discovers every leaf `cbflow X Y Z ...` subcommand by recursively
walking `cbflow X --help`, then invokes each one with safe args. Catches
regressions where a subcommand exists but is broken (import error, missing
arg validation, schema drift) — a bug class neither static_checks nor
e2e_runner exercises.

Invoked via `cbflow test --cli-smoke`.

Three execution modes per leaf:
  - DESTRUCTIVE — `run/release`, `flow checklist sign-off`, etc.: skipped
    by default; `--cli-smoke --destructive` opts in to `--help`-only runs.
  - SANDBOX-bound — workspace commands (need a workarea cwd) and `run`
    commands (need a run-dir cwd). Each flow×project sandbox is built
    once and shared across every command that fits its context.
  - OUTSIDE-sandbox + HELP-only — both run in a clean tempdir.

Three SAFE_ARGS value types:
  - list of str         — fixed args
  - callable(ctx)→list  — resolved at runtime; ctx has pd_dir, run_dir
  - None                — `--help`-only fallback (omitted from map ⇒ same)

NEGATIVE_TESTS — per-leaf {args → expected_error_substring} pairs run
deliberately to confirm validation fires when given bad input.
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path


# ─── Static config tables ────────────────────────────────────────────────────

def _libmgr_tech_config_args(ctx: dict) -> list[str]:
    """Build a --tech-config absolute-path arg from the active PD root."""
    p = os.path.join(ctx['pd_dir'],
                     'config', 'tech', 'gf_22nm', 'v1.0.0', 'tech_config.tcl')
    return ['--tech-config', p]


SAFE_ARGS = {
    # ── workspace ─────────────────────────────────────────────────────
    ('workspace', 'template'):     ['--flow', 'PNR'],
    ('workspace', 'status'):       [],
    ('workspace', 'list-runs'):    [],
    ('workspace', 'run-status'):   [],
    ('workspace', 'list'):         [],
    ('workspace', 'validate'):     [],

    # ── flow info / introspection ─────────────────────────────────────
    ('flow', 'types'):              [],
    ('flow', 'list-flows'):         [],
    ('flow', 'check'):              [],
    ('flow', 'info'):               ['--flow', 'PNR'],
    ('flow', 'stages'):             ['--flow', 'PNR'],
    ('flow', 'nodes'):              ['--flow', 'PNR'],

    # ── flow project (read-only) ──────────────────────────────────────
    ('flow', 'project', 'list'):    [],
    ('flow', 'project', 'info'):    ['--name', 'bumblebee'],

    # ── flow release (read-only) ──────────────────────────────────────
    ('flow', 'release', 'list'):    [],

    # ── flow version (read-only) ──────────────────────────────────────
    ('flow', 'version', 'list'):    ['--dir', 'config'],
    ('flow', 'version', 'status'):  [],

    # ── flow dev (read-only) ──────────────────────────────────────────
    ('flow', 'dev', 'status'):      [],

    # ── flow checklist (read-only mode) ──────────────────────────────
    ('flow', 'checklist', 'list'):        [],
    ('flow', 'checklist', 'list-checks'): ['--milestone', 'PLACE_EXIT'],

    # ── flow library-manager (read-only) ──────────────────────────────
    # list/check accept --tech-config <absolute path>. Callable resolves
    # at runtime since the static map can't know pd_dir.
    ('flow', 'library-manager', 'list'):     _libmgr_tech_config_args,
    ('flow', 'library-manager', 'check'):    _libmgr_tech_config_args,
    ('flow', 'library-manager', 'coverage'): ['--tech', 'gf_22nm'],

    # ── run (sandbox-only) ────────────────────────────────────────────
    ('run', 'status'):        [],
    ('run', 'list-nodes'):    [],
    ('run', 'list-branches'): [],
    ('run', 'logs'):          ['--list'],
    ('run', 'release-info'):  [],
    ('run', 'targets'):       [],
    ('run', 'show-graph'):    [],
}

# Leaves that are intrinsically write/destructive — never auto-run without
# the user opting in via --destructive.
DESTRUCTIVE_LEAVES = {
    ('workspace', 'create'),
    ('workspace', 'clean'),
    ('workspace', 'update'),
    ('run', 'all'),
    ('run', 'stage'),
    ('run', 'retrace'),
    ('run', 'bypass'),
    ('run', 'force'),
    ('run', 'forcevalidate'),
    ('run', 'clean'),
    ('run', 'release'),
    ('run', 'release-lock'),
    ('run', 'release-check'),
    ('run', 'add-node'),
    ('run', 'delete-node'),
    ('run', 'create-branch'),
    ('run', 'delete-branch'),
    ('run', 'update'),
    ('flow', 'checklist', 'sign-off'),
    ('flow', 'checklist', 'add-check'),
    ('flow', 'checklist', 'remove-check'),
    ('flow', 'checklist', 'waiver'),
    ('flow', 'checklist', 'generate'),
    ('flow', 'project', 'create'),
    ('flow', 'release', 'create'),
    ('flow', 'dev', 'start'),
    ('flow', 'dev', 'promote'),
    ('flow', 'dev', 'sandbox-push'),
    ('flow', 'dev', 'sandbox-create'),
    ('flow', 'library-manager', 'generate'),
    ('flow', 'library-manager', 'generate-mmmc'),
    ('flow', 'library-manager', 'scan'),
}

SANDBOX_WORKAREA = {
    ('workspace', 'status'),
    ('workspace', 'list-runs'),
    ('workspace', 'list'),
    ('workspace', 'run-status'),
    ('workspace', 'validate'),
    ('workspace', 'template'),
}

SANDBOX_RUNDIR = {
    ('run', 'status'),
    ('run', 'list-nodes'),
    ('run', 'list-branches'),
    ('run', 'logs'),
    ('run', 'release-info'),
    ('run', 'targets'),
    ('run', 'show-graph'),
}

SANDBOX_REQUIRED = SANDBOX_WORKAREA | SANDBOX_RUNDIR


# Negative tests — per leaf, a list of (bad_args, expected_substring) pairs.
# The runner invokes with bad_args and asserts that:
#   1. exit code is non-zero, AND
#   2. the expected substring appears in stdout+stderr (case-insensitive).
# These catch regressions in argparse validation (someone removes a
# `required=True`, an `int` type check, or a `choices=[...]` constraint).
NEGATIVE_TESTS = {
    ('flow', 'info'): [
        # Missing --flow argument
        ([], 'flow'),
        # Unknown flow value
        (['--flow', 'NOT_A_REAL_FLOW'], 'flow'),
    ],
    ('flow', 'stages'): [
        ([], 'flow'),
    ],
    ('flow', 'nodes'): [
        ([], 'flow'),
    ],
    ('workspace', 'template'): [
        # Missing --flow
        ([], 'flow'),
        # Bogus flow
        (['--flow', 'BOGUS'], 'flow'),
    ],
    ('flow', 'project', 'info'): [
        # Missing --name
        ([], 'name'),
    ],
    ('flow', 'checklist', 'list-checks'): [
        # Missing --milestone
        ([], 'milestone'),
        # Bogus milestone
        (['--milestone', 'BOGUS_MILESTONE'], 'milestone'),
    ],
}


# Sandbox iteration matrix. (flow, project) pairs that get their own
# sandbox built. Each pair lets sandbox-context commands run against
# a distinct flow's workarea + run-dir, catching tool-specific
# regressions (e.g. an Innovus-flavored `run logs` path that breaks
# while the Synopsys one keeps passing).
#
# Keep the matrix small for smoke speed — pair selection covers both
# vendor stacks + the two structurally-distinct flows (PNR uses a
# bigger stage set than STA).
SANDBOX_MATRIX = [
    ('SYNTH_PNR', 'bumblebee'),  # Synopsys, full PnR chain
    ('PNR',       'bumblebee'),  # Synopsys, PNR only
    ('PNR',       'denali'),      # Cadence/Innovus
    ('STA',       'bumblebee'),  # STA — smaller stage set
]


# ─── CLI discovery ───────────────────────────────────────────────────────────

_TOP_GROUPS = ('workspace', 'run', 'flow')
_CHOICES_RE = re.compile(r'^\s*\{([a-z0-9_,\-]+)\}\s*$', re.MULTILINE)


def _argparse_children(help_text: str) -> list[str]:
    m = _CHOICES_RE.search(help_text)
    if not m:
        return []
    raw = m.group(1)
    return [c.strip() for c in raw.split(',') if c.strip()]


def _heredoc_children(help_text: str, prefix_path: tuple) -> list[str]:
    pref = 'cbflow ' + ' '.join(prefix_path) + ' '
    children = []
    seen = set()
    for line in help_text.splitlines():
        stripped = line.lstrip()
        if not stripped.startswith(pref):
            continue
        rest = stripped[len(pref):].split(None, 1)[0]
        if not re.match(r'^[a-z][a-z0-9_-]+$', rest):
            continue
        if rest in seen:
            continue
        seen.add(rest)
        children.append(rest)
    return children


def discover(cbflow_bin: str, max_depth: int = 5) -> list[tuple]:
    leaves = []
    seen = set()

    def walk(path: tuple):
        if len(path) > max_depth or path in seen:
            return
        seen.add(path)
        if not path:
            for top in _TOP_GROUPS:
                walk((top,))
            return

        cmd = [cbflow_bin] + list(path) + ['--help']
        try:
            res = subprocess.run(cmd, capture_output=True, text=True,
                                 timeout=15)
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            return
        text = (res.stdout or '') + (res.stderr or '')

        children = _argparse_children(text) or _heredoc_children(text, path)
        if not children:
            leaves.append(path)
            return

        for c in children:
            walk(path + (c,))

    walk(())
    return [p for p in leaves if p]


# ─── Runner ──────────────────────────────────────────────────────────────────

def _cbflow_bin(pd_dir: str) -> str:
    return os.path.join(pd_dir, 'bin', 'cbflow')


def _classify(path: tuple) -> str:
    if path in DESTRUCTIVE_LEAVES:
        return 'destructive'
    if path in SAFE_ARGS:
        if path in SANDBOX_WORKAREA:
            return 'sandbox-workarea'
        if path in SANDBOX_RUNDIR:
            return 'sandbox-rundir'
        return 'outside'
    return 'help-only'


def _resolve_args(path: tuple, ctx: dict) -> list[str]:
    """Resolve SAFE_ARGS[path] into a concrete list[str]. Supports both
    static lists and callables that take a context dict."""
    val = SAFE_ARGS[path]
    if callable(val):
        return list(val(ctx))
    return list(val)


def _run_one(cbflow_bin: str, path: tuple, args: list, cwd: str,
             timeout: int = 30) -> tuple:
    cmd = [cbflow_bin] + list(path) + args
    try:
        res = subprocess.run(cmd, cwd=cwd,
                             capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 'FAIL', f'timeout after {timeout}s'
    except (FileNotFoundError, OSError) as e:
        return 'FAIL', f'spawn error: {e}'

    out = (res.stdout or '') + (res.stderr or '')
    if 'Traceback (most recent call last)' in out:
        return 'FAIL', 'python traceback in output'

    if res.returncode == 0:
        return 'PASS', 'exit=0'

    msg = _meaningful_stderr_tail(res.stderr or res.stdout or '')
    expected_patterns = (
        'no run found', 'no workspace', 'not a cbflow', 'not in a workarea',
        'no .run.cbflow.tcl', 'not in a run directory',
        'no run directory', 'must be run from',
        'not in a valid workspace directory',
        'usage: cbflow',
        'tech config not found', 'lib_config.tcl not found',
        'no library_sets found',
    )
    if any(p in msg.lower() for p in expected_patterns):
        return 'PASS', f'exit={res.returncode} (expected: {msg[:80]})'

    return 'FAIL', f'exit={res.returncode}: {msg[:200]}'


def _meaningful_stderr_tail(text: str) -> str:
    lines = []
    for line in text.splitlines():
        s = line.strip()
        if not s:
            continue
        if s.startswith('╔') or s.startswith('╠') or s.startswith('╚'):
            continue
        if s.startswith('║') or s.startswith('═'):
            continue
        if 'Developed by' in s or 'Physical Design Flow Management' in s:
            continue
        lines.append(s)
    return ' | '.join(lines[-2:])


def _run_negative(cbflow_bin: str, path: tuple, bad_args: list,
                  expected: str, cwd: str, timeout: int = 30) -> tuple:
    """Run a negative test: invocation MUST exit non-zero AND emit a
    diagnostic containing `expected` (case-insensitive)."""
    cmd = [cbflow_bin] + list(path) + bad_args
    try:
        res = subprocess.run(cmd, cwd=cwd,
                             capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 'FAIL', f'timeout after {timeout}s'
    except (FileNotFoundError, OSError) as e:
        return 'FAIL', f'spawn error: {e}'

    out = ((res.stdout or '') + (res.stderr or '')).lower()
    if res.returncode == 0:
        return 'FAIL', (f'expected non-zero exit but got 0 — '
                        f'validation may have been removed')
    if expected.lower() not in out:
        return 'FAIL', (f'exit={res.returncode} but expected substring '
                        f'{expected!r} not in error output')
    return 'PASS', f'exit={res.returncode}, matched {expected!r}'


def run(results, pd_dir: str, args=None):
    """Top-level entry. Called from test_cmd.py when --cli-smoke is on."""
    suite = 'cli'
    cbflow = _cbflow_bin(pd_dir)

    # Phase 1: discover the command tree.
    leaves = discover(cbflow)
    if not leaves:
        results.failed(suite, 'discovery', 'no leaf commands found',
                       'cbflow --help walking returned nothing')
        return
    results.passed(suite, 'discovery',
                   f'discovered {len(leaves)} leaf commands')

    # Phase 2: prepare a sandbox per (flow, project) in SANDBOX_MATRIX.
    sandboxes = {}  # (flow, project) → (workarea_cwd, rundir_cwd)
    if any(_classify(p) in ('sandbox-workarea', 'sandbox-rundir')
           for p in leaves):
        for (flow, project) in SANDBOX_MATRIX:
            wa, rd = _prepare_sandbox(pd_dir, results, flow, project)
            if wa or rd:
                sandboxes[(flow, project)] = (wa, rd)

    # Phase 3: run each leaf.
    destructive_enabled = bool(args and getattr(args, 'destructive', False))
    outside_cwd = tempfile.mkdtemp(prefix='cbflow-cli-smoke-')

    # Context dict for callable SAFE_ARGS resolution.
    ctx_outside = {'pd_dir': pd_dir, 'cwd': outside_cwd, 'run_dir': None}

    for path in sorted(leaves):
        slug = ' '.join(path) or '(root)'
        klass = _classify(path)

        if klass == 'destructive':
            if destructive_enabled:
                status, detail = _run_one(cbflow, path, ['--help'],
                                          outside_cwd)
                results.add(suite, 'help', slug, status, detail)
            else:
                results.skipped(suite, 'destructive', slug,
                                'destructive — opt in with --destructive')
            continue

        if klass == 'help-only':
            status, detail = _run_one(cbflow, path, ['--help'], outside_cwd)
            results.add(suite, 'help', slug, status, detail)
            continue

        # sandbox-* commands run against EVERY prepared sandbox in the
        # matrix (or the relevant subset). outside commands run once.
        if klass == 'sandbox-workarea':
            for (flow, project), (wa, rd) in sandboxes.items():
                if not wa:
                    continue
                ctx = {'pd_dir': pd_dir, 'cwd': wa, 'run_dir': rd}
                status, detail = _run_one(
                    cbflow, path, _resolve_args(path, ctx), wa)
                results.add(suite, f'workarea/{flow}/{project}', slug,
                            status, detail)
        elif klass == 'sandbox-rundir':
            for (flow, project), (wa, rd) in sandboxes.items():
                if not rd:
                    continue
                ctx = {'pd_dir': pd_dir, 'cwd': rd, 'run_dir': rd}
                status, detail = _run_one(
                    cbflow, path, _resolve_args(path, ctx), rd)
                results.add(suite, f'rundir/{flow}/{project}', slug,
                            status, detail)
        else:  # outside
            status, detail = _run_one(
                cbflow, path, _resolve_args(path, ctx_outside), outside_cwd)
            results.add(suite, 'outside', slug, status, detail)

    # Phase 4: negative tests — argument validation must still fire.
    for path, cases in NEGATIVE_TESTS.items():
        slug = ' '.join(path)
        for bad_args, expected in cases:
            label = f'{slug}  [{" ".join(bad_args) or "(no args)"}]'
            status, detail = _run_negative(
                cbflow, path, bad_args, expected, outside_cwd)
            results.add(suite, 'negative', label, status, detail)


def _prepare_sandbox(pd_dir: str, results, flow: str, project: str):
    """Build ONE sandbox for (flow, project). Returns (workarea_cwd,
    rundir_cwd). Either may be None if prep failed at that step."""
    try:
        from test_suite import e2e_runner
    except ImportError as e:
        results.failed('cli', 'sandbox', f'{flow}/{project} prepare',
                       f'cannot import e2e_runner: {type(e).__name__}: {e}')
        return None, None

    repo_root = os.path.dirname(pd_dir)
    workarea_test = os.path.join(repo_root, 'workarea_test')
    try:
        sandbox, fixture_or_err, cwd = e2e_runner.prepare_sandbox(
            flow, repo_root, pd_dir, workarea_test,
            vendor=None, project=project)
    except Exception as e:
        results.failed('cli', 'sandbox', f'{flow}/{project} prepare',
                       f'prepare_sandbox raised: {type(e).__name__}: {e}')
        return None, None

    if isinstance(fixture_or_err, str):
        results.skipped('cli', 'sandbox', f'{flow}/{project} prepare',
                        f'no fixture: {fixture_or_err}')
        return None, None

    workarea_cwd = cwd

    log_buf = []
    try:
        rc, _ = e2e_runner.run_workspace_create(
            pd_dir, workarea_cwd, fixture_or_err, 60, log_buf)
    except Exception as e:
        results.failed('cli', 'sandbox', f'{flow}/{project} workspace create',
                       f'raised: {type(e).__name__}: {e}')
        return workarea_cwd, None

    if rc != 0:
        results.failed('cli', 'sandbox',
                       f'{flow}/{project} workspace create',
                       f'rc={rc}')
        return workarea_cwd, None

    candidates = sorted(Path(workarea_cwd).glob('P0_run_*'))
    if not candidates:
        results.failed('cli', 'sandbox',
                       f'{flow}/{project} run-dir lookup',
                       'no run dir after workspace create')
        return workarea_cwd, None

    rundir_cwd = str(candidates[0])
    results.passed('cli', 'sandbox', f'{flow}/{project} ready',
                   f'workarea + {os.path.basename(rundir_cwd)}')
    return workarea_cwd, rundir_cwd
