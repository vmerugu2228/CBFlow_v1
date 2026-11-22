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
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: locate the synthesis node's netlist, the functional SDC and the UPF
flow_proc load_design {
    global design_name
    set ::export_netlist [oss_node_output [oss_chain_node synthesis] synthesis.v]
    # One mode per design for the open-source flow (see PNR/STA).
    set _modes {}
    foreach _v [oss_node_views [oss_chain_node synthesis]] {
        set _m [oss_view_attr $_v mode]
        if {$_m ni $_modes} { lappend _modes $_m }
    }
    if {[llength $_modes] != 1} { error "opensource flow times one mode per design; synthesis views use: $_modes" }
    set _sdc [lindex [glob -nocomplain "$::SDC_DIR/${design_name}.[lindex $_modes 0].sdc" "$::SDC_DIR/${design_name}.sdc"] 0]
    if {$_sdc eq ""} { error "SDC not staged in $::SDC_DIR (expected ${design_name}.[lindex $_modes 0].sdc or ${design_name}.sdc)" }
    set _upf "$::UPF_DIR/${design_name}.upf"
    if {![file exists $_upf]} { error "UPF not staged: $_upf" }
    # DFT: the synthesis node wrote the functional SDC (scan enable held 0)
    # and the scan-shift SDC next to the scan netlist
    set _sn "[cbflow_node_dir [oss_chain_node synthesis]]/outputs"
    if {[is_true [oss_get project dft,enable]]} { set _sdc "$_sn/synthesis.func.sdc" }
    set ::export_sdc $_sdc
    set ::export_upf $_upf
    set ::export_scan_sdc "$_sn/synthesis.scan.sdc"
}

# No operation / report step: export_data only copies the deliverables.

# Save the deliverables under canonical names: final.v, final.scan.sdc
# (DFT), final.sdc, final.upf
flow_proc save_design {
    file copy -force $::export_netlist [oss_stage_out final.v]
    if {[is_true [oss_get project dft,enable]]} {
        file copy -force $::export_scan_sdc [oss_stage_out final.scan.sdc]
    }
    foreach {_src _dst} [list $::export_sdc final.sdc $::export_upf final.upf] {
        # staged inputs are symlinks — copy the content
        while {[file type $_src] eq "link"} { set _src [file normalize [file join [file dirname $_src] [file readlink $_src]]] }
        file copy -force $_src [oss_stage_out $_dst]
    }
}

flow_exec_all
exit
