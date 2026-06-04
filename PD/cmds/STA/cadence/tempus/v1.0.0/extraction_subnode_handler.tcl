#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — extraction Subnode Handler (Cadence Tempus)
# Subnodes: setup, run, validate, finish, rc_* (dynamic RC corners)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "extraction"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(TEMPUS_VERSION)] ? $::env(TEMPUS_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/cadence/tempus/$_tool_ver/extraction_tempus.tcl"

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        puts "INFO: $stage_name setup completed"
    }
    "run" {
        puts "INFO: $stage_name run..."
        set _tool [expr {[info exists ::sta(tool,name)] ? $::sta(tool,name) : "tempus"}]
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
        # Dynamic RC corner subnode (e.g., rc_max, rc_typ, rc_min, rc_max_cworst)
        if {[string match "rc_*" $subnode_name]} {
            puts "INFO: extraction $subnode_name ($node_name)..."
            set _corner_dir "$run_dir/work/$::flow_type/$node_name/$subnode_name"
            file mkdir "$_corner_dir/run"
            file mkdir "$_corner_dir/results"

            # Resolve QRC tech file: priority qrc > nxtgrd > tluplus
            set _rc_file ""
            set _rc_file_type ""
            set _rc_corner $subnode_name
            foreach {_fmt} {qrc nxtgrd tluplus} {
                if {$_rc_file eq "" && [info exists ::tech(rcx,${_rc_corner},${_fmt})] && $::tech(rcx,${_rc_corner},${_fmt}) ne ""} {
                    set _rc_file $::tech(rcx,${_rc_corner},${_fmt})
                    set _rc_file_type $_fmt
                }
            }

            set _lef_file ""
            if {[info exists ::tech(lef_tech)]} { set _lef_file $::tech(lef_tech) }
            set _def_file ""
            if {[info exists ::sta(input,def_file)]} { set _def_file $::sta(input,def_file) }

            if {$test_mode} {
                puts "INFO: \[TEST MODE\] Extraction for RC corner: $subnode_name"
                puts "INFO:   RC file:     $_rc_file ($_rc_file_type)"
                puts "INFO:   LEF:         $_lef_file"
                puts "INFO:   DEF:         $_def_file"
                puts "INFO:   Corner dir:  $_corner_dir"
                set _spef "$_corner_dir/results/${node_name}_${subnode_name}.spef"
                set fh [open $_spef "w"]
                puts $fh "// SPEF for $subnode_name extraction (QRC/Quantus)"
                puts $fh "// Corner: $subnode_name  Node: $node_name"
                puts $fh "// RC file: $_rc_file ($_rc_file_type)"
                puts $fh "// Generated: [clock format [clock seconds]]"
                close $fh
                puts "INFO: Mock SPEF: $_spef"
                puts "INFO: extraction $subnode_name completed \[TEST MODE\]"
            } else {
                set _work_dir "$_corner_dir/run"
                set _spef_out "$_corner_dir/results/${node_name}_${subnode_name}.spef"
                set _qrc_cmd "$_work_dir/qrc_cmd_${subnode_name}"
                set _quantus_bin "quantus"
                if {[info exists ::sta(extraction,quantus_binary)]} { set _quantus_bin $::sta(extraction,quantus_binary) }
                set _fh [open $_qrc_cmd "w"]
                puts $_fh "extract_typ_file $_rc_file"
                if {$_lef_file ne ""} { puts $_fh "lef_file $_lef_file" }
                if {$_def_file ne ""} { puts $_fh "def_file $_def_file" }
                puts $_fh "output_name $_spef_out"
                puts $_fh "output_format SPEF"
                puts $_fh "coupled_extraction YES"
                close $_fh
                puts "INFO: Generated QRC cmd: $_qrc_cmd"
                file mkdir "$_work_dir/qrc_work"
                if {[catch {exec $_quantus_bin -cmd $_qrc_cmd >& "$_work_dir/${node_name}_${subnode_name}.log"} result]} {
                    puts "ERROR: QRC extraction $subnode_name failed: $result"; exit 1
                }
                puts "INFO: extraction $subnode_name completed"
            }
        } else {
            puts "ERROR: Unknown subnode: $subnode_name"
            exit 1
        }
    }
}
