#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                       CBflow DV Flow Configuration                          ║
# ║  Sourced by config_resolver.tcl when a DV flow (LINT / CDC / RDC / SIM /    ║
# ║  COV_MERGE / FORMAL / UPF_CHECK) is resolved. Sourced AFTER the global      ║
# ║  flow_registry.tcl — registry provides flow(types) + flow(discipline,*),   ║
# ║  this file provides DV-specific mandatory_vars and dispatches to the       ║
# ║  right node_config under this discipline's tree.                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set script_path [info script]
if {[file type $script_path] eq "link"} {
    set script_path [file readlink $script_path]
    if {[file pathtype $script_path] ne "absolute"} {
        set script_path [file join [file dirname [info script]] $script_path]
    }
}
set config_dir [file dirname $script_path]

# ── DV-specific mandatory_vars ────────────────────────────────────────────────
set flow(mandatory_vars,LINT)      {default_tool}
set flow(mandatory_vars,CDC)       {default_tool}
set flow(mandatory_vars,RDC)       {default_tool}
set flow(mandatory_vars,SIM)       {default_tool}
set flow(mandatory_vars,COV_MERGE) {default_tool}
set flow(mandatory_vars,FORMAL)    {default_tool}
set flow(mandatory_vars,UPF_CHECK) {default_tool}

# ── Flow type dispatch ────────────────────────────────────────────────────────
if {[info exists ::env(CBFLOW_FLOW_TYPE)]} {
    set current_flow_type $::env(CBFLOW_FLOW_TYPE)
    set node_config "$config_dir/node_configs/${current_flow_type}_config.tcl"
    if {[file exists $node_config]} {
        source $node_config
    } else {
        puts stderr "WARN: DV node_config not found: $node_config"
    }
}
