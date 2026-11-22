#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow CLP — clp Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "CLP"

set ::flow_type "CLP"
set stage_name "clp"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [expr {[info exists ::env(CONFORMAL_LP_VERSION)] && $::env(CONFORMAL_LP_VERSION) ne "" ? $::env(CONFORMAL_LP_VERSION) : [cbflow_require clp tool,version]}]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/CLP/cadence/conformal_lp/$_tool_ver/clp_conformal_lp.tcl"

set test_mode [handler_is_test_mode]
set _tool [cbflow_require clp tool,name]

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool "conformal_lp"
