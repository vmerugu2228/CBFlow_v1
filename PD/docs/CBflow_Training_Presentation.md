---
title: CBflow v2.0 — PD Flow Automation
subtitle: Training Guide for Physical Design Engineers
author: CBflow Team
date: 2026-05-14
---

# CBflow v2.0

## PD Flow Automation Framework

**What you'll learn:**
- What CBflow does and why
- How to create and run flows
- Using the FlowTracer GUI
- Key commands you'll use daily
- Tips & troubleshooting

---

# What is CBflow?

A **unified automation framework** for ASIC Physical Design flows.

| Before CBflow | With CBflow |
|--------------|-------------|
| Manual TCL scripting per run | One config file, automated execution |
| Different scripts per tool/vendor | Same workflow for Synopsys & Cadence |
| No visibility into run progress | Real-time GUI dashboard |
| Hard to reproduce runs | Versioned, locked releases |
| Manual retrace after edits | Auto-detection of file changes |

**One command to rule them all:**
```bash
cbflow workspace create --config user_config.tcl
cbflow run all
```

---

# Supported Flows (12 Total)

| Flow | Description | Stages |
|------|-------------|--------|
| **SYNTH** | Logic Synthesis | 7 stages |
| **PNR** | Place & Route | 13 stages |
| **SYNTH_PNR** | Combined Synth + PNR | 13 stages |
| **STA** | Static Timing Analysis | 8 stages (per-corner parallel) |
| **PV** | Physical Verification (DRC/LVS) | 9 stages |
| **LEC** | Logic Equivalence Checking | 5 stages |
| **CLP** | Clock-Domain Low Power | 5 stages |
| **FP** | Floorplanning | 8 stages |
| **FCFP** | Full-Chip Floorplanning | 13 stages |
| **ECO** | Engineering Change Order | 3 stages |
| **EMIR** | EM/IR Drop Analysis | 4 stages |
| **POPT** | Post-Route Optimization | 5 stages |

**Multi-vendor:** Synopsys (FC, PT, ICV) + Cadence (Innovus, Tempus, Conformal)

---

# How a Flow Works

```
user_config.tcl          RACE Engine              EDA Tool
┌──────────────┐    ┌──────────────────┐    ┌──────────────┐
│ project name │    │ Build DAG        │    │ Fusion       │
│ flow type    │───>│ Track status(DB) │───>│ Compiler     │
│ design inputs│    │ Execute stages   │    │ PrimeTime    │
│ run name     │    │ Parallel subnodes│    │ ICV/Calibre  │
└──────────────┘    └──────────────────┘    └──────────────┘
```

**Each stage has 4 subnodes:**
```
setup ──> run ──> validate ──> finish
```
- **setup** — Generate config files, link libraries
- **run** — Execute the EDA tool command
- **validate** — Check outputs, QoR metrics
- **finish** — Archive results, update status

---

# Getting Started: 3 Steps

### Step 1: Generate a config template
```bash
cbflow workspace template --flow SYNTH_PNR > user_config.tcl
```

### Step 2: Edit the config (your design specifics)
```tcl
set project(name)        "my_project"
set project(phase)       "P0"
set flow(type)           "SYNTH_PNR"
set flow(design_name)    "my_block"
set flow(run_name)       "run1"

set synth_pnr(input,rtl_filelist)   "/path/to/rtl.f"
set synth_pnr(input,sdc_func_file)  "/path/to/func.sdc"
set synth_pnr(input,upf_file)       "/path/to/power.upf"
```

### Step 3: Create & run
```bash
cbflow workspace create --config user_config.tcl
cd P0_run_SYNTH_PNR_run1
cbflow run all
```

---

# Run Directory Structure

```
P0_run_SYNTH_PNR_run1/
├── .run.cbflow.env          # Environment (auto-generated)
├── .run.cbflow.tcl          # TCL environment (auto-generated)
├── .race_*.db               # SQLite status database
├── setup/
│   └── user_config.tcl      # Your config (copied here)
├── work/
│   └── SYNTH_PNR/
│       ├── rtl1/             # Input stage work area
│       ├── synthesis1/       # Synthesis work area
│       ├── place1/           # Placement work area
│       └── ...
├── logs/                     # Execution logs
└── reports/                  # QoR reports
```

**Key:** The `.race_*.db` file is the single source of truth for all job status.

---

# Daily Commands

### Run & Monitor
```bash
cbflow run all                     # Run complete flow
cbflow run stage --stage place1    # Run single stage
cbflow run status                  # Show all stage status
cbflow run gui                     # Open FlowTracer GUI
```

### Control Execution
```bash
cbflow run retrace --from place1   # Re-run place1 + downstream
cbflow run force --stage cts1      # Force re-run cts1
cbflow run bypass --stage signoff1 # Skip a stage
cbflow run forcevalidate --stage synthesis1  # Mark as done
cbflow run stop                    # Stop all running jobs
```

### Clean
```bash
cbflow run clean --confirm         # Delete work + logs
```

---

# FlowTracer GUI

### Launch
```bash
cbflow run gui                     # Auto-opens browser
cbflow run gui --port 9090         # Custom port
```
Port auto-selects (8080-8180) — multiple users can run GUIs simultaneously.

