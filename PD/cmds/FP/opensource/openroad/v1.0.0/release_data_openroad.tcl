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
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [oss_get project release,phase]]
    set _ex "[cbflow_node_dir [oss_chain_node export_data]]/outputs"
    # Floorplan DEF under the name PNR reads (handshake PNR,def_file)
    ::CBFlow::Release::copy_file "$_ex/final.def" {*}[release_handshake PNR def_file]
    ::CBFlow::Release::copy_file "$_ex/final.odb" db      ${design_name}.odb
    ::CBFlow::Release::copy_file "$_ex/final.v"   netlist ${design_name}.v
    # PV at floorplan: GDS + power-aware LVS netlist under the PV handshake names
    ::CBFlow::Release::copy_file "$_ex/final.gds"   {*}[release_handshake PV gds]
    ::CBFlow::Release::copy_file "$_ex/final.lvs.v" {*}[release_handshake PV netlist]
    ::CBFlow::Release::copy_file "$_ex/final.sdc" sdc     ${design_name}.sdc
    if {[file exists "$_ex/final.upf"]} {
        ::CBFlow::Release::copy_file "$_ex/final.upf" upf ${design_name}.upf
    }
    foreach _n [lmap _t [oss_get fp oss,release,report_stages] {oss_chain_node $_t}] {
        ::CBFlow::Release::copy_glob "[cbflow_node_dir $_n]/reports/*.rpt" reports/$_n
    }
    # SmartGrid metrics of the exit: fp(checklist,report) of the exit node
    # (fp(checklist,exit_node,<exit>))
    set _ms [::CBFlow::Release::default_exit_tag $::FLOW_TYPE [oss_get project release,phase]]
    set _xn [oss_get fp checklist,exit_node,$_ms]
    ::CBFlow::Release::copy_file "$::run_dir/[string map [list {${exit_node}} $_xn] [oss_get fp checklist,report]]" . metrics.rpt
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
