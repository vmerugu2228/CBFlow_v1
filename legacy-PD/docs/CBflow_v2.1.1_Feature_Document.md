# CBflow v2.1.1 — Physical Design Automation Framework

**Feature Document**

**Classification: Internal**

**Version: 2.1.1**

**Release Date: 2026-06-12**

---

## What's new in v2.1.1

v2.1.1 is a quality + observability release on top of v2.1.0:

- **Per-user Dashboard Daemon** — one HTTP server per user (not per run); stable URL across all runs; in-browser register/deregister UI
- **`cbflow test`** — built-in static + e2e test suite (10 static check categories, 18 e2e checks per flow); replaces `cbflow-test-suite` shim
- **Dead-code audit (static cat 9)** — catches the specific bug classes we kept hitting: flow_proc-as-Tcl-command, brace imbalance, no-dispatch, dead-code-after-exit, undefined `$flow_dir`, STAGE_NAME mismatches
- **Elaborate e2e checks** — every registered flow_proc must execute, no `invalid command name`, no `TEST_CMD: exit` fallthrough, runtime `.tcl` generated per stage, all 4 subnode logs present, no handler errors
- **Code-quality fixes** — ~250 files touched, ~1000+ individual fix points (see "Hardening pass" below)
- **FP template** added (`uc_FP_fc.tcl`, `uc_FP_innovus.tcl`) — closes a long-standing gap
- **Test-mode dummy outputs** for release_data, reporting, extraction, timing, power_spec, drc/lvs/fill/erc/perc/xor (e2e suite in test_mode now has real artifacts to validate against)

---

## Table of Contents

