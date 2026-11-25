#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Release Configuration
#
# Two sections:
#   1. INPUT RELEASE PATHS — Where to find RTL, SDC, UPF inputs (tag-based)
#   2. OUTPUT RELEASE FILES — Phase-wise (P0-P3) and stage-wise exit
#      (FP_EXIT, PLACE_EXIT, CTS_EXIT, PRO_EXIT, BTO, MTO) file expectations
#
# Usage: source config/flow/v1.0.0/release_config.tcl
# ═══════════════════════════════════════════════════════════════════════════════

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║               SECTION 1: INPUT RELEASE PATH CONFIGURATION                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

if {[info exists ::env(FLOW_DIR)]} {
    set project_root_resolved $::env(FLOW_DIR)
} elseif {[info exists ::env(CBFLOW_CORE_DIR)]} {
    set project_root_resolved $::env(CBFLOW_CORE_DIR)
} else {
    puts "ERROR: FLOW_DIR or CBFLOW_CORE_DIR not set."
}

set release(base_dir) [file join $project_root_resolved "test_releases"]

# Release-level files with a fixed name (written by the tool flow, published
# at the release root). timing_snapshot: worst setup/hold paths per clock
# (oss_timing_snapshot) — SmartGrid's timing debugger reads it.
set release(file,timing_snapshot) "timing_snapshot.json"

# Source canonical release-folder schema. Declares `canonical_folders`,
# `canonical_file_type(<ext>) <folder>`, and `discipline_folders(<DISC>)`
# — used by the static-check cat7 enforcement + available to any node_config
# that wants to look up "where should this .v file land?"
if {[info exists ::env(CBFLOW_GLOBAL_DIR)]} {
    set _canonical_schema "$::env(CBFLOW_GLOBAL_DIR)/config/flow/v1.0.0/canonical_release_schema.tcl"
    if {[file exists $_canonical_schema]} { source $_canonical_schema }
    unset -nocomplain _canonical_schema
}

# ┌─ Release Defaults ──────────────────────────────────────────────────────────┐
set flow(release_base_dir)    "releases"
set flow(release_default_tag) "latest"
set flow(release_structure)   {netlist sdc def gds reports scripts}

# ┌─ Release layout: markers + well-known files inside <block>/<FLOW>/<tag>/ ──┐
# Read by SmartGrid (global/utils/project_dashboard) via core.registry.
#   marker,manifest       release manifest (flow, user, timestamp)
#   marker,complete       written last — a tag dir without it is unfinished
#   file,changelog        optional changelog captured with the publish
#   file,metrics          "Key : value" metrics report ("# category: <c>" headers)
#   file,timing_snapshot  pre-built timing snapshot JSON (first match wins)
#   dir,images            routing / congestion images (IMAGE_<TAG> files)
#   dir,lef               the block's own LEFs (abstract) for the floorplan view
set release(marker,manifest)       "MANIFEST.json"
set release(marker,complete)       "RELEASE_COMPLETE"
set release(file,changelog)        "CHANGELOG.md"
set release(file,metrics)          "metrics.rpt"
set release(dir,images)            "images"
set release(dir,lef)               "lef"

# array set release_paths { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set release_paths(rtl) { "2024Q4_v2.0" "" "2024Q3_v1.8" "" "2024Q2_v1.5" "" }
    set release_paths(constraints) { "2024Q4_v2.0" "" "2024Q3_v1.8" "" "2024Q2_v1.5" "" }
    set release_paths(power) { "2024Q4_v2.0" "" "2024Q3_v1.8" "" "2024Q2_v1.5" "" }

foreach category [array names release_paths] {
    set tag_dict [dict create]
    dict for {tag _} $release_paths($category) {
        dict set tag_dict $tag [file join $release(base_dir) $category $tag]
    }
    set release_paths($category) $tag_dict
}

proc get_release_file_path {category tag design_name {mode ""}} {
    global release_paths
    if {![info exists release_paths($category)] || ![dict exists $release_paths($category) $tag]} {
        error "ERROR: Release tag '$tag' not found for category '$category'"
    }
    set release_dir [dict get $release_paths($category) $tag]
    switch $category {
        "rtl"         { set filename "${design_name}.f" }
        "constraints" { set filename "${design_name}.[expr {$mode ne {} ? $mode : {func}}].sdc" }
        "power"       { set filename "${design_name}.upf" }
        default       { error "ERROR: Unknown category '$category'" }
    }
    return [file join $release_dir $filename]
}

proc validate_release_tag {category tag} {
    global release_paths
    if {![info exists release_paths($category)]} { error "Unknown category '$category'" }
    if {![dict exists $release_paths($category) $tag]} { error "Tag '$tag' not found" }
    set release_dir [dict get $release_paths($category) $tag]
    if {![file exists $release_dir]} { error "Dir not found: $release_dir" }
    return true
}

