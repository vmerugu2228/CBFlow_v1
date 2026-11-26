# CBflow Flow User Guide

**Version:** 2.0.0 | **November 2026**

> **2026-11:** SYNTH, FP, PNR, STA, PV and LEC also run with the open-source
> vendor on sky130. Select it with `<flow>(tool,name)` set to `yosys`, `openroad`, `opensta` or `magic`.
> The open-source stage lists differ from the ones below; see the
> [Open-Source Flow Guide](opensource-flow-guide.md). For design releases to exit
> milestones, see the [Exit Release Guide](exit-release-guide.md).

---

## 1. Getting Started

### 1.1 Create a Workspace

Every flow run starts with a workspace. A workspace ties together a project, flow type, and design block. The `cbflow workspace create` command auto-detects everything from the project config and release manifest.

Runs are created from the block's workarea, `<project(workarea_path)>/<block>/` (enforced):

```bash
cd $CBFLOW_ROOT/workarea/cpu_core

# Generate a user_config.tcl template for your flow
cbflow workspace template --flow PNR > user_config.tcl

# Edit user_config.tcl with your design-specific paths, then create the workspace
cbflow workspace create --config user_config.tcl
```

This creates the run directory with:

| File | Purpose |
|------|---------|
| `.run.cbflow.env` | Shell environment (project, release, paths, component versions) |
| `.run.cbflow.tcl` | Same environment in TCL format |
| `.race_*.db` | RACE SQLite status database (tracks all node/subnode status) |

The workspace locks the **project**, **flow type**, and **block**. These cannot be changed after creation.

### 1.2 Configure Your Run

Edit `user_config.tcl` with your design-specific paths:

```tcl
# ── Identity ─────────────────────────────────────────────────────
set project(name)        "bumblebee"
set flow(type)           "PNR"
set flow(design_name)    "cpu_core"
set flow(run_name)       "run1"
set project(phase)       "LC2"        ;# optional; default project(current_phase)

# ── Launch mode (defaults: test_mode false, use_lsf false, use_xterm true) ──
set flow(test_mode)      "false"      ;# "true" = no EDA tools, dummy outputs
set flow(use_lsf)        "true"       ;# submit through bsub (bsub must be on PATH)
set flow(use_xterm)      "false"      ;# "true" = one xterm per job (needs xterm + $DISPLAY)

# ── Input paths ──────────────────────────────────────────────────
set pnr(input,netlist)       "/data/synth_output/cpu_core.v"
set pnr(input,sdc_func_file) "/data/constraints/cpu_core.sdc"
set pnr(input,def_file)      "/data/floorplan/cpu_core.def"
set pnr(input,upf_file)      "/data/power/cpu_core.upf"
```

`workspace create` fails (and removes the partial run) when `use_lsf` is true without `bsub`, or `use_xterm` is
true without `xterm`. In production mode each stage must produce its `mandatory_outputs` and at least one file in
`outputs/`, so a tool that exits 0 without results fails the stage.

> **Test mode:** Set `flow(test_mode) "true"` to run the entire flow without invoking EDA tools. CBflow will execute all stages, create directories and update the RACE DB, and display command file contents instead of running tools. Useful for validating your configuration before a real run.

### 1.3 Create and Run

```bash
# Create the run directory
cbflow workspace create --config user_config.tcl

# Enter the run directory (<phase>_run_<FLOW>_<block>_<run>) and execute
cd LC2_run_PNR_cpu_core_run1
cbflow run all
```

That's it. CBflow creates the run directory. RACE builds the DAG from the node config and executes stages in dependency order, tracking all status in the SQLite database.

---

## 2. Supported Flows

CBflow has 12 PD flow types (plus DFT, DV and RTL flows — `cbflow flow types`). Stages are listed by
`cbflow flow stages --flow <FLOW>` and `cbflow flow info --flow <FLOW>`; the stage list below is the default
(Synopsys) node config. A tool overlay can change it — e.g. `pnr(tool,name) "openroad"` (see the
[Open-Source Flow Guide](opensource-flow-guide.md)) or `pnr(tool,name) "innovus"`.

