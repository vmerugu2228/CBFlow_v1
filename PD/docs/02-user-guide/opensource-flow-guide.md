# Open-Source RTL-to-GDS Flow (sky130) — User Guide

CBflow runs a complete RTL-to-GDS flow on SkyWater SKY130 (`sky130A`,
`sky130_fd_sc_hd`) with open-source tools under the vendor name
`opensource`. The flow uses the same RACE engine, release model, SmartGrid
publishing and exit checklists as the Synopsys / Cadence flows. Only the
tool overlay and the command files differ.

The reference project is **`opensky`**:

- Global config: `global/config/project/opensky/v1.0.0/`. This holds `opensky_config.tcl`, the `mmmc_*` files and `schedule_config.tcl`.
- PD overlay: `PD/config/project/opensky/v1.0.0/opensky_pd_config.tcl`.
- Tech: `global/config/tech/skywater_130nm/v1.0.0/tech_config.tcl`.

---

## 1. Tools per flow

| Flow | `<flow>(tool,name)` | Overlay (`PD/config/flow/v1.0.0/node_configs/`) | Engine | Stages |
|---|---|---|---|---|
| SYNTH | `yosys` | `SYNTH_yosys_config.tcl` | Yosys (DFT: OpenROAD) | `rtl1 sdc1 upf1 synthesis1 export_data1 release_data1` |
| FP | `openroad` | `FP_openroad_config.tcl` | OpenROAD | `netlist1 sdc1 upf1 init_design1 floorplan1 powerplan1 export_data1 release_data1` |
| PNR | `openroad` | `PNR_openroad_config.tcl` | OpenROAD | `netlist1 sdc1 def1 upf1 init_design1 place1 cts1 cts_opt1 route1 pro1 signoff1 export_data1 release_data1` |
| STA | `opensta` | `STA_opensta_config.tcl` | OpenRCX (extraction) + OpenSTA | `netlist1 sdc1 def1 extraction1 timing1 merge_reports1 release_data1` |
| PV | `magic` | `PV_magic_config.tcl` | KLayout DRC (default) or Magic DRC; Magic extract + Netgen LVS | `netlist1 gds1 drc1 lvs1 merge_data1 release_data1` |
| LEC | `yosys` | `LEC_yosys_config.tcl` | Yosys equivalence | `netlist_golden1 netlist_revised1 compare1 release_data1` |

### How the tool is selected

The selector is `<flow>(tool,name)`. When that key is unset, `<flow>(default_tool)` is used. The selected name loads the overlay `<FLOW>_<tool>_config.tcl`, which sets `tool,vendor "opensource"`, `tool,version` and the per-stage binary `<flow>(oss,tool,<stage>)`. The binary is one of `yosys`, `openroad`, `sta`, `magic`, `netgen`, `klayout` or `oss_tclsh`.

Priority at run time, highest first:

1. `<flow>(tool,name)` / `<flow>(tool,vendor)` in `setup/user_config.tcl`
2. `project(default_tools)`
3. The node-config default

opensky sets `project(default_tools) {SYNTH yosys FP openroad PNR openroad STA opensta PV magic}` in `opensky_pd_config.tcl`.

> **LEC** is not in `project(default_tools)`. A LEC run must set
> `set lec(tool,name) "yosys"` in its user config, as `workarea/gcd/uc_LEC_yosys.tcl`
> does. Otherwise it falls back to Formality.

---

## 2. Tool container — `cbflow-oss`

Every open-source tool runs inside a Docker container through
`global/bin/cbflow-oss` (also linked as `bin/cbflow-oss`).
`PD/config/flow/v1.0.0/tool_launch_config.tcl` routes each tool through it:
`lsf(tool_shell,<tool>)` is `"cbflow-oss <tool>"`, and `lsf(tool_shell,oss_tclsh)` is `"cbflow-oss tclsh"`.

```bash
cbflow-oss <tool> <cmd_file> <log_file>     # tool: yosys|openroad|sta|magic|netgen|klayout|tclsh
cbflow-oss exec -- <argv...>                # any command in the container
cbflow-oss check                            # verify engine + image + PDK
cbflow-oss gui openroad <stage.odb>         # OpenROAD GUI on a stage database
cbflow-oss gui klayout  <file.gds|.def>     # KLayout viewer
```

