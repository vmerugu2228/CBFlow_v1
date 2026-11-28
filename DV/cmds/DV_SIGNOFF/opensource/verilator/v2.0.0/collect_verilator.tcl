#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow DV_SIGNOFF — collect (opensource / container tclsh)
# Every DV exit of the phase's plan (project(phase_exits,DV), before
# DV_SIGNOFF_EXIT): released for the block (<release,path>/<phase>/<block>/
# <FLOW>/<exit>/RELEASE_COMPLETE) and its sign-off status -> outputs/exits.json,
# reports/collect.rpt.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "DV_SIGNOFF"
set STAGE_NAME "collect"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_DV_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dv_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"
flow_proc collect {
    global project
    set _ph [cbflow_run_phase]
    if {![info exists project(phase_exits,DV)] || ![dict exists $project(phase_exits,DV) $_ph]} {
        error "project(phase_exits,DV) has no entry for phase $_ph — the DV exits to sign off"
    }
    set _base [cbflow_require project release,path]
    set _rows {}; set _json {}
    foreach _e [dict get $project(phase_exits,DV) $_ph] {
        if {$_e eq "DV_SIGNOFF_EXIT"} continue
        set _c [glob -nocomplain "$_base/$_ph/$::design_name/*/$_e/RELEASE_COMPLETE"]
        if {![llength $_c]} { lappend _rows [list $_e "NOT RELEASED" ""]; continue }
        set _d [file dirname [lindex $_c 0]]
        set _r [lindex [concat [glob -nocomplain "$_d/reports/dv_signoff.rpt"] [glob -nocomplain "$_d/reports/sanity.rpt"]] 0]
        lappend _rows [list $_e [expr {$_r eq "" ? "NO REPORT" : [dv_status $_r]}] $_d]
    }
    set _L [list "DV exits — $::design_name $_ph (project(phase_exits,DV))"]
    foreach _x $_rows {
        lassign $_x _e _s _d
        lappend _L [format "  %-16s: %-12s %s" $_e $_s $_d]
        lappend _json "\"$_e\": \"$_s\""
    }
    oss_write_file "$::REPORTS_DIR/collect.rpt" "[join $_L \n]\n"
    oss_write_file [oss_stage_out exits.json] "{[join $_json {, }]}\n"
}

oss_exec_all
exit
