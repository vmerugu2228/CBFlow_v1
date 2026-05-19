# CBflow Flow User Guide

**Version:** 2.0.0 | **April 2026**

---

## 1. Getting Started

### 1.1 Create a Workspace

Every flow run starts with a workspace. A workspace ties together a project, flow type, and design block. The `cbflow workspace create` command auto-detects everything from the project config and release manifest.

```bash
cd /path/to/my/designs
mkdir pnr_workspace && cd pnr_workspace

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
# ── Workspace-locked (do not modify) ─────────────────────────────
set project(name)        "ravendrive"
set project(phase)       "P0"
set project(technology)  "gf_22nm"
set design(name)         "cpu_core"
set design(top_module)   "cpu_core"
set flow(type)           "PNR"

# ── User-editable ────────────────────────────────────────────────
set flow(run_name)       "run1"
set flow(test_mode)      false

# ── Input paths ──────────────────────────────────────────────────
set pnr(input,netlist)       "/data/synth_output/cpu_core.v"
set pnr(input,sdc_func_file) "/data/constraints/cpu_core.sdc"
set pnr(input,def_file)      "/data/floorplan/cpu_core.def"
set pnr(input,upf_file)      "/data/power/cpu_core.upf"
```

> **Test mode:** Set `flow(test_mode) true` to run the entire flow without invoking EDA tools. CBflow will execute all stages, create directories and update the RACE DB, and display command file contents instead of running tools. Useful for validating your configuration before a real run.

### 1.3 Create and Run

```bash
# Create the run directory
cbflow workspace create --config user_config.tcl

# Enter the run directory and execute
cd P0_run_PNR_run1
cbflow run all
```

That's it. CBflow creates the run directory. RACE builds the DAG from node_config.tcl and executes stages in dependency order, tracking all status in the SQLite database.

---

## 2. Supported Flows

CBflow supports 11 physical design flows. Each flow has a defined set of stages that execute sequentially (or in parallel where dependencies allow).

### 2.1 Flow Overview

| Flow | Tool | Vendor | Stages | Description |
|:---:|---|---|:---:|---|
| SYNTH | Fusion Compiler | Synopsys | 4 | RTL to gate-level netlist |
| FP | Fusion Compiler | Synopsys | 6 | Floorplanning and power grid |
| PNR | Fusion Compiler | Synopsys | 9 | Full place-and-route |
| STA | PrimeTime | Synopsys | 3 | Static timing analysis |
| LEC | Formality | Synopsys | 5 | Logic equivalence checking |
| EMIR | RedHawk | Synopsys | 4 | EM/IR drop and thermal |
| PV | IC Validator | Synopsys | 7 | DRC, LVS, ERC, PERC |
| ECO | Fusion Compiler | Synopsys | 3 | Engineering change orders |
| CLP | VC LP | Synopsys | 4 | Low-power intent verification |
| POPT | PrimeTime | Synopsys | 5 | Power optimization |
| FCFP | Fusion Compiler | Synopsys | 6 | Fullchip floorplanning |

### 2.2 Stage Dependency Diagrams

Each box is a stage. Arrows show execution order.

**SYNTH**
```
inputs1 ──> synthesis1 ──> export_data1 ──> release_data1
```

**FP**
```
inputs ──> import_design ──> floorplan ──> powerplan ──> export_data ──> release_data
```

**PNR**
```
inputs1 ──> place1 ──> cts1 ──> cts_opt1 ──> route1 ──> pro1 ──> signoff1 ──> export_data1 ──> release_data1
```

**STA**
```
inputs1 ──> extraction1 ──> timing1 (per-scenario subnodes) ──> reporting1 ──> release_data1
```

**LEC**
```
netlist_golden1 ──> netlist_revised1 ──> constraints1 ──> compare1 ──> release_data1
```

**EMIR**
```
inputs ──> power_analysis ──> ir_drop ──> thermal_analysis
```

**PV** (parallel verification)
```
            ┌──> drc  ──┐
            ├──> lvs  ──┤
inputs ─────┤            ├──> merge_data ──> release_data
            ├──> erc  ──┤
            └──> perc ──┘
```

