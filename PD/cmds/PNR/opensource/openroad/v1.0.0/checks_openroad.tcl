#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow — checklist library reports for a finished node (opensource / openroad)
# Report-only: loads the node's own database (+ timing views, SDC, the pro
# SPEF from pro on) and writes the check reports (oss_checks_run) into its
# reports/ — no implementation step re-runs. Launched by global/bin/
# cbflow-oss-checks <run_dir> <node> (FP and PNR nodes).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE $::env(CBFLOW_FLOW_TYPE)
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
set STAGE_NAME [cbflow_node_type $NODE_NAME]
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: this node's database (outputs/<stage>.odb, else final.odb), timing
# views, SDC; propagated clocks from CTS on; SPEF from pro on.
flow_proc load_design {
    global blocks
    set_thread_count [oss_get [oss_flow_arr] oss,threads]
    oss_read_corners $::NODE_NAME $blocks
    set _out "[cbflow_node_dir $::NODE_NAME]/outputs"
    set _odb [lindex [glob -nocomplain "$_out/$::STAGE_NAME.odb" "$_out/final.odb" "$_out/*.odb"] 0]
    if {$_odb eq ""} { error "no database in $_out — did $::NODE_NAME complete?" }
    read_db $_odb
    read_sdc [oss_sdc_file]
    if {$::STAGE_NAME in {cts cts_opt route pro signoff}} { set_propagated_clock [all_clocks] }
    set _pro ""
    if {$::STAGE_NAME eq "pro"} { set _pro $::NODE_NAME } elseif {$::STAGE_NAME eq "signoff"} { set _pro [oss_upstream_node] }
    if {$_pro ne ""} {
        foreach _v [oss_node_views $::NODE_NAME] {
            set _s "[cbflow_node_dir $_pro]/outputs/final_[oss_view_attr $_v rc_corner].spef"
            if {[file exists $_s]} { read_spef -corner $_v $_s }
        }
    } else {
        oss_set_wire_rc
        catch { estimate_parasitics -placement }
    }
}

# Report: the checklist library reports of this stage
flow_proc report {
    oss_checks_run $::STAGE_NAME
}

flow_exec_all
exit
