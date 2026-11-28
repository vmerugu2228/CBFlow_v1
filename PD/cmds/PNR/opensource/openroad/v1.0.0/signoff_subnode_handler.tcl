#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR (opensource) — signoff Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary per stage: pnr(oss,tool,signoff) (yosys | openroad | oss_tclsh)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "PNR"

set ::flow_type "PNR"
set stage_name "signoff"
if {$node_name eq ""} { set node_name [cbflow_node_name] }

set _tool_ver [handler_tool_version OPENROAD_VERSION]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/PNR/opensource/openroad/$_tool_ver/signoff_openroad.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::pnr(oss,tool,$stage_name)]} {
    puts "ERROR: pnr(oss,tool,$stage_name) not set — PNR_openroad_config.tcl not loaded?"
    exit 1
}
set _tool $::pnr(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
