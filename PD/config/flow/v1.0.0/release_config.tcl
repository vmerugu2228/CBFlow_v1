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

# ┌─ Release Defaults ──────────────────────────────────────────────────────────┐
set flow(release_base_dir)    "releases"
set flow(release_default_tag) "latest"
set flow(release_structure)   {netlist sdc def gds reports scripts}

array set release_paths {
    rtl         { "2024Q4_v2.0" "" "2024Q3_v1.8" "" "2024Q2_v1.5" "" }
    constraints { "2024Q4_v2.0" "" "2024Q3_v1.8" "" "2024Q2_v1.5" "" }
    power       { "2024Q4_v2.0" "" "2024Q3_v1.8" "" "2024Q2_v1.5" "" }
}

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
array set MILESTONE_STAGE_MAPPING {
    FP_EXIT    "init_design"
    PLACE_EXIT "place"
    CTS_EXIT   "cts_opt"
    PRO_EXIT   "pro"
    BTO        "signoff"
    MTO        "signoff"
}

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

array set release_exit_files {

    # ── SYNTH_PNR Flow ───────────────────────────────────────────────────────

    SYNTH_PNR,FP_EXIT,P0 {
        work/SYNTH_PNR/init_design1/reports/report_qor.rpt
        work/SYNTH_PNR/init_design1/reports/report_design.rpt
        work/SYNTH_PNR/init_design1/reports/report_utilization.rpt
    }
    SYNTH_PNR,FP_EXIT,P1 {
        work/SYNTH_PNR/init_design1/reports/report_qor.rpt
        work/SYNTH_PNR/init_design1/reports/report_design.rpt
        work/SYNTH_PNR/init_design1/reports/report_utilization.rpt
        work/SYNTH_PNR/init_design1/reports/check_timing.rpt
        work/SYNTH_PNR/init_design1/reports/report_clocks.rpt
    }
    SYNTH_PNR,FP_EXIT,P2 {
        work/SYNTH_PNR/init_design1/reports/report_qor.rpt
        work/SYNTH_PNR/init_design1/reports/report_design.rpt
        work/SYNTH_PNR/init_design1/reports/report_utilization.rpt
        work/SYNTH_PNR/init_design1/reports/check_timing.rpt
        work/SYNTH_PNR/init_design1/reports/report_clocks.rpt
        work/SYNTH_PNR/init_design1/reports/report_threshold_voltage_group.rpt
    }
    SYNTH_PNR,FP_EXIT,P3 {
        work/SYNTH_PNR/init_design1/reports/report_qor.rpt
        work/SYNTH_PNR/init_design1/reports/report_design.rpt
        work/SYNTH_PNR/init_design1/reports/report_utilization.rpt
        work/SYNTH_PNR/init_design1/reports/check_timing.rpt
        work/SYNTH_PNR/init_design1/reports/report_clocks.rpt
        work/SYNTH_PNR/init_design1/reports/report_threshold_voltage_group.rpt
        work/SYNTH_PNR/init_design1/reports/signoff_check_drc.rpt
    }

    SYNTH_PNR,PLACE_EXIT,P0 {
        work/SYNTH_PNR/place1/reports/report_qor.rpt
        work/SYNTH_PNR/place1/reports/report_timing.max.rpt
        work/SYNTH_PNR/place1/reports/report_congestion.rpt
    }
    SYNTH_PNR,PLACE_EXIT,P1 {
        work/SYNTH_PNR/place1/reports/report_qor.rpt
        work/SYNTH_PNR/place1/reports/report_timing.max.rpt
        work/SYNTH_PNR/place1/reports/report_timing.min.rpt
        work/SYNTH_PNR/place1/reports/report_congestion.rpt
        work/SYNTH_PNR/place1/reports/report_power.rpt
        work/SYNTH_PNR/place1/reports/check_legality.rpt
    }
    SYNTH_PNR,PLACE_EXIT,P2 {
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
    SYNTH_PNR,PLACE_EXIT,P3 {
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

    SYNTH_PNR,CTS_EXIT,P0 {
        work/SYNTH_PNR/cts1/reports/report_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt
    }
    SYNTH_PNR,CTS_EXIT,P1 {
        work/SYNTH_PNR/cts1/reports/report_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_qor.rpt
        work/SYNTH_PNR/cts1/reports/report_clock_timing.setup.rpt
        work/SYNTH_PNR/cts1/reports/report_timing.max.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_qor.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_timing.max.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_timing.min.rpt
        work/SYNTH_PNR/cts_opt1/reports/report_power.rpt
    }
    SYNTH_PNR,CTS_EXIT,P2 {
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
    SYNTH_PNR,CTS_EXIT,P3 {
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

    SYNTH_PNR,PRO_EXIT,P0 {
        work/SYNTH_PNR/pro1/reports/report_qor.rpt
        work/SYNTH_PNR/pro1/reports/report_timing.max.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    SYNTH_PNR,PRO_EXIT,P1 {
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
    SYNTH_PNR,PRO_EXIT,P2 {
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
    SYNTH_PNR,PRO_EXIT,P3 {
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

    SYNTH_PNR,BTO,P0 {
        work/SYNTH_PNR/signoff1/reports/report_qor.rpt
        work/SYNTH_PNR/signoff1/reports/report_timing.max.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    SYNTH_PNR,BTO,P1 {
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
    SYNTH_PNR,BTO,P2 {
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
    SYNTH_PNR,BTO,P3 {
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

    SYNTH_PNR,MTO,P0 {
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    SYNTH_PNR,MTO,P1 {
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
        outputs/${design_name}.upf
    }
    SYNTH_PNR,MTO,P2 {
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
    SYNTH_PNR,MTO,P3 {
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

    PNR,FP_EXIT,P0 {
        work/PNR/init_design1/reports/report_qor.rpt
        work/PNR/init_design1/reports/report_design.rpt
        work/PNR/init_design1/reports/report_utilization.rpt
    }
    PNR,FP_EXIT,P1 {
        work/PNR/init_design1/reports/report_qor.rpt
        work/PNR/init_design1/reports/report_design.rpt
        work/PNR/init_design1/reports/report_utilization.rpt
        work/PNR/init_design1/reports/check_timing.rpt
        work/PNR/init_design1/reports/report_clocks.rpt
    }
    PNR,FP_EXIT,P2 {
        work/PNR/init_design1/reports/report_qor.rpt
        work/PNR/init_design1/reports/report_design.rpt
        work/PNR/init_design1/reports/report_utilization.rpt
        work/PNR/init_design1/reports/check_timing.rpt
        work/PNR/init_design1/reports/report_clocks.rpt
        work/PNR/init_design1/reports/report_threshold_voltage_group.rpt
    }
    PNR,FP_EXIT,P3 {
        work/PNR/init_design1/reports/report_qor.rpt
        work/PNR/init_design1/reports/report_design.rpt
        work/PNR/init_design1/reports/report_utilization.rpt
        work/PNR/init_design1/reports/check_timing.rpt
        work/PNR/init_design1/reports/report_clocks.rpt
        work/PNR/init_design1/reports/report_threshold_voltage_group.rpt
        work/PNR/init_design1/reports/signoff_check_drc.rpt
    }

    PNR,PLACE_EXIT,P0 {
        work/PNR/place1/reports/report_qor.rpt
        work/PNR/place1/reports/report_timing.max.rpt
        work/PNR/place1/reports/report_congestion.rpt
    }
    PNR,PLACE_EXIT,P1 {
        work/PNR/place1/reports/report_qor.rpt
        work/PNR/place1/reports/report_timing.max.rpt
        work/PNR/place1/reports/report_timing.min.rpt
        work/PNR/place1/reports/report_congestion.rpt
        work/PNR/place1/reports/report_power.rpt
        work/PNR/place1/reports/check_legality.rpt
    }
    PNR,PLACE_EXIT,P2 {
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
    PNR,PLACE_EXIT,P3 {
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

    PNR,CTS_EXIT,P0 {
        work/PNR/cts1/reports/report_qor.rpt
        work/PNR/cts1/reports/report_clock_qor.rpt
        work/PNR/cts_opt1/reports/report_qor.rpt
    }
    PNR,CTS_EXIT,P1 {
        work/PNR/cts1/reports/report_qor.rpt
        work/PNR/cts1/reports/report_clock_qor.rpt
        work/PNR/cts1/reports/report_clock_timing.setup.rpt
        work/PNR/cts1/reports/report_timing.max.rpt
        work/PNR/cts_opt1/reports/report_qor.rpt
        work/PNR/cts_opt1/reports/report_timing.max.rpt
        work/PNR/cts_opt1/reports/report_timing.min.rpt
        work/PNR/cts_opt1/reports/report_power.rpt
    }
    PNR,CTS_EXIT,P2 {
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
    PNR,CTS_EXIT,P3 {
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

    PNR,PRO_EXIT,P0 {
        work/PNR/pro1/reports/report_qor.rpt
        work/PNR/pro1/reports/report_timing.max.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    PNR,PRO_EXIT,P1 {
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
    PNR,PRO_EXIT,P2 {
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
    PNR,PRO_EXIT,P3 {
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

    PNR,BTO,P0 {
        work/PNR/signoff1/reports/report_qor.rpt
        work/PNR/signoff1/reports/report_timing.max.rpt
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    PNR,BTO,P1 {
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
    PNR,BTO,P2 {
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
    PNR,BTO,P3 {
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

    PNR,MTO,P0 {
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
    }
    PNR,MTO,P1 {
        outputs/${design_name}.v
        outputs/${design_name}.def
        outputs/${design_name}.gds
        outputs/${design_name}.lef
        outputs/${design_name}.nlib
        outputs/${design_name}.enc
        outputs/${design_name}.upf
    }
    PNR,MTO,P2 {
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
    PNR,MTO,P3 {
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

    FP,FP_EXIT,P0 {
        work/FP/floorplan1/reports/report_design.rpt
        work/FP/floorplan1/reports/report_utilization.rpt
    }
    FP,FP_EXIT,P1 {
        work/FP/floorplan1/reports/report_design.rpt
        work/FP/floorplan1/reports/report_utilization.rpt
        work/FP/init_design1/reports/check_timing.rpt
        work/FP/post_floorplan1/reports/report_qor.rpt
        work/FP/post_floorplan1/reports/report_timing.max.rpt
        work/FP/post_floorplan1/reports/report_power.rpt
        work/FP/post_floorplan1/reports/report_congestion.rpt
    }
    FP,FP_EXIT,P2 {
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
    FP,FP_EXIT,P3 {
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

    FCFP,FP_EXIT,P0 {
        work/FCFP/create_floorplan1/reports/report_design.rpt
        work/FCFP/placement1/reports/report_qor.rpt
    }
    FCFP,FP_EXIT,P1 {
        work/FCFP/create_floorplan1/reports/report_design.rpt
        work/FCFP/placement1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_timing.max.rpt
        work/FCFP/timing_budget1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_power.rpt
        work/FCFP/placement1/reports/report_congestion.rpt
    }
    FCFP,FP_EXIT,P2 {
        work/FCFP/create_floorplan1/reports/report_design.rpt
        work/FCFP/placement1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_timing.max.rpt
        work/FCFP/placement1/reports/report_timing.min.rpt
        work/FCFP/timing_budget1/reports/report_qor.rpt
        work/FCFP/top_compile1/reports/report_qor.rpt
        work/FCFP/placement1/reports/report_threshold_voltage_group.rpt
        outputs/${design_name}.def
    }
    FCFP,FP_EXIT,P3 {
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

    SYNTH,P0 {
        work/SYNTH/synthesis1/reports/report_qor.rpt
        outputs/netlist/${design_name}.v
    }
    SYNTH,P1 {
        work/SYNTH/synthesis1/reports/report_qor.rpt
        work/SYNTH/synthesis1/reports/report_timing.max.rpt
        work/SYNTH/synthesis1/reports/report_timing.min.rpt
        work/SYNTH/synthesis1/reports/report_power.rpt
        outputs/netlist/${design_name}.v
        outputs/sdc/${design_name}.sdc
    }
    SYNTH,P2 {
        work/SYNTH/synthesis1/reports/report_qor.rpt
        work/SYNTH/synthesis1/reports/report_timing.max.rpt
        work/SYNTH/synthesis1/reports/report_timing.min.rpt
        work/SYNTH/synthesis1/reports/report_power.rpt
        work/SYNTH/synthesis1/reports/report_threshold_voltage_group.rpt
        outputs/netlist/${design_name}.v
        outputs/sdc/${design_name}.sdc
        outputs/${design_name}_compile.svf
    }
    SYNTH,P3 {
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

    STA,P0 {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
    }
    STA,P1 {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_congestion.rpt
    }
    STA,P2 {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
    }
    STA,P3 {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
        work/STA/timing1/reports/check_timing.rpt
    }
    STA,BTO,P2 {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
    }
    STA,BTO,P3 {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
        work/STA/timing1/reports/check_timing.rpt
    }
    STA,MTO,P2 {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
    }
    STA,MTO,P3 {
        work/STA/timing1/reports/report_timing.max.rpt
        work/STA/timing1/reports/report_timing.min.rpt
        work/STA/timing1/reports/report_qor.rpt
        work/STA/timing1/reports/report_power.rpt
        work/STA/timing1/reports/report_si.rpt
        work/STA/timing1/reports/report_threshold_voltage_group.rpt
        work/STA/timing1/reports/check_timing.rpt
    }

    # ── LEC Flow ─────────────────────────────────────────────────────────────

    LEC,P0 {
        work/LEC/compare1/reports/comparison_summary.rpt
    }
    LEC,P1 {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
    }
    LEC,P2 {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
    }
    LEC,P3 {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
        work/LEC/analyze1/reports/failing_points.rpt
    }
    LEC,BTO,P2 {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
    }
    LEC,BTO,P3 {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
        work/LEC/analyze1/reports/failing_points.rpt
    }
    LEC,MTO,P2 {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
    }
    LEC,MTO,P3 {
        work/LEC/compare1/reports/comparison_summary.rpt
        work/LEC/analyze1/reports/equivalence_analysis.rpt
        work/LEC/setup1/reports/setup_summary.rpt
        work/LEC/analyze1/reports/failing_points.rpt
    }

    # ── CLP Flow ─────────────────────────────────────────────────────────────

    CLP,P0 {
        work/CLP/clp1/reports/power_verification_summary.rpt
    }
    CLP,P1 {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
    }
    CLP,P2 {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
    }
    CLP,P3 {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
        work/CLP/clp1/reports/power_domain_check.rpt
    }
    CLP,BTO,P2 {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
    }
    CLP,BTO,P3 {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
        work/CLP/clp1/reports/power_domain_check.rpt
    }
    CLP,MTO,P2 {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
    }
    CLP,MTO,P3 {
        work/CLP/clp1/reports/power_verification_summary.rpt
        work/CLP/clp1/reports/isolation_check.rpt
        work/CLP/clp1/reports/retention_check.rpt
        work/CLP/clp1/reports/level_shifter_check.rpt
        work/CLP/clp1/reports/always_on_check.rpt
        work/CLP/clp1/reports/power_domain_check.rpt
    }

    # ── PV Flow ──────────────────────────────────────────────────────────────

    PV,P0 {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
    }
    PV,P1 {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/erc1/reports/erc_summary.rpt
    }
    PV,P2 {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/erc1/reports/erc_summary.rpt
        work/PV/perc1/reports/perc_summary.rpt
        work/PV/fill1/reports/fill_summary.rpt
    }
    PV,P3 {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/erc1/reports/erc_summary.rpt
        work/PV/perc1/reports/perc_summary.rpt
        work/PV/xor1/reports/xor_summary.rpt
        work/PV/fill1/reports/fill_summary.rpt
        work/PV/merge_data1/reports/merge_summary.rpt
    }
    PV,BTO,P2 {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/erc1/reports/erc_summary.rpt
        work/PV/perc1/reports/perc_summary.rpt
        work/PV/fill1/reports/fill_summary.rpt
    }
    PV,BTO,P3 {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/erc1/reports/erc_summary.rpt
        work/PV/perc1/reports/perc_summary.rpt
        work/PV/xor1/reports/xor_summary.rpt
        work/PV/fill1/reports/fill_summary.rpt
        work/PV/merge_data1/reports/merge_summary.rpt
    }
    PV,MTO,P2 {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/erc1/reports/erc_summary.rpt
        work/PV/perc1/reports/perc_summary.rpt
        work/PV/fill1/reports/fill_summary.rpt
    }
    PV,MTO,P3 {
        work/PV/drc1/reports/drc_summary.rpt
        work/PV/lvs1/reports/lvs_summary.rpt
        work/PV/erc1/reports/erc_summary.rpt
        work/PV/perc1/reports/perc_summary.rpt
        work/PV/xor1/reports/xor_summary.rpt
        work/PV/fill1/reports/fill_summary.rpt
        work/PV/merge_data1/reports/merge_summary.rpt
    }

    # ── EMIR Flow ────────────────────────────────────────────────────────────

    EMIR,P0 {
        work/EMIR/power_analysis1/reports/power_summary.rpt
    }
    EMIR,P1 {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
    }
    EMIR,P2 {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
    }
    EMIR,P3 {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_map.rpt
    }
    EMIR,BTO,P2 {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
    }
    EMIR,BTO,P3 {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_map.rpt
    }
    EMIR,MTO,P2 {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
    }
    EMIR,MTO,P3 {
        work/EMIR/power_analysis1/reports/power_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_summary.rpt
        work/EMIR/ir_drop1/reports/em_summary.rpt
        work/EMIR/thermal_analysis1/reports/thermal_summary.rpt
        work/EMIR/ir_drop1/reports/ir_drop_map.rpt
    }

    # ── ECO Flow ─────────────────────────────────────────────────────────────

    ECO,P0 {
        work/ECO/eco1/reports/report_qor.rpt
    }
    ECO,P1 {
        work/ECO/eco1/reports/report_qor.rpt
        work/ECO/eco1/reports/report_timing.max.rpt
    }
    ECO,P2 {
        work/ECO/eco1/reports/report_qor.rpt
        work/ECO/eco1/reports/report_timing.max.rpt
        work/ECO/eco1/reports/report_timing.min.rpt
        work/ECO/eco1/reports/report_power.rpt
    }
    ECO,P3 {
        work/ECO/eco1/reports/report_qor.rpt
        work/ECO/eco1/reports/report_timing.max.rpt
        work/ECO/eco1/reports/report_timing.min.rpt
        work/ECO/eco1/reports/report_power.rpt
        work/ECO/eco1/reports/check_timing.rpt
        outputs/eco/${design_name}.eco.v
    }

    # ── POPT Flow ────────────────────────────────────────────────────────────

    POPT,P0 {
        work/POPT/power_opt1/reports/post_opt_power_summary.rpt
    }
    POPT,P1 {
        work/POPT/power_opt1/reports/pre_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_power_summary.rpt
        work/POPT/merge_timing1/reports/merged_qor.rpt
    }
    POPT,P2 {
        work/POPT/power_opt1/reports/pre_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_timing.rpt
        work/POPT/merge_timing1/reports/merged_qor.rpt
        work/POPT/post_merge1/reports/post_merge_qor.rpt
        work/POPT/post_merge1/reports/post_merge_power.rpt
    }
    POPT,P3 {
        work/POPT/power_opt1/reports/pre_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_power_summary.rpt
        work/POPT/power_opt1/reports/post_opt_timing.rpt
        work/POPT/merge_timing1/reports/merged_qor.rpt
        work/POPT/post_merge1/reports/post_merge_qor.rpt
        work/POPT/post_merge1/reports/post_merge_power.rpt
        work/POPT/post_merge1/reports/post_merge_timing.rpt
    }
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          SECTION 3: CROSS-FLOW MILESTONE MAPPING                           ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Maps each milestone to required flows that must complete for sign-off
array set milestone_flow_map {
    FP_EXIT    {SYNTH_PNR PNR FP FCFP}
    PLACE_EXIT {SYNTH_PNR PNR SYNTH}
    CTS_EXIT   {SYNTH_PNR PNR SYNTH}
    PRO_EXIT   {SYNTH_PNR PNR SYNTH STA LEC}
    BTO        {SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO}
    MTO        {SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO POPT}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║          SECTION 4: PHASE CRITERIA THRESHOLDS                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set phase_criteria {
    FP_EXIT,P0,setup_wns        "-500"
    FP_EXIT,P0,utilization_min  "0.50"
    FP_EXIT,P1,setup_wns        "-200"
    FP_EXIT,P1,utilization_min  "0.60"
    FP_EXIT,P2,setup_wns        "-50"
    FP_EXIT,P2,utilization_min  "0.65"

    PLACE_EXIT,P0,setup_wns     "-200"
    PLACE_EXIT,P0,setup_tns     "-5000"
    PLACE_EXIT,P0,hold_wns      "-500"
    PLACE_EXIT,P1,setup_wns     "-80"
    PLACE_EXIT,P1,setup_tns     "-800"
    PLACE_EXIT,P1,hold_wns      "-200"
    PLACE_EXIT,P2,setup_wns     "-20"
    PLACE_EXIT,P2,setup_tns     "-100"
    PLACE_EXIT,P2,hold_wns      "-50"

    CTS_EXIT,P0,setup_wns       "-150"
    CTS_EXIT,P0,hold_wns        "-100"
    CTS_EXIT,P0,max_skew        "0.200"
    CTS_EXIT,P1,setup_wns       "-50"
    CTS_EXIT,P1,hold_wns        "-30"
    CTS_EXIT,P1,max_skew        "0.100"
    CTS_EXIT,P2,setup_wns       "-10"
    CTS_EXIT,P2,hold_wns        "-5"
    CTS_EXIT,P2,max_skew        "0.050"

    PRO_EXIT,P0,setup_wns       "-50"
    PRO_EXIT,P0,hold_wns        "-20"
    PRO_EXIT,P0,drc_count       "100"
    PRO_EXIT,P1,setup_wns       "-10"
    PRO_EXIT,P1,hold_wns        "-5"
    PRO_EXIT,P1,drc_count       "10"
    PRO_EXIT,P2,setup_wns       "0"
    PRO_EXIT,P2,hold_wns        "0"
    PRO_EXIT,P2,drc_count       "0"

    BTO,P2,setup_wns            "0"
    BTO,P2,hold_wns             "0"
    BTO,P2,drc_count            "0"
    BTO,P2,lvs_match            "true"
    BTO,P3,setup_wns            "0"
    BTO,P3,hold_wns             "0"
    BTO,P3,drc_count            "0"
    BTO,P3,lvs_match            "true"
    BTO,P3,antenna_violations   "0"
    BTO,P3,em_violations        "0"

    MTO,P3,setup_wns            "0"
    MTO,P3,hold_wns             "0"
    MTO,P3,drc_count            "0"
    MTO,P3,lvs_match            "true"
    MTO,P3,gds_errors           "0"
}

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
# ║  Maps each downstream flow's input types to upstream release locations     ║
# ║                                                                            ║
# ║  User sets in user_config.tcl:                                             ║
# ║    set pnr(input,netlist_release_tag) "v1.0.2"                             ║
# ║  Flow auto-resolves:                                                       ║
# ║    $release_path/$phase/$block/$tag/netlist/${design_name}.v               ║
# ║                                                                            ║
# ║  Or user gives direct path (existing behavior):                            ║
# ║    set pnr(input,netlist) "/path/to/netlist.v"                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# Handshake map: downstream_flow → input_type → {upstream_flow subdir filename_pattern}
# filename_pattern uses ${design_name} which is resolved at runtime
array set flow_input_handshake {
    SYNTH_PNR,rtl         {INPUTS   rtl      "${design_name}.f"}
    SYNTH_PNR,sdc         {INPUTS   sdc      "${design_name}.sdc"}
    SYNTH_PNR,upf_file    {INPUTS   upf      "${design_name}.upf"}

    SYNTH,rtl             {INPUTS   rtl      "${design_name}.f"}
    SYNTH,sdc             {INPUTS   sdc      "${design_name}.sdc"}
    SYNTH,upf_file        {INPUTS   upf      "${design_name}.upf"}

    PNR,netlist           {SYNTH    netlist   "${design_name}.v"}
    PNR,sdc               {SYNTH    sdc       "${design_name}.sdc"}
    PNR,upf_file          {SYNTH    upf       "${design_name}.upf"}
    PNR,def_file          {FP       def       "${design_name}.def"}
    PNR,fp_tcl            {FP       data      "floorplan.tcl"}

    FP,netlist            {SYNTH    netlist   "${design_name}.v"}
    FP,sdc                {SYNTH    sdc       "${design_name}.sdc"}
    FP,upf_file           {SYNTH    upf       "${design_name}.upf"}

    STA,netlist           {SYNTH_PNR netlist  "${design_name}.pt.v"}
    STA,sdc               {SYNTH_PNR sdc     "${design_name}.sdc"}
    STA,spef              {SYNTH_PNR spef    "${design_name}.spef"}
    STA,def_file          {SYNTH_PNR def     "${design_name}.def"}

    PV,gds                {SYNTH_PNR gds     "${design_name}.gds"}
    PV,netlist            {SYNTH_PNR netlist  "${design_name}.lvs.v"}
    PV,def_file           {SYNTH_PNR def     "${design_name}.def"}

    LEC,netlist_golden    {SYNTH    netlist   "${design_name}.v"}
    LEC,netlist_revised   {SYNTH_PNR netlist  "${design_name}.v"}

    CLP,netlist           {SYNTH_PNR netlist  "${design_name}.v"}
    CLP,upf_file          {SYNTH_PNR upf     "${design_name}.upf"}

    EMIR,def_file         {SYNTH_PNR def     "${design_name}.def"}
    EMIR,netlist          {SYNTH_PNR netlist  "${design_name}.v"}
    EMIR,spef             {SYNTH_PNR spef    "${design_name}.spef"}
    EMIR,gds              {SYNTH_PNR gds     "${design_name}.gds"}

    ECO,netlist           {SYNTH_PNR netlist  "${design_name}.v"}
    ECO,def_file          {SYNTH_PNR def     "${design_name}.def"}

    POPT,netlist          {SYNTH_PNR netlist  "${design_name}.pt.v"}
    POPT,spef             {SYNTH_PNR spef    "${design_name}.spef"}
    POPT,sdc              {SYNTH_PNR sdc     "${design_name}.sdc"}
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
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set release_tags {
    FP_EXIT    {description "Floorplan Exit"    phase_min P0 required_flows {SYNTH_PNR PNR FP FCFP}}
    PLACE_EXIT {description "Placement Exit"    phase_min P0 required_flows {SYNTH_PNR PNR SYNTH}}
    CTS_EXIT   {description "CTS Exit"          phase_min P1 required_flows {SYNTH_PNR PNR SYNTH}}
    PRO_EXIT   {description "Post-Route Exit"   phase_min P1 required_flows {SYNTH_PNR PNR SYNTH STA LEC}}
    BTO        {description "Backend Tapeout"   phase_min P2 required_flows {SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO}}
    MTO        {description "Mask Tapeout"      phase_min P3 required_flows {SYNTH_PNR PNR SYNTH FP STA LEC CLP PV EMIR ECO POPT}}
}

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                 SECTION 7: PER-FLOW RELEASE DELIVERABLES                   ║
# ║  Maps each flow to file suffixes that export_data produces                 ║
# ║  Used by release command to know what to copy per flow                     ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

array set release_deliverables {
    SYNTH_PNR,netlist  {.v .pt.v .fm.v .lvs.v .vc_lp.v .dc.v}
    SYNTH_PNR,gds      {.gds}
    SYNTH_PNR,def      {.def}
    SYNTH_PNR,lef      {.lef}
    SYNTH_PNR,sdc      {.sdc}
    SYNTH_PNR,spef     {.spef}
    SYNTH_PNR,upf      {.upf}
    SYNTH_PNR,data     {_wscript _wscript_for_pt _routing_constraints _floorplan .saif.ptpx.map .saif.fc.map}
    PNR,netlist  {.v .pt.v .fm.v .lvs.v}
    PNR,gds      {.gds}
    PNR,def      {.def}
    PNR,sdc      {.sdc}
    PNR,spef     {.spef}
    PNR,upf      {.upf}
    PNR,data     {_wscript _wscript_for_pt _routing_constraints _floorplan}
    SYNTH,netlist  {.v}
    SYNTH,sdc      {.sdc}
    STA,reports    {timing_summary.rpt mmmc_timing_summary.rpt}
    LEC,reports    {comparison_summary.rpt}
    CLP,reports    {power_verification_summary.rpt}
    PV,reports     {drc_summary.rpt lvs_summary.rpt erc_summary.rpt}
    EMIR,reports   {power_summary.rpt ir_drop_summary.rpt}
}

puts "INFO: Release configuration loaded — [array size release_exit_files] exit files, [array size release_tags] tags, [array size release_deliverables] deliverables"
