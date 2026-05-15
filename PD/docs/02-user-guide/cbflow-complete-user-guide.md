# CBflow Complete User Guide

**Version:** 2.0.0
**Date:** April 2026
**Author:** CBflow Development Team

---

## Table of Contents

1. [Overview](#1-overview)
2. [System Requirements](#2-system-requirements)
3. [Installation & Setup](#3-installation--setup)
4. [Architecture](#4-architecture)
5. [CLI Command Reference](#5-cli-command-reference)
6. [Supported Flows](#6-supported-flows)
7. [Workspace Management](#7-workspace-management)
8. [Run Execution](#8-run-execution)
9. [Flow Information & Management](#9-flow-information--management)
10. [Configuration System](#10-configuration-system)
11. [LSF Resource Management](#11-lsf-resource-management)
12. [MMMC Support](#12-mmmc-support)
13. [Validation Framework](#13-validation-framework)
14. [Release Management](#14-release-management)
15. [Advanced Features](#15-advanced-features)
16. [Troubleshooting](#16-troubleshooting)

> **GUI Dashboard**: For the full web-based dashboard reference (DAG visualization, config editor, branch management, MMMC scenario editor, keyboard shortcuts), see the dedicated **[GUI User Guide](cbflow-gui-user-guide.md)**.

---

## 1. Overview

CBflow is a comprehensive Physical Design (PD) flow management system for semiconductor chip design. It orchestrates EDA tool execution across 12 design flows using the RACE engine (Python-native DAG executor) with TCL/Python integration.

### Key Features

- **12 design flows** covering the full PD lifecycle (synthesis through tapeout)
- **Multi-tool support** integrating Synopsys and Cadence EDA tools
- **Hierarchical execution** with stage-level and subnode-level granularity
- **SQLite DB-based status tracking** for efficient incremental re-runs
- **LSF integration** with ML-based queue selection
- **MMMC support** for multi-mode multi-corner analysis
- **Version-controlled releases** with component-level tracking
- **Version locking** -- released versions are permanently read-only (`chmod 444` + `.locked` marker), irreversible
- **Dev workflow** -- `cbflow flow dev` commands with `-dev` suffix convention for in-progress versions
- **Web dashboard** for project visibility (auto-port 8080-8180 range)
- **Plugin system** for custom flow extensions

### Design Philosophy

```
User (cbflow CLI)
    |
Python Command Layer (workspace_cmd, run_cmd)
    |
RACE Engine (DAG executor)
    |
TCL Subnode Handlers (setup/run/validate/finish)
    |                    | "run" subnode
    |          Generates launch_<stage>.csh wrapper
    |          (module load + tool_shell -f cmd.tcl)
    |                    |
    |          Launch: LSF/xterm/local based on flow(use_lsf)/flow(use_xterm)
    |
TCL Command Files (EDA tool integration via flow_proc)
```

---

## 2. System Requirements

| Software | Minimum Version | Purpose |
|----------|:-:|---|
| Python | 3.6+ | CLI commands, config parsing, RACE engine |
| TCL/Tclsh | 8.6+ | Flow execution, EDA tool scripting |
| Git | 2.0+ | Version control and release management |
| Bash/Zsh | 4.0+ | Shell environment and completions |

### Optional

| Software | Purpose |
|----------|---|
| LSF (bsub) | Distributed job submission |
| jq | JSON processing in scripts |
| scikit-learn | ML-based LSF queue prediction |

---

## 3. Installation & Setup

### 3.1 Clone and Configure

```bash
# Clone CBflow
git clone <repository-url> CBflow
cd CBflow/PD

# Set core directory
export CBFLOW_CORE_DIR=$(pwd)
export PATH=$CBFLOW_CORE_DIR/bin:$PATH
```

### 3.2 Verify Installation

```bash
cbflow --version
# CBflow Version 2.0.0

cbflow flow check
# Verifies installation, configs, and tool availability
```

### 3.3 Shell Completions (Bash)

Bash tab completion requires sourcing the completion script. Add to your `~/.bashrc`:

```bash
source $CBFLOW_HOME/completions/cbflow.bash
```

To verify, open a new shell and type `cbflow <TAB>` to see available commands.

---

## 4. Architecture

### 4.1 Directory Structure

```
PD/                              (CBFLOW_CORE_DIR)
├── bin/                         CLI entry points
│   ├── cbflow                   Main dispatcher (v2.0.0)
│   ├── cbflow-workspace         Workspace command router
│   ├── cbflow-run               Run command router
│   └── cbflow-flow              Flow command router
├── cmds/                        EDA tool command files (per flow/vendor/tool/version)
│   ├── SYNTH/synopsys/fc/v1.0.0/
│   ├── FP/synopsys/fc/v1.0.0/
│   ├── PNR/synopsys/fc/v1.0.0/
│   ├── STA/synopsys/pt/v1.0.0/
│   ├── LEC/synopsys/formality/v1.0.0/
│   ├── EMIR/synopsys/redhawk/v1.0.0/
│   ├── PV/synopsys/icv/v1.0.0/
│   ├── ECO/synopsys/fc/v1.0.0/
│   ├── CLP/synopsys/vc_lp/v1.0.0/
│   ├── POPT/synopsys/pt/v1.0.0/
│   ├── FCFP/synopsys/fc/v1.0.0/
│   └── SYNTH_PNR/synopsys/fc/v1.0.0/
├── config/                      Configuration hierarchy
│   ├── flow/                    Flow definitions (v1.0.0, v1.0.1, workspace)
│   │   └── v1.0.0/
│   │       ├── flow_config.tcl       Master flow configuration
│   │       ├── dir_config.tcl        Directory structure definitions
│   │       ├── lsf_config.tcl        LSF queue mappings
│   │       ├── mmmc_config.tcl       Multi-corner configuration
│   │       ├── validation_config.tcl Validation rules
│   │       └── node_configs/         Per-flow stage definitions
│   │           ├── SYNTH_config.tcl
│   │           ├── PNR_config.tcl
│   │           └── ...              (12 flow configs)
│   ├── project/                 Project-specific settings
│   ├── tech/                    Technology node parameters
│   ├── setup/                   Flow/tool setup hooks
│   ├── exit/                    Exit milestone criteria
│   └── master_projects.json     Project registry
├── utils/                       Utility modules
│   ├── commands/                Python CLI handlers
│   ├── utilities/               TCL utilities (utils.tcl, error_utils.tcl)
│   ├── generation/              Setup generation
│   ├── validation/              Validation scripts
│   └── dashboard/               Web dashboard
├── releases/                    Versioned release artifacts
│   ├── v1.0.0/
│   │   ├── MANIFEST.json
│   │   ├── release_versions.tcl
│   │   └── components/          Symlinks to versioned components
│   └── current -> v1.0.0
└── docs/                        Documentation
```

### 4.2 Run Directory Structure

When a run is created, CBflow generates this structure:

```
P0_run_PNR_run1/
├── .race_*.db                   RACE SQLite status database (sole status tracking)
├── logs/                        Execution logs
├── setup/                       User configuration
│   └── user_config.tcl
├── work/                        Working directory
│   └── PNR/                     Flow-specific work area

├── .run.cbflow.env              Shell environment (export VAR=val)
├── .run.cbflow.tcl              TCL environment (set ::env(VAR) val)
└── .run.cnflow.tcl              TCL native environment
```

### 4.3 Execution Flow

```
cbflow workspace create --config user_config.tcl
    |
    v
Python: start_run.py creates run directory, env files. RACE builds DAG at runtime.
    |
    v
cbflow run all   (or: cbflow run stage --name place1, etc.)
    |
    v
RACE DAG place1 subnodes (status tracked in SQLite DB):
    place1_setup   -> tclsh place_subnode_handler.tcl setup $PWD
    place1_run     -> tclsh place_subnode_handler.tcl run $PWD
    place1_validate -> ...
    place1_finish   -> ...
    |
    v
place_subnode_handler.tcl (run subnode):
    loads .run.cbflow.tcl, flow_config, user_config
    if test_mode: shows command file
    else: exec tclsh place_innovus.tcl
    |
    v
place_innovus.tcl:
    flow_proc-based procedures
    EDA tool commands (FC place_design, etc.)
    Report generation
```

---

## 5. CLI Command Reference

CBflow uses a three-level command structure:

```
cbflow <command> <subcommand> [options]
```

### 5.1 Global Options

```bash
cbflow --version              # Show version (2.0.0)
cbflow --help                 # Show help
cbflow --completions bash     # Output bash completion script
cbflow --completions zsh      # Output zsh completion script
```

### 5.2 Workspace Commands

Run from any workspace directory (where `.cbflow.env` exists).

```bash
# Generate a user_config.tcl template for a specific flow
cbflow workspace template --flow SYNTH_PNR > user_config.tcl

# Create a run from user config (auto-detects project config + release manifest)
cbflow workspace create --config user_config.tcl
cbflow workspace create --config user_config.tcl --force

# List all runs
cbflow workspace list-runs

# Show status
cbflow workspace status                    # Overview
cbflow workspace status --run 1            # Detailed run status
cbflow workspace status --run 2 --summary  # Full report with metrics

# Validate workspace
cbflow workspace validate

# Clean all runs
cbflow workspace clean --confirm
```

### 5.3 Run Commands

Run from within a run directory (e.g., `P0_run_PNR_run1/`).

```bash
# Execute flow
cbflow run all                             # Run complete flow
cbflow run all --validate                  # With pre/post validation
cbflow run all --lsf                       # Submit via LSF
cbflow run all --lsf --queue XL            # LSF with queue override
cbflow run all --collect-metrics           # Collect metrics after run

# Run individual stage
cbflow run stage --name place              # Run specific stage
cbflow run stage --name cts --lsf          # Run stage via LSF

# Interactive EDA tool session
cbflow run interactive                     # Open empty interactive session in xterm
cbflow run interactive --load place1       # Load saved design from place1 stage

# Status and monitoring
cbflow run status                          # Stage completion overview
cbflow run status --details                # Show all subnodes per stage
cbflow run lsf-status                      # LSF job queue status

# Logs
cbflow run logs --list                     # List all log files
cbflow run logs --tail 50                  # Last 50 lines
cbflow run logs --tail 100 --level ERROR   # Filter by level

# Validation
cbflow run validate                        # Full validation
cbflow run validate --type config          # Config only
cbflow run validate --stage cts            # Stage outputs + exit criteria

# Retracing (re-run from a stage)
cbflow run retrace --from cts              # Rerun from CTS onwards

# Node management
cbflow run show-graph                      # Show dependency graph
cbflow run show-graph --detail             # Show with subnodes
cbflow run add-node --node eco1 --type eco --dep signoff
cbflow run delete-node --node eco1
cbflow run list-nodes                      # List all nodes

# Clean
cbflow run clean --confirm                 # Delete work + logs + RACE DB
```

### 5.4 Flow Commands

Run from `CBFLOW_CORE_DIR` only.

```bash
# Flow information
cbflow flow types                          # List all 12 flow types
cbflow flow info --flow PNR                # Show PNR details (tool, stages)
cbflow flow stages --flow SYNTH            # List SYNTH stages
cbflow flow nodes --flow PV              # Show PV node structure
cbflow flow check                          # Verify CBflow installation

# Project management
cbflow flow project list                   # List all projects
cbflow flow project info --name ravendrive    # Show project details
cbflow flow project create                 # Create new project (interactive)

# Release management
cbflow flow release list                   # List all releases
cbflow flow release info --version v1.0.0  # Show release details
cbflow flow release diff --v1 v1.0.0 --v2 v1.0.1

# Dev workflow
cbflow flow dev start --dir cmds/SYNTH --from v1.0.0  # Start dev version
cbflow flow dev status                     # Show active dev versions
cbflow flow dev diff --dir cmds/SYNTH      # Show dev changes
cbflow flow dev promote --dir cmds/SYNTH --version v1.0.1  # Promote to release
cbflow flow dev sandbox-create --name exp1 # Create sandbox
cbflow flow dev sandbox-push --name exp1   # Push sandbox changes

# Configuration management
cbflow flow config manage-flow             # Interactive flow config editor
cbflow flow config manage-node             # Interactive node config editor
cbflow flow config status                  # Show configuration status

# Plugin system
cbflow flow plugin list                    # List registered plugins
cbflow flow plugin scaffold --name MYFLOW --vendor acme --tool mytool

# Metrics and dashboard
cbflow flow metrics collect                # Collect metrics to database
cbflow flow metrics report                 # Show metrics summary
cbflow flow metrics report --flow PNR      # Filter by flow
cbflow flow metrics export --format csv    # Export metrics
cbflow flow dashboard start                # Start web dashboard (auto-port 8080-8180)
```

---

## 6. Supported Flows

CBflow supports 12 design flows covering the complete PD lifecycle:

### 6.1 Flow Summary

| Flow | Description | Tool | Vendor | Stages |
|------|-------------|------|--------|:---:|
| **SYNTH** | Logic synthesis and optimization | Fusion Compiler | Synopsys | 4 |
| **FP** | Floorplanning and power planning | Fusion Compiler | Synopsys | 6 |
| **PNR** | Place and route implementation | Fusion Compiler | Synopsys | 9 |
| **STA** | Static timing analysis and sign-off (PT-RM W-2024.09) | PrimeTime | Synopsys | 5 |
| **LEC** | Logic equivalence checking | Formality | Synopsys | 5 |
| **EMIR** | Power and thermal analysis | RedHawk | Synopsys | 4 |
| **PV** | Physical verification (ICV-RM V-2023.12) | IC Validator | Synopsys | 9 |
| **ECO** | Engineering change orders | Fusion Compiler | Synopsys | 3 |
| **CLP** | Conformal low power verification | VC LP | Synopsys | 4 |
| **POPT** | Power optimization and clock gating | PrimeTime | Synopsys | 5 |
| **FCFP** | Fullchip floorplanning | Fusion Compiler | Synopsys | 6 |
| **SYNTH_PNR** | Unified synthesis + PNR | Fusion Compiler | Synopsys | 11 |

### 6.2 Flow Details

#### SYNTH (Synthesis)

Transforms RTL to gate-level netlist using Synopsys Fusion Compiler.

```
inputs1 --> synthesis1 --> export_data1 --> release_data1
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs1 | rtl, sdc, library, upf, validate, finish | Load RTL, constraints, libraries |
| synthesis1 | setup, run, validate, finish | Elaborate, synthesize, optimize |
| export_data1 | setup, run, validate, finish | Export netlist, SDC, database |
| release_data1 | setup, run, validate, finish | Package for release |

---

#### FP (Floorplanning)

Physical floorplan creation using Synopsys Fusion Compiler.

```
inputs --> import_design --> floorplan --> powerplan --> export_data --> release_data
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs | netlist, sdc, def, upf, library, validate, finish | Load design data |
| import_design | setup, run, validate, finish | Import into Fusion Compiler |
| floorplan | setup, run, validate, finish | Create chip floorplan |
| powerplan | setup, run, validate, finish | Power grid creation |
| export_data | setup, run, validate, finish | Export DEF, database |
| release_data | setup, run, validate, finish | Package deliverables |

---

#### PNR (Place and Route)

Full place-and-route implementation using Synopsys Fusion Compiler.

```
inputs1 --> place1 --> cts1 --> cts_opt1 --> route1 --> pro1 --> signoff1 --> export_data1 --> release_data1
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs1 | netlist, sdc, def, upf, library, validate, finish | Load design data |
| place1 | setup, run, validate, finish | Cell placement |
| cts1 | setup, run, validate, finish | Clock tree synthesis |
| cts_opt1 | setup, run, validate, finish | CTS optimization |
| route1 | setup, run, validate, finish | Global and detail routing |
| pro1 | setup, run, validate, finish | Post-route optimization |
| signoff1 | setup, run, validate, finish | Timing sign-off |
| export_data1 | setup, run, validate, finish | Export final data |
| release_data1 | setup, run, validate, finish | Package for release |

---

#### STA (Static Timing / STA)

Static timing analysis using Synopsys PrimeTime (PT-RM W-2024.09 aligned, DMSA-style per-corner analysis). Each corner runs independently -- there is no MMMC concept in PT/Tempus. The timing1 stage is dynamic: each corner appears as a subnode in status.

```
inputs1 --> extraction1 --> timing1 (per-corner) --> reporting1 --> release_data1
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs1 | setup, netlist, sdc, spef, library, validate, finish | Load design + parasitics |
| extraction1 | setup, run, validate, finish | Parasitic extraction (SPEF) |
| timing1 | setup, run (per-corner), validate, finish | Setup/hold timing per corner (dynamic subnodes) |
| reporting1 | setup, run, validate, finish | Generate timing reports |
| release_data1 | setup, run, validate, finish | Package for release |

---

#### LEC (Logic Equivalence Checking)

Formal verification using Synopsys Formality.

```
netlist_golden1 --> netlist_revised1 --> constraints1 --> compare1 --> release_data1
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| netlist_golden1 | setup, run, validate, finish | Load golden (reference) netlist |
| netlist_revised1 | setup, run, validate, finish | Load revised (implementation) netlist |
| constraints1 | setup, run, validate, finish | Load Formality constraints/guidance |
| compare1 | setup, run, validate, finish | Run formal comparison |
| release_data1 | setup, run, validate, finish | Package results for release |

---

#### EMIR (EM/IR Analysis)

Power and thermal analysis using Synopsys RedHawk.

```
inputs --> power_analysis --> ir_drop --> thermal_analysis
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs | setup, netlist, def, spef, library, validate, finish | Load design data |
| power_analysis | setup, run, validate, finish | Static/dynamic power |
| ir_drop | setup, run, validate, finish | IR drop analysis, voltage maps |
| thermal_analysis | setup, run, validate, finish | Thermal simulation, hotspots |

---

#### PV (Physical Verification)

DRC/LVS/ERC/PERC/XOR checks using Synopsys IC Validator (ICV-RM V-2023.12 aligned). Fill runs first to generate filled GDS, then DRC/LVS/PERC/ERC/XOR run in parallel, followed by merge and release.

```
inputs1 --> fill1 --> drc1  \
                  --> lvs1   \
                  --> perc1   --> merge_data1 --> release_data1
                  --> erc1   /
                  --> xor1  /
```

Note: fill1 runs first (generates filled GDS). DRC, LVS, PERC, ERC, and XOR run in parallel after fill, then merge.

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs1 | setup, netlist, def, gds, validate, finish | Load GDS, netlist |
| fill1 | setup, run, validate, finish | Metal fill / OD fill insertion (generates filled GDS) |
| drc1 | setup, run, validate, finish | Design rule checks (spacing, width, density, via) |
| lvs1 | setup, run, validate, finish | Layout vs schematic comparison |
| perc1 | setup, run, validate, finish | Parasitic extraction rule checks (reliability, ESD, latchup) |
| erc1 | setup, run, validate, finish | Electrical rule checks (power, ground, floating) |
| xor1 | setup, run, validate, finish | XOR comparison between design versions |
| merge_data1 | setup, run, validate, finish | Merge all verification results |
| release_data1 | setup, run, validate, finish | Package for release |

---

#### ECO (Engineering Change Orders)

Design modifications using Synopsys Fusion Compiler.

```
inputs --> eco --> export_db
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs | setup, netlist, def, sdc, library, validate, finish | Load design data |
| eco | setup, run, validate, finish | Analyze, implement, verify ECO changes |
| export_db | setup, run, validate, finish | Export modified design |

---

#### CLP (Conformal Low Power)

Low-power verification using Synopsys VC LP.

```
inputs --> clp --> export_data --> release_data
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs | setup, netlist, upf, power_spec, validate, finish | Load netlist + UPF/CPF |
| clp | setup, run, validate, finish | LP verification (connectivity, isolation, level shifter, retention, power switch) |
| export_data | setup, run, validate, finish | Export database + reports |
| release_data | setup, run, validate, finish | Package for release |

---

#### POPT (Power Optimization)

Power optimization using Synopsys PrimeTime.

```
inputs --> merge_timing --> power_opt --> post_merge --> release_data
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs | setup, netlist, sdc, upf, validate, finish | Load design data |
| merge_timing | setup, run, validate, finish | Merge timing data |
| power_opt | setup, run, validate, finish | Power optimization, clock gating |
| post_merge | setup, run, validate, finish | Post-merge validation |
| release_data | setup, run, validate, finish | Package for release |

---

#### FCFP (Fullchip Floorplanning)

Chip-level floorplanning using Synopsys Fusion Compiler.

```
inputs --> fc_floorplan --> fc_powerplan --> fc_post_floorplan --> export_data --> release_data
```

| Stage | Subnodes | Description |
|-------|----------|-------------|
| inputs | setup, netlist, sdc, def, upf, library, validate, finish | Load design data |
| fc_floorplan | setup, run, validate, finish | Chip-level floorplan, macro placement |
| fc_powerplan | setup, run, validate, finish | Power grid, stripes, rail connections |
| fc_post_floorplan | setup, run, validate, finish | Congestion/timing optimization |
| export_data | setup, run, validate, finish | Export DEF, database |
| release_data | setup, run, validate, finish | Package deliverables |

---

## 7. Workspace Management

### 7.1 Creating a Workspace

A workspace is created in a single step using `cbflow workspace create --config`. There is no separate `workspace init` command -- the `create` command handles workspace initialization and run directory creation together.

```bash
# Generate a user_config.tcl template for a specific flow
cbflow workspace template --flow SYNTH_PNR > user_config.tcl

# Edit user_config.tcl (see below), then create the workspace and first run
cbflow workspace create --config user_config.tcl

# Creates: P0_run_SYNTH_PNR_run1/
#   with .run.cbflow.env, .run.cbflow.tcl, etc.
```

### 7.2 User Configuration

Edit `user_config.tcl` before creating a run. The template generated by `cbflow workspace template` includes all required fields:

```tcl
#!/usr/bin/env tclsh
# Project settings
set project(name)        "ravendrive"
set project(phase)       "P0"
set project(technology)  "gf_22nm"

# Design settings
set design(name)         "cpu_core"
set design(top_module)   "cpu_core"

# Flow settings
set flow(type)           "SYNTH_PNR"
set flow(run_name)       "run1"
set flow(test_mode)      false       ;# Set to true to bypass EDA tools
set flow(use_lsf)        true        ;# Enable LSF job submission
set flow(use_xterm)      true        ;# Launch stages in xterm windows

# Input paths (customize for your design)
set pnr(input,netlist)       "/path/to/synthesized_netlist.v"
set pnr(input,sdc_func_file) "/path/to/constraints.sdc"
set pnr(input,def_file)      "/path/to/floorplan.def"
set pnr(input,upf_file)      "/path/to/power_intent.upf"
```

### 7.3 Managing Runs

```bash
# Create additional runs (increment run_name in user_config.tcl first)
cbflow workspace create --config user_config.tcl

# Force-recreate an existing run
cbflow workspace create --config user_config.tcl --force

# List all runs
cbflow workspace list-runs

# Check workspace status
cbflow workspace status
```

The run directory naming pattern is `{phase}_run_{flow}_{run_name}/`, for example: `P0_run_SYNTH_PNR_run1/`.

### 7.4 Test Mode

Set `flow(test_mode) true` in user_config.tcl to run without EDA tools. In test mode, CBflow:
- Executes all stages and subnodes
- Creates directory structures and updates RACE DB status
- Shows command file contents instead of invoking tools
- Useful for validating flow structure and configuration

---

## 8. Run Execution

### 8.1 Running a Complete Flow

```bash
cd P0_run_PNR_run1/

# Run all stages
cbflow run all
```

### 8.2 Running Individual Stages

```bash
# Run specific stages
cbflow run stage --name inputs1
cbflow run stage --name place1
cbflow run stage --name cts1
```

### 8.3 Incremental Execution

CBflow uses the RACE SQLite database to track stage completion. Re-running `cbflow run all` skips completed stages:

```bash
# First run: executes all stages
cbflow run all

# Retrace from a specific stage to re-run from that point
cbflow run retrace --from cts1

# Re-run: only executes cts1 and downstream stages
cbflow run all
```

### 8.4 Retrace (Re-run from Stage)

```bash
# Retrace from CTS onwards (marks cts1 and all downstream for re-execution in RACE DB)
cbflow run retrace --from cts1

# Then re-run
cbflow run all
```

### 8.5 Stage Execution Architecture

Each stage has 4 standard subnodes (`setup`, `run`, `validate`, `finish`). The `run` subnode is where the EDA tool is actually invoked. Here is the detailed execution path:

```
cbflow run stage --name place
  |
  v
RACE executes stage (cbflow run stage --name place1)
  |
  v
tclsh handler.tcl run
  |
  v
Sources configuration:
  - .run.cbflow.tcl        (run environment)
  - flow_config.tcl        (global flow definitions)
  - node_config.tcl        (stage/subnode definitions)
  - user_config.tcl        (user overrides)
  - tool_launch_config.tcl (tool paths, module loads, bsub settings)
  |
  v
Generates: work/SYNTH_PNR/place1/run/launch_place.csh
  - Contains: module load commands + tool_shell -f <cmd>.tcl
  |
  v
Launch based on flow(use_lsf) and flow(use_xterm):
  - LSF + xterm:  bsub -Is ... xterm -e launch_place.csh
  - LSF batch:    bsub ... launch_place.csh
  - xterm local:  xterm -e launch_place.csh
  - local:        csh -f launch_place.csh
```

The inputs stage has additional subnodes for each input type (netlist, sdc, def, etc.).

### 8.6 Monitoring Progress

```bash
# Quick status (queries RACE DB)
cbflow run status

# Detailed status with subnodes
cbflow run status --details

# View dependency graph
cbflow run show-graph
cbflow run show-graph --detail   # Shows subnodes

# Check logs
cbflow run logs --list
cbflow run logs --tail 50 --level ERROR
```

---

## 9. Flow Information & Management

### 9.1 Listing Flows

```bash
cbflow flow types
# Lists all 12 flows with descriptions

cbflow flow info --flow PNR
# Shows: tool, vendor, version, stages, subnodes

cbflow flow stages --flow SYNTH
# Lists stages with dependencies
```

### 9.2 Project Management

```bash
cbflow flow project list
# Shows: ravendrive, india

cbflow flow project info --name ravendrive
# Shows: technology, enabled flows, phases, chip lead
```

### 9.3 Viewing Flow Graphs

```bash
cbflow run show-graph
# ASCII dependency graph:
#
# [inputs1] --> [place1] --> [cts1] --> [cts_opt1] --> [route1] --> [pro1] --> [signoff1]
```

---

## 10. Configuration System

### 10.1 Configuration Hierarchy

CBflow loads configuration in this order (later overrides earlier):

```
1. flow_config.tcl          (Global flow definitions)
2. {FLOW}_config.tcl         (Flow-specific stages/subnodes)
3. project_config.tcl        (Project: design hierarchy, constraints)
4. tech_config.tcl           (Technology: libraries, design rules)
5. setup hooks               (flow_proc_prepend/append hooks)
6. .run.cbflow.tcl           (Run-specific environment)
7. user_config.tcl           (User overrides)
```

### 10.2 Flow Configuration (`flow_config.tcl`)

Defines global settings for all flows:

```tcl
set flow(types) {SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR}
set flow(run_type) "node"        ;# "node" (default) or "flat"
set flow(test_mode) "false"
set flow(phases) {P0 P1 P2 P3}
```

### 10.3 Node Configuration (`{FLOW}_config.tcl`)

Each flow has a dedicated config file defining:

```tcl
# Stage definitions
array set pnr {
    stages {inputs1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}
    subnodes,place1 {setup run validate finish}
    dependencies,place1 {inputs1}
    tool,vendor "cadence"
    tool,name "innovus"
    runtime,timeout,place1 120
}
```

#### Tool Override in user_config

To switch a flow's EDA tool without editing the flow config, set the tool vendor and name in `user_config.tcl`:

```tcl
# Switch PNR from Synopsys FC to Cadence Innovus
set pnr(tool,vendor) "cadence"
set pnr(tool,name)   "innovus"
```

This overrides the default tool selection for that flow in the current run only.

### 10.4 Tool Configuration (`fc_config.tcl`, `pt_config.tcl`, etc.)

Each EDA tool has a dedicated tool config file that defines tool-specific parameters using a two-level scoping convention:

- **`<tool>(common,*)`** -- Settings shared across all nodes in the flow
- **`<tool>(<node>,*)`** -- Settings specific to a particular node (overrides common)

```tcl
# fc_config.tcl -- Fusion Compiler tool settings

# Common settings (apply to all FC-based nodes)
set fc(common,enable_clock_gating)        true
set fc(common,target_library)             "sc7p5t_cln28hpm_base_rvt_c14_tt_nominal_max_0p90v_25c.db"
set fc(common,enable_spg)                 true

# Node-specific settings (override common for this node only)
set fc(place1,congestion_effort)          high
set fc(place1,enable_coarse_placement)    false
set fc(cts1,max_skew)                     50
set fc(route1,detail_route_effort)        high
```

Tool config files follow the naming pattern `<tool>_config.tcl` (e.g., `fc_config.tcl` for Fusion Compiler, `pt_config.tcl` for PrimeTime).

The GUI Config Editor exposes these settings under the **Tool Config** tab with search, filter, and scope toggles. See the [GUI User Guide](cbflow-gui-user-guide.md#8-config-editor) for details.

#### Config Editor Categories (GUI)

The GUI Config Editor organizes settings into 5 categories:

| Category | Source | Description |
|----------|--------|-------------|
| **Node Config** | `SYNTH_PNR_config.tcl` | Stages, dependencies, subnodes, timeouts |
| **Tool Config** | `fc_config.tcl` / `pt_config.tcl` | Tool-specific parameters (`fc(common,*)` + `fc(<node>,*)`) |
| **LSF & Resources** | `tool_launch_config.tcl` | Queue tier, memory, CPU, runtime limit |
| **Flow Settings** | `flow_config.tcl` / `user_config.tcl` | `use_lsf`, `tool_module`, `test_mode` |
| **Exit Criteria** | `exit/` configs | Milestone exit files and thresholds |

Changes made in the Config Editor are saved to `override_config.tcl` in the run's setup directory.

### 10.4 Project Configuration

Located in `config/project/{project_name}/v1.0.0/{project}_config.tcl`:

```tcl
# Design hierarchy
set project(design_hierarchy) {
    chip_top {DL1 - Full chip}
    cpu_core {DL3 - Component}
}

# Clock constraints
set project(clock,period) 1.0
set project(clock,uncertainty) 0.1

# Power domains
set project(power,domains) {PD_CPU PD_MEM PD_IO PD_TOP}
```

### 10.5 Technology Configuration

Located in `config/tech/{tech_node}/v1.0.0/tech_config.tcl`:

```tcl
set tech(node) "gf_22nm"
set tech(lib,timing) {libs/timing/slow.lib libs/timing/fast.lib}
set tech(lef,standard_cells) "libs/lef/std_cells.lef"
set tech(lef,technology) "libs/lef/tech.lef"
```

### 10.6 Setup Hooks

Located in `config/setup/common/v1.0.0/{FLOW}/{vendor}/{tool}/`:

```tcl
# global_setup.tcl - runs for all stages
flow_proc_prepend flow_init {
    # Tool-specific initialization
    file mkdir "logs/genus"
}

flow_proc_append generate_reports {
    # Generate tool-specific summary after reports
}
```

### 10.7 Directory Configuration (`dir_config.tcl`)

Defines the standard directory structure created for each run:

```tcl
set directory(PNR) {
    "logs"          ;# Execution logs
    "setup"         ;# Configuration files
    "work"          ;# Working directory

    "work/PNR"      ;# Flow-specific work area
}
;# Note: Stage completion is tracked in the RACE SQLite database, not on disk.

```

---

## 11. LSF Resource Management

### 11.1 Launch Modes

CBflow supports 4 launch modes for stage execution, controlled by `flow(use_lsf)` and `flow(use_xterm)` in `user_config.tcl`:

| Mode | `flow(use_lsf)` | `flow(use_xterm)` | Behavior |
|------|:---:|:---:|---|
| **LSF + xterm** | true | true | `bsub -Is ... xterm -e launch_<stage>.csh` (interactive LSF with visible terminal) |
| **LSF batch** | true | false | `bsub ... launch_<stage>.csh` (batch LSF submission) |
| **xterm local** | false | true | `xterm -e launch_<stage>.csh` (local execution with visible terminal) |
| **local** | false | false | `csh -f launch_<stage>.csh` (direct local execution) |

LSF is auto-enabled from the `flow(use_lsf)` configuration in `user_config.tcl`. No environment variable is needed.

```tcl
# In user_config.tcl
set flow(use_lsf)    true    ;# Enable LSF job submission
set flow(use_xterm)  true    ;# Launch in xterm windows
```

### 11.2 Wrapper Script Generation

For every stage's `run` subnode, CBflow generates a `launch_<stage>.csh` wrapper script under `work/<FLOW>/<stage>/run/`. This wrapper includes:

1. **Module loads** -- Loads the correct EDA tool environment (e.g., `module load synopsys/fc/2023.09`)
2. **Tool shell invocation** -- Runs the tool shell with the command file (e.g., `fc_shell -f place_fc.tcl`)

The module loads and tool shell commands are read from `tool_launch_config.tcl`.

### 11.3 bsub Command Construction

When LSF is enabled, the `bsub` command is built from settings in `tool_launch_config.tcl`:

- **Queue** -- Mapped per flow and stage (e.g., PNR/route uses XL queue)
- **Memory** -- Resource requirement per queue type
- **CPU count** -- Number of cores requested
- **Runtime limit** -- Maximum wall-clock time
- **Interactive flag** -- `-Is` when `flow(use_xterm)` is true

### 11.4 Queue Type Mapping

Each flow/stage combination maps to a queue type in `tool_launch_config.tcl`:

| Flow | Light (S) | Medium (M) | Heavy (L) | Very Heavy (XL) |
|------|-----------|------------|-----------|-----------------|
| **SYNTH** | inputs, export, release | synthesis | - | - |
| **PNR** | inputs, release | export | place, cts, cts_opt, pro, signoff | route |
| **STA** | inputs, release | reporting | extraction, timing (per-corner) | - |
| **PV** | inputs, merge, release | erc, perc, xor | fill, drc, lvs | - |
| **EMIR** | inputs | - | power, ir_drop | thermal |

### 11.5 Escape Hatch: CBFLOW_BSUB_CMD

For advanced use cases where the auto-generated bsub command is insufficient, you can set the `CBFLOW_BSUB_CMD` environment variable to provide a fully custom bsub command string. When set, CBflow uses this command directly instead of building one from `tool_launch_config.tcl`.

```bash
# Override the entire bsub command
export CBFLOW_BSUB_CMD="bsub -q custom_queue -R 'rusage[mem=48000]' -n 24 -Is"
```

---

## 12. MMMC Support

Multi-Mode Multi-Corner analysis is configured in `mmmc_config.tcl`.

### 12.1 Process Corners

| Corner | Name | Setup Critical | Hold Critical |
|:---:|---|:---:|:---:|
| ss | slow_slow | Yes | No |
| tt | typical_typical | No | No |
| ff | fast_fast | No | Yes |
| sf | slow_fast | No | Yes |

### 12.2 Operating Conditions

- **Nominal Voltage:** 0.80V
- **Low Voltage:** 0.72V
- **Hot Temperature:** 125C
- **Cold Temperature:** -40C

### 12.3 Timing Derates

- Early (hold): 0.95
- Late (setup): 1.05
- Clock uncertainty: 0.1ns

---

## 13. Validation Framework

### 13.1 Validation Types

```bash
cbflow run validate                    # Full validation
cbflow run validate --type config      # Configuration only
cbflow run validate --type inputs      # Input files only
cbflow run validate --type outputs     # Output files only
cbflow run validate --stage place1     # Stage-specific validation
```

### 13.2 Critical Error Detection

CBflow monitors logs for critical errors with tool-specific patterns:

- **SYNTH (FC):** GENUS-001, SYN_FATAL, GEN_ABORT, memory exhaustion, license failures
- **PNR (FC):** INNOVUS-301, ROUTE_ERROR, PNR_ABORT
- **FP (FC):** INNOVUS-201, FP_ERROR, FP_FATAL

When critical errors are detected, CBflow can launch an xterm alert for immediate visibility.

### 13.3 Exit Milestones

CBflow defines exit criteria at key design milestones:

| Milestone | Description |
|-----------|-------------|
| FP_EXIT | Floorplan complete, area/utilization targets met |
| PLACE_EXIT | Placement complete, timing/congestion acceptable |
| CTS_EXIT | Clock tree synthesized, skew targets met |
| PRO_EXIT | Post-route optimization complete |
| BTO | Backend tapeout ready |
| MTO | Manufacturing tapeout ready |

---

## 14. Release Management

### 14.1 Release Structure

```
releases/
├── v1.0.0/
│   ├── MANIFEST.json           Component versions and paths
│   ├── release_versions.tcl    TCL version variables
│   ├── CHANGELOG.md            Release notes
│   └── components/             Symlinks to versioned components
│       ├── cmds_SYNTH_cadence_genus -> ../../../cmds/SYNTH/synopsys/fc/v1.0.0
│       ├── cmds_PNR_cadence_innovus -> ../../../cmds/PNR/synopsys/fc/v1.0.0
│       └── ...
├── v1.0.1/
└── current -> v1.0.0
```

### 14.2 Release Commands

```bash
cbflow flow release list
cbflow flow release info --version v1.0.0
cbflow flow release create --type patch --desc "Bug fix release"
cbflow flow release diff --v1 v1.0.0 --v2 v1.0.1
```

### 14.3 Version Management

```bash
cbflow flow version list --dir cmds/SYNTH
cbflow flow version create --dir cmds/SYNTH --type minor --desc "Added new optimization"
cbflow flow version promote --dir cmds/SYNTH --version v1.1.0
```

### 14.4 Version Locking

Released versions are permanently read-only. When a version is released, CBflow applies `chmod 444` to all files and creates a `.locked` marker file. This is irreversible -- there is no way to unlock or revert a locked version.

```bash
# After release, the version directory becomes read-only:
# cmds/SYNTH/synopsys/fc/v1.0.0/.locked   (marker file)
# All files in v1.0.0/ are chmod 444

# Attempting to edit a locked version will fail:
# Permission denied: cmds/SYNTH/synopsys/fc/v1.0.0/synthesis_fc.tcl
```

To make changes to a locked version, create a new version (copy) or use the dev workflow.

### 14.5 Dev Workflow

The dev workflow provides a structured way to develop and test changes before promoting them to a released version. Dev versions use the `-dev` suffix convention (e.g., `v1.0.0-dev`).

```bash
# Start a dev version from an existing released version
cbflow flow dev start --dir cmds/SYNTH --from v1.0.0
# Creates: cmds/SYNTH/synopsys/fc/v1.0.0-dev/ (writable copy)

# Check status of all active dev versions
cbflow flow dev status

# View changes made in a dev version
cbflow flow dev diff --dir cmds/SYNTH

# Create an isolated sandbox for experimentation
cbflow flow dev sandbox-create --name experiment1

# Push sandbox changes back to the dev version
cbflow flow dev sandbox-push --name experiment1

# Promote dev version to a new released version (applies version locking)
cbflow flow dev promote --dir cmds/SYNTH --version v1.0.1
# v1.0.1 is created, locked (chmod 444 + .locked), and v1.0.0-dev is removed
```

---

## 15. Advanced Features

### 15.1 Merged Flows

CBflow supports merging multiple flows into a single run:

```bash
# Generate config for merged flow
cbflow workspace template --flow SYNTH_FP > user_config.tcl
# Edit user_config.tcl, then:
cbflow workspace create --config user_config.tcl

# Stages will be prefixed: synth_inputs, synth_synthesis, ..., fp_inputs, fp_floorplan, ...
```

### 15.2 Custom Nodes

Add custom stages to an existing flow:

```bash
cd P0_run_PNR_run1/

# Add a custom ECO node after signoff
cbflow run add-node --node eco1 --type eco --dep signoff1

# Create a branch for experimental runs
cbflow run create-branch --name experiment_timing
```

### 15.3 Plugin System

Create custom flow plugins:

```bash
# Generate a flow plugin template
cbflow flow plugin scaffold --name MYFLOW --vendor acme --tool mytool

# Register the plugin
cbflow flow plugin register --name MYFLOW

# List plugins
cbflow flow plugin list
```

### 15.4 Metrics and Dashboard

```bash
# Collect run metrics
cbflow flow metrics collect

# View metrics report
cbflow flow metrics report
cbflow flow metrics report --flow PNR

# Export to CSV
cbflow flow metrics export --format csv

# Launch web dashboard (auto-selects available port in 8080-8180 range)
cbflow run gui
# Open http://localhost:<port> in browser (port printed on startup)
```

The web dashboard provides a full GUI for DAG visualization, node execution control, configuration editing, branch management, and MMMC scenario management. For the complete dashboard reference, see the **[GUI User Guide](cbflow-gui-user-guide.md)**.

### 15.5 Flat Execution Mode

Merge execution nodes to reduce EDA tool license usage:

```tcl
# In user_config.tcl
set flow(run_type) "flat"
```

In flat mode, multiple stages are combined into a single merged execution to minimize license checkouts.

---

## 16. Troubleshooting

### 16.1 Common Issues

**Problem:** `cbflow run all` fails with DAG build error
- **Cause:** RACE DAG build failure
- **Fix:** Re-create the run with `cbflow workspace create --config user_config.tcl --force`

**Problem:** `ERROR: .run.cbflow.tcl not found`
- **Cause:** Running cbflow from wrong directory
- **Fix:** Ensure you are inside the run directory (e.g., `cd P0_run_PNR_run1/`)

**Problem:** `list must have an even number of elements`
- **Cause:** TCL comments (`#`) inside `array set {}` blocks in config files
- **Fix:** Move comments outside the `array set` braces

**Problem:** Stage appears stuck / status not updating in RACE DB
- **Cause:** Subnode handler failed silently
- **Fix:** Check logs with `cbflow run logs --tail 100 --level ERROR`

**Problem:** Wrong queue selected for LSF
- **Cause:** Stage name mismatch between config and LSF mappings
- **Fix:** Verify stage names in `{FLOW}_config.tcl` match `lsf_config.tcl`

### 16.2 Useful Debug Commands

```bash
# Show what would run without executing
cbflow run verify-dag

# Check environment
cat .run.cbflow.env

# Verify config loading
tclsh -e 'source .run.cbflow.tcl; parray ::env'

# Check status from RACE DB
cbflow run status --details

# Force re-run a specific node
cbflow run force --node place1
cbflow run all
```

### 16.3 Test Mode Debugging

Enable test mode to validate flow structure without EDA tools:

```tcl
# In user_config.tcl
set flow(test_mode) true
```

Test mode shows the command file that would be executed at each stage, useful for verifying paths and configurations.

---

## Appendix A: Environment Variables

### Workspace Variables (set during `workspace create`)

| Variable | Description | Example |
|----------|-------------|---------|
| CBFLOW_PROJECT | Project name | ravendrive |
| CBFLOW_CORE_DIR | CBflow installation root | /tools/cbflow/PD |
| CBFLOW_RELEASE_VERSION | Active release | v1.0.0 |

### Run Variables (set during `workspace create`)

| Variable | Description | Example |
|----------|-------------|---------|
| CBFLOW_RUN_DIR | Run directory path | /work/P0_run_PNR_run1 |
| CBFLOW_FLOW_TYPE | Flow type | PNR |
| CBFLOW_DESIGN_NAME | Design/block name | cpu_core |
| CBFLOW_RUN_NAME | Run identifier | run1 |
| CBFLOW_PROJECT_PHASE | Project phase | P0 |
| FLOW_DIR | CBflow core directory | /tools/cbflow/PD |
| CONFIG_ROOT | Config directory | /tools/cbflow/PD/config |
| SCRIPTS_ROOT | Utils directory | /tools/cbflow/PD/utils |

### Component Versions (from release)

| Variable | Description |
|----------|-------------|
| FLOW_CONFIG_VERSION | Flow config version |
| UTILITIES_VERSION | Utilities version |
| GENERATION_VERSION | Setup generator version |
| VALIDATION_VERSION | Validation scripts version |

---

## Appendix B: Project Phases

| Phase | Description | Typical Activities |
|:---:|---|---|
| P0 | Initial implementation | RTL integration, first synthesis, initial floorplan |
| P1 | Design refinement | Timing closure, power optimization, DRC/LVS clean |
| P2 | Final implementation | Sign-off timing, final verification, ECO implementation |
| P3 | Production release | Tapeout preparation, manufacturing data generation |

---

## Appendix C: Quick Reference Card

```
# Setup
cbflow workspace template --flow PNR > user_config.tcl
cbflow workspace create --config user_config.tcl

# Execute
cd P0_run_PNR_run1/
cbflow run all                          # Run complete flow
cbflow run stage --name place1          # Run single stage
cbflow run status                       # Check progress

# Monitor
cbflow run status --details
cbflow run show-graph
cbflow run logs --tail 50 --level ERROR

# Re-run / Control
cbflow run retrace --from cts1          # Re-run from CTS onwards
cbflow run bypass --node export_data1   # Skip a node
cbflow run force --node place1          # Force re-run
cbflow run forcevalidate --node signoff1  # Force validate

# Debug
cbflow run validate
cbflow run verify-dag

# Info
cbflow flow types
cbflow flow info --flow PNR
cbflow flow stages --flow SYNTH
```
