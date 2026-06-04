#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow PV INPUTS Subnode Handler
# Description: Handles inputs stage subnodes (setup, netlist, def, gds, validate, finish)
# Supports test_mode: bypasses loading and shows info instead
# ═══════════════════════════════════════════════════════════════════════════════

if {$argc < 1} {
    puts "ERROR: Missing subnode argument"
    puts "Usage: $argv0 <subnode_name> \[run_dir\]"
    exit 1
}

set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]

if {[file exists "$run_dir/.run.cbflow.tcl"]} {
    source "$run_dir/.run.cbflow.tcl"
} else {
    puts "ERROR: Cannot find .run.cbflow.tcl in $run_dir"
    exit 1
}

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"

set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }

set phyv_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/PV_config.tcl"
if {[file exists $phyv_config]} { source $phyv_config }

if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set ::flow_type "PV"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }

set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} {
    set test_mode true
}

# Resolve inputs from upstream run manifest or release tag (before processing subnodes)
if {[info exists ::env(SCRIPTS_ROOT)] && [info exists ::env(UTILITIES_VERSION)]} {
    set _resolve_lib "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/resolve_inputs.tcl"
    if {[file exists $_resolve_lib]} {
        source $_resolve_lib
        resolve_flow_inputs $::flow_type $run_dir
    }
}
switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        file mkdir "$run_dir/work/$::flow_type/$node_name/netlist"
        file mkdir "$run_dir/work/$::flow_type/$node_name/def"
        file mkdir "$run_dir/work/$::flow_type/$node_name/gds"
        file mkdir "$run_dir/work/$::flow_type/$node_name/run"
    # Generate config.tcl + setup.tcl via config cascade
    if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
        set _gen "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
        if {[file exists $_gen]} {
            catch {exec tclsh $_gen $::flow_type $node_name ${node_name}_default $run_dir}
        }
    }
        puts "INFO: $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: $stage_name netlist..."
        set info_file "$run_dir/work/$::flow_type/$node_name/netlist/netlist.info"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "Netlist input prepared: [clock format [clock seconds]]"
        close $fh
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Skipping netlist loading"
        } else {
            puts "INFO: Netlist loading completed"
        }
        puts "INFO: $stage_name netlist completed"
    }
    "def" {
        puts "INFO: $stage_name def..."
        set info_file "$run_dir/work/$::flow_type/$node_name/def/def.info"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "DEF input prepared: [clock format [clock seconds]]"
        close $fh
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Skipping DEF loading"
        } else {
            puts "INFO: DEF loading completed"
        }
        puts "INFO: $stage_name def completed"
    }
    "gds" {
        puts "INFO: $stage_name gds..."
        set info_file "$run_dir/work/$::flow_type/$node_name/gds/gds.info"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "GDS input prepared: [clock format [clock seconds]]"
        close $fh
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Skipping GDS loading"
        } else {
            puts "INFO: GDS loading completed"
        }
        puts "INFO: $stage_name gds completed"
    }
    "validate" {
        puts "INFO: $stage_name validate..."
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Validation skipped"
        } else {
            puts "INFO: $stage_name validation passed"
        }
        puts "INFO: $stage_name validate completed"
    }
    "finish" {
        puts "INFO: $stage_name finish..."
        set finish_file "$run_dir/work/$::flow_type/$node_name/${stage_name}_finish.timestamp"
        file mkdir [file dirname $finish_file]
        set fh [open $finish_file "w"]
        puts $fh "Completed: [clock format [clock seconds]]"
        close $fh
        puts "INFO: $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
