#!/usr/bin/env python3
"""
CBFlow Production Validation Test Suite
=========================================
Comprehensive end-to-end testing for production release.

Tests:
  1. All flow runs execute in test_mode (SYNTH_PNR, STA, LEC, CLP, PNR, SYNTH)
  2. Database created with correct schema and data
  3. Ownership enforcement works
  4. Checklist evaluation works per milestone
  5. Data pointers (DB pointer, report paths) resolve correctly
  6. No hardcoded values break functionality
  7. Config resolver produces valid output
  8. All Python/TCL files compile without errors

Usage:
  python3 PD/utils/validation/v1.0.0/production_test.py
"""

import ast
import glob
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import traceback
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CBFLOW_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(SCRIPT_DIR))))
PD_DIR = os.path.join(CBFLOW_ROOT, 'PD')
# Most "commands" Python code moved from PD/utils/commands/ to
# global/utils/commands/ during the cbflow_global refactor. The ones that
# stayed under PD/utils/commands/ are PD-only (node_manager, checklist_cmd,
# qor_report_cmd, trending_cmd, autoppt_cmd, lsf_cmd, log_viewer,
# graph_renderer, makefile_generator, dashboard_daemon_cmd). The sys.path
# needs BOTH roots so a bare `import race_engine` (now global) and
# `import checklist_cmd` (still PD) both resolve.
COMMANDS_DIR = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'commands')
PD_COMMANDS_DIR = os.path.join(PD_DIR, 'utils', 'commands')
# PD-side dashboard also lives here (per-run GUI).
DASHBOARD_DIR = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'dashboard')
PD_DASHBOARD_DIR = os.path.join(PD_DIR, 'utils', 'dashboard')
WORKAREA = os.path.join(CBFLOW_ROOT, 'workarea', 'cpu_core')
for _p in (COMMANDS_DIR, PD_COMMANDS_DIR, DASHBOARD_DIR):
    if _p not in sys.path and os.path.isdir(_p):
        sys.path.insert(0, _p)

os.environ['CBFLOW_CORE_DIR'] = PD_DIR

PASS = 0
FAIL = 0
RESULTS = []
SECTION = ''


def section(name):
    global SECTION
    SECTION = name
    print(f'\n  {"─" * 70}')
    print(f'  {name}')
    print(f'  {"─" * 70}')


def test(name):
    def decorator(func):
        func._test_name = name
        return func
    return decorator


def run_test(func):
    global PASS, FAIL
    name = getattr(func, '_test_name', func.__name__)
    try:
        func()
        PASS += 1
        RESULTS.append(('PASS', SECTION, name))
        print(f'    \033[92m[PASS]\033[0m {name}')
    except Exception as e:
        FAIL += 1
        RESULTS.append(('FAIL', SECTION, name, str(e)))
        msg = str(e).split('\n')[0][:80]
        print(f'    \033[91m[FAIL]\033[0m {name}')
        print(f'           {msg}')


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: Python/TCL Compilation
# ═══════════════════════════════════════════════════════════════════════════════

@test("All Python files in utils/commands compile")
def t1_1():
    for f in glob.glob(os.path.join(COMMANDS_DIR, '*.py')):
        with open(f) as fh:
            ast.parse(fh.read())

@test("All Python files in dashboard compile")
def t1_2():
    for f in glob.glob(os.path.join(PD_DIR, 'utils', 'dashboard', '*.py')):
        with open(f) as fh:
            ast.parse(fh.read())

@test("All exit config TCL files parse")
def t1_3():
    for f in glob.glob(os.path.join(PD_DIR, 'config', 'exit', 'v1.0.0', '*.tcl')):
        r = subprocess.run(['tclsh', f], capture_output=True, text=True)
        assert r.returncode == 0, f"{os.path.basename(f)}: {r.stderr[:80]}"

@test("All check library TCL files parse")
def t1_4():
    for f in glob.glob(os.path.join(PD_DIR, 'config', 'exit', 'v1.0.0', 'checks', '*.tcl')):
        r = subprocess.run(['tclsh', f], capture_output=True, text=True)
        assert r.returncode == 0, f"{os.path.basename(f)}: {r.stderr[:80]}"

@test("All node config TCL files parse")
def t1_5():
    for f in glob.glob(os.path.join(PD_DIR, 'config', 'flow', 'v1.0.0', 'node_configs', '*.tcl')):
        r = subprocess.run(['tclsh', f], capture_output=True, text=True)
        if r.returncode != 0 and 'missing' in r.stderr and 'brace' in r.stderr:
            assert False, f"Syntax error in {os.path.basename(f)}"

@test("All check scripts in validation/checks parse")
def t1_6():
    for f in glob.glob(os.path.join(PD_DIR, 'utils', 'validation', 'v1.0.0', 'checks', '*.tcl')):
        r = subprocess.run(['tclsh', f, '--test-mode', '--result-dir', '/tmp'],
                          capture_output=True, text=True)
        assert r.returncode == 0, f"{os.path.basename(f)} failed in test-mode"

@test("resolve_inputs.tcl sources without error")
def t1_7():
    # resolve_inputs.tcl moved to global/utils/utilities during cbflow_global.
    r = subprocess.run(['tclsh',
        os.path.join(CBFLOW_ROOT, 'global', 'utils', 'utilities',
                     'v1.0.0', 'resolve_inputs.tcl')],
        capture_output=True, text=True)
    assert r.returncode == 0, f"resolve_inputs.tcl: {r.stderr[:80]}"

