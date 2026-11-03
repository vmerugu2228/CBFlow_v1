# ═══════════════════════════════════════════════════════════════════════════════
# EDT_OCC_EXIT Milestone Configuration
# EDT & OCC Exit — Pass3 compression + at-speed clocking insertion complete
# Stage: insert1 (DFT_INSERT_PASS3 flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "EDT_OCC_EXIT"
set milestone_info(discipline)  "DFT"
set milestone_info(stage)       "insert"
set milestone_info(description) "EDT & OCC Exit — Pass3 compression + at-speed clocking complete"
set milestone_info(stage_node)  "insert1"
set milestone_info(report_dir)  "reports/dft_insert_pass3"
set milestone_info(owner)       "Chaitanya"

array set check_packs {}

array set mandatory_checks {
    "edt_occ_inserted_rtl" {
        "script"            "check_file_exists.tcl"
        "description"       "Pass3 EDT+OCC inserted RTL exists"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.edt_occ.v"
    }
    "edt_occ_insertion_report" {
        "script"            "check_file_exists.tcl"
        "description"       "Pass3 insertion report present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/dft_insert_pass3/insertion.rpt"
    }
    "edt_spec" {
        "script"            "check_file_exists.tcl"
        "description"       "EDT spec present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.edt_spec"
    }
    "occ_spec" {
        "script"            "check_file_exists.tcl"
        "description"       "OCC spec present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.occ_spec"
    }
    "edt_occ_drc_clean" {
        "script"            "check_file_exists.tcl"
        "description"       "Post-opt DRC report present (zero new violations enforced in-handler)"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/dft_insert_pass3/drc_post.rpt"
    }
    "edt_patterns" {
        "script"            "check_file_exists.tcl"
        "description"       "EDT compressed patterns generated"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/EDT_patterns.v"
    }
}

array set optional_checks {
    "edt_compression_ratio" {
        "script"            "check_metric.tcl"
        "description"       "EDT compression ratio achieves target"
        "criteria"          "edt_compression_ratio >= 80"
        "min_phase_index"   "0"
        "metric_name"       "edt_compression_ratio"
        "operator"          ">="
        "default_threshold" "80"
    }
}

set mandatory_files [list \
    "outputs/${design_name}.edt_occ.v" \
    "outputs/${design_name}.edt_occ.sdc" \
    "outputs/${design_name}.edt_occ.pdl" \
    "outputs/${design_name}.edt_occ.tcd" \
    "outputs/${design_name}.edt.icl" \
    "outputs/${design_name}.edt_spec" \
    "outputs/${design_name}.occ.icl" \
    "outputs/${design_name}.occ_spec" \
    "outputs/EDT_patterns.v" \
    "outputs/EDT_patterns.pdl" \
    "outputs/edt_occ_simulation_data_dictionary" \
    "reports/dft_insert_pass3/insertion.rpt" \
    "reports/dft_insert_pass3/drc_pre.rpt" \
    "reports/dft_insert_pass3/drc_opt.rpt" \
    "reports/dft_insert_pass3/drc_post.rpt" \
]

array set deliverables {
    "edt_occ_rtl"     { "type" "rtl"      "src" "outputs/${design_name}.edt_occ.v"    "dst" "releases/EDT_OCC_EXIT/${design_name}.edt_occ.v" }
    "edt_spec"        { "type" "spec"     "src" "outputs/${design_name}.edt_spec"      "dst" "releases/EDT_OCC_EXIT/${design_name}.edt_spec" }
    "occ_spec"        { "type" "spec"     "src" "outputs/${design_name}.occ_spec"      "dst" "releases/EDT_OCC_EXIT/${design_name}.occ_spec" }
    "edt_patterns"    { "type" "patterns" "src" "outputs/EDT_patterns.v"                "dst" "releases/EDT_OCC_EXIT/EDT_patterns.v" }
    "insertion_report" { "type" "report"  "src" "reports/dft_insert_pass3/insertion.rpt" "dst" "releases/EDT_OCC_EXIT/insertion.rpt" }
}
