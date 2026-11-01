#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — bumblebee
# DV OVERLAY (design verification side: workarea, release, DV tooling)
#
# Sourced after global/config/project/<proj>/project_config.tcl, in parallel
# with PD/config/project/<proj>/project_pd_config.tcl. Keys are additive on
# project(...) — a DV-only sparse-checkout clone needs this file to resolve
# workarea_path + release,path (both of which also live in the PD overlay).
#
# Keep this overlay narrow — only the cross-domain operator-facing keys that
# a DV engineer actually needs to run DV flows end-to-end. PD-specific keys
# (lib_root, lsf,*, default_tools PNR/STA/..., validation waivers) live
# exclusively in project_pd_config.tcl.
# =============================================================================

if {[info exists ::env(PROJECT_ROOT)]} {
    set ROOT_DIR $::env(PROJECT_ROOT)
} elseif {[info exists cbflow(root)]} {
    set ROOT_DIR [file dirname $cbflow(root)]
} else {
    set ROOT_DIR [file dirname [file dirname [file dirname [file dirname [file normalize [info script]]]]]]
}
set project(root_dir) $ROOT_DIR

# Workarea path — all DV runs created under workarea_path/<design_name>/.
# `cbflow workspace create` enforces this. In a DV-only clone the PD
# overlay isn't on disk, so this is the authoritative setting.
set project(workarea_path) "/Users/vmerugu/projects/CBflow_clone/workarea"

# RACE DB — DV runs write status/metrics here too. Keep in sync with the
# PD overlay so a dashboard pointed at this area sees both disciplines'
# databases.
set project(race,db_path) "/Users/vmerugu/projects/CBflow_clone/.race_area"

# Release Path Configuration — DV deliverables (coverage reports, lint
# clean waivers, formal signoff artifacts) land under the same release
# tree as PD so the per-phase release manifest covers both.
set project(release,path) "/Users/vmerugu/projects/CBflow_clone/test_releases"
set project(release,phase) "LC1"
set project(release,block_name) ""
set project(release,active_tag) "DV_SIGNOFF"
set project(release,expiry_date) "2027-06-30"

# Dashboard — operator-facing byline (same string as PD overlay so the
# brand is consistent regardless of which discipline's daemon the user
# is pointed at).
set project(dashboard,developed_by) "SmartSoC CAD · Varun Reddy Merugu"
