#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# OMNI FLOW - Ravendrive Project Configuration
# Description: Ravendrive project-specific parameters
# ═══════════════════════════════════════════════════════════════════════════════

# Project identification
set project(name) "ravendrive"
set project(version) "1.0"
set project(cbflow_release) "v1.0.0"   ;# CBflow release version for this project
set project(description) "Ravendrive chip design project"
set project(owner) "Ravendrive Design Team"
set project(contact) "ravendrive@company.com"

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

# Track variant selection
# Available: 9T (high performance), 7.5T (balanced), 6.75T (high density)
set project(technology) "gf_22nm"
set project(track_variant) "9T"
set project(metal_stack) "11M"
set project(vt_flavors) "svt lvt hvt"
set project(lib_config_tag) "P0"
set project(lib_root) "/tmp/test_libs/gf_22nm"


# Design hierarchy
set project(top_module) "ravendrive_top"
set project(block_list) "cpu_core memory_ctrl io_ctrl"
set project(macro_list) "sram_macro rom_macro"
set project(memory_list) "cache_mem data_mem inst_mem"
set project(analog_blocks) "pll_block adc_block"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         DESIGN INFORMATION                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

# Design hierarchy with parent-child relationships
# DL1 - Full chip top level
set project(full_chip) "chip_top"

# Hierarchical partitions with parent-child linking
# Structure: {name {description parent children}}
set project(design_hierarchy) {
    chip_top {
        description "Full chip top level (DL1)"
        level "DL1"
        parent ""
        children {cpu_complex memory_subsys io_subsys power_mgmt}
    }

    cpu_complex {
        description "CPU and cache subsystem (DL2)"
        level "DL2"
        parent "chip_top"
        children {cpu_core l1_cache l2_cache}
    }

    memory_subsys {
        description "Memory controller and interfaces (DL2)"
        level "DL2"
        parent "chip_top"
        children {ddr_ctrl mem_arbiter}
    }

    io_subsys {
        description "I/O controllers and peripherals (DL2)"
        level "DL2"
        parent "chip_top"
        children {pcie_ctrl gpio_ctrl uart_ctrl spi_ctrl}
    }

    power_mgmt {
        description "Power management unit (DL2)"
        level "DL2"
        parent "chip_top"
        children {power_ctrl clock_mgr reset_ctrl}
    }

    cpu_core {
        description "Main CPU processing core (DL3)"
        level "DL3"
        parent "cpu_complex"
        children {alu fetch_unit decode_unit}
    }

    l1_cache {
        description "Level 1 cache controller (DL3)"
        level "DL3"
        parent "cpu_complex"
        children {}
    }

    l2_cache {
        description "Level 2 cache controller (DL3)"
        level "DL3"
        parent "cpu_complex"
        children {}
    }

    ddr_ctrl {
        description "DDR memory controller (DL3)"
        level "DL3"
        parent "memory_subsys"
        children {}
    }

    mem_arbiter {
        description "Memory arbiter (DL3)"
        level "DL3"
        parent "memory_subsys"
        children {}
    }

    pcie_ctrl {
        description "PCIe controller (DL3)"
        level "DL3"
        parent "io_subsys"
        children {}
    }

    gpio_ctrl {
        description "GPIO controller (DL3)"
        level "DL3"
        parent "io_subsys"
        children {}
    }

    uart_ctrl {
        description "UART controller (DL3)"
        level "DL3"
        parent "io_subsys"
        children {}
    }

    spi_ctrl {
        description "SPI controller (DL3)"
        level "DL3"
        parent "io_subsys"
        children {}
    }

    power_ctrl {
        description "Power control unit (DL3)"
        level "DL3"
        parent "power_mgmt"
        children {}
    }

    clock_mgr {
        description "Clock manager (DL3)"
        level "DL3"
        parent "power_mgmt"
        children {}
    }

    reset_ctrl {
        description "Reset controller (DL3)"
        level "DL3"
        parent "power_mgmt"
        children {}
    }

    alu {
        description "Arithmetic Logic Unit (DL4)"
        level "DL4"
        parent "cpu_core"
        children {}
    }

    fetch_unit {
        description "Instruction fetch unit (DL4)"
        level "DL4"
        parent "cpu_core"
        children {}
    }

    decode_unit {
        description "Instruction decode unit (DL4)"
        level "DL4"
        parent "cpu_core"
        children {}
    }
}

