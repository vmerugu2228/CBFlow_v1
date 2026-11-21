#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow user_config — STA with the open-source stack (OpenRCX + OpenSTA)
# Consumes the PNR release by tag (routed DEF, netlist, per-mode SDC);
# extraction runs per RC corner, timing per MMMC scenario (node scenario set,
# or list them below); publishes <phase>_STA_v<n> (reports + summary).
# ═══════════════════════════════════════════════════════════════════════════════

set project(name)              "<project_name>"
set flow(type)                 "STA"
set flow(design_name)          "<design_name>"
set flow(run_name)             "<run_name>"
set flow(run_type)             "hier"
set flow(test_mode)            "false"
set flow(use_lsf)              "false"
set flow(use_xterm)            "true"

set sta(tool,name)             "opensta"              ;# selects STA_opensta_config.tcl
set sta(input,release_tag)     "<phase>_PNR_v1"       ;# DEF + netlist + SDC from the PNR release

set project(release,tag)       "<phase>_STA_v1"

# Optional: explicit scenarios (default: the node's MMMC scenario set)
#   set sta(mmmc,setup_scenarios) "func_ss_1p60v_rc_max_100c func_ss_1p60v_rc_max_m40c"
#   set sta(mmmc,hold_scenarios)  "func_ff_1p95v_rc_min_m40c func_ff_1p95v_rc_min_100c"
