# ═══════════════════════════════════════════════════════════════════════════════
# CORE_DFT_EXIT Milestone Configuration
# Core DFT Exit — Pass1 MBIST + BSCAN insertion complete
# Stage: insert1 (DFT_INSERT_PASS1 flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "CORE_DFT_EXIT"
set milestone_info(discipline)  "DFT"
set milestone_info(stage)       "insert"
set milestone_info(description) "Core DFT Exit — Pass1 MBIST + BSCAN insertion complete"
set milestone_info(stage_node)  "insert1"
set milestone_info(report_dir)  "reports/dft_insert_pass1"
set milestone_info(owner)       "Ayyappa"

# ── Check packs ──────────────────────────────────────────────────────────────
array set check_packs {}

# ── Mandatory checks ─────────────────────────────────────────────────────────
array set mandatory_checks {
    "core_dft_inserted_rtl" {
        "script"            "check_file_exists.tcl"
        "description"       "Pass1 DFT-inserted RTL exists"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.dft.v"
    }
    "core_dft_insertion_report" {
        "script"            "check_file_exists.tcl"
        "description"       "DFT insertion report present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/dft_insert_pass1/insertion.rpt"
    }
    "core_dft_drc_clean" {
        "script"            "check_file_exists.tcl"
        "description"       "Post-TPI DRC report present (zero new violations enforced in-handler)"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/dft_insert_pass1/drc_post.rpt"
    }
    "core_dft_mbist_controller" {
        "script"            "check_file_exists.tcl"
        "description"       "MBIST controller Verilog present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}_rtl1_tessent_mbist_c1_controller.v"
    }
    "core_dft_tap_icl" {
        "script"            "check_file_exists.tcl"
        "description"       "TAP ICL spec present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.tap.icl"
    }
    "core_dft_memory_bist_patterns" {
        "script"            "check_file_exists.tcl"
        "description"       "MemoryBist_P1 pattern files present (v + pdl)"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/MemoryBist_P1.v"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "core_dft_bscan_present" {
        "script"            "check_file_exists.tcl"
        "description"       "BSCAN interface present (optional — top blocks only)"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}_rtl1_tessent_bscan_interface_m1.v"
    }
    "core_dft_mbist_controller_count" {
        "script"            "check_metric.tcl"
        "description"       "MBIST controller count metric emitted"
        "criteria"          "mbist_controller_count >= 1"
        "min_phase_index"   "0"
        "metric_name"       "mbist_controller_count"
        "operator"          ">="
        "default_threshold" "1"
    }
}

# ── Mandatory files — single-pass artifact enumeration ───────────────────────
set mandatory_files [list \
    "outputs/${design_name}.dft.v" \
    "outputs/${design_name}.icl" \
    "outputs/${design_name}.pdl" \
    "outputs/${design_name}.sdc" \
    "outputs/${design_name}.tcd" \
    "outputs/${design_name}.tsdb_info" \
    "outputs/${design_name}.dft_spec" \
    "outputs/${design_name}.tap.icl" \
    "outputs/${design_name}_rtl1_mbist.sdc_dictionary" \
    "outputs/${design_name}_rtl1_mbist.synthesis_dictionary" \
    "outputs/${design_name}_rtl1_tessent_mbist_bap.v" \
    "outputs/${design_name}_rtl1_tessent_mbist_c1_controller.v" \
    "outputs/ICLNetwork.v" \
    "outputs/ICLNetwork.pdl" \
    "outputs/MemoryBist_P1.v" \
    "outputs/MemoryBist_P1.pdl" \
    "outputs/simulation_data_dictionary" \
    "reports/dft_insert_pass1/insertion.rpt" \
    "reports/dft_insert_pass1/drc_pre.rpt" \
    "reports/dft_insert_pass1/drc_post.rpt" \
]

# ── Deliverables (file → release path) ───────────────────────────────────────
array set deliverables {
    "dft_rtl"                { "type" "rtl"      "src" "outputs/${design_name}.dft.v"                 "dst" "releases/CORE_DFT_EXIT/${design_name}.dft.v" }
    "dft_spec"               { "type" "spec"     "src" "outputs/${design_name}.dft_spec"              "dst" "releases/CORE_DFT_EXIT/${design_name}.dft_spec" }
    "tap_icl"                { "type" "icl"      "src" "outputs/${design_name}.tap.icl"               "dst" "releases/CORE_DFT_EXIT/${design_name}.tap.icl" }
    "mbist_controller"       { "type" "mbist"    "src" "outputs/${design_name}_rtl1_tessent_mbist_c1_controller.v" "dst" "releases/CORE_DFT_EXIT/${design_name}_mbist_c1_controller.v" }
    "memory_bist_patterns"   { "type" "patterns" "src" "outputs/MemoryBist_P1.v"                      "dst" "releases/CORE_DFT_EXIT/MemoryBist_P1.v" }
    "insertion_report"       { "type" "report"   "src" "reports/dft_insert_pass1/insertion.rpt"       "dst" "releases/CORE_DFT_EXIT/insertion.rpt" }
}
