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

# Design constraints
set project(clock,period) "2.0"
set project(clock,ports) "clk sys_clk ref_clk"
set project(clock,uncertainty) "0.1"
set project(clock,latency) "0.2"
set project(clock,frequency) "500000000"

# SDC Mode Definitions (used for file naming: <design_name>.<mode>.sdc)
set project(sdc_modes) {func scan test dft}
set project(default_sdc_mode) "func"

# Reset constraints
set project(reset,ports) "rst_n sys_rst_n"
set project(reset,polarity) "active_low"
set project(reset,async) "true"

# I/O constraints
set project(io,voltage) "1.8"
set project(io,drive_strength) "4"
set project(io,slew_rate) "slow"
set project(io,placement) "ravendrive_io.def"
set project(io,count) "256"

# Power intent
set project(power,domains) "PD_CPU PD_MEM PD_IO PD_TOP"
set project(power,states) "ON OFF RETENTION"
set project(power,switches) "sw_cpu sw_mem"
set project(power,isolation) "iso_cpu iso_mem"
set project(power,retention) "ret_cpu ret_mem"

# Design size estimates
set project(estimated_area) "5000000"
set project(estimated_power) "250"
set project(gate_count) "250000"
set project(register_count) "25000"
set project(memory_bits) "8388608"

# Technology targets
set project(target,frequency) "500"
set project(target,power) "200"
set project(target,area) "4500000"
set project(target,yield) "98"

# Test and verification
set project(dft,scan_chains) "8"
set project(dft,coverage_target) "98"
set project(dft,compression) "true"
set project(verification,formal) "true"
set project(verification,simulation) "true"

# Ravendrive-specific settings
set project(ravendrive,cpu_type) "RISC-V"
set project(ravendrive,isa) "RV32I"
set project(ravendrive,cache_size) "32KB"
set project(ravendrive,memory_map) "ravendrive_memmap.tcl"

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

# Add missing hierarchical variables for legacy compatibility
set project(target,utilization) 0.75
set project(target,aspect_ratio) 1.0

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
set project(lsf,selection_strategy) "ml_optimized"
set project(lsf,cost_optimization) "true"
set project(lsf,ml_analytics) "true"

# Project resource constraints
set project(lsf,max_concurrent_jobs) "25"
set project(lsf,max_daily_cost) "1000.00"     ; # USD
set project(lsf,priority_class) "normal"      ; # normal, high, critical
set project(lsf,budget_alert_threshold) "0.8" ; # 80% of budget

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
set project(lsf,node_requirements,FP,inputs,queue) "S"
set project(lsf,node_requirements,FP,inputs,memory) "4GB"
set project(lsf,node_requirements,FP,inputs,cpu) "2"
set project(lsf,node_requirements,FP,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,FP,floorplan,queue) "M"
set project(lsf,node_requirements,FP,floorplan,memory) "16GB"
set project(lsf,node_requirements,FP,floorplan,cpu) "8"
set project(lsf,node_requirements,FP,floorplan,runtime_estimate) "1.5"

set project(lsf,node_requirements,FP,powerplan,queue) "L"
set project(lsf,node_requirements,FP,powerplan,memory) "24GB"
set project(lsf,node_requirements,FP,powerplan,cpu) "12"
set project(lsf,node_requirements,FP,powerplan,runtime_estimate) "2.5"

set project(lsf,node_requirements,FP,post_floorplan,queue) "M"
set project(lsf,node_requirements,FP,post_floorplan,memory) "16GB"
set project(lsf,node_requirements,FP,post_floorplan,cpu) "8"
set project(lsf,node_requirements,FP,post_floorplan,runtime_estimate) "1.0"

# PNR Flow Node Requirements (Most Resource Intensive)
set project(lsf,node_requirements,PNR,inputs,queue) "S"
set project(lsf,node_requirements,PNR,inputs,memory) "4GB"
set project(lsf,node_requirements,PNR,inputs,cpu) "2"
set project(lsf,node_requirements,PNR,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,PNR,import_design,queue) "M"
set project(lsf,node_requirements,PNR,import_design,memory) "16GB"
set project(lsf,node_requirements,PNR,import_design,cpu) "8"
set project(lsf,node_requirements,PNR,import_design,runtime_estimate) "1.0"

set project(lsf,node_requirements,PNR,floorplan,queue) "M"
set project(lsf,node_requirements,PNR,floorplan,memory) "16GB"
set project(lsf,node_requirements,PNR,floorplan,cpu) "8"
set project(lsf,node_requirements,PNR,floorplan,runtime_estimate) "1.5"

