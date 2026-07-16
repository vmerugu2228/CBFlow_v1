# CBflow Kickstart Guide

**Copy to Unix, set PATH, run your first flow in 5 minutes.**

---

## 1. Copy to Unix

```bash
# Copy CBflow to your Unix/Linux machine
scp -r CBflow_clone/PD user@server:/opt/cbflow
# OR
rsync -avz CBflow_clone/PD user@server:/opt/cbflow
```

## 2. Set Environment

**Bash** (`~/.bashrc` or `~/.bash_profile`):
```bash
export CBFLOW_HOME=/opt/cbflow
export PATH=$CBFLOW_HOME/bin:$PATH

# Tab completion (bash)
source $CBFLOW_HOME/completions/cbflow.bash
```

**C-Shell** (`~/.cshrc` or `~/.tcshrc`):
```csh
setenv CBFLOW_HOME /opt/cbflow
set path = ($CBFLOW_HOME/bin $path)
```

**Verify:**
```bash
cbflow --version
```

## 3. Configure Project

Edit your project config (`config/project/<name>/v1.0.0/<name>_config.tcl`):

```tcl
set project(name)               "my_chip"
set project(cbflow_release)     "v1.0.0"
set project(release,path)       "/proj/my_chip/releases"
set project(release,phase)      "P0"
set project(release,block_name) "top"
set project(release,tag)        "v1.0.0"
```

## 3b. Metal Stack Configuration

Set the metal stack in your project config to auto-resolve routing layers, TLU+ files, and PG strap definitions:

```tcl
# In project_config.tcl:
set project(metal_stack) "gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB"
```

Available stacks: 8M, 9M, 10M, 11M. Everything auto-resolves (routing layers, TLU+, PG straps) based on the selected stack.

## 3c. Library Manager — populate .lib/.ndm and verify multi-VT setup

Tech configs ship with LEF and RCX declarations but no `.lib` / `.ndm` file paths — those come from a per-tech `lib_config.tcl` you generate once by pointing at your vendor library root. The library manager scans your `.lib` files, groups them by (track × VT × corner), and emits the resolved paths.

```bash
# One-time: generate lib_config.tcl for your tech from a vendor library root.
# This walks --lib-root, groups files by track (9T, 10T, ...) × VT (svt, lvt,
# hvt, ulvt) × PVT corner, and writes the resolved paths so downstream tool
# configs can index them with $tech(9T,svt,ndm), $tech(9T,lvt,ndm), etc.
cbflow flow library-manager generate \
  --tech gf_22nm \
  --lib-root /proj/libs/gf_22nm

# Optional filters:
#   --tag P0                     Write to lib_config_P0.tcl (for phase-specific libs)
#   --exclude "*ulvt*"           Drop a VT family before writing (never generated)
#   --stdcell-path /libs/eco     Alternate stdcell directory (for ECO libraries)
```

Multi-VT designs are supported out of the box:

- The tech config declares `tech(vt_variants_available) {svt lvt hvt ulvt}`.
- Your project selects the active subset with `set project(vt_flavors) "svt lvt hvt"` in `<project>_config.tcl`. Any VT listed here will be loaded into tool link lines; any VT you leave out is skipped even if the library exists.
- `library-manager generate` produces both **per-VT** arrays (`tech(9T,svt,ndm)`) and a **combined-per-track** array (`tech(9T,ndm)` — the union). Tool configs can pick either granularity — combined for signoff, VT-specific for a synthesis pass that must stay in one flavor.

Verify readiness before a signoff run:

```bash
# Signoff-readiness report — checks LEF/RCX coverage, VT enablement,
# lib_config.tcl presence, and dont_use masks. Exits 0 when everything
# needed for the project's enabled VTs is populated; exits 1 with a
# NOT READY summary otherwise.
cbflow flow library-manager status --tech gf_22nm --project bumblebee

# What's actually declared per set (LEF, RCX, and — once generate has
# run — per-track per-VT NDM/DB/LIB counts).
cbflow flow library-manager list --tech-config <path>

# On-disk validation: reads .lib file headers and cross-checks
# corner/voltage/temp against filename convention.
cbflow flow library-manager verify --path /proj/libs/gf_22nm --recursive

# Coverage matrix (needs lib_config.tcl):
cbflow flow library-manager coverage --tech gf_22nm
```

