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
if {$node_name eq ""} { set node_name [cbflow_node_name] }
set _tool_ver [expr {[info exists ::env(OPENSTA_VERSION)] && $::env(OPENSTA_VERSION) ne "" ? $::env(OPENSTA_VERSION) : [cbflow_require sta tool,version]}]
set test_mode [handler_is_test_mode]
# Node-graph helpers (cbflow_dep_node / cbflow_node_dir) read these.
set ::FLOW_TYPE $::flow_type
set ::NODE_NAME $node_name

# Upstream "inputs" node of input type <type> (RACE engine: input type = node
# name without its number) — where that input is staged: <node>/<type>/.
proc sta_input_dir {type} {
    set _todo [cbflow_node_deps $::NODE_NAME]
    set _seen {}
    while {[llength $_todo]} {
        set _n [lindex $_todo 0]; set _todo [lrange $_todo 1 end]
        if {$_n in $_seen} continue
        lappend _seen $_n
        if {[cbflow_node_type $_n] eq "inputs" && [string trimright $_n 0123456789] eq $type} {
            return "[cbflow_node_dir $_n]/$type"
        }
        lappend _todo {*}[cbflow_node_deps $_n]
    }
    error "no '$type' input node upstream of $::NODE_NAME"
}

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
        set _m "$::env(CBFLOW_GLOBAL_DIR)/config/project/$::env(CBFLOW_PROJECT_NAME)/[cbflow_version PROJECT_CONFIG_VERSION]/mmmc_config.tcl"
        if {![file exists $_m]} { puts "ERROR: MMMC config not found: $_m"; exit 1 }
        uplevel #0 [list source $_m]
        if {![info exists ::analysis_views($scenario)]} {
            puts "ERROR: scenario '$scenario' not in analysis_views (mmmc_config.tcl)"; exit 1
        }
        array set _sv $::analysis_views($scenario)
        set _dsg $::flow(design_name)
        # SDC: the mode's constraint file (operating_modes), else the staged
        # <design>.<mode>.sdc / <design>.sdc.
        set _sdc_dir [sta_input_dir sdc]
        set _cf [string map [list {${design_name}} $_dsg] $_sv(constraint_file)]
        set _sdc [lindex [glob -nocomplain "$_sdc_dir/$_cf" "$_sdc_dir/${_dsg}.$_sv(mode).sdc" "$_sdc_dir/${_dsg}.sdc"] 0]
        if {$_sdc eq "" && !$test_mode} {
            puts "ERROR: no SDC for mode $_sv(mode) in $_sdc_dir (expected $_cf, ${_dsg}.$_sv(mode).sdc or ${_dsg}.sdc)"; exit 1
        }
        # SPEF: this scenario's RC corner from the upstream extraction node
        # (sta(oss,extraction,spef) under <extraction node>/<rc_corner>/).
        set _spef "[cbflow_node_dir [cbflow_dep_node extraction]]/$_sv(rc_corner)/[string map [list {${design_name}} $_dsg {${rc_corner}} $_sv(rc_corner)] [cbflow_require sta oss,extraction,spef]]"
        set _qor [cbflow_require sta oss,scenario_qor_file]
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
            set _fh [open "$_dir/reports/$_qor" w]
            puts $_fh "set qor(scenario) \"$scenario\"\nset qor(wns_setup) 0.0\nset qor(wns_hold) 0.0\nset qor(tns_setup) 0.0\nset qor(tns_hold) 0.0"
            close $_fh
            puts "INFO: \[TEST MODE\] timing $scenario"
        } else {
            set _wrapper [generate_launch_wrapper "$_dir/run" $scenario $_ctx \
                              $::sta(oss,tool,timing) "$_dir/run/${scenario}.log"]
            submit_job $_wrapper $::flow_type $scenario $scenario "$_dir/run"
            if {![file exists "$_dir/reports/$_qor"]} {
                puts "ERROR: timing $scenario produced no QoR ($_dir/reports/$_qor)"; exit 1
            }
        }
        file mkdir "$run_dir/work/$::flow_type/$node_name/outputs"
        file copy -force "$_dir/reports/$_qor" "$run_dir/work/$::flow_type/$node_name/outputs/${scenario}[cbflow_require sta oss,qor_file_suffix]"
        puts "INFO: timing $scenario completed"
    }
}
