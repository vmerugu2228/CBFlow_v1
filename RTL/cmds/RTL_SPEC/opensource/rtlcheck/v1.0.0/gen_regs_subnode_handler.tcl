#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow RTL_SPEC (opensource) — gen_regs Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: rtl_spec(oss,tool,gen_regs)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "RTL_SPEC"

set ::flow_type "RTL_SPEC"
set stage_name "gen_regs"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [cbflow_require rtl_spec tool,version]
set cmd_file "$::env(CBFLOW_RTL_DIR)/cmds/RTL_SPEC/opensource/rtlcheck/$_tool_ver/gen_regs_rtlcheck.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::rtl_spec(oss,tool,$stage_name)]} {
    puts "ERROR: rtl_spec(oss,tool,$stage_name) not set — RTL_SPEC_rtlcheck_config.tcl not loaded?"
    exit 1
}
set _tool $::rtl_spec(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
