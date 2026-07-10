#!/usr/bin/env tclsh
# ============================================================================
# CBflow - Bumblebee Project Configuration
# Description: Bumblebee project-specific parameters
# ============================================================================

# Project identification
set project(name) "bumblebee"

# Phase timeline for this project (project-specific — flow(phases) is deprecated).
set project(phases)          {LC1 LC2 LC3 LC4 LC5}
set project(current_phase)   "LC1"
set project(version) "1.0"
set project(cbflow_release) "v1.0.0"   ;# CBflow release version for this project
set project(description) "Bumblebee chip design project"
set project(owner) "Bumblebee Design Team"
set project(contact) "bumblebee@company.com"

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
set project(technology) "gf_22nm"
set project(track_variant) "9T"
set project(metal_stack) "11M"
set project(vt_flavors) "svt lvt hvt"
set project(lib_config_tag) "LIB01"
set project(lib_root) "/tmp/test_libs/gf_22nm"

# Design hierarchy
set project(top_module) "bumblebee_top"

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

# Feature toggles
set project(autoppt,enabled) "false"         ;# Enable AutoPPT summary generation (requires python-pptx)

# Custom settings
set project(custom,scripts) "bumblebee_hooks.tcl"
set project(custom,constraints) "bumblebee_constraints.sdc"
set project(custom,hooks) "bumblebee_custom.tcl"
set project(custom,waivers) "bumblebee_waivers.tcl"
set project(custom,config_files) "bumblebee_extra.tcl"

# ---------------------------------------------------------------------------
# RELEASE CONFIGURATION
# ---------------------------------------------------------------------------

# RACE DB Path
# DB structure: $db_path/$project_name/$domain/$flow_type/$user_$run_name.db
set project(race,db_path) "/Users/vmerugu/projects/CBflow_clone/.race_area"

# Dashboard byline — override the default "SmartSoc Solutions Pvt Limited" credit
set project(dashboard,developed_by) "SmartSoC and MIPS"

# Release Path Configuration
# Release path structure: $release_path/$phase/$block_name/$release_tag
set project(release,path) "/Users/vmerugu/projects/CBflow_clone/test_releases"
set project(release,phase) "LC1"
set project(release,block_name) ""
set project(release,active_tag) "BTO"
set project(release,expiry_date) "2027-06-30"
set project(tapeout_date) "2026-12-07"          ;# ISO date — drives "Weeks to tapeout" on dashboard

# ---------------------------------------------------------------------------
# LSF RESOURCE MANAGEMENT
# ---------------------------------------------------------------------------

set project(lsf,enabled) "true"
set project(lsf,version) "1.0.0"
set project(lsf,config_date) "2025-10-08"

# Default LSF settings
set project(lsf,default_queue) "M"
set project(lsf,emergency_queue) "ultra"

# Project resource constraints
set project(lsf,max_concurrent_jobs) "25"
set project(lsf,max_daily_cost) "1000.00"        ;# USD
set project(lsf,priority_class) "normal"         ;# normal, high, critical

# Notification settings
set project(lsf,notifications,email_list) "bumblebee@company.com"
set project(lsf,notifications,cost_alerts) "true"
set project(lsf,notifications,failure_alerts) "true"
set project(lsf,notifications,completion_alerts) "false"
set project(lsf,notifications,weekly_summary) "true"

# ─────────────────────────────────────────────────────────────────────────────
# Design content + waivers (cross-project schema parity)
# ─────────────────────────────────────────────────────────────────────────────
set project(analog_blocks) "pll_block adc_block"
set project(validation,post_route_waivers) {    ".*[Ww]arning.*timing.*violation.*less.*than.*0\\.1ns.*"    ".*[Ww]arning.*hold.*time.*violation.*less.*than.*50ps.*"
    ".*[Ww]arning.*optimization.*convergence.*"
}
set project(validation,powerplan_waivers) {    ".*[Ww]arning.*power.*stripe.*spacing.*"    ".*[Ww]arning.*via.*stack.*"
    ".*[Ww]arning.*power.*domain.*"
}
set project(validation,SIGNOFF_waivers) {
    ".*[Ww]arning.*signoff.*quality.*"  ".*[Ww]arning.*verification.*"
}

# ═════════════════════════════════════════════════════════════════════════════
# MULTI-LINE VALUE BLOCKS (kept at the bottom so cross-project line-number
# parity holds for every single-line set project(...) key above.
# ═════════════════════════════════════════════════════════════════════════════

# ---------------------------------------------------------------------------
# DESIGN INFORMATION
# ---------------------------------------------------------------------------

# Simple hierarchy: denali_top (DL1) -> tom (DL2)
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

# Default Synopsys tools
set project(default_tools) {
    SYNTH    "fc"
    PNR      "fc"
    STA      "pt"
    LEC      "formality"
    CLP      "vc_lp"
    EMIR     "redhawk"
    PV       "icv"
}

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
    ".*[Ww]arning.*timing.*library.*missing.*"
}

set project(validation,floorplan_waivers) {
    ".*[Ww]arning.*macro.*overlap.*"
    ".*[Ww]arning.*placement.*density.*"
    ".*[Ww]arning.*utilization.*target.*"
    ".*[Ee]rror.*floorplan.*aspect.*ratio.*"
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

# Release directory sub-structure
set project(release,structure) {
    "netlist" "sdc" "def" "gds" "spef" "upf"
    "reports" "data" "db" "docs"
}

# ─────────────────────────────────────────────────────────────────────────────
# Derived: valid_design_names — depends on design_hierarchy above, so this
# line must come AFTER design_hierarchy is defined.
# ─────────────────────────────────────────────────────────────────────────────
# Generate valid design names from hierarchy
set project(valid_design_names) [dict keys $project(design_hierarchy)]

# ─────────────────────────────────────────────────────────────────────────────
# Derived: project(block_list) — the DL2 subsystems of design_hierarchy.
# Consumed by FCFP/FP init_design_fc.tcl for hierarchical NDM loading.
# ─────────────────────────────────────────────────────────────────────────────
set _blk_list {}
dict for {_blk _spec} $project(design_hierarchy) {
    if {[dict exists $_spec level] && [dict get $_spec level] eq "DL2"} {
        lappend _blk_list $_blk
    }
}
set project(block_list) $_blk_list
unset _blk_list _blk _spec
