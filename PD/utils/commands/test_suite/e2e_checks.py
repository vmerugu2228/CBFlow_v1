"""Post-run verification for an e2e flow execution.

Each check returns (status, detail) where status is 'PASS' | 'FAIL' | 'SKIP'.
The runner aggregates them into the shared Results object.
"""

import os
import re
import sqlite3
import subprocess
import sys
from pathlib import Path


_TERMINAL_OK = {'DONE', 'BYPASSED', 'FORCE_VALIDATED'}
_TERMINAL_FAIL = {'FAIL', 'FAILED', 'ERROR', 'KILLED'}


def _find_db(run_dir):
    for f in Path(run_dir).glob('.race_*.db'):
        return str(f)
    return None


def e2e1_run_dir_structure(run_dir):
    if not os.path.isdir(run_dir):
        return 'FAIL', f'run directory not created: {run_dir}'
    expected = ['.run.cbflow.env', 'work']
    missing = [p for p in expected if not os.path.exists(os.path.join(run_dir, p))]
    if missing:
        return 'FAIL', f'missing: {", ".join(missing)}'
    return 'PASS', 'run directory has .run.cbflow.env and work/'


def e2e2_db_initialized(run_dir):
    db = _find_db(run_dir)
    if not db:
        return 'FAIL', 'no .race_*.db file in run dir'
    try:
        conn = sqlite3.connect(db)
        cur = conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = {row[0] for row in cur}
        conn.close()
    except sqlite3.Error as e:
        return 'FAIL', f'sqlite error: {e}'
    required = {'jobs', 'run_info', 'dag_structure'}
    missing = required - tables
    if missing:
        return 'FAIL', f'tables missing: {", ".join(sorted(missing))}'
    return 'PASS', f'{len(tables)} tables present including jobs/run_info/dag_structure'


def e2e3_config_resolved(run_dir):
    work = os.path.join(run_dir, 'work')
    if not os.path.isdir(work):
        return 'SKIP', 'no work/ dir'
    resolved = 0
    unresolved_tokens = 0
    for cfg in Path(work).rglob('config.tcl'):
        resolved += 1
        text = cfg.read_text()
        if re.search(r'\?\?\?', text):
            unresolved_tokens += 1
    if resolved == 0:
        return 'SKIP', 'no work/<FLOW>/<node>/run/config.tcl produced (stages may not have started)'
    if unresolved_tokens:
        return 'FAIL', f'{unresolved_tokens}/{resolved} config.tcl files contain "???" placeholders'
    return 'PASS', f'{resolved} resolved config.tcl files, no "???" placeholders'


def e2e4_dag_populated(run_dir):
    db = _find_db(run_dir)
    if not db:
        return 'SKIP', 'no DB'
    try:
        conn = sqlite3.connect(db)
        n = conn.execute("SELECT COUNT(*) FROM dag_structure").fetchone()[0]
        conn.close()
    except sqlite3.Error as e:
        return 'FAIL', f'sqlite error: {e}'
    if n == 0:
        return 'FAIL', 'dag_structure is empty'
    return 'PASS', f'{n} dag_structure rows'


def e2e5_all_stages_terminal_ok(run_dir):
    db = _find_db(run_dir)
    if not db:
        return 'FAIL', 'no DB'
    try:
        conn = sqlite3.connect(db)
        cur = conn.execute(
            "SELECT job_name, status FROM jobs WHERE job_type = 'stage' "
            "AND id IN (SELECT MAX(id) FROM jobs GROUP BY job_name)")
        rows = list(cur)
        conn.close()
    except sqlite3.Error as e:
        return 'FAIL', f'sqlite error: {e}'
    if not rows:
        return 'FAIL', 'no stage rows in jobs table'
    bad = [(n, s) for n, s in rows if s not in _TERMINAL_OK]
    if bad:
        sample = ', '.join(f'{n}={s}' for n, s in bad[:5])
        return 'FAIL', f'{len(bad)}/{len(rows)} stages not in terminal-OK state: {sample}'
    return 'PASS', f'all {len(rows)} stages reached {sorted(_TERMINAL_OK)}'


