#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_LINT (opensource) — release_data Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: rtl_lint(oss,tool,release_data)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "RTL_LINT"

set ::flow_type "RTL_LINT"
set stage_name "release_data"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_RTL_DIR)/cmds/RTL_LINT/opensource/verilator/$_tool_ver/release_data_verilator.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::rtl_lint(oss,tool,$stage_name)]} {
    puts "ERROR: rtl_lint(oss,tool,$stage_name) not set — RTL_LINT_verilator_config.tcl not loaded?"
    exit 1
}
set _tool $::rtl_lint(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
