#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG (opensource) — timing_sim Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: atpg(oss,tool,timing_sim)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "ATPG"

set ::flow_type "ATPG"
set stage_name "timing_sim"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_DFT_DIR)/cmds/ATPG/opensource/fault/$_tool_ver/timing_sim_fault.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::atpg(oss,tool,$stage_name)]} {
    puts "ERROR: atpg(oss,tool,$stage_name) not set — ATPG_fault_config.tcl not loaded?"
    exit 1
}
set _tool $::atpg(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
