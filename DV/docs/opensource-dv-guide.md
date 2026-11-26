# Open-Source DV Flows — SystemVerilog UVM on Verilator (vendor `opensource`, project `opensky`)

Spec-to-GDS phase 3: the DV milestones run real regressions. `<flow>(tool,name)
"verilator"` selects the open-source overlay of TB_SETUP, M1–M4_EXEC and
DV_SIGNOFF (`<FLOW>_verilator_config.tcl`); `review` (the default) keeps the
generic review gates. The human gate of every DV exit is the checklist sign-off
(`cbflow flow checklist sign-off --milestone <EXIT>`).

Related guides: [open-source RTL (RTL_SPEC, register model, vPlan)](../../RTL/docs/opensource-rtl-guide.md),
[spec-to-GDS chain](../../PD/docs/02-user-guide/spec-to-gds-guide.md).

## 1. Tools

Verilator 5.052 (`--binary --timing --coverage`) with Accellera UVM 2020.3.1
(`UVM_HOME`, `UVM_NO_DPI`), z3 for constrained `randomize()`, ccache. Installs
(into `lsf(oss,tools_dir)`): `global/utils/oss/install_uvm.sh`,
`global/utils/oss/install_pytools.sh` (z3 from the pinned `z3-solver` wheel →
`<tools_dir>/bin/z3`). Helpers: `DV/utils/oss/uvmgen.py` (testbench generator),
`DV/utils/oss/dv_tool.py` (tests / regress / covmerge / runsum / triage /
signoff), Tcl `DV/utils/utilities/v1.0.0/oss_dv_utils.tcl`.

Verilator notes: covergroup bins are counted into the coverage database (crosses
included) but `get_coverage()` returns 0 — CBflow computes functional coverage
from the merged database. Every constrained `randomize()` is a z3 call; long
directed loops assign fields procedurally.

## 2. Testbench generation (uvmgen)

From the block spec (`<b>.spec.yaml`), the PeakRDL UVM register model and the
vPlan:

| File | Content |
|---|---|
| `<b>_if.sv` | one interface per spec interface + `<b>_misc_if` (other ports) |
| `<b>_agents.sv` | valid_ready: item (+ idle-delay `dist`), driver (DUT slave: requests; DUT master: random back-pressure `cfg.<if>_ready_pct`), monitor (protocol checks on DUT-driven valid/ready); APB4: master driver, monitor, RAL adapter |
| `<b>_scoreboard.sv` | input transactions → reference model, output transactions compared in order; drained at the end of a test |
| `<b>_env.sv` | agents, register model + predictor, scoreboard, coverage |
| `<b>_seqs.sv`, `<b>_base_test.sv` | random sequences; base test (reset, watchdog, objection, drain) + sanity test (traffic + `uvm_reg_hw_reset_seq`) |
| `<b>_test_stubs.sv` | a failing `TEST-TODO` stub per vPlan test whose class no user file defines |
| `<b>_tb_pkg.sv` | package including the above |
| `<b>_tb_top.sv`, `tb.f`, `rtl.f` | clock / reset from the spec, DUT hookup, compile list, DUT sources (code-coverage scope) |

The register model is the RTL_SPEC release's `ral/<b>_ral.sv` (PeakRDL UVM;
the spec's register map must declare its endianness — see the RTL guide).

