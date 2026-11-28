#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PV (opensource) — lvs Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: pv(oss,tool,lvs)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "PV"

set ::flow_type "PV"
set stage_name "lvs"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version MAGIC_VERSION]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/PV/opensource/magic/$_tool_ver/lvs_magic.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::pv(oss,tool,$stage_name)]} {
    puts "ERROR: pv(oss,tool,$stage_name) not set — PV_magic_config.tcl not loaded?"
    exit 1
}
set _tool $::pv(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
