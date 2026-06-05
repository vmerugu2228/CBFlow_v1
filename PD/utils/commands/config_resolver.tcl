#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow Config Resolver
# Executes node_config.tcl via tclsh, dumps resolved variables as key=value
# Called by race_engine.py instead of regex-parsing raw file text
# ═══════════════════════════════════════════════════════════════════════════════

if {$argc < 2} {
    puts stderr "Usage: config_resolver.tcl <flow_type> <run_dir>"
    exit 1
}

set flow_type [lindex $argv 0]
set run_dir   [lindex $argv 1]

# Source the run environment (sets all env vars)
set env_file "$run_dir/.run.cbflow.tcl"
if {[file exists $env_file]} {
    source $env_file
} else {
    puts stderr "ERROR: .run.cbflow.tcl not found in $run_dir"
    exit 1
}

# Source flow_config (which sources node_config + tool_config)
set config_root [expr {[info exists ::env(CONFIG_ROOT)] ? $::env(CONFIG_ROOT) : "$::env(FLOW_DIR)/config"}]
set flow_ver [expr {[info exists ::env(FLOW_CONFIG_VERSION)] ? $::env(FLOW_CONFIG_VERSION) : "v1.0.0"}]
set flow_config "$config_root/flow/$flow_ver/flow_config.tcl"

if {[file exists $flow_config]} {
    source $flow_config
} else {
    puts stderr "ERROR: flow_config.tcl not found: $flow_config"
    exit 1
}

# Source mmmc_config (scenarios, rc_corners, analysis_views) — per project
set _proj_name [expr {[info exists ::env(CBFLOW_PROJECT_NAME)] ? $::env(CBFLOW_PROJECT_NAME) : ""}]
set _proj_ver  [expr {[info exists ::env(FLOW_CONFIG_VERSION)] ? $::env(FLOW_CONFIG_VERSION) : "v1.0.0"}]
set _mmmc_cfg_path ""
if {$_proj_name ne ""} {
    set _mmmc_cfg_path "$config_root/project/$_proj_name/$_proj_ver/mmmc_config.tcl"
}
if {$_mmmc_cfg_path ne "" && [file exists $_mmmc_cfg_path]} {
    source $_mmmc_cfg_path
}

# Source user_config (may override tool selection, scenarios)
set user_config "$run_dir/setup/user_config.tcl"
if {[file exists $user_config]} {
    source $user_config
}

# Determine the flow array name (lowercase flow_type)
set flow_array [string tolower $flow_type]

# Dump resolved config as CBFLOW_CFG:key=value lines
# Python parses these lines to build the config dict

# ── stages ──
if {[info exists ${flow_array}(stages)]} {
    puts "CBFLOW_CFG:stages=[set ${flow_array}(stages)]"
}

# ── dependencies ──
foreach key [array names $flow_array "dependencies,*"] {
    set stage [lindex [split $key ","] 1]
    puts "CBFLOW_CFG:dependencies,$stage=[set ${flow_array}($key)]"
}

# ── subnodes ──
foreach key [array names $flow_array "subnodes,*"] {
    set stage [lindex [split $key ","] 1]
    puts "CBFLOW_CFG:subnodes,$stage=[set ${flow_array}($key)]"
}

# ── subnode_dependencies ──
foreach key [array names $flow_array "subnode_dependencies,*"] {
    puts "CBFLOW_CFG:$key=[set ${flow_array}($key)]"
}

# ── stage_types ──
foreach key [array names $flow_array "stage_types,*"] {
    set stage [lindex [split $key ","] 1]
    puts "CBFLOW_CFG:stage_types,$stage=[set ${flow_array}($key)]"
}

# ── node_types ──
foreach key [array names $flow_array "node_types,*"] {
    set stage [lindex [split $key ","] 1]
    puts "CBFLOW_CFG:node_types,$stage=[set ${flow_array}($key)]"
}

# ── tool info ──
foreach key {tool,vendor tool,name tool,version tool,args supported_tools default_tool} {
    if {[info exists ${flow_array}($key)]} {
        puts "CBFLOW_CFG:$key=[set ${flow_array}($key)]"
    }
}

# ── MMMC ──
foreach key [array names $flow_array "mmmc,*"] {
    puts "CBFLOW_CFG:$key=[set ${flow_array}($key)]"
}

# ── runtime timeouts ──
foreach key [array names $flow_array "runtime,timeout,*"] {
    puts "CBFLOW_CFG:$key=[set ${flow_array}($key)]"
}

# ── required_inputs ──
foreach key [array names $flow_array "required_inputs,*"] {
    puts "CBFLOW_CFG:$key=[set ${flow_array}($key)]"
}

# ── RC corner list (resolved from mmmc_config) ──
if {[info exists rc_corner_list]} {
    puts "CBFLOW_CFG:rc_corner_list=$rc_corner_list"
}

# ── MMMC scenario sets (resolved from mmmc_config auto-generation) ──
if {[array exists mmmc_scenario_sets]} {
    foreach key [array names mmmc_scenario_sets] {
        puts "CBFLOW_CFG:mmmc_scenario_set,$key=$mmmc_scenario_sets($key)"
    }
}

# ── Analysis views (for dynamic timing scenarios) ──
if {[array exists analysis_views]} {
    puts "CBFLOW_CFG:analysis_view_names=[lsort [array names analysis_views]]"
}

puts "CBFLOW_CFG:_done=true"
