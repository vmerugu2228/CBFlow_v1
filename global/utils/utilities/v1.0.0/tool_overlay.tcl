#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — tool-overlay reload
#
# Every <FLOW>_config.tcl picks its tool overlay (<FLOW>_<tool>_config.tcl)
# from `<flow>(tool,name)` when it is sourced — but user_config.tcl is
# sourced AFTER the node config, so a tool chosen there
# (`set synth(tool,name) "genus"`, `set synth_pnr(tool,name) "openroad"`)
# only renamed the tool; the default tool's overlay (app settings,
# tool,vendor, required_inputs, mandatory_outputs, …) stayed loaded.
#
# Call cbflow_reload_tool_overlay right after user_config.tcl is sourced.
# After the node config, `tool,name` equals `default_tool` (the overlay sets
# it); if user_config changed it, source that tool's overlay and re-source
# user_config so the user's own overrides still win.
#
# Sourced by: config_resolver.tcl, handler_common.tcl (handler_load_configs),
# and the per-node config.tcl written by generate_setup.tcl.
# ═══════════════════════════════════════════════════════════════════════════════

proc cbflow_reload_tool_overlay {flow_type node_cfg_dir {user_config ""}} {
    set _arr [string tolower $flow_type]
    upvar #0 $_arr _a
    if {![array exists _a]} { return 0 }
    if {![info exists _a(tool,name)] || ![info exists _a(default_tool)]} { return 0 }
    if {$_a(tool,name) eq $_a(default_tool)} { return 0 }
    # Already reloaded for this tool (idempotent across repeated calls).
    if {[info exists _a(tool,overlay_loaded)] && $_a(tool,overlay_loaded) eq $_a(tool,name)} {
        return 0
    }
    set _tool $_a(tool,name)
    set _overlay [file join $node_cfg_dir "${flow_type}_${_tool}_config.tcl"]
    if {![file exists $_overlay]} {
        set _sup [expr {[info exists _a(supported_tools)] ? $_a(supported_tools) : "?"}]
        error "Tool config not found for ${_arr}(tool,name)=$_tool: $_overlay (supported: $_sup)"
    }
    uplevel #0 [list source $_overlay]
    if {$user_config ne "" && [file exists $user_config]} {
        uplevel #0 [list source $user_config]
    }
    set _a(tool,overlay_loaded) $_a(tool,name)
    return 1
}
