#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow - Consolidated Config for SYNTH_PNR route1 (route1_default)
# Generated: Thu May 21 09:49:07 IST 2026
# Description: Main configs sourced, overrides expanded with validation
# ═══════════════════════════════════════════════════════════════════════════════

# Environment setup
if {[info exists ::env(FLOW_DIR)]} {
    set FLOW_DIR $::env(FLOW_DIR)
} else {
    set FLOW_DIR "/Users/vmerugu/projects/CBflow_clone/PD"
}
if {[info exists ::env(RUN_DIR)]} {
    set RUN_DIR $::env(RUN_DIR)
} else {
    set RUN_DIR "/Users/vmerugu/projects/CBflow_clone/workarea_test/P0_run_SYNTH_PNR_test1"
}
if {[info exists ::env(PROJECT_VERSION)]} {
    set PROJECT_VERSION $::env(PROJECT_VERSION)
} else {
    set PROJECT_VERSION "v1.0.0"
}
if {[info exists ::env(FLOW_VERSION)]} {
    set FLOW_VERSION $::env(FLOW_VERSION)
} else {
    set FLOW_VERSION "v1.0.0"
}
if {[info exists ::env(TECH_VERSION)]} {
    set TECH_VERSION $::env(TECH_VERSION)
} else {
    set TECH_VERSION "v1.0.0"
}
if {[info exists ::env(TECH_NAME)]} {
    set TECH_NAME $::env(TECH_NAME)
} else {
    set TECH_NAME "gf_22nm"
}
if {[info exists ::env(TOOL_VERSION)]} {
    set TOOL_VERSION $::env(TOOL_VERSION)
} else {
    set TOOL_VERSION "v1.0.0"
}

global synth_pnr synth pnr project tech flow

puts "INFO: Loading consolidated config for SYNTH_PNR route1 (route1_default)"

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN CONFIGURATION FILES (SOURCED)
# ═══════════════════════════════════════════════════════════════════════════════

# Source cbflow_init_config
if {[file exists "$FLOW_DIR/config/project/ravendrive/v1.0.0/cbflow_init_config.tcl"]} {
    puts "INFO: Loading cbflow_init_config: $FLOW_DIR/config/project/ravendrive/v1.0.0/cbflow_init_config.tcl"
    source "$FLOW_DIR/config/project/ravendrive/v1.0.0/cbflow_init_config.tcl"
} else {
    puts "WARNING: cbflow_init_config not found: $FLOW_DIR/config/project/ravendrive/v1.0.0/cbflow_init_config.tcl"
}

# Source project_config
if {[file exists "$FLOW_DIR/config/project/ravendrive/v1.0.0/ravendrive_config.tcl"]} {
    puts "INFO: Loading project_config: $FLOW_DIR/config/project/ravendrive/v1.0.0/ravendrive_config.tcl"
    source "$FLOW_DIR/config/project/ravendrive/v1.0.0/ravendrive_config.tcl"
} else {
    puts "WARNING: project_config not found: $FLOW_DIR/config/project/ravendrive/v1.0.0/ravendrive_config.tcl"
}

# Source team_config
if {[file exists "$FLOW_DIR/config/project/ravendrive/v1.0.0/team_config.tcl"]} {
    puts "INFO: Loading team_config: $FLOW_DIR/config/project/ravendrive/v1.0.0/team_config.tcl"
    source "$FLOW_DIR/config/project/ravendrive/v1.0.0/team_config.tcl"
} else {
    puts "WARNING: team_config not found: $FLOW_DIR/config/project/ravendrive/v1.0.0/team_config.tcl"
}

# Source technology_config
if {[file exists "$FLOW_DIR/config/tech/gf_22nm/v1.0.0/tech_config.tcl"]} {
    puts "INFO: Loading technology_config: $FLOW_DIR/config/tech/gf_22nm/v1.0.0/tech_config.tcl"
    source "$FLOW_DIR/config/tech/gf_22nm/v1.0.0/tech_config.tcl"
} else {
    puts "WARNING: technology_config not found: $FLOW_DIR/config/tech/gf_22nm/v1.0.0/tech_config.tcl"
}

# Source flow_config
if {[file exists "$FLOW_DIR/config/flow/v1.0.0/flow_config.tcl"]} {
    puts "INFO: Loading flow_config: $FLOW_DIR/config/flow/v1.0.0/flow_config.tcl"
    source "$FLOW_DIR/config/flow/v1.0.0/flow_config.tcl"
} else {
    puts "WARNING: flow_config not found: $FLOW_DIR/config/flow/v1.0.0/flow_config.tcl"
}

# Source node_config_SYNTH_PNR
if {[file exists "$FLOW_DIR/config/flow/v1.0.0/node_configs/SYNTH_PNR_config.tcl"]} {
    puts "INFO: Loading node_config_SYNTH_PNR: $FLOW_DIR/config/flow/v1.0.0/node_configs/SYNTH_PNR_config.tcl"
    source "$FLOW_DIR/config/flow/v1.0.0/node_configs/SYNTH_PNR_config.tcl"
} else {
    puts "WARNING: node_config_SYNTH_PNR not found: $FLOW_DIR/config/flow/v1.0.0/node_configs/SYNTH_PNR_config.tcl"
}

# Source mmmc_config
if {[file exists "$FLOW_DIR/config/flow/v1.0.0/mmmc_config.tcl"]} {
    puts "INFO: Loading mmmc_config: $FLOW_DIR/config/flow/v1.0.0/mmmc_config.tcl"
    source "$FLOW_DIR/config/flow/v1.0.0/mmmc_config.tcl"
} else {
    puts "WARNING: mmmc_config not found: $FLOW_DIR/config/flow/v1.0.0/mmmc_config.tcl"
}

# Source user_config
if {[file exists "$RUN_DIR/setup/user_config.tcl"]} {
    puts "INFO: Loading user_config: $RUN_DIR/setup/user_config.tcl"
    source "$RUN_DIR/setup/user_config.tcl"
} else {
    puts "WARNING: user_config not found: $RUN_DIR/setup/user_config.tcl"
}

puts "INFO: Consolidated configuration loading complete for SYNTH_PNR route1 (route1_default)"