# Generate valid design names from hierarchy
set project(valid_design_names) [dict keys $project(design_hierarchy)]

# Clock constraints (only `period` and `ports` are read downstream — used by
# inputs_innovus.tcl for display/logging. The authoritative clock spec comes
# from the SDC file referenced by `operating_modes(<mode>,constraint_file)`,
# not from these keys.)
set project(clock,period) "2.0"
set project(clock,ports) "clk sys_clk ref_clk"

# SDC Mode Definitions (used for file naming: <design_name>.<mode>.sdc)
set project(sdc_modes) {func scan test dft}
set project(default_sdc_mode) "func"

# Power & Ground Nets (consumed by init_design/PNR — top-level SoC-wide)
set project(power,vdd_net) "VDD"
set project(power,vss_net) "VSS"
set project(power,vdd_pin) "VDD"
set project(power,vss_pin) "VSS"

# Block-level specs (clock uncertainty, target frequency/power/area, reset
# ports, I/O voltage, power domains, design-size estimates) used to live
# here as `project(target,*)`, `project(estimated_*)`, `project(io,*)`,
# `project(reset,*)`, `project(power,domains|states|switches|isolation|
# retention)`. They were unread by any cmd handler and removed in the
# cleanup commit. Block-shaped specs belong in user_config or a per-block
# `<block_name>_floorplan.tcl`, not in this project-wide config.

# Test and verification
set project(dft,scan_chains) "8"
set project(dft,coverage_target) "98"
set project(dft,compression) "true"
set project(verification,formal) "true"
set project(verification,simulation) "true"

# Ravendrive-specific settings

# Feature toggles
set project(autoppt,enabled) "false"         ;# Enable AutoPPT summary generation (requires python-pptx)

# Custom settings
set project(custom,scripts) "ravendrive_hooks.tcl"
set project(custom,constraints) "ravendrive_constraints.sdc"
set project(custom,hooks) "ravendrive_custom.tcl"
set project(custom,waivers) "ravendrive_waivers.tcl"
set project(custom,config_files) "ravendrive_extra.tcl"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         VALIDATION WAIVER PATTERNS                         │
# └─────────────────────────────────────────────────────────────────────────────┘

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
    ".*[Ww]arning.*timing.*library.*missing.*"
}

set project(validation,floorplan_waivers) {
    ".*[Ww]arning.*macro.*overlap.*"
    ".*[Ww]arning.*placement.*density.*"
    ".*[Ww]arning.*utilization.*target.*"
    ".*[Ee]rror.*floorplan.*aspect.*ratio.*"
}

set project(validation,powerplan_waivers) {
    ".*[Ww]arning.*power.*stripe.*spacing.*"
    ".*[Ww]arning.*via.*stack.*"
    ".*[Ww]arning.*power.*domain.*"
}

set project(validation,cts_waivers) {
    ".*[Ww]arning.*clock.*tree.*balance.*"
    ".*[Ww]arning.*clock.*latency.*"
    ".*[Ww]arning.*useful.*skew.*"
}

set project(validation,route_waivers) {
    ".*[Ww]arning.*antenna.*violation.*"
    ".*[Ww]arning.*routing.*congestion.*"
    ".*[Ww]arning.*via.*pillar.*"
}

set project(validation,post_route_waivers) {
    ".*[Ww]arning.*timing.*violation.*less.*than.*0\\.1ns.*"
    ".*[Ww]arning.*hold.*time.*violation.*less.*than.*50ps.*"
    ".*[Ww]arning.*optimization.*convergence.*"
}

set project(validation,signoff_waivers) {
    ".*[Ww]arning.*final.*timing.*report.*"
    ".*[Ww]arning.*design.*margin.*"
}