- Each call runs `--rm -u uid:gid`.
- Host and container paths are identical. `CBFLOW_ROOT`, the PDK root, `CBFLOW_RUN_DIR`, `$PWD` and `CBFLOW_OSS_MOUNTS` are bind-mounted.
- `CBFLOW_*`, `FLOW_DIR`, `*_VERSION`, `TECH_NAME` and `DISPLAY` pass through to the container.
- Output is tee'd to the log with pipefail.

| Env var | Default |
|---|---|
| `CBFLOW_OSS_IMAGE` | pinned `hpretl/iic-osic-tools@sha256:…` (also `lsf(oss,image)`) |
| `CBFLOW_OSS_PDK_ROOT` | `$HOME/eda/pdks` |
| `CBFLOW_OSS_MOUNTS` | extra `:`-separated mounts |
| `CBFLOW_OSS_MAGICRC` | `<pdk>/sky130A/libs.tech/magic/sky130A.magicrc` |
| `CBFLOW_OSS_ENGINE` | `docker` |

The GUI on macOS needs XQuartz and `DISPLAY=host.docker.internal:0`.

---

## 3. Hierarchy and library tags

`project(design_hierarchy)` in `opensky_config.tcl` declares a three-level chip:

```
opensky_chip (DL1)
├── ctrl_subsys (DL2) ── gcd (DL3)
└── ai_subsys   (DL2) ── mac_array (DL3)
```

Blocks are hardened bottom-up:

1. Each DL3 block is released with its GDS, abstract LEF and timing lib.
2. The library manager adds the DL3 blocks to a **library tag**.
3. The DL2 blocks consume them as hard macros through that tag.
4. The same repeats for DL1.

A run selects its tag with `project(lib_config_tag)` (opensky default: `"OSS0"`).
You can set it per run in user_config:

```tcl
set project(lib_config_tag) "OSS1"
```

Tags are generated data under `project(lib_tag_root)` (`~/eda/lib_tags`), in
`<lib_tag_root>/skywater_130nm/<tag>/`. Each tag contains:

- `lib_config.tcl` and `blocks_config.tcl`
- `MANIFEST.tcl` and `README.md`
- the category directories: `stdcell/`, `memory/`, `io/`, `analog/`, `ip/` and `block/`

| Tag | Contents (as built for opensky) |
|---|---|
| OSS0 | sky130_fd_sc_hd (16 corners) + P0 `PNR/PRO_EXIT` blocks gcd, mac_array, ctrl_subsys |
| OSS1 | Same stdcells + P1 `PRO_EXIT` blocks gcd, mac_array, ai_subsys, ctrl_subsys. Some blocks have `pv_release "PENDING"`. Used by the DL2 script. |
| OSS2 | Adds the memory category `sky130_sram_1kbyte_1rw1r_32x256_8` (lef/gds/cdl/verilog/lib, corner `tt_1p8v_25c`). Used for P2. |

