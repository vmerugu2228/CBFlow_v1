# CBflow Kickstart Guide

**Copy the install, set one variable, run your first flow in 5 minutes.**

---

## 1. Copy to Unix

Copy the **whole umbrella install** (`bin/`, `global/`, `PD/`, `DFT/`, `DV/`, `RTL/`) —
`PD/` alone no longer runs, because every run sources the cross-discipline `global/` layer first.

```bash
rsync -avz CBflow_clone/ user@server:/opt/cbflow/
# or ship a bundle (excludes run data, releases, RACE area):
bin/cbflow bundle --output /tmp            # CBflow_v2.0.0_<date>.tar.gz
```

## 2. Set Environment

`CBFLOW_ROOT` is the only user-facing variable. `CBFLOW_GLOBAL_DIR`, `CBFLOW_CORE_DIR` (= `$CBFLOW_ROOT/PD`),
`CBFLOW_DFT_DIR`, `CBFLOW_DV_DIR` and `CBFLOW_RTL_DIR` are derived by the launcher.

**Bash:**
```bash
export CBFLOW_ROOT=/opt/cbflow
export PATH=$CBFLOW_ROOT/bin:$PATH
eval "$(cbflow --completions bash)"     # optional tab completion (zsh: --completions zsh)
```

**C-Shell:**
```csh
setenv CBFLOW_ROOT /opt/cbflow
set path = ($CBFLOW_ROOT/bin $path)
```

**Verify** (prints the resolved root / global / discipline directories):
```bash
cbflow --version
```

## 3. Configure the Project

A project is split across a global identity file and per-discipline overlays
(see [multi-discipline-kickoff.md](multi-discipline-kickoff.md) for the full cascade):

| File | Holds |
|------|-------|
| `global/config/project/<proj>/v1.0.0/<proj>_config.tcl` | identity, tech, hierarchy, `project(phases)`, `project(phase_exits)`, DFT params |
| `PD/config/project/<proj>/v1.0.0/<proj>_pd_config.tcl` | PD overlay: `workarea_path`, `release,*`, `lsf,*`, `lib_root`, `lib_tag_root`, `lib_config_tag` |
| `global/config/project/<proj>/v1.0.0/mmmc_config.tcl` | MMMC PVT building blocks |
| `global/config/tech/<tech>/v1.0.0/tech_config.tcl` | foundry data, metal stacks, physical cells |

Example (open-source project `opensky`, PD overlay):

```tcl
# PD/config/project/opensky/v1.0.0/opensky_pd_config.tcl
set project(workarea_path)   "/proj/opensky/workarea"
set project(lib_tag_root)    "/proj/eda/lib_tags"      ;# tags live in <lib_tag_root>/<tech>/<TAG>/
set project(lib_config_tag)  "OSS0"                    ;# default library tag (override per run)
set project(release,path)    "/proj/opensky/releases"  ;# <path>/<phase>/<block>/<FLOW>/<tag>
```

Exit plan per phase (global project config):

```tcl
set project(phases) {P0 P1 P2 P3}
set project(phase_exits) {
    P0 {FP_EXIT PRO_EXIT}
    P1 {FP_EXIT PRO_EXIT}
    P2 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
    P3 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}
}
set project(phase_exits,DV) { P1 {TB_SETUP_EXIT M1_EXIT M2_EXIT} P2 {M3_EXIT M4_EXIT DV_SIGNOFF_EXIT} ... }
```

## 3b. Metal Stack

The active stack is `project(metal_stack)` (one of `tech(metal_stacks_available)`); per-stack files live in
`global/config/tech/<tech>/v1.0.0/metal_stack/<stack>.tcl` and resolve routing layers, RC files and PG strap layers.

```tcl
set project(metal_stack) "5M"        ;# skywater_130nm (opensky)
```

## 3c. Library Manager

Libraries are delivered as **tags**: `<lib_tag_root>/<tech>/<TAG>/lib_config.tcl` (+ `blocks_config.tcl`
for hierarchical blocks). A run picks one with `project(lib_config_tag)`.

```bash
cbflow flow library-manager check  --tech skywater_130nm --lib_tag OSS2      # required views per category
cbflow flow library-manager status --tech skywater_130nm --project opensky --lib_tag OSS2
cbflow flow library-manager generate --tech gf_22nm --lib-root /proj/libs/gf_22nm --tag P0   # commercial
```

See [library-manager-user-guide.md](../02-user-guide/library-manager-user-guide.md) (design-vs-tag checks,
`add --category block|memory`, VT filtering, coverage).

