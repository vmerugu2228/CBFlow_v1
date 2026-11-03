#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      CBflow DFT Flow Configuration                          ║
# ║  Sourced by config_resolver.tcl when a DFT flow (DFT_INSERT_PASS{1,2,3} /   ║
# ║  SCAN_INSERT / ATPG / GLS_*) is resolved. Sourced AFTER the global          ║
# ║  flow_registry.tcl —                                                        ║
# ║  registry provides flow(types) + flow(discipline,*), this file provides     ║
# ║  the DFT-specific mandatory_vars and dispatches to the right node_config.   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ── Resolve config directory ──────────────────────────────────────────────────
set script_path [info script]
if {[file type $script_path] eq "link"} {
    set script_path [file readlink $script_path]
    if {[file pathtype $script_path] ne "absolute"} {
        set script_path [file join [file dirname [info script]] $script_path]
    }
}
set config_dir [file dirname $script_path]

# ── DFT-specific mandatory_vars ───────────────────────────────────────────────
# The catalog + discipline map already live in the global registry — this
# file only appends DFT-side mandatory_vars keys for the pre-flight validator.
# Every DFT flow requires a tool selection (Synopsys DFT-C vs Mentor Tessent).
set flow(mandatory_vars,DFT_INSERT_PASS1) {default_tool}
set flow(mandatory_vars,DFT_INSERT_PASS2) {default_tool}
set flow(mandatory_vars,DFT_INSERT_PASS3) {default_tool}
set flow(mandatory_vars,SCAN_INSERT)      {default_tool}
set flow(mandatory_vars,ATPG)             {default_tool}
set flow(mandatory_vars,GLS_FUNC)         {default_tool}
set flow(mandatory_vars,GLS_SCAN_MBIST)   {default_tool}

# ── Flow type dispatch ────────────────────────────────────────────────────────
# CBFLOW_FLOW_TYPE is set by the launcher (bin/cbflow) or by the resolver
# preamble. If we're in a DFT flow, source the matching node_config from
# THIS discipline's tree, not PD's.
if {[info exists ::env(CBFLOW_FLOW_TYPE)]} {
    set current_flow_type $::env(CBFLOW_FLOW_TYPE)
    set node_config "$config_dir/node_configs/${current_flow_type}_config.tcl"
    if {[file exists $node_config]} {
        source $node_config
    } else {
        puts stderr "WARN: DFT node_config not found: $node_config"
    }
}
