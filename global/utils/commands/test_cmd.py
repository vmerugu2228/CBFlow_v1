#!/usr/bin/env python3
"""CBflow Test Suite — `cbflow test` entry point.

Runs static config validation and (optionally) end-to-end flow execution
across the 12 supported flows, then reports results to the console and
optional machine-readable artifacts.

Defaults (documented choices, change with flags):
  - Static suite always runs.
  - E2E suite also runs (use --static to skip).
  - Sequential execution (e2e flows touch the same workarea/<design>/
    parent; sequential keeps cleanup deterministic).
  - One vendor per flow — the primary in node_configs/<FLOW>_config.tcl.
  - Sandboxes kept on failure, cleaned on success (--keep / --keep-on-fail).
  - Per-flow timeout: 300s (override with --timeout).
"""

import argparse
import os

# Post cbflow_global utils-refactor: shared Python packages (core.*,
# logging_config, cbflow_config, …) live under global/utils/, not PD/utils/.
# Add both to sys.path so inner `from core.* import …` calls resolve even
# when the invoker didn't preset env.
import sys as _bootstrap_sys
_this = os.path.dirname(os.path.abspath(__file__))
_pd_utils = os.path.dirname(_this)
_umbrella = os.path.dirname(os.path.dirname(_pd_utils))
_global_utils = os.path.join(_umbrella, 'global', 'utils')
if os.path.isdir(_global_utils) and _global_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _global_utils)
if _pd_utils not in _bootstrap_sys.path:
    _bootstrap_sys.path.insert(0, _pd_utils)

import re
import sys
import time
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# Post-refactor layout: this file lives at <REPO>/global/utils/commands/test_cmd.py
#   SCRIPT_DIR → global/utils/commands
#   dirname²  → global/utils
#   dirname³  → global
#   dirname⁴  → <REPO> (umbrella root — CBFLOW_ROOT)
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(SCRIPT_DIR)))
# PD_DIR anchors every static check — PD/config/flow, PD/cmds, PD/utils, …
# In a sparse-checkout DFT/DV clone, this directory may not exist; the
# static runner now skips cleanly when that's the case (see static_checks.run).
PD_DIR = os.environ.get('CBFLOW_CORE_DIR') or os.path.join(REPO_ROOT, 'PD')
sys.path.insert(0, SCRIPT_DIR)

# Post cbflow_global utils-refactor: test_suite moved from
# PD/utils/commands/test_suite/ to global/utils/commands/test_suite/.
# Add global/utils/commands/ so `from test_suite import …` resolves.
_global_cmds = os.path.join(REPO_ROOT, 'global', 'utils', 'commands')
if os.path.isdir(_global_cmds) and _global_cmds not in sys.path:
    sys.path.insert(0, _global_cmds)

from test_suite import e2e_checks, e2e_runner, fixtures, reporters, static_checks
from test_suite import integration_checks
from test_suite.results import Results

DEFAULT_FLOWS = ['SYNTH', 'FP', 'PNR', 'STA', 'LEC', 'EMIR', 'PV',
                 'ECO', 'CLP', 'POPT', 'FCFP', 'SYNTH_PNR']
DEFAULT_TIMEOUT = 300


# ── Flow selection ──────────────────────────────────────────────────────────

