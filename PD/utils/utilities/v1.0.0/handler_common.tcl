#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — Shared Handler Utilities
# Common procedures used by ALL subnode handlers to eliminate duplication.
# Source this at the top of every handler instead of copy-pasting 200 lines.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Parse handler arguments ──────────────────────────────────────────────────
# Returns: subnode_name, run_dir, node_name
# Usage: lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
proc handler_parse_args {argv argc} {
    if {$argc < 1} {
        puts "ERROR: Missing subnode argument"
        puts "Usage: tclsh <handler>.tcl <subnode_name> \[run_dir\] \[node_name\]"
        exit 1
    }
    set subnode_name [lindex $argv 0]
    set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
    set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]
    return [list $subnode_name $run_dir $node_name]
}

# ── Load standard configs for a handler ──────────────────────────────────────
# Sources: .run.cbflow.tcl, error_utils, flow_config, node_config, user_config, tool_launch_config
proc handler_load_configs {run_dir flow_type} {
    # Source everything at global scope (uplevel #0) so variables are accessible
    # Why: TCL 'source' inside a proc creates local variables. Config files
    # set global arrays (flow, synth, pnr, etc.) that must be in global scope.

    # Run environment (mandatory)
    if {[file exists "$run_dir/.run.cbflow.tcl"]} {
        uplevel #0 [list source "$run_dir/.run.cbflow.tcl"]
    } else {
        puts "ERROR: Cannot find .run.cbflow.tcl in $run_dir"
        exit 1
    }

    # Error utilities
    if {[info exists ::env(SCRIPTS_ROOT)] && [info exists ::env(UTILITIES_VERSION)]} {
        set _eu "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"
        if {[file exists $_eu]} { uplevel #0 [list source $_eu] }
    }

    # Flow config
    if {[info exists ::env(CONFIG_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
        set _fc "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
        if {[file exists $_fc]} { uplevel #0 [list source $_fc] }

        # Node config
        set _nc "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/${flow_type}_config.tcl"
        if {[file exists $_nc]} { uplevel #0 [list source $_nc] }
    }

    # User config (overrides all)
    if {[file exists "$run_dir/setup/user_config.tcl"]} {
        uplevel #0 [list source "$run_dir/setup/user_config.tcl"]
    }

    # Tool launch config (module load, tool shell, bsub, xterm)
    if {[info exists ::env(CONFIG_ROOT)] && [info exists ::env(FLOW_CONFIG_VERSION)]} {
        set _lc "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/tool_launch_config.tcl"
        if {[file exists $_lc]} { uplevel #0 [list source $_lc] }
    }
}

# ── Detect test mode ─────────────────────────────────────────────────────────
proc handler_is_test_mode {} {
    if {[info exists ::flow(test_mode)] && $::flow(test_mode) eq "true"} {
        return true
    }
    return false
}

# ── Setup subnode: create directories + generate config ──────────────────────
proc handler_setup {run_dir flow_type node_name} {
    file mkdir "$run_dir/work/$flow_type/$node_name/run"
    file mkdir "$run_dir/work/$flow_type/$node_name/setup"

    # Generate config.tcl + setup.tcl via config cascade
    if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
        set _gen "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
        if {[file exists $_gen]} {
            catch {exec tclsh $_gen $flow_type $node_name ${node_name}_default $run_dir}
        }
    }
}

# ── Finish subnode: create timestamp file ─────────────────────────────────────
proc handler_finish {run_dir flow_type node_name stage_name} {
    set finish_file "$run_dir/work/$flow_type/$node_name/run/${stage_name}_finish.timestamp"
    file mkdir [file dirname $finish_file]
    set fh [open $finish_file "w"]
    puts $fh "Completed: [clock format [clock seconds]]"
    close $fh
}

# ── Validate subnode: basic validation ────────────────────────────────────────
proc handler_validate {run_dir flow_type node_name stage_name test_mode} {
    if {$test_mode} {
        puts "INFO: \[TEST MODE\] Validation skipped"
    } else {
        puts "INFO: $stage_name validation passed"
    }
}
