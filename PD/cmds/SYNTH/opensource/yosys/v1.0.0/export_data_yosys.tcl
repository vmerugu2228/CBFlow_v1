#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SYNTH — export_data (opensource / tclsh)
# Synthesis deliverables under canonical names: final.v (netlist),
# final.sdc (functional mode constraints), final.upf (power intent).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SYNTH"
set STAGE_NAME "export_data"
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "export_data1"}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc export {
    global design_name
    file copy -force [oss_node_output [oss_chain_node synthesis] synthesis.v] [oss_stage_out final.v]
    # One mode per design for the open-source flow (see PNR/STA).
    set _modes {}
    foreach _v [oss_node_views [oss_chain_node synthesis]] {
        set _m [oss_view_attr $_v mode]
        if {$_m ni $_modes} { lappend _modes $_m }
    }
    if {[llength $_modes] != 1} { error "opensource flow times one mode per design; synthesis views use: $_modes" }
    set _sdc [lindex [glob -nocomplain "$::SDC_DIR/${design_name}.[lindex $_modes 0].sdc" "$::SDC_DIR/${design_name}.sdc" "$::SDC_DIR/*.sdc"] 0]
    if {$_sdc eq ""} { error "SDC not staged in $::SDC_DIR" }
    set _upf [lindex [glob -nocomplain "$::UPF_DIR/${design_name}.upf" "$::UPF_DIR/*.upf"] 0]
    if {$_upf eq ""} { error "UPF not staged in $::UPF_DIR" }
    foreach {_src _dst} [list $_sdc final.sdc $_upf final.upf] {
        # staged inputs are symlinks — copy the content
        while {[file type $_src] eq "link"} { set _src [file normalize [file join [file dirname $_src] [file readlink $_src]]] }
        file copy -force $_src [oss_stage_out $_dst]
    }
}

flow_exec_all
exit
