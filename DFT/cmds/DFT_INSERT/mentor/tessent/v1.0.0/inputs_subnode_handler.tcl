#!/usr/bin/env tclsh
# CBFlow DFT_INSERT INPUTS Subnode Handler — Mentor Tessent
# Subnodes: rtl, spec, lib (one stage each, each is its own leaf job)

if {$argc < 1} { puts "ERROR: Missing subnode argument"; exit 1 }
set subnode_name [lindex $argv 0]
set run_dir      [expr {$argc > 1 ? [lindex $argv 1] : [pwd]}]
set node_name    [expr {$argc > 2 ? [lindex $argv 2] : ""}]

if {[file exists "$run_dir/.run.cbflow.tcl"]} {
    source "$run_dir/.run.cbflow.tcl"
} else {
    puts "ERROR: .run.cbflow.tcl not found"; exit 1
}
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/error_utils.tcl"

set flow_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/flow_config.tcl"
if {[file exists $flow_config]} { source $flow_config }
set node_config "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/node_configs/DFT_INSERT_config.tcl"
if {[file exists $node_config]} { source $node_config }
if {[file exists "$run_dir/setup/user_config.tcl"]} { source "$run_dir/setup/user_config.tcl" }

set ::flow_type "DFT_INSERT"
set stage_name  "inputs"
if {$node_name eq ""} { set node_name $stage_name }

set test_mode false
if {[info exists flow(test_mode)] && $flow(test_mode) eq "true"} { set test_mode true }

# Resolve inputs from upstream run manifest or release tag
if {[info exists ::env(SCRIPTS_ROOT)] && [info exists ::env(UTILITIES_VERSION)]} {
    set _resolve_lib "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/resolve_inputs.tcl"
    if {[file exists $_resolve_lib]} {
        source $_resolve_lib
        resolve_flow_inputs $::flow_type $run_dir
    }
}

set _ts [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _t] ? "epoch [clock seconds]" : $_t}]

proc _link_or_stub {src dst label} {
    upvar 1 test_mode test_mode
    file mkdir [file dirname $dst]
    if {$src ne "" && [file exists $src]} {
        if {[file exists $dst]} { file delete -force $dst }
        file link -symbolic $dst $src
        puts "INFO:   $label: [file tail $src]"
        return 1
    } elseif {$test_mode} {
        set fh [open $dst "w"]
        puts $fh "// \[TEST MODE\] stub for $label"
        close $fh
        puts "INFO:   $label: \[TEST MODE\] stub created"
        return 1
    } else {
        puts "WARNING: $label source missing: $src"
        return 0
    }
}

switch $subnode_name {
    "rtl" {
        puts "INFO: DFT_INSERT rtl..."
        set wd "$run_dir/work/DFT_INSERT/$node_name/rtl"
        set src [expr {[info exists dft_insert(input,rtl)] ? $dft_insert(input,rtl) : ""}]
        _link_or_stub $src "$wd/[expr {$src ne "" ? [file tail $src] : {rtl_stub.v}}]" "RTL"
        set fh [open "$wd/rtl_info.tcl" "w"]
        puts $fh "set rtl_info(timestamp) \"$_ts\""
        puts $fh "set rtl_info(status) \"loaded\""
        close $fh
        puts "INFO: DFT_INSERT rtl completed"
    }
    "spec" {
        puts "INFO: DFT_INSERT spec..."
        set wd "$run_dir/work/DFT_INSERT/$node_name/spec"
        set src [expr {[info exists dft_insert(input,dft_spec)] ? $dft_insert(input,dft_spec) : ""}]
        _link_or_stub $src "$wd/[expr {$src ne "" ? [file tail $src] : {dft_spec_stub.tcl}}]" "DFT spec"
        set fh [open "$wd/spec_info.tcl" "w"]
        puts $fh "set spec_info(timestamp) \"$_ts\""
        puts $fh "set spec_info(status) \"loaded\""
        close $fh
        puts "INFO: DFT_INSERT spec completed"
    }
    "lib" {
        puts "INFO: DFT_INSERT lib..."
        set wd "$run_dir/work/DFT_INSERT/$node_name/lib"
        file mkdir $wd
        set fh [open "$wd/lib_info.tcl" "w"]
        puts $fh "set lib_info(timestamp) \"$_ts\""
        puts $fh "set lib_info(status) \"loaded\""
        close $fh
        puts "INFO: DFT_INSERT lib completed"
    }
    default {
        puts "ERROR: Unknown subnode: $subnode_name"
        exit 1
    }
}
