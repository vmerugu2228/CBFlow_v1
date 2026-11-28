#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow M1_EXEC (opensource) — cov_merge Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: m1_exec(oss,tool,cov_merge)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "M1_EXEC"

set ::flow_type "M1_EXEC"
set stage_name "cov_merge"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_DV_DIR)/cmds/M1_EXEC/opensource/verilator/$_tool_ver/cov_merge_verilator.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::m1_exec(oss,tool,$stage_name)]} {
    puts "ERROR: m1_exec(oss,tool,$stage_name) not set — M1_EXEC_verilator_config.tcl not loaded?"
    exit 1
}
set _tool $::m1_exec(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
