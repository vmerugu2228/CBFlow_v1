# Spec-to-GDS on the Open-Source Stack (project `opensky`, pilot gcd P3)

One block goes from a YAML spec to signed-off GDS through every discipline's
flows, each a normal cbflow run that releases an exit. The chain is data in the
project config and one driver runs it.

## 1. The chain

`project(signoff_chain,<phase>)` (global project config) — stages in order; a
stage is a list of `<step> <release tag>` pairs that run in parallel:

```tcl
set project(signoff_chain,P3) {
    {RTL_SPEC SPEC_EXIT}
    {RTL_LINT LINT_SIGNOFF  RTL_CDC CDC_SIGNOFF  UPF_CHECK UPF_SIGNOFF}
    {SYNTH P3_SYNTH_v1  TB_SETUP TB_SETUP_EXIT}
    {SCAN_INSERT SCAN_INSERT_EXIT  FP FP_EXIT  M1_EXEC M1_EXIT}
    {ATPG_pre ATPG_PREPD_EXIT  PNR BTO  M2_EXEC M2_EXIT}
    {STA BTO  PV BTO  LEC BTO  ATPG_post ATPG_POSTPD_EXIT  GLS_FUNC BTO  GLS_SCAN_MBIST BTO  M3_EXEC M3_EXIT}
    {M4_EXEC M4_EXIT}
    {DV_SIGNOFF DV_SIGNOFF_EXIT}
}
set project(signoff_chain,bypass) { ATPG_post {timing_sim1} }
```

A `<step>` names the block's user config: `workarea/<block>/uc_<step>_<phase>.tcl`,
or else the single `uc_<step>_<tool>_<phase>.tcl` (e.g. `uc_SYNTH_yosys_P3.tcl`,
`uc_FP_openroad_P3.tcl`); variants of a flow are separate steps (`ATPG_pre`,
`ATPG_post`). The flow comes from the user config's `flow(type)`, the run
directory from `<phase>_run_<FLOW>_<block>_<flow(run_name)>`. The tag is the release the
step must produce: an exit (`SPEC_EXIT`, `BTO`, `M2_EXIT` …) or a named tag
(`P3_SYNTH_v1`). Signoff flows (STA / PV / LEC / GLS) release under the exit
they verify. `project(signoff_chain,bypass)` lists stages the open-source flow
does not support (ATPG timing simulation) as `<step> {<nodes>}`, bypassed in
that step's run after it is created / retraced (`cbflow run bypass --stages`).

Every exit still goes through its own gates: the exit-order gate per
discipline (`project(phase_exits)` for PD, `project(phase_exits,DV)` for DV),
the checklists, the signoff flows' exit inputs.

## 2. The driver

```bash
workarea/run_spec2gds.sh <block> <phase>            # the whole chain
FROM=SCAN_INSERT UNTIL=STA workarea/run_spec2gds.sh gcd P3
DRY=1 workarea/run_spec2gds.sh gcd P3               # plan: steps, user configs, run dirs
```

| Env | Meaning |
|---|---|
| `FROM=<step>` | start at the stage holding `<step>` (earlier stages skipped) |
| `UNTIL=<step>` | stop after the stage holding `<step>` |
| `DRY=1` | print the plan only (nothing is created or run) |
| `PROJECT=<p>` | project (default `opensky`) |

Dry run for gcd P3 (abridged):

```
spec-to-GDS chain — gcd P3 (project opensky, 8 stages, release <CBFLOW_ROOT>/test_releases)
stage 1: RTL_SPEC -> SPEC_EXIT   uc_RTL_SPEC_P3.tcl   P3_run_RTL_SPEC_gcd_p3_spec
stage 2: RTL_LINT -> LINT_SIGNOFF   uc_RTL_LINT_P3.tcl   P3_run_RTL_LINT_gcd_p3_lint
...
stage 3: SYNTH -> P3_SYNTH_v1   uc_SYNTH_yosys_P3.tcl   P3_run_SYNTH_gcd_p3_synth
stage 4: FP -> FP_EXIT   uc_FP_openroad_P3.tcl   P3_run_FP_gcd_p3_b1
stage 5: ATPG_pre -> ATPG_PREPD_EXIT   uc_ATPG_pre_P3.tcl   P3_run_ATPG_gcd_p3_atpg_pre
...
stage 8: DV_SIGNOFF -> DV_SIGNOFF_EXIT   uc_DV_SIGNOFF_P3.tcl   P3_run_DV_SIGNOFF_gcd_p3_dv
```

A step whose user config is missing shows `MISSING` in the plan (and fails the
step in a real run).

Per step: `cbflow workspace create` from the user config (or, for an existing
run, `cbflow run retrace` from its first stage), the step's bypasses,
`cbflow run all`. A step passes when the run passes **and** its release
`<project(release,path)>/<phase>/<block>/<FLOW>/<tag>/RELEASE_COMPLETE` is
newer than the step's start — a run that did nothing does not count. The chain
stops after a stage with a failure; log `workarea/<block>/spec2gds_<phase>.log`
+ a summary table; per-run logs `spec2gds_<step>_create.log` (block dir),
`spec2gds_retrace.log` / `spec2gds_bypass.log` / `spec2gds_run.log` (run dir).
Runs launch as the user configs say — the gcd P3 configs set
`flow(use_xterm) "true"`, so every stage opens an xterm (needs `$DISPLAY`).

## 3. SmartGrid

The project page's **Spec-to-GDS chain** tile and `/project/<p>/chain`: per
phase with a `project(signoff_chain,<phase>)`, the stages left to right and one
row per block (of `project(design_hierarchy)`) that released at least one step —
✓ released (time), ⟳ released before an earlier stage was re-released (stale:
re-run it), — not released. A step's flow is the longest registered flow type
its name starts with (`ATPG_pre` → ATPG); status comes from the release area
only (`RELEASE_COMPLETE`), not from the run directories.

## 4. Pilot — gcd P3

Spec (`inputs/opensky/gcd/P3/spec/`), RTL (`rtl/gcd.sv`, GCD accelerator with
two SRAMs), UVM testbench (`tb/uvm/`), gate-level testbench
(`tb/gcd_gls_tb.v`), user configs `workarea/gcd/uc_*_P3.tcl`. Guides per
discipline: [RTL](../../../RTL/docs/opensource-rtl-guide.md),
[DV](../../../DV/docs/opensource-dv-guide.md),
[DFT](../../../DFT/docs/opensource-dft-guide.md),
[PD](opensource-flow-guide.md).

### Results (gcd P3)

| Stage | Steps | Result |
|---|---|---|
| 1–3 | RTL_SPEC, RTL_LINT / RTL_CDC / UPF_CHECK, SYNTH (slang) + TB_SETUP | PASS |
| 4 | SCAN_INSERT, FP, M1 | PASS |
| 5 | ATPG pre-PD, PNR (PLACE / CTS / PRO / BTO released in order), M2 | PASS |
| 6 | STA (setup WNS +5.915 ns, hold +0.069 ns), PV, LEC, ATPG post-PD, GLS_FUNC (queue + stream + registers on the BTO netlist), GLS_SCAN_MBIST, M3 (100/100) | PASS |
| 7 | M4 | FAIL — F9 memory-test readiness needs the MBIST collar (DFT phase 5) |
| 8 | DV_SIGNOFF | blocked by M4 |

Open on the BTO netlist: max transition (32) / capacitance (31) / fanout (39)
violations reported by STA (not gating). The driver found its own bug on the
first run (an existing run not retraced): the refreshed-release rule refused the
stale releases instead of passing them.
