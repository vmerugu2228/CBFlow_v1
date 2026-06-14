#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — extraction Subnode Handler (Synopsys PT/StarRC)
# Subnodes: setup, run, validate, finish, rc_* (dynamic RC corners)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "extraction"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(PT_VERSION)] ? $::env(PT_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/synopsys/pt/$_tool_ver/extraction_pt.tcl"

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        puts "INFO: $stage_name setup completed"
    }
    "run" {
        puts "INFO: $stage_name run..."
        set _tool [expr {[info exists ::sta(tool,name)] ? $::sta(tool,name) : "pt"}]
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
        # Dynamic RC corner subnode (e.g., rc_max, rc_typ, rc_min)
        if {[string match "rc_*" $subnode_name]} {
            puts "INFO: extraction $subnode_name ($node_name)..."
            set _corner_dir "$run_dir/work/$::flow_type/$node_name/$subnode_name"
            file mkdir "$_corner_dir/run"
            file mkdir "$_corner_dir/results"

            set _rc_file ""
            set _rc_file_type ""
            set _rc_corner $subnode_name
            foreach _fmt {nxtgrd tluplus} {
                if {$_rc_file eq "" && [info exists ::tech(rcx,${_rc_corner},${_fmt})] && $::tech(rcx,${_rc_corner},${_fmt}) ne ""} {
                    set _rc_file $::tech(rcx,${_rc_corner},${_fmt})
                    set _rc_file_type $_fmt
                }
            }

            if {$test_mode} {
                puts "INFO: \[TEST MODE\] StarRC extraction: $subnode_name"
                puts "INFO:   RC file: $_rc_file ($_rc_file_type)"
                set _spef "$_corner_dir/results/${node_name}_${subnode_name}.spef"
                set fh [open $_spef "w"]
                puts $fh "// SPEF for $subnode_name (StarRC) [expr {[catch {clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}} _ts] ? "epoch [clock seconds]" : $_ts}]"
                close $fh
                puts "INFO: Mock SPEF: $_spef"
                puts "INFO: extraction $subnode_name completed \[TEST MODE\]"
            } else {
                set _spef_out "$_corner_dir/results/${node_name}_${subnode_name}.spef"
                set _star_cmd "$_corner_dir/run/star_cmd_${subnode_name}"
                set fh [open $_star_cmd "w"]
                if {$_rc_file_type eq "nxtgrd"} {
                    puts $fh "NXTGRD_FILE: $_rc_file"
                } else {
                    puts $fh "TCAD_GRD_FILE: $_rc_file"
                }
                puts $fh "EXTRACTION: RC"
                puts $fh "OUTPUT_FORMAT: SPEF"
                puts $fh "OUTPUT_FILE: $_spef_out"
                close $fh
                if {[catch {exec StarXtract $_star_cmd} result]} {
                    puts "ERROR: StarRC $subnode_name failed: $result"; exit 1
                }
                puts "INFO: extraction $subnode_name completed"
            }
        } else {
            puts "ERROR: Unknown subnode: $subnode_name"
            exit 1
        }
    }
}
