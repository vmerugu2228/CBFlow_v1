#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — route Subnode Handler (Cadence Innovus)
# Subnodes: setup, run, validate, finish
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "PNR"

set ::flow_type "PNR"
set stage_name "route"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(INNOVUS_VERSION)] ? $::env(INNOVUS_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/PNR/cadence/innovus/$_tool_ver/route_innovus.tcl"

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        # Local cmd-file = symlink to canonical → diff main local = 0.
        set _gen_file "$run_dir/work/$::flow_type/$node_name/run/${node_name}.innovus.tcl"
        if {[file exists $cmd_file]} {
            catch {file delete $_gen_file}
            if {[catch {file link -symbolic $_gen_file $cmd_file} _err]} {
                puts "WARN: symlink failed ($_err); falling back to copy"
                file copy -force $cmd_file $_gen_file
            }
            puts "INFO: Command file (symlink → $cmd_file): $_gen_file"
        }
        puts "INFO: $stage_name setup completed"
    }
    "run" {
        puts "INFO: $stage_name run..."
        set _gen_file "$run_dir/work/$::flow_type/$node_name/run/${node_name}.innovus.tcl"
        set _tool [expr {[info exists pnr(tool,name)] ? $pnr(tool,name) : "innovus"}]
        handler_run $run_dir $::flow_type $node_name $stage_name $_gen_file $test_mode $_tool
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
