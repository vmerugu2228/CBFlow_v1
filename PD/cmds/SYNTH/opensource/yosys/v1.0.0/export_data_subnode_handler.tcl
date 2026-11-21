#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SYNTH (opensource) — export_data Subnode Handler
# Subnodes: setup, run, validate, finish (delegated to handler_dispatch)
# Tool binary: synth(oss,tool,export_data)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "SYNTH"

set ::flow_type "SYNTH"
set stage_name "export_data"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(YOSYS_VERSION)] ? $::env(YOSYS_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/PD/cmds/SYNTH/opensource/yosys/$_tool_ver/export_data_yosys.tcl"

set test_mode [handler_is_test_mode]
if {![info exists ::synth(oss,tool,$stage_name)]} {
    puts "ERROR: synth(oss,tool,$stage_name) not set — SYNTH_yosys_config.tcl not loaded?"
    exit 1
}
set _tool $::synth(oss,tool,$stage_name)

handler_dispatch $subnode_name $run_dir $::flow_type $node_name $stage_name \
                 $cmd_file $test_mode $_tool
