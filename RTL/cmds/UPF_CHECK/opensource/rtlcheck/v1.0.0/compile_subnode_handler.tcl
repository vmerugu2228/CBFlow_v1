#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow UPF_CHECK (opensource) — compile Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: upf_check(oss,tool,compile)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "UPF_CHECK"

set ::flow_type "UPF_CHECK"
set stage_name "compile"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version]
set cmd_file "$::env(CBFLOW_RTL_DIR)/cmds/UPF_CHECK/opensource/rtlcheck/$_tool_ver/compile_rtlcheck.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::upf_check(oss,tool,$stage_name)]} {
    puts "ERROR: upf_check(oss,tool,$stage_name) not set — UPF_CHECK_rtlcheck_config.tcl not loaded?"
    exit 1
}
set _tool $::upf_check(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
