#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ECO (opensource) — export_data Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary per stage: eco(oss,tool,export_data) (yosys | openroad | oss_tclsh)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "ECO"

set ::flow_type "ECO"
set stage_name "export_data"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [expr {[info exists ::env(OPENROAD_VERSION)] && $::env(OPENROAD_VERSION) ne "" ? $::env(OPENROAD_VERSION) : [cbflow_require eco tool,version]}]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/ECO/opensource/openroad/$_tool_ver/export_data_openroad.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::eco(oss,tool,$stage_name)]} {
    puts "ERROR: eco(oss,tool,$stage_name) not set — ECO_openroad_config.tcl not loaded?"
    exit 1
}
set _tool $::eco(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