**ECO**
```
inputs ──> eco ──> export_db
```

**CLP**
```
inputs ──> clp ──> export_data ──> release_data
```

**POPT**
```
inputs ──> merge_timing ──> power_opt ──> post_merge ──> release_data
```

**FCFP**
```
inputs ──> fc_floorplan ──> fc_powerplan ──> fc_post_floorplan ──> export_data ──> release_data
```

---

## 3. Flow Details

### 3.1 SYNTH — Logic Synthesis

Transforms RTL source code into an optimized gate-level netlist.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs1 | rtl, sdc, library, upf, validate, finish | Load RTL files, timing constraints, cell libraries, power intent |
| synthesis1 | setup, run, validate, finish | Elaborate design, map to gates, optimize for timing/area/power |
| export_data1 | setup, run, validate, finish | Export synthesized netlist (.v), constraints (.sdc), database |
| release_data1 | setup, run, validate, finish | Package outputs for downstream flows |

**User Config — Input Variables:**

```tcl
set synth(input,rtl_files)      "/path/to/rtl_filelist.f"
set synth(input,sdc_func_file)  "/path/to/constraints.sdc"
set synth(input,upf_file)       "/path/to/power_intent.upf"
```

**Key Outputs:**
- `results/netlist/synth.v` — Synthesized netlist
- `results/sdc/synth.sdc` — Output constraints
- `reports/synthesis/synth_qor.rpt` — Quality of results
- `reports/synthesis/synth_timing.rpt` — Timing report
- `reports/synthesis/synth_area.rpt` — Area report
- `reports/synthesis/synth_power.rpt` — Power report

**RACE Commands:**
```bash
cbflow run all                        # Complete flow
cbflow run stage --name inputs1       # Load inputs only
cbflow run stage --name synthesis1    # Run synthesis (requires inputs1)
cbflow run stage --name export_data1  # Export results
```

---

### 3.2 FP — Floorplanning

Creates the physical floorplan with block placement and power grid.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs | netlist, sdc, def, upf, library, validate, finish | Load synthesized netlist, constraints, floorplan seed |
| import_design | setup, run, validate, finish | Import design into Fusion Compiler |
| floorplan | setup, run, validate, finish | Define die area, place macros, create blockages |
| powerplan | setup, run, validate, finish | Create power grid, stripes, rails |
| export_data | setup, run, validate, finish | Export DEF, save database |
| release_data | setup, run, validate, finish | Package floorplan deliverables |

**User Config — Input Variables:**

```tcl
set fp(input,netlist)       "/path/to/synth_netlist.v"
set fp(input,sdc_func_file) "/path/to/constraints.sdc"
set fp(input,def_file)      "/path/to/seed_floorplan.def"
set fp(input,upf_file)      "/path/to/power_intent.upf"
```

---

### 3.3 PNR — Place and Route

Complete physical implementation from placement through sign-off.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs1 | netlist, sdc, def, upf, library, validate, finish | Load design data from FP output |
| place1 | setup, run, validate, finish | Standard cell placement |
| cts1 | setup, run, validate, finish | Clock tree synthesis |
| cts_opt1 | setup, run, validate, finish | Post-CTS optimization |
| route1 | setup, run, validate, finish | Global and detail routing |
| pro1 | setup, run, validate, finish | Post-route optimization |
| signoff1 | setup, run, validate, finish | Static timing sign-off |
| export_data1 | setup, run, validate, finish | Export GDS, netlist, SPEF |
| release_data1 | setup, run, validate, finish | Package for tapeout |

**User Config — Input Variables:**

```tcl
set pnr(input,netlist)       "/path/to/fp_netlist.v"
set pnr(input,sdc_func_file) "/path/to/constraints.sdc"
set pnr(input,def_file)      "/path/to/floorplan.def"
set pnr(input,upf_file)      "/path/to/power_intent.upf"
```

