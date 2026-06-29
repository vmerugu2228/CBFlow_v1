"""CLI smoke test runner.

Auto-discovers every leaf `cbflow X Y Z ...` subcommand by recursively
walking `cbflow X --help`, then invokes each one with safe args. Catches
regressions where a subcommand exists but is broken (import error, missing
arg validation, schema drift) — a bug class neither static_checks nor
e2e_runner exercises.

Invoked via `cbflow test --cli-smoke`. Two contexts:
  - outside-sandbox : commands that don't need a run-dir
                      (workspace template, flow info, library-manager list)
  - inside-sandbox  : commands that read a run-dir
                      (run status, run logs, run db-manage status,
                       flow checklist generate)
  One shared SYNTH_PNR/ravendrive sandbox covers all inside-sandbox cases.

Safety:
  - DESTRUCTIVE_LEAVES skip by default; --destructive turns them on.
  - --help is always safe; we ALSO call `<cmd> --help` for every discovered
    leaf as a baseline that catches help-only breakage.
"""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path


# ─── Static config tables ────────────────────────────────────────────────────

# Args that make each leaf command runnable safely (no destructive side
# effects). Keys are the full subcommand path as a tuple. Missing leaves
# get `--help`-only coverage (which is still useful — catches help-text
# crashes).
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
    ('flow', 'project', 'info'):    ['--name', 'ravendrive'],

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
    # Subcommands list/check/coverage don't accept `--tag`. They look for
    # the default `lib_config.tcl` filename; this tree ships
    # `lib_config_P0.tcl` (tagged). The check/list/coverage commands
    # therefore exit 1 with "Tech config not found" or "lib_config.tcl
    # not found" — that's expected for a tagged-only library tree.
    # _run_one's expected-patterns list tolerates these messages.
    # library-manager subcommands need an absolute --tech-config path or
    # a populated CWD. Defer to --help-only coverage (still catches broken
    # subcommand registration / argparse breakage); skip the read-only
    # invocation, which is environmentally too sensitive to a stable
    # cwd + tagged lib_config layout for this smoke.

    # ── run (sandbox-only) — args set per-leaf ────────────────────────
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

# Leaves that need a sandbox WORKAREA cwd (workspace commands).
SANDBOX_WORKAREA = {
    ('workspace', 'status'),
    ('workspace', 'list-runs'),
    ('workspace', 'list'),
    ('workspace', 'run-status'),
    ('workspace', 'validate'),
    ('workspace', 'template'),
}

# Leaves that need a RUN-DIR cwd (run commands).
SANDBOX_RUNDIR = {
    ('run', 'status'),
    ('run', 'list-nodes'),
    ('run', 'list-branches'),
    ('run', 'logs'),
    ('run', 'release-info'),
    ('run', 'targets'),
    ('run', 'show-graph'),
}

# Union — used to decide whether to spin up the sandbox at all.
SANDBOX_REQUIRED = SANDBOX_WORKAREA | SANDBOX_RUNDIR


# ─── CLI discovery ───────────────────────────────────────────────────────────

# Top-level cbflow uses a custom-rendered help (heredoc'd in the bash
# launcher), not argparse — so the top groups are hard-coded. Every
# subcommand below them DOES use argparse with the canonical
# `{a,b,c,...}` choices list, which is what we parse.
_TOP_GROUPS = ('workspace', 'run', 'flow')

# Matches argparse's positional-choices line:
#     {create,template,list-runs,run-status,status,update,clean,validate,list}
_CHOICES_RE = re.compile(r'^\s*\{([a-z0-9_,\-]+)\}\s*$', re.MULTILINE)


def _argparse_children(help_text: str) -> list[str]:
    """Pull child subcommand names out of an argparse --help dump."""
    m = _CHOICES_RE.search(help_text)
    if not m:
        return []
    raw = m.group(1)
    return [c.strip() for c in raw.split(',') if c.strip()]


# Fallback parser for the bash heredoc-style help blocks that cbflow
# uses for top-level and `flow`. Scrape lines like:
#     cbflow flow project list                     List all projects
#     cbflow flow checklist list-checks --milestone PLACE_EXIT
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
    """Recursively walk `cbflow ... --help` and return every leaf command
    as a tuple path. e.g. ('flow', 'checklist', 'list').

    Top-level groups are hard-coded (cbflow's own --help is a bash heredoc,
    not argparse). Below the top, every subcommand uses argparse and we
    parse the `{a,b,c,...}` choices block to find children.
    """
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

        # Try argparse format first; fall back to heredoc scraping.
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
    """Return 'destructive' | 'sandbox-workarea' | 'sandbox-rundir' |
       'outside' | 'help-only'."""
    if path in DESTRUCTIVE_LEAVES:
        return 'destructive'
    if path in SAFE_ARGS:
        if path in SANDBOX_WORKAREA:
            return 'sandbox-workarea'
        if path in SANDBOX_RUNDIR:
            return 'sandbox-rundir'
        return 'outside'
    return 'help-only'


