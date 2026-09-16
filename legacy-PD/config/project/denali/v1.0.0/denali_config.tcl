#!/usr/bin/env tclsh
# ============================================================================
# CBflow - Denali Project Configuration
# Description: Denali project-specific parameters
# ============================================================================

# Project identification
set project(name) "denali"

# Phase timeline for this project (project-specific — flow(phases) is deprecated).
set project(phases)          {P0 P1 P2 P3}
set project(current_phase)   "P0"
set project(version) "1.0"
set project(cbflow_release) "v1.0.0"   ;# CBflow release version for this project
set project(description) "Denali chip design project"
set project(owner) "Denali Design Team"
set project(contact) "denali@smartsoc.com"

;# Project root directory for relative path resolution
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
set project(technology) "gf_28nm"
set project(track_variant) "9T"
set project(metal_stack) "10M"
set project(vt_flavors) "rvt lvt hvt"
set project(lib_config_tag) "LIB02"
set project(lib_root) "/proj/libs/gf_28nm"

;# Design hierarchy
set project(top_module) "denali_top"

;
;# SDC Mode Definitions (used for file naming: <design_name>.<mode>.sdc)
set project(sdc_modes) {func scan test}
set project(default_sdc_mode) "func"

;# Power & Ground Nets (consumed by init_design/PNR — top-level SoC-wide)
set project(power,vdd_net) "VDD"
set project(power,vss_net) "VSS"
set project(power,vdd_pin) "VDD"
set project(power,vss_pin) "VSS"

;# Block-level specs (clock uncertainty, target frequency/power/area, reset
# ports, I/O voltage, power domains, design-size estimates) used to live
# here as `project(target,*)`, `project(estimated_*)`, `project(io,*)`,
# `project(reset,*)`, `project(power,domains|states|switches|isolation|
# retention)`. They were unread by any cmd handler and removed in the
# cleanup commit. Block-shaped specs belong in user_config or a per-block
# `<block_name>_floorplan.tcl`, not in this project-wide config.

# Test and verification
set project(dft,scan_chains) "4"
set project(dft,coverage_target) "98"
set project(dft,compression) "true"
set project(verification,formal) "true"
set project(verification,simulation) "true"

;# Feature toggles
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
set project(tapeout_date) "2026-09-30"          ;# ISO date — drives "Weeks to tapeout" on dashboard

;
;# ---------------------------------------------------------------------------
# LSF RESOURCE MANAGEMENT
# ---------------------------------------------------------------------------

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
set project(analog_blocks) ""        ;# Analog block list (project-specific; empty if none)
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
set project(design_hierarchy) {
    denali_top                    {
    description                   "Full chip top level (DL1)"
    level                         "DL1"
    parent                        ""
    children                      {tom}
    }                             tom
    {                             description
    "TOM processing block (DL2)"  level
    "DL2"                         parent
    "denali_top"                  children
    {}                            }
}

# Default Cadence tools
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
set project(valid_design_names) [dict keys $project(design_hierarchy)]

# ─────────────────────────────────────────────────────────────────────────────
# Derived: project(block_list) — the DL2 subsystems of design_hierarchy.
# Consumed by FCFP/FP init_design_fc.tcl for hierarchical NDM loading.
# ─────────────────────────────────────────────────────────────────────────────
set _blk_list {}
dict for {_blk _spec} $project(design_hierarchy) {
    if {[dict exists $_spec level] && [dict get $_spec level] eq "DL2"} {
        lappend _blk_list $_blk
    }
}
set project(block_list) $_blk_list
unset _blk_list _blk _spec
