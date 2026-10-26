# Basic Workflows

Real-world CBflow workflow examples. All examples use the RACE (Run Automation & Control Engine) dispatcher.

## 1. SYNTH_PNR Full Run (Synopsys FC)

```tcl
# user_config.tcl
set flow(design_name)               "cpu_core"
set flow(dispatcher)                "race"
set synth_pnr(design_name)          "cpu_core"
set synth_pnr(input,rtl_filelist)   "/proj/rtl/cpu_core.f"
set synth_pnr(input,sdc_file)       "/proj/sdc/cpu_core.func.sdc"
set synth_pnr(input,upf)            "/proj/upf/cpu_core.upf"
set synth_pnr(input,def_file)       "/proj/fp/cpu_core.def"
```

```bash
cbflow workspace create --config user_config.tcl
cd P0_run_SYNTH_PNR_run1/
cbflow run all          # RACE builds DAG and executes all nodes
cbflow run status       # Query status from RACE SQLite DB
```

Stages: inputs -> init_design -> synthesis -> place -> cts -> cts_opt -> route -> pro -> signoff -> export_data -> release_data

## 2. PNR with Cadence Innovus (Tool Override)

```tcl
# user_config.tcl — override tool to Innovus
set flow(design_name)          "cpu_core"
set flow(dispatcher)           "race"
set pnr(design_name)           "cpu_core"
set pnr(tool,vendor)            "cadence"
set pnr(tool,name)              "innovus"
set pnr(input,netlist)          "/proj/synth/outputs/cpu_core.v"
set pnr(input,sdc_file)        "/proj/sdc/cpu_core.func.sdc"
set pnr(input,def_file)        "/proj/fp/cpu_core.def"
```

```bash
cbflow workspace create --config user_config.tcl
cd P0_run_PNR_run1/
cbflow run all    # RACE selects Innovus command files automatically
```

## 3. Per-Corner STA with PrimeTime (Dynamic Subnodes)

```tcl
# user_config.tcl — 2 corners for setup and hold
set flow(design_name)              "cpu_core"
set flow(dispatcher)               "race"
set sta(design_name)               "cpu_core"
set sta(input,netlist)             "/proj/pnr/outputs/cpu_core.pt.v"
set sta(input,spef)                "/proj/pnr/outputs/cpu_core.spef"
set sta(mmmc,setup_scenarios)      "ss_0p72v_125c"
set sta(mmmc,hold_scenarios)       "ff_0p88v_m40c"
```

```bash
cbflow workspace create --config user_config.tcl
cd P0_run_STA_run1/
cbflow run all
# RACE generates per-corner dynamic subnodes from user_config
# Each corner runs independently — no MMMC stage
# Reports at: work/STA/timing1/reports/
```

## 4. PV with ICV (Parallel DRC/LVS/ERC Subnodes)

```tcl
# user_config.tcl
set flow(design_name)     "cpu_core"
set flow(dispatcher)      "race"
set pv(design_name)       "cpu_core"
set pv(input,gds)         "/proj/pnr/outputs/cpu_core.gds"
set pv(input,netlist)     "/proj/pnr/outputs/cpu_core.lvs.v"
set pv(input,def)         "/proj/pnr/outputs/cpu_core.def"
```

```bash
cbflow workspace create --config user_config.tcl
cd P0_run_PV_run1/
cbflow run all
# RACE pipeline: inputs -> fill -> (drc|lvs|perc|erc|xor parallel) -> merge_data -> release_data
# RACE runs drc, lvs, erc, perc, xor in parallel after fill completes
```

## 5. Release and Handshake Between Flows

### Step 1: SYNTH releases

```tcl
# project_config.tcl
set project(release,path)       "/proj/releases"
set project(release,phase)      "P2"
set project(release,block_name) "cpu_core"
set project(release,tag)        "v1.0.2"
```

```bash
cd P0_run_SYNTH_run1/
cbflow run all
# release_data copies outputs -> /proj/releases/P2/cpu_core/v1.0.2/
```

### Step 2: PNR picks up via release_tag

```tcl
# PNR user_config.tcl
set pnr(input,netlist_release_tag) "v1.0.2"   # auto-resolves from release path
set pnr(input,sdc_release_tag)     "v1.0.2"
set pnr(input,def_file)            "/proj/fp/cpu_core.def"
```

```bash
cd P0_run_PNR_run1/
cbflow run all
# resolve_inputs auto-resolves: /proj/releases/P2/cpu_core/v1.0.2/netlist/cpu_core.v
```

## 6. Checklist: Add Check, Run, Sign-Off

```bash
# Add a grep-based check
cbflow flow checklist add-check --milestone BTO \
  --name drc_zero --check-type mandatory \
  --description "DRC violations must be zero" \
  --grep-file "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt" \
  --grep-pattern "Total.*0.*violation" --grep-pass-if found

# Add a file check
cbflow flow checklist add-check --milestone BTO \
  --name gds_exists --check-type file \
  --file-path 'outputs/${design_name}.gds'

# Run checklist
cbflow run checklist --milestone PRO_EXIT --phase P2

# Sign off
cbflow run checklist --milestone BTO --sign-off --approver chip_lead
```

## 7. Email on Completion

```bash
cbflow run email --to team@company.com --template run-summary
cbflow run email --to user@company.com --template run-status --preview
```

## 8. AutoPPT Generation

```bash
cbflow run autoppt                          # HTML summary
cbflow run autoppt --format pptx            # PowerPoint
cbflow run autoppt -o summary.html          # Custom path
```

## 9. Bypass / Force / Forcevalidate

```bash
# Skip a node (mark as bypassed in RACE DB)
cbflow run bypass --node export_data1

# Force re-run a node regardless of current status
cbflow run force --node place1

# Force validate a specific node
cbflow run forcevalidate --node signoff1

# Force validate a range of nodes
cbflow run forcevalidate --from place1 --to pro1

# Force validate from a node to end
cbflow run forcevalidate --from cts1

# Force validate from start to a node
cbflow run forcevalidate --to route1
```

## 10. Custom Nodes and Branches

```bash
# Add a custom node to the RACE DAG
cbflow run add-node --node eco1 --type export_data --dep signoff

# Create a branch in the DAG
cbflow run create-branch --name experimental

# List all nodes in the DAG
cbflow run list-nodes

# Visualize the RACE DAG
cbflow run show-graph
```

## 11. File Change Detection

RACE automatically detects when input files change and retraces downstream nodes:

```bash
# After editing an input file (e.g., SDC constraint file):
cbflow run all
# RACE detects the file change, marks downstream nodes for re-execution,
# and only re-runs affected nodes

# Or manually retrace from a specific node:
cbflow run retrace --from cts1
cbflow run all    # Re-runs from CTS onwards
```

---

**Documentation Version**: 2.0.0
