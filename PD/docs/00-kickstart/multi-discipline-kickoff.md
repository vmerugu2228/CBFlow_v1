# Kickoff — Multi-Discipline CBflow

CBflow v2.0.0 (`cbflow_global` branch) supports three disciplines side by
side: **PD** (Physical Design), **DFT** (Design-For-Test), and **DV** (RTL
Design Verification). This document is the fastest path from a fresh
checkout to running your first flow.

---

## 1. Repository layout at a glance

```
CBflow_clone/                             $CBFLOW_ROOT
├── bin/cbflow                            Top-level entry (symlink → global/bin/cbflow)
├── global/                               Cross-discipline configs + launcher
├── PD/                                   Physical Design
├── DFT/                                  Design-For-Test
└── DV/                                   RTL Design Verification
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

**Auto-dispatch:** typing `cbflow flow library-manager …` from anywhere
transparently forwards to `PD/bin/cbflow-pd`. The subcommand → discipline
map lives at `global/config/cli/discipline_commands.tcl`.

Both forms produce the same result:

```bash
# Auto-dispatched (recommended — one command surface)
bin/cbflow flow library-manager status --tech gf_22nm

# Directly invoked
PD/bin/cbflow-pd flow library-manager status --tech gf_22nm
```

## 4. Kicking off a run — the standard flow

Same shape as before the refactor, only the launcher changed:

```bash
# 1. Go to the workarea for your design
cd /path/to/workarea/<design_name>/

# 2. Generate a template user_config for the flow you want
bin/cbflow workspace template --flow SYNTH_PNR > user_config.tcl

# 3. Edit the template (RTL / SDC / UPF paths, tool selection, phase)
vi user_config.tcl

# 4. Create the run — this validates, builds the DAG, initializes the
#    RACE DB, drops .race_db_pointer, generates .run.cbflow.tcl
bin/cbflow workspace create --config user_config.tcl

# 5. cd into the run directory and execute
cd LC1_run_SYNTH_PNR_run1
bin/cbflow run all

# 6. Check status
bin/cbflow run status --details
bin/cbflow run gui                # opens web dashboard
```

## 5. Config cascade — where variables come from

Every run resolves configs in this fixed order. If you're reading a
`config.tcl` at `work/<FLOW>/<node>/run/`, this is what it sourced:

1. `global/config/project/<proj>/v1.0.0/project_config.tcl` — identity + hierarchy
2. `PD/config/project/<proj>/v1.0.0/project_pd_config.tcl` — PD overlay (workarea, release, LSF, lib_root)
3. `global/config/tech/<tech>/v1.0.0/tech_config.tcl` — foundry data (identity + VT + rules + SPICE + RCX)
4. `PD/config/tech/<tech>/v1.0.0/tech_pd_config.tcl` — PD overlay (metal stacks, physical cells, body bias)
5. `global/config/flow/v1.0.0/flow_registry.tcl` — flow catalog + discipline map + cross-domain runtime defaults
6. `<discipline>/config/flow/v1.0.0/flow_config.tcl` — routed by `flow(discipline,$flow_type)`
7. `<discipline>/config/flow/v1.0.0/node_configs/<FLOW>_config.tcl`
8. `global/config/project/<proj>/v1.0.0/mmmc_config.tcl` — MMMC PVT building blocks
9. `<run>/setup/user_config.tcl` — user overrides (last writer wins)

Project is sourced first because tech references `$project(lib_root)`.

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
two booleans in `user_config.tcl`:

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
bin/cbflow test --static           # ~1s, 1338 checks across 16 categories
bin/cbflow test --e2e              # ~10 min, 419 checks across every flow×project fixture
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

For the config-cascade reasoning + config-split rationale, see the
project memory at
`~/.claude/projects/-Users-vmerugu-projects-CBflow-clone/memory/`.
