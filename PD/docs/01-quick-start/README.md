# Quick Start Guide

Get started with CBflow v2.0.0 in 5 minutes.

## Prerequisites

- Python 3.6+, GNU Make 3.81+, Bash/Zsh 4.0+
- EDA tools in `$PATH` (only tools for your selected flow needed)
- `CBFLOW_HOME` set to CBflow installation directory

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
cbflow run all          # Run complete flow
cbflow run status       # Check progress
```

## Step 5: Review Results

```bash
cbflow run report                                    # Per-node report
cbflow run logs --tail 50 --level ERROR              # View errors
cbflow run checklist --milestone PRO_EXIT --phase P2  # Exit checklist
cbflow run autoppt                                    # Generate summary
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
cbflow run all                                     # Execute flow
cbflow run stage --name place1                     # Run single stage
cbflow run status                                  # Check progress
cbflow run checklist --milestone BTO --phase P3    # Exit checklist
cbflow run email --to user@co.com --template run-summary  # Email
cbflow run autoppt --format html                   # PPT summary
cbflow run interactive --load signoff1             # Interactive session
```

---

**Documentation Version**: 2.0.0