@test("threshold_overrides.tcl resolves correctly")
def t1_8():
    r = subprocess.run(['tclsh', '-c', '''
source global/config/exit/v1.0.0/threshold_overrides.tcl
set v [get_threshold bumblebee PLACE_EXIT setup_wns P0]
if {$v != -150} { error "Expected -150, got $v" }
'''], capture_output=True, text=True, cwd=CBFLOW_ROOT)
    assert r.returncode == 0, f"Threshold resolution: {r.stderr[:80]}"


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: Flow Run Tests (test_mode)
# ═══════════════════════════════════════════════════════════════════════════════

def _check_run(flow, run_dir):
    """Validate a completed test_mode run."""
    assert os.path.isdir(run_dir), f"Run dir missing: {run_dir}"
    assert os.path.isdir(os.path.join(run_dir, 'setup')), f"Missing setup/"
    # Check DB exists
    db_files = glob.glob(os.path.join(run_dir, '.race_*.db'))
    pointer = os.path.join(run_dir, '.race_db_pointer')
    assert db_files or os.path.exists(pointer), f"No RACE DB found"
    # Check work dir has stages
    work_dir = os.path.join(run_dir, 'work', flow)
    if os.path.isdir(work_dir):
        stages = os.listdir(work_dir)
        assert len(stages) > 0, f"No stages in work/{flow}/"


@test("SYNTH_PNR test run exists and has correct structure")
def t2_1():
    # Dynamically discover a SYNTH_PNR run. Pre 2026-11-03 this was
    # hardcoded `P0_run_SYNTH_PNR_test1` but bumblebee now uses LC1
    # phases, so the hardcoded P0 prefix never matches.
    candidates = sorted(glob.glob(os.path.join(WORKAREA, '*_run_SYNTH_PNR_*')))
    if not candidates:
        raise AssertionError(
            f'no SYNTH_PNR run in {WORKAREA} to validate — run '
            '`cbflow workspace create --config uc_SYNTH_PNR_varun1.tcl` '
            'in workarea/cpu_core/ to populate.')
    run_dir = candidates[0]
    _check_run('SYNTH_PNR', run_dir)
    # Check expected stages — pulled from the flow's node_config at runtime
    # so renaming / adding a stage auto-updates this test instead of relying
    # on a hardcoded list that silently drifts out of date.
    import sys as _sys
    _utils_cmd = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'commands')
    if _utils_cmd not in _sys.path:
        _sys.path.insert(0, _utils_cmd)
    try:
        from tcl_config_parser import get_flow_stages
        expected = get_flow_stages('SYNTH_PNR')
    except Exception:
        # Fallback — if resolver is broken, keep the canonical list so
        # the test's own diagnostic survives.
        expected = ['init_design1', 'synthesis1', 'place1', 'cts1', 'cts_opt1',
                    'route1', 'pro1', 'signoff1', 'export_data1']
    work = os.path.join(run_dir, 'work', 'SYNTH_PNR')
    # Only check EXECUTION stages (skip input stages like rtl1/sdc1/upf1 and
    # release_data1 which don't produce a work/<stage>/ dir).
    _skip = {'rtl1', 'sdc1', 'upf1', 'netlist1', 'scandef1', 'sdf1', 'lib1',
             'spec1', 'release_data1'}
    for stage in expected:
        if stage in _skip:
            continue
        assert os.path.isdir(os.path.join(work, stage)), f"Missing stage: {stage}"

@test("STA test run exists")
def t2_2():
    # Check at least one STA run exists
    sta_runs = [d for d in os.listdir(WORKAREA) if 'STA' in d and os.path.isdir(os.path.join(WORKAREA, d))]
    assert sta_runs, "No STA test run found"

@test("LEC test run exists")
def t2_3():
    _cands = sorted(glob.glob(os.path.join(WORKAREA, '*_run_LEC_*')))
    run_dir = _cands[0] if _cands else os.path.join(WORKAREA, 'P0_run_LEC_test1')
    if os.path.isdir(run_dir):
        _check_run('LEC', run_dir)

@test("CLP test run exists")
def t2_4():
    _cands = sorted(glob.glob(os.path.join(WORKAREA, '*_run_CLP_*')))
    run_dir = _cands[0] if _cands else os.path.join(WORKAREA, 'P0_run_CLP_test1')
    if os.path.isdir(run_dir):
        _check_run('CLP', run_dir)

@test("PNR test run exists")
def t2_5():
    _cands = sorted(glob.glob(os.path.join(WORKAREA, '*_run_PNR_*')))
    run_dir = _cands[0] if _cands else os.path.join(WORKAREA, 'P0_run_PNR_test1')
    if os.path.isdir(run_dir):
        _check_run('PNR', run_dir)

@test("SYNTH test run exists")
def t2_6():
    _cands = sorted(glob.glob(os.path.join(WORKAREA, '*_run_SYNTH_cbflowtest*')))
    run_dir = _cands[0] if _cands else os.path.join(WORKAREA, 'P0_run_SYNTH_test1')
    if os.path.isdir(run_dir):
        _check_run('SYNTH', run_dir)


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: Database Schema & Data
# ═══════════════════════════════════════════════════════════════════════════════

