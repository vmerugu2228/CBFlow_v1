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
11. [Metal Stack Configuration](#11-metal-stack-configuration)
12. [LSF Resource Management](#12-lsf-resource-management)
13. [MMMC Support](#13-mmmc-support)
14. [Validation Framework](#14-validation-framework)
15. [Run Ownership & Protection](#15-run-ownership--protection)
16. [Database Schema](#16-database-schema)
17. [Exit Checklist System](#17-exit-checklist-system)
18. [Release Management](#18-release-management)
19. [Advanced Features](#19-advanced-features)
20. [Troubleshooting](#20-troubleshooting)

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
- **Web dashboard** for project visibility (per-user run-dashboard daemon; SmartGrid per project)
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
| Bash/Zsh | 4.0+ | Shell environment and completions (`cbflow --completions bash|zsh`) |

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
git clone <repository-url> CBflow_clone
export CBFLOW_ROOT=$PWD/CBflow_clone          # the only user-facing variable
export PATH=$CBFLOW_ROOT/bin:$PATH
```

`CBFLOW_GLOBAL_DIR` (`$CBFLOW_ROOT/global`), `CBFLOW_CORE_DIR` (`$CBFLOW_ROOT/PD`), `CBFLOW_DFT_DIR`,
`CBFLOW_DV_DIR` and `CBFLOW_RTL_DIR` are derived by the launcher.

### 3.2 Verify Installation

```bash
cbflow --version        # v2.0.0 + the resolved root / global / discipline directories
cbflow flow check       # Verifies installation, configs, and tool availability
```

### 3.3 Shell Completions

```bash
eval "$(cbflow --completions bash)"     # add to ~/.bashrc
eval "$(cbflow --completions zsh)"      # zsh
```

---

## 4. Architecture

### 4.1 Directory Structure

```
CBflow_clone/                    $CBFLOW_ROOT
├── bin/                         cbflow (-> global/bin/cbflow) and cbflow-* launchers
├── global/                      Cross-discipline layer, sourced by every run
│   ├── bin/                     cbflow, cbflow-flow, cbflow-oss (open-source tool container), ...
│   ├── config/
│   │   ├── flow/v1.0.0/flow_registry.tcl     flow catalog, discipline map, runtime + dashboard defaults
│   │   ├── exit/v1.0.0/                      exit milestone + STA_SIGNOFF configs, waiver_config.tcl
│   │   ├── tech/<tech>/v1.0.0/tech_config.tcl
│   │   ├── project/<proj>/v1.0.0/            <proj>_config.tcl, mmmc_*.tcl, schedule_config.tcl, team_config.tcl
│   │   └── cli/discipline_commands.tcl
│   └── utils/                   commands/ (race_engine, run_cmd, ...), utilities/, generation/,
│                                dashboard/ (run dashboard), project_dashboard/ (SmartGrid), validation/
├── PD/                          $CBFLOW_CORE_DIR
│   ├── bin/cbflow-pd            library-manager, mmmc-manager, checklist
│   ├── config/
│   │   ├── project/<proj>/v1.0.0/<proj>_pd_config.tcl   workarea, release, lsf, lib_root, lib_tag_root
│   │   ├── flow/v1.0.0/         flow_config.tcl, release_config.tcl, lsf_config.tcl, dir_config.tcl,
│   │   │                        tool_launch_config.tcl, node_configs/<FLOW>_config.tcl + <FLOW>_<tool>_config.tcl
│   │   └── setup/               flow_proc hook files
│   ├── cmds/<FLOW>/<vendor>/<tool>/v1.0.0/   command files (synopsys, cadence, opensource)
│   └── utils/commands/          library_manager, mmmc_manager, checklist, ...
├── DFT/  DV/  RTL/              same shape (bin/cbflow-<disc>, config/, cmds/, utils/)
└── workarea/                    project(workarea_path) of the example projects
```

### 4.2 Run Directory Structure

When a run is created, CBflow generates this structure:

```
LC2_run_PNR_cpu_core_run1/
├── .race_db_pointer             Points to RACE DB in race area
├── .race_<run>_<user>_<hash>.db  RACE SQLite status database (in race area)
├── logs/                        Execution logs
├── setup/                       User configuration
│   └── user_config.tcl
├── work/                        Working directory
│   └── PNR/                     Flow-specific work area

├── .run.cbflow.env              Shell environment (export VAR=val)
└── .run.cbflow.tcl              TCL environment (set ::env(VAR) val)
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

Run from the block's workarea `<project(workarea_path)>/<block>/` (enforced by `workspace create`).

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

Run from within a run directory (e.g., `LC2_run_PNR_cpu_core_run1/`; pattern `<phase>_run_<FLOW>_<block>_<run>`).

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

# Interactive EDA tool session (restores a node's saved design)
cbflow run interactive --node place1
cbflow run interactive --node timing1_func_ss_0p80v_rcmax_125c   # STA: one scenario

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
cbflow run retrace --from cts              # Clear CTS onwards (add --run to rerun)
cbflow run force --stages place1           # Re-run only place1
cbflow run bypass --stages export_data1    # Mark done without running
cbflow run forcevalidate --from netlist1 --to init_design1

# Node management
cbflow run show-graph                      # Show dependency graph
cbflow run show-graph --detail             # Show with subnodes
cbflow run add-node --node place2 --type place --dep place1
cbflow run set-dep --node export_data1 --deps place1      # rewire (--reset to restore)
cbflow run delete-node --node place2
cbflow run create-branch --branch timing_fix --from cts1
cbflow run list-nodes                      # List all nodes

# Releases (see exit-release-guide.md)
cbflow run release --tag PRO_EXIT --dry-run
cbflow run release --from-run . --publish
cbflow run release-check --tag BTO --project bumblebee --phase LC3

# Dashboard
cbflow run gui                             # register with the per-user run dashboard and open it

# Clean
cbflow run clean --confirm                 # Delete work + logs + RACE DB
```

### 5.4 Flow Commands

`cbflow flow …` works from anywhere; PD-owned subcommands (`library-manager`, `mmmc-manager`, `checklist`)
auto-dispatch to `PD/bin/cbflow-pd`.

```bash
# Flow information
cbflow flow types                          # Flow types by discipline (--domain PD|DFT|DV)
cbflow flow info --flow PNR                # Show PNR details (tool, stages)
cbflow flow stages --flow SYNTH            # List SYNTH stages
cbflow flow nodes --flow PV              # Show PV node structure
cbflow flow check                          # Verify CBflow installation

# Project management
cbflow flow project list                   # List all projects
cbflow flow project info --name bumblebee    # Show project details
cbflow flow project create                 # Create new project (interactive)

# Release management
cbflow flow release list                   # List all releases
cbflow flow release info --version v1.0.0  # Show release details
cbflow flow release diff --v1 v1.0.0 --v2 v1.0.1

# Dev workflow
cbflow flow dev start --component config/flow --from v1.0.0  # Start dev version
cbflow flow dev status                     # Show active dev versions
cbflow flow dev diff --component config/flow                # Show dev changes
cbflow flow dev promote --component config/flow             # Promote to release-ready
cbflow flow dev sandbox-create             # Create local sandbox (--base / --dir)
cbflow flow dev sandbox-push               # Push sandbox to central

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
cbflow flow dashboard start                # Start project/run browser (auto-port 8080-8999)

# PD-owned
cbflow flow library-manager check --tech skywater_130nm --lib_tag OSS2
cbflow flow mmmc-manager show --project opensky --tech skywater_130nm
cbflow flow checklist list --discipline PD

# Dashboards
cbflow run dashboard status --discipline PD          # per-user run dashboard daemon
cbflow smartgrid start --project opensky             # SmartGrid project dashboard
```

---

## 6. Supported Flows

PD has 12 flow types; DFT (7), DV (9) and RTL (5) flows are listed by `cbflow flow types`. Stage lists below are the
default (Synopsys) node configs — `cbflow flow stages --flow <FLOW>` prints the current list, and a tool overlay
(`<flow>(tool,name)`, e.g. `openroad`, `innovus`) can change it. Inputs per flow: [Flow User Guide §3](cbflow-flow-user-guide.md#3-flow-inputs).

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

Every stage has the subnodes `setup`, `run`, `validate`, `finish`. STA's `timing1` expands into one subnode per
MMMC scenario (`timing1_<mode>_<corner>_<voltage>_<rc>_<temp>`).

---

## 7. Workspace Management

### 7.1 Creating a Workspace

A workspace is created in a single step using `cbflow workspace create --config`. There is no separate `workspace init` command -- the `create` command handles workspace initialization and run directory creation together.

```bash
# Generate a user_config.tcl template for a specific flow
cbflow workspace template --flow SYNTH_PNR > user_config.tcl

# Edit user_config.tcl (see below), then create the workspace and first run
cbflow workspace create --config user_config.tcl

# Creates: LC1_run_SYNTH_PNR_cpu_core_run1/
#   with .run.cbflow.env, .run.cbflow.tcl, etc.
```

### 7.2 User Configuration

Edit `user_config.tcl` before creating a run. The template generated by `cbflow workspace template` includes all required fields:

```tcl
#!/usr/bin/env tclsh
# Project settings
set project(name)        "bumblebee"
set project(phase)       "LC1"       ;# optional: default project(current_phase)

# Flow settings
set flow(type)           "SYNTH_PNR"
set flow(design_name)    "cpu_core"
set flow(run_name)       "run1"
set flow(test_mode)      "false"     ;# "true" = bypass EDA tools (dummy outputs)
set flow(use_lsf)        "true"      ;# submit via bsub (bsub must be on PATH)
set flow(use_xterm)      "false"     ;# "true" = launch jobs in xterm windows

# Input paths (customize for your design)
set synth_pnr(input,rtl_filelist)  "/path/to/cpu_core.f"
set synth_pnr(input,rtl_format)    "sverilog"
set synth_pnr(input,sdc_func_file) "/path/to/cpu_core_func.sdc"
set synth_pnr(input,upf_file)      "/path/to/cpu_core.upf"
```

Defaults (`global/config/flow/v1.0.0/flow_registry.tcl`): `test_mode=false`, `use_lsf=false`, `use_xterm=true`.
`workspace create` refuses `use_lsf=true` without `bsub` and `use_xterm=true` without `xterm`.

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

The run directory naming pattern is `{phase}_run_{flow}_{block}_{run_name}/`, for example: `LC1_run_SYNTH_PNR_cpu_core_run1/`.

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
cd LC2_run_PNR_cpu_core_run1/

# Run all stages
cbflow run all
```

### 8.2 Running Individual Stages

```bash
# Run specific stages
cbflow run stage --name netlist1
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
# Lists the flow types by discipline (PD 12, DFT 7, DV 9, RTL 5)

cbflow flow info --flow PNR
# Shows: tool, vendor, version, stages, subnodes

cbflow flow stages --flow SYNTH
# Lists stages with dependencies
```

### 9.2 Project Management

```bash
cbflow flow project list
# Shows: bumblebee, india

cbflow flow project info --name bumblebee
# Shows: technology, enabled flows, phases, chip lead
```

### 9.3 Viewing Flow Graphs

```bash
cbflow run show-graph
# ASCII dependency graph:
#
# [init_design1] --> [place1] --> [cts1] --> [cts_opt1] --> [route1] --> [pro1] --> [signoff1]
```

---

## 10. Configuration System

### 10.1 Configuration Hierarchy

CBflow loads configuration in this order (later overrides earlier):

```
1. global/config/project/<proj>/v1.0.0/<proj>_config.tcl         identity, hierarchy, phases, exit plans
2. <disc>/config/project/<proj>/v1.0.0/<proj>_<disc>_config.tcl  discipline overlays (PD: workarea, release, lsf, lib roots / tag)
3. global/config/tech/<tech>/v1.0.0/tech_config.tcl              + the library tag's lib_config.tcl / blocks_config.tcl
4. global/config/flow/v1.0.0/flow_registry.tcl                   flow catalog, runtime defaults
5. <disc>/config/flow/v1.0.0/flow_config.tcl
6. <disc>/config/flow/v1.0.0/node_configs/<FLOW>_config.tcl + <FLOW>_<tool>_config.tcl
7. global/config/project/<proj>/v1.0.0/mmmc_config.tcl
8. <run>/setup/user_config.tcl
9. <run>/setup/override_config.tcl -> .<stage> -> .<branch> -> .<node_type> -> .<node>
```

The result is one generated `work/<FLOW>/<node>/run/config.tcl` per node; flow_proc hooks go in
`setup/override_setup*.tcl` and `PD/config/setup/`.

### 10.2 Flow Configuration (`flow_config.tcl`)

Defines global settings for all flows:

The flow catalog (`flow(types)`, `flow(discipline,<FLOW>)`) and the cross-discipline runtime defaults
(`flow(test_mode)`, `flow(use_lsf)`, `flow(use_xterm)`, dashboard ports) live in
`global/config/flow/v1.0.0/flow_registry.tcl`; `PD/config/flow/v1.0.0/flow_config.tcl` holds the PD mandatory
variables and node-config dispatch. Phases are project-defined (`project(phases)`), not a flow setting.

### 10.3 Node Configuration (`{FLOW}_config.tcl`)

Each flow has a dedicated config file defining:

```tcl
# Stage definitions
array set pnr {
    stages {netlist1 sdc1 def1 upf1 init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1}
    subnodes,place1 {setup run validate finish}
    dependencies,place1 {init_design1}
    node_types,place1 "place"
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

### 10.4 Tool Configuration (`<FLOW>_<tool>_config.tcl`)

Each flow uses **one array** (`pnr()`, `sta()`, …) — there are no tool arrays (`fc()`, `pt()`). The tool overlay
`<FLOW>_<tool>_config.tcl` next to the node config is selected by `<flow>(tool,name)` and adds the tool's settings
to the same array:

```tcl
# PD/config/flow/v1.0.0/node_configs/PNR_fc_config.tcl
array set pnr {
    tool,vendor   "synopsys"
    tool,name     "fc"
    tool,version  "v1.0.0"
    place,effort               "high"
    place,congestion_aware     true
    place,max_density          0.85
}
```

Override any key per run in `user_config.tcl` (`set pnr(place,max_density) 0.80`) or per node in
`setup/override_config.<node>.tcl`. The open-source overlays use `<flow>(oss,…)` keys (e.g. `pnr(oss,place,density)`).

The GUI Config Editor exposes these settings under the **Tool Config** tab with search, filter, and scope toggles. See the [GUI User Guide](cbflow-gui-user-guide.md#8-config-editor) for details.

#### Config Editor Categories (GUI)

The GUI Config Editor organizes settings into 5 categories:

| Category | Source | Description |
|----------|--------|-------------|
| **Node Config** | `SYNTH_PNR_config.tcl` | Stages, dependencies, subnodes, timeouts |
| **Tool Config** | `SYNTH_PNR_fc_config.tcl` (`<FLOW>_<tool>_config.tcl`) | Tool-specific keys of the flow array |
| **LSF & Resources** | `tool_launch_config.tcl` | Queue tier, memory, CPU, runtime limit |
| **Flow Settings** | `flow_config.tcl` / `user_config.tcl` | `use_lsf`, `tool_module`, `test_mode` |
| **Exit Criteria** | `global/config/exit/v1.0.0/` configs | Milestone exit files and thresholds |

Changes made in the Config Editor are saved to `override_config.tcl` in the run's setup directory.

### 10.4 Project Configuration

Located in `global/config/project/{project_name}/v1.0.0/{project}_config.tcl` (identity, hierarchy, phases, exit plans) plus the PD overlay `PD/config/project/{project_name}/v1.0.0/{project}_pd_config.tcl` (workarea, release, LSF, library roots / tag):

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

Located in `global/config/tech/{tech_node}/v1.0.0/tech_config.tcl` (one file per technology; the former PD tech overlay is merged in):

```tcl
set tech(node) "gf_22nm"
set tech(lib,timing) {libs/timing/slow.lib libs/timing/fast.lib}
set tech(lef,standard_cells) "libs/lef/std_cells.lef"
set tech(lef,technology) "libs/lef/tech.lef"
```

### 10.6 Setup Hooks

Located in `PD/config/setup/common/…` (all projects) and `PD/config/setup/<project>/…`; per run in `setup/override_setup*.tcl`:

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

## 11. Metal Stack Configuration

### 11.1 Setting the Metal Stack

The metal stack defines the full interconnect layer configuration for your technology node. Set it in your project config:

```tcl
# In global/config/project/<name>/v1.0.0/<name>_config.tcl
set project(metal_stack) "gf22naphlogl24uhf116a_11M_2Mx_6Cx_1Jx_2Qx_LB"
```

### 11.2 Available Options

Each technology node provides multiple metal stack options. The naming convention encodes the layer composition:

| Stack | Layers | Composition |
|-------|:---:|---|
| 8M | 8 | 2Mx + 4Cx + 1Jx + 1Qx |
| 9M | 9 | 2Mx + 5Cx + 1Jx + 1Qx |
| 10M | 10 | 2Mx + 5Cx + 1Jx + 2Qx |
| 11M | 11 | 2Mx + 6Cx + 1Jx + 2Qx |

Layer types: **Mx** (thin metal), **Cx** (intermediate metal), **Jx** (semi-global metal), **Qx** (global/thick metal).

### 11.3 What Auto-Resolves

Once `project(metal_stack)` is set, the following are automatically resolved:

- **Routing layers** -- Number and names of routable layers
- **Clock layers** -- Preferred layers for clock tree routing
- **TLU+ files** -- Parasitic extraction models per RC corner
- **PG strap definitions** -- Power grid width/pitch/layers for each strap tier
- **Via stacks** -- Available via definitions between layers

### 11.4 Per-Layer Properties

Each layer in the stack provides these properties:

```tcl
# Auto-populated per layer:
tech(metal_stack,M1,direction)    ;# horizontal or vertical
tech(metal_stack,M1,pitch)        ;# minimum pitch (nm)
tech(metal_stack,M1,width)        ;# minimum width (nm)
tech(metal_stack,M1,spacing)      ;# minimum spacing (nm)
tech(metal_stack,M1,type)         ;# Mx, Cx, Jx, or Qx
```

### 11.5 Adding a New Metal Stack Option

To add a new metal stack option for a technology node:

1. Define the stack in `global/config/tech/<node>/v1.0.0/tech_config.tcl` (+ `metal_stack/<stack>.tcl`)
2. Provide per-layer properties (direction, pitch, width, spacing, type)
3. Map the stack to TLU+ files for each RC corner
4. Define PG strap configurations for the new layer count
5. The stack becomes available via `project(metal_stack)` in any project config

---

## 12. LSF Resource Management

### 12.1 Launch Modes

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

### 12.2 Wrapper Script Generation

For every stage's `run` subnode, CBflow generates a `launch_<stage>.csh` wrapper script under `work/<FLOW>/<stage>/run/`. This wrapper includes:

1. **Module loads** -- Loads the correct EDA tool environment (e.g., `module load synopsys/fc/2023.09`)
2. **Tool shell invocation** -- Runs the tool shell with the command file (e.g., `fc_shell -f place_fc.tcl`)

The module loads and tool shell commands are read from `tool_launch_config.tcl`.

### 12.3 bsub Command Construction

When LSF is enabled, the `bsub` command is built from settings in `tool_launch_config.tcl`:

- **Queue** -- Mapped per flow and stage (e.g., PNR/route uses XL queue)
- **Memory** -- Resource requirement per queue type
- **CPU count** -- Number of cores requested
- **Runtime limit** -- Maximum wall-clock time
- **Interactive flag** -- `-Is` when `flow(use_xterm)` is true

### 12.4 Queue Type Mapping

Each flow/stage combination maps to a queue type in `tool_launch_config.tcl`:

| Flow | Light (S) | Medium (M) | Heavy (L) | Very Heavy (XL) |
|------|-----------|------------|-----------|-----------------|
| **SYNTH** | inputs, export, release | synthesis | - | - |
| **PNR** | inputs, release | export | place, cts, cts_opt, pro, signoff | route |
| **STA** | inputs, release | reporting | extraction, timing (per-corner) | - |
| **PV** | inputs, merge, release | erc, perc, xor | fill, drc, lvs | - |
| **EMIR** | inputs | - | power, ir_drop | thermal |

### 12.5 Escape Hatch: CBFLOW_BSUB_CMD

For advanced use cases where the auto-generated bsub command is insufficient, you can set the `CBFLOW_BSUB_CMD` environment variable to provide a fully custom bsub command string. When set, CBflow uses this command directly instead of building one from `tool_launch_config.tcl`.

```bash
# Override the entire bsub command
export CBFLOW_BSUB_CMD="bsub -q custom_queue -R 'rusage[mem=48000]' -n 24 -Is"
```

---

## 13. MMMC Support

Multi-Mode Multi-Corner analysis is configured in `mmmc_config.tcl`.

### 13.1 Process Corners

| Corner | Name | Setup Critical | Hold Critical |
|:---:|---|:---:|:---:|
| ss | slow_slow | Yes | No |
| tt | typical_typical | No | No |
| ff | fast_fast | No | Yes |
| sf | slow_fast | No | Yes |

### 13.2 Operating Conditions

- **Nominal Voltage:** 0.80V
- **Low Voltage:** 0.72V
- **Hot Temperature:** 125C
- **Cold Temperature:** -40C

### 13.3 Timing Derates

- Early (hold): 0.95
- Late (setup): 1.05
- Clock uncertainty: 0.1ns

---

## 14. Validation Framework

### 14.1 Validation Types

```bash
cbflow run validate                    # Full validation
cbflow run validate --type config      # Configuration only
cbflow run validate --type inputs      # Input files only
cbflow run validate --type outputs     # Output files only
cbflow run validate --stage place1     # Stage-specific validation
```

### 14.2 Critical Error Detection

CBflow monitors logs for critical errors with tool-specific patterns:

- **SYNTH (FC):** GENUS-001, SYN_FATAL, GEN_ABORT, memory exhaustion, license failures
- **PNR (FC):** INNOVUS-301, ROUTE_ERROR, PNR_ABORT
- **FP (FC):** INNOVUS-201, FP_ERROR, FP_FATAL

When critical errors are detected, CBflow can launch an xterm alert for immediate visibility.

### 14.3 Exit Milestones

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

## 15. Run Ownership & Protection

### 15.1 Ownership Model

Every run in CBflow is owned by its creator. The ownership is enforced via UID-based checks in both the RACE engine and the web dashboard.

**Only the run creator can:**
- Retrace (re-run from a stage)
- Add or delete nodes
- Bypass or force nodes
- Delete the run
- Modify run configuration

**Everyone can:**
- View run status (`cbflow run status`)
- Access the GUI dashboard (`cbflow run gui`)
- Read logs (`cbflow run logs`)
- View the DAG graph (`cbflow run show-graph`)

### 15.2 Enforcement

Ownership is determined by the UID of the user who executed `cbflow workspace create`. This is stored in the RACE database at creation time. Any modification attempt by a different UID results in an error:

```
ERROR: Permission denied. Run owned by <creator_uid>. Only the creator can modify this run.
```

---

## 16. Database Schema

### 16.1 Overview

The RACE engine uses a SQLite database with 13 tables for comprehensive run tracking and data collection.

### 16.2 Database Tables

| Table | Purpose |
|-------|---------|
| `jobs` | Node/subnode execution status, start/end times, exit codes |
| `run_info` | Run metadata (creator, creation time, flow type, phase) |
| `run_config` | Resolved configuration snapshot at run creation |
| `job_order` | DAG execution order and dependency tracking |
| `dag_structure` | Full DAG definition (nodes, edges, subnode hierarchy) |
| `stage_metrics` | Per-stage metrics (runtime, memory, QoR data) |
| `design_info` | Design metadata (cell count, area, utilization) |
| `checklist_results` | Exit milestone check results and waivers |
| `release_info` | Release history and milestone tags |
| `lsf_details` | LSF job IDs, queues, resource usage |
| `run_logs` | Structured log entries with severity levels |
| `metrics_snapshot` | Point-in-time metrics for trending |
| `config_history` | Configuration change tracking across retraces |

### 16.3 Database Location

The RACE database is stored in the race area configured by `project(race,db_path)`. A pointer file (`.race_db_pointer`) in the run directory references the actual database location.

**Database naming convention:**
```
.race_<run_dir>_<user>_<hash>.db
```

Where:
- `<run_dir>` -- Abbreviated run directory name
- `<user>` -- Creator's username
- `<hash>` -- Short hash for uniqueness

### 16.4 Database Management

```bash
# List all RACE databases with status
cbflow run db-manage --list
# Shows: database path, run association, ACTIVE/ORPHANED status, size, creator

# Interactive cleanup of orphaned databases (owner-only)
cbflow run db-manage --cleanup
# Prompts for confirmation before removing orphaned DBs
# Only the DB owner can clean up their databases
```

---

## 17. Exit Checklist System

### 17.1 Overview

CBflow provides an exit checklist system with milestones for every discipline (`cbflow flow checklist list`): PD FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO (+ the STA_SIGNOFF checklist); DFT, DV and RTL exits alongside. Exit configs live in `global/config/exit/v1.0.0/`; checks activate progressively with the project's phases.

### 17.2 Milestones

| Discipline | Milestones (`cbflow flow checklist list`) |
|-----------|-------------|
| PD | FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO; STA_SIGNOFF checklist (STA_0001…STA_0015, published with every STA run) |
| DFT | CORE_DFT_EXIT, TOP_DFT_EXIT, EDT_OCC_EXIT, SCAN_INSERT_EXIT, ATPG_PREPD_EXIT, ATPG_POSTPD_EXIT |
| DV | SPEC_RAMP_EXIT, PLANNING_EXIT, TB_SETUP_EXIT, M1_EXIT, M2_EXIT, M3_EXIT, M4_EXIT, ECO_EXEC_EXIT, DV_SIGNOFF_EXIT |
| RTL | SPEC_EXIT, LINT_SIGNOFF, CDC_SIGNOFF, UPF_SIGNOFF |

Signoff flows (STA / PV / LEC) attach to the exit they verify rather than having exits of their own.

### 17.3 Check Categories and IDs

Each check has a unique ID with a category prefix:

| Prefix | Category | Example Checks |
|--------|----------|----------------|
| TMG | Timing | Setup/hold slack, transition |
| PLC | Placement | Utilization, congestion, cell overlap |
| CLK | Clock | Skew targets, insertion delay, clock DRC |
| RTG | Routing | DRC violations, antenna, shorts |
| PWR | Power | IR drop, EM violations, power budget |
| PHY | Physical | Cell density, pin access, blockage |
| SI | Signal integrity | Crosstalk, noise |
| MFG | Manufacturing | Metal density, via redundancy, antenna |

PD milestones draw from a library of 182 checks in 9 categories (the above plus eco_flow); DFT / DV milestones use
mandatory files + per-flow metric checks; RTL flows use `violations_final.csv`.

### 17.4 CLI Commands

```bash
# Milestones (filter by owning discipline)
cbflow flow checklist list
cbflow flow checklist list --discipline DFT

# Checks of a milestone (milestone auto-detected from a run dir when omitted)
cbflow flow checklist list-checks --milestone BTO --phase P2
cbflow flow checklist list-checks --milestone BTO --phase P3 --run-dir . --summary

# Evaluate against a run / generate the checklist
cbflow flow checklist status   --milestone PLACE_EXIT --run-dir .
cbflow flow checklist generate --milestone BTO --phase P3 --format html
cbflow run checklist --milestone PRO_EXIT --phase P2            # same, from inside the run

# Record sign-off
cbflow flow checklist sign-off --milestone BTO --run-dir . --approver chip_lead

# Manage individual checks
cbflow flow checklist add-check --milestone BTO --name timing_clean --type mandatory \
    --description "Setup WNS must be >= 0" --script check_timing.tcl --criteria "setup_wns >= 0"
cbflow flow checklist remove-check --milestone BTO --name timing_clean

# Waivers (max 90 days; no BTO / MTO waivers — waiver_config.tcl)
cbflow flow checklist waiver --action list --milestone BTO
cbflow flow checklist waiver --action add --milestone PRO_EXIT --check congestion_analysis \
    --reason "Known hotspot, ECO planned" --approver chip_lead --expiry 2026-12-31
cbflow flow checklist waiver --action revoke --waiver-id W001
```

`--discipline PD|DFT|DV|RTL` filters by the milestone's owner (`milestone_info(discipline)`).

### 17.5 Phase Filtering

Checks are phase-aware. The same milestone applies different criteria depending on the project phase:

Phases are project-defined (`project(phases)`: opensky P0-P3, bumblebee LC1-LC5). Each check declares the
phase from which it is active; `--phase` filters to the checks active at that phase, so later phases enforce more.

### 17.6 Auto-Detection

When running checklist commands from within a run directory, CBflow auto-detects:
- The milestone (from flow type and completed stages)
- The phase (the run's phase, `CBFLOW_PROJECT_PHASE` — from `project(phase)` in the user config, else `project(current_phase)`)
- The run context (from `.run.cbflow.tcl`)

No flags needed for the common case -- just `cbflow flow checklist status` from your run directory.

---

## 18. Release Management

### 18.1 Release Structure

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

### 18.2 Release Commands

```bash
cbflow flow release list
cbflow flow release info --version v1.0.0
cbflow flow release create --type patch --desc "Bug fix release"
cbflow flow release diff --v1 v1.0.0 --v2 v1.0.1
```

### 18.3 Version Management

```bash
cbflow flow version list --dir config/flow
cbflow flow version copy --dir config/flow --from v1.0.0 --to v1.0.1
cbflow flow version create --dir config --version v2.0.0 --desc "New features"
cbflow flow version set-current --dir config/flow --version v1.0.1
```

### 18.4 Version Locking

Released versions are permanently read-only. When a version is released, CBflow applies `chmod 444` to all files and creates a `.locked` marker file. This is irreversible -- there is no way to unlock or revert a locked version.

```bash
# After release, the version directory becomes read-only:
# cmds/SYNTH/synopsys/fc/v1.0.0/.locked   (marker file)
# All files in v1.0.0/ are chmod 444

# Attempting to edit a locked version will fail:
# Permission denied: cmds/SYNTH/synopsys/fc/v1.0.0/synthesis_fc.tcl
```

To make changes to a locked version, create a new version (copy) or use the dev workflow.

### 18.5 Dev Workflow

The dev workflow provides a structured way to develop and test changes before promoting them to a released version. Dev versions use the `-dev` suffix convention (e.g., `v1.0.0-dev`).

```bash
# Start a dev version from an existing released version
cbflow flow dev start --component config/flow --from v1.0.0
# Creates: config/flow/v1.0.0-dev/ (writable copy)

# Check status of all active dev versions
cbflow flow dev status

# View changes made in a dev version
cbflow flow dev diff --component config/flow

# Create an isolated sandbox for experimentation
cbflow flow dev sandbox-create

# Push sandbox changes back to the dev version
cbflow flow dev sandbox-push

# Promote dev version to a new released version (applies version locking)
cbflow flow dev promote --component config/flow
# the next version is created and locked (chmod 444 + .locked); the -dev copy is removed
```

---

## 19. Advanced Features

### 19.1 Merged Flows

CBflow supports merging multiple flows into a single run:

```bash
# Generate config for merged flow
cbflow workspace template --flow SYNTH_FP > user_config.tcl
# Edit user_config.tcl, then:
cbflow workspace create --config user_config.tcl

# Stages will be prefixed: synth_inputs, synth_synthesis, ..., fp_inputs, fp_floorplan, ...
```

### 19.2 Custom Nodes

Add custom stages to an existing flow:

```bash
cd LC2_run_PNR_cpu_core_run1/

# Add a custom ECO node after signoff
cbflow run add-node --node place2 --type place --dep place1

# Create a branch for experimental runs
cbflow run create-branch --branch experiment_timing --from cts1
```

### 19.3 Plugin System

Create custom flow plugins:

```bash
# Generate a flow plugin template
cbflow flow plugin scaffold --name MYFLOW --vendor acme --tool mytool

# Register the plugin
cbflow flow plugin register --name MYFLOW

# List plugins
cbflow flow plugin list
```

### 19.4 Metrics and Dashboard

```bash
# Collect run metrics
cbflow flow metrics collect

# View metrics report
cbflow flow metrics report
cbflow flow metrics report --flow PNR

# Export to CSV
cbflow flow metrics export --format csv

# Register the run with the per-user dashboard daemon and open it (PD port 9000 + uid%300)
cbflow run gui
# Open http://localhost:<port> in browser (port printed on startup)
```

The web dashboard provides a full GUI for DAG visualization, node execution control, configuration editing, branch management, and MMMC scenario management. For the complete dashboard reference, see the **[GUI User Guide](cbflow-gui-user-guide.md)**.

### 19.5 Flat Execution Mode

Merge execution nodes to reduce EDA tool license usage:

```tcl
# In user_config.tcl
set flow(run_type) "flat"
```

In flat mode, multiple stages are combined into a single merged execution to minimize license checkouts.

---

## 20. Troubleshooting

### 20.1 Common Issues

**Problem:** `cbflow run all` fails with DAG build error
- **Cause:** RACE DAG build failure
- **Fix:** Re-create the run with `cbflow workspace create --config user_config.tcl --force`

**Problem:** `ERROR: .run.cbflow.tcl not found`
- **Cause:** Running cbflow from wrong directory
- **Fix:** Ensure you are inside the run directory (e.g., `cd LC2_run_PNR_cpu_core_run1/`)

**Problem:** `list must have an even number of elements`
- **Cause:** TCL comments (`#`) inside `array set {}` blocks in config files
- **Fix:** Move comments outside the `array set` braces

**Problem:** Stage appears stuck / status not updating in RACE DB
- **Cause:** Subnode handler failed silently
- **Fix:** Check logs with `cbflow run logs --tail 100 --level ERROR`

**Problem:** Wrong queue selected for LSF
- **Cause:** Stage name mismatch between config and LSF mappings
- **Fix:** Verify stage names in `{FLOW}_config.tcl` match `lsf_config.tcl`

### 20.2 Useful Debug Commands

```bash
# Show what would run without executing
cbflow run gen-makefile        # verifies the RACE DAG (no Makefile is written)

# Check environment
cat .run.cbflow.env

# Verify config loading
tclsh -e 'source .run.cbflow.tcl; parray ::env'

# Check status from RACE DB
cbflow run status --details

# Force re-run a specific node
cbflow run force --stages place1
cbflow run all
```

### 20.3 Test Mode Debugging

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
| CBFLOW_PROJECT | Project name | bumblebee |
| CBFLOW_CORE_DIR | CBflow installation root | /tools/cbflow/PD |
| CBFLOW_RELEASE_VERSION | Active release | v1.0.0 |

### Run Variables (set during `workspace create`)

| Variable | Description | Example |
|----------|-------------|---------|
| CBFLOW_RUN_DIR | Run directory path | /proj/workarea/cpu_core/LC2_run_PNR_cpu_core_run1 |
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

Phases are project-defined in `global/config/project/<proj>/v1.0.0/<proj>_config.tcl`:

```tcl
set project(phases)         {P0 P1 P2 P3}      ;# opensky (bumblebee: {LC1 LC2 LC3 LC4 LC5})
set project(current_phase)  "P0"
set project(phase_exits)    { P0 {FP_EXIT PRO_EXIT} P1 {FP_EXIT PRO_EXIT} P2 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO} P3 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO} }
set project(phase_exits,DV) { P1 {TB_SETUP_EXIT M1_EXIT M2_EXIT} P2 {M3_EXIT M4_EXIT DV_SIGNOFF_EXIT} ... }
```

A run's phase is `project(phase)` from its user config, else `project(current_phase)`.

---

## Appendix C: Quick Reference Card

```
# Setup
cbflow workspace template --flow PNR > user_config.tcl
cbflow workspace create --config user_config.tcl

# Execute
cd LC2_run_PNR_cpu_core_run1/
cbflow run all                          # Run complete flow
cbflow run stage --name place1          # Run single stage
cbflow run status                       # Check progress

# Monitor
cbflow run status --details
cbflow run show-graph
cbflow run logs --tail 50 --level ERROR

# Re-run / Control
cbflow run retrace --from cts1          # Re-run from CTS onwards
cbflow run bypass --stages export_data1   # Skip a node
cbflow run force --stages place1          # Force re-run
cbflow run forcevalidate --node signoff1  # Force validate

# Debug
cbflow run validate
cbflow run gen-makefile        # verifies the RACE DAG (no Makefile is written)

# Info
cbflow flow types
cbflow flow info --flow PNR
cbflow flow stages --flow SYNTH
```
