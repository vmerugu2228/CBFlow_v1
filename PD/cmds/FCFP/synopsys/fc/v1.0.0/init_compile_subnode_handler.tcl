#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FCFP — init_compile Subnode Handler (Synopsys FC)
# Subnodes: setup, run, validate, finish
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "FCFP"

set ::flow_type "FCFP"
set stage_name "init_compile"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(FC_VERSION)] ? $::env(FC_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/FCFP/synopsys/fc/$_tool_ver/init_compile_init_compile_fc.tcl"

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        puts "INFO: $stage_name setup completed"
    }
    "run" {
        puts "INFO: $stage_name run..."
        set _tool [expr {[info exists fcfp(tool,name)] ? $fcfp(tool,name) : "fc"}]
        handler_run $run_dir $::flow_type $node_name $stage_name $cmd_file $test_mode $_tool
    }
    "validate" {
        puts "INFO: $stage_name validate..."
        handler_validate $run_dir $::flow_type $node_name $stage_name $test_mode
        puts "INFO: $stage_name validate completed"
    }
    "finish" {
        puts "INFO: $stage_name finish..."
        handler_finish $run_dir $::flow_type $node_name $stage_name
        puts "INFO: $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