def _resolve_flows(args):
    """Resolve the flow list for this test run, dropping flows whose
    discipline directory isn't on disk.

    Sparse-checkout clones (cbflow-git-bootstrap pd/dft/dv) deliberately
    don't have the other disciplines' trees. A test suite that insists
    on resolving every flow would fail noisily — the handlers, node
    configs, and lsf configs are gone by design. Filter against
    is_discipline_available() so each clone only tests what it has.
    """
    if args.flow:
        requested = [args.flow.upper()]
    elif args.flows:
        requested = [f.strip().upper() for f in args.flows.split(',') if f.strip()]
    else:
        requested = list(DEFAULT_FLOWS)

    try:
        from tcl_config_parser import is_discipline_available, get_flow_discipline
    except ImportError:
        return requested

    filtered, skipped = [], []
    for ft in requested:
        try:
            disc = (get_flow_discipline(ft) or 'PD').upper()
        except Exception:
            disc = 'PD'
        if is_discipline_available(disc):
            filtered.append(ft)
        else:
            skipped.append((ft, disc))

    # Only announce when the user asked for the default set; an explicit
    # --flow / --flows gets the exact list they asked for, plus a clean
    # discipline-missing error later if that's what's going on.
    if skipped and not (args.flow or args.flows):
        import sys as _sys
        absent = sorted({d for _, d in skipped})
        print(f'[INFO] sparse checkout: skipping {len(skipped)} flow(s) '
              f'from absent discipline(s): {", ".join(absent)}',
              file=_sys.stderr)
    return filtered or requested


def _resolve_categories(args):
    if args.category is None:
        return None
    return [int(args.category)]


# Default projects that the e2e suite exercises. bumblebee's fixtures use
# the Synopsys toolchain (fc, pt, formality, …); denali's use Cadence
# (innovus, tempus, conformal, …). Both must stay green for every release.
DEFAULT_PROJECTS = ('bumblebee', 'denali')


def _resolve_projects(args):
    """Return the list of project names to iterate.

    `--projects X,Y` filters to a comma-separated set (case-sensitive,
    matched against `project(name)` in each fixture). `--projects ALL`
    iterates every project found under PD/config/project/. Default is
    DEFAULT_PROJECTS so every release covers both tool stacks."""
    raw = getattr(args, 'projects', None)
    if not raw:
        return list(DEFAULT_PROJECTS)
    if raw.upper() == 'ALL':
        from core.paths import list_available_projects
        found = list_available_projects()
        return found if found else list(DEFAULT_PROJECTS)
    return [p.strip() for p in raw.split(',') if p.strip()]


# ── Listing ─────────────────────────────────────────────────────────────────

def _do_list():
    print('Static categories (--static or default suite):')
    for n, (name, _) in sorted(static_checks.CATEGORIES.items()):
        print(f'  {n}. {name}')
    print()
    print('E2E checks (run per flow when --e2e or default suite):')
    for name, _, _ in e2e_checks.CHECKS:
        print(f'  - {name}')
    print()
    print('Default flows:')
    print(f'  {", ".join(DEFAULT_FLOWS)}')
    return 0


# ── Cleanup of stray run dirs ───────────────────────────────────────────────

def _do_cleanup(console):
    """Remove the leftover P0_run_*_test1/ directories at the repo root.
    Prompts unless --yes is set (--yes plumbed through cleanup_yes attr)."""
    candidates = sorted(Path(REPO_ROOT).glob('P0_run_*_test1'))
    candidates = [c for c in candidates if c.is_dir()]
    if not candidates:
        console.info('No stray P0_run_*_test1/ directories found at repo root.')
        return 0
    console.info(f'Found {len(candidates)} stray run directories at {REPO_ROOT}:')
    for c in candidates:
        console.info(f'  - {c.name}')
    return 0


# ── E2E orchestration ───────────────────────────────────────────────────────

