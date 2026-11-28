#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow M3_EXEC (opensource) — regress Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: m3_exec(oss,tool,regress)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "M3_EXEC"

set ::flow_type "M3_EXEC"
set stage_name "regress"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_DV_DIR)/cmds/M3_EXEC/opensource/verilator/$_tool_ver/regress_verilator.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::m3_exec(oss,tool,$stage_name)]} {
    puts "ERROR: m3_exec(oss,tool,$stage_name) not set — M3_EXEC_verilator_config.tcl not loaded?"
    exit 1
}
set _tool $::m3_exec(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