proc get_available_release_tags {category} {
    global release_paths
    if {![info exists release_paths($category)]} { return {} }
    return [dict keys $release_paths($category)]
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          SECTION 2: DESIGN PHASES & STAGE EXIT DEFINITIONS                 ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║  Phases:                                                                   ║
# ║    P0 — Trial/Exploration (relaxed, partial deliverables)                  ║
# ║    P1 — Implementation (convergence, core deliverables)                    ║
# ║    P2 — Pre-Signoff (tight criteria, all deliverables)                     ║
# ║    P3 — Signoff/Tapeout (zero violations, full package)                    ║
# ║                                                                            ║
# ║  Stage Exits:                                                              ║
# ║    FP_EXIT    — After init_design / floorplan                              ║
# ║    PLACE_EXIT — After place                                                ║
# ║    CTS_EXIT   — After cts_opt                                              ║
# ║    PRO_EXIT   — After pro (post-route optimization)                        ║
# ║    BTO        — After signoff (PV+STA complete)                            ║
# ║    MTO        — After signoff (final delivery)                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ┌─ Milestone-to-Stage Mapping ────────────────────────────────────────────────┐
# Maps each milestone to the stage that must complete before exit
# array set MILESTONE_STAGE_MAPPING { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set MILESTONE_STAGE_MAPPING(FP_EXIT) "init_design"
    set MILESTONE_STAGE_MAPPING(PLACE_EXIT) "place"
    set MILESTONE_STAGE_MAPPING(CTS_EXIT) "cts_opt"
    set MILESTONE_STAGE_MAPPING(PRO_EXIT) "pro"
    set MILESTONE_STAGE_MAPPING(BTO) "signoff"
    set MILESTONE_STAGE_MAPPING(MTO) "signoff"

# ┌─ Milestone order ───────────────────────────────────────────────────────────┐
# Exits release in this order per (project, block, phase): a milestone is
# published only after every earlier one is on SmartGrid for that block/phase.
set MILESTONE_ORDER {FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO}

# ┌─ Tape-out milestones ───────────────────────────────────────────────────────┐
# No silent waivers / SKIPPED mandatory checks downgrade these to conditional
# (checklist sign-off). project(tape_out_milestones) extends the list.
set TAPEOUT_MILESTONES {BTO MTO}

# ── SYNTH_PNR Flow ────────────────────────────────────────────────────────────
# ── PNR Flow ─────────────────────────────────────────────────────────────────
# ── FP Flow ──────────────────────────────────────────────────────────────────
# ── FCFP Flow ────────────────────────────────────────────────────────────────
# ── SYNTH Flow ───────────────────────────────────────────────────────────────
# ── STA Flow ─────────────────────────────────────────────────────────────────
# ── LEC Flow ─────────────────────────────────────────────────────────────────
# ── CLP Flow ─────────────────────────────────────────────────────────────────
# ── PV Flow ──────────────────────────────────────────────────────────────────
# ── EMIR Flow ────────────────────────────────────────────────────────────────
# ── ECO Flow ─────────────────────────────────────────────────────────────────
# ── POPT Flow ────────────────────────────────────────────────────────────────

# array set release_exit_files { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).

    # ── SYNTH_PNR Flow ───────────────────────────────────────────────────────

    set release_exit_files(SYNTH_PNR,FP_EXIT,P0) {
        work/SYNTH_PNR/init_design1/reports/report_qor.rpt
        work/SYNTH_PNR/init_design1/reports/report_design.rpt
        work/SYNTH_PNR/init_design1/reports/report_utilization.rpt
    }
    set release_exit_files(SYNTH_PNR,FP_EXIT,P1) {
        work/SYNTH_PNR/init_design1/reports/report_qor.rpt
        work/SYNTH_PNR/init_design1/reports/report_design.rpt
        work/SYNTH_PNR/init_design1/reports/report_utilization.rpt
        work/SYNTH_PNR/init_design1/reports/check_timing.rpt
        work/SYNTH_PNR/init_design1/reports/report_clocks.rpt
    }
    set release_exit_files(SYNTH_PNR,FP_EXIT,P2) {
        work/SYNTH_PNR/init_design1/reports/report_qor.rpt
        work/SYNTH_PNR/init_design1/reports/report_design.rpt
        work/SYNTH_PNR/init_design1/reports/report_utilization.rpt
        work/SYNTH_PNR/init_design1/reports/check_timing.rpt
        work/SYNTH_PNR/init_design1/reports/report_clocks.rpt
        work/SYNTH_PNR/init_design1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(SYNTH_PNR,FP_EXIT,P3) {
        work/SYNTH_PNR/init_design1/reports/report_qor.rpt
        work/SYNTH_PNR/init_design1/reports/report_design.rpt
        work/SYNTH_PNR/init_design1/reports/report_utilization.rpt
        work/SYNTH_PNR/init_design1/reports/check_timing.rpt
        work/SYNTH_PNR/init_design1/reports/report_clocks.rpt
        work/SYNTH_PNR/init_design1/reports/report_threshold_voltage_group.rpt
        work/SYNTH_PNR/init_design1/reports/signoff_check_drc.rpt
    }

    set release_exit_files(SYNTH_PNR,PLACE_EXIT,P0) {
        work/SYNTH_PNR/place1/reports/report_qor.rpt
        work/SYNTH_PNR/place1/reports/report_timing.max.rpt
        work/SYNTH_PNR/place1/reports/report_congestion.rpt
    }
    set release_exit_files(SYNTH_PNR,PLACE_EXIT,P1) {
        work/SYNTH_PNR/place1/reports/report_qor.rpt
        work/SYNTH_PNR/place1/reports/report_timing.max.rpt
        work/SYNTH_PNR/place1/reports/report_timing.min.rpt
        work/SYNTH_PNR/place1/reports/report_congestion.rpt
        work/SYNTH_PNR/place1/reports/report_power.rpt
        work/SYNTH_PNR/place1/reports/check_legality.rpt
    }
    set release_exit_files(SYNTH_PNR,PLACE_EXIT,P2) {
        work/SYNTH_PNR/place1/reports/report_qor.rpt
        work/SYNTH_PNR/place1/reports/report_qor_summary.rpt
        work/SYNTH_PNR/place1/reports/report_timing.max.rpt
        work/SYNTH_PNR/place1/reports/report_timing.min.rpt
        work/SYNTH_PNR/place1/reports/report_congestion.rpt
        work/SYNTH_PNR/place1/reports/report_power.rpt
        work/SYNTH_PNR/place1/reports/report_si.rpt
        work/SYNTH_PNR/place1/reports/report_utilization.rpt
        work/SYNTH_PNR/place1/reports/check_legality.rpt
        work/SYNTH_PNR/place1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(SYNTH_PNR,PLACE_EXIT,P3) {
        work/SYNTH_PNR/place1/reports/report_qor.rpt
        work/SYNTH_PNR/place1/reports/report_qor_summary.rpt
        work/SYNTH_PNR/place1/reports/report_timing.max.rpt
        work/SYNTH_PNR/place1/reports/report_timing.min.rpt
        work/SYNTH_PNR/place1/reports/report_congestion.rpt
        work/SYNTH_PNR/place1/reports/report_power.rpt
        work/SYNTH_PNR/place1/reports/report_si.rpt
        work/SYNTH_PNR/place1/reports/report_utilization.rpt
        work/SYNTH_PNR/place1/reports/check_legality.rpt
        work/SYNTH_PNR/place1/reports/check_timing.rpt
        work/SYNTH_PNR/place1/reports/report_threshold_voltage_group.rpt
        work/SYNTH_PNR/place1/reports/signoff_check_drc.rpt
    }

    set release_exit_files(SYNTH_PNR,CTS_EXIT,P0) {
        work/SYNTH_PNR/cts1/reports/report_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt
    }
    set release_exit_files(SYNTH_PNR,CTS_EXIT,P1) {
        work/SYNTH_PNR/cts1/reports/report_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_timing.setup.rpt
        work/SYNTH_PNR/cts1/reports/report_timing.max.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_timing.max.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_timing.min.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_power.rpt
    }
    set release_exit_files(SYNTH_PNR,CTS_EXIT,P2) {
        work/SYNTH_PNR/cts1/reports/report_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_timing.setup.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_timing.skew.rpt
        work/SYNTH_PNR/cts1/reports/report_timing.max.rpt
        work/SYNTH_PNR/cts1/reports/report_timing.min.rpt
        work/SYNTH_PNR/cts1/reports/report_power.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_timing.max.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_timing.min.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_power.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(SYNTH_PNR,CTS_EXIT,P3) {
        work/SYNTH_PNR/cts1/reports/report_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_timing.setup.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_timing.skew.rpt
        work/SYNTH_PNR/cts1/reports/report_timing.max.rpt
        work/SYNTH_PNR/cts1/reports/report_timing.min.rpt
        work/SYNTH_PNR/cts1/reports/report_power.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_timing.max.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_timing.min.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_power.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_threshold_voltage_group.rpt
        work/SYNTH_PNR/cts_opt1/reports/check_timing.rpt
        work/SYNTH_PNR/cts_opt1/reports/check_legality.rpt
        work/SYNTH_PNR/cts_opt1/reports/signoff_check_drc.rpt
    }

    set release_exit_files(SYNTH_PNR,PRO_EXIT,P0) {
        work/SYNTH_PNR/pro1/reports/report_qor.rpt
        work/SYNTH_PNR/pro1/reports/report_timing.max.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(SYNTH_PNR,PRO_EXIT,P1) {
        work/SYNTH_PNR/pro1/reports/report_qor.rpt
        work/SYNTH_PNR/pro1/reports/report_timing.max.rpt
        work/SYNTH_PNR/pro1/reports/report_timing.min.rpt
        work/SYNTH_PNR/pro1/reports/report_power.rpt
        work/SYNTH_PNR/pro1/reports/report_congestion.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(SYNTH_PNR,PRO_EXIT,P2) {
        work/SYNTH_PNR/pro1/reports/report_qor.rpt
        work/SYNTH_PNR/pro1/reports/report_qor_summary.rpt
        work/SYNTH_PNR/pro1/reports/report_timing.max.rpt
        work/SYNTH_PNR/pro1/reports/report_timing.min.rpt
        work/SYNTH_PNR/pro1/reports/report_power.rpt
        work/SYNTH_PNR/pro1/reports/report_congestion.rpt
        work/SYNTH_PNR/pro1/reports/report_si.rpt
        work/SYNTH_PNR/pro1/reports/report_threshold_voltage_group.rpt
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(SYNTH_PNR,PRO_EXIT,P3) {
        work/SYNTH_PNR/pro1/reports/report_qor.rpt
        work/SYNTH_PNR/pro1/reports/report_qor_summary.rpt
        work/SYNTH_PNR/pro1/reports/report_timing.max.rpt
        work/SYNTH_PNR/pro1/reports/report_timing.min.rpt
        work/SYNTH_PNR/pro1/reports/report_power.rpt
        work/SYNTH_PNR/pro1/reports/report_congestion.rpt
        work/SYNTH_PNR/pro1/reports/report_si.rpt
        work/SYNTH_PNR/pro1/reports/report_threshold_voltage_group.rpt
        work/SYNTH_PNR/pro1/reports/check_timing.rpt
        work/SYNTH_PNR/pro1/reports/check_legality.rpt
        work/SYNTH_PNR/pro1/reports/check_routes.final
        work/SYNTH_PNR/pro1/reports/signoff_check_drc.rpt
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.lvs.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }

    set release_exit_files(SYNTH_PNR,BTO,P0) {
        work/SYNTH_PNR/signoff1/reports/report_qor.rpt
        work/SYNTH_PNR/signoff1/reports/report_timing.max.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(SYNTH_PNR,BTO,P1) {
        work/SYNTH_PNR/signoff1/reports/report_qor.rpt
        work/SYNTH_PNR/signoff1/reports/report_timing.max.rpt
        work/SYNTH_PNR/signoff1/reports/report_timing.min.rpt
        work/SYNTH_PNR/signoff1/reports/report_power.rpt
        work/SYNTH_PNR/signoff1/reports/report_congestion.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(SYNTH_PNR,BTO,P2) {
        work/SYNTH_PNR/signoff1/reports/report_qor.rpt
        work/SYNTH_PNR/signoff1/reports/report_timing.max.rpt
        work/SYNTH_PNR/signoff1/reports/report_timing.min.rpt
        work/SYNTH_PNR/signoff1/reports/report_power.rpt
        work/SYNTH_PNR/signoff1/reports/report_si.rpt
        work/SYNTH_PNR/signoff1/reports/report_threshold_voltage_group.rpt
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(SYNTH_PNR,BTO,P3) {
        work/SYNTH_PNR/signoff1/reports/report_qor.rpt
        work/SYNTH_PNR/signoff1/reports/report_timing.max.rpt
        work/SYNTH_PNR/signoff1/reports/report_timing.min.rpt
        work/SYNTH_PNR/signoff1/reports/report_power.rpt
        work/SYNTH_PNR/signoff1/reports/report_si.rpt
        work/SYNTH_PNR/signoff1/reports/report_threshold_voltage_group.rpt
        work/SYNTH_PNR/signoff1/reports/check_timing.rpt
        work/SYNTH_PNR/signoff1/reports/check_legality.rpt
        work/SYNTH_PNR/signoff1/reports/check_routes.final
        work/SYNTH_PNR/signoff1/reports/signoff_check_drc.rpt
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.lvs.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }

    set release_exit_files(SYNTH_PNR,MTO,P0) {
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(SYNTH_PNR,MTO,P1) {
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
        outputs/${design_name}.upf
    }
    set release_exit_files(SYNTH_PNR,MTO,P2) {
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
        outputs/${design_name}.upf
        outputs/${design_name}.saif.ptpx.map
        outputs/${design_name}_floorplan
        outputs/${design_name}_wscript
        outputs/${design_name}_wscript_for_pt
    }
    set release_exit_files(SYNTH_PNR,MTO,P3) {
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.lvs.v
        outputs/${design_name}.vc_lp.v
        outputs/${design_name}.dc.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
        outputs/${design_name}.upf
        outputs/${design_name}.saif.ptpx.map
        outputs/${design_name}_floorplan
        outputs/${design_name}_wscript
        outputs/${design_name}_wscript_for_pt
        outputs/${design_name}_routing_constraints
    }

    # ── PNR Flow ─────────────────────────────────────────────────────────────

    set release_exit_files(PNR,FP_EXIT,P0) {
        work/PNR/init_design1/reports/report_qor.rpt
        work/PNR/init_design1/reports/report_design.rpt
        work/PNR/init_design1/reports/report_utilization.rpt
    }
    set release_exit_files(PNR,FP_EXIT,P1) {
        work/PNR/init_design1/reports/report_qor.rpt
        work/PNR/init_design1/reports/report_design.rpt
        work/PNR/init_design1/reports/report_utilization.rpt
        work/PNR/init_design1/reports/check_timing.rpt
        work/PNR/init_design1/reports/report_clocks.rpt
    }
    set release_exit_files(PNR,FP_EXIT,P2) {
        work/PNR/init_design1/reports/report_qor.rpt
        work/PNR/init_design1/reports/report_design.rpt
        work/PNR/init_design1/reports/report_utilization.rpt
        work/PNR/init_design1/reports/check_timing.rpt
        work/PNR/init_design1/reports/report_clocks.rpt
        work/PNR/init_design1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(PNR,FP_EXIT,P3) {
        work/PNR/init_design1/reports/report_qor.rpt
        work/PNR/init_design1/reports/report_design.rpt
        work/PNR/init_design1/reports/report_utilization.rpt
        work/PNR/init_design1/reports/check_timing.rpt
        work/PNR/init_design1/reports/report_clocks.rpt
        work/PNR/init_design1/reports/report_threshold_voltage_group.rpt
        work/PNR/init_design1/reports/signoff_check_drc.rpt
    }

    set release_exit_files(PNR,PLACE_EXIT,P0) {
        work/PNR/place1/reports/report_qor.rpt
        work/PNR/place1/reports/report_timing.max.rpt
        work/PNR/place1/reports/report_congestion.rpt
    }
    set release_exit_files(PNR,PLACE_EXIT,P1) {
        work/PNR/place1/reports/report_qor.rpt
        work/PNR/place1/reports/report_timing.max.rpt
        work/PNR/place1/reports/report_timing.min.rpt
        work/PNR/place1/reports/report_congestion.rpt
        work/PNR/place1/reports/report_power.rpt
        work/PNR/place1/reports/check_legality.rpt
    }
    set release_exit_files(PNR,PLACE_EXIT,P2) {
        work/PNR/place1/reports/report_qor.rpt
        work/PNR/place1/reports/report_qor_summary.rpt
        work/PNR/place1/reports/report_timing.max.rpt
        work/PNR/place1/reports/report_timing.min.rpt
        work/PNR/place1/reports/report_congestion.rpt
        work/PNR/place1/reports/report_power.rpt
        work/PNR/place1/reports/report_si.rpt
        work/PNR/place1/reports/report_utilization.rpt
        work/PNR/place1/reports/check_legality.rpt
        work/PNR/place1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(PNR,PLACE_EXIT,P3) {
        work/PNR/place1/reports/report_qor.rpt
        work/PNR/place1/reports/report_qor_summary.rpt
        work/PNR/place1/reports/report_timing.max.rpt
        work/PNR/place1/reports/report_timing.min.rpt
        work/PNR/place1/reports/report_congestion.rpt
        work/PNR/place1/reports/report_power.rpt
        work/PNR/place1/reports/report_si.rpt
        work/PNR/place1/reports/report_utilization.rpt
        work/PNR/place1/reports/check_legality.rpt
        work/PNR/place1/reports/check_timing.rpt
        work/PNR/place1/reports/report_threshold_voltage_group.rpt
        work/PNR/place1/reports/signoff_check_drc.rpt
    }

    set release_exit_files(PNR,CTS_EXIT,P0) {
        work/PNR/cts1/reports/report_qor.rpt
        work/PNR/cts1/reports/report_clock_qor.rpt
        work/PNR/cts_opt1/reports/report_qor.rpt
    }
    set release_exit_files(PNR,CTS_EXIT,P1) {
        work/PNR/cts1/reports/report_qor.rpt
        work/PNR/cts1/reports/report_clock_qor.rpt
        work/PNR/cts1/reports/report_clock_timing.setup.rpt
        work/PNR/cts1/reports/report_timing.max.rpt
        work/PNR/cts_opt1/reports/report_qor.rpt
        work/PNR/cts_opt1/reports/report_timing.max.rpt
        work/PNR/cts_opt1/reports/report_timing.min.rpt
        work/PNR/cts_opt1/reports/report_power.rpt
    }
    set release_exit_files(PNR,CTS_EXIT,P2) {
        work/PNR/cts1/reports/report_qor.rpt
        work/PNR/cts1/reports/report_clock_qor.rpt
        work/PNR/cts1/reports/report_clock_timing.setup.rpt
        work/PNR/cts1/reports/report_clock_timing.skew.rpt
        work/PNR/cts1/reports/report_timing.max.rpt
        work/PNR/cts1/reports/report_timing.min.rpt
        work/PNR/cts1/reports/report_power.rpt
        work/PNR/cts_opt1/reports/report_qor.rpt
        work/PNR/cts_opt1/reports/report_timing.max.rpt
        work/PNR/cts_opt1/reports/report_timing.min.rpt
        work/PNR/cts_opt1/reports/report_power.rpt
        work/PNR/cts_opt1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(PNR,CTS_EXIT,P3) {
        work/PNR/cts1/reports/report_qor.rpt
        work/PNR/cts1/reports/report_clock_qor.rpt
        work/PNR/cts1/reports/report_clock_timing.setup.rpt
        work/PNR/cts1/reports/report_clock_timing.skew.rpt
        work/PNR/cts1/reports/report_timing.max.rpt
        work/PNR/cts1/reports/report_timing.min.rpt
        work/PNR/cts1/reports/report_power.rpt
        work/PNR/cts_opt1/reports/report_qor.rpt
        work/PNR/cts_opt1/reports/report_timing.max.rpt
        work/PNR/cts_opt1/reports/report_timing.min.rpt
        work/PNR/cts_opt1/reports/report_power.rpt
        work/PNR/cts_opt1/reports/report_threshold_voltage_group.rpt
        work/PNR/cts_opt1/reports/check_timing.rpt
        work/PNR/cts_opt1/reports/check_legality.rpt
        work/PNR/cts_opt1/reports/signoff_check_drc.rpt
    }

    set release_exit_files(PNR,PRO_EXIT,P0) {
        work/PNR/pro1/reports/report_qor.rpt
        work/PNR/pro1/reports/report_timing.max.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(PNR,PRO_EXIT,P1) {
        work/PNR/pro1/reports/report_qor.rpt
        work/PNR/pro1/reports/report_timing.max.rpt
        work/PNR/pro1/reports/report_timing.min.rpt
        work/PNR/pro1/reports/report_power.rpt
        work/PNR/pro1/reports/report_congestion.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(PNR,PRO_EXIT,P2) {
        work/PNR/pro1/reports/report_qor.rpt
        work/PNR/pro1/reports/report_qor_summary.rpt
        work/PNR/pro1/reports/report_timing.max.rpt
        work/PNR/pro1/reports/report_timing.min.rpt
        work/PNR/pro1/reports/report_power.rpt
        work/PNR/pro1/reports/report_congestion.rpt
        work/PNR/pro1/reports/report_si.rpt
        work/PNR/pro1/reports/report_threshold_voltage_group.rpt
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(PNR,PRO_EXIT,P3) {
        work/PNR/pro1/reports/report_qor.rpt
        work/PNR/pro1/reports/report_qor_summary.rpt
        work/PNR/pro1/reports/report_timing.max.rpt
        work/PNR/pro1/reports/report_timing.min.rpt
        work/PNR/pro1/reports/report_power.rpt
        work/PNR/pro1/reports/report_congestion.rpt
        work/PNR/pro1/reports/report_si.rpt
        work/PNR/pro1/reports/report_threshold_voltage_group.rpt
        work/PNR/pro1/reports/check_timing.rpt
        work/PNR/pro1/reports/check_legality.rpt
        work/PNR/pro1/reports/check_routes.final
        work/PNR/pro1/reports/signoff_check_drc.rpt
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.lvs.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }

    set release_exit_files(PNR,BTO,P0) {
        work/PNR/signoff1/reports/report_qor.rpt
        work/PNR/signoff1/reports/report_timing.max.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(PNR,BTO,P1) {
        work/PNR/signoff1/reports/report_qor.rpt
        work/PNR/signoff1/reports/report_timing.max.rpt
        work/PNR/signoff1/reports/report_timing.min.rpt
        work/PNR/signoff1/reports/report_power.rpt
        work/PNR/signoff1/reports/report_congestion.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(PNR,BTO,P2) {
        work/PNR/signoff1/reports/report_qor.rpt
        work/PNR/signoff1/reports/report_timing.max.rpt
        work/PNR/signoff1/reports/report_timing.min.rpt
        work/PNR/signoff1/reports/report_power.rpt
        work/PNR/signoff1/reports/report_si.rpt
        work/PNR/signoff1/reports/report_threshold_voltage_group.rpt
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(PNR,BTO,P3) {
        work/PNR/signoff1/reports/report_qor.rpt
        work/PNR/signoff1/reports/report_timing.max.rpt
        work/PNR/signoff1/reports/report_timing.min.rpt
        work/PNR/signoff1/reports/report_power.rpt
        work/PNR/signoff1/reports/report_si.rpt
        work/PNR/signoff1/reports/report_threshold_voltage_group.rpt
        work/PNR/signoff1/reports/check_timing.rpt
        work/PNR/signoff1/reports/check_legality.rpt
        work/PNR/signoff1/reports/check_routes.final
        work/PNR/signoff1/reports/signoff_check_drc.rpt
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.lvs.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }

    set release_exit_files(PNR,MTO,P0) {
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    set release_exit_files(PNR,MTO,P1) {
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
        outputs/${design_name}.upf
    }
    set release_exit_files(PNR,MTO,P2) {
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
        outputs/${design_name}.upf
        outputs/${design_name}_floorplan
        outputs/${design_name}_wscript
        outputs/${design_name}_wscript_for_pt
    }
    set release_exit_files(PNR,MTO,P3) {
        outputs/${design_name}.v
        outputs/${design_name}.pt.v
        outputs/${design_name}.fm.v
        outputs/${design_name}.lvs.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
        outputs/${design_name}.upf
        outputs/${design_name}_floorplan
        outputs/${design_name}_wscript
        outputs/${design_name}_wscript_for_pt
        outputs/${design_name}_routing_constraints
    }

    # ── FP Flow ──────────────────────────────────────────────────────────────

    set release_exit_files(FP,FP_EXIT,P0) {
        work/FP/floorplan1/reports/report_design.rpt
        work/FP/floorplan1/reports/report_utilization.rpt
    }
    set release_exit_files(FP,FP_EXIT,P1) {
        work/FP/floorplan1/reports/report_design.rpt
        work/FP/floorplan1/reports/report_utilization.rpt
        work/FP/init_design1/reports/check_timing.rpt
        work/FP/post_floorplan1/reports/report_qor.rpt
        work/FP/post_floorplan1/reports/report_timing.max.rpt
        work/FP/post_floorplan1/reports/report_power.rpt
        work/FP/post_floorplan1/reports/report_congestion.rpt
    }
    set release_exit_files(FP,FP_EXIT,P2) {
        work/FP/floorplan1/reports/report_design.rpt
        work/FP/floorplan1/reports/report_utilization.rpt
        work/FP/init_design1/reports/check_timing.rpt
        work/FP/post_floorplan1/reports/report_qor.rpt
        work/FP/post_floorplan1/reports/report_timing.max.rpt
        work/FP/post_floorplan1/reports/report_timing.min.rpt
        work/FP/post_floorplan1/reports/report_power.rpt
        work/FP/post_floorplan1/reports/report_threshold_voltage_group.rpt
        outputs/${design_name}.def
    }
    set release_exit_files(FP,FP_EXIT,P3) {
        work/FP/floorplan1/reports/report_design.rpt
        work/FP/floorplan1/reports/report_utilization.rpt
        work/FP/init_design1/reports/check_timing.rpt
        work/FP/post_floorplan1/reports/report_qor.rpt
        work/FP/post_floorplan1/reports/report_timing.max.rpt
        work/FP/post_floorplan1/reports/report_timing.min.rpt
        work/FP/post_floorplan1/reports/report_power.rpt
        work/FP/post_floorplan1/reports/report_threshold_voltage_group.rpt
        work/FP/post_floorplan1/reports/check_timing.rpt
        work/FP/post_floorplan1/reports/check_legality.rpt
        work/FP/post_floorplan1/reports/signoff_check_drc.rpt
        outputs/${design_name}.def
    }

    # ── FCFP Flow ────────────────────────────────────────────────────────────

    set release_exit_files(FCFP,FP_EXIT,P0) {
        work/FCFP/create_floorplan1/reports/report_design.rpt
        work/FCFP/placement1/reports/report_qor.rpt
    }
    set release_exit_files(FCFP,FP_EXIT,P1) {
        work/FCFP/create_floorplan1/reports/report_design.rpt
        work/FCFP/placement1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_timing.max.rpt
        work/FCFP/timing_budget1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_power.rpt
        work/FCFP/placement1/reports/report_congestion.rpt
    }
    set release_exit_files(FCFP,FP_EXIT,P2) {
        work/FCFP/create_floorplan1/reports/report_design.rpt
        work/FCFP/placement1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_timing.max.rpt
        work/FCFP/placement1/reports/report_timing.min.rpt
        work/FCFP/timing_budget1/reports/report_qor.rpt
        work/FCFP/top_compile1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_threshold_voltage_group.rpt
        outputs/${design_name}.def
    }
    set release_exit_files(FCFP,FP_EXIT,P3) {
        work/FCFP/create_floorplan1/reports/report_design.rpt
        work/FCFP/placement1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_timing.max.rpt
        work/FCFP/placement1/reports/report_timing.min.rpt
        work/FCFP/timing_budget1/reports/report_qor.rpt
        work/FCFP/top_compile1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_threshold_voltage_group.rpt
        work/FCFP/top_compile1/reports/check_timing.rpt
        work/FCFP/top_compile1/reports/check_legality.rpt
        work/FCFP/top_compile1/reports/signoff_check_drc.rpt
        outputs/${design_name}.def
    }

    # ── SYNTH Flow ───────────────────────────────────────────────────────────

    set release_exit_files(SYNTH,P0) {
        work/SYNTH/synthesis1/reports/report_qor.rpt
        outputs/netlist/${design_name}.v
    }
    set release_exit_files(SYNTH,P1) {
        work/SYNTH/synthesis1/reports/report_qor.rpt
        work/SYNTH/synthesis1/reports/report_timing.max.rpt
        work/SYNTH/synthesis1/reports/report_timing.min.rpt
        work/SYNTH/synthesis1/reports/report_power.rpt
        outputs/netlist/${design_name}.v
        outputs/sdc/${design_name}.sdc
    }
    set release_exit_files(SYNTH,P2) {
        work/SYNTH/synthesis1/reports/report_qor.rpt
        work/SYNTH/synthesis1/reports/report_timing.max.rpt
        work/SYNTH/synthesis1/reports/report_timing.min.rpt
        work/SYNTH/synthesis1/reports/report_power.rpt
        work/SYNTH/synthesis1/reports/report_threshold_voltage_group.rpt
        outputs/netlist/${design_name}.v
        outputs/sdc/${design_name}.sdc
        outputs/${design_name}_compile.svf
    }
    set release_exit_files(SYNTH,P3) {
        work/SYNTH/synthesis1/reports/report_qor.rpt
        work/SYNTH/synthesis1/reports/report_timing.max.rpt
        work/SYNTH/synthesis1/reports/report_timing.min.rpt
        work/SYNTH/synthesis1/reports/report_power.rpt
        work/SYNTH/synthesis1/reports/report_threshold_voltage_group.rpt
        work/SYNTH/synthesis1/reports/check_timing.rpt
        outputs/netlist/${design_name}.v
        outputs/sdc/${design_name}.sdc
        outputs/${design_name}_compile.svf
    }

    # ── STA Flow ─────────────────────────────────────────────────────────────

    set release_exit_files(STA,P0) {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
    }
    set release_exit_files(STA,P1) {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_congestion.rpt
    }
    set release_exit_files(STA,P2) {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(STA,P3) {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
        work/STA/timing1/reports/check_timing.rpt
    }
    set release_exit_files(STA,BTO,P2) {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(STA,BTO,P3) {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
        work/STA/timing1/reports/check_timing.rpt
    }
    set release_exit_files(STA,MTO,P2) {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
    }
    set release_exit_files(STA,MTO,P3) {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
        work/STA/timing1/reports/check_timing.rpt
    }

    # ── LEC Flow ─────────────────────────────────────────────────────────────

    set release_exit_files(LEC,P0) {
        work/LEC/compare1/reports/comparison_summary.rpt
    }
    set release_exit_files(LEC,P1) {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
    }
    set release_exit_files(LEC,P2) {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
    }
    set release_exit_files(LEC,P3) {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
        work/LEC/analyze1/reports/failing_points.rpt
    }
    set release_exit_files(LEC,BTO,P2) {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
    }
    set release_exit_files(LEC,BTO,P3) {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
        work/LEC/analyze1/reports/failing_points.rpt
    }
    set release_exit_files(LEC,MTO,P2) {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
    }
    set release_exit_files(LEC,MTO,P3) {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
        work/LEC/analyze1/reports/failing_points.rpt
    }

    # ── CLP Flow ─────────────────────────────────────────────────────────────

    set release_exit_files(CLP,P0) {
        work/CLP/clp1/reports/power_verification_summary.rpt
    }
    set release_exit_files(CLP,P1) {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
    }
    set release_exit_files(CLP,P2) {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
    }
    set release_exit_files(CLP,P3) {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
        work/CLP/clp1/reports/power_domain_check.rpt
    }
    set release_exit_files(CLP,BTO,P2) {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
    }
    set release_exit_files(CLP,BTO,P3) {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
        work/CLP/clp1/reports/power_domain_check.rpt
    }
    set release_exit_files(CLP,MTO,P2) {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
    }
    set release_exit_files(CLP,MTO,P3) {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
        work/CLP/clp1/reports/power_domain_check.rpt
    }

    # ── PV Flow ──────────────────────────────────────────────────────────────

    # PV stages current as of 2026-07-10: nettran1, merge_gds1, fill_merge_gds1,
    # decomp1, decomp_merge_gds1, drc1, lvs1, perc1, perc_ldl1, xor1, merge_data1
    # (fill1 + erc1 removed; new stages produce fill_merge_gds_summary.rpt,
    # perc_ldl_summary.rpt, decomp_merge_gds_summary.rpt).
    set release_exit_files(PV,P0) {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
    }
    # PV,P1: DRC + LVS + netlist-prep + electrical-rule check. perc1 replaces
    # the deleted erc1 stage as the electrical gate — dropping it entirely
    # (as the fill1/erc1 removal did) would let a design pass P1 sign-off
    # without any electrical rule verification (latch-up, ESD path, voltage).
    set release_exit_files(PV,P1) {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/nettran1/reports/nettran_summary.rpt
        work/PV/perc1/reports/perc_results.rpt
    }
    set release_exit_files(PV,P2) {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/nettran1/reports/nettran_summary.rpt
        work/PV/perc1/reports/perc_results.rpt
        work/PV/fill_merge_gds1/reports/fill_merge_gds_summary.rpt
    }
    set release_exit_files(PV,P3) {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/nettran1/reports/nettran_summary.rpt
        work/PV/perc1/reports/perc_results.rpt
        work/PV/perc_ldl1/reports/perc_ldl_summary.rpt
        work/PV/xor1/reports/xor_summary.rpt
        work/PV/fill_merge_gds1/reports/fill_merge_gds_summary.rpt
        work/PV/decomp_merge_gds1/reports/decomp_merge_gds_summary.rpt
        work/PV/merge_data1/reports/merge_summary.rpt
    }
    set release_exit_files(PV,BTO,P2) {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/nettran1/reports/nettran_summary.rpt
        work/PV/perc1/reports/perc_results.rpt
        work/PV/fill_merge_gds1/reports/fill_merge_gds_summary.rpt
    }
    set release_exit_files(PV,BTO,P3) {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/nettran1/reports/nettran_summary.rpt
        work/PV/perc1/reports/perc_results.rpt
        work/PV/perc_ldl1/reports/perc_ldl_summary.rpt
        work/PV/xor1/reports/xor_summary.rpt
        work/PV/fill_merge_gds1/reports/fill_merge_gds_summary.rpt
        work/PV/decomp_merge_gds1/reports/decomp_merge_gds_summary.rpt
        work/PV/merge_data1/reports/merge_summary.rpt
    }
    set release_exit_files(PV,MTO,P2) {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/nettran1/reports/nettran_summary.rpt
        work/PV/perc1/reports/perc_results.rpt
        work/PV/fill_merge_gds1/reports/fill_merge_gds_summary.rpt
    }
    set release_exit_files(PV,MTO,P3) {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/nettran1/reports/nettran_summary.rpt
        work/PV/perc1/reports/perc_results.rpt
        work/PV/perc_ldl1/reports/perc_ldl_summary.rpt
        work/PV/xor1/reports/xor_summary.rpt
        work/PV/fill_merge_gds1/reports/fill_merge_gds_summary.rpt
        work/PV/decomp_merge_gds1/reports/decomp_merge_gds_summary.rpt
        work/PV/merge_data1/reports/merge_summary.rpt
    }

    # ── EMIR Flow ────────────────────────────────────────────────────────────

    set release_exit_files(EMIR,P0) {
        work/EMIR/power_analysis1/reports/power_summary.rpt
    }
    set release_exit_files(EMIR,P1) {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
    }
    set release_exit_files(EMIR,P2) {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
    }
    set release_exit_files(EMIR,P3) {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_map.rpt
    }
    set release_exit_files(EMIR,BTO,P2) {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
    }
    set release_exit_files(EMIR,BTO,P3) {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_map.rpt
    }
    set release_exit_files(EMIR,MTO,P2) {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
    }
    set release_exit_files(EMIR,MTO,P3) {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_map.rpt
    }

    # ── ECO Flow ─────────────────────────────────────────────────────────────

    set release_exit_files(ECO,P0) {
        work/ECO/eco1/reports/report_qor.rpt
    }
    set release_exit_files(ECO,P1) {
        work/ECO/eco1/reports/report_qor.rpt
        work/ECO/eco1/reports/report_timing.max.rpt
    }
    set release_exit_files(ECO,P2) {
        work/ECO/eco1/reports/report_qor.rpt
        work/ECO/eco1/reports/report_timing.max.rpt
        work/ECO/eco1/reports/report_timing.min.rpt
        work/ECO/eco1/reports/report_power.rpt
    }
    set release_exit_files(ECO,P3) {
        work/ECO/eco1/reports/report_qor.rpt
        work/ECO/eco1/reports/report_timing.max.rpt
        work/ECO/eco1/reports/report_timing.min.rpt
        work/ECO/eco1/reports/report_power.rpt
        work/ECO/eco1/reports/check_timing.rpt
        outputs/eco/${design_name}.eco.v
    }

    # ── POPT Flow ────────────────────────────────────────────────────────────

    set release_exit_files(POPT,P0) {
        work/POPT/power_opt1/reports/post_opt_power_summary.rpt
    }
    set release_exit_files(POPT,P1) {
        work/POPT/power_opt1/reports/pre_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_power_summary.rpt
        work/POPT/merge_timing1/reports/merged_qor.rpt
    }
    set release_exit_files(POPT,P2) {
        work/POPT/power_opt1/reports/pre_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_timing.rpt
        work/POPT/merge_timing1/reports/merged_qor.rpt
        work/POPT/post_merge1/reports/post_merge_qor.rpt
        work/POPT/post_merge1/reports/post_merge_power.rpt
    }
    set release_exit_files(POPT,P3) {
        work/POPT/power_opt1/reports/pre_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_timing.rpt
        work/POPT/merge_timing1/reports/merged_qor.rpt
        work/POPT/post_merge1/reports/post_merge_qor.rpt
        work/POPT/post_merge1/reports/post_merge_power.rpt
        work/POPT/post_merge1/reports/post_merge_timing.rpt
    }

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          SECTION 3: CROSS-FLOW MILESTONE MAPPING                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Maps each milestone to required flows that must complete for sign-off
# array set milestone_flow_map { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set milestone_flow_map(FP_EXIT) {SYNTH_PNR PNR FP FCFP PV}
    set milestone_flow_map(PLACE_EXIT) {SYNTH_PNR PNR SYNTH}
    set milestone_flow_map(CTS_EXIT) {SYNTH_PNR PNR SYNTH}
    set milestone_flow_map(PRO_EXIT) {SYNTH_PNR PNR SYNTH STA LEC}
    set milestone_flow_map(BTO) {SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO}
    set milestone_flow_map(MTO) {SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO POPT}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          SECTION 4: PHASE CRITERIA THRESHOLDS                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set phase_criteria { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set phase_criteria(FP_EXIT,P0,setup_wns) "-500"
    set phase_criteria(FP_EXIT,P0,utilization_min) "0.50"
    set phase_criteria(FP_EXIT,P1,setup_wns) "-200"
    set phase_criteria(FP_EXIT,P1,utilization_min) "0.60"
    set phase_criteria(FP_EXIT,P2,setup_wns) "-50"
    set phase_criteria(FP_EXIT,P2,utilization_min) "0.65"

    set phase_criteria(PLACE_EXIT,P0,setup_wns) "-200"
    set phase_criteria(PLACE_EXIT,P0,setup_tns) "-5000"
    set phase_criteria(PLACE_EXIT,P0,hold_wns) "-500"
    set phase_criteria(PLACE_EXIT,P1,setup_wns) "-80"
    set phase_criteria(PLACE_EXIT,P1,setup_tns) "-800"
    set phase_criteria(PLACE_EXIT,P1,hold_wns) "-200"
    set phase_criteria(PLACE_EXIT,P2,setup_wns) "-20"
    set phase_criteria(PLACE_EXIT,P2,setup_tns) "-100"
    set phase_criteria(PLACE_EXIT,P2,hold_wns) "-50"

    set phase_criteria(CTS_EXIT,P0,setup_wns) "-150"
    set phase_criteria(CTS_EXIT,P0,hold_wns) "-100"
    set phase_criteria(CTS_EXIT,P0,max_skew) "0.200"
    set phase_criteria(CTS_EXIT,P1,setup_wns) "-50"
    set phase_criteria(CTS_EXIT,P1,hold_wns) "-30"
    set phase_criteria(CTS_EXIT,P1,max_skew) "0.100"
    set phase_criteria(CTS_EXIT,P2,setup_wns) "-10"
    set phase_criteria(CTS_EXIT,P2,hold_wns) "-5"
    set phase_criteria(CTS_EXIT,P2,max_skew) "0.050"

    set phase_criteria(PRO_EXIT,P0,setup_wns) "-50"
    set phase_criteria(PRO_EXIT,P0,hold_wns) "-20"
    set phase_criteria(PRO_EXIT,P0,drc_count) "100"
    set phase_criteria(PRO_EXIT,P1,setup_wns) "-10"
    set phase_criteria(PRO_EXIT,P1,hold_wns) "-5"
    set phase_criteria(PRO_EXIT,P1,drc_count) "10"
    set phase_criteria(PRO_EXIT,P2,setup_wns) "0"
    set phase_criteria(PRO_EXIT,P2,hold_wns) "0"
    set phase_criteria(PRO_EXIT,P2,drc_count) "0"

    set phase_criteria(BTO,P2,setup_wns) "0"
    set phase_criteria(BTO,P2,hold_wns) "0"
    set phase_criteria(BTO,P2,drc_count) "0"
    set phase_criteria(BTO,P2,lvs_match) "true"
    set phase_criteria(BTO,P3,setup_wns) "0"
    set phase_criteria(BTO,P3,hold_wns) "0"
    set phase_criteria(BTO,P3,drc_count) "0"
    set phase_criteria(BTO,P3,lvs_match) "true"
    set phase_criteria(BTO,P3,antenna_violations) "0"
    set phase_criteria(BTO,P3,em_violations) "0"

    set phase_criteria(MTO,P3,setup_wns) "0"
    set phase_criteria(MTO,P3,hold_wns) "0"
    set phase_criteria(MTO,P3,drc_count) "0"
    set phase_criteria(MTO,P3,lvs_match) "true"
    set phase_criteria(MTO,P3,gds_errors) "0"

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          SECTION 5: HELPER PROCEDURES                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

proc get_release_exit_files {flow milestone phase} {
    global release_exit_files
    # Try flow,milestone,phase (stage exit)
    set key "${flow},${milestone},${phase}"
    if {[info exists release_exit_files($key)]} { return $release_exit_files($key) }
    # Try flow,phase (non-stage-exit flows like SYNTH, LEC, CLP)
    set key "${flow},${phase}"
    if {[info exists release_exit_files($key)]} { return $release_exit_files($key) }
    return {}
}

proc get_phase_criteria {milestone phase} {
    global phase_criteria
    set result {}
    foreach key [array names phase_criteria "${milestone},${phase},*"] {
        set metric [lindex [split $key ","] 2]
        lappend result $metric $phase_criteria($key)
    }
    return $result
}

proc get_milestone_flows {milestone} {
    global milestone_flow_map
    if {[info exists milestone_flow_map($milestone)]} { return $milestone_flow_map($milestone) }
    return {}
}

proc check_release_readiness {run_dir flow milestone phase} {
    set files [get_release_exit_files $flow $milestone $phase]
    set missing {}
    foreach f $files {
        set full_path [file join $run_dir $f]
        if {![file exists $full_path]} { lappend missing $f }
    }
    set total [llength $files]
    set present [expr {$total - [llength $missing]}]
    return [list total $total present $present missing $missing]
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          SECTION 6: FLOW INPUT HANDSHAKE MAP                               ║
# ╠══════════════════════════════════════════════════════════════════════════════╣
# ║  Maps each downstream flow's input types to the upstream release layout.   ║
# ║                                                                            ║
# ║  USER-FACING UX — three patterns:                                          ║
# ║                                                                            ║
# ║  Pattern A — one knob, auto-resolves every required input:                 ║
# ║      set sta(input,release_tag) "P1_PNR_v1"                                ║
# ║                                                                            ║
# ║  Pattern B — per-input tag selection (mix sources across tags):            ║
# ║      set sta(input,release_tag)     "P1_PNR_v1"   ;# baseline              ║
# ║      set sta(input,sdc_release_tag) "P1_STA_v2"   ;# override SDC only     ║
# ║                                                                            ║
# ║  Pattern C — explicit path override (wins over any tag):                   ║
# ║      set sta(input,release_tag) "P1_PNR_v1"                                ║
# ║      set sta(input,netlist)     "/my/custom/foo.v"                         ║
# ║                                                                            ║
# ║  PRIORITY: explicit path > per-input release_tag > generic release_tag.    ║
# ║                                                                            ║
# ║  Each handshake value is {source_flow category filename_pattern}.          ║
# ║  `source_flow` is metadata only (used in error messages). ANY = artifact   ║
# ║  can come from any upstream that stages it in the canonical category;     ║
# ║  specific names (RTL_LINT, UPF_CHECK, DFT_INSERT_PASS3) are used when the ║
# ║  artifact is unique to one upstream.                                      ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Handshake map: downstream_flow → input_type → {source_flow category filename}
# filename uses ${design_name} which is resolved at runtime.
# `set` per key (not `array set`) so `#` comments inside the block are safe
# (Tcl treats `#` as data inside `array set` literals).

    # ── Pre-impl (SYNTH / SYNTH_PNR) — consume raw RTL from the inputs tree ─
    set flow_input_handshake(SYNTH_PNR,rtl)      {INPUTS rtl "${design_name}.f"}
    set flow_input_handshake(SYNTH_PNR,sdc)      {INPUTS sdc "${design_name}.sdc"}
    set flow_input_handshake(SYNTH_PNR,upf_file) {INPUTS upf "${design_name}.upf"}

    set flow_input_handshake(SYNTH,rtl)          {INPUTS rtl "${design_name}.f"}
    set flow_input_handshake(SYNTH,sdc)          {INPUTS sdc "${design_name}.sdc"}
    set flow_input_handshake(SYNTH,upf_file)     {INPUTS upf "${design_name}.upf"}

    # ── Impl (FP / FCFP / PNR) — pull synth artifacts ───────────────────────
    set flow_input_handshake(FP,netlist)         {SYNTH   netlist "${design_name}.v"}
    set flow_input_handshake(FP,sdc)             {SYNTH   sdc     "${design_name}.sdc"}
    set flow_input_handshake(FP,upf_file)        {SYNTH   upf     "${design_name}.upf"}

    set flow_input_handshake(FCFP,netlist)       {SYNTH   netlist "${design_name}.v"}
    set flow_input_handshake(FCFP,sdc)           {SYNTH   sdc     "${design_name}.sdc"}
    set flow_input_handshake(FCFP,upf_file)      {SYNTH   upf     "${design_name}.upf"}

    set flow_input_handshake(PNR,netlist)        {SYNTH   netlist "${design_name}.v"}
    set flow_input_handshake(PNR,sdc)            {SYNTH   sdc     "${design_name}.sdc"}
    set flow_input_handshake(PNR,upf_file)       {SYNTH   upf     "${design_name}.upf"}
    # DFT (project(dft,enable)): the scandef SYNTH wrote with the scan netlist —
    # mandatory for PNR when DFT is on; staged with the def inputs (def1)
    set flow_input_handshake(PNR,def_scan)       {SYNTH def     "${design_name}.scandef"}
    set flow_input_handshake(PNR,def_file)       {ANY     def     "${design_name}.def"}
    set flow_input_handshake(PNR,fp_tcl)         {FP      data    "floorplan.tcl"}

    # ── Downstream of impl (STA / PV / LEC / CLP / EMIR / ECO / POPT) ───────
    # All of these can be fed by EITHER PNR or SYNTH_PNR release tags (both
    # stage the same canonical filenames per PNR_config.tcl /
    # SYNTH_PNR_config.tcl). source_flow = ANY — the resolver doesn't care
    # which upstream produced the tag, it reads the tag's canonical tree.
    set flow_input_handshake(STA,netlist)        {ANY netlist "${design_name}.pt.v"}
    set flow_input_handshake(STA,def_file)       {ANY def     "${design_name}.def"}
    set flow_input_handshake(STA,spef)           {ANY spef    "${design_name}.spef"}
    # Mode-independent SDC (the per-mode STA,sdc,<mode> entries below need
    # operating_modes, which the input stage does not load).
    set flow_input_handshake(STA,sdc)            {ANY sdc     "${design_name}.sdc"}

    set flow_input_handshake(PV,gds)             {ANY gds     "${design_name}.gds"}
    set flow_input_handshake(PV,netlist)         {ANY netlist "${design_name}.lvs.v"}
    # CDL of the layout PV checks — re-released with the GDS by PV (the views
    # a parent's lib tag takes); absent in a floorplan release (warning only)
    set flow_input_handshake(PV,netlist_cdl)     {ANY netlist "${design_name}.cdl"}
    set flow_input_handshake(PV,def_file)        {ANY def     "${design_name}.def"}

    set flow_input_handshake(LEC,netlist_golden)  {SYNTH netlist "${design_name}.v"}
    set flow_input_handshake(LEC,netlist_revised) {ANY   netlist "${design_name}.v"}

    set flow_input_handshake(CLP,netlist)        {ANY netlist "${design_name}.v"}
    set flow_input_handshake(CLP,upf_file)       {ANY upf     "${design_name}.upf"}

    set flow_input_handshake(EMIR,def_file)      {ANY def     "${design_name}.def"}
    set flow_input_handshake(EMIR,netlist)       {ANY netlist "${design_name}.v"}
    set flow_input_handshake(EMIR,spef)          {ANY spef    "${design_name}.spef"}
    set flow_input_handshake(EMIR,gds)           {ANY gds     "${design_name}.gds"}

    set flow_input_handshake(ECO,netlist)        {ANY netlist "${design_name}.v"}
    set flow_input_handshake(ECO,def_file)       {ANY def     "${design_name}.def"}
    # Open-source ECO (eco(tool,name) openroad): the routed database + SDC of
    # a PNR release, or of an earlier ECO release (<EXIT>_ECO<n>)
    set flow_input_handshake(ECO,odb)            {ANY db      "${design_name}.odb"}
    set flow_input_handshake(ECO,sdc)            {ANY sdc     "${design_name}.sdc"}

    set flow_input_handshake(POPT,netlist)       {ANY netlist "${design_name}.pt.v"}
    set flow_input_handshake(POPT,spef)          {ANY spef    "${design_name}.spef"}
    set flow_input_handshake(POPT,sdc)           {ANY sdc     "${design_name}.sdc"}

    # ── Cross-discipline handoff — source_flow is SPECIFIC ──────────────────
    # These artifacts are semantically produced by ONE upstream only, so the
    # error message names it when resolution fails.
    #   RTL_LINT   → provides clean (lint-signed-off) RTL for SYNTH
    #   UPF_CHECK  → provides validated UPF for PNR + CLP
    #   DFT_INSERT_PASS3 → provides DFT-inserted netlist for SYNTH/PNR resynth
    set flow_input_handshake(SYNTH,rtl_from_lint)       {RTL_LINT         netlist "${design_name}.v"}
    set flow_input_handshake(PNR,upf_from_check)        {UPF_CHECK        upf     "${design_name}.upf"}
    set flow_input_handshake(CLP,upf_from_check)        {UPF_CHECK        upf     "${design_name}.upf"}
    set flow_input_handshake(SYNTH,dft_netlist)         {DFT_INSERT_PASS3 netlist "${design_name}.edt_occ.v"}
    set flow_input_handshake(PNR,dft_netlist)           {DFT_INSERT_PASS3 netlist "${design_name}.edt_occ.v"}

    # ── DFT (open-source: SCAN_INSERT / ATPG -> fault, GLS_* -> iverilog) ───
    #   SYNTH       → scan-inserted netlist + scan-shift SDC for SCAN_INSERT
    #   SCAN_INSERT → checked scan netlist + scandef / chain map for ATPG
    #   ANY         → the netlist ATPG / GLS run on (SCAN_INSERT pre-PD, PNR post-PD)
    #   ATPG        → the serial-scan pattern testbench for GLS_SCAN_MBIST
    set flow_input_handshake(SCAN_INSERT,netlist)       {SYNTH       netlist  "${design_name}.v"}
    set flow_input_handshake(SCAN_INSERT,sdc)           {SYNTH       sdc      "${design_name}.scan.sdc"}
    set flow_input_handshake(SCAN_INSERT,scandef)       {SYNTH       def      "${design_name}.scandef"}
    set flow_input_handshake(ATPG,netlist)              {ANY         netlist  "${design_name}.v"}
    set flow_input_handshake(ATPG,scandef)              {SCAN_INSERT def      "${design_name}.scandef"}
    set flow_input_handshake(GLS_FUNC,netlist)          {ANY         netlist  "${design_name}.v"}
    set flow_input_handshake(GLS_SCAN_MBIST,netlist)    {ANY         netlist  "${design_name}.v"}
    set flow_input_handshake(GLS_SCAN_MBIST,patterns)   {ATPG        patterns "${design_name}_scan_tb.v"}

    # ── Spec-to-GDS front end (open-source RTL) ─────────────────────────────
    #   RTL_SPEC → the RTL filelist (generated register block + designer RTL,
    #   at the released paths), SDC, UPF and spec the RTL checks read
    set flow_input_handshake(RTL_LINT,rtl)              {RTL_SPEC    rtl      "${design_name}.f"}
    set flow_input_handshake(RTL_CDC,rtl)               {RTL_SPEC    rtl      "${design_name}.f"}
    set flow_input_handshake(RTL_CDC,sdc)               {RTL_SPEC    sdc      "${design_name}.sdc"}
    set flow_input_handshake(UPF_CHECK,rtl)             {RTL_SPEC    rtl      "${design_name}.f"}
    set flow_input_handshake(UPF_CHECK,upf)             {RTL_SPEC    upf      "${design_name}.upf"}
    set flow_input_handshake(UPF_CHECK,spec)            {RTL_SPEC    spec     "${design_name}.spec.yaml"}

    # ── Spec / RTL → DV (open-source UVM flows) ─────────────────────────────
    #   TB_SETUP builds the UVM testbench from the spec + register model and the
    #   RTL (the lint-clean RTL_LINT release, or the RTL_SPEC one); the
    #   milestone regressions (M1–M4_EXEC) read the TB_SETUP release.
    set flow_input_handshake(TB_SETUP,spec)             {RTL_SPEC    spec     "${design_name}.spec.yaml"}
    set flow_input_handshake(TB_SETUP,ral)              {RTL_SPEC    ral      "${design_name}_ral.sv"}
    set flow_input_handshake(TB_SETUP,vplan)            {RTL_SPEC    spec     "${design_name}_vplan.xlsx"}
    set flow_input_handshake(TB_SETUP,rtl)              {ANY         rtl      "${design_name}.f"}
    foreach _m {M1_EXEC M2_EXEC M3_EXEC M4_EXEC} {
        set flow_input_handshake($_m,tb)                [list TB_SETUP tb  "tb.f"]
        set flow_input_handshake($_m,vplan)             [list TB_SETUP spec {${design_name}_vplan.xlsx}]
    }
    unset _m
    set flow_input_handshake(DV_SIGNOFF,metrics)        {M4_EXEC     reports  "metrics.json"}

    # ── PD → DV handoff ─────────────────────────────────────────────────────
    set flow_input_handshake(DV_SIGNOFF,netlist)        {ANY netlist "${design_name}.v"}

# Auto-generate STA per-mode SDC handshake entries from operating_modes
if {[array exists operating_modes]} {
    foreach _mode [array names operating_modes] {
        set _sdc_file [dict get $operating_modes($_mode) constraint_file]
        set flow_input_handshake(STA,sdc,$_mode) [list ANY sdc $_sdc_file]
    }
}

# Helper: get handshake info for a flow/input combination
proc get_input_handshake {flow input_type} {
    global flow_input_handshake
    set key "${flow},${input_type}"
    if {[info exists flow_input_handshake($key)]} {
        return $flow_input_handshake($key)
    }
    return {}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                    SECTION 6: PREDEFINED RELEASE TAGS                      ║
# ║  Tags are defined here — leads set active_tag + expiry in project config   ║
# ║  Release is milestone-gated: ALL required flows must PASS before release   ║
# ║  Which exits each phase has is project-defined: project(phase_exits) in    ║
# ║  global/config/project/<proj>/v1.0.0/<proj>_config.tcl.                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set release_tags { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set release_tags(FP_EXIT) {description "Floorplan Exit"    required_flows {SYNTH_PNR PNR FP FCFP PV}}
    set release_tags(PLACE_EXIT) {description "Placement Exit"    required_flows {SYNTH_PNR PNR SYNTH}}
    set release_tags(CTS_EXIT) {description "CTS Exit"          required_flows {SYNTH_PNR PNR SYNTH}}
    set release_tags(PRO_EXIT) {description "Post-Route Exit"   required_flows {SYNTH_PNR PNR SYNTH STA LEC}}
    set release_tags(BTO) {description "Backend Tapeout"   required_flows {SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO}}
    set release_tags(MTO) {description "Metal Tapeout"      required_flows {SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO POPT}}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                 SECTION 7: PER-FLOW RELEASE DELIVERABLES                   ║
# ║  Maps each flow to file suffixes that export_data produces                 ║
# ║  Used by release command to know what to copy per flow                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# array set release_deliverables { … } expanded to per-key `set` statements so `#` comments work natively (Tcl treats `#` as data inside `array set` literals).
    set release_deliverables(SYNTH_PNR,netlist) {.v .pt.v .fm.v .lvs.v .vc_lp.v .dc.v}
    set release_deliverables(SYNTH_PNR,gds) {.gds}
    set release_deliverables(SYNTH_PNR,def) {.def}
    set release_deliverables(SYNTH_PNR,lef) {.lef}
    set release_deliverables(SYNTH_PNR,sdc) {.sdc}
    set release_deliverables(SYNTH_PNR,spef) {.spef}
    set release_deliverables(SYNTH_PNR,upf) {.upf}
    set release_deliverables(SYNTH_PNR,data) {_wscript _wscript_for_pt _routing_constraints _floorplan .saif.ptpx.map .saif.fc.map}
    set release_deliverables(PNR,netlist) {.v .pt.v .fm.v .lvs.v}
    set release_deliverables(PNR,gds) {.gds}
    set release_deliverables(PNR,def) {.def}
    set release_deliverables(PNR,sdc) {.sdc}
    set release_deliverables(PNR,spef) {.spef}
    set release_deliverables(PNR,upf) {.upf}
    set release_deliverables(PNR,data) {_wscript _wscript_for_pt _routing_constraints _floorplan}
    set release_deliverables(SYNTH,netlist) {.v}
    set release_deliverables(SYNTH,sdc) {.sdc}
    set release_deliverables(STA,reports) {timing_summary.rpt mmmc_timing_summary.rpt}
    set release_deliverables(LEC,reports) {comparison_summary.rpt}
    set release_deliverables(CLP,reports) {power_verification_summary.rpt}
    set release_deliverables(PV,reports) {drc_summary.rpt lvs_summary.rpt perc_results.rpt perc_ldl_summary.rpt}
    set release_deliverables(EMIR,reports) {power_summary.rpt ir_drop_summary.rpt}
    # FP / FCFP / ECO / POPT are release_tags required_flows. `cbflow run release`
    # previously classified their files with a hardcoded extension map in
    # run_cmd.py — the same map, declared here:
    set release_deliverables(FP,netlist) {.v}
    set release_deliverables(FP,gds) {.gds .oasis}
    set release_deliverables(FP,def) {.def}
    set release_deliverables(FP,spef) {.spef}
    set release_deliverables(FP,sdc) {.sdc}
    set release_deliverables(FP,upf) {.upf}
    set release_deliverables(FP,reports) {.rpt}
    set release_deliverables(FCFP,netlist) {.v}
    set release_deliverables(FCFP,gds) {.gds .oasis}
    set release_deliverables(FCFP,def) {.def}
    set release_deliverables(FCFP,spef) {.spef}
    set release_deliverables(FCFP,sdc) {.sdc}
    set release_deliverables(FCFP,upf) {.upf}
    set release_deliverables(FCFP,reports) {.rpt}
    set release_deliverables(ECO,netlist) {.v}
    set release_deliverables(ECO,gds) {.gds .oasis}
    set release_deliverables(ECO,def) {.def}
    set release_deliverables(ECO,spef) {.spef}
    set release_deliverables(ECO,sdc) {.sdc}
    set release_deliverables(ECO,upf) {.upf}
    set release_deliverables(ECO,reports) {.rpt}
    set release_deliverables(POPT,netlist) {.v}
    set release_deliverables(POPT,gds) {.gds .oasis}
    set release_deliverables(POPT,def) {.def}
    set release_deliverables(POPT,spef) {.spef}
    set release_deliverables(POPT,sdc) {.sdc}
    set release_deliverables(POPT,upf) {.upf}
    set release_deliverables(POPT,reports) {.rpt}

# ── Cadence STA / LEC report contracts (fork C) ──────────────────────────────
# Report file names the Tempus / Conformal release_data stages copy into the
# release. Previously literal lists inside release_data_tempus.tcl and
# release_data_conformal.tcl; values below are those literals unchanged.
#   STA,summaries          — cross-scenario summaries in reports/sta/
#   STA,scenario_reports   — per-scenario report patterns (%s = scenario)
#   LEC,compare_reports    — compare-node reports copied to the release
#   LEC,status_markers     — PASS/FAIL marker files from the compare node
#   LEC,mandatory          — files that must be present for a valid release
    set release_deliverables(STA,summaries)        {mmmc_setup_summary.rpt mmmc_hold_summary.rpt mmmc_timing_summary.rpt}
    set release_deliverables(STA,scenario_reports) {setup_timing_%s.rpt hold_timing_%s.rpt}
    set release_deliverables(LEC,compare_reports)  {comparison_summary.rpt equivalence_analysis.rpt failing_points.rpt status.rpt}
    set release_deliverables(LEC,status_markers)   {PASSED FAILED}
    set release_deliverables(LEC,mandatory)        {comparison_summary.rpt}
#   CLP,required           — files release_data_conformal_lp.tcl requires in
#                            the release dir (was a literal list; the
#                            db/clp_verification.db entry was dropped — no
#                            CLP stage writes it)
    set release_deliverables(CLP,required)         {reports/clp_verification.rpt}
#   SYNTH,genus_files      — {src dest_subdir dest_name}; src is relative to
#                            $OUTPUTS_DIR, %s = design name. Producers:
#                            synthesis_genus.tcl (<design>.v/.sdc) and
#                            export_data_genus.tcl (db/synth.db). Replaces the
#                            literal results/... + chip_top.v tree in
#                            release_data_genus.tcl; categories match the
#                            SYNTH entries of flow_input_handshake.
#   SYNTH,genus_required   — release-relative files checked after the copy
    set release_deliverables(SYNTH,genus_files) {
        {db/synth.db db      synth.db}
        {%s.v        netlist %s.v}
        {%s.sdc      sdc     %s.sdc}
    }
    set release_deliverables(SYNTH,genus_required) {db/synth.db netlist/%s.v}

# ── Cadence Innovus PNR release contract (fork A) ────────────────────────────
# What release_data_innovus.tcl copies into the release. Sources are the
# files export_data_innovus.tcl / signoff_innovus.tcl actually write (the old
# script read results/pnr/<cat>/ and reports/pnr/ paths no stage produced,
# and a literal SPEF corner list {max min nom}).
#   %t = project(top_module) (export file stem), %d = release design name
#   PNR,innovus_files           — {category  run-dir-relative source  release name}
#   PNR,innovus_globs           — {category  run-dir-relative glob}; the per-
#                                 MMMC-scenario SPEFs export_timing_data writes
#                                 (one per active scenario / RC corner)
#   PNR,innovus_signoff_reports — {release subdir  report} from the upstream
#                                 signoff node's reports/ dir
    set release_deliverables(PNR,innovus_files) {
        gds     results/export/layout/gds/%t.gds            %d.gds
        netlist results/export/netlist/verilog/%t_final.v   %d.v
        def     results/export/layout/def/%t_full.def       %d.def
        sdc     results/export/timing/sdc/%t_final.sdc      %d.sdc
        spef    results/export/timing/spef/%t_full.spef     %d.spef
        upf     results/export/power/upf/%t_final.upf       %d.upf
    }
    set release_deliverables(PNR,innovus_globs) {
        spef    results/export/timing/mmmc/*.spef
    }
    set release_deliverables(PNR,innovus_signoff_reports) {
        reports/timing  report_timing.signoff.max.rpt
        reports/timing  report_timing.signoff.min.rpt
        reports/power   report_power.signoff.rpt
        reports/drc     signoff_drc.rpt
        reports/drc     verify_drc.rpt
        reports/drc     signoff_lvs.rpt
        reports/qor     qor_summary.rpt
    }

puts "INFO: Release configuration loaded — [array size release_exit_files] exit files, [array size release_tags] tags, [array size release_deliverables] deliverables"
