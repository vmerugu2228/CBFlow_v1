#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Flow Registry — cross-discipline flow catalog
#
# Authoritative source for:
#   · flow(types)        — every flow known to the framework (PD + DFT + DV)
#   · flow(disciplines)  — top-level tree names
#   · flow(discipline,*) — per-flow → discipline mapping
#
# Consumed by:
#   · Every discipline's flow_config.tcl (PD/DFT/DV) at source-time — the
#     discipline appends only its mandatory_vars, not the flow catalog itself
#   · Python-side race_engine._build_command() for handler routing
#   · flow_cmd.py for `cbflow flow types [--domain PD|DFT|DV]` grouping
#   · config_validator to fail-fast on unmapped flows
#
# Every entry in flow(types) MUST also have flow(discipline,<name>) below.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Flow Types (union of every discipline) ────────────────────────────────────
set flow(types) {
    SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP SYNTH_PNR
    DFT_INSERT_PASS1 DFT_INSERT_PASS2 DFT_INSERT_PASS3
    SCAN_INSERT ATPG GLS_FUNC GLS_SCAN_MBIST
    SPEC_RAMP PLANNING TB_SETUP M1_EXEC M2_EXEC M3_EXEC M4_EXEC
    ECO_EXEC DV_SIGNOFF
}

# ── Discipline Roster ─────────────────────────────────────────────────────────
# Names match the top-level directory: $CBFLOW_ROOT/<name>. Each discipline
# owns its cmds/, node_configs/, tool_launch_config, etc. The launcher exports
# CBFLOW_<UPPER>_DIR for each when the directory exists.
set flow(disciplines) {PD DFT DV}

# Directory-name for each discipline (used by paths.get_node_config_path()).
set flow(discipline_dir,PD)  "PD"
set flow(discipline_dir,DFT) "DFT"
set flow(discipline_dir,DV)  "DV"

# ── Per-Flow → Discipline Map ─────────────────────────────────────────────────
# PD — Physical Design (implementation → tapeout)
set flow(discipline,SYNTH)          "PD"
set flow(discipline,FP)             "PD"
set flow(discipline,FCFP)           "PD"
set flow(discipline,PNR)            "PD"
set flow(discipline,SYNTH_PNR)      "PD"
set flow(discipline,STA)            "PD"
set flow(discipline,LEC)            "PD"
set flow(discipline,CLP)            "PD"
set flow(discipline,PV)             "PD"
set flow(discipline,EMIR)           "PD"
set flow(discipline,POPT)           "PD"
set flow(discipline,ECO)            "PD"

# DFT — Design-For-Test (scan, ATPG, GLS)
# DFT_INSERT is split into three sequential passes (per owner spreadsheet
# DFT_FLOW_Dependencies_Input_Output.xlsx): Pass1=Core (MBIST+BSCAN),
# Pass2=Top (TDR/DFT-Signals/SRI), Pass3=EDT+OCC. Each pass is releasable
# and surfaces independently in the dashboard so per-pass owners can
# track their own work.
set flow(discipline,DFT_INSERT_PASS1) "DFT"
set flow(discipline,DFT_INSERT_PASS2) "DFT"
set flow(discipline,DFT_INSERT_PASS3) "DFT"
set flow(discipline,SCAN_INSERT)      "DFT"
set flow(discipline,ATPG)             "DFT"
set flow(discipline,GLS_FUNC)         "DFT"
set flow(discipline,GLS_SCAN_MBIST)   "DFT"

# DV — Verification milestone / review flows
set flow(discipline,SPEC_RAMP)      "DV"
set flow(discipline,PLANNING)       "DV"
set flow(discipline,TB_SETUP)       "DV"
set flow(discipline,M1_EXEC)        "DV"
set flow(discipline,M2_EXEC)        "DV"
set flow(discipline,M3_EXEC)        "DV"
set flow(discipline,M4_EXEC)        "DV"
set flow(discipline,ECO_EXEC)       "DV"
set flow(discipline,DV_SIGNOFF)     "DV"

# ── Descriptions — sourced from adjacent descriptions_config.tcl ──────────────
# Kept in a separate file for edit-cadence (descriptions change often; the
# registry is stable). The load path below tolerates the case where the
# registry is sourced standalone (e.g. by a Python test harness) without
# descriptions.
set _desc_path [file join [file dirname [info script]] descriptions_config.tcl]
if {[file exists $_desc_path]} {
    source $_desc_path
}
unset -nocomplain _desc_path

