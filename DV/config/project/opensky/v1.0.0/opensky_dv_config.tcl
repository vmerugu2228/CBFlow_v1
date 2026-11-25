#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# opensky — DV overlay (open-source UVM flows: TB_SETUP, M1-M4_EXEC, DV_SIGNOFF)
# Sourced after the global project config. The DV exits each phase delivers
# are project(phase_exits,DV) in the global project config.
# ═══════════════════════════════════════════════════════════════════════════════

# Milestone targets, the single source the M<n>_EXEC sign-off checks against
# (%): pass_rate = passing runs / runs (every test x seed), code_coverage =
# line + branch of the DUT sources, functional_coverage = covergroup bins,
# plan_coverage = vPlan features up to the milestone closed (tests passing on
# every seed + coverage items 100 %) or waived. A key left out has no target.
set project(dv,targets,M1) {pass_rate 100}
set project(dv,targets,M2) {pass_rate 80  code_coverage 70 plan_coverage 60}
set project(dv,targets,M3) {pass_rate 95  code_coverage 90 plan_coverage 90}
set project(dv,targets,M4) {pass_rate 100 code_coverage 95 plan_coverage 100}