See [Library Manager — `add`](library-manager-user-guide.md#add--add-a-category-to-a-library-tag) for how tags are built.

---

## 4. Command files — flow procs

The command files live in `PD/cmds/<FLOW>/opensource/<tool>/v1.0.0/`:

- `PD/cmds/SYNTH/opensource/yosys/`
- `PD/cmds/FP/opensource/openroad/`
- `PD/cmds/PNR/opensource/openroad/`
- `PD/cmds/STA/opensource/opensta/`
- `PD/cmds/PV/opensource/magic/`
- `PD/cmds/LEC/opensource/yosys/`

Each directory holds `<stage>_<tool>.tcl` plus `<stage>_subnode_handler.tcl`.

Every stage command file follows the same shape:

1. Bootstrap: `.run.cbflow.tcl`, `utils.tcl`, `config.tcl`, `setup.tcl` (hooks), `setup_dirs`, `oss_utils.tcl`.
2. `flow_proc load_design` → one or more operation procs → `flow_proc report` → `flow_proc save_design`.
3. `flow_exec_all`.

The shared helpers are in `global/utils/utilities/v1.0.0/oss_utils.tcl`, for example `oss_load_stage`, `oss_write_qor`, `oss_stage_out`, `oss_read_lefs` and `oss_pdn`. The per-stage proc names are listed in the [Flow Procs Reference](../Flow_Procs_Reference.md#open-source-flows-sky130).

SYNTH (`synthesis_yosys.tcl`) runs `read_design → synthesize → report → write_design → dft_insert`. `report` runs before `dft_insert`, so `synthesis_stat.rpt` describes the pre-DFT netlist.

Customize with hooks in `setup/override_setup.tcl`, `override_setup.<stage>.tcl` or `override_setup.<node>.tcl`:

```tcl
flow_proc_append report {
    report_design_area_metrics
}
```

> `flow_proc_prepend` / `flow_proc_append` from setup files survive.
> `flow_proc_replace` in a setup file does **not** take effect today. The
> command file registers its own `flow_proc` bodies after `setup.tcl` is
> sourced, which overwrites the replacement.

---

## 5. SYNTH — DFT, clock gating, multi-Vt, memories

### DFT scan insertion

These are project keys in `opensky_config.tcl`. A block can override them in its user_config or `override_config.tcl`.

```tcl
set project(dft,enable)              true
set project(dft,max_chain_length)    100            ;# scan flops per chain
set project(dft,clock_mixing)        no_mix         ;# no_mix | clock_mix
set project(dft,scan_enable_pattern) scan_enable_*  ;# ports DFT adds (SDC case analysis)
```

`dft_insert` runs OpenROAD (`synth(oss,dft,openroad_cmd) {openroad -exit -no_init}`):

- It calls `set_dft_config`, `scan_replace` and `execute_dft_plan`.
- It ties the scan-ICG test enable to the scan-enable port.
- It writes `reports/dft_plan.rpt`.
- Netlists: `synthesis_pre_dft.v` → `synthesis.v`.

SDCs:

- `synthesis1` writes `synthesis.func.sdc` (scan enable `set_case_analysis 0`) and `synthesis.scan.sdc` (value 1).
- `export_data1` copies them to `final.sdc` / `final.scan.sdc`.
- The release stages `<design>.scan.sdc` under `sdc/`.

### Clock gating

```tcl
set synth(oss,clock_gating,enable)  true   ;# yosys clockgate
set synth(oss,clock_gating,min_ffs) 4      ;# min flops sharing clock + enable
```

The ICG cells come from the tech config:

- `tech(<track>,icg_cell)`, e.g. `tech(hd,icg_cell) "sky130_fd_sc_hd__dlclkp_1/GATE/CLK/GCLK"`.
- `tech(<track>,icg_scan_cell)` when DFT is on (`sky130_fd_sc_hd__sdlclkp_1/GATE/CLK/GCLK/SCE`). Its test enable goes to scan enable.

Report: `reports/synthesis_clock_gating.rpt`.

### Multi-Vt

- `project(vt_flavors)` lists the Vts the block may use; opensky uses `"svt"`.
- `tech(vt_variants_available)` lists the Vts in the library.
- `tech(vt_pattern,<vt>)` matches each Vt's cells.

Every Vt library of the lib set is read, and Vts outside `project(vt_flavors)` become dont_use. Both SYNTH and PNR use the same procs in `oss_utils.tcl`:

- `oss_vt_dont_use` returns the patterns of unused Vts. It errors on a flavor that is not available.
- `oss_pnr_dont_use` returns `tech(<track>,dont_use_pnr)` + `oss_vt_dont_use`.

### Memory / register-array report

`reports/synthesis_memory.rpt` starts with
`# Memories inferred (mapped to register arrays): N`. It sits next to
`synthesis_hierarchy.rpt` and `synthesis_stat.rpt`.

---

## 6. Memory macros (SRAM)

Memory macros come from the library tag's `memory` category
(`library-manager add --category memory`). The library manager bundles every
view of the shared categories (`memory`, `io`, `analog`, `ip`) and emits these keys:

```tcl
tech(lef,<cat>)  tech(gds,<cat>)  tech(cdl,<cat>)  tech(verilog,<cat>)
tech(lib,<corner>,timing,memory)
```

CDL accepts `.cdl`, `.spice` or `.sp`. The tech config maps the macros onto the flow:

```tcl
set tech(memory,power_pins)  "vccd1"   ;# add_global_connection patterns
set tech(memory,ground_pins) "vssd1"
set tech(memory,lib_set_map) { ... }   ;# stdcell lib set -> memory lib corner (sky130: all -> tt_1p8v_25c)
```

How each flow handles memories:

| Flow | Behavior |
|---|---|
| SYNTH | Memory libs are read as blackboxes. Instances are kept with `setattr -set keep 1` (`oss_memory_cells` = MACRO names from the tag's memory LEFs). |
| FP | Memories are placed and reported like hierarchy children (`oss_fp_place_macros`, `oss_fp_macro_report`). |
| PNR | A leaf block with memories gets the `leaf_mem` PDN: block pins on the horizontal strap layer `tech(5M,pdn_strap_h)` = `met5`, straps extended to the boundary, and a via-only `mem_<inst>` grid met4→met5 per macro. Export reads the memory LEF/GDS, and the CDL adds the memory CDL. |
| STA | Memories are timed through `tech(memory,lib_set_map)`. |
| PV LVS | Magic reads the memory LEFs as abstracts (`gds noduplicates true`), so Netgen sees black boxes. |

gcd P2 RTL (`inputs/opensky/gcd/P2/gcd.v`, `gcd.f`) instantiates two
`sky130_sram_1kbyte_1rw1r_32x256_8` macros (`u_sram_req`, `u_sram_resp`) and
runs with `LIB_TAG=OSS2`.

---

## 7. FP — floorplan options (OpenROAD)

Defaults are in `FP_openroad_config.tcl`; set them per block in the FP user config.

| Key | Default | Meaning |
|---|---|---|
| `fp(oss,fp,die_area)` | `""` | `{x0 y0 x1 y1}`. Wins over utilization sizing; the core is the die inset by `core_margin`. |
| `fp(oss,fp,core_utilization)` | `45` | Std-cell utilization %. |
| `fp(oss,fp,aspect_ratio)` | `1.0` | |
| `fp(oss,fp,core_margin)` | `10` | µm |
| `fp(oss,fp,macro_channel)` | `60` | µm between macros / to the core edge |
| `fp(oss,macro,halo)` | `10` | µm |
| `fp(oss,macro,placement)` | `""` | `""` = `rtl_macro_placer`; `"row"` = one row from the core corner; `{inst x y orient ...}` = explicit `place_macro` |
| `fp(oss,macro,blockage_sides)` | `{}` | Any of `left right bottom top`: hard placement blockages from each child macro to the core edge |
| `fp(oss,pins,region)` | `""` | `""` = all edges; e.g. `top:*` → `set_io_pin_constraint -region` for all signal pins |
| `fp(oss,pins,constraints)` | `{}` | Per-group ports: `{{top:100-400 a_vec*} {left:* host_*}}` — each group kept together (`-group`) in its region; pins no group takes use `pins,region`; a glob matching no pin is an error |
| `fp(oss,probe,enable)` | `false` | `probe1` (off the release chain): quick `global_placement` + `global_route` on the floorplan, nothing saved → `work/FP/probe1/reports/probe.rpt` (per-layer usage / overflow, total overflow, wirelength) |
| `fp(oss,probe,density)` | `0.6` | Probe global-placement target density |
| `fp(oss,pins,hor_layer)` / `ver_layer` | `met3` / `met2` | |
| `fp(oss,fail_on_violations)` | `false` | |

**Die sizing with macros.** The core area is the macro area (including halo) plus std-cell area divided by utilization. The core width is at least the sum of the macro widths plus (n+1) channels. The core height is at least the tallest macro plus 2 channels. Use `die_area` to size a parent die from a released child macro. `workarea/chain_ai_p1.sh` computes ai_subsys's `die_area` from mac_array's released size.

**Floorplan skill.** `.claude/skills/floorplan/` (Claude Code) proposes die size, explicit
macro placement, blockage sides and port groups from the SYNTH release + library tag,
probes the shortlist (`fp(oss,probe,enable) true`), checks the floorplan rules
(`scripts/fp_check.py`) and recommends the smallest floorplan with 0 probe overflow.
Unset `fp(oss,macro,placement)` uses `rtl_macro_placer -min_channel_size <halo>`.

**Macro blockages** (`fp(oss,macro,blockage_sides)`) are created after `tapcell`:

- Each region is clipped to the existing rows, minus the endcap width at each row end. Endcaps under a blockage fail detailed placement.
- Rows with the same x-span merge into one blockage.
- The blockages are written to the DEF.

```tcl
set fp(oss,macro,blockage_sides) {left right bottom}   ;# ai_subsys: mac_array on the core bottom edge
set fp(oss,pins,region)          "top:*"
```

**Power grid switch** (project key, default `true` in opensky):

```tcl
set project(pdn,enable) false   ;# logical supply connections only; no grid, power checks skipped (bring-up)
```

PNR reads the floorplan from the FP release:
`set pnr(input,def_file_release_tag) "FP_EXIT"`.

---

## 8. STA — OpenSTA

`STA_opensta_config.tcl`, `timing_opensta.tcl`:

| Key | Default | Meaning |
|---|---|---|
| `sta(oss,sta,mode)` | `flat` | `flat` reads every descendant's `tech(block,<b>,netlist)` and stitches per-instance SPEF (`read_spef -path <inst>` from `tech(block,<b>,spef,<rc>)`). `hier` uses the children's `.lib` models. Flat applies only when the design has children. A missing block SPEF is an error naming `spef_corners`. |
| `sta(oss,allow_no_spef)` | `false` | |
| `sta(oss,report_power)` | `true` | `power.rpt` per scenario; `sta_power.rpt` merged |
| `sta(oss,drv,max_fanout)` | `10` | DRV fanout limit |
| `sta(oss,dont_use,tech_key)` | `dont_use_pnr` | Patterns checked against placed cells |
| `sta(oss,dont_touch,instances)` | `{}` | Each pattern must match ≥1 instance, else MISSING |
| `sta(oss,path_groups)` | R2R / I2R / R2O / I2O | registers/inputs → registers/outputs |
| `sta(oss,path_groups,report_paths)` | `10` | |

Per-scenario reports (`work/STA/timing1/.../reports/`):

- `setup.rpt` and `hold.rpt`
- `timing_<setup|hold>_<group>.rpt`, which gives WNS / TNS / NVP per path group
- `drv.rpt`, with limits and margins
- `dont_use.rpt` and `dont_touch.rpt`
- `parasitic_annotation.rpt`, with header lines `Unannotated nets :`, `Partially annotated nets :` and `Load-less nets (not counted) :`
- `power.rpt`

`merge_reports1` writes `sta_summary.rpt` (per-scenario rows + worst, including `Worst setup NVP` / `Worst hold NVP`), `sta_power.rpt` and `sta_checklist.rpt`.

NVP is the number of violating paths. It is computed with `find_timing_paths -slack_max 0 -endpoint_path_count 1`.

The `STA_SIGNOFF` checklist (`global/config/exit/v1.0.0/STA_SIGNOFF_config.tcl`) publishes with the STA run. Each of these checks must be `== 0`:

| ID | Check |
|---|---|
| STA_0012 | dont_use cells |
| STA_0013 | dont_touch instances missing |
| STA_0014 | Driven nets without SPEF parasitics (worst scenario; load-less nets excluded) |
| STA_0015 | Partially annotated nets |

PNR uses the same path groups: `pnr(oss,path_groups)` gives R2R/I2R/R2O/I2O WNS/TNS/NVP per corner per stage, which SmartGrid shows as stage × corner tables.

---

## 9. PV — DRC / LVS

`PV_magic_config.tcl` (`pv(tool,name) magic`):

| Key | Default | Meaning |
|---|---|---|
| `pv(oss,drc,engine)` | `klayout` | `klayout` (deck `tech(klayout,drc)`, sky130 manufacturing rules) or `magic` |
| `pv(oss,pv,mode)` | `flat` | `hier`: child cells emptied for DRC (`<design>_hier.gds`); child LEFs read as abstracts so Netgen black-boxes them in LVS. `flat`: full DRC; LVS adds every descendant's `tech(block,<b>,lvs_netlist)` |
| `pv(oss,drc,klayout_threads)` | `4` | |
| `pv(oss,drc,klayout_options)` | `{feol true beol true offgrid true floating_met false seal false sram_exclude true}` | |
| `pv(oss,drc,style)` | `drc(full)` | Magic only |
| `pv(oss,drc,max_errors)` | `0` | |
| `pv(signoff,lvs_required)` | `true` | `false` → DRC-only verdict (LVS still reported) |

KLayout writes `reports/drc_klayout.lyrdb`.

The PV release carries what it checked: `gds/<design>.gds` (required) and `netlist/<design>.cdl` (required when `lvs_required`). Downstream flows read the CDL through the handshake `flow_input_handshake(PV,netlist_cdl)`. `library-manager add --category block` takes a block's GDS/CDL from this PV release.

PV can also run on an FP release (`FP_EXIT`, which needs PV). It checks the floorplan GDS and the LVS netlist. `run_signoff.sh <b> FP_EXIT` sets `pv(signoff,lvs_required) false`, which gives a DRC-only verdict.

---

## 10. LEC — Yosys equivalence

`LEC_yosys_config.tcl`. `compare1` runs `load_design / compare / report / save_design / verdict`. The golden netlist is the SYNTH release (`<PHASE>_SYNTH_v1`). The revised netlist is the exit's PNR release (`lec(release,exit_from) "input,netlist_revised_release_tag"`; `netlist_golden` is exit-exempt).

---

## 11. Workarea scripts (`workarea/`)

These scripts drive the opensky chain end-to-end. Run them from `workarea/`.

### `run_p1_dl3.sh [blocks...]` — DL3 blocks (default `gcd mac_array`, run in parallel)

| Env | Default | Meaning |
|---|---|---|
| `PHASE` | `P1` | Sets `project(phase)` / `project(release,phase)` in each generated user config |
| `RUN` | `<phase>_b1` (e.g. `p1_b1`) | Run name |
| `LIB_TAG` | project's `lib_config_tag` | Library tag |
| `FROM` | — | `FP` skips SYNTH; `PNR` skips SYNTH + FP |
| `PUBLISH_OVERRIDE` | — | Non-empty → `--override` on publish |

Per block, the script runs these steps:

1. SYNTH (tag `<PHASE>_SYNTH_v1`).
2. FP, then publish.
3. PNR with `pnr(input,def_file_release_tag) "FP_EXIT"`, then publish.
4. `run_signoff.sh <b> PRO_EXIT` in the background.

If `inputs/opensky/<b>/<PHASE>/<b>.f` exists, it replaces `synth(input,rtl_filelist)`; today only gcd P2 has one. `overrides/pnr_<PHASE>.tcl` is appended to the PNR `setup/override_config.tcl`.

```bash
PHASE=P2 RUN=p2_b1 LIB_TAG=OSS2 ./run_p1_dl3.sh gcd
FROM=PNR ./run_p1_dl3.sh mac_array
```

### `run_p1_dl2.sh <blocks...>` — DL2 blocks (e.g. `ctrl_subsys ai_subsys`)

`PHASE=P1 RUN=p1_b1 LIB_TAG=OSS1` are fixed in the script. The script accepts:

- `FROM=FP|PNR`
- `UNTIL=FP`: stop after the FP publish
- `UNTIL=PNR`: stop after the PNR publish, no signoff
- `PUBLISH_OVERRIDE`

Per block, the script runs these steps:

1. SYNTH.
2. FP, then publish, then `run_signoff.sh <b> FP_EXIT` in the background (PV on the floorplan).
3. PNR, then publish.
4. `run_signoff.sh <b> PRO_EXIT`.

It uses `overrides/pnr_<PHASE>_dl2.tcl` if present, else `overrides/pnr_<PHASE>.tcl`.

### `run_signoff.sh <block> [exit]` — STA / PV / LEC on an exit release (exit default `PRO_EXIT`)

| Env | Default | Meaning |
|---|---|---|
| `PHASE` | `P0` | |
| `RUN` | `oss_b1` | |
| `FLOWS` | `STA PV LEC` | Any subset; the flows run in parallel |
| `PUBLISH` | `1` | Publishes only when `1` |
| `LIB_TAG` | — | Sets `project(lib_config_tag)` |
| `PV_MODE` | `flat` | `hier` sets `pv(oss,pv,mode) hier` and releases to `<exit>_HIER` |
| `MAX_PARALLEL` | — | Sets `flow(max_parallel_jobs)` |

With `FP_EXIT`, the script runs PV only (run `<RUN>_fp`, DRC-only verdict).

```bash
FLOWS="STA" PHASE=P2 RUN=p2_b1 LIB_TAG=OSS2 ./run_signoff.sh gcd PRO_EXIT
PV_MODE=hier MAX_PARALLEL=4 PHASE=P1 ./run_signoff.sh ai_subsys PRO_EXIT
```

### Release tests

- `test_place_release.sh` (`SRC=place1` → PLACE_EXIT, `SRC=cts_opt1` → CTS_EXIT) runs on gcd P2. It exercises the three ways to release an intermediate stage: bypass, set-dep and add-node. See [Exit Release Guide](exit-release-guide.md).
- `test_exit_order.sh` runs on gcd P2:
  1. Releases PRO_EXIT via set-dep.
  2. Runs STA signoff.
  3. Runs a full BTO run, which passes the exit-order gate.

Both test scripts hard-code the `cbflow` path (`C=...`). Edit that line on another checkout.

Publishes from all scripts are serialized by the lock directory `workarea/.publish.lock`.
