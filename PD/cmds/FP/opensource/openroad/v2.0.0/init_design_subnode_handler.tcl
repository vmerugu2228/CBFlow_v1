#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FP (opensource) — init_design Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary per stage: fp(oss,tool,init_design) (yosys | openroad | oss_tclsh)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "FP"

set ::flow_type "FP"
set stage_name "init_design"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version OPENROAD_VERSION]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/FP/opensource/openroad/$_tool_ver/init_design_openroad.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::fp(oss,tool,$stage_name)]} {
    puts "ERROR: fp(oss,tool,$stage_name) not set — FP_openroad_config.tcl not loaded?"
    exit 1
}
set _tool $::fp(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
