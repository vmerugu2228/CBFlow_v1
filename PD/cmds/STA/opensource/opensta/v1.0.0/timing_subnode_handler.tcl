#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow STA (opensource) — timing Subnode Handler
# Subnodes: setup, <scenario> (dynamic: one per MMMC scenario — OpenSTA with
# the scenario's lib set, SDC and its RC corner's SPEF), validate, finish.
# ═══════════════════════════════════════════════════════════════════════════════

source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/handler_common.tcl"
source "$::env(SCRIPTS_ROOT)/utilities/$::env(UTILITIES_VERSION)/launch_utils.tcl"

lassign [handler_parse_args $argv $argc] subnode_name run_dir node_name
handler_load_configs $run_dir "STA"

set ::flow_type "STA"
set stage_name "timing"
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
        set scenario $subnode_name
        foreach _m [list "$::env(CBFLOW_GLOBAL_DIR)/config/project/$::env(CBFLOW_PROJECT_NAME)/$::env(FLOW_CONFIG_VERSION)/mmmc_config.tcl"] {
            if {[file exists $_m]} { uplevel #0 [list source $_m] }
        }
        if {![info exists ::analysis_views($scenario)]} {
            puts "ERROR: scenario '$scenario' not in analysis_views (mmmc_config.tcl)"; exit 1
        }
        array set _sv $::analysis_views($scenario)
        set _dsg $::flow(design_name)
        # SDC: the mode's constraint file (operating_modes), else the staged SDC.
        set _sdc_dir "$run_dir/work/$::flow_type/sdc1/sdc"
        set _cf [string map [list {${design_name}} $_dsg] $_sv(constraint_file)]
        set _sdc [lindex [glob -nocomplain "$_sdc_dir/$_cf" "$_sdc_dir/${_dsg}.$_sv(mode).sdc" "$_sdc_dir/${_dsg}.sdc" "$_sdc_dir/*.sdc"] 0]
        # SPEF: this scenario's RC corner from the upstream extraction node.
        set _ext [lindex [expr {[info exists ::sta(dependencies,$node_name)] ? $::sta(dependencies,$node_name) : "extraction1"}] 0]
        set _spef "$run_dir/work/$::flow_type/$_ext/$_sv(rc_corner)/results/${_dsg}_$_sv(rc_corner).spef"
        set _dir "$run_dir/work/$::flow_type/$node_name/$scenario"
        file mkdir "$_dir/run" "$_dir/reports"
        set _ctx "$_dir/run/${scenario}.tcl"
        set _fh [open $_ctx w]
        puts $_fh "# CBflow STA scenario context — $scenario"
        puts $_fh "set ::OSS_NODE     \"$node_name\""
        puts $_fh "set ::SCENARIO     \"$scenario\""
        puts $_fh "set ::MODE         \"$_sv(mode)\""
        puts $_fh "set ::LIB_SET      \"$_sv(lib_set_ref)\""
        puts $_fh "set ::RC_CORNER    \"$_sv(rc_corner)\""
        puts $_fh "set ::SDC_FILE     \"$_sdc\""
        puts $_fh "set ::SPEF_FILE    \"$_spef\""
        puts $_fh "set ::SCEN_REPORTS \"$_dir/reports\""
        puts $_fh "source \"$::env(FLOW_DIR)/PD/cmds/STA/opensource/opensta/$_tool_ver/timing_opensta.tcl\""
        close $_fh
        if {$test_mode} {
            set _fh [open "$_dir/reports/qor.tcl" w]
            puts $_fh "set qor(scenario) \"$scenario\"\nset qor(wns_setup) 0.0\nset qor(wns_hold) 0.0\nset qor(tns_setup) 0.0\nset qor(tns_hold) 0.0"
            close $_fh
            puts "INFO: \[TEST MODE\] timing $scenario"
        } else {
            set _wrapper [generate_launch_wrapper "$_dir/run" $scenario $_ctx \
                              $::sta(oss,tool,timing) "$_dir/run/${scenario}.log"]
            submit_job $_wrapper $::flow_type $scenario $node_name "$_dir/run"
            if {![file exists "$_dir/reports/qor.tcl"]} {
                puts "ERROR: timing $scenario produced no QoR ($_dir/reports/qor.tcl)"; exit 1
            }
        }
        file mkdir "$run_dir/work/$::flow_type/$node_name/outputs"
        file copy -force "$_dir/reports/qor.tcl" "$run_dir/work/$::flow_type/$node_name/outputs/${scenario}_qor.tcl"
        puts "INFO: timing $scenario completed"
    }
}