def e2e6_stage_metrics_populated(run_dir):
    db = _find_db(run_dir)
    if not db:
        return 'SKIP', 'no DB'
    try:
        conn = sqlite3.connect(db)
        try:
            n = conn.execute("SELECT COUNT(*) FROM stage_metrics").fetchone()[0]
        except sqlite3.OperationalError:
            return 'SKIP', 'stage_metrics table not present'
        conn.close()
    except sqlite3.Error as e:
        return 'FAIL', f'sqlite error: {e}'
    if n == 0:
        return 'SKIP', 'stage_metrics empty (test_mode may skip metric capture)'
    return 'PASS', f'{n} stage_metrics rows'


def e2e7_logs_captured(run_dir):
    work = os.path.join(run_dir, 'work')
    if not os.path.isdir(work):
        return 'SKIP', 'no work/'
    logs = list(Path(work).rglob('*.log'))
    if not logs:
        return 'FAIL', 'no .log files anywhere under work/'

    tcl_errors = []
    for lg in logs:
        try:
            text = lg.read_text(errors='replace')
        except OSError:
            continue
        if re.search(r'(?m)^Error: |can\'t read "[^"]*"', text):
            tcl_errors.append(lg.name)
            if len(tcl_errors) >= 5:
                break
    if tcl_errors:
        return 'FAIL', f'Tcl errors found in: {", ".join(tcl_errors)}'
    return 'PASS', f'{len(logs)} log files, no uncaught Tcl errors'