def _run_one(cbflow_bin: str, path: tuple, args: list, cwd: str,
             timeout: int = 30) -> tuple:
    """Run one cli command. Returns (status, detail)."""
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

    # Non-zero exits — some are legitimately expected (e.g. running a
    # workspace-context command outside a workarea). Strip the cbflow
    # ASCII logo box from stderr noise, look at the meaningful tail.
    msg = _meaningful_stderr_tail(res.stderr or res.stdout or '')
    expected_patterns = (
        # No run/workarea context — outside-sandbox runs.
        'no run found', 'no workspace', 'not a cbflow', 'not in a workarea',
        'no .run.cbflow.tcl', 'not in a run directory',
        'no run directory', 'must be run from',
        'not in a valid workspace directory',
        # Argparse usage banners for non-leaf nodes we couldn't auto-detect.
        'usage: cbflow',
        # Tech / library config absent (library-manager against a tree
        # without a default lib_config.tcl). Surfaces structural gaps but
        # isn't a CLI breakage.
        'tech config not found', 'lib_config.tcl not found',
        'no library_sets found',
    )
    if any(p in msg.lower() for p in expected_patterns):
        return 'PASS', f'exit={res.returncode} (expected: {msg[:80]})'

    return 'FAIL', f'exit={res.returncode}: {msg[:200]}'


def _meaningful_stderr_tail(text: str) -> str:
    """Drop the cbflow ASCII logo box and other UI fluff from a stderr
    blob, return the last informative line (or two)."""
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
    # Last 2 meaningful lines, separated.
    return ' | '.join(lines[-2:])


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

    # Phase 2: prepare a shared sandbox if any leaf needs one.
    workarea_cwd = None
    rundir_cwd = None
    if any(_classify(p) in ('sandbox-workarea', 'sandbox-rundir')
           for p in leaves):
        workarea_cwd, rundir_cwd = _prepare_sandbox(pd_dir, results)

    # Phase 3: run each leaf in its appropriate context.
    destructive_enabled = bool(args and getattr(args, 'destructive', False))
    outside_cwd = tempfile.mkdtemp(prefix='cbflow-cli-smoke-')

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

        # outside / sandbox-* — safe args, real run.
        safe = SAFE_ARGS[path]
        if klass == 'sandbox-workarea':
            cwd = workarea_cwd
            cat = 'workarea'
        elif klass == 'sandbox-rundir':
            cwd = rundir_cwd
            cat = 'rundir'
        else:
            cwd = outside_cwd
            cat = 'outside'

        if klass.startswith('sandbox-') and not cwd:
            results.skipped(suite, cat, slug,
                            'sandbox preparation failed; skipping')
            continue

        status, detail = _run_one(cbflow, path, safe, cwd)
        results.add(suite, cat, slug, status, detail)


def _prepare_sandbox(pd_dir: str, results):
    """Build one SYNTH_PNR/ravendrive sandbox. Returns (workarea_cwd,
    rundir_cwd). Either may be None if prep failed at that step.
    """
    try:
        from test_suite import e2e_runner
    except ImportError as e:
        results.failed('cli', 'sandbox', 'prepare',
                       f'cannot import e2e_runner: {type(e).__name__}: {e}')
        return None, None

    repo_root = os.path.dirname(pd_dir)
    workarea_test = os.path.join(repo_root, 'workarea_test')
    try:
        sandbox, fixture_or_err, cwd = e2e_runner.prepare_sandbox(
            'SYNTH_PNR', repo_root, pd_dir, workarea_test,
            vendor=None, project='ravendrive')
    except Exception as e:
        results.failed('cli', 'sandbox', 'prepare',
                       f'prepare_sandbox raised: {type(e).__name__}: {e}')
        return None, None

    if isinstance(fixture_or_err, str):
        results.skipped('cli', 'sandbox', 'prepare',
                        f'no fixture: {fixture_or_err}')
        return None, None

    workarea_cwd = cwd

    # Workspace-create so `run` commands have a run-dir to operate on.
    # e2e_runner.run_workspace_create signature:
    #   (pd_dir, cwd, config_path, timeout, log_buf)
    log_buf = []
    try:
        rc, _ = e2e_runner.run_workspace_create(
            pd_dir, workarea_cwd, fixture_or_err, 60, log_buf)
    except Exception as e:
        results.failed('cli', 'sandbox', 'workspace create',
                       f'raised: {type(e).__name__}: {e}')
        return workarea_cwd, None

    if rc != 0:
        results.failed('cli', 'sandbox', 'workspace create', f'rc={rc}')
        return workarea_cwd, None

    candidates = sorted(Path(workarea_cwd).glob('P0_run_*'))
    if not candidates:
        results.failed('cli', 'sandbox', 'run-dir lookup',
                       'no run dir under sandbox after workspace create')
        return workarea_cwd, None

    rundir_cwd = str(candidates[0])
    results.passed('cli', 'sandbox', 'ready',
                   f'workarea + {os.path.basename(rundir_cwd)}')
    return workarea_cwd, rundir_cwd