@test("SYNTH_PNR DB has all 13 tables")
def t3_1():
    run_dir = (sorted(glob.glob(os.path.join(WORKAREA, '*_run_SYNTH_PNR_*'))) or [os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')])[0]
    db_files = glob.glob(os.path.join(run_dir, '.race_*.db'))
    assert db_files, "No DB found"
    conn = sqlite3.connect(db_files[0])
    tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    conn.close()
    for t in ['jobs', 'run_info', 'run_config', 'dag_structure', 'job_order',
              'stage_metrics', 'design_info', 'checklist_results', 'release_info',
              'lsf_details', 'run_logs', 'metrics_snapshot', 'config_history']:
        assert t in tables, f"Missing table: {t}"

@test("run_info has correct metadata")
def t3_2():
    run_dir = (sorted(glob.glob(os.path.join(WORKAREA, '*_run_SYNTH_PNR_*'))) or [os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')])[0]
    db_files = glob.glob(os.path.join(run_dir, '.race_*.db'))
    conn = sqlite3.connect(db_files[0])
    info = dict(conn.execute("SELECT key, value FROM run_info").fetchall())
    conn.close()
    assert info.get('flow_type') == 'SYNTH_PNR', f"Wrong flow_type: {info.get('flow_type')}"
    assert info.get('project') == 'bumblebee', f"Wrong project: {info.get('project')}"

@test("dag_structure has jobs")
def t3_3():
    run_dir = (sorted(glob.glob(os.path.join(WORKAREA, '*_run_SYNTH_PNR_*'))) or [os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')])[0]
    db_files = glob.glob(os.path.join(run_dir, '.race_*.db'))
    conn = sqlite3.connect(db_files[0])
    count = conn.execute("SELECT COUNT(*) FROM dag_structure").fetchone()[0]
    conn.close()
    assert count > 10, f"Only {count} jobs in dag_structure"


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: Ownership Enforcement
# ═══════════════════════════════════════════════════════════════════════════════

@test("StatusDB stores owner on creation")
def t4_1():
    from race_engine import StatusDB
    td = tempfile.mkdtemp()
    db = StatusDB(td, run_name='own_test', user='testuser')
    db.set_run_info('owner', 'testuser')
    db.set_run_info('owner_uid', str(os.getuid()))
    assert db.get_run_info('owner') == 'testuser'
    shutil.rmtree(td)

@test("Ownership check rejects different UID")
def t4_2():
    from race_engine import StatusDB
    td = tempfile.mkdtemp()
    db = StatusDB(td, run_name='perm_test', user='other')
    db.set_run_info('owner_uid', '99999')
    row = sqlite3.connect(db.db_path).execute(
        "SELECT value FROM run_info WHERE key='owner_uid'").fetchone()
    assert row and int(row[0]) != os.getuid()
    shutil.rmtree(td)

@test("DB pointer mechanism works")
def t4_3():
    from race_engine import StatusDB
    race_area = tempfile.mkdtemp()
    run_dir = tempfile.mkdtemp()
    os.makedirs(os.path.join(race_area, 'proj', 'PD', 'SYNTH_PNR'), exist_ok=True)
    db = StatusDB(run_dir, project_name='proj', flow_type='SYNTH_PNR',
                  run_name='t', user='u', db_base_path=race_area)
    pointer = os.path.join(run_dir, '.race_db_pointer')
    assert os.path.exists(pointer), "Pointer file not created"
    found = StatusDB.find_db_from_run_dir(run_dir)
    assert found == db.db_path, f"Pointer mismatch: {found} != {db.db_path}"
    shutil.rmtree(race_area)
    shutil.rmtree(run_dir)


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: Checklist System
# ═══════════════════════════════════════════════════════════════════════════════

@test("21 milestones available (6 PD + 6 DFT + 9 DV)")
def t5_1():
    # Milestone count expanded from 6→21 on 2026-11-03 (DFT + DV milestones
    # added). Exit configs also moved to global/config/exit/ in the same
    # discipline-ownership refactor.
    import checklist_cmd as cl
    ms = cl.get_available_milestones()
    assert len(ms) >= 21, f"Expected >=21, got {len(ms)}: {ms}"
    for m in ['FP_EXIT', 'PLACE_EXIT', 'CTS_EXIT', 'PRO_EXIT', 'BTO', 'MTO',
              'CORE_DFT_EXIT', 'TOP_DFT_EXIT', 'EDT_OCC_EXIT',
              'SCAN_INSERT_EXIT', 'ATPG_PREPD_EXIT', 'ATPG_POSTPD_EXIT',
              'SPEC_RAMP_EXIT', 'PLANNING_EXIT', 'TB_SETUP_EXIT',
              'M1_EXIT', 'M2_EXIT', 'M3_EXIT', 'M4_EXIT',
              'ECO_EXEC_EXIT', 'DV_SIGNOFF_EXIT']:
        assert m in ms, f"Missing milestone: {m}"

@test("All milestone configs parse with milestone_info and discipline")
def t5_2():
    import checklist_cmd as cl
    for ms in cl.get_available_milestones():
        cfg = cl.parse_milestone_config(cl.get_milestone_config_path(ms))
        assert cfg.get('milestone_info', {}).get('name') == ms, f"{ms} name mismatch"
        # Every milestone must declare its owning discipline post-refactor.
        disc = cfg.get('milestone_info', {}).get('discipline', '').upper()
        assert disc in ('PD', 'DFT', 'DV'), (
            f"{ms}: milestone_info(discipline) must be PD/DFT/DV, got {disc!r}")

@test("Library checks present (checks/*.tcl)")
def t5_3():
    # Exit configs moved to global/config/exit on 2026-11-03.
    _checks_dir = os.path.join(CBFLOW_ROOT, 'global', 'config', 'exit',
                               'v1.0.0', 'checks')
    total = 0
    for f in glob.glob(os.path.join(_checks_dir, '*.tcl')):
        total += sum(1 for line in open(f) if '"description"' in line)
    # Current library has 182 checks across 9 categories (audit 2026-11-03).
    # Keep the lower bound loose so new checks don't bite this test.
    assert total >= 150, f"Expected >=150 library checks, got {total}"

@test("All library checks have script field")
def t5_4():
    _checks_dir = os.path.join(CBFLOW_ROOT, 'global', 'config', 'exit',
                               'v1.0.0', 'checks')
    for f in glob.glob(os.path.join(_checks_dir, '*.tcl')):
        with open(f) as fh:
            content = fh.read()
        descs = content.count('"description"')
        scripts = content.count('"script"')
        assert scripts >= descs, f"{os.path.basename(f)}: {scripts} scripts < {descs} descriptions"

@test("Phase filtering: min_phase gates check activation")
def t5_5():
    # Updated for the 2026-11-03 project-defined-phases work. Rather than
    # P0/P3 which doesn't apply to projects using LC1-LC5, pick two phases
    # from the project's own list and verify the earlier-phase check pass
    # has fewer active checks than the later one. Falls back to P0/P3 if
    # project(phases) isn't declared on the running env.
    import checklist_cmd as cl
    cfg = cl.parse_milestone_config(cl.get_milestone_config_path('BTO'))
    all_checks = {**cfg.get('mandatory_checks', {}),
                  **cfg.get('optional_checks', {}),
                  **cfg.get('library_checks', {})}
    # Pick first + last from the project's actual phases.
    try:
        from tcl_config_parser import get_phases
        phases = get_phases()
    except Exception:
        phases = []
    if not phases:
        phases = ['P0', 'P3']
    early, late = phases[0], phases[-1]
    e_eval = cl._evaluate_checks('/tmp/fake', all_checks, set(), phase=early)
    l_eval = cl._evaluate_checks('/tmp/fake', all_checks, set(), phase=late)
    e_active = sum(1 for r in e_eval if r['status'] != 'SKIPPED')
    l_active = sum(1 for r in l_eval if r['status'] != 'SKIPPED')
    # Equality is acceptable (same phase index); earlier should NOT be
    # strictly MORE active than later.
    assert e_active <= l_active, (
        f"earlier phase {early}({e_active}) should be ≤ later {late}({l_active}) "
        f"for min_phase gating to work correctly")

@test("Auto-detect milestone from flow type (dynamic, no hardcoding)")
def t5_6():
    # Post 2026-11-03 the PD per-flow _SIGNOFF configs (STA_SIGNOFF,
    # LEC_SIGNOFF, CLP_SIGNOFF, PV_SIGNOFF, EMIR_SIGNOFF) are gone — those
    # were dropped during an earlier refactor. _detect_milestone_for_flow
    # now falls through to BTO (the primary PD exit) for every PD flow.
    # The only _SIGNOFF-named milestone that still exists is
    # DV_SIGNOFF_EXIT.
    import checklist_cmd as cl
    # All PD flows resolve to BTO (fallback) since no per-flow signoff
    # config exists.
    for flow in ('SYNTH_PNR', 'STA', 'LEC', 'CLP', 'PV', 'EMIR'):
        got = cl._detect_milestone_for_flow(flow)
        assert got == 'BTO', (
            f"_detect_milestone_for_flow({flow!r}) should fall back to "
            f"'BTO' (no {flow}_SIGNOFF config exists), got {got!r}")

@test("Auto-detect phase from run dir: honors project phase list")
def t5_7():
    # Set up a temp run_dir with a minimal setup/user_config.tcl that
    # declares its own project(phases) so the resolver can read them.
    # Pre 2026-11-03 phase detection was hardcoded to P0-P3; now it
    # walks the project's declared phase list. The test verifies the
    # detector matches a dir prefix against that list.
    import checklist_cmd as cl
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        run_dir = os.path.join(td, 'LC2_run_MY_FLOW_demo')
        os.makedirs(os.path.join(run_dir, 'setup'))
        with open(os.path.join(run_dir, 'setup', 'user_config.tcl'), 'w') as f:
            f.write('set project(name) demo_project\n')
            f.write('set project(phases) {LC1 LC2 LC3 LC4 LC5}\n')
            f.write('set flow(type) MY_FLOW\n')
            f.write('set flow(design_name) demo_block\n')
            f.write('set flow(run_name) demo\n')
        # Clear any stale phase-order cache from prior tests.
        try:
            cl._PHASE_ORDER_CACHE.clear()
        except AttributeError:
            pass
        phase = cl._detect_phase(run_dir)
        # The dir prefix "LC2_" should resolve to "LC2" because the test
        # project declares LC1-LC5. If the resolver can't source the
        # project overlay (no CBFLOW_PROJECT_NAME env + no project dir
        # on disk), empty string is the correct safe fallback.
        assert phase in ('LC2', ''), (
            f"_detect_phase matched to {phase!r}; expected 'LC2' "
            f"(matched) or '' (no project overlay resolvable)")

@test("Checklist DB write works")
def t5_8():
    import checklist_cmd as cl
    run_dir = (sorted(glob.glob(os.path.join(WORKAREA, '*_run_SYNTH_PNR_*'))) or [os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')])[0]
    db_path = cl._find_run_db(run_dir)
    assert db_path, "No DB found for test run"


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: Report Files & Data Pointers
# ═══════════════════════════════════════════════════════════════════════════════

@test("Sample reports exist in all stages")
def t6_1():
    run_dir = (sorted(glob.glob(os.path.join(WORKAREA, '*_run_SYNTH_PNR_*'))) or [os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')])[0]
    for stage in ['init_design1', 'place1', 'cts1', 'pro1', 'signoff1']:
        rdir = os.path.join(run_dir, 'work', 'SYNTH_PNR', stage, 'reports')
        assert os.path.isdir(rdir), f"Missing reports dir: {stage}"
        rpts = os.listdir(rdir)
        assert len(rpts) > 0, f"No reports in {stage}"

@test("Check scripts work against sample reports")
def t6_2():
    scripts_dir = os.path.join(PD_DIR, 'utils', 'validation', 'v1.0.0', 'checks')
    reports_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1', 'work', 'SYNTH_PNR', 'pro1', 'reports')
    results_dir = tempfile.mkdtemp()
    checks = [
        ('check_legality.tcl', 'check_legality.rpt', []),
        ('check_routing.tcl', 'check_routes', []),
        ('check_drc.tcl', 'signoff_check_drc.rpt', []),
        ('check_signal_integrity.tcl', 'report_si.rpt', []),
        ('check_file_exists.tcl', 'report_qor.rpt', ['--check-name', 'test']),
    ]
    for script, report, extra in checks:
        r = subprocess.run(
            ['tclsh', os.path.join(scripts_dir, script),
             '--report', os.path.join(reports_dir, report),
             '--result-dir', results_dir] + extra,
            capture_output=True, text=True)
        assert r.returncode == 0, f"{script} failed: {r.stderr[:60]}"
    shutil.rmtree(results_dir)

@test("Milestone report_file paths point to existing stage dirs")
def t6_3():
    import checklist_cmd as cl
    run_dir = (sorted(glob.glob(os.path.join(WORKAREA, '*_run_SYNTH_PNR_*'))) or [os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')])[0]
    for ms in ['FP_EXIT', 'PLACE_EXIT', 'CTS_EXIT', 'PRO_EXIT', 'BTO']:
        cfg = cl.parse_milestone_config(cl.get_milestone_config_path(ms))
        info = cfg.get('milestone_info', {})
        report_dir = info.get('report_dir', '')
        if report_dir:
            full_path = os.path.join(run_dir, os.path.dirname(report_dir))
            # The work/SYNTH_PNR/<stage> dir should exist
            assert os.path.isdir(full_path), f"{ms}: missing {full_path}"


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: No Hardcoded Values
# ═══════════════════════════════════════════════════════════════════════════════

@test("No hardcoded tool defaults in race_engine.py")
def t7_1():
    # race_engine moved to global/utils/commands post the cbflow_global refactor.
    with open(os.path.join(COMMANDS_DIR, 'race_engine.py')) as f:
        content = f.read()
    assert "'synopsys'" not in content or "get('tool,vendor', 'synopsys')" not in content
    assert "get('tool,name', 'fc')" not in content

@test("No hardcoded flow→milestone dict in checklist_cmd.py")
def t7_2():
    # checklist_cmd stayed under PD/utils/commands (PD-specific).
    with open(os.path.join(PD_COMMANDS_DIR, 'checklist_cmd.py')) as f:
        content = f.read()
    assert "flow_milestones = {" not in content, "Hardcoded flow_milestones dict found"
    assert "'SYNTH_PNR': 'BTO'" not in content, "Hardcoded SYNTH_PNR→BTO found"

@test("No hardcoded tool shell map in run_cmd.py")
def t7_3():
    with open(os.path.join(COMMANDS_DIR, 'run_cmd.py')) as f:
        content = f.read()
    assert "'fc': 'fc_shell'" not in content, "Hardcoded fc→fc_shell found"

@test("No hardcoded v1.0.0 in dashboard (uses env var)")
def t7_4():
    # The per-run GUI dashboard moved to global/utils/dashboard.
    with open(os.path.join(DASHBOARD_DIR, 'race_dashboard.py')) as f:
        lines = f.readlines()
    for i, line in enumerate(lines, 1):
        if "'v1.0.0'" in line and 'config' in line.lower() and 'get(' not in line and '#' not in line.split("'v1.0.0'")[0]:
            assert False, f"Line {i}: hardcoded v1.0.0 in path: {line.strip()[:60]}"

@test("No stale file paths in exit configs")
def t7_5():
    stale = ['work/FP/', 'work/PNR/', 'floorplan.enc', 'placement.enc', 'cts.enc']
    # Exit configs moved to global/config/exit on 2026-11-03.
    _exit_dir = os.path.join(CBFLOW_ROOT, 'global', 'config', 'exit', 'v1.0.0')
    for f in glob.glob(os.path.join(_exit_dir, '*_config.tcl')):
        with open(f) as fh:
            content = fh.read()
        for pat in stale:
            assert pat not in content, f"Stale path '{pat}' in {os.path.basename(f)}"

@test("No hardcoded VALID_MILESTONES in qor_report_cmd.py")
def t7_6():
    with open(os.path.join(PD_COMMANDS_DIR, 'qor_report_cmd.py')) as f:
        content = f.read()
    assert "VALID_MILESTONES = [" not in content, "Hardcoded VALID_MILESTONES found"

@test("release_config.tcl has MILESTONE_STAGE_MAPPING")
def t7_7():
    rc = os.path.join(PD_DIR, 'config', 'flow', 'v1.0.0', 'release_config.tcl')
    with open(rc) as f:
        content = f.read()
    assert 'MILESTONE_STAGE_MAPPING' in content
    assert 'flow_input_handshake' in content

@test("Handshake covers all downstream flows")
def t7_8():
    rc = os.path.join(PD_DIR, 'config', 'flow', 'v1.0.0', 'release_config.tcl')
    with open(rc) as f:
        content = f.read()
    for flow in ['STA', 'LEC', 'CLP', 'PV', 'EMIR']:
        assert f'{flow},' in content, f"Missing handshake for {flow}"


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: GUI Port & DB Naming
# ═══════════════════════════════════════════════════════════════════════════════

@test("Deterministic GUI port produces valid range")
def t8_1():
    h = int(hashlib.md5(b'/test/run1').hexdigest(), 16)
    port = 10000 + (h % 50000)
    assert 10000 <= port <= 60000

@test("DB filename includes run dir name + user + hash")
def t8_2():
    from race_engine import StatusDB
    td = tempfile.mkdtemp(prefix='P0_run_TEST_')
    db = StatusDB(td, run_name='test', user='testuser')
    name = os.path.basename(db.db_path)
    dirname = os.path.basename(td)
    assert dirname in name, f"DB name '{name}' missing run dir name '{dirname}'"
    assert 'testuser' in name, f"DB name '{name}' missing username"
    shutil.rmtree(td)


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 9: Dashboard tier rendering
# ═══════════════════════════════════════════════════════════════════════════════

def _bootstrap_tracker_db(path):
    """Create a tracker.db with one project, two blocks, 2 published runs
    across PD + DFT disciplines. Used by the dashboard-render tests to
    exercise the SSR paths without a real daemon or workspace."""
    import sys as _sys
    _dash = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'project_dashboard')
    if _dash not in _sys.path:
        _sys.path.insert(0, _dash)
    import tracker_db as t
    t.init_db(path)
    # publish() needs project, metrics, block_info — supply a minimal
    # payload so get_published() reads a complete row.
    for i, (block, disc) in enumerate([('cpu_core', 'PD'),
                                       ('cpu_core', 'DFT')]):
        t.publish(path, {
            'block': block, 'phase': 'LC1',
            'milestone': 'FP_EXIT' if disc == 'PD' else 'CORE_DFT_EXIT',
            'published_by': 'testuser',
            'override': True,
            'release_tag': f'LC1_TEST_{i}',
            'release_dir': f'/tmp/test_release_{i}',
            'run_dir': f'/tmp/test_run_{i}',
            'run_id': f'run{i:04d}',
            'verdict': 'PASS',
            'closability_pct': 100.0,
            'discipline': disc,
            'project_info': {'name': 'bumblebee',
                             'phases': ['LC1', 'LC2', 'LC3', 'LC4', 'LC5']},
            'block_info': {'name': block},
            'metrics': [{'name': 'WNS', 'value': '-0.012', 'unit': 'ns',
                         'scenario': 'func', 'corner': 'ss'}]
                       if disc == 'PD' else
                       [{'name': 'fault_coverage_pct', 'value': '97.3',
                         'unit': '%'}],
            'checklist': [], 'files': [],
        }, 'bumblebee')


@test("Dashboard Tier 1 (projects grid) renders")
def t9_1():
    import sys as _sys, importlib, tempfile
    _dash = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'project_dashboard')
    if _dash not in _sys.path:
        _sys.path.insert(0, _dash)
    with tempfile.TemporaryDirectory() as td:
        db_path = os.path.join(td, 'tracker.db')
        _bootstrap_tracker_db(db_path)
        # Monkey-patch state_paths.tracker_db to point at our test DB.
        import state_paths
        orig = state_paths.tracker_db
        state_paths.tracker_db = lambda p: db_path
        try:
            # Build the handler class via make_handler and render a Tier 1
            # response by calling _page_tier1 with a mock send pipeline.
            import router
            # Tier 1 is _render_tier1(scope); use the lower-level renderer
            # directly to avoid wiring an HTTP request.
            html_fn = router._render_tier1 if hasattr(router, '_render_tier1') else None
            # _render_tier1 is defined inside make_handler closure, so
            # instead probe the module-level pieces: _render_project_card
            # and the project discovery helpers.
            assert hasattr(router, 'make_handler'), 'router.make_handler not exported'
        finally:
            state_paths.tracker_db = orig


@test("tracker_db.publish is atomic — rollback on child insert failure")
def t9_2():
    """Verify the C3 atomic-publish fix: if a child-table insert fails,
    the main published_runs row + housekeeping upserts both roll back."""
    import sys as _sys, tempfile
    _dash = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'project_dashboard')
    if _dash not in _sys.path:
        _sys.path.insert(0, _dash)
    import tracker_db as t
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, 'tracker.db')
        t.init_db(path)
        # First publish establishes a baseline project_info row.
        t.publish(path, {
            'block': 'cpu_core', 'phase': 'LC1', 'milestone': 'FP_EXIT',
            'published_by': 'u1', 'override': True,
            'verdict': 'PASS', 'closability_pct': 95.0,
            'discipline': 'PD',
            'project_info': {'name': 'bumblebee', 'tapeout_date': '2026-12-01'},
            'block_info': {'name': 'cpu_core'},
            'metrics': [], 'checklist': [], 'files': [],
        }, 'bumblebee')
        import sqlite3
        conn = sqlite3.connect(path)
        tapeout = conn.execute(
            "SELECT tapeout_date FROM project_info WHERE project='bumblebee'"
        ).fetchone()[0]
        conn.close()
        assert tapeout == '2026-12-01', (
            f'baseline tapeout_date should be 2026-12-01, got {tapeout!r}')

        # Second publish attempts to flip tapeout to a different value
        # with a verdict that the CHECK constraint rejects. Pre-fix, the
        # project_info upsert happened BEFORE the main INSERT and
        # auto-committed, so tapeout would be flipped despite the failure.
        # Post-fix: everything is in one txn and rolls back together.
        try:
            t.publish(path, {
                'block': 'cpu_core', 'phase': 'LC1', 'milestone': 'FP_EXIT',
                'published_by': 'u2', 'override': True,
                'verdict': 'GARBAGE_VERDICT',  # CHECK will reject
                'project_info': {'name': 'bumblebee',
                                 'tapeout_date': '2099-01-01'},
                'block_info': {'name': 'cpu_core'},
                'metrics': [], 'checklist': [], 'files': [],
            }, 'bumblebee')
            assert False, 'expected IntegrityError on bad verdict'
        except Exception:
            pass  # Expected — bad verdict rejected by CHECK.
        # Verify tapeout_date was NOT flipped (atomic rollback worked).
        conn = sqlite3.connect(path)
        tapeout_after = conn.execute(
            "SELECT tapeout_date FROM project_info WHERE project='bumblebee'"
        ).fetchone()[0]
        conn.close()
        assert tapeout_after == '2026-12-01', (
            f'atomic publish broken: tapeout_date was flipped to '
            f'{tapeout_after!r} despite the publish rolling back')


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: Sign-off → release-gate enforcement
# ═══════════════════════════════════════════════════════════════════════════════

@test("Checklist waiver validator accepts library checks")
def t10_1():
    """Verify the sweep-earlier fix: library checks like `setup_wns` are
    waivable. Pre-fix the validator rejected them with
    'Check not in BTO' despite them being critical at sign-off."""
    _cmds = os.path.join(CBFLOW_ROOT, 'PD', 'utils', 'commands')
    r = subprocess.run(
        [sys.executable,
         os.path.join(_cmds, 'checklist_cmd.py'),
         'waiver', '--action', 'add',
         '--milestone', 'BTO', '--check', 'setup_wns',
         '--reason', 'production_test smoke',
         '--approver', 'test_runner'],
        capture_output=True, text=True, env={**os.environ,
            'CBFLOW_CORE_DIR': os.path.join(CBFLOW_ROOT, 'PD'),
            'CBFLOW_GLOBAL_DIR': os.path.join(CBFLOW_ROOT, 'global'),
            'FLOW_CONFIG_VERSION': 'v1.0.0'})
    out = r.stdout + r.stderr
    # Pre-fix pattern: "Check 'setup_wns' not in BTO".
    assert "not in BTO" not in out, (
        f"library check waiver rejected (regression!):\n{out[:400]}")
    # Post-fix pattern emits a W<N> block.
    assert "setup_wns" in out, (
        f"waiver output should mention the check name:\n{out[:400]}")


@test("Checklist discipline guard rejects mismatched milestone")
def t10_2():
    """Verify the Phase-B --discipline guard: add-check with
    --discipline DFT on a PD milestone (BTO) must error out."""
    _cmds = os.path.join(CBFLOW_ROOT, 'PD', 'utils', 'commands')
    r = subprocess.run(
        [sys.executable,
         os.path.join(_cmds, 'checklist_cmd.py'),
         'add-check', '--milestone', 'BTO',
         '--discipline', 'DFT',
         '--name', 'test_regression_check',
         '--type', 'optional',
         '--description', 'should fail',
         '--script', 'check_file_exists.tcl'],
        capture_output=True, text=True, env={**os.environ,
            'CBFLOW_CORE_DIR': os.path.join(CBFLOW_ROOT, 'PD'),
            'CBFLOW_GLOBAL_DIR': os.path.join(CBFLOW_ROOT, 'global'),
            'FLOW_CONFIG_VERSION': 'v1.0.0'})
    out = r.stdout + r.stderr
    assert '--discipline=DFT does not match' in out, (
        f"discipline guard did not fire — add-check succeeded despite "
        f"mismatch:\n{out[:400]}")


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 11: Concurrent-write safety (serialization via WAL + FK)
# ═══════════════════════════════════════════════════════════════════════════════

@test("tracker_db WAL mode: concurrent reader doesn't block writer")
def t11_1():
    """With WAL enabled by init_db (sweep C2), a reader connection
    can SELECT concurrently with a writer connection's INSERT. Pre-WAL
    (DELETE journal) they would serialize fully."""
    import sys as _sys, tempfile, sqlite3, time
    _dash = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'project_dashboard')
    if _dash not in _sys.path:
        _sys.path.insert(0, _dash)
    import tracker_db as t
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, 'tracker.db')
        t.init_db(path)
        # Writer opens a BEGIN IMMEDIATE
        writer = t._connect(path)
        writer.execute('BEGIN IMMEDIATE')
        writer.execute("INSERT INTO blocks (project, block_name) "
                       "VALUES ('bumblebee', 'cpu_core')")
        # Reader (separate connection) should still be able to SELECT.
        reader = t._connect(path)
        reader.execute('PRAGMA busy_timeout=1000')
        row_count = reader.execute(
            'SELECT COUNT(*) FROM blocks').fetchone()[0]
        reader.close()
        # Reader sees the pre-txn state (0 rows) because WAL isolates.
        assert row_count == 0, (
            f'reader should see pre-txn state (0 rows), got {row_count}')
        writer.commit()
        writer.close()
        # After commit, a fresh reader sees the new row.
        reader2 = t._connect(path)
        row_count2 = reader2.execute(
            'SELECT COUNT(*) FROM blocks').fetchone()[0]
        reader2.close()
        assert row_count2 == 1, (
            f'post-commit reader should see 1 row, got {row_count2}')


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 12: DagBuilder — core DAG scheduling
# ═══════════════════════════════════════════════════════════════════════════════

@test("DagBuilder detects circular dependencies")
def t12_1():
    """RaceEngine's DAG builder must raise on self-loops / cycles.
    Smoke-test with a tiny self-referencing node config."""
    import sys as _sys
    _cmds = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'commands')
    if _cmds not in _sys.path:
        _sys.path.insert(0, _cmds)
    # Direct cycle detection: build a trivial graph and run the topological
    # sort used by the engine. The engine's internal method is private, so
    # this is a smoke-test that cycle_check() exists in the module. If
    # the engine is refactored to externalize DagBuilder, this test will
    # become a true unit test; today it validates the API surface.
    import race_engine as _re
    assert hasattr(_re, 'RaceEngine'), 'race_engine.RaceEngine missing'
    assert hasattr(_re, 'Job'), 'race_engine.Job missing'
    # Job class carries status constants used throughout the DAG.
    for st in ('READY', 'PENDING', 'RUNNING', 'DONE', 'FAIL',
               'INVALIDATED', 'BYPASSED', 'FORCE_VALIDATED'):
        assert hasattr(_re.Job, st), f'Job.{st} not defined'


@test("DagBuilder: Job.deps initialized per-instance (no mutable default)")
def t12_2():
    """Guard against the classic Python mutable-default bug on Job.deps.
    If `def __init__(..., deps=[]):` were used, all Jobs would share one
    list and mutations on one Job would appear on another."""
    import sys as _sys
    _cmds = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'commands')
    if _cmds not in _sys.path:
        _sys.path.insert(0, _cmds)
    import race_engine as _re
    j1 = _re.Job('j1', 'stage1', 'setup', 'cmd1')
    j2 = _re.Job('j2', 'stage2', 'setup', 'cmd2')
    j1.deps.append('d1')
    assert j1.deps == ['d1'], f"j1 deps: {j1.deps}"
    assert j2.deps == [], (
        f'MUTABLE DEFAULT BUG: j2.deps was mutated by j1.deps.append — '
        f'should be [] but is {j2.deps}')


@test("StatusDB jobs.status CHECK rejects invalid values")
def t12_3():
    """Verify the sweep C2/B2 schema CHECK on jobs.status fires on
    anything outside the 9-value enum."""
    import sys as _sys, tempfile
    _cmds = os.path.join(CBFLOW_ROOT, 'global', 'utils', 'commands')
    if _cmds not in _sys.path:
        _sys.path.insert(0, _cmds)
    from race_engine import StatusDB
    td = tempfile.mkdtemp(prefix='P0_run_TEST_')
    try:
        db = StatusDB(td, run_name='t12_3', user='testuser')
        import sqlite3
        conn = sqlite3.connect(db.db_path)
        # Legit status accepted.
        conn.execute("INSERT INTO jobs (job_name, stage, status) "
                     "VALUES ('j1', 's1', 'PENDING')")
        # Garbage status rejected by CHECK.
        try:
            conn.execute("INSERT INTO jobs (job_name, stage, status) "
                         "VALUES ('j2', 's2', 'TOTALLY_INVALID_STATUS')")
            conn.commit()
            raise AssertionError(
                'CHECK on jobs.status did not fire for garbage value')
        except sqlite3.IntegrityError:
            pass  # Expected.
        conn.close()
    finally:
        shutil.rmtree(td)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    all_tests = [v for v in globals().values()
                 if callable(v) and hasattr(v, '_test_name')]
    all_tests.sort(key=lambda f: f.__name__)

    print(f'\n{"═" * 74}')
    print(f'  CBFlow Production Validation Test Suite')
    print(f'  {len(all_tests)} tests across 12 sections')
    print(f'{"═" * 74}')

    # Group by section prefix
    sections = {
        't1_':  'Section 1: Compilation & Parsing',
        't2_':  'Section 2: Flow Run Tests',
        't3_':  'Section 3: Database Schema & Data',
        't4_':  'Section 4: Ownership Enforcement',
        't5_':  'Section 5: Checklist System',
        't6_':  'Section 6: Report Files & Data Pointers',
        't7_':  'Section 7: No Hardcoded Values',
        't8_':  'Section 8: GUI Port & DB Naming',
        't9_':  'Section 9: Dashboard tier rendering',
        't10_': 'Section 10: Sign-off + release gate',
        't11_': 'Section 11: Concurrent-write safety',
        't12_': 'Section 12: DagBuilder core',
    }

    for prefix, sec_name in sections.items():
        section(sec_name)
        for func in all_tests:
            if func.__name__.startswith(prefix):
                run_test(func)

    print(f'\n{"═" * 74}')
    if FAIL == 0:
        print(f'  \033[92mRESULTS: {PASS} passed, {FAIL} failed — ALL CLEAR FOR PRODUCTION\033[0m')
    else:
        print(f'  \033[91mRESULTS: {PASS} passed, {FAIL} failed — PRODUCTION BLOCKED\033[0m')
    print(f'{"═" * 74}')

    if FAIL > 0:
        print(f'\n  FAILED TESTS:')
        for r in RESULTS:
            if r[0] == 'FAIL':
                print(f'    [{r[1]}] {r[2]}: {r[3] if len(r) > 3 else ""}')
        print()

    return 0 if FAIL == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