def e2e8_run_status_command(pd_dir, run_dir):
    cbflow = os.path.join(pd_dir, 'bin', 'cbflow')
    try:
        proc = subprocess.run([cbflow, 'run', 'status'], cwd=run_dir,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return 'FAIL', 'cbflow run status timed out'
    except OSError as e:
        return 'FAIL', f'cbflow run status: {e}'
    if proc.returncode != 0:
        return 'FAIL', f'cbflow run status exited {proc.returncode}'
    return 'PASS', 'cbflow run status returned 0'


# ── Elaborate corner checks ─────────────────────────────────────────────────
#
# Each `e2eN_*` below targets a specific bug class we've hit at least once
# this session. Adding them here means future regressions get caught
# automatically by `cbflow test --e2e`.

_INVALID_CMD_RE = re.compile(r'invalid command name "([^"]+)"')
_REGISTERED_RE = re.compile(r"Flow procedure '([^']+)' registered")
_EXECUTED_RE = re.compile(r'flow_proc:\s*(\w+)')
_TEST_MODE_FALLTHROUGH_RE = re.compile(
    r'TEST_CMD:\s+exit\s+\d+\s+\(intercepted\s+—\s+continuing\)[^\n]*\n'
    r'(?:[^\n]*\n){0,5}?[^\n]*can\'t\s+read'
)
_NO_SUCH_ELEMENT_RE = re.compile(r'can\'t\s+read\s+"[^"]+":\s+no\s+such\s+element')
_UNKNOWN_CMD_RE = re.compile(r'wrong\s+#\s+args:|invalid\s+command\s+name')


def _iter_logs(run_dir):
    work = os.path.join(run_dir, 'work')
    if not os.path.isdir(work):
        return []
    return list(Path(work).rglob('*.log'))


# Stage names that don't have their own runtime .tcl / subnode logs because
# they're bundled into the inputs_<tool>.tcl pipeline (rtl, sdc, upf, def,
# netlist, library — all the "data input" pseudo-stages).
_INPUT_PSEUDO_STAGES = frozenset({
    'rtl1', 'sdc1', 'upf1', 'def1', 'netlist1', 'library1',
    'spef1', 'gds1', 'lib1', 'constraints1',
    'netlist_golden1', 'netlist_revised1',
    'power_spec1',  # CLP input pseudo-stage
})

# Stages that use the dynamic-subnode pattern (one subnode per MMMC scenario)
# instead of setup/run/validate/finish. Their `run/` dir contains per-scenario
# artifacts named differently from `<node>.<tool>.tcl` and `<node>_run.log`.
# Examples:
#   STA/timing1     — one subnode per MMMC scenario
#   STA/extraction1 — one subnode per RC corner
_DYNAMIC_SUBNODE_STAGES = frozenset({
    'timing1', 'extraction1',
})


def _is_input_pseudo_stage(stage):
    """Match exactly or by prefix (handles future <stage>1, <stage>2 variants)."""
    return stage in _INPUT_PSEUDO_STAGES or stage.rstrip('0123456789') in {
        s.rstrip('0123456789') for s in _INPUT_PSEUDO_STAGES
    }


def _stage_dirs(run_dir, skip_pseudo=True, skip_dynamic=True):
    """Return [(flow, stage, stage_dir), ...] for every work/<flow>/<stage>/ dir.
    By default skips:
      - input pseudo-stages (bundled into inputs_<tool>.tcl)
      - dynamic-subnode stages (different runtime artifact layout)
    """
    work = os.path.join(run_dir, 'work')
    if not os.path.isdir(work):
        return []
    out = []
    for flow in os.listdir(work):
        flow_dir = os.path.join(work, flow)
        if not os.path.isdir(flow_dir):
            continue
        for stage in os.listdir(flow_dir):
            sd = os.path.join(flow_dir, stage)
            if not os.path.isdir(sd):
                continue
            if skip_pseudo and _is_input_pseudo_stage(stage):
                continue
            if skip_dynamic and stage in _DYNAMIC_SUBNODE_STAGES:
                continue
            out.append((flow, stage, sd))
    return out


def e2e9_no_invalid_command(run_dir):
    """No 'invalid command name "..."' anywhere in any log.

    Caught by example: the FP/cadence/innovus `generate_globals` bug where
    a flow_proc was invoked as a Tcl command via `catch {$step}`.
    """
    found = {}
    for lg in _iter_logs(run_dir):
        try:
            text = lg.read_text(errors='replace')
        except OSError:
            continue
        for m in _INVALID_CMD_RE.finditer(text):
            found.setdefault(m.group(1), set()).add(lg.name)
    if not found:
        return 'PASS', 'no "invalid command name" in any log'
    sample = ', '.join(f'{n} (in {next(iter(found[n]))})'
                       for n in list(found)[:3])
    return 'FAIL', f'{len(found)} invalid command(s): {sample}'


def e2e10_flow_procs_executed(run_dir):
    """For every flow_proc registered, verify the same proc actually executed.

    Catches: procs registered but never dispatched (missing flow_exec_all,
    foreach-step bug, etc.).
    """
    registered_by_stage = {}
    executed_by_stage = {}
    for lg in _iter_logs(run_dir):
        try:
            text = lg.read_text(errors='replace')
        except OSError:
            continue
        # Stage = parent dir name (init_design1/run/init_design1_run.log)
        stage = lg.parent.parent.name
        for m in _REGISTERED_RE.finditer(text):
            registered_by_stage.setdefault(stage, set()).add(m.group(1))
        for m in _EXECUTED_RE.finditer(text):
            executed_by_stage.setdefault(stage, set()).add(m.group(1))

    if not registered_by_stage:
        return 'SKIP', 'no flow_procs registered (no logs or empty stages)'

    missing = []
    for stage, regs in registered_by_stage.items():
        execs = executed_by_stage.get(stage, set())
        miss = regs - execs
        if miss:
            missing.append(f'{stage}: {sorted(miss)}')

    if missing:
        return 'FAIL', f'{len(missing)} stage(s) with un-executed procs: {missing[:3]}'
    total = sum(len(v) for v in registered_by_stage.values())
    return 'PASS', f'all {total} registered flow_procs executed'


def e2e11_no_test_mode_fallthrough(run_dir):
    """Detect `TEST_CMD: exit N (intercepted)` followed by code that reads
    an unguarded variable — the test_mode-exit-fallthrough bug.

    Real-life example: FP set_design_mode hit `handle_error + exit 1` but
    test_mode intercepted exit, then the next line read fp(common,cpu_count)
    which doesn't exist, crashing the proc.
    """
    hits = []
    for lg in _iter_logs(run_dir):
        try:
            text = lg.read_text(errors='replace')
        except OSError:
            continue
        if _TEST_MODE_FALLTHROUGH_RE.search(text):
            hits.append(lg.name)
            if len(hits) >= 5:
                break
    if hits:
        return 'FAIL', (f'test_mode exit-fallthrough detected in: {", ".join(hits)} — '
                       f'replace `exit N` with `return` after handle_error in flow_procs')
    return 'PASS', 'no test_mode exit-fallthrough patterns'


def e2e12_runtime_tcl_generated(run_dir):
    """Every executed stage has either:
      (a) a generated `<node>.<tool>.tcl` runtime file in its run/ dir
          (handlers using `_gen_file` pattern: FC, Innovus, Genus, PT, etc.), or
      (b) a launch wrapper csh + log indicating the cmd_file was invoked
          directly (handlers using direct cmd_file pattern: Calibre, ICV, Redhawk,
          Voltus, Conformal).
    Confirms the subnode-handler 'setup' or 'run' step ran.
    """
    missing = []
    found = 0
    for flow, stage, sd in _stage_dirs(run_dir):
        run_dir_ = os.path.join(sd, 'run')
        if not os.path.isdir(run_dir_):
            continue
        entries = os.listdir(run_dir_)
        # Pattern (a): per-node tcl in run/
        has_per_node_tcl = any(
            f.endswith('.tcl') and f not in ('config.tcl', 'setup.tcl')
            for f in entries
        )
        # Pattern (b): launch wrapper csh + a run log
        has_launch = any(f.startswith('launch_') and f.endswith('.csh')
                         for f in entries)
        has_run_log = any(f.endswith('_run.log') for f in entries)
        if has_per_node_tcl or (has_launch and has_run_log):
            found += 1
        else:
            missing.append(f'{flow}/{stage}')
    if missing:
        return 'FAIL', f'{len(missing)} stage(s) missing runtime artifacts: {missing[:5]}'
    if found == 0:
        return 'SKIP', 'no stages with run/ dirs'
    return 'PASS', f'{found} stages have runtime artifacts'


def e2e13_each_subnode_logged(run_dir):
    """Every stage has setup/run/validate/finish subnode logs.

    A missing subnode log indicates a subnode failed silently or was
    skipped (e.g., handler script crashed before producing output).
    """
    expected_subnodes = ('setup', 'run', 'validate', 'finish')
    incomplete = []
    complete = 0
    for flow, stage, sd in _stage_dirs(run_dir):
        run_dir_ = os.path.join(sd, 'run')
        if not os.path.isdir(run_dir_):
            continue
        present = set()
        for f in os.listdir(run_dir_):
            for sub in expected_subnodes:
                if f.endswith(f'_{sub}.log'):
                    present.add(sub)
        missing = set(expected_subnodes) - present
        if missing:
            incomplete.append(f'{flow}/{stage} missing {sorted(missing)}')
        else:
            complete += 1
    if incomplete:
        return 'FAIL', f'{len(incomplete)} incomplete stages: {incomplete[:3]}'
    if complete == 0:
        return 'SKIP', 'no execution stages'
    return 'PASS', f'all {complete} stages have all 4 subnode logs'


def e2e14_outputs_dir_nonempty(run_dir):
    """Every execution stage produced at least one file in its outputs/ dir.
    Empty outputs/ = stage ran but produced nothing → broken contract.
    """
    empty_stages = []
    nonempty = 0
    for flow, stage, sd in _stage_dirs(run_dir):
        outdir = os.path.join(sd, 'outputs')
        if not os.path.isdir(outdir):
            continue
        try:
            contents = os.listdir(outdir)
        except OSError:
            continue
        if not contents:
            empty_stages.append(f'{flow}/{stage}')
        else:
            nonempty += 1
    if empty_stages:
        return 'FAIL', f'{len(empty_stages)} stages with empty outputs/: {empty_stages[:5]}'
    if nonempty == 0:
        return 'SKIP', 'no stage has outputs/ dir'
    return 'PASS', f'{nonempty} stages have non-empty outputs/'


def e2e15_config_no_unresolved(run_dir):
    """Generated config.tcl files have no '???' or '${unresolved}' tokens.
    Already partially covered by e2e3; this extends to all generated config files.
    """
    work = os.path.join(run_dir, 'work')
    if not os.path.isdir(work):
        return 'SKIP', 'no work/'
    bad = []
    total = 0
    for cfg in Path(work).rglob('config.tcl'):
        total += 1
        try:
            text = cfg.read_text(errors='replace')
        except OSError:
            continue
        if '???' in text or re.search(r'\$\{[a-zA-Z_]+\}', text):
            bad.append(str(cfg.relative_to(work)))
            if len(bad) >= 5:
                break
    if bad:
        return 'FAIL', f'{len(bad)} config.tcl with unresolved tokens: {bad}'
    return 'PASS', f'{total} config.tcl files all resolved'


def e2e16_no_array_element_missing(run_dir):
    """Scan logs for 'no such element in array' — surfaces unguarded
    `$arr(key)` reads where guard was forgotten. Stricter than e2e7.
    """
    hits = {}
    for lg in _iter_logs(run_dir):
        try:
            text = lg.read_text(errors='replace')
        except OSError:
            continue
        for m in _NO_SUCH_ELEMENT_RE.finditer(text):
            key = m.group(0).split('"')[1] if '"' in m.group(0) else m.group(0)
            hits.setdefault(key, set()).add(lg.name)
    if hits:
        sample = list(hits.keys())[:3]
        return 'FAIL', f'{len(hits)} missing array keys: {sample}'
    return 'PASS', 'no missing array elements in any log'


def e2e17_db_run_logs_table(run_dir):
    """The run_logs table in the SQLite DB has rows. If it's empty the
    framework's log-aggregation pipeline broke."""
    db = _find_db(run_dir)
    if not db:
        return 'SKIP', 'no DB'
    try:
        conn = sqlite3.connect(db)
        try:
            n = conn.execute("SELECT COUNT(*) FROM run_logs").fetchone()[0]
        except sqlite3.OperationalError:
            return 'SKIP', 'run_logs table not present'
        conn.close()
    except sqlite3.Error as e:
        return 'FAIL', f'sqlite error: {e}'
    if n == 0:
        return 'SKIP', 'run_logs empty (test_mode may not aggregate)'
    return 'PASS', f'{n} run_logs rows'


def e2e18_no_handler_errors(run_dir):
    """Scan for 'ERROR: Command file not found' and similar handler errors.
    These would surface FP/cadence/innovus-style 'init_design1_innovus.tcl
    not found' bugs."""
    pat = re.compile(r'(?:ERROR|FATAL).*?(?:Command file not found|Cannot find generated config|'
                     r'Unknown subnode|Flow procedure .* not found)')
    hits = []
    for lg in _iter_logs(run_dir):
        try:
            text = lg.read_text(errors='replace')
        except OSError:
            continue
        if pat.search(text):
            hits.append(lg.name)
            if len(hits) >= 5:
                break
    if hits:
        return 'FAIL', f'handler errors in: {", ".join(hits)}'
    return 'PASS', 'no handler errors in any log'


CHECKS = [
    ('e2e1_run_dir_structure',     e2e1_run_dir_structure,     False),
    ('e2e2_db_initialized',        e2e2_db_initialized,        False),
    ('e2e3_config_resolved',       e2e3_config_resolved,       False),
    ('e2e4_dag_populated',         e2e4_dag_populated,         False),
    ('e2e5_all_stages_terminal_ok', e2e5_all_stages_terminal_ok, False),
    ('e2e6_stage_metrics_populated', e2e6_stage_metrics_populated, False),
    ('e2e7_logs_captured',         e2e7_logs_captured,         False),
    ('e2e8_run_status_command',    e2e8_run_status_command,    True),  # needs pd_dir
    # ── elaborate corner checks ─────────────────────────────────────────────
    ('e2e9_no_invalid_command',    e2e9_no_invalid_command,    False),
    ('e2e10_flow_procs_executed',  e2e10_flow_procs_executed,  False),
    ('e2e11_no_test_mode_fallthrough', e2e11_no_test_mode_fallthrough, False),
    ('e2e12_runtime_tcl_generated', e2e12_runtime_tcl_generated, False),
    ('e2e13_each_subnode_logged',  e2e13_each_subnode_logged,  False),
    ('e2e14_outputs_dir_nonempty', e2e14_outputs_dir_nonempty, False),
    ('e2e15_config_no_unresolved', e2e15_config_no_unresolved, False),
    ('e2e16_no_array_element_missing', e2e16_no_array_element_missing, False),
    ('e2e17_db_run_logs_table',    e2e17_db_run_logs_table,    False),
    ('e2e18_no_handler_errors',    e2e18_no_handler_errors,    False),
]


def run_all_checks(results, flow, pd_dir, run_dir):
    """Run every e2e check against an already-executed run dir."""
    suite = 'e2e'
    category = f'{flow}'
    for name, fn, needs_pd_dir in CHECKS:
        try:
            if needs_pd_dir:
                status, detail = fn(pd_dir, run_dir)
            else:
                status, detail = fn(run_dir)
        except Exception as e:
            status, detail = 'FAIL', f'{type(e).__name__}: {e}'
        if status == 'PASS':
            results.passed(suite, category, name, detail)
        elif status == 'SKIP':
            results.skipped(suite, category, name, detail)
        else:
            results.failed(suite, category, name, detail)
