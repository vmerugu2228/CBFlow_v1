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
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/release_utils.tcl"

# PD release_config.tcl (handshake map, release(file,*)) — not part of the
# node config; loaded once on demand.
proc release_config_load {} {
    if {![array exists ::flow_input_handshake]} {
        uplevel #0 [list source "$::env(FLOW_DIR)/PD/config/flow/[cbflow_version FLOW_CONFIG_VERSION]/release_config.tcl"]
    }
}

# Release names that downstream flows consume: {category file} from
# flow_input_handshake(<flow>,<input>).
proc release_handshake {flow input} {
    release_config_load
    if {![info exists ::flow_input_handshake($flow,$input)]} {
        error "flow_input_handshake($flow,$input) is not set (PD release_config.tcl)"
    }
    lassign $::flow_input_handshake($flow,$input) _src _cat _file
    return [list $_cat [string map [list {${design_name}} $::design_name] $_file]]
}

flow_proc publish {
    global design_name
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [cbflow_run_phase]]
    set _ex "[cbflow_node_dir [oss_chain_node export_data]]/outputs"
    # Names PNR reads from this release (handshake PNR,<input>)
    foreach {_src _in} {final.v netlist final.sdc sdc final.upf upf_file} {
        ::CBFlow::Release::copy_file "$_ex/$_src" {*}[release_handshake PNR $_in]
    }
    # DFT scan-shift SDC (scan mode) beside the functional one
    if {[file exists "$_ex/final.scan.sdc"]} {
        ::CBFlow::Release::copy_file "$_ex/final.scan.sdc" sdc ${design_name}.scan.sdc
    }
    ::CBFlow::Release::copy_glob "[cbflow_node_dir [oss_chain_node synthesis]]/reports/*.rpt" reports
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir\ndesign $design_name\nlevel [hier_level $design_name]"
    close $_fh
    handle_info "Released $design_name synthesis -> $_dir"
}

flow_exec_all
exit
