# CBflow Release Bundle

**Generated:** 2026-07-10
**Test suite:** 1816 pass · 0 fail · 122 skip (100% pass rate)
**Coverage:** 12 flows × 2 projects (bumblebee + denali) × 2 tool chains (Cadence + Synopsys)
**Duration:** 561 seconds

## cbflow_global branch — Phase 0 checkpoint (2026-09-16)

Branch `cbflow_global` opened for multi-discipline refactor (PD + DFT + RTL DV).
Phase 0 preserves the current `PD/` tree as `legacy-PD/` at the repo root as a
full backup. Rollback: `rm -rf PD && mv legacy-PD PD`. Plan file at
`~/.claude/plans/lets-make-a-new-sharded-fern.md`.

## Bundle contents

- `manifest_release_files.txt` — 313 files touched this session (source only, no logs / workarea)
- `manifest_changed.txt` — full change list (403 files including workarea/logs)
- `manifest_deleted.txt` — 83 files removed (STA subnode-handler consolidation + PV `fill1`/`erc1` teardown)
- `test_report.json` — machine-readable test suite output
- `test_report.junit.xml` — CI-consumable JUnit report
- `dashboard_snapshot.json` — 21 registered runs with metadata
- `sources.tar.gz` — every file in `manifest_release_files.txt` archived

## Framework improvements

1. **STA scenario dispatch** — inlined per-scenario invocation into `timing_subnode_handler.tcl` (both PT + Tempus). Fixed non-test-mode crash from deleted `timing_scenario_pt.tcl` / `timing_scenario_handler.tcl` references.
2. **Post-cascade config validation** — new `config_validator.py`, `flow(mandatory_vars,*)` declared per-flow, wired into `race_engine.build()`. Missing keys fail pre-flight before any `work/` dir is created.
3. **Handler consolidation** — 133 subnode handlers migrated to `handler_dispatch` / `handler_dispatch_inputs` in `handler_common.tcl`. Net reduction of ~4400 LOC.
4. **Smarter dashboard polling** — ETag on `/api/status`, `/api/dag`, `/api/jobs`, `/api/run-summary`; activity-aware client interval (2 s active / 10 s idle); resolver cache tracks framework config mtimes so daemon picks up `<FLOW>_config.tcl` edits without restart.
5. **Test-mode outputs generator** — extended `handler_run` test-mode block to seed outputs for `nettran`, `merge_gds`, `fill_merge_gds`, `decomp`, `decomp_merge_gds`, `perc_ldl`. Keeps e2e14 (outputs_dir_nonempty) green.

## PV flow evolution

**Stages removed:** `fill1`, `erc1`

**Stages added:**
- `nettran1` — Verilog→SPICE translation (calibre `v2lvs`, ICV inputs)
- `merge_gds1` — fill GDS merge (`calibredrv layout filemerge`)
- `fill_merge_gds1` — post-merge fill validation (nmDRC fill-oriented runset)
- `decomp1` — mask decomposition / multi-patterning colorization (`calibre -mp`)
- `decomp_merge_gds1` — signoff GDS assembly (parallel to decomp, gated on both fill_merge_gds1 and decomp1)
- `perc_ldl1` — PERC Latch-up/Leakage-Driven analysis (parallel to `perc1`)

**Rewired:** all check stages (`drc1`, `lvs1`, `perc1`, `perc_ldl1`, `xor1`) now depend on `decomp_merge_gds1` instead of the old `fill1`. `lvs1` retains its dependency on `nettran1` for the LVS-ready CDL.

**Result:** 15 stages / 63 jobs (down from 12 stages / 44 in the original baseline; up from the interim 11/44 after fill1/erc1 removal alone).

## Command-file audit — Calibre nmPlatform 2024.x

All 12 stage command files use current reference-flow syntax:

- `calibre -drc -hier -64 -turbo N -hcell <file> <SVRF runset>`
- `calibre -lvs -hier -64 -turbo N <runset>`
- `calibre -perc -hier -64 -turbo N <runset>`  (and `-perc -ldl` variant)
- `calibre -mp -hier -64 -turbo N -mp_colors N <runset>`
- `calibredrv -64 -a "layout filemerge -in <a> -in <b> -out <c> -mode combine"`
- `v2lvs -v <verilog> -o <cdl> -c <top> -p VDD -g VSS -s <spicedeck> -lsp`

**Runset resolution convention** (documented in `PV_config.tcl` and all 4 `tech_config.tcl` files):

- Calibre (SVRF): `pv(<stage>,runset)` → `pv(input,rule_deck_<stage>)` → passthrough
- ICV (RSL):     `pv(<stage>,rule_deck)` → `tech(rules,<stage>)` → `pv(input,rule_deck_<stage>)`

All 4 tech configs (`gf_22nm`, `gf_28nm`, `tsmc_5nm`, `tsmc_7nm`) declare `tech(rules,drc/lvs/erc/perc/perc_ldl/fill/multi_patterning/xor/antenna)` + `tech(spice,stdcell)` placeholders as documented interface points.

## LSF coverage — new checks

Three new test-suite categories (2 static + 1 e2e) ensure every job has a real LSF envelope:

- **`cat15_lsf_per_node_assignment`** (static): every stage of every flow has either an explicit `lsf(flow_mapping,*,*)` entry OR a `default_queue_type` fallback. **107 checks pass.**
- **`cat16_lsf_tier_completeness`** (static): every referenced tier has `memory` + `cpu` + `runtime_limit`. **5 tiers verified** (XS, S, M, L, XL).
- **`e2e19_lsf_tier_resolved`** (e2e): every subnode job in every executed DAG resolved to a valid tier at build time. **21 runs verified**, ~1200 jobs total.

Alongside these, explicit `lsf(flow_mapping,PV,*)` entries added for all 6 new PV stages, so nothing falls to the default queue anymore.

## Dashboards live at

- **Per-run daemon:** `http://127.0.0.1:9001/` — 21 runs registered
- **bumblebee project dashboard:** `http://127.0.0.1:26333/` — 88 published rows (release history)
- **denali project dashboard:** `http://127.0.0.1:26025/` — 0 published rows (populate via `cbflow run release --tag <milestone>`)

## Recommended next steps

1. `git add PD/ workarea_test/` — bring the 313 changed files under version control
2. Split commits by area: STA fix, config validator, handler consolidation, dashboard, PV expansion, LSF checks
3. Tag release once tests are re-verified on the target machine
4. Populate `denali` project dashboard by promoting demo runs to milestones