**RACE Commands:**
```bash
cbflow run all                        # Complete PNR flow (9 stages)
cbflow run stage --name place1        # Run placement only
cbflow run stage --name cts1          # Run CTS (requires place1)
cbflow run stage --name route1        # Run routing (requires cts_opt1)
cbflow run status                     # Show which stages are done
cbflow run retrace --from cts1        # Re-run from CTS onwards
```

---

### 3.4 STA — Static Timing Analysis

Sign-off timing verification using Synopsys PrimeTime. Each MMMC scenario runs as an independent subnode in the timing1 stage, enabling parallel per-scenario execution.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs1 | setup, netlist, sdc, spef, library, validate, finish | Load netlist, constraints, parasitics |
| extraction1 | setup, run, validate, finish | Parasitic extraction, generate SPEF |
| timing1 | setup, run (per-scenario dynamic subnodes), validate, finish | Setup/hold analysis per MMMC scenario (parallel) |
| reporting1 | setup, run, validate, finish | Generate timing reports |
| release_data1 | setup, run, validate, finish | Package for release |

**User Config — Input Variables:**

```tcl
set sta(input,netlist)       "/path/to/pnr_netlist.v"
set sta(input,sdc_func_file) "/path/to/constraints.sdc"
set sta(input,spef)          "/path/to/parasitics.spef"
```

**Key Outputs:**
- `results/extraction/parasitic.spef` — Extracted parasitics
- `results/timing/timing.rpt` — Static timing report
- `results/timing/violations.rpt` — Timing violations
- `reports/timing/setup_timing.rpt` — Setup analysis
- `reports/timing/hold_timing.rpt` — Hold analysis

---

### 3.5 LEC — Logic Equivalence Checking

Formal verification that two netlists are logically equivalent.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| netlist_golden1 | setup, run, validate, finish | Load golden (reference) netlist |
| netlist_revised1 | setup, run, validate, finish | Load revised (implementation) netlist |
| constraints1 | setup, run, validate, finish | Load Formality constraints/guidance |
| compare1 | setup, run, validate, finish | Match compare points, run formal verification |
| release_data1 | setup, run, validate, finish | Package results for release |

**User Config — Input Variables:**

```tcl
set lec(input,netlist_golden)  "/path/to/golden_netlist.v"
set lec(input,netlist_revised) "/path/to/revised_netlist.v"
set lec(input,constraints)     "/path/to/formality_constraints.svf"
```

**Key Outputs:**
- `results/lec/comparison.rpt` — Comparison results
- `results/lec/equivalence.rpt` — Equivalence analysis
- `results/lec/analysis.log` — Detailed analysis log
- `reports/lec/failing_points.rpt` — Failing compare points

---

### 3.6 EMIR — EM/IR Drop and Thermal Analysis

Power integrity and thermal verification using Synopsys RedHawk.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs | setup, netlist, def, spef, library, validate, finish | Load design with parasitics |
| power_analysis | setup, run, validate, finish | Static and dynamic power consumption |
| ir_drop | setup, run, validate, finish | Static/dynamic IR drop, voltage maps |
| thermal_analysis | setup, run, validate, finish | Thermal simulation, hotspot identification |

**User Config — Input Variables:**

```tcl
set emir(input,netlist) "/path/to/pnr_netlist.v"
set emir(input,def)     "/path/to/routed.def"
set emir(input,spef)    "/path/to/parasitics.spef"
```

**Key Outputs:**
- `results/emir/power_analysis.rpt` — Power report
- `results/emir/ir_drop.rpt` — IR drop analysis
- `results/emir/thermal_analysis.rpt` — Thermal report
- `reports/emir/ir_drop/static_ir.rpt` — Static IR drop
- `reports/emir/thermal/hotspots.rpt` — Thermal hotspots

---

### 3.7 PV — Physical Verification

DRC, LVS, ERC, and PERC checks using Synopsys IC Validator.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs | setup, netlist, def, gds, validate, finish | Load GDS layout and source netlist |
| drc | setup, run, validate, finish | Spacing, width, density, via checks |
| lvs | setup, run, validate, finish | Layout extraction, schematic comparison |
| erc | setup, run, validate, finish | Power/ground connectivity, floating nets |
| perc | setup, run, validate, finish | Reliability, ESD, latch-up checks |
| merge_data | setup, run, validate, finish | Merge all verification results into summary |
| release_data | setup, run, validate, finish | Package reports for release |

