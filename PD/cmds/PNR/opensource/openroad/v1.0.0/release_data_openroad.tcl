#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — release_data (opensource / tclsh)
# Publish the block to <release,path>/<phase>/<design>/<tag>/: the views a
# parent block consumes (lef, gds, netlist, lib per lib set) + DEF/SPEF/SDC/CDL/db
# and signoff reports.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
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
    global design_name project
    set _dir [::CBFlow::Release::init $::FLOW_TYPE $design_name $::DIRS(run) [oss_get project release,phase]]
    set _so "$::run_dir/work/$::FLOW_TYPE/[oss_chain_node signoff]/outputs"
    set _pr "$::run_dir/work/$::FLOW_TYPE/[oss_chain_node pro]/outputs"
    ::CBFlow::Release::copy_file [oss_node_output [oss_chain_node export_data] final.gds] gds     ${design_name}.gds
    ::CBFlow::Release::copy_file "$_so/final.lef"                       lef     ${design_name}.lef
    ::CBFlow::Release::copy_file "$_so/final.v"                         netlist ${design_name}.v
    # STA handshake names: <d>.pt.v and the per-mode SDC (operating_modes)
    ::CBFlow::Release::copy_file "$_so/final.v"                         netlist ${design_name}.pt.v
    if {[array exists ::operating_modes]} {
        foreach _mode [array names ::operating_modes] {
            set _cf [string map [list {${design_name}} $design_name] \
                         [dict get $::operating_modes($_mode) constraint_file]]
            if {$_cf ne "${design_name}.sdc"} {
                ::CBFlow::Release::copy_file "$_so/final.sdc" sdc $_cf
            }
        }
    }
    ::CBFlow::Release::copy_file "$_so/final.lvs.v"                     netlist ${design_name}.lvs.v
    ::CBFlow::Release::copy_file "$_so/final.cdl"                       netlist ${design_name}.cdl
    ::CBFlow::Release::copy_file "$_so/final.def"                       def     ${design_name}.def
    ::CBFlow::Release::copy_file "$_so/final.sdc"                       sdc     ${design_name}.sdc
    ::CBFlow::Release::copy_file "$_so/final.odb"                       db      ${design_name}.odb
    foreach _lib [glob -nocomplain "$_so/final__*.lib"] {
        regsub {^final__} [file tail $_lib] "${design_name}__" _name
        ::CBFlow::Release::copy_file $_lib lib $_name
    }
    foreach _spef [glob -nocomplain "$_pr/final_*.spef"] {
        regsub {^final_} [file tail $_spef] "${design_name}_" _name
        ::CBFlow::Release::copy_file $_spef spef $_name
    }
    foreach _n [lmap _t {init_design place cts cts_opt route pro signoff} {oss_chain_node $_t}] {
        # per node: several nodes write the same report names
        ::CBFlow::Release::copy_glob "$::run_dir/work/$::FLOW_TYPE/$_n/reports/*.rpt" reports/$_n
        ::CBFlow::Release::copy_glob "$::run_dir/work/$::FLOW_TYPE/$_n/reports/*_qor.tcl" reports/$_n
    }
    # SmartGrid data of the exit this release fills: the exit node's metrics
    # and timing snapshot (node from pnr(checklist,exit_node,<exit>)) and the
    # routed-layout image.
    set _ms [::CBFlow::Release::default_exit_tag $::FLOW_TYPE [oss_get project release,phase]]
    set _xn [oss_get pnr checklist,exit_node,$_ms]
    set _xr "$::run_dir/work/$::FLOW_TYPE/$_xn/reports"
    ::CBFlow::Release::copy_file "$_xr/checklist_metrics.rpt" . metrics.rpt
    if {[file exists "$_xr/timing_snapshot.json"]} {
        ::CBFlow::Release::copy_file "$_xr/timing_snapshot.json" . timing_snapshot.json
    }
    set _img [oss_node_output [oss_chain_node export_data] layout.png]
    if {[file exists $_img]} { ::CBFlow::Release::copy_file $_img images routing_layout.png }
    ::CBFlow::Release::generate_manifest
    ::CBFlow::Release::stamp_complete
    set _fh [open [oss_stage_out release.manifest] w]
    puts $_fh "release_dir $_dir"
    puts $_fh "design $design_name"
    puts $_fh "level [hier_level $design_name]"
    # Exit milestone this release fills in SmartGrid (published by
    # `cbflow run all` on the host after the run passes).
    # The phase's exit for this flow (project(phase_exits)), e.g. PNR in P0
    # -> PRO_EXIT; also the default release tag.
    puts $_fh "milestone [::CBFlow::Release::default_exit_tag $::FLOW_TYPE [oss_get project release,phase]]"
    close $_fh
    handle_info "Released $design_name -> $_dir"
}

flow_exec_all
exit
