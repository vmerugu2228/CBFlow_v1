#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA (opensource) — release_data Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: sta(oss,tool,release_data)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "release_data"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [expr {[info exists ::env(OPENSTA_VERSION)] && $::env(OPENSTA_VERSION) ne "" ? $::env(OPENSTA_VERSION) : [cbflow_require sta tool,version]}]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/STA/opensource/opensta/$_tool_ver/release_data_opensta.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::sta(oss,tool,$stage_name)]} {
    puts "ERROR: sta(oss,tool,$stage_name) not set — STA_opensta_config.tcl not loaded?"
    exit 1
}
set _tool $::sta(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
