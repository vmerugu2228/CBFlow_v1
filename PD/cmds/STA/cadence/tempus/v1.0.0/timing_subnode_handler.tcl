#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA — timing Subnode Handler (Cadence Tempus)
# Subnodes: setup, run, validate, finish, dynamic, <scenario> (MMMC)
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "timing"
if {$node_name eq ""} { set node_name "${stage_name}1" }

set _tool_ver [expr {[info exists ::env(TEMPUS_VERSION)] ? $::env(TEMPUS_VERSION) : "v1.0.0"}]
set cmd_file "$::env(FLOW_DIR)/cmds/STA/cadence/tempus/$_tool_ver/timing_tempus.tcl"

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
    "dynamic" {
        # Resolve MMMC scenarios and run per-scenario timing
        puts "INFO: $stage_name dynamic — resolving MMMC scenarios..."

        set mmmc_config_file "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $mmmc_config_file]} { source $mmmc_config_file }

        set setup_scenarios {}
        set hold_scenarios {}

        if {[info exists ::sta(mmmc,setup_scenarios)] && $::sta(mmmc,setup_scenarios) ne ""} {
            set setup_scenarios $::sta(mmmc,setup_scenarios)
        } elseif {[info exists mmmc_scenario_sets] && [array exists mmmc_scenario_sets]} {
            set sset [expr {[info exists ::sta(mmmc,scenario_set)] ? $::sta(mmmc,scenario_set) : "sta_signoff"}]
            if {$sset ne "custom" && [info exists mmmc_scenario_sets($sset)]} {
                array set _ss $mmmc_scenario_sets($sset)
                if {[info exists _ss(scenarios)]} { set setup_scenarios $_ss(scenarios) }
            }
        }
        if {[info exists ::sta(mmmc,hold_scenarios)] && $::sta(mmmc,hold_scenarios) ne ""} {
            set hold_scenarios $::sta(mmmc,hold_scenarios)
        }

        set all_scenarios [lsort -unique [concat $setup_scenarios $hold_scenarios]]
        if {[llength $all_scenarios] == 0} {
            set all_scenarios {func_ss_0p76v_rcmax_150c func_ff_0p84v_rcmin_m40c}
        }

        puts "INFO: MMMC scenarios to run ([llength $all_scenarios]):"
        puts "INFO:   Setup: $setup_scenarios"
        puts "INFO:   Hold:  $hold_scenarios"

        set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir $_work_dir
        file mkdir "$run_dir/reports/sta"

        set _scenario_handler "$::env(FLOW_DIR)/cmds/STA/cadence/tempus/$_tool_ver/timing_scenario_handler.tcl"

        foreach scenario $all_scenarios {
            puts "INFO: -- Scenario: $scenario --"
            if {$test_mode} {
                if {[file exists $_scenario_handler]} {
                    catch {exec tclsh $_scenario_handler $scenario $run_dir} result
                    puts $result
                } else {
                    puts "INFO: \[TEST MODE\] Scenario $scenario — creating stubs"
                    set rpt [open "$run_dir/reports/sta/timing_${scenario}_summary.rpt" "w"]
                    puts $rpt "# Test mode: $scenario"
                    puts $rpt "Setup WNS: 0.000ns  Hold WNS: 0.000ns"
                    close $rpt
                }
            } else {
                if {[file exists $_scenario_handler]} {
                    if {[catch {exec tclsh $_scenario_handler $scenario $run_dir} result]} {
                        puts "ERROR: Scenario $scenario failed: $result"; exit 1
                    }
                    puts $result
                } else {
                    puts "ERROR: Scenario handler not found: $_scenario_handler"; exit 1
                }
            }
        }
        puts "INFO: $stage_name dynamic completed — [llength $all_scenarios] scenarios processed"
    }
    default {
        # Per-scenario MMMC subnode (e.g., func_ss_0p76v_rcmax_150c)
        set scenario $subnode_name
        puts "INFO: $stage_name scenario: $scenario"

        set _mmmc_cfg "$::env(CONFIG_ROOT)/flow/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"
        if {[file exists $_mmmc_cfg]} { source $_mmmc_cfg }

        if {![info exists analysis_views($scenario)]} {
            puts "ERROR: Scenario '$scenario' not found in analysis_views"
            exit 1
        }
        array set _sv $analysis_views($scenario)

        set _work_dir "$run_dir/work/$::flow_type/$node_name/run"
        file mkdir $_work_dir
        file mkdir "$run_dir/reports/sta"

        # Write scenario context file
        set _ctx "$_work_dir/${scenario}_context.tcl"
        set _fh [open $_ctx "w"]
        puts $_fh "set ::scenario_name \"$scenario\""
        puts $_fh "set ::CORNER \"$_sv(corner)\""
        puts $_fh "set ::MODE \"$_sv(mode)\""
        puts $_fh "set ::VOLTAGE \"$_sv(voltage)\""
        puts $_fh "set ::TEMPERATURE \"$_sv(temperature)\""
        puts $_fh "set ::RC_CORNER \"$_sv(rc_corner)\""
        puts $_fh "set ::LIB_SET \"$_sv(lib_set_ref)\""
        puts $_fh "set ::DESIGN_NAME \"$::flow(design_name)\""
        set _sdc_dir "$run_dir/work/$::flow_type/sdc1/sdc"
        puts $_fh "set ::SDC_FILE \"$_sdc_dir/$_sv(constraint_file)\""
        set _spef_manifest "$_work_dir/../setup/spef_manifest.tcl"
        if {[file exists $_spef_manifest]} {
            source $_spef_manifest
            if {[info exists spef_map($_sv(rc_corner))]} {
                puts $_fh "set ::SPEF_FILE \"$spef_map($_sv(rc_corner))\""
            }
        }
        close $_fh

        set scenario_cmd "$::env(FLOW_DIR)/cmds/STA/cadence/tempus/$_tool_ver/timing_scenario_tempus.tcl"

        if {$test_mode} {
            puts "INFO: \[TEST MODE\] Scenario $scenario"
            puts "INFO:   Corner=$_sv(corner) Mode=$_sv(mode) Voltage=$_sv(voltage) Temp=$_sv(temperature)"
            set rpt [open "$run_dir/reports/sta/timing_${scenario}_summary.rpt" "w"]
            puts $rpt "# Test mode: $scenario"
            puts $rpt "Setup WNS: 0.000ns  Hold WNS: 0.000ns"
            close $rpt
            puts "INFO: $stage_name scenario $scenario completed \[TEST MODE\]"
        } else {
            set _tool [expr {[info exists ::sta(tool,name)] ? $::sta(tool,name) : "tempus"}]
            handler_run $run_dir $::flow_type $node_name $scenario $scenario_cmd false $_tool
            puts "INFO: $stage_name scenario $scenario completed"
        }
    }
}
