# Checklist reference (CBflow exit milestones)

## Where things live
| What | Where |
|---|---|
| Milestone configs | `global/config/exit/v1.0.0/<M>_config.tcl` — `milestone_info(name|discipline|flow_type|stage|stage_node)`, `check_packs`, `mandatory_checks`, `optional_checks`, `mandatory_files`, `deliverables` |
| PD check library | `global/config/exit/v1.0.0/checks/<category>_checks.tcl` (timing, placement, clock, power, routing, physical, si, manufacturing, eco_flow); a check joins `<M>` when `<M>` is in its `applicable_milestones` and its category is in `<M>`'s `check_packs` (value = min phase index) |
| Policy | `remediation_config.tcl` (16 failure types: setup_wns, setup_tns, hold_wns, clock_skew, clock_coverage, clock_power, congestion, utilization_high/low, drc_violations, antenna_violations, metal_density, ir_drop, em_violations, lvs_mismatch, gds_errors), `threshold_overrides.tcl`, `waiver_config.tcl` |
| Tool map (where the data is) | the run's node config, from the tool overlay `<disc>/config/flow/v1.0.0/node_configs/<FLOW>_<tool>_config.tcl`: `<arr>(checklist,exit_node,<M>)`, `(checklist,report)` default report (may use `${exit_node}`), `(checklist,report,<check>)`, `(checklist,metric,<check>)` regex group 1, `(checklist,grep,<check>)` + `(checklist,grep_pass_if,<check>)`, `(checklist,mandatory_files,<M>)` |
| Exit order / tape-out | `PD/config/flow/v1.0.0/release_config.tcl`: `MILESTONE_ORDER`, `TAPEOUT_MILESTONES` (BTO MTO), `MILESTONE_STAGE_MAPPING` |
| Engine | `PD/utils/commands/checklist_cmd.py` (`_load_and_validate_config`, `_apply_tool_checklist_map`, `_evaluate_checks`, `cmd_status`) — the scripts import it read-only |
| Status output | `<run>/logs/checklist_status_<M>_<YYYYmmdd_HHMMSS>.json`: `verdict` (PASS/BLOCKED), `completion_pct`, `mandatory_checks` / `optional_checks` / `library_checks` = `[{name, status, detail, value}]`, `file_status` = `[{path, exists}]`, `blocking_items`, `active_waivers` |
| RACE DB | path in `<run>/.race_db_pointer`; `checklist_results(milestone, check_name, check_type, category, severity, status, metric_value, threshold, detail, report_file, phase, evaluated_at, check_id, description)`; `jobs` (latest row per `job_name` = node status: DONE / FAIL / BYPASSED / INVALIDATED / READY …); `run_config` `env.TECH_NAME`, `env.CBFLOW_BLOCK_NAME`, `env.CBFLOW_PROJECT_PHASE` |

## How `status` evaluates a check
1. Phase gate: `min_phase_index` (0-based into `project(phases)`) above the run's phase → SKIPPED.
2. Active waiver for the check name → WAIVED.
3. Report: `report_file` / `grep_file` (after the tool map) → `report_pattern` (path, else basename searched under `work/`, shortest path wins) → `reports/<check>.rpt`. None → **NA**.
4. `metric_pattern` → group 1 vs `operator` `default_threshold` (`between` = "lo,hi"); no match → **PENDING**; no capture group → CONFIG_ERROR.
5. `grep_pattern` → PASS when found (`grep_pass_if found`) / not found.
6. `script check_file_exists.tcl` → PASS when the file is non-empty.
7. Otherwise the report text: SKIP marker (test mode) → SKIP; `FAIL(ED)` → FAIL; `PASS(ED)` → PASS; else PENDING.

Blocking (`verdict BLOCKED`): any active mandatory check not PASS/WAIVED (FAIL **or** NA/PENDING),
any FAIL library check with `severity critical`, any missing mandatory file. Optional and
non-critical library FAILs never block (the text report prints them as `[WARN]`; a blocking
critical library FAIL is also printed `[WARN]` — read the BLOCKING ITEMS list).

## Thresholds
- The check's own `operator` / `default_threshold` (unit in `unit`) is what `status` uses.
- `threshold_overrides.tcl` layers `default_thresholds(<M>,<metric>)` → `phase_defaults(<phase>,<M>,<metric>)`
  → `threshold_override(<project>,<M>,<metric>)` → `phase_override(<project>,<phase>,<M>,<metric>)`.
  Units: timing / skew **ps**, utilization / congestion ratio, IR mV. **`status` does not apply them**
  (`generate` only displays the project / phase-override layers). Triage shows the policy value next to
  the check threshold; library slack checks are in **ns** (`-0.024` ns = -24 ps).
- DV targets: `project(dv,targets,M<n>)` (DV overlay `DV/config/project/<p>/v1.0.0/<p>_dv_config.tcl`);
  the gate is `dv_signoff_status` (`Status : PASS` in `dv_signoff.rpt`); the per-metric optional
  checks use `>= 0` (vacuous).

## Waivers
Policy (`waiver_config.tcl` `waiver_policy`): approval + expiry required, `max_waiver_duration_days 90`,
`allow_bto_waivers false`, `allow_mto_waivers false`. Only on the user's decision:
```bash
bin/cbflow flow checklist waiver --action list [--milestone <M>]
bin/cbflow flow checklist waiver --action add --milestone <M> --check <check> --reason "<why>" \
    --approver <name> --expiry <YYYY-MM-DD, <= today+90> --project <p>
```
`add` prints the `W<nnn>,<field>` Tcl lines for `waiver_config.tcl` (framework config — the owner adds
them). It does not itself refuse BTO/MTO or a > 90-day expiry, and scopes block `*`: check those yourself.

