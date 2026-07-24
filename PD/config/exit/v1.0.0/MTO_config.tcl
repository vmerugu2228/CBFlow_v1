# ═══════════════════════════════════════════════════════════════════════════════
# MTO Milestone Configuration
# Mask Tape Out — Final delivery package for mask shop
# Stage: signoff (SYNTH_PNR flow) — all BTO checks must pass first
# ═══════════════════════════════════════════════════════════════════════════════

set milestone_info(name)        "MTO"
set milestone_info(stage)       "signoff"
set milestone_info(description) "Mask Tape Out - Final delivery for mask generation"
set milestone_info(stage_node)  "signoff1"
set milestone_info(report_dir)  "work/SYNTH_PNR/signoff1/reports"

# ── Check packs — all categories active for MTO ──────────────────────────
array set check_packs {
    timing         "0"
    placement      "0"
    clock          "0"
    power          "1"
    routing        "0"
    physical       "1"
    si             "2"
    manufacturing  "2"
}

# ── Mandatory checks ─────────────────────────────────────────────────────────
# MTO checks focus on completeness of the delivery package.
# All BTO quality checks (timing, DRC, routing, etc.) are prerequisites.
array set mandatory_checks {
    "mto_gds_complete" {
        "script"      "check_file_exists.tcl"
        "description" "Final GDS layout exists"
        "criteria"    "file exists and non-empty"
        "min_phase_index"   "0"
        "report_file" "outputs/${design_name}.gds"
    }
    "mto_netlist_complete" {
        "script"      "check_file_exists.tcl"
        "description" "Final Verilog netlist exists"
        "criteria"    "file exists and non-empty"
        "min_phase_index"   "0"
        "report_file" "outputs/${design_name}.v"
    }
    "mto_def_complete" {
        "script"      "check_file_exists.tcl"
        "description" "Final DEF exists"
        "criteria"    "file exists and non-empty"
        "min_phase_index"   "0"
        "report_file" "outputs/${design_name}.def"
    }
    "mto_lef_complete" {
        "script"      "check_file_exists.tcl"
        "description" "Final LEF abstract exists"
        "criteria"    "file exists and non-empty"
        "min_phase_index"   "0"
        "report_file" "outputs/${design_name}.lef"
    }
    "mto_upf_complete" {
        "script"      "check_file_exists.tcl"
        "description" "UPF power intent exists"
        "criteria"    "file exists"
        "min_phase_index"   "1"
        "report_file" "outputs/${design_name}.upf"
    }
    "mto_pt_netlist" {
        "script"      "check_file_exists.tcl"
        "description" "PT-format netlist for STA"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "outputs/${design_name}.pt.v"
    }
    "mto_fm_netlist" {
        "script"      "check_file_exists.tcl"
        "description" "Formality netlist for LEC"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "outputs/${design_name}.fm.v"
    }
    "mto_lvs_netlist" {
        "script"      "check_file_exists.tcl"
        "description" "LVS netlist for physical verification"
        "criteria"    "file exists"
        "min_phase_index"   "3"
        "report_file" "outputs/${design_name}.lvs.v"
    }
    "mto_vclp_netlist" {
        "script"      "check_file_exists.tcl"
        "description" "VC-LP netlist for power verification"
        "criteria"    "file exists"
        "min_phase_index"   "3"
        "report_file" "outputs/${design_name}.vc_lp.v"
    }
    "mto_dc_netlist" {
        "script"      "check_file_exists.tcl"
        "description" "DC netlist"
        "criteria"    "file exists"
        "min_phase_index"   "3"
        "report_file" "outputs/${design_name}.dc.v"
    }
}

# ── Optional checks ──────────────────────────────────────────────────────────
array set optional_checks {
    "mto_floorplan" {
        "script"      "check_file_exists.tcl"
        "description" "Floorplan file for downstream blocks"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "outputs/${design_name}_floorplan"
    }
    "mto_wscript" {
        "script"      "check_file_exists.tcl"
        "description" "Wavescope script"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "outputs/${design_name}_wscript"
    }
    "mto_wscript_pt" {
        "script"      "check_file_exists.tcl"
        "description" "Wavescope script for PT"
        "criteria"    "file exists"
        "min_phase_index"   "2"
        "report_file" "outputs/${design_name}_wscript_for_pt"
    }
    "mto_routing_constraints" {
        "script"      "check_file_exists.tcl"
        "description" "Routing constraints for downstream"
        "criteria"    "file exists"
        "min_phase_index"   "3"
        "report_file" "outputs/${design_name}_routing_constraints"
    }
    "mto_design_db_nlib" {
        "script"      "check_file_exists.tcl"
        "description" "FC design database (.nlib)"
        "criteria"    "file exists"
        "min_phase_index"   "3"
        "report_file" "outputs/${design_name}.nlib"
    }
    "mto_design_db_enc" {
        "script"      "check_file_exists.tcl"
        "description" "Innovus design database (.enc)"
        "criteria"    "file exists"
        "min_phase_index"   "3"
        "report_file" "outputs/${design_name}.enc"
    }
}

# ── Mandatory files ───────────────────────────────────────────────────────────
set mandatory_files {
    "outputs/${design_name}.v"
    "outputs/${design_name}.def"
    "outputs/${design_name}.gds"
    "outputs/${design_name}.lef"
}

# ── Deliverables ──────────────────────────────────────────────────────────────
array set deliverables {
    "gds" {
        "source" "outputs/${design_name}.gds"
        "target" "releases/MTO/${design_name}.gds"
        "type"   "layout"
    }
    "netlist" {
        "source" "outputs/${design_name}.v"
        "target" "releases/MTO/${design_name}.v"
        "type"   "netlist"
    }
    "def" {
        "source" "outputs/${design_name}.def"
        "target" "releases/MTO/${design_name}.def"
        "type"   "physical"
    }
    "lef" {
        "source" "outputs/${design_name}.lef"
        "target" "releases/MTO/${design_name}.lef"
        "type"   "abstract"
    }
    "pt_netlist" {
        "source" "outputs/${design_name}.pt.v"
        "target" "releases/MTO/${design_name}.pt.v"
        "type"   "netlist"
    }
    "fm_netlist" {
        "source" "outputs/${design_name}.fm.v"
        "target" "releases/MTO/${design_name}.fm.v"
        "type"   "netlist"
    }
    "lvs_netlist" {
        "source" "outputs/${design_name}.lvs.v"
        "target" "releases/MTO/${design_name}.lvs.v"
        "type"   "netlist"
    }
    "upf" {
        "source" "outputs/${design_name}.upf"
        "target" "releases/MTO/${design_name}.upf"
        "type"   "power_intent"
    }
}
