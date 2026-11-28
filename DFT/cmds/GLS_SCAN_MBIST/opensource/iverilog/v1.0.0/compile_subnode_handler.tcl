#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow GLS_SCAN_MBIST (opensource) — compile Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: gls_scan_mbist(oss,tool,compile)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "GLS_SCAN_MBIST"

set ::flow_type "GLS_SCAN_MBIST"
set stage_name "compile"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_DFT_DIR)/cmds/GLS_SCAN_MBIST/opensource/iverilog/$_tool_ver/compile_iverilog.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::gls_scan_mbist(oss,tool,$stage_name)]} {
    puts "ERROR: gls_scan_mbist(oss,tool,$stage_name) not set — GLS_SCAN_MBIST_iverilog_config.tcl not loaded?"
    exit 1
}
set _tool $::gls_scan_mbist(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
