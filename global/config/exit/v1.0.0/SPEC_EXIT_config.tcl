# ═══════════════════════════════════════════════════════════════════════════════
# SPEC_EXIT Milestone Configuration
# Spec Exit — block spec checked; IP-XACT, register RTL, SDC / UPF, RTL
# filelist and vPlan generated from it; RTL top matches the spec's ports
# Stage: gen_collateral1 (RTL_SPEC flow)
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "SPEC_EXIT"
set milestone_info(discipline)  "RTL"
set milestone_info(flow_type)   "RTL_SPEC"
set milestone_info(stage)       "gen_collateral"
set milestone_info(description) "Spec Exit — spec clean, IP-XACT valid, register RTL generated, RTL ports match the spec"
set milestone_info(stage_node)  "gen_collateral1"
set milestone_info(report_dir)  "reports/rtl_spec"
set milestone_info(owner)       "vmerugu"

array set check_packs {}

array set mandatory_checks {
    "spec_errors" {
        "id"                "SPEC_0001"
        "script"            "check_metric.tcl"
        "description"       "Block spec has no schema / consistency errors"
        "criteria"          "spec_errors <= 0"
        "min_phase_index"   "0"
        "metric_name"       "spec_errors"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
    "ipxact_schema_valid" {
        "id"                "SPEC_0002"
        "script"            "check_grep.tcl"
        "description"       "IP-XACT component validates against IEEE 1685-2014"
        "criteria"          "schema VALID"
        "min_phase_index"   "0"
        "report_file"       "reports/rtl_spec/ipxact.rpt"
        "grep_pattern"      "Schema\\s*:\\s*VALID"
        "grep_pass_if"      "found"
    }
    "rtl_port_mismatches" {
        "id"                "SPEC_0003"
        "script"            "check_metric.tcl"
        "description"       "RTL top ports match the spec (name, direction, width)"
        "criteria"          "rtl_port_mismatches <= 0"
        "min_phase_index"   "0"
        "metric_name"       "rtl_port_mismatches"
        "unit"              ""
        "operator"          "<="
        "default_threshold" "0"
    }
    "register_rtl" {
        "id"                "SPEC_0004"
        "script"            "check_file_exists.tcl"
        "description"       "Register block generated (or the spec declares no registers)"
        "criteria"          "file exists"
        "min_phase_index"   "0"
        "report_file"       "outputs/regs.status"
    }
}

array set optional_checks {}

set mandatory_files [list \
    "outputs/component.xml" \
    "outputs/design.f" \
    "outputs/design.sdc" \
]

array set deliverables {
    "ipxact"   { "type" "spec"    "src" "outputs/component.xml" "dst" "releases/SPEC_EXIT/${design_name}.xml" }
    "filelist" { "type" "rtl"     "src" "outputs/design.f"      "dst" "releases/SPEC_EXIT/${design_name}.f" }
    "sdc"      { "type" "sdc"     "src" "outputs/design.sdc"    "dst" "releases/SPEC_EXIT/${design_name}.sdc" }
}
