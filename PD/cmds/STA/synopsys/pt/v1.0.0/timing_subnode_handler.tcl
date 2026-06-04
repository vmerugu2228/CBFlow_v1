#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — timing Subnode Handler (Synopsys PT)
# Subnodes: setup, run, validate, finish
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "timing"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(PT_VERSION)] ? $::env(PT_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/synopsys/pt/$_tool_ver/timing_pt.tcl"

set test_mode [handler_is_test_mode]

switch $subnode_name {
    "setup" {
        puts "INFO: $stage_name setup..."
        handler_setup $run_dir $::flow_type $node_name
        puts "INFO: $stage_name setup completed"
    }
    "run" {
        puts "INFO: $stage_name run..."
        set _tool [expr {[info exists sta(tool,name)] ? $sta(tool,name) : "pt"}]
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
    "dynamic" {
        # Resolve MMMC scenarios and run per-scenario timing
        puts "INFO: $stage_name dynamic — resolving MMMC scenarios..."
        set mmmc_cfg "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $mmmc_cfg]} { uplevel #0 [list source $mmmc_cfg] }

        set setup_scenarios {}
        set hold_scenarios {}
        if {[info exists ::sta(mmmc,setup_scenarios)] && $::sta(mmmc,setup_scenarios) ne ""} {
            set setup_scenarios $::sta(mmmc,setup_scenarios)
        }
        if {[info exists ::sta(mmmc,hold_scenarios)] && $::sta(mmmc,hold_scenarios) ne ""} {
            set hold_scenarios $::sta(mmmc,hold_scenarios)
        }
        set all_scenarios [lsort -unique [concat $setup_scenarios $hold_scenarios]]
        if {[llength $all_scenarios] == 0} {
            set all_scenarios {func_ss_0p76v_rcmax_150c func_ff_0p84v_rcmin_m40c}
        }
        puts "INFO: MMMC scenarios: [llength $all_scenarios]"

        set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir $_work_dir
        file mkdir "$run_dir/reports/sta"

        foreach scenario $all_scenarios {
            if {$test_mode} {
                set rpt [open "$run_dir/reports/sta/timing_${scenario}_summary.rpt" "w"]
                puts $rpt "# Test mode: $scenario — Setup WNS: 0.000ns  Hold WNS: 0.000ns"
                close $rpt
                puts "INFO: \[TEST MODE\] Scenario $scenario done"
            }
        }
        puts "INFO: $stage_name dynamic completed"
    }
    default {
        # Per-scenario MMMC subnode (e.g., func_ss_0p76v_rcmax_150c)
        set scenario $subnode_name
        puts "INFO: $stage_name scenario: $scenario"

        set mmmc_cfg "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $mmmc_cfg]} { uplevel #0 [list source $mmmc_cfg] }

        set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir $_work_dir
        file mkdir "$run_dir/reports/sta"

        # Write context + stub report
        if {[info exists ::analysis_views($scenario)]} {
            array set _sv $::analysis_views($scenario)
            set _ctx "$_work_dir/${scenario}_context.tcl"
            set _fh [open $_ctx "w"]
            puts $_fh "set ::CORNER \"$_sv(corner)\""
            puts $_fh "set ::MODE \"$_sv(mode)\""
            puts $_fh "set ::VOLTAGE \"$_sv(voltage)\""
            puts $_fh "set ::TEMPERATURE \"$_sv(temperature)\""
            puts $_fh "set ::RC_CORNER \"$_sv(rc_corner)\""
            puts $_fh "set ::LIB_SET \"$_sv(lib_set_ref)\""
            close $_fh
        }

        if {$test_mode} {
            set rpt [open "$run_dir/reports/sta/timing_${scenario}_summary.rpt" "w"]
            puts $rpt "# Test mode: $scenario — Setup WNS: 0.000ns"
            close $rpt
            puts "INFO: \[TEST MODE\] Scenario $scenario completed"
        } else {
            set _tool [expr {[info exists ::sta(tool,name)] ? $::sta(tool,name) : "pt"}]
            set scenario_cmd "$::env(FLOW_DIR)/cmds/STA/synopsys/pt/$_tool_ver/timing_scenario_pt.tcl"
            handler_run $run_dir $::flow_type $node_name $scenario $scenario_cmd false $_tool
        }
    }
}
