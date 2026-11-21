#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA (opensource) — extraction Subnode Handler
# Subnodes: setup, <rc_corner> (dynamic: one per rc_corner_list entry —
# OpenRCX via OpenROAD, each in its own run dir/log), validate, finish.
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "extraction"
if {$node_name eq ""} { set node_name "${stage_name}1" }
set _tool_ver [expr {[info exists ::env(OPENSTA_VERSION)] ? $::env(OPENSTA_VERSION) : "v1.0.0"}]
set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        if {[catch {handler_setup $run_dir $::flow_type $node_name} _rc] || $_rc != 0} {
            puts stderr "ERROR: $stage_name setup failed: $_rc"; exit 1
        }
    }
    "validate" { handler_validate $run_dir $::flow_type $node_name $stage_name $test_mode }
    "finish"   { handler_finish   $run_dir $::flow_type $node_name $stage_name }
    default {
        if {![string match "rc_*" $subnode_name]} { puts "ERROR: Unknown subnode: $subnode_name"; exit 1 }
        set _rc  $subnode_name
        set _dsg $::flow(design_name)
        set _dir "$run_dir/work/$::flow_type/$node_name/$_rc"
        file mkdir "$_dir/run" "$_dir/results"
        set _spef "$_dir/results/${_dsg}_${_rc}.spef"
        set _ctx  "$_dir/run/${_rc}.tcl"
        set _fh [open $_ctx w]
        puts $_fh "# CBflow STA extraction context — $_rc"
        puts $_fh "set ::OSS_NODE  \"$node_name\""
        puts $_fh "set ::RC_CORNER \"$_rc\""
        puts $_fh "set ::SPEF_OUT  \"$_spef\""
        puts $_fh "source \"$::env(FLOW_DIR)/PD/cmds/STA/opensource/opensta/$_tool_ver/extraction_opensta.tcl\""
        close $_fh
        if {$test_mode} {
            set _fh [open $_spef w]; puts $_fh "// test-mode SPEF $_rc"; close $_fh
            puts "INFO: \[TEST MODE\] extraction $_rc -> $_spef"
        } else {
            set _wrapper [generate_launch_wrapper "$_dir/run" $_rc $_ctx \
                              $::sta(oss,tool,extraction) "$_dir/run/${_rc}.log"]
            submit_job $_wrapper $::flow_type $_rc $_rc "$_dir/run"
            if {![file exists $_spef] || [file size $_spef] == 0} {
                puts "ERROR: extraction $_rc produced no SPEF ($_spef)"; exit 1
            }
        }
        # node outputs/ (what node validation checks): one SPEF per corner
        file mkdir "$run_dir/work/$::flow_type/$node_name/outputs"
        file copy -force $_spef "$run_dir/work/$::flow_type/$node_name/outputs/[file tail $_spef]"
        puts "INFO: extraction $_rc completed"
    }
}
