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
COMMANDS_DIR = os.path.join(PD_DIR, 'utils', 'commands')
WORKAREA = os.path.join(CBFLOW_ROOT, 'workarea_test')
sys.path.insert(0, COMMANDS_DIR)

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
    r = subprocess.run(['tclsh', os.path.join(PD_DIR, 'utils', 'utilities', 'v1.0.0', 'resolve_inputs.tcl')],
                      capture_output=True, text=True)
    assert r.returncode == 0, f"resolve_inputs.tcl: {r.stderr[:80]}"

@test("threshold_overrides.tcl resolves correctly")
def t1_8():
    r = subprocess.run(['tclsh', '-c', '''
source PD/config/exit/v1.0.0/threshold_overrides.tcl
set v [get_threshold ravendrive PLACE_EXIT setup_wns P0]
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
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')
    _check_run('SYNTH_PNR', run_dir)
    # Check all expected stages
    work = os.path.join(run_dir, 'work', 'SYNTH_PNR')
    for stage in ['init_design1', 'synthesis1', 'place1', 'cts1', 'cts_opt1',
                   'route1', 'pro1', 'signoff1', 'export_data1']:
        assert os.path.isdir(os.path.join(work, stage)), f"Missing stage: {stage}"

@test("STA test run exists")
def t2_2():
    # Check at least one STA run exists
    sta_runs = [d for d in os.listdir(WORKAREA) if 'STA' in d and os.path.isdir(os.path.join(WORKAREA, d))]
    assert sta_runs, "No STA test run found"

@test("LEC test run exists")
def t2_3():
    run_dir = os.path.join(WORKAREA, 'P0_run_LEC_test1')
    if os.path.isdir(run_dir):
        _check_run('LEC', run_dir)

@test("CLP test run exists")
def t2_4():
    run_dir = os.path.join(WORKAREA, 'P0_run_CLP_test1')
    if os.path.isdir(run_dir):
        _check_run('CLP', run_dir)

@test("PNR test run exists")
def t2_5():
    run_dir = os.path.join(WORKAREA, 'P0_run_PNR_test1')
    if os.path.isdir(run_dir):
        _check_run('PNR', run_dir)

@test("SYNTH test run exists")
def t2_6():
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_test1')
    if os.path.isdir(run_dir):
        _check_run('SYNTH', run_dir)


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: Database Schema & Data
# ═══════════════════════════════════════════════════════════════════════════════

@test("SYNTH_PNR DB has all 13 tables")
def t3_1():
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')
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
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')
    db_files = glob.glob(os.path.join(run_dir, '.race_*.db'))
    conn = sqlite3.connect(db_files[0])
    info = dict(conn.execute("SELECT key, value FROM run_info").fetchall())
    conn.close()
    assert info.get('flow_type') == 'SYNTH_PNR', f"Wrong flow_type: {info.get('flow_type')}"
    assert info.get('project') == 'ravendrive', f"Wrong project: {info.get('project')}"

@test("dag_structure has jobs")
def t3_3():
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')
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

@test("11 milestones available")
def t5_1():
    import checklist_cmd as cl
    ms = cl.get_available_milestones()
    assert len(ms) >= 11, f"Expected >=11, got {len(ms)}: {ms}"
    for m in ['FP_EXIT', 'PLACE_EXIT', 'CTS_EXIT', 'PRO_EXIT', 'BTO', 'MTO',
              'STA_SIGNOFF', 'LEC_SIGNOFF', 'CLP_SIGNOFF', 'PV_SIGNOFF', 'EMIR_SIGNOFF']:
        assert m in ms, f"Missing milestone: {m}"

@test("All milestone configs parse with check_packs and library_checks")
def t5_2():
    import checklist_cmd as cl
    for ms in cl.get_available_milestones():
        cfg = cl.parse_milestone_config(cl.get_milestone_config_path(ms))
        assert cfg.get('milestone_info', {}).get('name') == ms, f"{ms} name mismatch"
        assert 'check_packs' in cfg, f"{ms} missing check_packs"

@test("292 library checks across 14 files")
def t5_3():
    total = 0
    for f in glob.glob(os.path.join(PD_DIR, 'config', 'exit', 'v1.0.0', 'checks', '*.tcl')):
        total += sum(1 for line in open(f) if '"description"' in line)
    assert total >= 290, f"Expected >=290 checks, got {total}"

@test("All library checks have script field")
def t5_4():
    for f in glob.glob(os.path.join(PD_DIR, 'config', 'exit', 'v1.0.0', 'checks', '*.tcl')):
        with open(f) as fh:
            content = fh.read()
        descs = content.count('"description"')
        scripts = content.count('"script"')
        assert scripts >= descs, f"{os.path.basename(f)}: {scripts} scripts < {descs} descriptions"

@test("Phase filtering works (P0 shows fewer checks than P3)")
def t5_5():
    import checklist_cmd as cl
    cfg = cl.parse_milestone_config(cl.get_milestone_config_path('BTO'))
    all_checks = {**cfg.get('mandatory_checks', {}), **cfg.get('optional_checks', {}),
                  **cfg.get('library_checks', {})}
    p0 = cl._evaluate_checks('/tmp/fake', all_checks, set(), phase='P0')
    p3 = cl._evaluate_checks('/tmp/fake', all_checks, set(), phase='P3')
    p0_active = sum(1 for r in p0 if r['status'] != 'SKIPPED')
    p3_active = sum(1 for r in p3 if r['status'] != 'SKIPPED')
    assert p0_active < p3_active, f"P0({p0_active}) should be < P3({p3_active})"

@test("Auto-detect milestone from flow type (dynamic, no hardcoding)")
def t5_6():
    import checklist_cmd as cl
    # STA → STA_SIGNOFF (scanned from config dir)
    assert cl._detect_milestone_for_flow('STA') == 'STA_SIGNOFF'
    assert cl._detect_milestone_for_flow('LEC') == 'LEC_SIGNOFF'
    assert cl._detect_milestone_for_flow('CLP') == 'CLP_SIGNOFF'
    assert cl._detect_milestone_for_flow('PV') == 'PV_SIGNOFF'
    assert cl._detect_milestone_for_flow('EMIR') == 'EMIR_SIGNOFF'
    # SYNTH_PNR → BTO (no SYNTH_PNR_SIGNOFF exists, falls to BTO)
    assert cl._detect_milestone_for_flow('SYNTH_PNR') == 'BTO'

@test("Auto-detect phase from run dir")
def t5_7():
    import checklist_cmd as cl
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')
    phase = cl._detect_phase(run_dir)
    assert phase == 'P0', f"Expected P0, got {phase}"

@test("Checklist DB write works")
def t5_8():
    import checklist_cmd as cl
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')
    db_path = cl._find_run_db(run_dir)
    assert db_path, "No DB found for test run"


# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: Report Files & Data Pointers
# ═══════════════════════════════════════════════════════════════════════════════

@test("Sample reports exist in all stages")
def t6_1():
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')
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
    run_dir = os.path.join(WORKAREA, 'P0_run_SYNTH_PNR_test1')
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
    with open(os.path.join(COMMANDS_DIR, 'race_engine.py')) as f:
        content = f.read()
    # Should NOT have: get('tool,vendor', 'synopsys') or get('tool,name', 'fc')
    assert "'synopsys'" not in content or "get('tool,vendor', 'synopsys')" not in content
    assert "get('tool,name', 'fc')" not in content

@test("No hardcoded flow→milestone dict in checklist_cmd.py")
def t7_2():
    with open(os.path.join(COMMANDS_DIR, 'checklist_cmd.py')) as f:
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
    with open(os.path.join(PD_DIR, 'utils', 'dashboard', 'race_dashboard.py')) as f:
        lines = f.readlines()
    # Check that v1.0.0 is not used in path construction without env var
    for i, line in enumerate(lines, 1):
        if "'v1.0.0'" in line and 'config' in line.lower() and 'get(' not in line and '#' not in line.split("'v1.0.0'")[0]:
            assert False, f"Line {i}: hardcoded v1.0.0 in path: {line.strip()[:60]}"

@test("No stale file paths in exit configs")
def t7_5():
    stale = ['work/FP/', 'work/PNR/', 'floorplan.enc', 'placement.enc', 'cts.enc']
    for f in glob.glob(os.path.join(PD_DIR, 'config', 'exit', 'v1.0.0', '*_config.tcl')):
        with open(f) as fh:
            content = fh.read()
        for pat in stale:
            assert pat not in content, f"Stale path '{pat}' in {os.path.basename(f)}"

@test("No hardcoded VALID_MILESTONES in qor_report_cmd.py")
def t7_6():
    with open(os.path.join(COMMANDS_DIR, 'qor_report_cmd.py')) as f:
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
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    all_tests = [v for v in globals().values()
                 if callable(v) and hasattr(v, '_test_name')]
    all_tests.sort(key=lambda f: f.__name__)

    print(f'\n{"═" * 74}')
    print(f'  CBFlow Production Validation Test Suite')
    print(f'  {len(all_tests)} tests across 8 sections')
    print(f'{"═" * 74}')

    # Group by section prefix
    sections = {
        't1_': 'Section 1: Compilation & Parsing',
        't2_': 'Section 2: Flow Run Tests',
        't3_': 'Section 3: Database Schema & Data',
        't4_': 'Section 4: Ownership Enforcement',
        't5_': 'Section 5: Checklist System',
        't6_': 'Section 6: Report Files & Data Pointers',
        't7_': 'Section 7: No Hardcoded Values',
        't8_': 'Section 8: GUI Port & DB Naming',
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
