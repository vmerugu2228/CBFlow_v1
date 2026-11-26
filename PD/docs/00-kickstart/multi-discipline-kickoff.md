# Kickoff — Multi-Discipline CBflow

CBflow v2.0.0 (`cbflow_global` branch) supports four disciplines side by
side: **PD** (Physical Design), **DFT** (Design-For-Test), **DV** (RTL
Design Verification) and **RTL** (design-side quality: spec, lint, CDC, RDC, UPF). This document is the fastest path from a fresh
checkout to running your first flow.

---

## 1. Repository layout at a glance

```
CBflow_clone/                             $CBFLOW_ROOT
├── bin/cbflow                            Top-level entry (symlink → global/bin/cbflow)
├── global/                               Cross-discipline configs + launcher
├── PD/                                   Physical Design
├── DFT/                                  Design-For-Test
├── DV/                                   RTL Design Verification
└── RTL/                                  RTL design quality (RTL_SPEC, RTL_LINT, RTL_CDC, RTL_RDC, UPF_CHECK)
```

Every discipline has the same shape: `bin/`, `config/`, `cmds/`, `utils/`.
The shared `global/` layer holds anything that isn't discipline-specific —
tech identity, project hierarchy, MMMC scenarios, and the flow catalog.

## 2. Environment — one variable

**`CBFLOW_ROOT` is the only user-facing env var.** Everything else is
auto-derived by the launcher.

```bash
# Most installs need nothing — the launcher discovers the root from its
# own location. But if you're calling from a non-standard install:
export CBFLOW_ROOT=/path/to/CBflow_clone
```

Auto-derived from `CBFLOW_ROOT`:

| Variable | Auto-value | Purpose |
|---|---|---|
| `CBFLOW_CORE_DIR` | `$CBFLOW_ROOT/PD` | PD discipline root |
| `CBFLOW_GLOBAL_DIR` | `$CBFLOW_ROOT/global` | Cross-domain config layer |
| `CBFLOW_DFT_DIR` | `$CBFLOW_ROOT/DFT` | Only exported if directory exists |
| `CBFLOW_DV_DIR` | `$CBFLOW_ROOT/DV` | Only exported if directory exists |
| `CBFLOW_RTL_DIR` | `$CBFLOW_ROOT/RTL` | Only exported if directory exists |

**Note:** `CBFLOW_ROOT` is the umbrella anchor, NOT `CBFLOW_GLOBAL_DIR`.
`global/` sits *inside* the root, alongside every discipline directory.

To see what got resolved:
```bash
bin/cbflow --version
```

Output includes:
```
  Installation Root (CBFLOW_ROOT):  /Users/vmerugu/projects/CBflow_clone
  Global config     (CBFLOW_GLOBAL_DIR): .../global
  PD  (CBFLOW_CORE_DIR):            .../PD
  DFT (CBFLOW_DFT_DIR):             .../DFT
  DV  (CBFLOW_DV_DIR):              .../DV
```

And the banner shows the discipline roster (`[+]` = directory exists,
`[-]` = registered in flow_registry but not scaffolded yet).

## 3. Launcher composition

There are four launcher entry points, each for a specific scope:

| Launcher | Owns | Falls through to |
|---|---|---|
| `bin/cbflow` (→ `global/bin/cbflow`) | cross-domain: workspace, run, bundle, migrate, test, flow types/info/stages/check, flow project, flow release, flow metrics, flow dashboard | (none — this is the umbrella) |
| `PD/bin/cbflow-pd` | `flow library-manager`, `flow mmmc-manager`, `flow checklist` | `bin/cbflow` |
| `DFT/bin/cbflow-dft` | (empty — extension point) | `bin/cbflow` |
| `DV/bin/cbflow-dv` | (empty — extension point) | `bin/cbflow` |
| `RTL/bin/cbflow-rtl` | (empty — extension point) | `bin/cbflow` |

**Auto-dispatch:** typing `cbflow flow library-manager …` from anywhere
transparently forwards to `PD/bin/cbflow-pd`. The subcommand → discipline
map lives at `global/config/cli/discipline_commands.tcl`.

Both forms produce the same result:

```bash
# Auto-dispatched (recommended — one command surface)
bin/cbflow flow library-manager status --tech skywater_130nm --lib_tag OSS2

# Directly invoked
PD/bin/cbflow-pd flow library-manager status --tech skywater_130nm --lib_tag OSS2
```

## 4. Kicking off a run — the standard flow

Same shape as before the refactor, only the launcher changed:

```bash
# 1. Go to the workarea for your design (project(workarea_path)/<block>)
cd $CBFLOW_ROOT/workarea/gcd/

# 2. Generate a template user_config for the flow you want
bin/cbflow workspace template --flow SYNTH > user_config.tcl

# 3. Edit the template (RTL / SDC / UPF paths, tool selection, phase)
vi user_config.tcl

# 4. Create the run — this validates, builds the DAG, initializes the
#    RACE DB, drops .race_db_pointer, generates .run.cbflow.tcl
bin/cbflow workspace create --config user_config.tcl

# 5. cd into the run directory (<phase>_run_<FLOW>_<block>_<run>) and execute
cd P1_run_SYNTH_gcd_run1
bin/cbflow run all

# 6. Check status
bin/cbflow run status --details
bin/cbflow run gui                # opens web dashboard
```

## 5. Config cascade — where variables come from

Every run resolves configs in this fixed order. If you're reading a
`config.tcl` at `work/<FLOW>/<node>/run/`, this is what it sourced:

1. `global/config/project/<proj>/v1.0.0/<proj>_config.tcl` — identity + hierarchy + `project(phases)` / `project(phase_exits)`
2. `<disc>/config/project/<proj>/v1.0.0/<proj>_<disc>_config.tcl` — discipline overlays, own discipline last
   (PD: `<proj>_pd_config.tcl` — workarea, release, LSF, `lib_root`, `lib_tag_root`, `lib_config_tag`)
3. `global/config/tech/<tech>/v1.0.0/tech_config.tcl` — one tech file (foundry data, metal stacks, physical cells);
   it sources the library tag's `lib_config.tcl` / `blocks_config.tcl` from `<lib_tag_root>/<tech>/<TAG>/`
4. `global/config/flow/v1.0.0/flow_registry.tcl` — flow catalog + discipline map + cross-domain runtime defaults
5. `<discipline>/config/flow/v1.0.0/flow_config.tcl` — routed by `flow(discipline,$flow_type)`
6. `<discipline>/config/flow/v1.0.0/node_configs/<FLOW>_config.tcl` (+ `<FLOW>_<tool>_config.tcl` from `<flow>(tool,name)`)
7. `global/config/project/<proj>/v1.0.0/mmmc_config.tcl` — MMMC PVT building blocks
8. `<run>/setup/user_config.tcl` — user overrides
9. `<run>/setup/override_config.tcl` → `.<stage>` → `.<branch>` → `.<node_type>` → `.<node>` (last writer wins)

Project is sourced first because tech references `$project(lib_root)`. (The former
`PD/config/tech/<tech>/…/tech_pd_config.tcl` overlay is merged into the single tech file.)

## 6. RACE DB — created at workspace-create time

Every run has a SQLite status DB. As of `cbflow_global`, the DB is
created **at workspace-create time**, not lazily on first `run all`. If
DB creation fails, `workspace create` errors out and removes the partial
run dir — no silent half-runs.

- **DB location:** `.race_area/<project>/PD/<flow>/<run_dir_name>_<user>_<hash>.db`
- **Pointer file:** `<run_dir>/.race_db_pointer` contains the absolute path
- **Naming:** always includes username (`_vmerugu_`) for multi-user areas

## 7. Adding a new discipline command

To add, say, `flow scan-debug` under DFT:

```
1. Add to global/config/cli/discipline_commands.tcl:
     set cli(discipline,scan-debug) "DFT"

2. Add to DFT/bin/cbflow-dft's DFT_FLOW_SUBCOMMANDS array:
     DFT_FLOW_SUBCOMMANDS=(scan-debug)

3. Add a case in the launcher's dispatcher:
     case "$subcmd" in
         scan-debug) exec python3 "$CBFLOW_DFT_DIR/utils/commands/scan_debug_cmd.py" "$@" ;;
     esac

4. Drop the Python handler at DFT/utils/commands/scan_debug_cmd.py
```

Now `cbflow flow scan-debug …` auto-dispatches to DFT, `PD/bin/cbflow-pd
flow scan-debug …` errors ("not owned by PD"), and cross-domain
subcommands like `cbflow workspace` and `cbflow run` remain unaffected.

## 8. Launch mode — controlling how EDA tools run

Every stage's `run` subnode picks one of three launch paths, controlled by
three booleans in `user_config.tcl`:

```tcl
set flow(test_mode) "false"    # real EDA tools invoked
set flow(use_lsf)   "false"    # local exec (no bsub)
set flow(use_xterm) "true"     # xterm window per stage
```

