# Basic Workflows

Real-world CBflow workflow examples.

## 1. SYNTH_PNR Full Run (Synopsys FC)

```tcl
# user_config.tcl
set flow(design_name)               "cpu_core"
set synth_pnr(design_name)          "cpu_core"
set synth_pnr(input,rtl_filelist)   "/proj/rtl/cpu_core.f"
set synth_pnr(input,sdc_file)       "/proj/sdc/cpu_core.func.sdc"
set synth_pnr(input,upf)            "/proj/upf/cpu_core.upf"
set synth_pnr(input,def_file)       "/proj/fp/cpu_core.def"
```

```bash
cbflow workspace create --config user_config.tcl
cd P0_run_SYNTH_PNR_run1/
cbflow run all
cbflow run status
```

Stages: inputs → init_design → synthesis → place → cts → cts_opt → route → pro → signoff → export_data → release_data

## 2. PNR with Cadence Innovus (Tool Override)

```tcl
# user_config.tcl — override tool to Innovus
set flow(design_name)          "cpu_core"
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
cbflow run all    # Runs with Innovus instead of FC
```

## 3. Per-Corner STA with PrimeTime

```tcl
# user_config.tcl — 2 corners for setup and hold
set flow(design_name)              "cpu_core"
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
# Each corner runs independently — no MMMC stage
# Reports at: work/STA/timing1/reports/
```

## 4. PV with ICV (Parallel DRC/LVS/ERC)

```tcl
# user_config.tcl
set flow(design_name)     "cpu_core"
set pv(design_name)       "cpu_core"
set pv(input,gds)         "/proj/pnr/outputs/cpu_core.gds"
set pv(input,netlist)     "/proj/pnr/outputs/cpu_core.lvs.v"
set pv(input,def)         "/proj/pnr/outputs/cpu_core.def"
```

```bash
cbflow workspace create --config user_config.tcl
cd P0_run_PV_run1/
cbflow run all
# Pipeline: inputs → fill → (drc|lvs|perc|erc|xor parallel) → merge_data → release_data
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
# release_data copies outputs → /proj/releases/P2/cpu_core/v1.0.2/
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

---

**Documentation Version**: 2.0.0
