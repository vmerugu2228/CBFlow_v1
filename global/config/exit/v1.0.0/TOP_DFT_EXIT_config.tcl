# ═══════════════════════════════════════════════════════════════════════════════
# TOP_DFT_EXIT Milestone Configuration
# Top DFT Exit — Pass2 TDR + DFT Signals + SRI insertion complete
# Stage: insert1 (DFT_INSERT_PASS2 flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "TOP_DFT_EXIT"
set milestone_info(discipline)  "DFT"
set milestone_info(flow_type)   "DFT_INSERT_PASS2"
set milestone_info(stage)       "insert"
set milestone_info(description) "Top DFT Exit — Pass2 TDR + DFT Signals + SRI complete"
set milestone_info(stage_node)  "insert1"
set milestone_info(report_dir)  "reports/dft_insert_pass2"
set milestone_info(owner)       "Nandini"

array set check_packs {}

array set mandatory_checks {
    "top_dft_inserted_rtl" {
        "id"          "DFT_INSERT_PASS2_0001"
        "script"            "check_file_exists.tcl"
        "description"       "Pass2 top-level DFT-inserted RTL exists"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.top.dft.v"
    }
    "top_dft_insertion_report" {
        "id"          "DFT_INSERT_PASS2_0002"
        "script"            "check_file_exists.tcl"
        "description"       "Pass2 insertion report present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/dft_insert_pass2/insertion.rpt"
    }
    "top_dft_spec" {
        "id"          "DFT_INSERT_PASS2_0003"
        "script"            "check_file_exists.tcl"
        "description"       "Top DFT spec written"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.top.dft_spec"
    }
    "top_dft_icl" {
        "id"          "DFT_INSERT_PASS2_0004"
        "script"            "check_file_exists.tcl"
        "description"       "Top-level ICL network present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.top.icl"
    }
    "top_dft_drc" {
        "id"          "DFT_INSERT_PASS2_0005"
        "script"            "check_file_exists.tcl"
        "description"       "Top-level DRC report present"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "reports/dft_insert_pass2/drc.rpt"
    }
}

array set optional_checks {
    "top_dft_sdc" {
        "id"          "DFT_INSERT_PASS2_0006"
        "script"            "check_file_exists.tcl"
        "description"       "Top-level SDC generated"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/${design_name}.top.sdc"
    }
}

set mandatory_files [list \
    "outputs/${design_name}.top.dft.v" \
    "outputs/${design_name}.top.icl" \
    "outputs/${design_name}.top.pdl" \
    "outputs/${design_name}.top.sdc" \
    "outputs/${design_name}.top.tcd" \
    "outputs/${design_name}.top.tsdb_info" \
    "outputs/${design_name}.top.dft_spec" \
    "reports/dft_insert_pass2/insertion.rpt" \
    "reports/dft_insert_pass2/drc.rpt" \
]

array set deliverables {
    "top_dft_rtl"            { "type" "rtl"    "src" "outputs/${design_name}.top.dft.v"    "dst" "releases/TOP_DFT_EXIT/${design_name}.top.dft.v" }
    "top_dft_spec"           { "type" "spec"   "src" "outputs/${design_name}.top.dft_spec" "dst" "releases/TOP_DFT_EXIT/${design_name}.top.dft_spec" }
    "top_dft_icl"            { "type" "icl"    "src" "outputs/${design_name}.top.icl"      "dst" "releases/TOP_DFT_EXIT/${design_name}.top.icl" }
    "top_dft_insertion_report" { "type" "report" "src" "reports/dft_insert_pass2/insertion.rpt" "dst" "releases/TOP_DFT_EXIT/insertion.rpt" }
}
