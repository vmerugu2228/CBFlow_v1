#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow FP — release_data (opensource / tclsh)
# Publish the floorplan to <release,path>/<phase>/<design>/<tag>/ (def, db,
# netlist, sdc, upf, reports) — PNR picks it up by tag
# (pnr(input,def_file_release_tag)).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "FP"
set STAGE_NAME "release_data"
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "release_data1"}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [oss_get project release,phase]]
    set _ex "$::run_dir/work/$::FLOW_TYPE/[oss_chain_node export_data]/outputs"
    ::CBFlow::Release::copy_file "$_ex/final.def" def     ${design_name}.def
    ::CBFlow::Release::copy_file "$_ex/final.odb" db      ${design_name}.odb
    ::CBFlow::Release::copy_file "$_ex/final.v"   netlist ${design_name}.v
    ::CBFlow::Release::copy_file "$_ex/final.sdc" sdc     ${design_name}.sdc
    if {[file exists "$_ex/final.upf"]} {
        ::CBFlow::Release::copy_file "$_ex/final.upf" upf ${design_name}.upf
    }
    foreach _n [lmap _t {init_design floorplan powerplan export_data} {oss_chain_node $_t}] {
        ::CBFlow::Release::copy_glob "$::run_dir/work/$::FLOW_TYPE/$_n/reports/*.rpt" reports
    }
    # SmartGrid metrics of the exit (node from fp(checklist,exit_node,<exit>))
    set _ms [::CBFlow::Release::default_exit_tag $::FLOW_TYPE [oss_get project release,phase]]
    set _xr "$::run_dir/work/$::FLOW_TYPE/[oss_get fp checklist,exit_node,$_ms]/reports"
    ::CBFlow::Release::copy_file "$_xr/checklist_metrics.rpt" . metrics.rpt
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir"
    puts $_fh "design $design_name"
    puts $_fh "level [hier_level $design_name]"
    # The phase's exit for this flow (project(phase_exits)), e.g. PNR in P0
    # -> PRO_EXIT; also the default release tag.
    puts $_fh "milestone [::CBFlow::Release::default_exit_tag $::FLOW_TYPE [oss_get project release,phase]]"
    close $_fh
    handle_info "Released floorplan $design_name -> $_dir"
}

flow_exec_all
exit
