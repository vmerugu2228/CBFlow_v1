# project-kickoff reference

## Spec (JSON) — `kickoff.py template` writes it
| Field | Kind | Notes |
|---|---|---|
| `like` | reference | project the defaults and file templates come from |
| `name` | ASK | lowercase, `[a-z][a-z0-9_]{1,31}`, not taken |
| `description`, `owner`, `contact`, `chip_lead` | ASK | |
| `technology` | ASSUMED | `global/config/tech/<tech>/v1.0.0/tech_config.tcl` must exist |
| `phases`, `current_phase` | ASSUMED | current ∈ phases |
| `phase_exits.{PD,DV,DFT,RTL}.{<phase>: [exits]}` | ASSUMED | every exit must be an exit milestone of that discipline (`global/config/exit/v1.0.0/*_config.tcl`) |
| `top_module` | ASK | = the hierarchy top |
| `hierarchy.{<block>: {level, parent, children, description}}` | ASK | one DL1 top; parent / children symmetric; levels DL1 / DL2 / DL3 |
| `enabled_flows.{PD,DFT,DV,RTL}` | ASSUMED | each flow must belong to that discipline (`flow(discipline,*)`) |
| `default_tools.{<FLOW>: tool}` | ASSUMED | `node_configs/<FLOW>_<tool>_config.tcl` must exist |
| `process.{vt_flavors, track_variant, metal_stack}` | ASSUMED | |
| `sdc_modes.{<mode>: constraint file pattern}` | ASSUMED | first mode = default |
| `power.{vdd_net, vss_net, vdd_pin, vss_pin, rail_nets}`, `pdn_enable` | ASSUMED | |
| `paths.workarea`, `paths.release`, `paths.race_db` | ASK | absolute; release / race outside the CBflow tree |
| `paths.lib_root`, `paths.lib_tag_root` | ASSUMED | directories must exist |
| `paths.release_disks` | optional | `project(release,disks)` |
| `library.base_tag` | ASK | cells-only base tag under `<lib_tag_root>/<tech>/` |
| `library.project_tag` | optional | created empty (default `<NAME>_T1` in the skill) |
| `mmmc.{voltage, temperature, process_corners, pvt, rc_corners}` | ASSUMED | pvt per process corner; rc corners need temperature + multipliers |
| `dft.*`, `dv_targets.<M>.*`, `lsf.*` | ASSUMED | |
| `dates.start`, `dates.tapeout` | start = today, tapeout ASK | |
| `block_inputs.<block>.{rtl_filelist, sdc, upf}` | ASK (SYNTH enabled) | files must exist; upf required when the reference SYNTH config sets one |

## What `generate` writes (staging dir mirrors the repo)
| File | From |
|---|---|
| `global/config/project/<p>/v1.0.0/<p>_config.tcl` | reference config; replaced: name, phases, current phase, phase_exits per discipline, description / owner / contact / technology / VT / top / tapeout, power, SDC modes, DFT keys, design_hierarchy; signoff_chain removed (per project) |
| `PD/config/project/<p>/v1.0.0/<p>_pd_config.tcl` | workarea, track, metal stack, lib_root, lib_tag_root, lib_config_tag (project tag), race db, release path / phase, LSF, default_tools, release disks; SmartGrid branding removed |
| `DFT/…/<p>_dft_config.tcl`, `DV/…/<p>_dv_config.tcl` (RTL when present) | DFT patterns / coverage, DV targets |
| `global/…/mmmc_config.tcl` | voltages, temperatures, process corners, pvt, rc_corners, operating modes |
| `global/…/mmmc_node_scenarios.tcl` | the reference's per-node setup / hold, re-targeted by role (same process + RC corner class) |
| `global/…/schedule_config.tcl` | start / tapeout (exit dates to fill) |
| `<workarea>/<block>/uc_<FLOW>[_<tool>]_<phase>.tcl` | per block × enabled flow, from the reference's newest-phase user config of a block of the same kind (leaf / parent), with project, block, phase, paths, library tag and SYNTH inputs substituted; leftover `/inputs/...` paths are reported as NOTEs |
| `STAGE.json` | registry entry, dirs to make, notes |

`apply` adds:
- the `master_projects.json` entry;
- the dirs (workarea / blocks / release / race);
- `mmmc_view_definition.tcl` (`mmmc-manager generate-view-def --style flow`);
- the project library tag (`library-manager project-tag create`);
- the record of everything it made, in `APPLIED.json`.

## Undo (only when the user asks)
1. Remove every path in `<stage>/APPLIED.json`.
2. Restore `global/config/master_projects.json` (git checkout, if nothing else changed).
3. Remove the project tag dir.

## Known limits
- `signoff_chain` and schedule exit dates are not generated (write them once the
  flows run).
- Flows beyond SYNTH may need project files (testbench, spec YAML, waivers): NOTEs
  name each one.
- MMMC node scenarios are re-targeted by role. Review them with
  `mmmc-manager list-scenarios` (mmmc-manager skill).
