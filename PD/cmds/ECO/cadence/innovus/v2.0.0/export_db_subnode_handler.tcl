#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ECO — export_db Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "ECO"

set ::flow_type "ECO"
set stage_name "export_db"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/ECO/cadence/innovus/$_tool_ver/export_db_innovus.tcl"

set test_mode [handler_is_test_mode]
set _tool [cbflow_require eco tool,name]

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
