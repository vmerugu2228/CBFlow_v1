#!/usr/bin/env tclsh
# ============================================================================
# CBflow - Denali Project Configuration
# Description: Denali project-specific parameters
# ============================================================================

# Project identification
set project(name) "denali"
set project(version) "1.0"
set project(cbflow_release) "v1.0.0"   ;# CBflow release version for this project
set project(description) "Denali chip design project"
set project(owner) "Denali Design Team"
set project(contact) "denali@smartsoc.com"

# Project root directory for relative path resolution
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

# Technology — GF 28nm SLP-E
set project(technology) "gf_28nm"
set project(track_variant) "9T"
set project(metal_stack) "gf28slpe_10M_2Mx_5Cx_1Jx_2Qx"
set project(vt_flavors) "rvt lvt hvt"
set project(lib_root) "/proj/libs/gf_28nm"

# Design hierarchy
set project(top_module) "denali_top"
set project(block_list) "tom"

# ---------------------------------------------------------------------------
# DESIGN INFORMATION
# ---------------------------------------------------------------------------

# Simple hierarchy: denali_top (DL1) -> tom (DL2)
set project(design_hierarchy) {
    denali_top {
        description "Full chip top level (DL1)"
        level "DL1"
        parent ""
        children {tom}
    }
    tom {
        description "TOM processing block (DL2)"
        level "DL2"
        parent "denali_top"
        children {}
    }
}

# Generate valid design names from hierarchy
set project(valid_design_names) [dict keys $project(design_hierarchy)]

# Clock constraints
set project(clock,period) "2.5"
set project(clock,ports) "clk ref_clk"
set project(clock,uncertainty) "0.12"
set project(clock,latency) "0.25"
set project(clock,frequency) "400000000"

# SDC Mode Definitions (used for file naming: <design_name>.<mode>.sdc)
set project(sdc_modes) {func scan test}
set project(default_sdc_mode) "func"

# Reset constraints
set project(reset,ports) "rst_n"
set project(reset,polarity) "active_low"
set project(reset,async) "true"

# I/O constraints
set project(io,voltage) "1.8"
set project(io,drive_strength) "4"
set project(io,slew_rate) "slow"
set project(io,placement) "denali_io.def"
set project(io,count) "128"

# Power intent
set project(power,domains) "PD_TOM PD_TOP"
set project(power,states) "ON OFF RETENTION"
set project(power,switches) "sw_tom"
set project(power,isolation) "iso_tom"
set project(power,retention) "ret_tom"

# Design size estimates
set project(estimated_area) "2000000"
set project(estimated_power) "150"
set project(gate_count) "120000"
set project(register_count) "12000"
set project(memory_bits) "4194304"

# Technology targets
set project(target,frequency) "400"
set project(target,power) "120"
set project(target,area) "1800000"
set project(target,yield) "98"
set project(target,utilization) 0.70
set project(target,aspect_ratio) 1.0

# Test and verification
set project(dft,scan_chains) "4"
set project(dft,coverage_target) "98"
set project(dft,compression) "true"
set project(verification,formal) "true"
set project(verification,simulation) "true"

# Default Cadence tools
set project(default_tools) {
    SYNTH    "genus"
    PNR      "innovus"
    STA      "tempus"
    LEC      "conformal"
    CLP      "conformal_lp"
    EMIR     "voltus"
    PV       "calibre"
}

# Feature toggles
set project(autoppt,enabled) "false"         ;# Enable AutoPPT summary generation (requires python-pptx)

# Custom settings
set project(custom,scripts) "denali_hooks.tcl"
set project(custom,constraints) "denali_constraints.sdc"
set project(custom,hooks) "denali_custom.tcl"
set project(custom,waivers) "denali_waivers.tcl"
set project(custom,config_files) "denali_extra.tcl"

# ---------------------------------------------------------------------------
# VALIDATION WAIVER PATTERNS
# ---------------------------------------------------------------------------

