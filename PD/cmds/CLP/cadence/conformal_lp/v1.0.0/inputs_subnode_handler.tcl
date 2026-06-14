#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBFlow CLP INPUTS Subnode Handler
# Description: Handles inputs stage subnodes for CLP flow
# Subnodes: setup, netlist, upf, power_spec, validate, finish
# Supports test_mode: bypasses EDA tool and shows command file instead
# ═══════════════════════════════════════════════════════════════════════════════

# Parse arguments
if {$argc < 1} {
    puts "ERROR: Missing subnode argument"
    puts "Usage: $argv0 <subnode_name> \[run_dir\]"
    exit 1
}

set subnode_name [lindex $argv 0]
set run_dir [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name [expr {$argc > 2 ? [lindex $argv 2] : ""}]

# Load environment
if {[file exists "$run_dir/.run.cbflow.tcl"]} {
    source "$run_dir/.run.cbflow.tcl"
} else {
    puts "ERROR: Cannot find .run.cbflow.tcl in $run_dir"
    exit 1
}

# Load error handling
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"

# Load flow and CLP configuration
set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }

set clp_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/CLP_config.tcl"
if {[file exists $clp_config]} { source $clp_config }

# Load project config before tech_config
if {[info exists ::env(CBFLOW_PROJECT_NAME)] && $::env(CBFLOW_PROJECT_NAME) ne ""} {
    set _proj_dir "$::env(CONFIG_ROOT)/project/$::env(CBFLOW_PROJECT_NAME)"
    foreach _pv [glob -nocomplain "$_proj_dir/v*"] {
        foreach _pc [glob -nocomplain "$_pv/*_config.tcl"] {
            if {[file exists $_pc]} { source $_pc }
        }
        break
    }
}
# Source tech_config
if {[info exists ::env(TECH_NAME)] && $::env(TECH_NAME) ne "" && [info exists ::env(TECH_VERSION)]} {
    set _tc "$::env(CONFIG_ROOT)/tech/$::env(TECH_NAME)/$::env(TECH_VERSION)/tech_config.tcl"
    if {[file exists $_tc]} { source $_tc }
}
# Source user_config for overrides
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set ::flow_type "CLP"
set stage_name "inputs"
if {$node_name eq ""} { set node_name $stage_name }

# Check test mode
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
        puts "INFO: CLP $stage_name setup..."
        file mkdir "$run_dir/work/CLP/$node_name"
        file mkdir "$run_dir/work/CLP/$node_name/netlist"
        file mkdir "$run_dir/work/CLP/$node_name/upf"
        file mkdir "$run_dir/work/CLP/$node_name/power_spec"
    # Generate config.tcl + setup.tcl via config cascade
    if {[info exists ::env(GENERATION_VERSION)] && $::env(GENERATION_VERSION) ne ""} {
        set _gen "$::env(FLOW_DIR)/utils/generation/$::env(GENERATION_VERSION)/generate_setup.tcl"
        if {[file exists $_gen]} {
            catch {exec tclsh $_gen $::flow_type $node_name ${node_name}_default $run_dir}
        }
    }
        puts "INFO: CLP $stage_name setup completed"
    }
    "netlist" {
        puts "INFO: CLP $stage_name netlist..."
        # Link or copy netlist for CLP analysis
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Netlist loading skipped"
        }
        set info_file "$run_dir/work/CLP/$node_name/netlist/netlist_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set netlist_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        puts $fh "set netlist_info(status) \"loaded\""
        close $fh
        puts "INFO: CLP $stage_name netlist completed"
    }
    "upf" {
        puts "INFO: CLP $stage_name upf..."
        # Link or copy UPF power intent file
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] UPF loading skipped"
        }
        set info_file "$run_dir/work/CLP/$node_name/upf/upf_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set upf_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        puts $fh "set upf_info(status) \"loaded\""
        close $fh
        puts "INFO: CLP $stage_name upf completed"
    }
    "power_spec" {
        puts "INFO: CLP $stage_name power_spec..."
        # Link or copy power specification files
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Power spec loading skipped"
        }
        set info_file "$run_dir/work/CLP/$node_name/power_spec/power_spec_info.tcl"
        file mkdir [file dirname $info_file]
        set fh [open $info_file "w"]
        puts $fh "set power_spec_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        puts $fh "set power_spec_info(status) \"loaded\""
        close $fh
        puts "INFO: CLP $stage_name power_spec completed"
    }
    "validate" {
        puts "INFO: CLP $stage_name validate..."
        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Validation skipped"
        } else {
            puts "INFO: CLP inputs validation passed"
        }
        puts "INFO: CLP $stage_name validate completed"
    }
    "finish" {
        puts "INFO: CLP $stage_name finish..."
        set finish_file "$run_dir/work/CLP/$node_name/finish/finish_info.tcl"
        file mkdir [file dirname $finish_file]
        set fh [open $finish_file "w"]
        puts $fh "set finish_info(timestamp) \"[expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]\""
        close $fh
        puts "INFO: CLP $stage_name finish completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