## 3d. MMMC Manager

```bash
cbflow flow mmmc-manager show     --project opensky --tech skywater_130nm
cbflow flow mmmc-manager validate --project opensky --tech skywater_130nm
cbflow flow mmmc-manager list-scenarios --project opensky --tech skywater_130nm --set signoff
cbflow flow mmmc-manager generate-view-def --project bumblebee --tech gf_22nm --style flow --output mmmc_view_definition.tcl
```

Outside a run shell pass `--tech` (inside one, `CBFLOW_TECH_NODE` is set). Every mutation (`add-mode`, `remove-mode`, `add-pvt`, `remove-pvt`, `add-rc`, `set-node`) re-validates and
refuses to write an inconsistent config. See [mmmc-manager-user-guide.md](../02-user-guide/mmmc-manager-user-guide.md).

## 4. Create a User Config

Generate a template, then fill in the inputs:

```bash
cd $CBFLOW_ROOT/workarea/gcd
cbflow workspace template --flow PNR > uc_PNR.tcl
```

```tcl
# uc_PNR.tcl — open-source PNR of gcd, inputs by release tag
set project(name)              "opensky"
set flow(type)                 "PNR"
set flow(design_name)          "gcd"
set flow(run_name)             "b1"
set project(phase)             "P1"

set flow(test_mode)            "false"   ;# "true" = dummy outputs, no tools
set flow(use_lsf)              "false"   ;# "true" = submit through bsub
set flow(use_xterm)            "false"   ;# "true" = each job in an xterm (needs $DISPLAY)

set pnr(tool,name)             "openroad"
set pnr(input,release_tag)     "P1_SYNTH_v1"   ;# netlist + SDC from the SYNTH release
set pnr(input,def_file_release_tag) "FP_EXIT"  ;# floorplan from the FP release
set project(lib_config_tag)    "OSS2"
```

Defaults (`global/config/flow/v1.0.0/flow_registry.tcl`): `test_mode=false`, `use_lsf=false`, `use_xterm=true`.
`workspace create` refuses to start when `use_lsf=true` and `bsub` is missing, or `use_xterm=true` and `xterm` is missing.

## 5. Create the Run and Execute

```bash
cbflow workspace create --config uc_PNR.tcl
cd P1_run_PNR_gcd_b1/          # <phase>_run_<FLOW>_<block>_<run>

cbflow run all                 # RACE builds the DAG from the node config and runs it
cbflow run status --details
cbflow run logs --tail 20 --level ERROR
cbflow run gui                 # run dashboard (per-user daemon)
```

## 6. RACE Engine Basics

RACE (Run Automation & Control Engine) is the Python-native DAG executor:

- Builds the DAG from `<FLOW>_config.tcl` (+ the tool overlay) at runtime
- Tracks node status in SQLite (`.race_<run_dir>_<user>_<hash>.db` in `project(race,db_path)`, pointer `.race_db_pointer`)
- Runs independent nodes / subnodes in parallel (capped by `flow(max_parallel_jobs)`, 0 = unlimited)
- Generates dynamic subnodes (e.g. STA per MMMC scenario)
- Run ownership: only the creator can run / retrace / bypass / force / add or rewire nodes; status, GUI and logs are open to all

There is no Makefile and no `make` command.

## 7. Key Commands

| Command | Purpose |
|---------|---------|
| `cbflow run all` | Run the complete flow |
| `cbflow run stage --name place1` | Run one stage |
| `cbflow run status --details` | Progress incl. subnodes |
| `cbflow run retrace --from cts1` | Clear cts1 and downstream (add `--run` to rerun) |
| `cbflow run bypass --stages cts1,cts_opt1` | Mark stages done without running (creates `BYPASSED`) |
| `cbflow run force --stages place1` | Re-run only these stages |
| `cbflow run forcevalidate --node place1` / `--from X --to Y` | Mark done (ran outside CBflow) |
| `cbflow run add-node --node export_data2 --type export_data --dep place1` | Add a node |
| `cbflow run set-dep --node export_data1 --deps place1` | Rewire a node (`--reset` restores) |
| `cbflow run create-branch --branch timing_fix --from cts1` | Branch the flow |
| `cbflow run show-graph --detail` | Show the DAG |
| `cbflow run interactive --node place1` | Restore a node in the tool GUI |
| `cbflow run checklist --milestone PRO_EXIT --phase P2` | Exit checklist for this run |
| `cbflow run release --from-run . --publish` | Publish a self-released (open-source) run |
| `cbflow run email --to user@co.com --template run-summary` | Email report |
| `cbflow run autoppt --format html` | Run summary |
| `cbflow run db-manage --list` / `--cleanup` | RACE databases |
| `cbflow flow checklist list --discipline PD` | Exit milestones |
| `cbflow flow library-manager check --tech <t> --lib_tag <TAG>` | Library tag readiness |