# Global validation waivers - patterns that should be waivered across all stages
set project(validation,global_waivers) {
    ".*[Ww]arning.*clock.*skew.*"
    ".*[Ww]arning.*timing.*convergence.*"
    ".*[Ww]arning.*unconnected.*pin.*"
    ".*[Ww]arning.*library.*characterization.*"
    ".*[Ii]nfo.*optimization.*"
    ".*[Nn]ote.*"
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
    ".*[Ww]arning.*antenna.*violation.*"
    ".*[Ww]arning.*routing.*congestion.*"
}

set project(validation,signoff_waivers) {
    ".*[Ww]arning.*final.*timing.*report.*"
    ".*[Ww]arning.*design.*margin.*"
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

# ---------------------------------------------------------------------------
# RELEASE CONFIGURATION
# ---------------------------------------------------------------------------

# RACE DB Path
# DB structure: $db_path/$project_name/$domain/$flow_type/$user_$run_name.db
set project(race,db_path) "/proj/denali/race_db"

set project(release,author) "Denali Design Team"
set project(release,organization) "GF 28nm SLP-E Design Group"

# Release Path Configuration
# Release path structure: $release_path/$phase/$block_name/$release_tag
set project(release,path) "/Users/vmerugu/projects/CBflow_clone/test_releases"
set project(release,phase) "P0"
set project(release,block_name) ""
set project(release,active_tag) "BTO"
set project(release,expiry_date) "2027-06-30"

# Release directory sub-structure
set project(release,structure) {
    "netlist" "sdc" "def" "gds" "spef" "upf"
    "reports" "data" "db" "docs"
}

# Release settings
set project(release,include_timestamp) "false"
set project(release,generate_notes) "true"
set project(release,validate_mandatory) "true"

# ---------------------------------------------------------------------------
# LSF RESOURCE MANAGEMENT
# ---------------------------------------------------------------------------

set project(lsf,enabled) "true"
set project(lsf,version) "1.0.0"
set project(lsf,config_date) "2026-06-02"

# Default LSF settings
set project(lsf,default_queue) "M"
set project(lsf,emergency_queue) "ultra"
set project(lsf,selection_strategy) "ml_optimized"
set project(lsf,cost_optimization) "true"
set project(lsf,ml_analytics) "true"

# Project resource constraints
set project(lsf,max_concurrent_jobs) "15"
set project(lsf,max_daily_cost) "500.00"        ;# USD
set project(lsf,priority_class) "normal"         ;# normal, high, critical
set project(lsf,budget_alert_threshold) "0.8"    ;# 80% of budget

# Node-specific resource requirements — SYNTH
set project(lsf,node_requirements,SYNTH,inputs,queue) "S"
set project(lsf,node_requirements,SYNTH,inputs,memory) "4GB"
set project(lsf,node_requirements,SYNTH,inputs,cpu) "2"
set project(lsf,node_requirements,SYNTH,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,SYNTH,synthesis,queue) "M"
set project(lsf,node_requirements,SYNTH,synthesis,memory) "8GB"
set project(lsf,node_requirements,SYNTH,synthesis,cpu) "4"
set project(lsf,node_requirements,SYNTH,synthesis,runtime_estimate) "1.5"

set project(lsf,node_requirements,SYNTH,export_data,queue) "S"
set project(lsf,node_requirements,SYNTH,export_data,memory) "4GB"
set project(lsf,node_requirements,SYNTH,export_data,cpu) "2"
set project(lsf,node_requirements,SYNTH,export_data,runtime_estimate) "0.5"

# Node-specific resource requirements — PNR
set project(lsf,node_requirements,PNR,inputs,queue) "S"
set project(lsf,node_requirements,PNR,inputs,memory) "4GB"
set project(lsf,node_requirements,PNR,inputs,cpu) "2"
set project(lsf,node_requirements,PNR,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,PNR,import_design,queue) "M"
set project(lsf,node_requirements,PNR,import_design,memory) "12GB"
set project(lsf,node_requirements,PNR,import_design,cpu) "4"
set project(lsf,node_requirements,PNR,import_design,runtime_estimate) "0.75"

set project(lsf,node_requirements,PNR,floorplan,queue) "M"
set project(lsf,node_requirements,PNR,floorplan,memory) "12GB"
set project(lsf,node_requirements,PNR,floorplan,cpu) "4"
set project(lsf,node_requirements,PNR,floorplan,runtime_estimate) "1.0"

set project(lsf,node_requirements,PNR,powerplan,queue) "M"
set project(lsf,node_requirements,PNR,powerplan,memory) "16GB"
set project(lsf,node_requirements,PNR,powerplan,cpu) "8"
set project(lsf,node_requirements,PNR,powerplan,runtime_estimate) "2.0"

set project(lsf,node_requirements,PNR,placement,queue) "L"
set project(lsf,node_requirements,PNR,placement,memory) "24GB"
set project(lsf,node_requirements,PNR,placement,cpu) "8"
set project(lsf,node_requirements,PNR,placement,runtime_estimate) "3.0"

set project(lsf,node_requirements,PNR,cts,queue) "L"
set project(lsf,node_requirements,PNR,cts,memory) "24GB"
set project(lsf,node_requirements,PNR,cts,cpu) "8"
set project(lsf,node_requirements,PNR,cts,runtime_estimate) "2.5"

set project(lsf,node_requirements,PNR,route,queue) "L"
set project(lsf,node_requirements,PNR,route,memory) "32GB"
set project(lsf,node_requirements,PNR,route,cpu) "16"
set project(lsf,node_requirements,PNR,route,runtime_estimate) "5.0"

set project(lsf,node_requirements,PNR,route_opt,queue) "L"
set project(lsf,node_requirements,PNR,route_opt,memory) "32GB"
set project(lsf,node_requirements,PNR,route_opt,cpu) "16"
set project(lsf,node_requirements,PNR,route_opt,runtime_estimate) "4.0"

set project(lsf,node_requirements,PNR,post_route,queue) "M"
set project(lsf,node_requirements,PNR,post_route,memory) "16GB"
set project(lsf,node_requirements,PNR,post_route,cpu) "8"
set project(lsf,node_requirements,PNR,post_route,runtime_estimate) "1.5"

# Node-specific resource requirements — STA
set project(lsf,node_requirements,STA,inputs,queue) "S"
set project(lsf,node_requirements,STA,inputs,memory) "4GB"
set project(lsf,node_requirements,STA,inputs,cpu) "2"
set project(lsf,node_requirements,STA,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,STA,extraction,queue) "M"
set project(lsf,node_requirements,STA,extraction,memory) "16GB"
set project(lsf,node_requirements,STA,extraction,cpu) "8"
set project(lsf,node_requirements,STA,extraction,runtime_estimate) "3.0"

set project(lsf,node_requirements,STA,timing,queue) "M"
set project(lsf,node_requirements,STA,timing,memory) "16GB"
set project(lsf,node_requirements,STA,timing,cpu) "8"
set project(lsf,node_requirements,STA,timing,runtime_estimate) "2.0"

# Node-specific resource requirements — LEC
set project(lsf,node_requirements,LEC,inputs,queue) "S"
set project(lsf,node_requirements,LEC,inputs,memory) "4GB"
set project(lsf,node_requirements,LEC,inputs,cpu) "2"
set project(lsf,node_requirements,LEC,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,LEC,equivalence_check,queue) "M"
set project(lsf,node_requirements,LEC,equivalence_check,memory) "12GB"
set project(lsf,node_requirements,LEC,equivalence_check,cpu) "4"
set project(lsf,node_requirements,LEC,equivalence_check,runtime_estimate) "1.5"

# Node-specific resource requirements — EMIR
set project(lsf,node_requirements,EMIR,inputs,queue) "S"
set project(lsf,node_requirements,EMIR,inputs,memory) "4GB"
set project(lsf,node_requirements,EMIR,inputs,cpu) "2"
set project(lsf,node_requirements,EMIR,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,EMIR,ir_analysis,queue) "M"
set project(lsf,node_requirements,EMIR,ir_analysis,memory) "16GB"
set project(lsf,node_requirements,EMIR,ir_analysis,cpu) "8"
set project(lsf,node_requirements,EMIR,ir_analysis,runtime_estimate) "3.0"

set project(lsf,node_requirements,EMIR,em_analysis,queue) "M"
set project(lsf,node_requirements,EMIR,em_analysis,memory) "16GB"
set project(lsf,node_requirements,EMIR,em_analysis,cpu) "8"
set project(lsf,node_requirements,EMIR,em_analysis,runtime_estimate) "2.5"

# Node-specific resource requirements — PV
set project(lsf,node_requirements,PV,inputs,queue) "S"
set project(lsf,node_requirements,PV,inputs,memory) "4GB"
set project(lsf,node_requirements,PV,inputs,cpu) "2"
set project(lsf,node_requirements,PV,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,PV,drc_check,queue) "M"
set project(lsf,node_requirements,PV,drc_check,memory) "16GB"
set project(lsf,node_requirements,PV,drc_check,cpu) "8"
set project(lsf,node_requirements,PV,drc_check,runtime_estimate) "2.5"

set project(lsf,node_requirements,PV,lvs_check,queue) "M"
set project(lsf,node_requirements,PV,lvs_check,memory) "12GB"
set project(lsf,node_requirements,PV,lvs_check,cpu) "4"
set project(lsf,node_requirements,PV,lvs_check,runtime_estimate) "2.0"

# Notification settings
set project(lsf,notifications,email_list) "denali@smartsoc.com"
set project(lsf,notifications,cost_alerts) "true"
set project(lsf,notifications,failure_alerts) "true"
set project(lsf,notifications,completion_alerts) "false"
set project(lsf,notifications,weekly_summary) "true"

# ---------------------------------------------------------------------------
# MMMC NODE SCENARIO ASSIGNMENTS
# Which scenarios to use at each PNR/STA stage (setup/hold)
# Scenario format: <mode>_<corner>_<voltage>_<rc>_<temperature>
# ---------------------------------------------------------------------------

array set mmmc {
    init_design {
        setup {func_tt_0p80v_rctyp_25c}
        hold  {func_tt_0p80v_rctyp_25c}
    }

    floorplan {
        setup {func_ss_0p76v_rcmax_150c}
        hold  {func_ff_0p84v_rcmin_m40c}
    }

    powerplan {
        setup {func_ss_0p76v_rcmax_150c}
        hold  {func_ff_0p84v_rcmin_m40c}
    }

    placement {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
        }
    }

    cts {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_150c
        }
    }

    cts_opt {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_150c
        }
    }

    route {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_150c
        }
    }

    post_route {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_150c
            func_ff_0p80v_rcmin_m40c
        }
    }

    signoff {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
            func_ss_0p80v_rcmax_150c
            func_ss_0p80v_rcmax_25c
            test_ss_0p76v_rcmax_150c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
            func_ff_0p84v_rcmin_150c
            func_ff_0p80v_rcmin_m40c
            test_ff_0p84v_rcmin_m40c
            test_ff_0p84v_rcmin_25c
        }
    }

    synthesis {
        setup {
            func_ss_0p76v_rcmax_150c
            func_ss_0p76v_rcmax_25c
            func_ss_0p76v_rcmax_m40c
        }
        hold {
            func_ff_0p84v_rcmin_m40c
            func_ff_0p84v_rcmin_25c
        }
    }
}