set project(lsf,node_requirements,PNR,powerplan,queue) "L"
set project(lsf,node_requirements,PNR,powerplan,memory) "32GB"
set project(lsf,node_requirements,PNR,powerplan,cpu) "16"
set project(lsf,node_requirements,PNR,powerplan,runtime_estimate) "3.0"

set project(lsf,node_requirements,PNR,placement,queue) "L"
set project(lsf,node_requirements,PNR,placement,memory) "32GB"
set project(lsf,node_requirements,PNR,placement,cpu) "16"
set project(lsf,node_requirements,PNR,placement,runtime_estimate) "4.0"

set project(lsf,node_requirements,PNR,cts,queue) "L"
set project(lsf,node_requirements,PNR,cts,memory) "32GB"
set project(lsf,node_requirements,PNR,cts,cpu) "16"
set project(lsf,node_requirements,PNR,cts,runtime_estimate) "3.5"

set project(lsf,node_requirements,PNR,route,queue) "XL"
set project(lsf,node_requirements,PNR,route,memory) "64GB"
set project(lsf,node_requirements,PNR,route,cpu) "32"
set project(lsf,node_requirements,PNR,route,runtime_estimate) "8.0"

set project(lsf,node_requirements,PNR,route_opt,queue) "XL"
set project(lsf,node_requirements,PNR,route_opt,memory) "64GB"
set project(lsf,node_requirements,PNR,route_opt,cpu) "32"
set project(lsf,node_requirements,PNR,route_opt,runtime_estimate) "6.0"

set project(lsf,node_requirements,PNR,post_route,queue) "L"
set project(lsf,node_requirements,PNR,post_route,memory) "32GB"
set project(lsf,node_requirements,PNR,post_route,cpu) "16"
set project(lsf,node_requirements,PNR,post_route,runtime_estimate) "2.0"

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

set project(lsf,node_requirements,LEC,equivalence_check,queue) "M"
set project(lsf,node_requirements,LEC,equivalence_check,memory) "16GB"
set project(lsf,node_requirements,LEC,equivalence_check,cpu) "8"
set project(lsf,node_requirements,LEC,equivalence_check,runtime_estimate) "2.5"

# EMIR Flow Node Requirements
set project(lsf,node_requirements,EMIR,inputs,queue) "S"
set project(lsf,node_requirements,EMIR,inputs,memory) "4GB"
set project(lsf,node_requirements,EMIR,inputs,cpu) "2"
set project(lsf,node_requirements,EMIR,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,EMIR,ir_analysis,queue) "L"
set project(lsf,node_requirements,EMIR,ir_analysis,memory) "32GB"
set project(lsf,node_requirements,EMIR,ir_analysis,cpu) "16"
set project(lsf,node_requirements,EMIR,ir_analysis,runtime_estimate) "5.0"

set project(lsf,node_requirements,EMIR,em_analysis,queue) "L"
set project(lsf,node_requirements,EMIR,em_analysis,memory) "32GB"
set project(lsf,node_requirements,EMIR,em_analysis,cpu) "16"
set project(lsf,node_requirements,EMIR,em_analysis,runtime_estimate) "4.5"

set project(lsf,node_requirements,EMIR,si_analysis,queue) "XL"
set project(lsf,node_requirements,EMIR,si_analysis,memory) "64GB"
set project(lsf,node_requirements,EMIR,si_analysis,cpu) "32"
set project(lsf,node_requirements,EMIR,si_analysis,runtime_estimate) "7.0"

# PV Flow Node Requirements
set project(lsf,node_requirements,PV,inputs,queue) "S"
set project(lsf,node_requirements,PV,inputs,memory) "4GB"
set project(lsf,node_requirements,PV,inputs,cpu) "2"
set project(lsf,node_requirements,PV,inputs,runtime_estimate) "0.25"

set project(lsf,node_requirements,PV,drc_check,queue) "L"
set project(lsf,node_requirements,PV,drc_check,memory) "32GB"
set project(lsf,node_requirements,PV,drc_check,cpu) "16"
set project(lsf,node_requirements,PV,drc_check,runtime_estimate) "4.0"

set project(lsf,node_requirements,PV,lvs_check,queue) "L"
set project(lsf,node_requirements,PV,lvs_check,memory) "24GB"
set project(lsf,node_requirements,PV,lvs_check,cpu) "12"
set project(lsf,node_requirements,PV,lvs_check,runtime_estimate) "3.5"

# ═══════════════════════════════════════════════════════════════════════════════
# DESIGN COMPLEXITY-BASED SCALING FACTORS
# ═══════════════════════════════════════════════════════════════════════════════