## 8. Flows

32 flow types in four disciplines (`cbflow flow types`):

| Discipline | Flows |
|------------|-------|
| PD (12) | SYNTH, FP, PNR, SYNTH_PNR, FCFP, STA, LEC, CLP, PV, EMIR, POPT, ECO |
| DFT (7) | DFT_INSERT_PASS1/2/3, SCAN_INSERT, ATPG, GLS_FUNC, GLS_SCAN_MBIST |
| DV (9) | SPEC_RAMP, PLANNING, TB_SETUP, M1_EXEC … M4_EXEC, ECO_EXEC, DV_SIGNOFF |
| RTL | RTL_SPEC, RTL_LINT, RTL_CDC, RTL_RDC, UPF_CHECK |

## 9. Exit Milestones

Declared in `global/config/exit/v1.0.0/<EXIT>_config.tcl` (`cbflow flow checklist list`):

| Discipline | Exits |
|------------|-------|
| PD | FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO (+ STA_SIGNOFF checklist) |
| DFT | CORE_DFT_EXIT, TOP_DFT_EXIT, EDT_OCC_EXIT, SCAN_INSERT_EXIT, ATPG_PREPD_EXIT, ATPG_POSTPD_EXIT |
| DV | SPEC_RAMP_EXIT, PLANNING_EXIT, TB_SETUP_EXIT, M1_EXIT … M4_EXIT, ECO_EXEC_EXIT, DV_SIGNOFF_EXIT |
| RTL | SPEC_EXIT, LINT_SIGNOFF, CDC_SIGNOFF, UPF_SIGNOFF |

Checks are phase-aware: the project's `project(phases)` drive which checks are active.

## 10. Input Handshaking

```tcl
set sta(input,release_tag)     "PRO_EXIT"          ;# A: one tag resolves every input
set sta(input,sdc_release_tag) "P1_STA_v2"         ;# B: per-input tag wins over the generic one
set sta(input,netlist)         "/my/custom/gcd.v"  ;# C: explicit path wins over any tag
set sta(input,from_run)        "/path/to/P1_run_PNR_gcd_b1"   ;# or a sibling run's outputs
```

## 11. Override Hierarchy

All configs are consolidated into one generated `config.tcl` per node:

```
global project  -> discipline overlays (<proj>_pd_config.tcl …) -> tech_config.tcl
  -> flow_registry.tcl -> <DISC> flow_config.tcl -> <FLOW>_config.tcl + <FLOW>_<tool>_config.tcl
    -> mmmc_config.tcl -> setup/user_config.tcl
      -> setup/override_config.tcl -> .<stage> -> .<branch> -> .<node_type> -> .<node>
```

## 12. Exit Releases

Releases land in `<project(release,path)>/<phase>/<block>/<FLOW>/<tag>` (tag = exit name unless
`project(release,tag)` is set). Exits of a phase must release in plan order (`check_exit_order`).

```bash
cbflow run release --tag PRO_EXIT --dry-run         # commercial flows: package + gate check
cbflow run release --from-run . --publish           # open-source: the run released itself; publish to SmartGrid
cbflow run release --from-run . --clone-from BTO --tag MTO --publish
```

Publishing is opt-in (`--publish`). Details: [exit-release-guide.md](../02-user-guide/exit-release-guide.md).

## 13. SmartGenie

```bash
cbflow smartgenie setup               # check Ollama + model + knowledge base
cbflow smartgenie ingest --all        # build the knowledge base
cbflow smartgenie                     # interactive agent
cbflow smartgenie search "hold fix"
```

See [SmartGenie User Guide](../02-user-guide/smartgenie-user-guide.md).

## 14. Bundle & Permissions

```bash
cbflow bundle --output /path/to/dir     # CBflow_v2.0.0_<date>.tar.gz
bin/cbflow run release-lock             # configs 444, scripts 555, dirs 755
bin/cbflow run release-lock --unlock    # back to 777 (development)
```

## 15. Test Suite

```bash
cbflow test --static               # static config checks
cbflow test --e2e --flow PNR       # end-to-end test_mode runs for one flow
cbflow test --cli-smoke            # every cbflow leaf command with safe args
cbflow test --list
```

---

**Next**: [Quick Start Guide](../01-quick-start/README.md) for detailed setup.
