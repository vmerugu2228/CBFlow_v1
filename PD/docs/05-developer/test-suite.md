# `cbflow test` — Developer Guide

**Version:** 2.1.1
**Date:** 2026-06-12

The CBflow test suite catches both **structural problems** (static config validation, dead-code detection) and **runtime regressions** (end-to-end flow execution in test_mode). It's the single source of truth for "is the codebase healthy".

---

## Table of Contents

1. [TL;DR](#1-tldr)
2. [Module layout](#2-module-layout)
3. [Running the suite](#3-running-the-suite)
4. [Static categories 1-9](#4-static-categories-1-9)
5. [E2E checks 1-18](#5-e2e-checks-1-18)
6. [Test fixtures](#6-test-fixtures)
7. [Sandbox model](#7-sandbox-model)
8. [Reporters: console / JSON / JUnit](#8-reporters-console-json-junit)
9. [Adding a new static check](#9-adding-a-new-static-check)
10. [Adding a new e2e check](#10-adding-a-new-e2e-check)
11. [CI integration](#11-ci-integration)
12. [The pseudo-stage / dynamic-subnode allowlist](#12-the-pseudo-stage-dynamic-subnode-allowlist)

---

## 1. TL;DR

```bash
cbflow test                           # static cats 1-9 + e2e all 12 flows
cbflow test --static --category 9     # one category, fast
cbflow test --e2e --flow SYNTH_PNR    # one flow, ~20s
cbflow test --ci                      # junit + non-zero exit on fail
```

Today's baseline (v2.1.1, all 12 flows, test_mode):

```
STATIC:  PASS=1269   FAIL=0   SKIP=80
E2E:     PASS=144    FAIL=0   SKIP=20
Duration: ~3-5 min
```

Any new commit should keep these green. Cat 9 specifically catches the bug classes that bit us in v2.1.0.

---

## 2. Module layout

```
PD/utils/commands/test_cmd.py           # CLI entry point
PD/utils/commands/test_suite/
  __init__.py
  results.py            # shared Results collector
  static_checks.py      # cats 1-9
  fixtures.py           # picks workarea_test/uc_*.tcl, rewrites run_name
  sandbox.py            # tempdir + run-dir lifecycle
  e2e_runner.py         # cbflow workspace create + cbflow run all subprocess driver
  e2e_checks.py         # 18 per-run verifications
  reporters.py          # Console, JSON, JUnit XML
PD/bin/cbflow-test-suite                # 20-line shim → `cbflow test --static`
```

Dispatcher wiring: `PD/bin/cbflow:222-260` routes `cbflow test` → `test_cmd.py`.

---

## 3. Running the suite

### Default

```
cbflow test
```

Runs static cats 1-9 sequentially, then e2e against all 12 flows (one at a time, in sandboxed temp workareas). Print pass/fail summary at the end. Exit 0 if all pass, 1 if any fail.

### Scope flags

| Flag | Effect |
|---|---|
| `--static` | Skip e2e |
| `--e2e` | Skip static |
| `--flow SYNTH_PNR` | Single flow |
| `--flows SYNTH,PNR,STA` | Comma-separated subset |
| `--category 9` | Single static category |
| `--vendor synopsys` | Prefer fixture variant matching this vendor |
| `--list` | List all categories + e2e checks and exit |

### Sandbox control

| Flag | Effect |
|---|---|
| `--timeout 600` | Per-flow timeout in seconds |
| `--keep` | Never delete sandboxes (debug) |
| `--keep-on-fail` (default) | Keep sandboxes only when the flow failed |
| `--clean-on-fail` | Always remove sandboxes |

### Reports

| Flag | Effect |
|---|---|
| `--report results.json` | JSON report path |
| `--junit junit.xml` | JUnit XML report path |
| `--ci` | Implies `--junit cbflow-junit.xml`, plain console, non-zero exit on fail |
| `--verbose` | Show every PASS/FAIL line (default: only FAIL) |
| `--quiet` | Show only the final summary |

---

## 4. Static categories 1-9

### Cat 1 — Workspace & Run Creation

For every flow, validates that:
- `node_configs/<FLOW>_config.tcl` exists
- `stages {...}` block is defined
- Every stage has a `dependencies,<stage>` entry
- Every stage has `stage_types,<stage>` and `node_types,<stage>` entries
- Every stage has a `runtime,timeout,<stage>` entry
- Flow type is listed in `flow_config.tcl flow(types)`

### Cat 2 — Makefile & Handler Validation

For every flow × tool:
- `cmds/<FLOW>/<vendor>/<tool>/v1.0.0/` exists
- For non-input stages: either a `<stage>_<tool>.tcl` cmd file or a `<stage>_subnode_handler.tcl` handler
- For input pseudo-stages (`node_types == "inputs"`): `inputs_<tool>.tcl` is acceptable as bundled coverage
- For cmd files: REPORTS_DIR / tech_config / user_config tokens present OR setup.tcl is sourced (accepts indirection)
- File ends with `exit` OR `flow_exec_all` OR `exit_with_status` (any terminator)

Tool resolution: tries `<FLOW>_config.tcl`, then any `<FLOW>_<tool>_config.tcl`, then any `cmds/<FLOW>/<vendor>/<tool>/v1.0.0/` that actually exists.

### Cat 3 — Override Setup & Config Mechanism

- Every cmd file references either `setup.tcl` or `setup_file`
- `override_setup` hook mechanism
- Project / tech config dirs present

### Cat 4 — LSF Management

- `tool_launch_config.tcl`: `tool_shell,<tool>` for each EDA tool, `flow_mapping,<flow_lower>,<stage>` per flow
- `lsf_config.tcl`: `bsub,queue` / `bsub,project` / queue tiers `XS/S/M/L/XL/ultra`
- `flow_config.tcl`: `flow(use_lsf)` / `flow(use_xterm)`
- Python helpers: `lsf_cmd.py`, `lsf_manager_cmd.py`

### Cat 5 — MMMC Config & Scenarios

- Per-project `mmmc_config.tcl` (not framework-level)
- `mmmc_manager_cmd.py`
- `init_design_fc.tcl` has `create_mode`, `create_corner`, `create_scenario`, `set_scenario_status`
- Per-tech: `library_sets` OR `tech(ndm,...)` OR `tech(<track>,ndm)` OR `lib_root` keys

### Cat 6 — Mandatory I/O & Validation

- Each flow declares `release_types,<exit_stage>,...` (or skips if not a stage-exit flow)
- `release_config.tcl` has entries for every flow
- `release_utils.tcl` defines `init`, `validate_mandatory_files`, `resolve`
- Zero env-var lookups for release data (everything goes through `project()` array)
- `resolve_inputs` coverage across `inputs_*.tcl`

### Cat 7 — Log Parsing & Error Halt

- `log_viewer.py` recognizes error patterns
- `validation_cmd.py` exists
- `flow_exec_all` coverage across cmd files
- `utils.tcl` defines `handle_error`, `handle_warning`, `handle_info`, `flow_proc`, `flow_exec_all`
- Exit milestone configs present (`config/exit/v1.0.0/`)

### Cat 8 — Cross-Cutting

- Zero `$::run_dir` bugs in cmd files (the run_dir-in-eval-context anti-pattern)
- No `FCT` / `PHYV` references (retired naming)
- Shell completion scripts present
- Project configs have `project(release,path)` defined

### Cat 9 — **Dead-Code & Cross-Reference Audit** (10 checks)

The most aggressive category, added in v2.1.1. Each check targets a specific bug class we've hit:

| Check | Targets |
|---|---|
| 1: Handler → cmd_file integrity | Subnode handlers referencing missing/wrong cmd files |
| 2: STAGE_NAME ↔ filename | `STAGE_NAME "export_db"` in a file named `export_data_*.tcl` |
| 3: Undefined `$flow_dir` | Code that uses `$flow_dir` instead of `$::env(FLOW_DIR)` |
| 4: Dead `if-source-puts-exit` | Success+error paths both running because of missing `else` |
| 5: Orphan stage (info only) | Cmd files whose stage isn't in the flow's `stages {...}` list — emitted as SKIP, not FAIL, because legitimate sub-view files exist |
| 6: Header comment vs location | `# FP …` header in a file under `cmds/FCFP/` |
| 7: `foreach step { … } { catch {$step} … }` | flow_procs invoked as Tcl commands (the FP `generate_globals` bug) |
| 8: `handle_error; exit N` + later `$arr(...)` | Test-mode exit fallthrough crashes |
| 9: flow_procs registered, no dispatch | Procs defined but `flow_exec_all` / `flow_exec NAME` never invoked at top level |
| 10: Unbalanced `{` and `}` | Broken Tcl syntax (often hides `flow_exec_all` inside an unclosed proc body) |

#### Known allowlist (`_STAGE_NAME_ALIASES`, `_SYNTHETIC_STAGES`)

Synthetic stages: `inputs`, `validate`, `release_data`, `export_data` — present everywhere as bundled-input or release files but legitimately not in some flows' `stages {...}` list.

Stage-name aliases: `timing_scenario` → `timing`, `timing_setup` → `timing`, `timing_hold` → `timing` — MMMC sub-view templates intentionally inherit the parent stage name.

Add a new alias by editing `static_checks.py:_STAGE_NAME_ALIASES`.

---

## 5. E2E checks 1-18

Each check runs once per flow against a real `workspace create` + `run all` in a sandboxed temp area. Failures point at the run dir if `--keep-on-fail` is set.

| Check | Validates |
|---|---|
| **e2e1** | `.run.cbflow.env` + `work/` dir created |
| **e2e2** | SQLite DB has `jobs`, `run_info`, `dag_structure` tables |
| **e2e3** | Resolved `config.tcl` files have no `???` placeholders |
| **e2e4** | `dag_structure` table populated |
| **e2e5** | Every stage reached `DONE`/`BYPASSED`/`FORCE_VALIDATED` |
| **e2e6** | `stage_metrics` table has rows (SKIP if test_mode opts out) |
| **e2e7** | `.log` files present in every stage's run dir |
| **e2e8** | `cbflow run status` returns 0 |
| **e2e9** | No `invalid command name "..."` anywhere |
| **e2e10** | Every registered `flow_proc 'X'` also shows `── flow_proc: X ──` execution |
| **e2e11** | No `TEST_CMD: exit N (intercepted)` followed within 5 lines by `can't read` |
| **e2e12** | Each stage's `run/` has either `<node>.<tool>.tcl` OR a `launch_*.csh` wrapper + `*_run.log` |
| **e2e13** | All 4 subnode logs present (`*_setup.log`, `*_run.log`, `*_validate.log`, `*_finish.log`) |
| **e2e14** | `outputs/` directory has at least one file |
| **e2e15** | Generated config.tcl files have no `???` / `${unresolved}` tokens |
| **e2e16** | No "no such element in array" errors |
| **e2e17** | `run_logs` SQLite table populated (SKIP if test_mode doesn't aggregate) |
| **e2e18** | No "Command file not found" / "Cannot find generated config" / "Unknown subnode" / "Flow procedure not found" |

### What the checks together prove

- The cmd file actually ran (`e2e12`, `e2e13`)
- Every flow_proc the cmd file defined got executed (`e2e10`)
- No Tcl errors snuck through `flow_exec`'s catch (`e2e9`, `e2e16`)
- Test_mode didn't mask a real bug by intercepting `exit` (`e2e11`)
- The DAG actually ran to terminal-OK (`e2e5`, `e2e4`, `e2e6`)
- The DB layer is intact (`e2e2`, `e2e8`, `e2e17`)
- Stages produced their declared artifacts (`e2e14`)
- The handler layer wasn't silently broken (`e2e18`)

---

## 6. Test fixtures

`workarea_test/uc_<FLOW>.tcl` and `workarea_test/uc_<FLOW>_<tool>.tcl` — ready-to-use user_configs for every flow. The e2e runner picks the best match for each flow (`uc_<FLOW>.tcl` first, then a vendor variant, then any `uc_<FLOW>_*.tcl`).

For each run, `fixtures.py:rewrite_for_isolation` copies the fixture to a temp dir and patches:
- `flow(run_name) "cbflowtest_<uuid8>"` — guarantees no collision with existing runs
- `flow(test_mode) "true"` — forces test mode if the fixture forgot

Each rewritten fixture is fed to `cbflow workspace create --config <rewritten> --force`. The resulting run dir lives at `project(workarea_path)/<design>/P<phase>_run_<flow>_<test_name>/`.

---

## 7. Sandbox model

Each e2e flow gets a `Sandbox` (defined in `sandbox.py`):

```python
class Sandbox:
    flow:      str             # 'SYNTH_PNR'
    tmp_dir:   str             # /tmp/cbflow-test-synth_pnr-XXXXXX/
    run_dir:   str             # workarea/<design>/P0_run_<flow>_cbflowtest_<uuid>
    run_name:  str             # cbflowtest_<uuid>
    kept:      bool            # set by cleanup(keep=True)
```

After each e2e cycle:

- `--keep`: never delete
- `--keep-on-fail` (default): delete only if all checks passed
- `--clean-on-fail`: always delete

Sandboxes are independent — they use unique `run_name` so they share `workarea/<design>/` with other runs without collisions.

---

## 8. Reporters: console / JSON / JUnit

### Console (always on)

- Per-category section headers (=== bar)
- Per-check status line (only FAIL by default; `--verbose` adds PASS)
- Per-flow E2E header
- Final summary box with totals

### JSON (`--report path`)

```json
{
  "summary": {"pass": 1269, "fail": 0, "skip": 80, "duration_s": 0.12, "has_failures": false},
  "entries": [
    {"suite": "static", "category": "cat1_workspace_creation",
     "test": "SYNTH: stages defined", "status": "PASS",
     "detail": "6: rtl1 sdc1 upf1 ...", "duration_ms": 0},
    ...
  ]
}
```

Consumable by dashboards / trend analysis.

### JUnit XML (`--junit path` or `--ci`)

Maps to `<testsuite name="suite.category" tests=N failures=K skipped=M>`. Each entry becomes a `<testcase>` with `<failure>` / `<skipped>` children. Drop-in for Jenkins, GitLab CI, GitHub Actions.

---

## 9. Adding a new static check

1. Open `PD/utils/commands/test_suite/static_checks.py`
2. Add a function `def catN_my_check(results, pd_dir, flows): ...`
3. Use `results.passed(...)`, `results.failed(...)`, `results.skipped(...)` (signature in `results.py`)
4. Register in the `CATEGORIES` dict at the bottom of the file

Example:

```python
def cat10_my_new_check(results, pd_dir, flows):
    suite = 'static'
    category = 'cat10_my_new_check'
    for flow in flows:
        for vendor, tool, tdir in _tool_dirs_for(pd_dir, flow):
            scope = f'{flow}/{vendor}/{tool}'
            ...
            if bad_thing:
                results.failed(suite, category, f'{scope}: bad thing',
                               'detail message')
            else:
                results.passed(suite, category, f'{scope}: bad thing absent')

CATEGORIES = {
    ...
    10: ('My New Check', cat10_my_new_check),
}
```

Run with `cbflow test --static --category 10`.

---

## 10. Adding a new e2e check

1. Open `PD/utils/commands/test_suite/e2e_checks.py`
2. Add a function `def e2eN_my_check(run_dir): ...` returning `(status, detail)` where status is `'PASS' | 'FAIL' | 'SKIP'`
3. Register in the `CHECKS` list

Example:

```python
def e2e19_my_new_check(run_dir):
    """Validate the new invariant."""
    work = os.path.join(run_dir, 'work')
    if not os.path.isdir(work):
        return 'SKIP', 'no work/'
    # ... checks ...
    if violated:
        return 'FAIL', 'detail about violation'
    return 'PASS', f'invariant holds: <metric>'

CHECKS = [
    ...
    ('e2e19_my_new_check', e2e19_my_new_check, False),
]
```

The third tuple element is `True` if the check needs `pd_dir` as the first arg (most don't).

Pseudo-stages and dynamic-subnode stages are skipped automatically via `_stage_dirs(skip_pseudo=True, skip_dynamic=True)` — you can opt back in by passing `False`.

---

## 11. CI integration

### Jenkins

```groovy
stage('CBflow test suite') {
  steps {
    sh '''
      ./PD/bin/cbflow test --ci --report cbflow-test.json
    '''
    junit 'cbflow-junit.xml'
    archiveArtifacts 'cbflow-test.json'
  }
}
```

### GitHub Actions

```yaml
- name: Run CBflow test suite
  run: ./PD/bin/cbflow test --ci --report cbflow-test.json

- uses: mikepenz/action-junit-report@v4
  if: success() || failure()
  with:
    report_paths: cbflow-junit.xml
```

### GitLab CI

```yaml
test:
  script:
    - ./PD/bin/cbflow test --ci --report cbflow-test.json
  artifacts:
    when: always
    reports:
      junit: cbflow-junit.xml
    paths:
      - cbflow-test.json
```

In all cases, `--ci` produces non-zero exit on failure so the pipeline fails appropriately.

---

## 12. The pseudo-stage / dynamic-subnode allowlist

In `e2e_checks.py`:

```python
_INPUT_PSEUDO_STAGES = frozenset({
    'rtl1', 'sdc1', 'upf1', 'def1', 'netlist1', 'library1',
    'spef1', 'gds1', 'lib1', 'constraints1',
    'netlist_golden1', 'netlist_revised1',
    'power_spec1',
})

_DYNAMIC_SUBNODE_STAGES = frozenset({
    'timing1', 'extraction1',
})
```

**Input pseudo-stages** are bundled into `inputs_<tool>.tcl` rather than getting their own runtime artifacts. The checks `e2e12_runtime_tcl_generated`, `e2e13_each_subnode_logged`, `e2e14_outputs_dir_nonempty` skip these so they don't false-positive.

**Dynamic-subnode stages** spawn one subnode per MMMC scenario (STA timing per corner, STA extraction per RC corner). Their artifact layout is `<scenario>_run.log` per subnode, not `<node>_run.log` — different lifecycle, also skipped from the per-subnode checks.

To add a new pseudo-stage or dynamic stage, edit those sets.