# Ravendrive-specific scaling based on design characteristics
set project(lsf,complexity_scaling,gate_count_threshold) "500000"  ; # gates
set project(lsf,complexity_scaling,memory_scaling_factor) "1.5"    ; # 50% more memory for large designs
set project(lsf,complexity_scaling,cpu_scaling_factor) "1.3"       ; # 30% more CPUs for large designs

# Hierarchical design scaling
set project(lsf,hierarchical_scaling,enabled) "true"
set project(lsf,hierarchical_scaling,block_count_threshold) "10"   ; # blocks
set project(lsf,hierarchical_scaling,resource_multiplier) "1.8"    ; # 80% more resources for hierarchical

# Memory estimation based on design size
set project(lsf,memory_estimation,base_memory_per_kgate) "0.1"     ; # GB per 1K gates
set project(lsf,memory_estimation,routing_memory_multiplier) "2.5" ; # Routing needs 2.5x more memory
set project(lsf,memory_estimation,signoff_memory_multiplier) "3.0" ; # Signoff needs 3x more memory

# ═══════════════════════════════════════════════════════════════════════════════
# COST BUDGETS AND CONSTRAINTS
# ═══════════════════════════════════════════════════════════════════════════════

# Ravendrive project cost budgets
set project(lsf,budget,daily_limit) "1000.00"          ; # USD per day
set project(lsf,budget,weekly_limit) "5000.00"         ; # USD per week
set project(lsf,budget,monthly_limit) "20000.00"       ; # USD per month
set project(lsf,budget,emergency_allowance) "2000.00"  ; # USD for emergency queue usage

# Cost allocation by flow type
set project(lsf,budget,allocation,SYNTH) "15"    ; # 15% of budget
set project(lsf,budget,allocation,FP) "10"       ; # 10% of budget
set project(lsf,budget,allocation,PNR) "50"      ; # 50% of budget (most expensive)
set project(lsf,budget,allocation,STA) "10"      ; # 10% of budget
set project(lsf,budget,allocation,LEC) "5"       ; # 5% of budget
set project(lsf,budget,allocation,EMIR) "8"      ; # 8% of budget
set project(lsf,budget,allocation,PV) "2"      ; # 2% of budget

# ═══════════════════════════════════════════════════════════════════════════════
# ML ANALYTICS SETTINGS
# ═══════════════════════════════════════════════════════════════════════════════

# Ravendrive project ML analytics configuration
set project(lsf,ml,learning_enabled) "true"
set project(lsf,ml,data_collection_level) "detailed"   ; # basic, detailed, comprehensive
set project(lsf,ml,model_training_frequency) "weekly"
set project(lsf,ml,prediction_accuracy_target) "0.85"  ; # 85% accuracy
set project(lsf,ml,historical_data_retention) "180"    ; # days

# Ravendrive-specific ML features
set project(lsf,ml,features,design_characteristics) {
    "gate_count" "register_count" "memory_bits" "macro_count"
    "hierarchy_depth" "clock_domains" "power_domains"
}
set project(lsf,ml,features,runtime_characteristics) {
    "previous_runtime" "design_complexity_score" "tool_version"
    "optimization_level" "target_frequency" "utilization_target"
}

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
set project(lsf,alerts,cost_warning_threshold) "0.7"     ; # 70% of daily budget
set project(lsf,alerts,cost_critical_threshold) "0.9"    ; # 90% of daily budget
set project(lsf,alerts,job_failure_rate_threshold) "0.05" ; # 5% failure rate
set project(lsf,alerts,long_wait_time_threshold) "3600"  ; # 1 hour wait time

# ═══════════════════════════════════════════════════════════════════════════════
# QUALITY OF SERVICE (QoS)
# ═══════════════════════════════════════════════════════════════════════════════

# Ravendrive project QoS settings
set project(lsf,qos,deadline_aware_scheduling) "true"
set project(lsf,qos,priority_boost_for_critical_path) "true"
set project(lsf,qos,resource_reservation_for_tapeout) "true"
set project(lsf,qos,load_balancing_preference) "cost_optimized"  ; # performance_optimized, cost_optimized, balanced

# SLA (Service Level Agreement) targets
set project(lsf,sla,job_start_time_target) "300"        ; # seconds
set project(lsf,sla,resource_availability_target) "0.95" ; # 95% availability
set project(lsf,sla,cost_predictability_variance) "0.1"  ; # 10% variance from estimate
set project(lsf,sla,completion_time_accuracy) "0.8"     ; # 80% of jobs complete within estimated time

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

