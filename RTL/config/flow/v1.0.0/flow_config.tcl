#!/usr/bin/env tclsh
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      CBflow RTL Flow Configuration                          ║
# ║  Sourced by config_resolver.tcl when an RTL flow (RTL_LINT / RTL_CDC /      ║
# ║  RTL_RDC / UPF_CHECK) is resolved. Sourced AFTER the global                 ║
# ║  flow_registry.tcl —                                                        ║
# ║  registry provides flow(types) + flow(discipline,*), this file provides     ║
# ║  the RTL-specific mandatory_vars and dispatches to the right node_config.   ║
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

# ── RTL-specific mandatory_vars ───────────────────────────────────────────────
# The catalog + discipline map already live in the global registry — this
# file only appends RTL-side mandatory_vars keys for the pre-flight validator.
# Every RTL flow requires a tool selection (Synopsys Spyglass / VC-LP vs
# Cadence Jaspergold / Conformal LP).
set flow(mandatory_vars,RTL_LINT)   {default_tool}
set flow(mandatory_vars,RTL_CDC)    {default_tool}
set flow(mandatory_vars,RTL_RDC)    {default_tool}
set flow(mandatory_vars,UPF_CHECK)  {default_tool}

# ── Flow type dispatch ────────────────────────────────────────────────────────
# CBFLOW_FLOW_TYPE is set by the launcher (bin/cbflow) or by the resolver
# preamble. If we're in an RTL flow, source the matching node_config from
# THIS discipline's tree, not PD's.
if {[info exists ::env(CBFLOW_FLOW_TYPE)]} {
    set current_flow_type $::env(CBFLOW_FLOW_TYPE)
    set node_config "$config_dir/node_configs/${current_flow_type}_config.tcl"
    if {[file exists $node_config]} {
        source $node_config
    } else {
        puts stderr "WARN: RTL node_config not found: $node_config"
    }
}
