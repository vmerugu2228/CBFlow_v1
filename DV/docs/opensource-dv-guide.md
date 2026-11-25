# Open-Source DV Flows — SystemVerilog UVM on Verilator (vendor `opensource`, project `opensky`)

Spec-to-GDS phase 3: the DV milestones run real regressions. `<flow>(tool,name)
"verilator"` selects the open-source overlay of TB_SETUP, M1–M4_EXEC and
DV_SIGNOFF (`<FLOW>_verilator_config.tcl`); `review` (the default) keeps the
generic review gates. The human gate of every DV exit is the checklist sign-off
(`cbflow flow checklist sign-off --milestone <EXIT>`).

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
| `<b>_test_stubs.sv` | a failing `TEST-TODO` stub per vPlan test nobody wrote |
| `<b>_tb_top.sv`, `tb.f`, `rtl.f` | clock / reset from the spec, DUT hookup, compile list, DUT sources |

User-owned files (`tb_setup(oss,tb_dir)`; same file name replaces the generated
one, regeneration never touches them): `<b>_ref_model.sv`, `<b>_coverage.sv`
(coverpoint / cross names = vPlan coverage items), `<b>_tests.sv`. Memory models
of the library tag travel with the TB (fixed for simulation, quiet).

Timing convention: the TB drives 1 time unit after the rising edge and samples
at the rising edge (pre-update values — what the DUT's flops capture).

## 3. Flows

| Flow | Stages | Release |
|---|---|---|
| TB_SETUP | spec, ral, vplan, rtl (inputs) → tb_gen → compile → sanity → release_data | `TB_SETUP_EXIT`: `tb/` (tb.f at the released paths), `spec/<b>_vplan.xlsx`, reports |
| M1–M4_EXEC | tb, vplan (inputs) → compile → regress → cov_merge ∥ triage → signoff → release_data | `M<n>_EXIT`: sign-off, coverage, regression, triage, `plan.csv`, `metrics.json`, `data/merged.dat` |
| DV_SIGNOFF | metrics (M4 release) → collect → signoff → release_data | `DV_SIGNOFF_EXIT` |

Inputs by tag: TB_SETUP `tb_setup(input,release_tag) "SPEC_EXIT"` (spec, ral,
vplan) + `tb_setup(input,rtl_release_tag) "LINT_SIGNOFF"`; M<n>
`<m>_exec(input,release_tag) "TB_SETUP_EXIT"`; DV_SIGNOFF
`dv_signoff(input,release_tag) "M4_EXIT"`.

**Regression** — tests of every vPlan feature up to the milestone
(cumulative) × `<m>_exec(oss,regress,seeds)` seeds, in parallel; a run passes
on exit 0 + UVM report summary + 0 UVM_ERROR / UVM_FATAL.
**Metrics** — pass rate (runs), code coverage (line + branch of the DUT
sources; expr / toggle / FSM reported), functional coverage (bins), vPlan
coverage (features whose tests pass on every seed and whose coverage items are
100 %, or waived in the vPlan).
**Targets** — `project(dv,targets,M<n>)` in the DV project overlay
(`DV/config/project/<proj>/v1.0.0/<proj>_dv_config.tcl`); a target not met fails
the sign-off stage, so the exit is not released.

**Exit plan** — `project(phase_exits,DV)` (global project config) lists the DV
exits per phase; they release in that order (the exit-order gate checks them
independently of the PD plan). opensky: P1 TB_SETUP_EXIT M1 M2, P2 M3 M4
DV_SIGNOFF_EXIT, P3 (the spec-to-GDS pilot) all six.

## 4. Pilot — gcd P3 (`inputs/opensky/gcd/P3/tb/uvm/`)

User-owned: reference model (stream responses), coverage (17 vPlan coverage
items), 10 tests (F1–F8); `gcd_mbist_test` (F9) stays a stub until the MBIST
collar exists (DFT phase 5). Runs: `workarea/gcd/uc_{TB_SETUP,M1..M4_EXEC,DV_SIGNOFF}_P3.tcl`.

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
