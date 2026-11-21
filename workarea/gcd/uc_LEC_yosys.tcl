#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — LEC with the open-source stack (Yosys equivalence)
# Golden = SYNTH release netlist, revised = PNR release netlist (per-input
# tags); publishes P0_LEC_v<n> (reports/lec).
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "opensky"
set flow(type)                 "LEC"
set flow(design_name)          "gcd"
set flow(run_name)             "oss_r1"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set lec(tool,name)                     "yosys"
set lec(input,netlist_golden_release_tag)  "P0_SYNTH_v1"
set lec(input,netlist_revised_release_tag) "P0_PNR_v1"

set project(release,tag)       "P0_LEC_v1"
