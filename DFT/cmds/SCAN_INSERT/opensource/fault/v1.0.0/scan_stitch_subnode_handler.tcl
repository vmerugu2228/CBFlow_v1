#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SCAN_INSERT (opensource) — scan_stitch Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: scan_insert(oss,tool,scan_stitch)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "SCAN_INSERT"

set ::flow_type "SCAN_INSERT"
set stage_name "scan_stitch"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_DFT_DIR)/cmds/SCAN_INSERT/opensource/fault/$_tool_ver/scan_stitch_fault.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::scan_insert(oss,tool,$stage_name)]} {
    puts "ERROR: scan_insert(oss,tool,$stage_name) not set — SCAN_INSERT_fault_config.tcl not loaded?"
    exit 1
}
set _tool $::scan_insert(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