### 2.1 Flow Overview

| Flow | Default tool | Also | Stages (default node config) |
|:---:|---|---|---|
| SYNTH | Fusion Compiler | Genus, yosys | rtl1, sdc1, upf1 -> synthesis1 -> export_data1 -> release_data1 |
| FP | Fusion Compiler | Innovus, OpenROAD | netlist1, sdc1, def1, upf1, library1 -> init_design1 -> floorplan1 -> powerplan1 -> export_data1 -> release_data1 |
| PNR | Fusion Compiler | Innovus, OpenROAD | netlist1, sdc1, def1, upf1 -> init_design1 -> place1 -> cts1 -> cts_opt1 -> route1 -> pro1 -> signoff1 -> export_data1 -> release_data1 |
| SYNTH_PNR | Fusion Compiler | | rtl1, sdc1, upf1 -> init_design1 -> synthesis1 -> place1 -> cts1 -> cts_opt1 -> route1 -> pro1 -> signoff1 -> export_data1 -> release_data1 |
| STA | PrimeTime | Tempus, OpenSTA | netlist1, sdc1, def1, library1 -> extraction1 -> timing1 (one subnode per MMMC scenario) -> merge_reports1 -> release_data1 |
| LEC | Formality | Conformal, yosys | netlist_golden1 -> netlist_revised1 -> constraints1 -> compare1 -> release_data1 |
| EMIR | RedHawk | Voltus | netlist1, def1, spef1, library1 -> power_analysis1 -> ir_drop1 -> thermal_analysis1 |
| PV | IC Validator | Calibre, KLayout / Magic + Netgen | netlist1, def1, gds1 -> nettran1 -> merge_gds1 -> fill_merge_gds1 -> decomp1 -> decomp_merge_gds1 -> (drc1, lvs1, perc1, perc_ldl1, xor1 in parallel) -> merge_data1 -> release_data1 |
| ECO | Fusion Compiler | OpenROAD | netlist1, def1, sdc1, library1 -> eco1 -> export_db1 |
| CLP | VC LP | Conformal LP | netlist1, upf1 -> power_spec1 -> clp1 -> release_data1 |
| POPT | PrimeTime | | netlist1, sdc1, upf1 -> merge_timing1 -> power_opt1 -> post_merge1 -> release_data1 |
| FCFP | Fusion Compiler | | netlist1, sdc1, def1, upf1, library1 -> init_design1 -> commit_blocks1 -> init_compile1 -> create_floorplan1 -> shaping1 -> placement1 -> create_power1 -> place_pins1 -> top_compile1 -> timing_budget1 -> export_data1 -> release_data1 |

Input stages (`netlist1`, `sdc1`, `rtl1`, …) resolve and copy one input each; they run in parallel.
Every stage has the subnodes `setup`, `run`, `validate`, `finish` (run one with `cbflow run stage --name <n> --subnode <s>`).

---

## 3. Flow Inputs

Generate the inputs of a flow with `cbflow workspace template --flow <FLOW>`. Required inputs (any one input of a
mandatory group satisfies it — e.g. a path, a per-input release tag, or the generic `<flow>(input,release_tag)`):

| Flow | Required inputs (explicit-path form) |
|---|---|
| SYNTH | `synth(input,rtl_filelist)`, `synth(input,sdc_func_file)` (UPF optional: `synth(input,upf_file)`) |
| FP | `fp(input,netlist)`, `fp(input,sdc_func_file)` |
| PNR | `pnr(input,netlist)`, `pnr(input,sdc_func_file)`, `pnr(input,def_file)` |
| SYNTH_PNR | `synth_pnr(input,rtl_filelist)`, `synth_pnr(input,rtl_format)`, `synth_pnr(input,sdc_func_file)`, `synth_pnr(input,upf_file)` |
| STA | `sta(input,netlist)`, `sta(input,sdc,<mode>)` (one per operating mode, e.g. `sta(input,sdc,func)`) |
| LEC | `lec(input,netlist_golden)`, `lec(input,netlist_revised)` |
| EMIR | `emir(input,netlist)`, `emir(input,def_file)` |
| PV | `pv(input,gds)` (optional `pv(input,netlist)`, `pv(input,def_file)`) |
| CLP | `clp(input,netlist)`, `clp(input,upf_file)` |
| ECO, POPT, FCFP | no mandatory input keys (from the upstream release / run) |