# Flow-specific validation waivers
set project(validation,PNR_waivers) {
    ".*[Ww]arning.*place.*and.*route.*"
    ".*[Ww]arning.*physical.*verification.*"
}

set project(validation,SYNTH_waivers) {
    ".*[Ww]arning.*synthesis.*optimization.*"
    ".*[Ww]arning.*logic.*optimization.*"
}

set project(validation,SIGNOFF_waivers) {
    ".*[Ww]arning.*signoff.*quality.*"
    ".*[Ww]arning.*verification.*"
}

# Ravendrive-specific critical error patterns that should NEVER be waivered
set project(validation,critical_errors) {
    ".*[Ee]rror.*license.*"
    ".*[Ee]rror.*tool.*crash.*"
    ".*[Ee]rror.*segmentation.*fault.*"
    ".*[Ee]rror.*memory.*allocation.*"
    ".*[Ff]atal.*"
    ".*[Aa]bort.*"
    ".*[Cc]ore.*dumped.*"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         RELEASE CONFIGURATION                              │
# └─────────────────────────────────────────────────────────────────────────────┘

# Ravendrive project release settings
# ── RACE DB Path ──────────────────────────────────────────────────
# DB structure: $db_path/$project_name/$domain/$flow_type/$user_$run_name.db
set project(race,db_path) "/proj/ravendrive/race_db"

set project(release,author) "Ravendrive Design Team"
set project(release,organization) "GF 22FDX Design Group"

# ── Release Path Configuration ───────────────────────────────────────────────
# Release path structure: $release_path/$phase/$block_name/$release_tag
# Example: /proj/ravendrive/releases/P2/top_chip/v1.0.2
set project(release,path) "/Users/vmerugu/projects/CBflow_clone/test_releases"
set project(release,phase) "P0"
set project(release,block_name) ""
set project(release,active_tag) "BTO"
set project(release,expiry_date) "2026-06-30"

# Release directory sub-structure
set project(release,structure) {
    "netlist" "sdc" "def" "gds" "spef" "upf"
    "reports" "data" "db" "docs"
}

# Release settings
set project(release,include_timestamp) "false"
set project(release,generate_notes) "true"
set project(release,validate_mandatory) "true"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         LSF RESOURCE MANAGEMENT                            │
# └─────────────────────────────────────────────────────────────────────────────┘

# Ravendrive Project LSF Configuration
set project(lsf,enabled) "true"
set project(lsf,version) "1.0.0"
set project(lsf,config_date) "2025-10-08"

# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT-LEVEL LSF DEFAULTS
# ═══════════════════════════════════════════════════════════════════════════════

# Default LSF settings for Ravendrive project
set project(lsf,default_queue) "M"
set project(lsf,emergency_queue) "ultra"

# Project resource constraints
set project(lsf,max_concurrent_jobs) "25"
set project(lsf,max_daily_cost) "1000.00"     ; # USD
set project(lsf,priority_class) "normal"      ; # normal, high, critical

# ═══════════════════════════════════════════════════════════════════════════════
# NODE-SPECIFIC RESOURCE REQUIREMENTS
# ═══════════════════════════════════════════════════════════════════════════════

# SYNTH Flow Node Requirements
set project(lsf,node_requirements,SYNTH,inputs,queue) "S"
set project(lsf,node_requirements,SYNTH,inputs,memory) "4GB"
set project(lsf,node_requirements,SYNTH,inputs,cpu) "2"
set project(lsf,node_requirements,SYNTH,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,SYNTH,synthesis,queue) "M"
set project(lsf,node_requirements,SYNTH,synthesis,memory) "12GB"
set project(lsf,node_requirements,SYNTH,synthesis,cpu) "6"
set project(lsf,node_requirements,SYNTH,synthesis,runtime_estimate) "2.0"

set project(lsf,node_requirements,SYNTH,export_data,queue) "S"
set project(lsf,node_requirements,SYNTH,export_data,memory) "4GB"
set project(lsf,node_requirements,SYNTH,export_data,cpu) "2"
set project(lsf,node_requirements,SYNTH,export_data,runtime_estimate) "0.5"

# FP Flow Node Requirements




# PNR Flow Node Requirements (Most Resource Intensive)
set project(lsf,node_requirements,PNR,inputs,queue) "S"
set project(lsf,node_requirements,PNR,inputs,memory) "4GB"
set project(lsf,node_requirements,PNR,inputs,cpu) "2"
set project(lsf,node_requirements,PNR,inputs,runtime_estimate) "0.25"





set project(lsf,node_requirements,PNR,cts,queue) "L"
set project(lsf,node_requirements,PNR,cts,memory) "32GB"
set project(lsf,node_requirements,PNR,cts,cpu) "16"
set project(lsf,node_requirements,PNR,cts,runtime_estimate) "3.5"

set project(lsf,node_requirements,PNR,route,queue) "XL"
set project(lsf,node_requirements,PNR,route,memory) "64GB"
set project(lsf,node_requirements,PNR,route,cpu) "32"
set project(lsf,node_requirements,PNR,route,runtime_estimate) "8.0"



# STA Flow Node Requirements
set project(lsf,node_requirements,STA,inputs,queue) "S"
set project(lsf,node_requirements,STA,inputs,memory) "4GB"
set project(lsf,node_requirements,STA,inputs,cpu) "2"
set project(lsf,node_requirements,STA,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,STA,extraction,queue) "L"
set project(lsf,node_requirements,STA,extraction,memory) "32GB"
set project(lsf,node_requirements,STA,extraction,cpu) "16"
set project(lsf,node_requirements,STA,extraction,runtime_estimate) "4.0"

set project(lsf,node_requirements,STA,timing,queue) "L"
set project(lsf,node_requirements,STA,timing,memory) "24GB"
set project(lsf,node_requirements,STA,timing,cpu) "12"
set project(lsf,node_requirements,STA,timing,runtime_estimate) "3.0"

# LEC Flow Node Requirements
set project(lsf,node_requirements,LEC,inputs,queue) "S"
set project(lsf,node_requirements,LEC,inputs,memory) "4GB"
set project(lsf,node_requirements,LEC,inputs,cpu) "2"
set project(lsf,node_requirements,LEC,inputs,runtime_estimate) "0.25"


# EMIR Flow Node Requirements
set project(lsf,node_requirements,EMIR,inputs,queue) "S"
set project(lsf,node_requirements,EMIR,inputs,memory) "4GB"
set project(lsf,node_requirements,EMIR,inputs,cpu) "2"
set project(lsf,node_requirements,EMIR,inputs,runtime_estimate) "0.25"




# PV Flow Node Requirements
set project(lsf,node_requirements,PV,inputs,queue) "S"
set project(lsf,node_requirements,PV,inputs,memory) "4GB"
set project(lsf,node_requirements,PV,inputs,cpu) "2"
set project(lsf,node_requirements,PV,inputs,runtime_estimate) "0.25"



# ═══════════════════════════════════════════════════════════════════════════════
# DESIGN COMPLEXITY-BASED SCALING FACTORS
# ═══════════════════════════════════════════════════════════════════════════════

# Ravendrive-specific scaling based on design characteristics

# Hierarchical design scaling

# Memory estimation based on design size

# ═══════════════════════════════════════════════════════════════════════════════
# COST BUDGETS AND CONSTRAINTS
# ═══════════════════════════════════════════════════════════════════════════════

# Ravendrive project cost budgets


# ═══════════════════════════════════════════════════════════════════════════════
# ML ANALYTICS SETTINGS
# ═══════════════════════════════════════════════════════════════════════════════



# ═══════════════════════════════════════════════════════════════════════════════
# NOTIFICATION AND ALERTING
# ═══════════════════════════════════════════════════════════════════════════════

# Ravendrive project notification settings
set project(lsf,notifications,email_list) "ravendrive@company.com"
set project(lsf,notifications,cost_alerts) "true"
set project(lsf,notifications,failure_alerts) "true"
set project(lsf,notifications,completion_alerts) "false"  ; # Too many for large flows
set project(lsf,notifications,weekly_summary) "true"

# Alert thresholds specific to Ravendrive project

# ═══════════════════════════════════════════════════════════════════════════════
# ═══════════════════════════════════════════════════════════════════════════════



# ═══════════════════════════════════════════════════════════════════════════════
# MMMC NODE SCENARIO ASSIGNMENTS
# Which scenarios to use at each PNR/STA stage (setup/hold)
# Edit these to match your project's timing closure strategy
# Scenario format: <mode>_<corner>_<voltage>_<rc>_<temperature>
# ═══════════════════════════════════════════════════════════════════════════════

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

# ─────────────────────────────────────────────────────────────────────────────
# Stage entries added to align with denali canonical schema
# ─────────────────────────────────────────────────────────────────────────────

set project(lsf,node_requirements,EMIR,ir_drop,queue) "M"
set project(lsf,node_requirements,EMIR,ir_drop,memory) "16GB"
set project(lsf,node_requirements,EMIR,ir_drop,cpu) "8"
set project(lsf,node_requirements,EMIR,ir_drop,runtime_estimate) "2.5"

set project(lsf,node_requirements,EMIR,power_analysis,queue) "M"
set project(lsf,node_requirements,EMIR,power_analysis,memory) "16GB"
set project(lsf,node_requirements,EMIR,power_analysis,cpu) "8"
set project(lsf,node_requirements,EMIR,power_analysis,runtime_estimate) "3.0"

set project(lsf,node_requirements,LEC,compare,queue) "M"
set project(lsf,node_requirements,LEC,compare,memory) "12GB"
set project(lsf,node_requirements,LEC,compare,cpu) "4"
set project(lsf,node_requirements,LEC,compare,runtime_estimate) "1.5"

set project(lsf,node_requirements,PNR,cts_opt,queue) "L"
set project(lsf,node_requirements,PNR,cts_opt,memory) "24GB"
set project(lsf,node_requirements,PNR,cts_opt,cpu) "8"
set project(lsf,node_requirements,PNR,cts_opt,runtime_estimate) "2.5"

set project(lsf,node_requirements,PNR,init_design,queue) "M"
set project(lsf,node_requirements,PNR,init_design,memory) "12GB"
set project(lsf,node_requirements,PNR,init_design,cpu) "4"
set project(lsf,node_requirements,PNR,init_design,runtime_estimate) "0.75"

set project(lsf,node_requirements,PNR,place,queue) "L"
set project(lsf,node_requirements,PNR,place,memory) "24GB"
set project(lsf,node_requirements,PNR,place,cpu) "8"
set project(lsf,node_requirements,PNR,place,runtime_estimate) "3.0"

set project(lsf,node_requirements,PNR,pro,queue) "L"
set project(lsf,node_requirements,PNR,pro,memory) "32GB"
set project(lsf,node_requirements,PNR,pro,cpu) "16"
set project(lsf,node_requirements,PNR,pro,runtime_estimate) "4.0"

set project(lsf,node_requirements,PNR,signoff,queue) "M"
set project(lsf,node_requirements,PNR,signoff,memory) "16GB"
set project(lsf,node_requirements,PNR,signoff,cpu) "8"
set project(lsf,node_requirements,PNR,signoff,runtime_estimate) "1.5"

set project(lsf,node_requirements,PV,drc,queue) "M"
set project(lsf,node_requirements,PV,drc,memory) "16GB"
set project(lsf,node_requirements,PV,drc,cpu) "8"
set project(lsf,node_requirements,PV,drc,runtime_estimate) "2.5"

set project(lsf,node_requirements,PV,lvs,queue) "M"
set project(lsf,node_requirements,PV,lvs,memory) "12GB"
set project(lsf,node_requirements,PV,lvs,cpu) "4"
set project(lsf,node_requirements,PV,lvs,runtime_estimate) "2.0"

# Default tool selections (aligned with denali canonical)
set project(default_tools) {
    SYNTH    "genus"
    PNR      "innovus"
    STA      "tempus"
    LEC      "conformal"
    CLP      "conformal_lp"
    EMIR     "voltus"
    PV       "calibre"
}