1. [Per-user Dashboard Daemon](#1-per-user-dashboard-daemon)
2. [`cbflow test` — built-in test suite](#2-cbflow-test-built-in-test-suite)
3. [Static Cat 9 — Dead-code & cross-reference audit](#3-static-cat-9-dead-code-cross-reference-audit)
4. [E2E corner checks](#4-e2e-corner-checks)
5. [FP user-config templates](#5-fp-user-config-templates)
6. [Hardening pass — bug classes fixed](#6-hardening-pass-bug-classes-fixed)
7. [Upgrade notes](#7-upgrade-notes)
8. [Compatibility](#8-compatibility)

---

## 1. Per-user Dashboard Daemon

### Problem solved

In v2.1.0, every `cbflow run gui` spawned a fresh foreground HTTP server. With 5-10 active runs per user this produced:

- "Port already in use" race between `_is_port_free()` and `HTTPServer()`
- "Firefox already running, but is not responding" from repeated `firefox -new-tab URL` Popen calls
- 10 active runs = 10 server processes, 10 file watchers, 10 browser tabs

### v2.1.1 model

- **One per-user daemon process**, deterministic port `9000 + (uid % 1000)`
- All runs register with the daemon; UI presents deep-links per run
- Daemon outlives shells; auto-starts on first `cbflow run gui` (now defaults to daemon mode)
- AF_UNIX control socket for IPC (mode 0600, kernel-enforced uid)
- HTTP server binds `127.0.0.1` only (SSH-tunnel flow unchanged: `ssh -L PORT:localhost:PORT host`)
- O_EXCL pidfile guarantees single-instance per user

### State layout

```
~/.cbflow/dashboard/
  dashboard.pid          # atomic O_EXCL on start
  dashboard.port
  dashboard.start_ts     # PID-recycling identity check
  dashboard.log          # size-rotated
  runs/<run_id>.json     # one file per registered run
  control.sock           # AF_UNIX mode 0600
  last_open.json         # 5-sec browser-launch dedup
```

Run ID = `md5(canonical_run_dir)[:12]`. Stable across restarts.

### CLI surface

```
cbflow dashboard start [--port N] [--foreground]
cbflow dashboard stop
cbflow dashboard restart
cbflow dashboard status            # exit 0 running, 3 stopped, 4 stale
cbflow dashboard open [<run>]      # SSH-aware (skips browser, prints ssh -L hint)
cbflow dashboard logs [--follow]
cbflow dashboard list
cbflow dashboard register <run_dir>
cbflow dashboard deregister <run-or-id>

cbflow run gui                     # NEW DEFAULT: daemon path
cbflow run gui --no-browser        # register, print URL, skip browser
cbflow run gui --foreground        # legacy per-run server (back-compat)
```

### Web UI

- **Banner**: project chips, active/archived/projects/designs/pid/port tiles, RACE engine pill, "Developed by SmartSoc"
- **Register form**: paste any run directory or click **Browse** to expand a filterable picker of all discovered runs (scanned from each project's `workarea_path`)
- **Runs table**: color-coded flow badges, relative timestamps, per-row Deregister buttons, live search filter, 5-second auto-poll
- **Deep-links** to per-run dashboard: `/run/<id>/...`
- **Daemon-level endpoints**: `/api/runs`, `/api/register` (POST), `/api/deregister` (POST), `/api/daemon-status`, `/api/discover-runs`

### Stale-state recovery

Three-level check on every start:

1. `os.kill(pid, 0)` — pid liveness
2. `start_ts` identity check (Linux: `/proc/<pid>/stat` field 22; macOS: `ps -o lstart=`)
3. Port-liveness probe

Any stale state is logged + replaced.

### Phase 2 default flip

In v2.1.0, `cbflow run gui` ran a per-run foreground server.
In v2.1.1, **default behavior is daemon-mode registration**. Pass `--foreground` to opt back into the legacy path. Passing `--port` without `--foreground` errors with a pointer to `cbflow dashboard start --port N`.

`cbflow run clean --confirm` now also deregisters the run from the daemon (best-effort; silent if daemon is down).

---

## 2. `cbflow test` — built-in test suite

### CLI

```
cbflow test                            # static + e2e on all 12 flows
cbflow test --static                   # cat 1-9 only
cbflow test --e2e                      # e2e only, all flows
cbflow test --flow SYNTH_PNR           # one flow
cbflow test --flows SYNTH,PNR,STA      # subset
cbflow test --category 9               # one static category
cbflow test --vendor synopsys          # prefer synopsys fixture variant
cbflow test --timeout 600
cbflow test --keep | --keep-on-fail (default) | --clean-on-fail
cbflow test --report results.json      # machine-readable
cbflow test --junit junit.xml          # CI report
cbflow test --ci                       # plain console + junit + non-zero exit
cbflow test --list
```

`cbflow-test-suite` is now a 20-line back-compat shim that calls `cbflow test --static`.

### Module layout

```
PD/utils/commands/test_cmd.py
PD/utils/commands/test_suite/
  __init__.py
  results.py          # shared collector
  static_checks.py    # cats 1-9 (10 checks in cat 9)
  fixtures.py         # picks workarea_test/uc_*.tcl, rewrites run_name
  sandbox.py          # tempdir + run-dir lifecycle
  e2e_runner.py       # cbflow workspace create + cbflow run all subprocess driver
  e2e_checks.py       # 18 per-run verifications
  reporters.py        # console, JSON, JUnit XML
```

### Static categories (cats 1-9)

| Cat | Title | Purpose |
|---|---|---|
| 1 | Workspace & Run Creation | node_configs exist, stages defined, dependencies wired, runtime timeouts |
| 2 | Makefile & Handler Validation | every stage has a cmd file or handler; input pseudo-stages bundled into `inputs_<tool>.tcl` accepted |
| 3 | Override Setup & Config | setup.tcl hook, override_setup, config.tcl sourcing |
| 4 | LSF Management | `lsf(tool_shell,<tool>)`, `lsf(flow_mapping,<flow>,<stage>)`, queue tiers, `bsub,queue`/`bsub,project` |
| 5 | MMMC Config & Scenarios | per-project mmmc_config.tcl, `mmmc_manager_cmd.py`, MCMM markers in init_design_fc.tcl, per-tech library data |
| 6 | Mandatory I/O & Validation | flow's release_types, release_config.tcl entries, release_utils procs, resolve_inputs coverage |
| 7 | Log Parsing & Error Halt | `log_viewer.py`, `flow_exec_all` coverage, exit milestones |
| 8 | Cross-Cutting | no `$::run_dir` bugs, no `FCT`/`PHYV` references, completion scripts |
| 9 | **Dead-Code & Cross-Reference Audit** | see next section |

### E2E suite (18 checks × 12 flows)

| Check | What it validates |
|---|---|
| `e2e1_run_dir_structure` | `.run.cbflow.env` + `work/` directory |
| `e2e2_db_initialized` | SQLite DB created with `jobs`, `run_info`, `dag_structure` tables |
| `e2e3_config_resolved` | Resolved `config.tcl` files have no `???` placeholders |
| `e2e4_dag_populated` | `dag_structure` table has rows |
| `e2e5_all_stages_terminal_ok` | Every stage reached `DONE`/`BYPASSED`/`FORCE_VALIDATED` |
| `e2e6_stage_metrics_populated` | `stage_metrics` table populated |
| `e2e7_logs_captured` | `.log` files in every stage's run dir |
| `e2e8_run_status_command` | `cbflow run status` returns 0 |
| `e2e9_no_invalid_command` | No `invalid command name "..."` in any log (catches flow_proc-as-Tcl-command bugs) |
| `e2e10_flow_procs_executed` | Every registered flow_proc actually ran |
| `e2e11_no_test_mode_fallthrough` | No `TEST_CMD: exit N (intercepted)` followed by `can't read` |
| `e2e12_runtime_tcl_generated` | Per-node `<node>.<tool>.tcl` exists in `run/` (or launch wrapper + run log) |
| `e2e13_each_subnode_logged` | All 4 subnode logs present (`*_setup.log`, `*_run.log`, `*_validate.log`, `*_finish.log`) |
| `e2e14_outputs_dir_nonempty` | Each stage's `outputs/` has at least one file |
| `e2e15_config_no_unresolved` | All `config.tcl` files have no `???` or `${unresolved}` tokens |
| `e2e16_no_array_element_missing` | No "no such element in array" errors |
| `e2e17_db_run_logs_table` | `run_logs` table populated |
| `e2e18_no_handler_errors` | No "Command file not found", "Cannot find generated config", "Unknown subnode", "Flow procedure not found" |

Input pseudo-stages (`rtl1`, `sdc1`, `upf1`, `def1`, `netlist1`, `library1`, `power_spec1`, etc.) and dynamic-subnode stages (`timing1`, `extraction1`) are allowlisted where appropriate so checks don't false-positive.

---

## 3. Static Cat 9 — Dead-code & cross-reference audit

10 checks targeting the exact bug classes that bit us in v2.1.0:

1. **Subnode-handler → cmd-file integrity** — resolve `set cmd_file "..."` line and verify path exists; compare target's `STAGE_NAME` against handler's `stage_name`
2. **Cmd-file STAGE_NAME ↔ filename** — `STAGE_NAME "X"` must match filename `<X>_<tool>.tcl`
3. **Undefined `$flow_dir`** — regex `\$flow_dir(?!\w)` (not `$::env(FLOW_DIR)`)
4. **Dead `if-source-puts-exit` fall-through** — pattern matching `if {[file exists ...]} { source ... ; puts "ERROR..." ; exit 1; <next> }` without `else`
5. **Cmd-file stage ∈ flow's stage list** — orphan files whose stage isn't in the flow config (SKIP, not FAIL; synthetic stages like `inputs`, `validate` allowlisted)
6. **Header comment vs filesystem location** — `# FP …` in a `cmds/FCFP/` file
7. **`foreach step { … } { catch {$step} … }`** — flow_proc names invoked as Tcl commands (the FP `generate_globals` bug)
8. **`handle_error; exit N` followed by `$arr(key)` read** — test_mode intercepts exit; dead code after it runs
9. **flow_procs defined but no `flow_exec_all` / `flow_exec NAME` dispatch** — procs registered, never run
10. **Unbalanced `{` and `}`** — broken Tcl syntax; often traps `flow_exec_all` inside an unclosed proc body

Known intentional aliases: `timing_scenario_*.tcl` files set `STAGE_NAME "timing"` (MMMC per-scenario template); allowlisted via `_STAGE_NAME_ALIASES`.

---

## 4. E2E corner checks

The e2e suite previously had 8 binary checks. v2.1.1 adds 10 more (above) that target *specific* failure modes we've hit:

- **Tcl interpreter errors** masked by `flow_exec_all`'s catch — surfaced by `e2e9`, `e2e16`
- **flow_procs registered but never dispatched** — surfaced by `e2e10`
- **`exit` intercepted in test_mode → dead code crashes** — surfaced by `e2e11`
- **Subnode handler bugs** producing partial logs — surfaced by `e2e13`
- **Empty `outputs/` directories** (broken stage contracts) — surfaced by `e2e14`
- **Handler-level errors** like "Command file not found" — surfaced by `e2e18` (this catches the bug ajay hit in v2.1.0)

---

## 5. FP user-config templates

`PD/config/templates/` previously had `uc_<FLOW>_<tool>.tcl` for every flow except **FP**. v2.1.1 adds:

- `uc_FP_fc.tcl` — Synopsys Fusion Compiler (default for FP)
- `uc_FP_innovus.tcl` — Cadence Innovus (explicit `fp(tool,name) "innovus"`)

Both follow the same structure as `uc_PNR_fc.tcl` / `uc_PNR_innovus.tcl` (project / flow / tool / execution / inputs sections with `<project_name>` / `<design_name>` / `<run_name>` placeholders).

---

## 6. Hardening pass — bug classes fixed

The cat 9 / e2e checks found these in v2.1.0; v2.1.1 fixes them all:

| Bug class | Files | Fix |
|---|---|---|
| `foreach step { ... } { catch {$step} ... }` — flow_proc as Tcl command | 6 (FP/cadence/innovus + PNR/cadence/innovus/cts_innovus.tcl) | Replaced block with `flow_exec_all` |
| `source -e $file` (invalid Tcl option) | 37 / 179 occurrences | `source -e ` → `source ` |
| `if {[info exists X] && $X}` where `$X=""` → "expected boolean" | 23 / 75 occurrences | Wrapped with `string is true -strict` |
| `handle_error; exit 1` (dead-code-after-exit in test_mode) | 15 / 39 occurrences | `exit 1` → `return` inside flow_procs |
| Brace imbalance (unclosed proc bodies) | 12 | Auto-fixer: insert `}` before each subsequent `flow_proc` at depth > 0 |
| flow_procs defined, no `flow_exec_all` dispatch | 10 | Added `flow_exec_all` before final `exit` |
| Missing `flow` / `tech` / `project` in `global` declarations | 14 / 63 procs | Bulk-added based on body usage |
| `$project(release,tag)` unguarded read in `handle_info` | 20 | Wrapped with `[info exists]` |
| `clock format [clock seconds]` failing without TZData | 107 / 210 expressions | `catch` + fallback to `epoch N` |
| `$flow_dir` (undefined) | 1 | `$flow_dir` → `$::env(FLOW_DIR)` |
| `STAGE_NAME` mismatches (PNR copy-paste residue) | 4 | SYNTH/cadence/genus + PNR/cadence/innovus renames |
| Missing `source release_utils.tcl` in release_data files | 20 | Added bootstrap |
| `::CBFlow::Release::init` hard-errored in test_mode | release_utils.tcl | Test-mode-friendly defaults (placeholder values) |
| Runtime tool path hardcoded `cadence/` vendor + `node_type` (with `1`) instead of stage_name | `generate_setup.tcl` | Vendor map per tool; `[regsub {[0-9]+$} $node_type ""]` for stage_name |
| FP `generate_globals` silently skipped cell LEFs when `tech(<trk>,lef)` missing | `init_design_innovus.tcl` | Loud `handle_warning` + per-Vt fallback aggregator; also detects `//` in tech LEF paths and multi-entry `lef_tech` lists |
| Test-mode dummy outputs missing for several stages | `launch_utils.tcl` | Added cases for release_data, reporting, extraction, timing, power_spec, drc/lvs/fill/erc/perc/xor/merge_data |

Total: ~250 files touched, ~1000+ individual fix points.

---

## 7. Upgrade notes

### From v2.1.0

1. **Existing per-run dashboards** keep working via `cbflow run gui --foreground`. Default flips to daemon mode — most users will want the new default.
2. **`cbflow-test-suite`** still works (it's a thin shim now). New CI/CD should use `cbflow test --static --ci` for JUnit output.
3. **No config changes required** — all the hardening fixes are in cmd files and utilities; tech/project configs untouched.
4. **One state directory added**: `~/.cbflow/dashboard/` (auto-created, mode 0700). No global state.

### Smoke test after install

```
cbflow dashboard status                          # expect: stopped
cbflow workspace create --config workarea_test/uc_SYNTH.tcl --force
cd P0_run_SYNTH_test1
cbflow run all                                   # ~10s in test_mode
cbflow run gui --no-browser                      # daemon starts, run registers
cbflow dashboard list                            # 1 active
cbflow test --static                             # expect ALL PASS (1269/0/80)
cbflow test --e2e --flow SYNTH                   # expect ALL PASS
```

### What to send to users

The bundle `CBflow_v2.1.1_20260612.tar.gz` is a drop-in replacement for v2.1.0. Extraction keeps the `CBflow_v2.1.0/` dir name from earlier deployments untouched if they use the bundle's `CBflow_v2.1.1/` prefix; ops can rsync or symlink as they prefer.

---

## 8. Compatibility

- **OS**: macOS (darwin) tested through development; Linux (RHEL/CentOS/Ubuntu) tested on production-style remote machines (ajay's `desktop0.aus5.mythic-ai.com`)
- **Python**: 3.10+ (uses stdlib only — `http.server`, `sqlite3`, `socket`, `threading`)
- **Tcl**: 8.6+ (init_design and generate_globals require `regsub`, `string is true -strict`, `clock format -format`)
- **Browsers**: Chrome / Chromium / Firefox / xdg-open / `open` (macOS); daemon URL is stable across runs so browsers reuse existing tabs
- **EDA tools**: same matrix as v2.1.0 (Fusion Compiler, PrimeTime, Formality, ICV, RedHawk, VC_LP, Genus, Innovus, Tempus, Conformal LP, Voltus, Calibre)
- **CI**: `cbflow test --ci` produces JUnit XML + non-zero exit; drop-in for Jenkins/GitLab/GitHub Actions
