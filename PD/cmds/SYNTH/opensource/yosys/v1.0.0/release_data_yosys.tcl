#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SYNTH — release_data (opensource / tclsh)
# Publish the synthesis release <release,path>/<phase>/<design>/<tag>/:
# netlist/<d>.v, sdc/<d>.sdc, upf/<d>.upf (consumed by PNR via release_tag).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
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
    ::CBFlow::Release::copy_file "$_ex/final.v"   netlist ${design_name}.v
    ::CBFlow::Release::copy_file "$_ex/final.sdc" sdc     ${design_name}.sdc
    ::CBFlow::Release::copy_file "$_ex/final.upf" upf     ${design_name}.upf
    ::CBFlow::Release::copy_glob "$::run_dir/work/$::FLOW_TYPE/[oss_chain_node synthesis]/reports/*.rpt" reports
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir\ndesign $design_name\nlevel [hier_level $design_name]"
    close $_fh
    handle_info "Released $design_name synthesis -> $_dir"
}

flow_exec_all
exit