Prefer release tags over paths (see section 9 and the [Exit Release Guide](exit-release-guide.md)):

```tcl
set pnr(input,release_tag)          "P1_SYNTH_v1"   ;# every PNR input from the SYNTH release
set pnr(input,def_file_release_tag) "FP_EXIT"       ;# the floorplan from the FP release
set sta(input,release_tag)          "PRO_EXIT"      ;# signoff STA of the PRO_EXIT release
set lec(input,netlist_golden_release_tag)  "P1_SYNTH_v1"
set lec(input,netlist_revised_release_tag) "PRO_EXIT"
```

Signoff flows (STA / PV / LEC with the open-source tools) read **only** the release of the exit they verify:
`from_run`, explicit paths and other tags are refused for non-exempt inputs.

Outputs of a node are in `work/<FLOW>/<node>/outputs/` and reports in `work/<FLOW>/<node>/reports/`;
the release node copies the deliverables to `<release,path>/<phase>/<block>/<FLOW>/<tag>/<category>/`.

---

## 4. Running Flows

### 4.1 Complete Workflow (Step by Step)

```bash
# 1. Generate a user_config.tcl template
cbflow workspace template --flow PNR > user_config.tcl

# 2. Edit user_config.tcl with your input paths

# 3. Create a run
cbflow workspace create --config user_config.tcl

# 4. Enter run directory
cd LC2_run_PNR_cpu_core_run1

# 5. Run complete flow
cbflow run all

# 6. Check results
cbflow run status --details
ls work/PNR/pro1/reports/
cbflow run gui                       # run dashboard
```

### 4.2 Running Individual Stages

```bash
cbflow run stage --name netlist1               # Only resolve the netlist input
cbflow run stage --name place1                 # Only run placement
cbflow run stage --name cts1 --subnode setup   # Only the setup subnode of cts1
```

If a dependency stage hasn't run, RACE will run it automatically.

### 4.3 Re-running Stages

CBflow tracks completion in the RACE SQLite database. To re-run a stage:

```bash
# Option 1: Retrace from a stage (marks that node + all downstream for re-execution)
cbflow run retrace --from cts1
cbflow run all    # Re-runs from cts1 onwards

# Option 1b: retrace and re-run in one step
cbflow run retrace --from cts1 --run

# Option 2: Force re-run specific nodes only (downstream untouched; deps must be DONE)
cbflow run force --stages place1

# Option 3: Bypass nodes (mark DONE without running; writes work/<FLOW>/<node>/BYPASSED)
cbflow run bypass --stages export_data1,release_data1

# Option 4: Mark nodes done that ran outside CBflow
cbflow run forcevalidate --from netlist1 --to init_design1
```

### 4.4 Viewing Status

```bash
# Quick overview (queries RACE DB)
cbflow run status

# Detailed view with subnodes
cbflow run status --details

# Dependency graph
cbflow run show-graph
```

### 4.5 Viewing Logs

```bash
# List all log files
cbflow run logs --list

# Tail recent output
cbflow run logs --tail 50

# Filter by severity
cbflow run logs --tail 100 --level ERROR
cbflow run logs --tail 100 --level WARNING
```

### 4.6 Validation

```bash
# Validate everything (config + inputs + outputs)
cbflow run validate

# Config only
cbflow run validate --type config

# Specific stage outputs
cbflow run validate --stage place1
```

---