> DRC, LVS, ERC, and PERC all depend only on inputs, so they can run in parallel.

**User Config — Input Variables:**

```tcl
set pv(input,netlist) "/path/to/pnr_netlist.v"
set pv(input,def)     "/path/to/routed.def"
set pv(input,gds)     "/path/to/layout.gds"
```

**Key Outputs:**
- `results/drc/drc_results.rpt` — DRC violations
- `results/lvs/lvs_results.rpt` — LVS comparison
- `results/erc/erc_results.rpt` — ERC violations
- `results/perc/perc_results.rpt` — PERC results
- `results/pv/pv_summary.rpt` — Merged summary

---

### 3.8 ECO — Engineering Change Orders

Implement late-stage design changes using Synopsys Fusion Compiler.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs | setup, netlist, def, sdc, library, validate, finish | Load current design + ECO change list |
| eco | setup, run, validate, finish | Analyze impact, implement changes, verify |
| export_db | setup, run, validate, finish | Export modified netlist and database |

**User Config — Input Variables:**

```tcl
set eco(input,netlist)       "/path/to/current_netlist.v"
set eco(input,def)           "/path/to/current.def"
set eco(input,sdc_func_file) "/path/to/constraints.sdc"
set eco(input,eco_script)    "/path/to/eco_changes.tcl"
```

---

### 3.9 CLP — Conformal Low Power Verification

Verifies UPF/CPF power intent correctness using Synopsys VC LP.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs | setup, netlist, upf, power_spec, validate, finish | Load netlist and UPF/CPF power intent |
| clp | setup, run, validate, finish | Connectivity, isolation, level shifter, retention, power switch checks |
| export_data | setup, run, validate, finish | Export verification database and reports |
| release_data | setup, run, validate, finish | Package for release |

**User Config — Input Variables:**

```tcl
set clp(input,netlist)    "/path/to/netlist.v"
set clp(input,upf_file)   "/path/to/power_intent.upf"
set clp(input,power_spec) "/path/to/power_spec.tcl"
```

**Key Outputs:**
- `results/clp/power_verification.rpt` — Verification summary
- `results/db/clp_verification.db` — Verification database
- `reports/clp/connectivity_check.rpt` — Domain connectivity
- `reports/clp/isolation_check.rpt` — Isolation rules
- `reports/clp/level_shifter_check.rpt` — Level shifter rules
- `reports/clp/retention_check.rpt` — Retention rules

---

### 3.10 POPT — Power Optimization

Post-synthesis power optimization using Synopsys PrimeTime.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs | setup, netlist, sdc, upf, validate, finish | Load design with power constraints |
| merge_timing | setup, run, validate, finish | Merge timing data for optimization |
| power_opt | setup, run, validate, finish | Clock gating, multi-Vt, power reduction |
| post_merge | setup, run, validate, finish | Post-optimization validation |
| release_data | setup, run, validate, finish | Package optimized design |

---

### 3.11 FCFP — Fullchip Floorplanning

Chip-level floorplan with macro placement and power planning using Synopsys Fusion Compiler.

**Stages and Subnodes:**

| Stage | Subnodes | What Happens |
|-------|----------|---|
| inputs | setup, netlist, sdc, def, upf, library, validate, finish | Load chip-level design data |
| fc_floorplan | setup, run, validate, finish | Chip die, core utilization, macro placement, blockages |
| fc_powerplan | setup, run, validate, finish | Power grid, stripes, rail connections |
| fc_post_floorplan | setup, run, validate, finish | Congestion and timing optimization |
| export_data | setup, run, validate, finish | Export DEF, database |
| release_data | setup, run, validate, finish | Package deliverables |

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
cd P0_run_PNR_run1

# 5. Run complete flow
cbflow run all

