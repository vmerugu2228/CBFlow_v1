#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — mmmc_setup Subnode Handler (Cadence Tempus)
# Subnodes: setup, load_config, resolve_scenarios (run), validate, finish
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "mmmc_setup"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(TEMPUS_VERSION)] ? $::env(TEMPUS_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/cadence/tempus/$_tool_ver/mmmc_setup_tempus.tcl"

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        puts "INFO: $stage_name setup completed"
    }
    "load_config" {
        puts "INFO: $stage_name load_config..."
        set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $mmmc_config_file]} {
            source $mmmc_config_file
            puts "INFO: MMMC configuration loaded from $mmmc_config_file"
        } else {
            puts "ERROR: MMMC config not found: $mmmc_config_file"
            exit 1
        }
        puts "INFO: $stage_name load_config completed"
    }
    "resolve_scenarios" {
        puts "INFO: $stage_name resolve_scenarios..."
        set _tool [expr {[info exists ::sta(tool,name)] ? $::sta(tool,name) : "tempus"}]
        handler_run $run_dir $::flow_type $node_name $stage_name $cmd_file $test_mode $_tool
    }
    "validate" {
        puts "INFO: $stage_name validate..."
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Validation skipped"
        } else {
            set scenarios_file "$run_dir/work/$::flow_type/$node_name/run/active_scenarios.tcl"
            if {![file exists $scenarios_file]} {
                puts "ERROR: active_scenarios.tcl not found at $scenarios_file"
                exit 1
            }
        }
        puts "INFO: $stage_name validate completed"
    }
    "finish" {
        puts "INFO: $stage_name finish..."
        handler_finish $run_dir $::flow_type $node_name $stage_name
        puts "INFO: $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
