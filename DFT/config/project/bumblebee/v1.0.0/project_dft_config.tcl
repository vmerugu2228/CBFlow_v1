#!/usr/bin/env tclsh
# =============================================================================
# CBflow Project Configuration — bumblebee
# DFT OVERLAY (design-for-test side: workarea, release, DFT tooling)
#
# Sourced after global/config/project/<proj>/project_config.tcl, in parallel
# with PD/config/project/<proj>/project_pd_config.tcl. Keys are additive on
# project(...) — a DFT-only sparse-checkout clone needs this file to resolve
# workarea_path + release,path (both of which also live in the PD overlay).
#
# Keep this overlay narrow — only the cross-domain operator-facing keys that
# a DFT engineer actually needs. PD-specific keys (lib_root, lsf,*,
# default_tools PNR/STA/..., validation waivers) live exclusively in
# project_pd_config.tcl.
# =============================================================================

if {[info exists ::env(PROJECT_ROOT)]} {
    set ROOT_DIR $::env(PROJECT_ROOT)
} elseif {[info exists cbflow(root)]} {
    set ROOT_DIR [file dirname $cbflow(root)]
} else {
    set ROOT_DIR [file dirname [file dirname [file dirname [file dirname [file normalize [info script]]]]]]
}
set project(root_dir) $ROOT_DIR

set project(workarea_path) "/Users/vmerugu/projects/CBflow_clone/workarea"

set project(race,db_path) "/Users/vmerugu/projects/CBflow_clone/.race_area"

set project(release,path) "/Users/vmerugu/projects/CBflow_clone/test_releases"
set project(release,phase) "LC1"
set project(release,block_name) ""
set project(release,active_tag) "DFT_INSERT"
set project(release,expiry_date) "2027-06-30"

set project(dashboard,developed_by) "SmartSoC CAD · Varun Reddy Merugu"