def _run_e2e(results, console, flows, args):
    workarea_test = fixtures.discover_workarea_test_dir(REPO_ROOT)
    if not os.path.isdir(workarea_test):
        console.info(f'Skipping e2e — fixture dir not found: {workarea_test}')
        results.skipped('e2e', 'setup', 'fixtures', f'no workarea_test/ under {REPO_ROOT}')
        return

    # Default coverage: both projects. bumblebee exercises the Synopsys tool
    # stack (fc, pt, formality, …); denali exercises the Cadence stack
    # (innovus, tempus, conformal, …). Override with --projects "name" or
    # --projects "name1,name2" or --projects ALL.
    projects = _resolve_projects(args)
    for flow in flows:
        for project in projects:
            # Multi-mode: iterate every input-handoff variant available for
            # this (flow, project) pair. Downstream flows (STA/LEC/ECO/...)
            # typically have 2–3 fixtures each covering `direct`,
            # `from_run`, and `release_tag` — upstream flows (SYNTH/PNR/FP)
            # usually have just one (mode='direct').
            matches = fixtures.pick_fixtures(
                workarea_test, flow, vendor=args.vendor, project=project)
            if not matches:
                base_label = f'{project}/{flow}' if project else flow
                console.section(f'E2E: {base_label}')
                proj_note = f' (project={project})' if project else ''
                err = f'no fixture in {workarea_test} for flow={flow}{proj_note}'
                console.event('SKIP', f'{base_label}: prepare_sandbox', err)
                results.skipped('e2e', base_label, 'prepare_sandbox', err)
                continue

            for fixture_path, mode in matches:
                # Include the mode tag when > 1 variant so the log makes it
                # obvious which handoff is being exercised. Single-variant
                # (mode=direct) flows stay unchanged for readability.
                if len(matches) > 1:
                    label = (f'{project}/{flow}[{mode}]' if project
                             else f'{flow}[{mode}]')
                else:
                    label = f'{project}/{flow}' if project else flow
                console.section(f'E2E: {label}')

                sandbox, fixture_or_err, cwd = e2e_runner.prepare_sandbox(
                    flow, REPO_ROOT, PD_DIR, workarea_test,
                    vendor=args.vendor, project=project,
                    fixture=fixture_path)
                if sandbox is None:
                    console.event('SKIP', f'{label}: prepare_sandbox', fixture_or_err)
                    results.skipped('e2e', label, 'prepare_sandbox', fixture_or_err)
                    continue

                log_buf = []
                flow_failed = False

                # Workspace create
                try:
                    rc, dur = e2e_runner.run_workspace_create(
                        PD_DIR, cwd, fixture_or_err, args.timeout, log_buf)
                except Exception as e:
                    results.failed('e2e', label, 'workspace_create', f'{type(e).__name__}: {e}')
                    console.event('FAIL', f'{label}: workspace_create', str(e))
                    sandbox.cleanup(keep=args.keep or args.keep_on_fail)
                    continue
                if rc != 0:
                    tail = log_buf[-1][-500:] if log_buf else ''
                    results.failed('e2e', label, 'workspace_create', f'exit={rc}; tail: {tail}')
                    console.event('FAIL', f'{label}: workspace_create', f'exit={rc}')
                    sandbox.cleanup(keep=args.keep or args.keep_on_fail)
                    continue
                results.passed('e2e', label, 'workspace_create', f'{dur:.1f}s')
                console.event('PASS', f'{label}: workspace_create', f'{dur:.1f}s')

                # Run all
                try:
                    rc, dur = e2e_runner.run_all(PD_DIR, sandbox.run_dir, args.timeout, log_buf)
                except Exception as e:
                    results.failed('e2e', label, 'run_all', f'{type(e).__name__}: {e}')
                    console.event('FAIL', f'{label}: run_all', str(e))
                    flow_failed = True
                else:
                    if rc != 0:
                        tail = log_buf[-1][-500:] if log_buf else ''
                        results.failed('e2e', label, 'run_all', f'exit={rc}; tail: {tail}')
                        console.event('FAIL', f'{label}: run_all', f'exit={rc}')
                        flow_failed = True
                    else:
                        results.passed('e2e', label, 'run_all', f'{dur:.1f}s')
                        console.event('PASS', f'{label}: run_all', f'{dur:.1f}s')

                # Post-execution checks (always run — partial DBs still inform us)
                before = len(results.entries)
                e2e_checks.run_all_checks(results, label, PD_DIR, sandbox.run_dir or '')
                for entry in results.entries[before:]:
                    console.event(entry['status'], f'{label}: {entry["test"]}', entry['detail'])
                    if entry['status'] == 'FAIL':
                        flow_failed = True

                # Sandbox cleanup
                keep = args.keep or (args.keep_on_fail and flow_failed)
                if keep:
                    console.info(f'Keeping sandbox: {sandbox.tmp_dir} / {sandbox.run_dir}')
                sandbox.cleanup(keep=keep)