Defaults come from `global/config/flow/v1.0.0/flow_registry.tcl` — you can
leave all three unset in user_config and get real-EDA, local-exec, xterm-on.

### Common configurations

```tcl
# ── Local exec, real tools, no batch, no GUI ───────────────────────────
set flow(test_mode) "false"
set flow(use_lsf)   "false"
set flow(use_xterm) "false"

# ── Production with LSF batch submission ───────────────────────────────
set flow(test_mode) "false"
set flow(use_lsf)   "true"        # requires bsub in PATH
set flow(use_xterm) "false"       # bsub -Is if use_xterm=true (interactive)

# ── Dry-run / test mode ────────────────────────────────────────────────
set flow(test_mode) "true"        # skip EDA entirely, fabricate outputs
```

### Env-var overrides (for CI / non-persistent config)

```bash
export CBFLOW_USE_LSF=1
export CBFLOW_USE_XTERM=0
export CBFLOW_BSUB_CMD=/site/tools/my-bsub    # override bsub path
```

Precedence (highest first): `CBFLOW_BSUB_CMD` → user_config → env var.

### Silent test-mode fallthrough — the layered defense

Before `2026-09-29`, if `flow(use_xterm)="true"` but `xterm` or `$DISPLAY`
was missing, `submit_job` did `exec xterm ... &` — fire-and-forget. The
handler saw success (fork worked), moved on. Every stage marked DONE with
empty outputs. Same silent-success shape existed for `flow(use_lsf)="true"`
with missing `bsub`.

Three independent gates now prevent this:

1. **Pre-flight at `workspace create`** — fails immediately if `use_lsf=true`
   but `bsub` missing, or `use_xterm=true` but `xterm` missing. Prints a
   clear message, cleans up the partial run directory.

2. **Runtime sync-exec** in `launch_utils.tcl::submit_job` — xterm now runs
   synchronously (no `&`), `$DISPLAY` is checked, wrapper executability is
   verified. Non-zero exit surfaces as a stage failure.

3. **Post-run validation** — `handler_validate` in production mode enforces
   `mandatory_outputs` exists+non-empty AND `outputs/` has ≥1 file. Catches
   tools that return exit 0 without producing artifacts (license unavailable,
   warnings-only failure).

Test-mode (`flow(test_mode)="true"`) short-circuits before any of these gates,
so the test suite is unaffected.

### Diagnostic — inspect a production run

```bash
RUN_DIR=/path/to/P0_run_<FLOW>_<name>

# 1. Confirm test_mode is actually false at run time
grep 'flow(test_mode)' $RUN_DIR/work/*/*/run/config.tcl 2>/dev/null | head

# 2. Confirm handlers took the production branch (no "[TEST MODE]" markers)
grep -c "\[TEST MODE\]" $RUN_DIR/work/*/*/run/*.log 2>/dev/null | grep -v ":0$"

# 3. Real tool wrapper generated
find $RUN_DIR/work -name "launch_*.csh" | head

# 4. Every execution stage produced non-empty outputs/
find $RUN_DIR/work -name outputs -type d -exec sh -c 'echo "$1: $(ls $1 | wc -l) files"' _ {} \;

# 5. No stub files
grep -rl "TEST_MODE stub" $RUN_DIR/work 2>/dev/null

# 6. LSF / xterm availability if enabled
USE_LSF=$(grep 'flow(use_lsf)' $RUN_DIR/setup/user_config.tcl | grep -oE 'true|false' | head -1)
[ "$USE_LSF" = "true" ] && command -v bsub >/dev/null || echo "  bsub → NOT FOUND"
```

## 9. Test suite — verify your install

```bash
bin/cbflow test --static           # static config checks
bin/cbflow test --e2e              # every flow × project fixture in test_mode
bin/cbflow test --e2e --flow STA   # single flow
```

Every job in every runnable fixture should reach exit-0. In test_mode
(the default for e2e), EDA tools are bypassed and handlers produce
placeholder outputs.

## 10. Where to look next

- **CLAUDE.md** at repo root — canonical architecture summary
- **RELEASE_NOTES.md** — what changed in this release
- **PD/docs/02-user-guide/** — deeper user documentation
- **PD/docs/03-reference/** — reference material
- **PD/docs/04-architecture/** — engine / DAG / dashboard design docs
- **PD/docs/02-user-guide/exit-release-guide.md** — per-discipline exit plans and releases
- **PD/docs/02-user-guide/opensource-flow-guide.md** — the open-source sky130 flow (project `opensky`)