# 6. Check results
cbflow run status
ls reports/
ls results/
```

### 4.2 Running Individual Stages

```bash
cbflow run stage --name inputs1    # Only load inputs
cbflow run stage --name place1     # Only run placement (inputs1 must be done)
cbflow run stage --name cts1       # Only run CTS (place1 must be done)
```

If a dependency stage hasn't run, RACE will run it automatically.

### 4.3 Re-running Stages

CBflow tracks completion in the RACE SQLite database. To re-run a stage:

```bash
# Option 1: Retrace from a stage (marks that node + all downstream for re-execution)
cbflow run retrace --from cts1
cbflow run all    # Re-runs from cts1 onwards

# Option 2: Force re-run a specific node
cbflow run force --node place1
cbflow run all

# Option 3: Bypass a node (skip without running)
cbflow run bypass --node export_data1
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

Generates stages: `synth_inputs`, `synth_synthesis`, `synth_export_data`, ... , `fp_inputs`, `fp_import_design`, `fp_floorplan`, ...

The FP inputs stage automatically depends on the SYNTH export_data stage.

**User Config for Merged Flow:**

```tcl
set flow(type) "SYNTH_FP"

# SYNTH inputs
set synth(input,rtl_files)      "/path/to/rtl.v"
set synth(input,sdc_func_file)  "/path/to/constraints.sdc"

# FP inputs (fed from SYNTH output)
set fp(input,netlist)           "/path/to/synth_netlist.v"
set fp(input,sdc_func_file)    "/path/to/constraints.sdc"
set fp(input,def_file)          "/path/to/seed.def"
```

### 5.2 Other Merged Combinations

- `SYNTH_FP_PNR` — Full front-to-back implementation
- `SYNTH_FP` — Synthesis through floorplan
- Any combination of sequential flows

---

## 6. LSF Submission

### 6.1 Submitting to LSF

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

### 6.3 Checking LSF Status

```bash
cbflow run lsf-status
```

---

## 7. Node and Branch Management

### 7.1 Adding Custom Nodes

Add custom stages to a run after creation:

```bash
# Add an ECO node after signoff
cbflow run add-node --node eco1 --type eco --dep signoff1

# List all nodes
cbflow run list-nodes

# Delete a custom node
cbflow run delete-node --node eco1
```

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
P0_run_PNR_run1/
├── .race_*.db                   RACE SQLite status database (sole status tracking)
├── work/PNR/                    Tool working area
│   ├── inputs/
│   │   ├── netlist/
│   │   ├── sdc/
│   │   └── ...
│   ├── place/
│   │   ├── setup/
│   │   └── run/
│   └── ...
├── reports/                     Generated reports
│   └── timing/
│       ├── setup_timing.rpt
│       └── hold_timing.rpt
├── results/                     Output data
│   ├── netlist/
│   ├── sdc/
│   └── db/
├── logs/                        Execution logs
├── setup/
│   └── user_config.tcl          Your configuration
├── .race_*.db                   RACE status database
├── .run.cbflow.env              Shell environment
├── .run.cbflow.tcl              TCL environment
└── .run.cnflow.tcl              TCL native environment
```

---

## 9. Milestone Release System

### 9.1 Overview

CBflow uses a **milestone-gated release** system. Release tags are predefined (not free-form) and map to design exit milestones. Leads set the **active tag** and **expiry date** at the project level. A release only proceeds when ALL required flows for that milestone have completed successfully.

### 9.2 Predefined Release Tags

| Tag | Description | Min Phase | Required Flows |
|-----|-------------|-----------|----------------|
| `FP_EXIT` | Floorplan Exit | P0 | FP, FCFP, SYNTH_PNR |
| `PLACE_EXIT` | Placement Exit | P0 | SYNTH_PNR, PNR |
| `CTS_EXIT` | CTS Exit | P1 | SYNTH_PNR, PNR |
| `PRO_EXIT` | Post-Route Exit | P1 | SYNTH_PNR, PNR |
| `BTO` | Backend Tapeout | P2 | SYNTH_PNR, PNR, PV, STA, LEC, CLP, EMIR |
| `MTO` | Mask Tapeout | P3 | SYNTH_PNR, PNR, PV, STA, LEC, CLP, EMIR |

Tags are defined in `config/flow/v1.0.0/release_config.tcl`. New tags can be added to the `release_tags` array.

### 9.3 Lead Configuration (Project Level)

Leads control the active tag and expiry in `config/project/<name>/<ver>/<name>_config.tcl`:

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
```