### What You See
- **Left panel:** Project info, design details
- **Center:** DAG graph with color-coded stage status
- **Right panel:** Stage details, config editor

### Color Legend
| Color | Status |
|-------|--------|
| Purple | Idle / Ready |
| Blue | Queued (Pending) |
| Yellow | Running |
| Green | Done |
| Red | Failed |
| Gray | Bypassed |

### Keyboard Shortcuts
`F` Fit to window | `R` Retrace | `V` Force Validate | `Y` Bypass | `E` Edit Config | `S` Stop | `?` Help

### Right-Click Menu
Run, Retrace, Bypass, Force, Force Validate, Edit Config, Duplicate, Create Branch, View Subnodes, MMMC Scenarios

---

# STA: Per-Corner Parallel Execution

STA runs **each timing corner as a separate subnode** — in parallel:

```
                    ┌─ func_ss_0p76v_rcmax_150c ─┐
netlist1 ─> sdc1 ─> setup ─┤                              ├─> validate ─> finish
                    └─ func_ff_0p84v_rcmin_m40c ─┘
```

### Configure in user_config.tcl:
```tcl
set sta(mmmc,scenario_set) "custom"
set sta(mmmc,setup_scenarios) "func_ss_0p76v_rcmax_150c"
set sta(mmmc,hold_scenarios)  "func_ff_0p84v_rcmin_m40c"
```

Each scenario can be independently:
- Force re-run
- Bypassed
- Force-validated

---

# Branching & Custom Nodes

### Create a branch (explore alternatives)
Right-click a node → **Create Branch**

```
rtl1 → synthesis1 → place1 → cts1 → route1 → ...
                  └→ place2 → cts2 → route2 → ...   (branch)
```

### Duplicate a node
Right-click → **Duplicate** — creates a copy with different settings

### Add custom node
Right-click → **Add Node** — insert a new stage into the DAG

All changes are **non-destructive** — the original flow keeps running.

---

# Retrace During Execution

You can retrace/bypass/force-validate **while the flow is running**.

```
Running: rtl1 ✓ → synthesis1 ✓ → place1 [RUNNING] → cts1 [PENDING] → ...
                                    ↑
                        User clicks "Retrace from place1"
                                    ↓
Result:  rtl1 ✓ → synthesis1 ✓ → place1 [INVALIDATED] → cts1 [INVALIDATED] → ...
```

The engine immediately stops executing invalidated stages — no wasted compute.

---

# Release Versioning

### Why it matters
All flow configs, command files, and utilities are **version-locked** per release.

```
v1.0.0 (LOCKED)  ←  Your runs use this — read-only, can't be edited
v1.0.1-dev       ←  CAD team developing next version — writable
```

### What this means for you
- Your runs are **reproducible** — same config = same results
- Nobody can accidentally break your flow by editing a shared file
- Version is recorded in every run: `FLOW_CONFIG_VERSION=v1.0.0`

### Check your version
```bash
grep CBFLOW_RELEASE_VERSION .run.cbflow.env
# → v1.0.0
```

---

# Test Mode

For testing without EDA tools (no licenses needed):

```tcl
set flow(test_mode) "true"
```

- All handlers run but skip actual EDA tool invocation
- Creates stub report files
- Verifies the complete DAG, dependencies, and file flow
- Great for validating configs before launching real runs

---

# Troubleshooting

### Stage failed — how to debug?
```bash
cbflow run status                  # See which stage failed
cbflow run gui                     # Visual status in browser
```
Then check: `work/SYNTH_PNR/<stage>/run/*.log`

### Re-run a failed stage
```bash
cbflow run force --stage place1    # Force re-execute
```

### Skip a blocking stage
```bash
cbflow run bypass --stage signoff1 # Mark as done, continue
```

### Flow stuck / not progressing
```bash
cbflow run stop                    # Stop all, then
cbflow run retrace --from <stage>  # Retrace and re-run
```

### Port in use when launching GUI
The GUI auto-finds a free port (8080-8180). If all ports busy:
```bash
cbflow run gui --port 9999
```

---

# Quick Reference Card

| Task | Command |
|------|---------|
| Generate config template | `cbflow workspace template --flow SYNTH_PNR` |
| Create a run | `cbflow workspace create --config user_config.tcl` |
| Run all stages | `cbflow run all` |
| Run one stage | `cbflow run stage --stage place1` |
| Check status | `cbflow run status` |
| Open GUI | `cbflow run gui` |
| Retrace from stage | `cbflow run retrace --from place1` |
| Force re-run | `cbflow run force --stage cts1` |
| Skip a stage | `cbflow run bypass --stage signoff1` |
| Mark as done | `cbflow run forcevalidate --stage synthesis1` |
| Stop execution | `cbflow run stop` |
| Clean run | `cbflow run clean --confirm` |
| List all runs | `cbflow workspace list-runs` |

---

# Summary

1. **One config file** → `user_config.tcl` with your design inputs
2. **One command** → `cbflow workspace create` + `cbflow run all`
3. **Real-time GUI** → `cbflow run gui` for visual monitoring
4. **Full control** → retrace, bypass, force, branch — even during execution
5. **Reproducible** → locked releases, versioned configs
6. **Multi-vendor** → same workflow for Synopsys and Cadence tools

**Questions?** Check the docs: `PD/docs/02-user-guide/`