# ══════════════════════════════════════════════════════════════════════════════
#                    CROSS-DOMAIN RUNTIME DEFAULTS
# Every discipline (PD, DFT, DV) inherits these. Each discipline's
# flow_config.tcl is sourced INSTEAD of (not on top of) another discipline's,
# so cross-cutting defaults MUST live here to reach all three.
# ══════════════════════════════════════════════════════════════════════════════

# ── Cross-domain mandatory keys ─────────────────────────────────────────────
# Set by user_config or workspace create; validated pre-flight for every flow.
set flow(mandatory_vars,all) {flow(run_name) flow(type) flow(design_name)}

# ── Runtime defaults ────────────────────────────────────────────────────────
# Guarded sets — if the cascade is ever reordered so user_config /
# flow_config loads BEFORE this registry, the bare `set` form would
# silently clobber the user's values. `info exists` guards keep the
# defaults as defaults — the first writer wins.
proc _registry_default {name value} {
    if {![info exists ::$name]} { set ::$name $value }
}
# Scalar flow(...) defaults — paths with parens need the array-aware
# info exists form.
if {![info exists flow(run_name)]}           { set flow(run_name)      "" }
if {![info exists flow(design_name)]}        { set flow(design_name)   "" }
if {![info exists flow(run_type)]}           { set flow(run_type)      "" }
if {![info exists flow(run_types)]}          { set flow(run_types)     {hier flat} }
if {![info exists flow(test_mode)]}          { set flow(test_mode)     "false" }

# ── Dispatcher ──────────────────────────────────────────────────────────────
if {![info exists flow(dispatcher)]}            { set flow(dispatcher)    "race" }
if {![info exists flow(use_lsf)]}               { set flow(use_lsf)       false }
if {![info exists flow(use_xterm)]}             { set flow(use_xterm)     true }
if {![info exists flow(cbflow_version)]}        { set flow(cbflow_version) "2.0.0" }
if {![info exists flow(dashboard,default_port)]} { set flow(dashboard,default_port) 0 }

# ── Flow Mode ───────────────────────────────────────────────────────────────
if {![info exists flow(mode)]}                  { set flow(mode)                  "default" }
if {![info exists flow(merged,flows)]}          { set flow(merged,flows)          "SYNTH_PNR" }
if {![info exists flow(merged,fp_independent)]} { set flow(merged,fp_independent) true }
if {![info exists flow(merged,pnr_depends_fp)]} { set flow(merged,pnr_depends_fp) true }

# ── RACE Database ───────────────────────────────────────────────────────────
if {![info exists flow(race,db_max_sessions)]}  { set flow(race,db_max_sessions)  10 }

# ── MMMC ────────────────────────────────────────────────────────────────────
# MMMC is a PD concept (STA/PNR scenarios), but the global default lives here
# so the resolver has something to emit for DFT/DV runs too — they set it to
# false in their own flow_config if it's truly not applicable.
if {![info exists flow(mmmc,enabled)]}         { set flow(mmmc,enabled)        true }
if {![info exists flow(mmmc,enabled_stages)]}  { set flow(mmmc,enabled_stages) {place cts cts_opt route pro signoff} }

# ── Milestones ──────────────────────────────────────────────────────────────
# PD milestones — DFT and DV will declare their own via flow(exit_milestones,DFT)
# / flow(exit_milestones,DV) as those phases mature.
if {![info exists flow(exit_milestones)]} { set flow(exit_milestones) {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO} }

# ── File-Validation Rules ───────────────────────────────────────────────────
# Type → allowed extensions. Consumed by validate_run + inputs handlers.
array set FILE_VALIDATION_RULES {
    RTL     {".v" ".vg" ".sv" ".svh"}
    NETLIST {".v" ".vg" ".sv"}
    SDC     {".sdc"}
    DEF     {".def"}
    SPEF    {".spef"}
    LIB     {".lib"}
    LEF     {".lef"}
    GDS     {".gds" ".gdsii"}
    SDF     {".sdf"}
}

set flow(valid_status) {NOTRUN RUNNING COMPLETE ERROR WARNING SKIPPED RETRACED}
set flow(status_file)  ".run.status"
