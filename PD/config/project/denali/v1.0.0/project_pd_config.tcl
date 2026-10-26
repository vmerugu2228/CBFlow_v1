#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — denali
# PD OVERLAY (physical design side: workarea, release, LSF, tool selection)
# Sourced after global project_config.tcl; keys are additive on project(...)
# =============================================================================

if {[info exists ::env(PROJECT_ROOT)]} {
    set ROOT_DIR $::env(PROJECT_ROOT)
} elseif {[info exists cbflow(root)]} {
    set ROOT_DIR [file dirname $cbflow(root)]
} else {
    # Fallback: calculate from current directory structure
    set ROOT_DIR [file dirname [file dirname [file dirname [file dirname [file normalize [info script]]]]]]
}
set project(root_dir) $ROOT_DIR

# Workarea path — all runs MUST be created under workarea_path/<design_name>/
# cbflow workspace create enforces this. Use full absolute path.
set project(workarea_path) "/Users/vmerugu/projects/CBflow_clone/workarea"

;# Technology — GF 28nm SLP-E
set project(track_variant) "9T"
set project(metal_stack) "10M"
set project(lib_config_tag) "LIB02"
set project(lib_root) "/proj/libs/gf_28nm"

;# Design hierarchy
set project(autoppt,enabled) "false"         ;# Enable AutoPPT summary generation (requires python-pptx)

# Custom settings
set project(custom,scripts) "denali_hooks.tcl"
set project(custom,constraints) "denali_constraints.sdc"
set project(custom,hooks) "denali_custom.tcl"
set project(custom,waivers) "denali_waivers.tcl"
set project(custom,config_files) "denali_extra.tcl"

;# ---------------------------------------------------------------------------
# RELEASE CONFIGURATION
# ---------------------------------------------------------------------------

# RACE DB Path
# DB structure: $db_path/$project_name/$domain/$flow_type/$user_$run_name.db
set project(race,db_path) "/Users/vmerugu/projects/CBflow_clone/.race_area/denali"

;# Release Path Configuration
# Release path structure: $release_path/$phase/$block_name/$release_tag
set project(release,path) "/Users/vmerugu/projects/CBflow_clone/test_releases"
set project(release,phase) "P0"
set project(release,block_name) ""
set project(release,active_tag) "BTO"
set project(release,expiry_date) "2027-06-30"
set project(lsf,enabled) "true"
set project(lsf,version) "1.0.0"
set project(lsf,config_date) "2026-06-02"

;# Default LSF settings
set project(lsf,default_queue) "M"
set project(lsf,emergency_queue) "ultra"

;# Project resource constraints
set project(lsf,max_concurrent_jobs) "15"
set project(lsf,max_daily_cost) "500.00"        ;# USD
set project(lsf,priority_class) "normal"         ;# normal, high, critical

;# Node-specific resource requirements — PNR (node_types: inputs, init_design, place, cts, cts_opt, route, pro, signoff, export_data)

;# Node-specific resource requirements — STA (node_types: inputs, extraction, timing, reporting)

;# Node-specific resource requirements — LEC (node_types: inputs, compare)

;# Node-specific resource requirements — EMIR (node_types: inputs, power_analysis, ir_drop, thermal_analysis)

;# Node-specific resource requirements — PV (node_types: inputs, drc, lvs, fill, perc, erc, xor)

;# Notification settings
set project(lsf,notifications,email_list) "denali@smartsoc.com"
set project(lsf,notifications,cost_alerts) "true"
set project(lsf,notifications,failure_alerts) "true"
set project(lsf,notifications,completion_alerts) "false"
set project(lsf,notifications,weekly_summary) "true"

;# ---------------------------------------------------------------------------

# ─────────────────────────────────────────────────────────────────────────────
# Design content + waivers (cross-project schema parity)
# ─────────────────────────────────────────────────────────────────────────────
set project(validation,post_route_waivers) ""        ;# Post-route validation waivers (project-specific)
set project(validation,powerplan_waivers) ""        ;# Powerplan validation waivers (project-specific)
set project(validation,SIGNOFF_waivers) ""        ;# Signoff validation waivers (project-specific)

# ═════════════════════════════════════════════════════════════════════════════
# MULTI-LINE VALUE BLOCKS (kept at the bottom so cross-project line-number
# parity holds for every single-line set project(...) key above.
# ═════════════════════════════════════════════════════════════════════════════

# ---------------------------------------------------------------------------
# DESIGN INFORMATION
# ---------------------------------------------------------------------------

# Simple hierarchy: denali_top (DL1) -> tom (DL2)
set project(default_tools) {
    SYNTH  "genus"
    PNR    "innovus"
    STA    "tempus"
    LEC    "conformal"
    CLP    "conformal_lp"
    EMIR   "voltus"
    PV     "calibre"
}

# ---------------------------------------------------------------------------
# VALIDATION WAIVER PATTERNS
# ---------------------------------------------------------------------------

# Global validation waivers - patterns that should be waivered across all stages
set project(validation,global_waivers) {
    ".*[Ww]arning.*clock.*skew.*"       ".*[Ww]arning.*timing.*convergence.*"
    ".*[Ww]arning.*unconnected.*pin.*"  ".*[Ww]arning.*library.*characterization.*"
    ".*[Ii]nfo.*optimization.*"         ".*[Nn]ote.*"
}

# Stage-specific validation waivers
set project(validation,init_design_waivers) {
    ".*[Ww]arning.*netlist.*case.*sensitivity.*"
    ".*[Ww]arning.*module.*binding.*"
    ".*[Ee]rror.*design.*has.*no.*clock.*constraint.*"
}

set project(validation,floorplan_waivers) {
    ".*[Ww]arning.*macro.*overlap.*"
    ".*[Ww]arning.*placement.*density.*"
    ".*[Ww]arning.*utilization.*target.*"
}

set project(validation,cts_waivers) {
    ".*[Ww]arning.*clock.*tree.*balance.*"
    ".*[Ww]arning.*clock.*latency.*"
    ".*[Ww]arning.*useful.*skew.*"
}

set project(validation,route_waivers) {
    ".*[Ww]arning.*antenna.*violation.*"  ".*[Ww]arning.*routing.*congestion.*"
}

set project(validation,signoff_waivers) {
    ".*[Ww]arning.*final.*timing.*report.*"  ".*[Ww]arning.*design.*margin.*"
}

# Flow-specific validation waivers
set project(validation,PNR_waivers) {
    ".*[Ww]arning.*place.*and.*route.*"
}

set project(validation,SYNTH_waivers) {
    ".*[Ww]arning.*synthesis.*optimization.*"
}

# Critical error patterns that should NEVER be waivered
set project(validation,critical_errors) {
    ".*[Ee]rror.*license.*"
    ".*[Ee]rror.*tool.*crash.*"
    ".*[Ee]rror.*segmentation.*fault.*"
    ".*[Ee]rror.*memory.*allocation.*"
    ".*[Ff]atal.*"
    ".*[Aa]bort.*"
    ".*[Cc]ore.*dumped.*"
}

# Release directory sub-structure
set project(release,structure) {
    "netlist"  "sdc"
    "def"      "gds"
    "spef"     "upf"
    "reports"  "data"
    "db"       "docs"
}

# ─────────────────────────────────────────────────────────────────────────────
# Derived: valid_design_names — depends on design_hierarchy above, so this
# line must come AFTER design_hierarchy is defined.
# ─────────────────────────────────────────────────────────────────────────────
# Generate valid design names from hierarchy
