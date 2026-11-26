# Basic Workflows

Real-world CBflow workflow examples. All examples run on the RACE engine (no Makefile).
Commercial-tool examples use project **bumblebee** (gf_22nm, phases LC1-LC5, block `cpu_core`);
open-source examples use project **opensky** (skywater_130nm, phases P0-P3, blocks `gcd`, `mac_array`,
`ctrl_subsys`, `ai_subsys`, `opensky_chip`, library tag `OSS2`).

Every user config can be started from a template:

```bash
cbflow workspace template --flow <FLOW> > uc_<FLOW>.tcl
```

Run directories are named `<phase>_run_<FLOW>_<block>_<run>`.

## 1. SYNTH_PNR Full Run (Synopsys FC)

```tcl
# workarea/cpu_core/uc_SYNTH_PNR.tcl
set project(name)                   "bumblebee"
set flow(type)                      "SYNTH_PNR"
set flow(design_name)               "cpu_core"
set flow(run_name)                  "run1"
set flow(test_mode)                 "false"
set flow(use_lsf)                   "true"     ;# bsub must be on PATH
set flow(use_xterm)                 "false"
set synth_pnr(input,rtl_filelist)   "/proj/rtl/cpu_core.f"
set synth_pnr(input,rtl_format)     "sverilog"
set synth_pnr(input,sdc_func_file)  "/proj/sdc/cpu_core_func.sdc"
set synth_pnr(input,upf_file)       "/proj/upf/cpu_core.upf"
```

```bash
cd workarea/cpu_core
cbflow workspace create --config uc_SYNTH_PNR.tcl
cd LC1_run_SYNTH_PNR_cpu_core_run1/
cbflow run all
cbflow run status --details
```

Stages (`cbflow flow stages --flow SYNTH_PNR`): rtl1 -> sdc1 -> upf1 -> init_design1 -> synthesis1 -> place1 ->
cts1 -> cts_opt1 -> route1 -> pro1 -> signoff1 -> export_data1 -> release_data1

## 2. PNR with Cadence Innovus (tool override)

```tcl
set project(name)          "bumblebee"
set flow(type)             "PNR"
set flow(design_name)      "cpu_core"
set flow(run_name)         "inv1"
set pnr(tool,vendor)       "cadence"
set pnr(tool,name)         "innovus"               ;# selects PNR_innovus_config.tcl
set pnr(input,release_tag) "LC1_SYNTH_v1"           ;# netlist + SDC + UPF from the SYNTH release
set pnr(input,def_file)    "/proj/fp/cpu_core.def"  ;# explicit path wins over the tag
```

## 3. Open-source PNR of gcd (OpenROAD, sky130)

```tcl
# workarea/gcd/uc_PNR_openroad_P1.tcl
set project(name)                   "opensky"
set flow(type)                      "PNR"
set flow(design_name)               "gcd"
set flow(run_name)                  "b1"
set project(phase)                  "P1"
set project(lib_config_tag)         "OSS2"
set flow(test_mode)                 "false"
set flow(use_lsf)                   "false"
set flow(use_xterm)                 "false"
set pnr(tool,name)                  "openroad"
set pnr(input,release_tag)          "P1_SYNTH_v1"
set pnr(input,def_file_release_tag) "FP_EXIT"
```

```bash
cd workarea/gcd
cbflow workspace create --config uc_PNR_openroad_P1.tcl
cd P1_run_PNR_gcd_b1 && cbflow run all
cbflow run release --from-run . --publish      # the run released itself (release_data1); publish to SmartGrid
```

## 4. Per-scenario STA (dynamic subnodes)

STA runs one `timing1_<scenario>` subnode per MMMC scenario. A signoff STA reads only the release of the exit it
verifies (`sta(input,release_tag)` names that exit):

```tcl
# workarea/gcd/uc_STA_P3.tcl — signoff STA of the gcd BTO release
set project(name)          "opensky"
set flow(type)             "STA"
set flow(design_name)      "gcd"
set flow(run_name)         "p3_bto"
set project(phase)         "P3"
set project(lib_config_tag) "OSS2"
set sta(tool,name)         "opensta"
set sta(input,release_tag) "BTO"
```

Restrict the scenarios of one node in `setup/override_config.timing1.tcl` (or right-click timing1 -> MMMC Scenarios
in the run GUI, which writes the same file):