# ── Main ────────────────────────────────────────────────────────────────────

def main(argv=None):
    parser = argparse.ArgumentParser(
        prog='cbflow test',
        description='Run the CBflow test suite (static config checks + e2e flow execution).',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples:
  cbflow test                          # static + e2e, all 12 flows
  cbflow test --static                 # static config-validation only
  cbflow test --e2e                    # e2e only, all flows
  cbflow test --flow SYNTH_PNR         # one flow
  cbflow test --flows SYNTH,PNR,STA    # subset
  cbflow test --category 3             # one static category
  cbflow test --vendor synopsys        # prefer synopsys variant fixture
  cbflow test --timeout 600            # per-flow timeout
  cbflow test --keep                   # never clean up sandboxes
  cbflow test --report results.json    # machine-readable
  cbflow test --junit junit.xml        # CI report
  cbflow test --ci                     # CI mode: junit + non-zero exit + no colors
  cbflow test --list                   # show all categories + e2e checks
""")

    scope = parser.add_mutually_exclusive_group()
    scope.add_argument('--static', action='store_true', help='Static config checks only')
    scope.add_argument('--e2e', action='store_true', help='End-to-end execution only')
    scope.add_argument('--dispatch-smoke', dest='dispatch_smoke',
                       action='store_true',
                       help='LSF dispatch smoke: exercise submit_job with '
                            'stubbed bsub+xterm. Catches the class '
                            'test_mode=true hides.')
    scope.add_argument('--cli-smoke', dest='cli_smoke',
                       action='store_true',
                       help='CLI smoke: auto-discover every `cbflow ...` '
                            'leaf command and run it with safe args. '
                            'Catches broken --help text, missing args, '
                            'import errors in command modules.')
    scope.add_argument('--integration', dest='integration',
                       action='store_true',
                       help='Integration: real library-manager + '
                            'mmmc-manager workflows against sandbox tech. '
                            'Catches the class of bug where discovery '
                            'looks in stale paths (what cli-smoke misses '
                            'because it only tests --help).')
    parser.add_argument('--destructive', action='store_true',
                        help='In --cli-smoke, also exercise destructive '
                             'leaves (run all, release, create-branch, '
                             'etc.) — they still only get --help by default')

    parser.add_argument('--flow', help='Test a single flow')
    parser.add_argument('--flows', help='Comma-separated list of flows')
    parser.add_argument('--category', type=int, help='Run one static category (1-8)')
    parser.add_argument('--vendor', help='Prefer fixtures matching this vendor (e.g. synopsys, cadence)')
    parser.add_argument(
        '--projects',
        help='Comma-separated projects for e2e iteration. '
             'Default: bumblebee,denali (covers both Synopsys + Cadence tool '
             'stacks). Use --projects ALL to iterate every project under '
             'PD/config/project/. Use --projects bumblebee to test only one.')

    parser.add_argument('--timeout', type=int, default=DEFAULT_TIMEOUT,
                        help=f'Per-flow timeout in seconds (default {DEFAULT_TIMEOUT})')

    keep_grp = parser.add_mutually_exclusive_group()
    keep_grp.add_argument('--keep', action='store_true', help='Never delete sandboxes')
    keep_grp.add_argument('--keep-on-fail', dest='keep_on_fail', action='store_true',
                          default=True, help='Keep sandboxes only when the flow failed (default)')
    keep_grp.add_argument('--clean-on-fail', dest='keep_on_fail', action='store_false',
                          help='Always remove sandboxes even on failure')

    parser.add_argument('--report', help='Write JSON report to this path')
    parser.add_argument('--junit', help='Write JUnit XML report to this path')
    parser.add_argument('--ci', action='store_true',
                        help='CI mode: implies --junit cbflow-junit.xml, plain console, exit non-zero on failure')

    verbosity = parser.add_mutually_exclusive_group()
    verbosity.add_argument('--verbose', '-v', action='store_true', help='Show all results including PASS')
    verbosity.add_argument('--quiet', '-q', action='store_true', help='Only final summary')

    parser.add_argument('--list', dest='do_list', action='store_true', help='List categories and exit')
    parser.add_argument('--cleanup', action='store_true',
                        help='List leftover P0_run_*_test1 dirs at repo root and exit')

    args = parser.parse_args(argv)

    console = reporters.Console(verbose=args.verbose, quiet=args.quiet, color=not args.ci)

    if args.do_list:
        return _do_list()

    if args.cleanup:
        return _do_cleanup(console)

    results = Results()

    flows = _resolve_flows(args)
    run_integration = bool(getattr(args, 'integration', False))
    run_static   = (not args.e2e and not args.dispatch_smoke
                    and not args.cli_smoke and not run_integration)
    run_e2e      = (not args.static and not args.dispatch_smoke
                    and not args.cli_smoke and not run_integration)
    run_dispatch = bool(args.dispatch_smoke)
    run_cli      = bool(args.cli_smoke)

    console.section(
        f'CBflow Test Suite — flows={",".join(flows)}, '
        f'static={"on" if run_static else "off"}, e2e={"on" if run_e2e else "off"}'
    )

    if run_static:
        # Static checks target PD/config/flow and friends. In a DFT or DV
        # sparse-checkout clone, PD/ is intentionally absent — walking the
        # 16 PD-rooted categories would emit ~44 FAILs that reflect nothing
        # broken, just an absent discipline. Skip the whole run cleanly.
        pd_present = os.path.isdir(os.path.join(PD_DIR, 'config', 'flow'))
        if not pd_present:
            results.skipped('static', 'pd_absent',
                            'PD tree not in checkout — static checks are '
                            'PD-rooted; skipping all 16 categories')
            console.event('SKIP', 'static/pd_absent',
                          'PD tree not in checkout — skipping all 16 categories')
        else:
            cats = _resolve_categories(args)
            for cat_num in sorted(cats or static_checks.CATEGORIES.keys()):
                cat_name, func = static_checks.CATEGORIES.get(cat_num, (None, None))
                if not func:
                    continue
                before = len(results.entries)
                console.section(f'STATIC {cat_num}: {cat_name}')
                func(results, PD_DIR, flows)
                for entry in results.entries[before:]:
                    console.event(entry['status'], entry['test'], entry['detail'])

    if run_e2e:
        _run_e2e(results, console, flows, args)

    if run_dispatch:
        from test_suite import dispatch_smoke
        before = len(results.entries)
        console.section('DISPATCH SMOKE: launch_utils.tcl::submit_job '
                        '(stubbed bsub + xterm)')
        dispatch_smoke.run(results)
        for entry in results.entries[before:]:
            console.event(entry['status'], entry['test'], entry['detail'])

    if run_cli:
        from test_suite import cli_smoke
        before = len(results.entries)
        console.section('CLI SMOKE: every `cbflow ...` leaf, safe args')
        cli_smoke.run(results, PD_DIR, args)
        for entry in results.entries[before:]:
            console.event(entry['status'], entry['test'], entry['detail'])

    if run_integration:
        before = len(results.entries)
        integration_checks.run_all(results, console, PD_DIR)

    # Reports
    if args.report:
        reporters.write_json(args.report, results)
        console.info(f'JSON report: {args.report}')
    junit_path = args.junit or ('cbflow-junit.xml' if args.ci else None)
    if junit_path:
        reporters.write_junit(junit_path, results)
        console.info(f'JUnit report: {junit_path}')

    console.summary(results)
    return 1 if results.has_failures() else 0


if __name__ == '__main__':
    sys.exit(main())