User-owned files (`tb_setup(oss,tb_dir)`; same file name replaces the generated
one, regeneration never touches them; extra files there are carried along —
`` `include `` them from a user file): `<b>_ref_model.sv`, `<b>_coverage.sv`
(coverpoint / cross names = vPlan coverage items), `<b>_tests.sv`. Until they
exist the generated ones are stubs (`tb_gen.rpt`: reference model "STUB —
outputs not checked", coverage model "STUB — no functional coverage"). Memory models
of the library tag travel with the TB (fixed for simulation, quiet).

Timing convention: the TB drives 1 time unit after the rising edge and samples
at the rising edge (pre-update values — what the DUT's flops capture).

## 3. Flows

| Flow | Stages | Release |
|---|---|---|
| TB_SETUP | spec1, ral1, vplan1, rtl1 (inputs) → tb_gen1 → compile1 → sanity1 → release_data1 | `TB_SETUP_EXIT`: `tb/` (`tb.f` at the released paths), `spec/<b>_vplan.xlsx`, `reports/` (tb_gen, sanity) |
| M1–M4_EXEC | tb1, vplan1 (inputs) → compile1 → regress1 → cov_merge1 ∥ triage1 → signoff1 → release_data1 | `M<n>_EXIT`: `reports/` (regression, coverage, triage, sign-off reports, `metrics.json`, `plan.csv`, `results.csv`), `data/merged.dat` |
| DV_SIGNOFF | metrics1 (M4 release `reports/metrics.json`) → collect1 → signoff1 → release_data1 | `DV_SIGNOFF_EXIT`: collect / sign-off reports, `reports/m4_metrics.json` |

Inputs by tag: TB_SETUP `tb_setup(input,release_tag) "SPEC_EXIT"` (spec, ral,
vplan — handshakes `TB_SETUP,spec|ral|vplan`) + `tb_setup(input,rtl_release_tag)
"LINT_SIGNOFF"` (`TB_SETUP,rtl`, any release with `rtl/<b>.f`); M<n>
`<m>_exec(input,release_tag) "TB_SETUP_EXIT"` (`M<n>_EXEC,tb|vplan`); DV_SIGNOFF
`dv_signoff(input,release_tag) "M4_EXIT"` (`DV_SIGNOFF,metrics`).

User configs (`workarea/gcd/`):

```tcl
# uc_TB_SETUP_P3.tcl
set flow(type)                      "TB_SETUP"
set flow(run_name)                  "p3_tb"
set tb_setup(tool,name)             "verilator"
set tb_setup(input,release_tag)     "SPEC_EXIT"      ;# spec, register model, vPlan
set tb_setup(input,rtl_release_tag) "LINT_SIGNOFF"   ;# RTL filelist
set tb_setup(oss,tb_dir)            "<CBFLOW_ROOT>/inputs/opensky/gcd/P3/tb/uvm"

# uc_M2_EXEC_P3.tcl (M1 / M3 / M4 alike)
set flow(type)                 "M2_EXEC"
set m2_exec(tool,name)         "verilator"
set m2_exec(input,release_tag) "TB_SETUP_EXIT"

# uc_DV_SIGNOFF_P3.tcl
set flow(type)                    "DV_SIGNOFF"
set dv_signoff(tool,name)         "verilator"
set dv_signoff(input,release_tag) "M4_EXIT"
```

Keys (overlay defaults):

| Key | Default |
|---|---|
| `tb_setup(oss,tb_dir)` | `""` — the user-owned TB files |
| `tb_setup(oss,sanity,seeds)` | `2` |
| `<arr>(oss,verilator,flags)` / `oss,verilator,jobs` | `{-Wno-fatal -Wno-lint -Wno-style}` / `8` |
| `<arr>(oss,sim,timeout_s)` | `1800` per simulation |
| `<m>_exec(oss,milestone)` | `M1` … `M4` |
| `<m>_exec(oss,regress,seeds)` | M1 `2`, M2 `5`, M3 `10`, M4 `10` |
| `<m>_exec(oss,regress,jobs)` | `8` parallel runs |

**Launch** — the P3 user configs set `flow(use_xterm) "true"` (local, no
LSF): each stage opens an xterm (needs `$DISPLAY` — XQuartz on macOS; the
xterm is `lsf(xterm,command)`). Set `flow(use_xterm) "false"` for silent local
runs.

**Regression** (`dv_tool.py tests` + `regress`) — tests of every vPlan feature
up to the milestone (cumulative) × `<m>_exec(oss,regress,seeds)` seeds, in
parallel; a run passes on exit 0 + UVM report summary + 0 UVM_ERROR /
UVM_FATAL. **Triage** (`dv_tool.py triage`) buckets failing runs by their first
UVM_ERROR / UVM_FATAL signature.
**Metrics** (`dv_tool.py covmerge`, coverage of the passing runs merged) — pass rate (runs), code coverage (line + branch of the DUT
sources; expr / toggle / FSM reported), functional coverage (bins), vPlan
coverage (features whose tests pass on every seed and whose coverage items are
100 %, or waived in the vPlan).
**Targets** (`dv_tool.py signoff`) — `project(dv,targets,M<n>)` in the DV
project overlay (`DV/config/project/<proj>/v1.0.0/<proj>_dv_config.tcl`); keys
`pass_rate`, `code_coverage`, `functional_coverage`, `plan_coverage` (%), a key
left out has no target; a target not met fails the sign-off stage, so the exit
is not released. opensky:

```tcl
set project(dv,targets,M1) {pass_rate 100}
set project(dv,targets,M2) {pass_rate 80  code_coverage 70 plan_coverage 60}
set project(dv,targets,M3) {pass_rate 95  code_coverage 90 plan_coverage 90}
set project(dv,targets,M4) {pass_rate 100 code_coverage 95 plan_coverage 100}
```

**DV sign-off** — `collect1` reads `project(phase_exits,DV)` for the run's
phase and finds every DV exit of it (except DV_SIGNOFF_EXIT) in the release
area with its sign-off status; `signoff1` passes when every one is PASS and the
M4 vPlan coverage is 100 %.

**Exit plan** — `project(phase_exits,DV)` (global project config) lists the DV
exits per phase; they release in that order (the exit-order gate checks them
independently of the PD plan `project(phase_exits)`). opensky:

```tcl
set project(phase_exits,DV) {
    P0 {}
    P1 {TB_SETUP_EXIT M1_EXIT M2_EXIT}
    P2 {M3_EXIT M4_EXIT DV_SIGNOFF_EXIT}
    P3 {TB_SETUP_EXIT M1_EXIT M2_EXIT M3_EXIT M4_EXIT DV_SIGNOFF_EXIT}
}
```

## 4. Pilot — gcd P3 (`inputs/opensky/gcd/P3/tb/uvm/`)

User-owned: reference model (stream responses), coverage (17 vPlan coverage
items), 10 tests (F1–F8); `gcd_mbist_test` (F9) stays a stub until the MBIST
collar exists (DFT phase 5). Runs: `workarea/gcd/uc_TB_SETUP_P3.tcl`,
`uc_M1_EXEC_P3.tcl` … `uc_M4_EXEC_P3.tcl`, `uc_DV_SIGNOFF_P3.tcl` — steps of
the spec-to-GDS chain (TB_SETUP in stage 3, M1 4, M2 5, M3 6, M4 7, DV_SIGNOFF 8).

| Exit | Runs | Pass rate | Code cov. | Functional | vPlan | Sign-off |
|---|---|---|---|---|---|---|
| TB_SETUP_EXIT | sanity × 2 | 100 % | – | – | – | PASS |
| M1_EXIT | 4 | 100 % | 73.4 % | 3.8 % | 0/1 (operands_zero 2/3 bins) | PASS (target: pass rate) |
| M2_EXIT | 35 | 100 % | 94.5 % | 98.6 % | 4/5 | PASS |
| M3_EXIT | 100 | 100 % | 96.1 % | 100 % | 8/8 | PASS |
| M4 | 110 | 90.9 % | 96.1 % | 100 % | 8/9 | FAIL — F9 MBIST not implemented (10 runs, one triage bucket) |

Found on the way: an RTL bug — a CTRL.start written while the engine was busy
(stream operation) was lost (single-cycle pulse sampled only in S_IDLE);
`gcd_mixed_test` (F8) failed with RES_COUNT 0; fixed with a pending-start latch,
then RTL_SPEC → RTL checks → SYNTH / FP / PNR and the DV ladder re-ran.

## 5. Future scope (not implemented)

**LSF agent** — today a regression runs every test × seed as parallel local
processes inside the tool container (`<m>_exec(oss,regress,jobs)`), and the
flow stages run locally (`flow(use_lsf) false`). The planned LSF agent will:
- submit each regression run (and each flow stage) as an LSF job — queue and
  resources from `lsf_config.tcl` tiers, licence-aware;
- watch the jobs (pending / running / exit), resubmit infrastructure
  failures (host lost, preemption) without hiding real test failures, and
  enforce per-run timeouts;
- stream per-job status and results back to the RACE database and the run
  dashboard, so a regression of thousands of runs is tracked like one stage.