## 3d. MMMC Manager — define analysis views + scenario sets

`mmmc_config.tcl` describes your **modes** (`func`, `test`, `scan`), **process corners** (ff/tt/ss) with their **PVT points** (voltage/temperature), and **RC corners** (rc_min / rc_typ / rc_max plus extensions like `rc_max_cworst`). The manager expands modes × PVT × RC into analysis views and groups those views into scenario sets (`setup`, `hold`, `signoff`, `all`) that STA and MMMC-aware stages consume.

```bash
# Inspect the current MMMC configuration (parsed + auto-generated views).
cbflow flow mmmc-manager show --config PD/config/project/<name>/v1.0.0/mmmc_config.tcl

# Six-check validation: PVT completeness, RC pairing, RC-corner existence,
# constraint files, TCL executability, node scenario references.
cbflow flow mmmc-manager validate --config <path>

# List generated views and scenario sets.
cbflow flow mmmc-manager list-views      --config <path>
cbflow flow mmmc-manager list-scenarios  --set setup --config <path>
cbflow flow mmmc-manager list-scenarios  --set hold  --config <path>

# Emit a Cadence-style view_definition.tcl (create_library_set /
# create_delay_corner / create_analysis_view / create_constraint_mode).
cbflow flow mmmc-manager generate-view-def --config <path> --output view_definition.tcl
```

Edit modes / PVTs / RC corners without hand-editing TCL:

```bash
# Modes — SDC file per operating mode.
cbflow flow mmmc-manager add-mode    --name scan --sdc '${design_name}_scan.sdc' --config <path>
cbflow flow mmmc-manager remove-mode --name scan --config <path>

# PVT points — one voltage/temperature pair added or removed per invocation.
cbflow flow mmmc-manager add-pvt    --corner ss --voltage 0p85v --temperature 105c --config <path>
cbflow flow mmmc-manager remove-pvt --corner ss --voltage 0p85v --temperature 105c --config <path>

# RC corners — extend beyond rc_min/typ/max (e.g. rc_max_cworst for signoff SI).
cbflow flow mmmc-manager add-rc --name rc_max_cworst \
  --temperature 125 --cap_mult 1.15 --res_mult 1.20 \
  --metal_mult 1.0 --via_mult 1.0 --config <path>

# Per-node scenario overrides — pin a stage/subnode to a specific
# setup/hold scenario list (e.g., CTS uses fewer corners than signoff).
cbflow flow mmmc-manager set-node --node cts \
  --setup "func_ss_0p80v_rcmax_125c" \
  --hold  "func_ff_1p10v_rcmin_m40c" --config <path>
```

Every mutation re-runs the TCL parser and the six validation checks; if you land on an inconsistent state (missing SDC file for a new mode, RC pair points at a non-existent RC corner) the tool refuses to write and prints the specific check that failed.

## 4. Create User Config

```tcl
# user_config.tcl — minimum for SYNTH_PNR flow
set flow(design_name)               "my_design"
set flow(dispatcher)                "race"
set synth_pnr(design_name)          "my_design"
set synth_pnr(input,rtl_filelist)   "/proj/rtl/my_design.f"
set synth_pnr(input,sdc_file)       "/proj/constraints/my_design.sdc"
set synth_pnr(input,upf)            "/proj/power/my_design.upf"
```

## 5. Create Run and Execute

```bash
# Create run directory
cbflow workspace create --config user_config.tcl
cd P0_run_SYNTH_PNR_run1/

# Run the full flow (RACE builds DAG from node_config.tcl, executes all nodes)
cbflow run all

# Check status (reads from RACE SQLite DB)
cbflow run status

# View logs
cbflow run logs --tail 20

# Generate summary
cbflow run autoppt
```

## 6. RACE Engine Basics

CBflow v2.0.0 uses the **RACE (Run Automation & Control Engine)** as its dispatcher. RACE is a Python-native DAG executor that:

- Builds the execution DAG from `node_config.tcl` at runtime
- Tracks all node status in a SQLite database (`.race_<run_dir>_<user>_<hash>.db`)
- Detects file changes on inputs and auto-retraces downstream nodes
- Runs independent subnodes in parallel (e.g., PV: drc/lvs/erc/perc/xor)
- Generates dynamic subnodes (e.g., STA per-corner from user_config)

There is no Makefile, no `.make/` directory, and no `make` command. All execution is handled by RACE.

Additional RACE features:
- **Run ownership**: Only the run creator can modify a run (retrace, add-node, delete, bypass, force). Everyone can view status, GUI, and logs.
- **13 database tables** for comprehensive data collection (jobs, run_info, run_config, job_order, dag_structure, stage_metrics, design_info, checklist_results, release_info, lsf_details, run_logs, metrics_snapshot, config_history)
- **Deterministic GUI port**: Each run gets a consistent port for the web dashboard
- **DB stored in race area**: Configured via `project(race,db_path)`, with a `.race_db_pointer` in the run directory

## 7. Key Commands

| Command | Purpose |
|---------|---------|
| `cbflow run all` | Run complete flow |
| `cbflow run stage --name place1` | Run single stage |
| `cbflow run status` | Check progress (from RACE DB) |
| `cbflow run retrace --from cts1` | Mark CTS and downstream for re-execution |
| `cbflow run bypass --node <node>` | Skip a node |
| `cbflow run force --node <node>` | Force re-run a node |
| `cbflow run forcevalidate --node <node>` | Force validate a specific node |
| `cbflow run forcevalidate --from X --to Y` | Force validate a range of nodes |
| `cbflow run checklist --milestone PRO_EXIT --phase P2` | Exit checklist |
| `cbflow run email --to user@co.com --template run-summary` | Email report |
| `cbflow run autoppt --format html` | Generate PPT summary |
| `cbflow run interactive --load signoff1` | Interactive session |
| `cbflow run logs --level ERROR` | View errors |
| `cbflow run add-node --node <n> --type <t>` | Add custom node to DAG |
| `cbflow run create-branch --name <n>` | Create a flow branch |
| `cbflow run show-graph` | Visualize DAG |
| `cbflow flow checklist list-checks` | List all checks with IDs (auto-detects milestone/phase from run dir) |
| `cbflow flow checklist list-checks -s` | Summary mode |
| `cbflow flow checklist status` | Evaluate checks against run (auto-detects context) |
| `cbflow flow checklist sign-off` | Record sign-off |
| `cbflow flow library-manager status --tech <T> --project <P>` | Signoff-readiness (LEF/RCX/VT coverage) — see §3c |
| `cbflow flow library-manager generate --tech <T> --lib-root <path>` | Emit `lib_config.tcl` from a vendor library root |
| `cbflow flow library-manager list --tech-config <path>` | List declared library sets |
| `cbflow flow mmmc-manager show --config <path>` | Print modes / PVTs / RC corners / views / scenario sets |
| `cbflow flow mmmc-manager validate --config <path>` | 6-check MMMC config validation |
| `cbflow flow mmmc-manager generate-view-def --config <path> --output view_definition.tcl` | Emit Cadence view_definition.tcl |
| `cbflow run db-manage --list` | List RACE databases (ACTIVE/ORPHANED status) |
| `cbflow run db-manage --cleanup` | Interactive cleanup (owner-only) |

## 8. Supported Flows (12)

| Flow | What It Does |
|------|-------------|
| `SYNTH` | RTL synthesis |
| `FP` | Floorplanning |
| `PNR` | Place and route |
| `SYNTH_PNR` | Unified synthesis + PNR (FC) |
| `STA` | Static timing analysis (per-corner, dynamic subnodes) |
| `PV` | Physical verification (DRC/LVS/ERC, parallel subnodes) |
| `LEC` | Logic equivalence check |
| `ECO` | Engineering change order |
| `CLP` | Clock low power verification |
| `EMIR` | EM/IR drop analysis |
| `POPT` | Power optimization |
| `FCFP` | Full chip floorplan (hierarchical) |

## 9. Exit Milestones

CBflow defines 11 exit milestones across the PD lifecycle with 292 library checks across 14 categories:

| Milestone | Flow |
|-----------|------|
| FP_EXIT | Floorplanning complete |
| PLACE_EXIT | Placement complete |
| CTS_EXIT | Clock tree synthesis complete |
| PRO_EXIT | Post-route optimization complete |
| BTO | Backend tapeout ready |
| MTO | Manufacturing tapeout ready |
| STA_SIGNOFF | Static timing sign-off |
| LEC_SIGNOFF | Logic equivalence sign-off |
| CLP_SIGNOFF | Low power verification sign-off |
| PV_SIGNOFF | Physical verification sign-off |
| EMIR_SIGNOFF | EM/IR analysis sign-off |

Milestones are **phase-aware**: P0 applies relaxed criteria, P3 enforces zero-tolerance on all checks.

## 10. Input Handshaking

```tcl
# In user_config.tcl — two modes:

# Mode 1: Release tag (auto-resolves from release directory)
set pnr(input,netlist_release_tag) "v1.0.2"

# Mode 2: Direct path
set pnr(input,netlist) "/proj/runs/synth_run1/outputs/my_design.v"
```

## 11. Override Hierarchy

All configs are consolidated into a single generated `config.tcl` per node. Command files source it once.

```
project_config.tcl            (project-specific)
  -> tech_config.tcl           (technology + libraries)
    -> flow_config.tcl          (flow defaults)
      -> node_config.tcl        (stage definitions)
        -> mmmc_config.tcl      (MMMC scenarios/corners)
          -> <tool>_config.tcl  (tool-specific: fc_config, pt_config)
            -> user_config.tcl  (per-run overrides)
              -> override_config.tcl              (global hook)
                -> override_config.<stage>.tcl    (stage-type hook)
                  -> override_config.<branch>.tcl (branch-scoped hook)
                    -> override_config.<node>.tcl (per-node hook)
```

Flow type must be explicitly set (via `CBFLOW_FLOW_TYPE` env var or user_config). If missing or invalid, CBflow exits with error and lists available flows.

## 12. Milestone Release

Releases are milestone-gated. Tags are predefined; leads set the active tag in project config.

```bash
# From workspace (where all runs live):
cbflow run release                      # Release using project's active tag
cbflow run release --tag PLACE_EXIT     # Specific milestone
cbflow run release --dry-run            # Validate without copying

# Predefined tags: FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO
# Release path: <base>/<project>/<design>/<phase>_<tag>/<FLOW>/
```

## 13. SmartGenie AI Agent

```bash
# Setup (one time)
brew install ollama && ollama serve && ollama pull qwen2.5:7b
cbflow smartgenie ingest --all       # Build knowledge base (4000+ chunks)
cbflow smartgenie setup              # Verify

# Use
cbflow smartgenie                    # Interactive AI agent
cbflow smartgenie "run SYNTH_PNR"    # One-shot command
cbflow smartgenie search "hold fix"  # Search knowledge

# Enterprise (multi-user, shared learning)
cbflow smartgenie serve              # Start central server
export SMARTGENIE_SERVER=http://server:8091
cbflow smartgenie "prompt"           # All users connect, knowledge auto-shared
```

100% private — runs on-premise via Ollama. No data leaves your network. See [SmartGenie User Guide](../02-user-guide/smartgenie-user-guide.md).

## 14. Customer Bundle & Permissions

```bash
# Create customer bundle (all files 777 for safe unzip)
cbflow bundle                           # Creates CBflow_v2.0.0_<date>.tar.gz
cbflow bundle --output /path/to/dir     # Custom output directory

# After customer unpacks:
tar xzf CBflow_v2.0.0_20260519.tar.gz
cd CBflow_v2.0.0_20260519
bin/cbflow run release-lock             # Lock: configs=444, scripts=555, dirs=755
bin/cbflow run release-lock --unlock    # Unlock: restore 777 (development mode)
```

Lead config (in project_config.tcl):
```tcl
set project(release,active_tag)  "BTO"
set project(release,expiry_date) "2026-06-30"
set project(release,path)        "/proj/releases"
```

## 15. Test Suite

```bash
bin/cbflow-test-suite              # 994 tests, all categories
bin/cbflow-test-suite --verbose    # Show all results
```

---

**Next**: [Quick Start Guide](../01-quick-start/README.md) for detailed setup.
