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
import re
import sys
import time
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PD_DIR = os.path.dirname(os.path.dirname(SCRIPT_DIR))
REPO_ROOT = os.path.dirname(PD_DIR)
sys.path.insert(0, SCRIPT_DIR)

from test_suite import e2e_checks, e2e_runner, fixtures, reporters, static_checks
from test_suite.results import Results

DEFAULT_FLOWS = ['SYNTH', 'FP', 'PNR', 'STA', 'LEC', 'EMIR', 'PV',
                 'ECO', 'CLP', 'POPT', 'FCFP', 'SYNTH_PNR']
DEFAULT_TIMEOUT = 300


# ── Flow selection ──────────────────────────────────────────────────────────

def _resolve_flows(args):
    if args.flow:
        return [args.flow.upper()]
    if args.flows:
        return [f.strip().upper() for f in args.flows.split(',') if f.strip()]
    return list(DEFAULT_FLOWS)


def _resolve_categories(args):
    if args.category is None:
        return None
    return [int(args.category)]


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

    for flow in flows:
        console.section(f'E2E: {flow}')

        sandbox, fixture_or_err, cwd = e2e_runner.prepare_sandbox(
            flow, REPO_ROOT, PD_DIR, workarea_test, vendor=args.vendor)
        if sandbox is None:
            console.event('SKIP', f'{flow}: prepare_sandbox', fixture_or_err)
            results.skipped('e2e', flow, 'prepare_sandbox', fixture_or_err)
            continue

        log_buf = []
        flow_failed = False

        # Workspace create
        try:
            rc, dur = e2e_runner.run_workspace_create(
                PD_DIR, cwd, fixture_or_err, args.timeout, log_buf)
        except Exception as e:
            results.failed('e2e', flow, 'workspace_create', f'{type(e).__name__}: {e}')
            console.event('FAIL', f'{flow}: workspace_create', str(e))
            sandbox.cleanup(keep=args.keep or args.keep_on_fail)
            continue
        if rc != 0:
            tail = log_buf[-1][-500:] if log_buf else ''
            results.failed('e2e', flow, 'workspace_create', f'exit={rc}; tail: {tail}')
            console.event('FAIL', f'{flow}: workspace_create', f'exit={rc}')
            sandbox.cleanup(keep=args.keep or args.keep_on_fail)
            continue
        results.passed('e2e', flow, 'workspace_create', f'{dur:.1f}s')
        console.event('PASS', f'{flow}: workspace_create', f'{dur:.1f}s')

        # Run all
        try:
            rc, dur = e2e_runner.run_all(PD_DIR, sandbox.run_dir, args.timeout, log_buf)
        except Exception as e:
            results.failed('e2e', flow, 'run_all', f'{type(e).__name__}: {e}')
            console.event('FAIL', f'{flow}: run_all', str(e))
            flow_failed = True
        else:
            if rc != 0:
                tail = log_buf[-1][-500:] if log_buf else ''
                results.failed('e2e', flow, 'run_all', f'exit={rc}; tail: {tail}')
                console.event('FAIL', f'{flow}: run_all', f'exit={rc}')
                flow_failed = True
            else:
                results.passed('e2e', flow, 'run_all', f'{dur:.1f}s')
                console.event('PASS', f'{flow}: run_all', f'{dur:.1f}s')

        # Post-execution checks (always run — partial DBs still inform us)
        before = len(results.entries)
        e2e_checks.run_all_checks(results, flow, PD_DIR, sandbox.run_dir or '')
        for entry in results.entries[before:]:
            console.event(entry['status'], f'{flow}: {entry["test"]}', entry['detail'])
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

    parser.add_argument('--flow', help='Test a single flow')
    parser.add_argument('--flows', help='Comma-separated list of flows')
    parser.add_argument('--category', type=int, help='Run one static category (1-8)')
    parser.add_argument('--vendor', help='Prefer fixtures matching this vendor (e.g. synopsys, cadence)')

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
    run_static = not args.e2e
    run_e2e = not args.static

    console.section(
        f'CBflow Test Suite — flows={",".join(flows)}, '
        f'static={"on" if run_static else "off"}, e2e={"on" if run_e2e else "off"}'
    )

    if run_static:
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