The release command:
1. Validates the tag is predefined
2. Checks the current phase meets the tag's minimum
3. Checks the expiry date hasn't passed
4. **Gate check**: scans workspace for ALL required flow runs with PASS status
5. If any missing: ERROR listing which flows need to be run first
6. If all present: copies deliverables from each flow to the release directory

### 9.5 Release Directory Structure

```
<release_path>/<project>/<design>/<phase>_<tag>/
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
cbflow run release-check --tag BTO --project ravendrive --phase P2

# Check specific block only
cbflow run release-check --tag PLACE_EXIT --project ravendrive --block cpu_core
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

Inputs: `--tag` (required), `--project` (required), `--phase` (default P0), `--block` (optional, default all)

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

### 9.1 Input Variable Naming Convention

Each flow uses a consistent naming pattern for input variables:

```
{flow_array}(input,{input_type})
```

| Flow | Array | Common Input Variables |
|------|-------|---|
| SYNTH | `synth()` | `synth(input,rtl_files)`, `synth(input,sdc_func_file)`, `synth(input,upf_file)` |
| FP | `fp()` | `fp(input,netlist)`, `fp(input,sdc_func_file)`, `fp(input,def_file)`, `fp(input,upf_file)` |
| PNR | `pnr()` | `pnr(input,netlist)`, `pnr(input,sdc_func_file)`, `pnr(input,def_file)`, `pnr(input,upf_file)` |
| STA | `sta()` | `sta(input,netlist)`, `sta(input,sdc_func_file)`, `sta(input,spef)` |
| LEC | `lec()` | `lec(input,netlist_golden)`, `lec(input,netlist_revised)`, `lec(input,constraints)` |
| EMIR | `emir()` | `emir(input,netlist)`, `emir(input,def)`, `emir(input,spef)` |
| PV | `pv()` | `pv(input,netlist)`, `pv(input,def)`, `pv(input,gds)` |
| ECO | `eco()` | `eco(input,netlist)`, `eco(input,def)`, `eco(input,sdc_func_file)`, `eco(input,eco_script)` |
| CLP | `clp()` | `clp(input,netlist)`, `clp(input,upf_file)`, `clp(input,power_spec)` |
| POPT | `popt()` | `popt(input,netlist)`, `popt(input,sdc_func_file)`, `popt(input,upf_file)` |
| FCFP | `fcfp()` | `fcfp(input,netlist)`, `fcfp(input,sdc_func_file)`, `fcfp(input,def_file)`, `fcfp(input,upf_file)` |

### 9.2 Project Phases

| Phase | Description | Typical Activities |
|:---:|---|---|
| **P0** | Initial implementation | First synthesis, initial floorplan, early timing |
| **P1** | Design refinement | Timing closure iterations, power optimization |
| **P2** | Final implementation | Sign-off timing, final DRC/LVS, ECO implementation |
| **P3** | Production release | Tapeout data generation, manufacturing release |

### 9.3 Environment Variables

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

## 10. Typical PD Workflow

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

## 11. Quick Reference

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
cbflow run bypass --node <node>          # Skip a node
cbflow run force --node <node>           # Force re-run
cbflow run forcevalidate --node <node>   # Force validate
cbflow run show-graph                    # Show dependency graph
cbflow run clean --confirm               # Delete work + logs + RACE DB

# ── FLOW INFO ────────────────────────────────────────────────────
cbflow flow types                  # List all 11 flows
cbflow flow info --flow PNR        # Show flow details
cbflow flow stages --flow SYNTH    # List stages

# ── LOGS & DEBUG ─────────────────────────────────────────────────
cbflow run logs --list             # List logs
cbflow run logs --tail 50          # Recent output
cbflow run logs --level ERROR      # Errors only
cbflow run validate                # Validate config + outputs
```
