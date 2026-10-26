# Quick Start Guide

Get started with CBflow v2.0.0 in 5 minutes.

## Prerequisites

- Python 3.6+, Bash/Zsh 4.0+
- EDA tools in `$PATH` (only tools for your selected flow needed)
- `CBFLOW_HOME` set to CBflow installation directory

Note: CBflow v2.0.0 uses the RACE (Run Automation & Control Engine) as its dispatcher. GNU Make is NOT required.

## Step 1: Set Environment

```bash
export CBFLOW_HOME=/opt/cbflow
export PATH=$CBFLOW_HOME/bin:$PATH
source $CBFLOW_HOME/completions/cbflow.bash   # Tab completion
```

## Step 2: Create User Config

```tcl
# user_config.tcl
set flow(design_name)               "my_design"
set flow(dispatcher)                "race"
set synth_pnr(design_name)          "my_design"
set synth_pnr(input,rtl_filelist)   "/proj/rtl/my_design.f"
set synth_pnr(input,sdc_file)       "/proj/sdc/my_design.sdc"
set synth_pnr(input,upf)            "/proj/upf/my_design.upf"
```

## Step 3: Create Run

```bash
cbflow workspace create --config user_config.tcl
cd P0_run_SYNTH_PNR_run1/
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
cbflow run bypass --node export_data1                # Skip a node
cbflow run force --node place1                       # Force re-run a node
cbflow run forcevalidate --node signoff1             # Force validate a node
cbflow run forcevalidate --from place1 --to pro1     # Force validate a range
```

## What's Next

- [Installation Details](installation.md) -- Full setup guide
- [System Requirements](system-requirements.md) -- Tools, LSF, dependencies
- [First Version](first-version.md) -- Directory-based versioning
- [User Guide](../02-user-guide/README.md) -- Daily workflows
- [Examples](../06-examples/basic-workflows.md) -- Real-world workflows

## Supported Flows (12)

SYNTH, FP, PNR, STA, LEC, EMIR, PV, ECO, CLP, POPT, FCFP, SYNTH_PNR

## Key Commands

```bash
cbflow workspace create --config user_config.tcl  # Create run
cbflow run all                                     # Execute flow (via RACE DAG)
cbflow run stage --name place1                     # Run single stage
cbflow run status                                  # Check progress (RACE DB)
cbflow run retrace --from cts1                     # Retrace from node
cbflow run bypass --node <node>                    # Skip a node
cbflow run force --node <node>                     # Force re-run
cbflow run forcevalidate --node <node>             # Force validate
cbflow run checklist --milestone BTO --phase P3    # Exit checklist
cbflow run email --to user@co.com --template run-summary  # Email
cbflow run autoppt --format html                   # PPT summary
cbflow run interactive --load signoff1             # Interactive session
cbflow run show-graph                              # Visualize RACE DAG
```

---

**Documentation Version**: 2.0.0
