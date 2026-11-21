#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow LEC (opensource) — release_data Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: lec(oss,tool,release_data)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "LEC"

set ::flow_type "LEC"
set stage_name "release_data"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(LEC_YOSYS_VERSION)] ? $::env(LEC_YOSYS_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/LEC/opensource/yosys/$_tool_ver/release_data_yosys.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::lec(oss,tool,$stage_name)]} {
    puts "ERROR: lec(oss,tool,$stage_name) not set — LEC_yosys_config.tcl not loaded?"
    exit 1
}
set _tool $::lec(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
