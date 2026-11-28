# MMMC manager — reference (open-source flow, opensky / sky130)

## Files
| File | Holds |
|---|---|
| `global/config/project/<p>/v1.0.0/mmmc_config.tcl` | `mmmc(process_corners)`, `mmmc(pvt,<corner>) {{<v> <t>} …}`, `rc_corners` array, `operating_modes` (mode → SDC), `analysis_views` (full cartesian mode × PVT × RC), `mmmc_scenario_sets(setup|hold|power|signoff|all|sta_*)` (engineer-declared) |
| `…/mmmc_node_scenarios.tcl` | `array set mmmc { <node> { setup {…} hold {…} } }` per stage name (place, cts, cts_opt, route, pro, extraction, signoff, timing, eco, synthesis, init_*) |
| `…/mmmc_view_definition.tcl` | Cadence `read_mmmc` file (generated, `--style flow`) — not read by the open-source flow |
| `global/config/tech/<tech>/v1.0.0/tech_config.tcl` | `tech(rc_corners_available)`, `tech(rcx,<stack>,<rc>,openrcx)` decks, `tech(memory,lib_set_map)` |
| `<lib_tag_root>/<tech>/<TAG>/lib_config.tcl` (+ `blocks_config.tcl`) | `tech(<trk>,lib,<lib_set>,timing)`, `tech(lib,<c>,timing,memory)`, `tech(block,<b>,lib_sets)`, `tech(block,<b>,spef_corners)` |

View name `<mode>_<corner>_<voltage>_<rc>_<temp>` (e.g. `func_ss_1p60v_rc_max_m40c`);
its lib set is `<corner>_<voltage>_<temp>` (`ss_1p60v_m40c`).

## How scenarios reach each flow
| Flow / node | Scenario source (first hit wins) |
|---|---|
| STA `timing1` (dynamic, one subnode per view) | 1 `setup/override_config.timing1.tcl`: `sta(mmmc,setup_scenarios)` / `sta(mmmc,hold_scenarios)` · 2 the same keys in user_config · 3 `mmmc_scenario_set,<sta(mmmc,scenario_set)>` (default `signoff`) — `race_engine.py::_resolve_dynamic_subnodes`. The DAG is rebuilt on every command, so a new view becomes a new READY subnode. |
| STA `extraction1` | one subnode per `rc_corner_list` entry (all RC corners, whatever the views) |
| PNR place … signoff, ECO | `get_node_scenarios` (`utils.tcl`) reads the **dict** `mmmc(<node>)`, then `mmmc(<stage>)`; one OpenROAD corner per view (`oss_node_views`). |
| SYNTH, DFT init_* | `mmmc(synthesis)`, `mmmc(init_scan|init_atpg|init_sim)` |

Every STA scenario reports setup **and** hold; the setup / hold lists only
select which views run. PNR `signoff` writes one timing model per view lib set
(`final__<lib_set>.lib` → release `lib/`, tag `tech(block,<b>,lib,<lib_set>)`):
a parent can only time a view whose lib set every child's signoff node timed.

## One-run overrides (text for the user)
```tcl
# STA, a new run: in its uc_STA_*.tcl (or <run>/setup/override_config.timing1.tcl)
set sta(mmmc,setup_scenarios) "func_ss_1p60v_rc_max_m40c func_ss_1p60v_rc_max_100c func_tt_1p80v_rc_typ_25c"
set sta(mmmc,hold_scenarios)  "func_ff_1p95v_rc_min_m40c func_ff_1p95v_rc_min_100c"
# PNR, one node of one run: <run>/setup/override_config.cts_opt1.tcl
set mmmc(cts_opt1) {setup {func_ss_1p60v_rc_max_m40c} hold {func_ff_1p95v_rc_min_m40c}}
# PNR, every node of a stage in one run: user_config (sourced after mmmc_node_scenarios.tcl)
set mmmc(cts_opt) {setup {…} hold {…}}
```
**Pitfall**: the run dashboard's MMMC dialog on a PNR node writes
`set mmmc(<node>,setup_scenarios) "…"` — `get_node_scenarios` never reads that
key, so the node silently keeps the project assignment (`mmmc_inventory.py`
flags it `override_ignored`). Use the dict form above.

## mmmc-manager subcommands
Read-only: `show`, `validate`, `list-views`, `list-scenarios --set <s>`,
`generate-view-def` (stdout without `--output`). All take `--project <p> [--tech <t>]`.
Writing (user only, after the proposal is agreed): `set-node`, `add-mode`,
`remove-mode`, `add-pvt`, `remove-pvt`, `add-rc`, `generate`, `generate-view-def --output`.
`validate` checks names only — not that the tag has the lib sets or that child
blocks have models; `mmmc_inventory.py` does.

## Reading the QoR
- **Setup corner**: sky130 hd at 1.60 V shows temperature inversion — the cold
  `ss_1p60v_*_m40c` view is the setup corner (gcd, ctrl_subsys, ai_subsys,
  mac_array, chip all); `ss_*_100c` usually limits nothing for setup but can own
  tran slack and is the hot leakage view of the slow corner.
- **Hold corner**: `ff_1p95v_rc_min_m40c` usually; `ff_*_100c` within a few ps —
  keep both until margin is clear. Hold owned by an `ss` view (opensky_chip P1)
  means skew / interface / child-model paths: keep that view in the hold set.
- **RC corners**: the OpenRCX decks (librelane `rules.openrcx.sky130A.{min,nom,max}`)
  give identical total net capacitance — only resistance changes (≈ ±9 %); on
  gcd P0 the 3 RC corners differ by < 1 ps. One RC corner per PVT is enough:
  rc_max for setup, rc_min for hold.
- **Power**: the signoff set has no typical view, so power numbers in STA / PNR
  are at ff / ss. Typical power = `func_tt_1p80v_rc_typ_25c` (power set);
  worst total / leakage = `ff_1p95v_*_100c` (EMIR, leakage signoff).
- **Memories**: sky130 SRAMs ship one corner (`tt_1p8v_25c`); every view times
  them there (`tech(memory,lib_set_map)`), so macro paths do not track PVT.
- **Children**: `tech(block,<b>,lib_sets)` = the child's PNR signoff views. A tt
  power view at a parent is BLOCKED until every child's signoff node times
  `tt_1p80v_25c` and the tag is refreshed (`library-manager` skill). Child SPEF
  corners follow the child's views too (ctrl_subsys: rc_max rc_min only).

## QoR sources the script reads
| Source | Path |
|---|---|
| STA run | `work/STA/<timing node>/<view>/reports/qor.tcl` (+ `drv.rpt`) |
| STA release | `<rel>/<phase>/<b>/STA/<exit>/metrics.rpt` (`# scenario:` sections) |
| PNR run | `work/PNR/<node>/reports/checklist_metrics.rpt` (path-group WNS/TNS/NVP + power per view; no per-view DRV) |
| PNR release | `<rel>/<phase>/<b>/PNR/<exit>/metrics.rpt` (`# stage: <s>` blocks) |
Parsing of `qor.tcl` / `drv.rpt` is shared with the timing-eco skill
(`timing-eco/scripts/timing_summary.py`); for paths of a scenario use that script.
