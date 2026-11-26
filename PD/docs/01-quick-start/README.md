# Quick Start Guide

Get started with CBflow v2.0.0 in 5 minutes.

## Prerequisites

- Python 3.6+, Bash/Zsh 4.0+
- EDA tools in `$PATH` (only tools for your selected flow needed)
- `CBFLOW_ROOT` set to the CBflow umbrella install (the directory holding `bin/`, `global/`, `PD/`, `DFT/`, `DV/`, `RTL/`)

Note: CBflow v2.0.0 uses the RACE (Run Automation & Control Engine) as its dispatcher. GNU Make is NOT required.

## Step 1: Set Environment

```bash
export CBFLOW_ROOT=/opt/cbflow
export PATH=$CBFLOW_ROOT/bin:$PATH
cbflow --version          # shows the resolved root / global / discipline dirs
```

## Step 2: Create User Config

From the block's workarea (`project(workarea_path)/<block>`), generate a template and fill it in:

```bash
cd $CBFLOW_ROOT/workarea/cpu_core
cbflow workspace template --flow SYNTH_PNR > user_config.tcl
```

```tcl
# user_config.tcl (commercial example, project bumblebee)
set project(name)                   "bumblebee"
set flow(type)                      "SYNTH_PNR"
set flow(design_name)               "cpu_core"
set flow(run_name)                  "run1"
set flow(test_mode)                 "false"   ;# "true" = dummy outputs, no EDA tools
set flow(use_lsf)                   "false"   ;# "true" = submit through bsub
set flow(use_xterm)                 "true"    ;# "false" = silent local exec
set synth_pnr(input,rtl_filelist)   "/proj/rtl/cpu_core.f"
set synth_pnr(input,rtl_format)     "sverilog"
set synth_pnr(input,sdc_func_file)  "/proj/sdc/cpu_core_func.sdc"
set synth_pnr(input,upf_file)       "/proj/upf/cpu_core.upf"
```

The phase comes from `project(current_phase)` (override per run with `set project(phase) "P1"`).

## Step 3: Create Run

```bash
cbflow workspace create --config user_config.tcl
cd LC1_run_SYNTH_PNR_cpu_core_run1/      # <phase>_run_<FLOW>_<block>_<run>
```

## Step 4: Execute Flow

```bash
cbflow run all          # RACE builds DAG and executes all nodes
cbflow run status       # Check progress (reads from RACE SQLite DB)
```

## Step 5: Review Results

```bash
cbflow run report                                    # Per-node report
cbflow run logs --tail 50 --level ERROR              # View errors
cbflow run checklist --milestone PRO_EXIT --phase P2  # Exit checklist
cbflow run autoppt                                    # Generate summary
```

## Step 6: Control Execution

```bash
cbflow run retrace --from cts1                       # Retrace from CTS onwards
cbflow run bypass --stages export_data1              # Skip a node (comma-separated list)
cbflow run force --stages place1                     # Force re-run only this node
cbflow run set-dep --node export_data1 --deps place1 # Rewire a node's dependencies
cbflow run forcevalidate --node signoff1             # Force validate a node
cbflow run forcevalidate --from place1 --to pro1     # Force validate a range
```

## What's Next

- [Installation Details](installation.md) -- Full setup guide
- [System Requirements](system-requirements.md) -- Tools, LSF, dependencies
- [First Version](first-version.md) -- Directory-based versioning
- [User Guide](../02-user-guide/README.md) -- Daily workflows
- [Examples](../06-examples/basic-workflows.md) -- Real-world workflows

## Supported Flows

- PD (12): SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP, SYNTH_PNR
- DFT, DV and RTL flows: `cbflow flow types` (grouped by discipline)

## Key Commands

```bash
cbflow workspace create --config user_config.tcl  # Create run
cbflow run all                                     # Execute flow (via RACE DAG)
cbflow run stage --name place1                     # Run single stage
cbflow run status                                  # Check progress (RACE DB)
cbflow run retrace --from cts1                     # Retrace from node
cbflow run bypass --stages <node>[,<node>]         # Skip nodes
cbflow run force --stages <node>[,<node>]          # Force re-run
cbflow run add-node --node <n> --type <t> --dep <d>  # Add a node
cbflow run forcevalidate --node <node>             # Force validate
cbflow run checklist --milestone BTO --phase P3    # Exit checklist
cbflow run email --to user@co.com --template run-summary  # Email
cbflow run autoppt --format html                   # PPT summary
cbflow run interactive --node signoff1             # Interactive session
cbflow run show-graph                              # Visualize RACE DAG
```

---

**Documentation Version**: 2.0.0