## 5. Merged Flows

CBflow can combine multiple flows into a single run. Stage names are prefixed with the flow name.

### 5.1 SYNTH_FP (Synthesis + Floorplan)

```bash
cbflow workspace template --flow SYNTH_FP > user_config.tcl
# Edit user_config.tcl, then:
cbflow workspace create --config user_config.tcl
```

The run gets one work area per flow (`work/SYNTH/`, `work/FP/`); the FP input stages depend on the SYNTH export.
A merged flow belongs to the one discipline all of its flows share. Separate runs connected by release tags
(SYNTH -> FP -> PNR) are the more common setup and are what the workarea scripts use.

**User Config for Merged Flow:**

```tcl
set flow(type) "SYNTH_FP"

# SYNTH inputs
set synth(input,rtl_filelist)   "/path/to/rtl.f"
set synth(input,sdc_func_file)  "/path/to/constraints.sdc"

# FP inputs (fed from SYNTH output)
set fp(input,netlist)           "/path/to/synth_netlist.v"
set fp(input,sdc_func_file)    "/path/to/constraints.sdc"
set fp(input,def_file)          "/path/to/seed.def"
```

### 5.2 Other Merged Combinations

- `SYNTH_FP_PNR` — Full front-to-back implementation
- `SYNTH_FP` — Synthesis through floorplan
- `SYNTH_PNR` is a single flow of its own (Fusion Compiler RTL-to-signoff), not a merge

---

## 6. LSF Submission

### 6.1 Submitting to LSF

Set it once in user_config (`set flow(use_lsf) "true"`, `set flow(use_xterm) "false"`) or per command:

```bash
# Submit complete flow
cbflow run all --lsf

# With specific queue
cbflow run all --lsf --queue XL

# Submit single stage
cbflow run stage --name route1 --lsf
```

### 6.2 Queue Recommendations

CBflow assigns queues based on the flow and stage:

| Queue | Memory | CPUs | Time | Used For |
|:---:|:---:|:---:|:---:|---|
| **S** | 8 GB | 4 | 2h | inputs, validate, export, release stages |
| **M** | 16 GB | 8 | 4h | synthesis, floorplan, CTS, ECO, CLP |
| **L** | 32 GB | 16 | 8h | placement, routing opt, DRC, LVS, extraction, IR drop |
| **XL** | 64 GB | 32 | 12h | complex routing, thermal analysis |
| **ultra** | 128 GB | 64 | 24h | full-chip signoff |

**Detailed mappings by flow:**

| Flow | S | M | L | XL |
|------|---|---|---|---|
| SYNTH | inputs, export, release | synthesis | | |
| PNR | inputs, release | export | place, cts, cts_opt, pro, signoff | route |
| STA | inputs | | extraction, timing | |
| LEC | netlist_golden, netlist_revised, constraints, release_data | compare | | |
| EMIR | inputs | | power_analysis, ir_drop | thermal_analysis |
| PV | inputs, merge, release | erc, perc | drc, lvs | |
| ECO | inputs | export_db | eco | |
| CLP | inputs, export, release | clp | | |
| POPT | inputs, release | merge_timing, post_merge | power_opt | |
| FCFP | inputs, export, release | fc_post_floorplan | fc_floorplan, fc_powerplan | |

Tiers are defined in `PD/config/flow/v1.0.0/lsf_config.tcl` (XS / S / M / L / XL / ultra; default
`lsf(default_queue_type) "M"`); the table above is indicative. Per node: `cbflow run add-node … --resource-tier XL`.
Override the bsub binary with `CBFLOW_BSUB_CMD`.

### 6.3 Checking LSF Status

```bash
cbflow run lsf-status
```

---

## 7. Node and Branch Management

### 7.1 Adding Custom Nodes

Add custom stages to a run after creation:

```bash
# Add a second placement after place1 (type = a stage type of this flow)
cbflow run add-node --node place2 --type place --dep place1
cbflow run add-node --type place --dep cts1              # auto-named place3
cbflow run add-node --node pro2 --type pro --dep route1 --resource-tier XL

# Add an export + release pair under a stage (releases that stage's exit)
cbflow run add-node --node export_data2  --type export_data  --dep place1
cbflow run add-node --node release_data2 --type release_data --dep export_data2

# Rewire any node (base or custom)
cbflow run set-dep --node export_data1 --deps place1     # comma- or space-separated
cbflow run set-dep --node export_data1 --reset           # back to the node config

# List / delete
cbflow run list-nodes
cbflow run delete-node --node place2
```

Added nodes inherit the base stage's `runtime,timeout`. Base-node rewires are stored as `dep_overrides` in
`setup/runtime_flow_config.tcl`; cycles are refused. In the run dashboard: right-click a node -> Set Dependencies….

### 7.2 Branches

Create experimental branches from any stage. Branching creates the **full downstream pipeline** (all stages from the branch point through release_data), not just a single node:

```bash
# Branch from CTS — creates: cts2 -> cts_opt2 -> route2 -> ... -> release_data2
cbflow run create-branch --branch timing_experiment --from cts1

# Branch from a custom node — also creates full downstream
cbflow run create-branch --branch from_eco --from place2_eco

# List branches
cbflow run list-branches

# Delete branch
cbflow run delete-branch --branch timing_experiment
```

All RACE commands work with custom nodes and branch nodes:
```bash
cbflow run retrace --from cts2          # Retrace from branch node
cbflow run bypass --stages cts2         # Bypass a branch node
cbflow run force --stages place2_eco    # Force re-run a custom node
cbflow run stage --name route2          # Run a specific branch stage
```

### 7.3 Viewing the Graph

```bash
# Simple view
cbflow run show-graph

# With subnodes
cbflow run show-graph --detail
```

---

## 8. Run Directory Structure

After `cbflow run all` completes, a run directory contains:

```
LC2_run_PNR_cpu_core_run1/
├── .race_db_pointer             path of the RACE DB (in project(race,db_path))
├── .run.cbflow.env              Shell environment
├── .run.cbflow.tcl              TCL environment
├── setup/
│   ├── user_config.tcl          Your configuration
│   ├── runtime_flow_config.tcl  added nodes, dep_overrides
│   └── override_config*.tcl     per-run / per-node overrides (optional)
├── work/PNR/<node>/             One directory per node (place1, cts1, ...)
│   ├── run/                     config.tcl, setup.tcl, <job>.log
│   ├── outputs/
│   ├── reports/
│   └── BYPASSED                 present when the node was bypassed
└── logs/
```

---

## 9. Milestone Release System

### 9.1 Overview

> The authoritative guide for design releases is the [Exit Release Guide](exit-release-guide.md) (layout,
> source-stage exits, intermediate releases, clone-from, exit order per discipline, publishing). This section
> summarizes the commercial `cbflow run release` packaging.

CBflow uses a **milestone-gated release** system. Release tags are predefined (not free-form) and map to design exit milestones. Leads set the **active tag** and **expiry date** at the project level. A release only proceeds when ALL required flows for that milestone have completed successfully.

### 9.2 Predefined Release Tags

| Tag | Description | Required Flows (`release_tags(<exit>)`) |
|-----|-------------|----------------|
| `FP_EXIT` | Floorplan Exit | SYNTH_PNR PNR FP FCFP PV |
| `PLACE_EXIT` | Placement Exit | SYNTH_PNR PNR SYNTH |
| `CTS_EXIT` | CTS Exit | SYNTH_PNR PNR SYNTH |
| `PRO_EXIT` | Post-Route Exit | SYNTH_PNR PNR SYNTH STA LEC |
| `BTO` | Backend Tapeout | SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO |
| `MTO` | Metal Tapeout | SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO POPT |

