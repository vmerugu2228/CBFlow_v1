# Installation & Setup

Complete setup guide for CBflow v2.0.0.

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Python | 3.6+ | Stdlib only -- no pip install needed |
| Bash or Zsh | 4.0+ | CLI dispatcher |
| Tcl/Tclsh | 8.5+ | Config files and flow_proc engine |

Note: GNU Make is NOT required. CBflow v2.0.0 uses the RACE (Run Automation & Control Engine) for all flow execution and status tracking.

## Installation

```bash
# 1. Copy the whole umbrella install (bin/ global/ PD/ DFT/ DV/ RTL/) — PD/ alone does not run
tar xzf CBflow_v2.0.0_<date>.tar.gz -C /opt      # bundle made with `cbflow bundle`
# OR
rsync -avz CBflow_clone/ server:/opt/cbflow/

# 2. Set environment — CBFLOW_ROOT is the only user-facing variable
export CBFLOW_ROOT=/opt/cbflow
export PATH=$CBFLOW_ROOT/bin:$PATH

# 3. Add to ~/.bashrc or ~/.zshrc for persistence
echo 'export CBFLOW_ROOT=/opt/cbflow' >> ~/.bashrc
echo 'export PATH=$CBFLOW_ROOT/bin:$PATH' >> ~/.bashrc
```

`CBFLOW_GLOBAL_DIR`, `CBFLOW_CORE_DIR` (`$CBFLOW_ROOT/PD`), `CBFLOW_DFT_DIR`, `CBFLOW_DV_DIR` and
`CBFLOW_RTL_DIR` are derived by the launcher — do not export them.

## Verify Installation

```bash
cbflow --version                    # v2.0.0 + the resolved root / global / discipline dirs
cbflow flow types                   # flow types grouped by discipline (PD / DFT / DV / RTL)
cbflow test --static                # static config checks
bin/cbflow-healthcheck              # System health check
bin/cbflow-verify                   # Production verification
```

## RACE Engine

CBflow v2.0.0 uses RACE (Run Automation & Control Engine) as the sole dispatcher. Key points:

- **No Makefile**: RACE builds the execution DAG from `<FLOW>_config.tcl` (+ the `<FLOW>_<tool>_config.tcl` overlay) at runtime.
- **SQLite DB status**: each run tracks node status in `.race_<run_dir_name>_<user>_<hash>.db`, created at `workspace create`.
- **DB location**: the race area `project(race,db_path)`; the run directory holds a `.race_db_pointer`.
- **Parallel execution**: independent nodes / subnodes run in parallel, capped by `flow(max_parallel_jobs)` (0 = unlimited).
- **Dynamic subnodes**: STA per MMMC scenario, generated at runtime.
- **Verify the DAG** of a run without executing: `cbflow run gen-makefile`.

## EDA Tool Setup

CBflow expects EDA tools in `$PATH`. Configure via `module load` or equivalent:

```bash
module load synopsysFusionCompiler/2025.06
module load synopsysPrimeTime/2025.06
module load cadenceInnovus/23.1
# etc.
```

Tool-to-module mappings are in `PD/config/flow/v1.0.0/tool_launch_config.tcl`. Open-source tools (sky130) run in a
docker container through `global/bin/cbflow-oss` instead — see the [open-source flow guide](../02-user-guide/opensource-flow-guide.md).

## Project Setup

A project has a global identity file plus per-discipline overlays (scaffold one with
`cbflow flow project create --name my_chip`):

```tcl
# global/config/project/my_chip/v1.0.0/my_chip_config.tcl — identity, hierarchy, phases, exit plan
set project(name)           "my_chip"
set project(technology)     "gf_22nm"
set project(phases)         {P0 P1 P2 P3}
set project(current_phase)  "P0"
set project(phase_exits)    { P0 {FP_EXIT PRO_EXIT} P1 {FP_EXIT PRO_EXIT} P2 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO} P3 {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO} }
```

```tcl
# PD/config/project/my_chip/v1.0.0/my_chip_pd_config.tcl — PD overlay
set project(workarea_path)  "/proj/my_chip/workarea"   ;# runs are created under <workarea>/<block>/
set project(release,path)   "/proj/my_chip/releases"   ;# <path>/<phase>/<block>/<FLOW>/<tag>
set project(lib_tag_root)   "/proj/eda/lib_tags"       ;# library tags: <root>/<tech>/<TAG>/lib_config.tcl
set project(lib_config_tag) "P0"
set project(race,db_path)   "/proj/my_chip/.race_area"
```

## Technology Setup

Tech configs live in `global/config/tech/<tech>/v1.0.0/tech_config.tcl` (one file per technology; the former
PD tech overlay is merged in):

| Config | Technology |
|--------|-----------|
| `gf_22nm` | GlobalFoundries 22FDX (project bumblebee) |
| `gf_28nm` | GlobalFoundries 28nm |
| `tsmc_7nm` | TSMC N7 |
| `tsmc_5nm` | TSMC N5 |
| `skywater_130nm` | SkyWater sky130 open PDK (project opensky, open-source tools) |

Library views are not edited in the tech file: generate a library tag with
`cbflow flow library-manager generate --tech <tech> --lib-root <dir> --tag <TAG>` and select it with
`project(lib_config_tag)`. See the [library manager guide](../02-user-guide/library-manager-user-guide.md).

## LSF Setup (Optional)

Enable LSF per run in `user_config.tcl` (`workspace create` fails if `bsub` is not on `PATH`):

```tcl
set flow(use_lsf)   "true"
set flow(use_xterm) "false"
```

Queue tiers (XS / S / M / L / XL / ultra) are defined in `PD/config/flow/v1.0.0/lsf_config.tcl`; project policy
(`project(lsf,default_queue)`, `project(lsf,max_concurrent_jobs)`, …) lives in the PD overlay
`<proj>_pd_config.tcl`. Override the bsub binary with `CBFLOW_BSUB_CMD`, the queue per run with
`cbflow run all --lsf --queue XL`, or per node with `cbflow run add-node … --resource-tier L`.

---

**Next**: [System Requirements](system-requirements.md) for detailed tool versions.