```tcl
set mmmc(timing1,setup_scenarios) "func_ss_1p60v_rc_max_100c"
set mmmc(timing1,hold_scenarios)  "func_ff_1p95v_rc_min_m40c"
```

Stages: netlist1 -> sdc1 -> def1 -> library1 -> extraction1 -> timing1 (per scenario) -> merge_reports1 -> release_data1.

## 5. PV (parallel DRC / LVS / PERC / XOR)

```tcl
set project(name)          "bumblebee"
set flow(type)             "PV"
set flow(design_name)      "cpu_core"
set flow(run_name)         "pv1"
set pv(input,release_tag)  "BTO"         ;# GDS + LVS netlist + DEF of the BTO release
```

Stages: netlist1, def1, gds1 -> nettran1 -> merge_gds1 -> fill_merge_gds1 -> decomp1 -> decomp_merge_gds1 ->
(drc1 | lvs1 | perc1 | perc_ldl1 | xor1 in parallel) -> merge_data1 -> release_data1.

## 6. Release and handshake between flows

Releases land in `<project(release,path)>/<phase>/<block>/<FLOW>/<tag>`; the tag is the exit name unless
`project(release,tag)` is set (e.g. `P1_SYNTH_v1` for a SYNTH release).

```tcl
# SYNTH user config
set project(release,tag)   "P1_SYNTH_v1"      ;# -> <release,path>/P1/gcd/SYNTH/P1_SYNTH_v1/

# PNR user config — three ways to pick inputs (priority: explicit path > per-input tag > generic tag)
set pnr(input,release_tag)          "P1_SYNTH_v1"   ;# every PNR input from one tag
set pnr(input,def_file_release_tag) "FP_EXIT"       ;# the DEF from the FP release
set pnr(input,netlist)              "/my/gcd.v"     ;# explicit path wins
```

The handshake map (`PD/config/flow/v1.0.0/release_config.tcl`, section 6) declares which source flow, category and
file each input comes from.

## 7. Checklist: add a check, run, sign off

```bash
# Grep-based check
cbflow flow checklist add-check --milestone BTO \
  --name drc_zero --type mandatory \
  --description "DRC violations must be zero" \
  --grep-file "work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt" \
  --grep-pattern "Total.*0.*violation" --grep-pass-if found

# File check
cbflow flow checklist add-check --milestone BTO \
  --name gds_exists --type file --file-path 'outputs/${design_name}.gds'

# Evaluate against this run, then sign off
cbflow run checklist --milestone PRO_EXIT --phase P2
cbflow flow checklist list-checks --milestone BTO --phase P3 --run-dir . --summary
cbflow run checklist --milestone BTO --phase P3 --sign-off --approver chip_lead
```

## 8. Email on completion

```bash
cbflow run email --to team@company.com --template run-summary
cbflow run email --to user@company.com --template run-status --preview
```

## 9. AutoPPT

```bash
cbflow run autoppt                          # default format
cbflow run autoppt --format pptx
cbflow run autoppt --format html --output summary.html
```

## 10. Bypass / Force / Forcevalidate

```bash
cbflow run bypass --stages export_data1,release_data1   # mark done without running (work/<FLOW>/<node>/BYPASSED)
cbflow run force --stages place1                        # re-run only place1 (deps must be DONE)
cbflow run forcevalidate --node signoff1                # mark done (ran outside CBflow)
cbflow run forcevalidate --from place1 --to pro1
cbflow run forcevalidate --from cts1                    # from cts1 to the end
cbflow run forcevalidate --to route1                    # from the start to route1
```

## 11. Custom nodes, rewiring and branches

```bash
cbflow run add-node --node place2 --type place --dep place1            # explicit name
cbflow run add-node --type drc --dep gds1                              # auto-named (drc2)
cbflow run add-node --node pro2 --type pro --dep route1 --resource-tier XL
cbflow run set-dep --node export_data1 --deps place1                   # rewire (comma/space list)
cbflow run set-dep --node export_data1 --reset                         # back to the node config
cbflow run delete-node --node place2
cbflow run create-branch --branch timing_fix --from cts1
cbflow run list-nodes
cbflow run show-graph --detail
```

Added nodes inherit the base stage's `runtime,timeout`.

## 12. Retrace

```bash
cbflow run retrace --from cts1          # clear cts1 and everything downstream
cbflow run retrace --from cts1 --run    # clear and re-run
cbflow run stage --name cts1            # or re-run one stage
```

---

**Documentation Version**: 2.0.0