Tags are defined in `PD/config/flow/v1.0.0/release_config.tcl` (`release_tags`, `MILESTONE_ORDER`,
`MILESTONE_STAGE_MAPPING`). Which exits each phase delivers is project-defined: `project(phase_exits)` (PD) and
`project(phase_exits,<DISC>)` in `global/config/project/<proj>/v1.0.0/<proj>_config.tcl`.

### 9.3 Lead Configuration (Project Level)

Leads control the active tag and expiry in the PD overlay `PD/config/project/<name>/v1.0.0/<name>_pd_config.tcl`:

```tcl
set project(release,active_tag)  "BTO"           ;# Current milestone target
set project(release,expiry_date) "2026-06-30"    ;# Tag expires after this date
set project(release,path)        "/proj/releases" ;# Shared release directory
```

### 9.4 Running a Release

```bash
# From the workspace directory (where all runs live):
cbflow run release                      # Use active tag from project config
cbflow run release --tag PLACE_EXIT     # Override with specific tag
cbflow run release --dry-run            # Validate only, don't copy files
cbflow run release --tag PRO_EXIT --publish   # also publish to SmartGrid (opt-in)

# Open-source flows release themselves in release_data; publish / clone that release:
cbflow run release --from-run <run_dir> --publish
cbflow run release --from-run <run_dir> --node release_data2 --publish
cbflow run release --from-run <run_dir> --clone-from BTO --tag MTO --publish
```

Flags: `--tag --name --dry-run --from-run --node --clone-from --publish --no-publish --override`.

The release command:
1. Validates the tag is predefined
2. Checks the current phase meets the tag's minimum
3. Checks the expiry date hasn't passed
4. **Gate check**: scans workspace for ALL required flow runs with PASS status
5. **Exit order**: earlier exits of the phase's plan must already be released (no bypass flag)
6. If any missing: ERROR listing what needs to be run / released first
7. If all present: copies deliverables from each flow to the release directory

### 9.5 Release Directory Structure

```
<project(release,path)>/<phase>/<block>/<FLOW>/<tag>/      # tag = exit name unless project(release,tag)
e.g. /proj/releases/LC3/cpu_core/SYNTH_PNR/BTO/
  ├── SYNTH_PNR/
  │   ├── netlist/   (.v, .pt.v, .fm.v, .lvs.v, .vc_lp.v, .dc.v)
  │   ├── gds/       (.gds)
  │   ├── def/       (.def)
  │   ├── sdc/       (*.sdc)
  │   ├── spef/      (*.spef)
  │   ├── upf/       (.upf)
  │   ├── data/      (wscript, routing_constraints, floorplan, SAIF maps)
  │   └── lef/       (.lef)
  ├── PNR/
  │   ├── netlist/   (.v, .pt.v, .fm.v, .lvs.v)
  │   ├── gds/def/sdc/spef/upf/data/
  ├── STA/reports/
  ├── PV/reports/
  ├── LEC/reports/
  ├── CLP/reports/
  ├── EMIR/reports/
  ├── MANIFEST.json
  └── RELEASE_COMPLETE
```

### 9.6 Release Artifacts

- **MANIFEST.json** — JSON metadata: tag, phase, project, design, timestamp, user, per-flow run directories, total file count
- **RELEASE_COMPLETE** — Key-value status file: TAG, MILESTONE, PHASE, FILES, FLOWS, STATUS=PASS/FAIL, TIMESTAMP

### 9.7 Chip-Level Release Check

Verify that ALL blocks in the project have released for a milestone:

```bash
# Check all blocks for BTO readiness
cbflow run release-check --tag BTO --project bumblebee --phase LC3

# Check specific block only
cbflow run release-check --tag PLACE_EXIT --project bumblebee --phase LC2 --block cpu_core
```

The check command reads `project(block_list)` from the project config and scans the release directory for each block × flow combination. Output is a matrix:

```
Block                SYNTH_PNR     PNR           STA           Status
────────────────────────────────────────────────────────────────
cpu_core             PASS(18)      PASS(13)      PASS(5)       [COMPLETE]
memory_ctrl          PASS(18)      PASS(13)      MISS          [INCOMPLETE]
io_ctrl              MISS          MISS          MISS          [INCOMPLETE]
────────────────────────────────────────────────────────────────
TOTAL                1/3 blocks complete

CHIP-LEVEL RELEASE: NOT READY — 2 block(s) incomplete
```

Inputs: `--tag` (required), `--project` (required), `--phase` (required in practice — use the project's current phase), `--block` (optional, default all)

### 9.8 Customer Bundle & Permissions

Create a customer-ready bundle with 777 permissions (ensures clean unzip on any OS):

```bash
cbflow bundle                           # Creates CBflow_v2.0.0_<date>.tar.gz in current dir
cbflow bundle --output /delivery/dir    # Custom output location
cbflow bundle --version v2.0.0_rc1      # Custom version tag
```

After customer unpacks, lock permissions for production:

```bash
tar xzf CBflow_v2.0.0_20260519.tar.gz
cd CBflow_v2.0.0_20260519

# Lock — sets production permissions
bin/cbflow run release-lock
#   Directories:     755 (rwxr-xr-x)
#   Scripts/Python:  555 (r-xr-xr-x)
#   Config/TCL/Docs: 444 (r--r--r--)

# Unlock — restore 777 for development/debugging
bin/cbflow run release-lock --unlock
```

---

## 10. Configuration Reference

### 10.1 Input Variable Naming Convention

Each flow uses a consistent naming pattern for input variables:

```
{flow_array}(input,{input_type})                 explicit path (wins)
{flow_array}(input,{input_type}_release_tag)     that input from a release tag
{flow_array}(input,release_tag)                  every input from one tag
{flow_array}(input,from_run)                     every input from a sibling run's outputs
```

| Flow | Array | Common Input Variables |
|------|-------|---|
| SYNTH | `synth()` | `synth(input,rtl_filelist)`, `synth(input,sdc_func_file)`, `synth(input,upf_file)` |
| FP | `fp()` | `fp(input,netlist)`, `fp(input,sdc_func_file)`, `fp(input,def_file)`, `fp(input,upf_file)` |
| PNR | `pnr()` | `pnr(input,netlist)`, `pnr(input,sdc_func_file)`, `pnr(input,def_file)`, `pnr(input,upf_file)` |
| STA | `sta()` | `sta(input,netlist)`, `sta(input,sdc,<mode>)`, `sta(input,spef)` |
| LEC | `lec()` | `lec(input,netlist_golden)`, `lec(input,netlist_revised)`, `lec(input,constraints)` |
| EMIR | `emir()` | `emir(input,netlist)`, `emir(input,def_file)`, `emir(input,spef)` |
| PV | `pv()` | `pv(input,netlist)`, `pv(input,def_file)`, `pv(input,gds)` |
| ECO | `eco()` | `eco(input,netlist)`, `eco(input,def)`, `eco(input,sdc_func_file)`, `eco(input,eco_script)` |
| CLP | `clp()` | `clp(input,netlist)`, `clp(input,upf_file)`, `clp(input,power_spec)` |
| POPT | `popt()` | `popt(input,netlist)`, `popt(input,sdc_func_file)`, `popt(input,upf_file)` |
| FCFP | `fcfp()` | `fcfp(input,netlist)`, `fcfp(input,sdc_func_file)`, `fcfp(input,def_file)`, `fcfp(input,upf_file)` |

### 10.2 Project Phases

Phases are project-defined (`set project(phases) {...}` in the global project config); checks activate as the
phases advance. Examples: opensky `P0 P1 P2 P3`, bumblebee `LC1 … LC5`.

| Phase (opensky) | Exits delivered (`project(phase_exits)`) |
|:---:|---|
| **P0** | FP_EXIT PRO_EXIT |
| **P1** | FP_EXIT PRO_EXIT |
| **P2** | FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO |
| **P3** | FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO |

### 10.3 Environment Variables

These are set automatically in `.run.cbflow.env` and `.run.cbflow.tcl`:

| Variable | Description |
|----------|---|
| `CBFLOW_RUN_DIR` | Absolute path to current run directory |
| `CBFLOW_FLOW_TYPE` | Flow type (e.g., PNR, SYNTH) |
| `CBFLOW_DESIGN_NAME` | Design/block name |
| `CBFLOW_RUN_NAME` | Run identifier (e.g., run1) |
| `CBFLOW_PROJECT_PHASE` | Phase (P0, P1, P2, P3) |
| `CBFLOW_PROJECT_NAME` | Project name |
| `CBFLOW_BLOCK_NAME` | Block name |
| `FLOW_DIR` | CBflow core directory |
| `CONFIG_ROOT` | Configuration root |
| `FLOW_CONFIG_VERSION` | Active flow config version |
| `UTILITIES_VERSION` | Utilities version |
| `CBFLOW_NODE_NAME` | Current node name (e.g., `place1`, `place2_eco`) -- set per job by RACE engine |
| `CBFLOW_SUBNODE` | Current subnode (e.g., `setup`, `run`, `validate`, `finish`) -- set per job |

---

## 11. Typical PD Workflow

A typical chip design flow using CBflow follows this sequence:

```
Step 1: SYNTH
    RTL --> gate-level netlist
    Output: synth.v, synth.sdc

Step 2: FP
    netlist --> floorplan with power grid
    Output: floorplan.def

Step 3: PNR
    floorplan --> placed & routed design
    Output: routed.def, routed.gds, parasitics.spef

Step 4: STA
    routed design + parasitics --> timing sign-off
    Output: timing.rpt, violations.rpt

Step 5: LEC
    RTL vs synthesized netlist --> equivalence proof
    synthesized vs P&R netlist --> equivalence proof
    Output: equivalence.rpt

Step 6: PV
    GDS --> DRC/LVS/ERC/PERC clean
    Output: drc_results.rpt, lvs_results.rpt

Step 7: EMIR
    routed design + parasitics --> IR drop / thermal pass
    Output: ir_drop.rpt, thermal_analysis.rpt

Step 8: CLP
    netlist + UPF --> low-power intent verified
    Output: power_verification.rpt
```

Each step is an independent CBflow workspace + run. Outputs from one flow become inputs to the next.

---

## 12. Quick Reference

```bash
# ── WORKSPACE ────────────────────────────────────────────────────
cbflow workspace template --flow PNR > user_config.tcl # Generate template
cbflow workspace create --config user_config.tcl       # Create run
cbflow workspace list-runs                             # List runs
cbflow workspace status                                # Overview

# ── RUN (from inside run directory) ──────────────────────────────
cbflow run all                           # Run complete flow
cbflow run stage --name <stage>          # Run single stage
cbflow run status                        # Check progress (from RACE DB)
cbflow run retrace --from <stage>        # Re-run from stage
cbflow run bypass --stages <n>[,<n>]     # Skip nodes
cbflow run force --stages <n>[,<n>]      # Force re-run
cbflow run forcevalidate --node <node>   # Force validate
cbflow run add-node --node <n> --type <t> --dep <d>   # Add a node
cbflow run set-dep --node <n> --deps <d>[,<d>]        # Rewire a node
cbflow run release --from-run . --publish             # Publish a self-released run
cbflow run show-graph                    # Show dependency graph
cbflow run clean --confirm               # Delete work + logs + RACE DB

# ── FLOW INFO ────────────────────────────────────────────────────
cbflow flow types                  # Flow types by discipline
cbflow flow info --flow PNR        # Show flow details
cbflow flow stages --flow SYNTH    # List stages

# ── LOGS & DEBUG ─────────────────────────────────────────────────
cbflow run logs --list             # List logs
cbflow run logs --tail 50          # Recent output
cbflow run logs --level ERROR      # Errors only
cbflow run validate                # Validate config + outputs
```