## add-check (suggest; the user / owner runs it — it edits global/config/exit/)
```bash
bin/cbflow flow checklist add-check --milestone <M> --name <name> --type mandatory|optional \
    --description "<d>" --grep-file <run-relative report> --grep-pattern '<regex>' --grep-pass-if found|not_found
bin/cbflow flow checklist add-check --milestone <M> --name <name> --type file --file-path <path>
bin/cbflow flow checklist add-check --milestone <M> --name <name> --type mandatory --script <s> --criteria "<expr>"
bin/cbflow flow checklist remove-check --milestone <M> --name <name>
```
No numeric-threshold mode: a metric check needs a milestone-config entry (`metric_pattern` or
tool-map `metric`, `operator`, `default_threshold`, `unit`) — propose it as a config change. A grep
check reads a fixed run-relative path: other flows' runs need their own tool-map entry.

## Drill-down (confirm a cause before proposing a fix)
| Failure | Look at |
|---|---|
| PNR setup / hold / NVP | `work/PNR/<exit_node>/reports/checklist_metrics.rpt` (scenario blocks: `Setup R2R WNS …`), `signoff_setup_<group>_<scenario>.rpt`, `report_qor.rpt` (worst corner) → skill `timing-eco` |
| PNR max tran / cap | `signoff_drv.rpt`, `checklist_metrics.rpt` (`Max slew/cap violations`) → `timing-eco` |
| PNR DRC / antenna | `signoff_check_drc.rpt`, `signoff_drc_markers.rpt`, `report_antenna.rpt`; PV run → skill `drc-fix` |
| clock skew / latency / transition | `report_clock_qor.rpt`, `report_clock_timing.setup.rpt`, `clock_skew.rpt` |
| STA_SIGNOFF | `work/STA/merge_reports1/outputs/sta_summary.rpt` (per-scenario WNS / TNS), `work/STA/timing1/<scenario>/reports/{setup,hold,drv,parasitic_annotation,dont_use,dont_touch}.rpt` |
| ATPG | `work/ATPG/coverage_report1/reports/coverage.rpt` (fault vs test coverage, redundant / aborted, inputs unused), `zd_sim1/reports/zd_sim.log`, `timing_sim1/` (BYPASSED marker), `signoff1/reports/signoff.rpt` |
| DV M<n> | `work/<FLOW>/signoff1/reports/dv_signoff.rpt` (targets NOT MET, open vPlan features, failing tests), `cov_merge1/reports/coverage.rpt`; per-test logs under the regress node |
| NA / missing file | node dir `BYPASSED` marker, latest `jobs` row, stage log `work/<FLOW>/<node>/run/<job>.log`; path under another flow's `work/<F>/` = check definition does not fit this flow |

## Known framework gaps (found 2026-11-28; owner fixes, do not patch)
- `BTO_config.tcl` optional_checks ends with an orphan `{ "description" "Audit test — safe to remove" … }`
  block: the file no longer sources in Tcl (odd `array set` list); the Python parser skips it.
- `parse_mandatory_files` stops at the first `}` — in `${design_name}` — so BTO evaluates only its first
  3 mandatory files; `cmd_status` also checks file paths without expanding `${design_name}`.
- PNR open-source tool map has `mandatory_files,PRO_EXIT` but not `,BTO`/`,MTO`: BTO on a PNR run
  requires `work/SYNTH_PNR/signoff1/*` (always missing) and `bto_si` reads a SYNTH_PNR path (NA → blocking).
- `ATPG_fault_config.tcl`: `atpg(checklist,grep,atpg_timing_sim_pass)` has no `report,` entry, so it
  greps `coverage.rpt` (no `Mismatches` line) and cannot pass.
- `list-checks --run-dir` evaluates without the tool map (PENDING where `status` has PASS/FAIL).
- `_detect_milestone_for_flow` falls back to BTO for every flow without a `<FLOW>_SIGNOFF` config
  (ATPG, M<n>_EXEC …) — always pass `--milestone`.
- PNR signoff: `checklist_metrics.rpt` `DRC violations : 0` while `signoff_check_drc.rpt`
  `Total DRC violations : 2` (bto_signoff_drc passes, drc_spacing fails).

## Learned store
`learned/<tech>/<block>.md` and `learned/<tech>/_tech.md`, one line per entry, written by
`scripts/learn.py add` — format in [learned/README.md](learned/README.md). `checklist_triage.py`
prints entries whose `check` matches; `missing_checks.py` flags suggestions recorded as `missing-rejected`.

## Commands
| Command | Use |
|---|---|
| `bin/cbflow flow checklist list [--discipline D]` | milestones |
| `… list-checks --milestone <M> [--phase P] [--summary]` | check definitions (not the verdict) |
| `… generate --milestone <M> --project <p> --phase <P> [--format text|json|html]` | formatted checklist (+ waivers, project overrides) |
| `… status --milestone <M> --run-dir <run> [--phase P]` | verdict; writes logs JSON + DB rows |
| `… waiver --action list|add|revoke …` | waivers (add/revoke on the user's decision) |
| `… add-check / remove-check …` | check definitions (user / owner) |
| `… sign-off --milestone <M> --run-dir <run> --approver <n>` | sign-off (user only) |
| `scripts/checklist_triage.py <run> --milestone <M>` | ranked failures + evidence + remediation |
| `scripts/missing_checks.py <run> --milestone <M>` | missing / lax checks + add-check commands |
| `scripts/learn.py context|read|add` | learned store |
