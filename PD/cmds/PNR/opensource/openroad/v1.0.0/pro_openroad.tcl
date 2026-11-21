#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — pro (opensource / openroad)
# Post-route: filler insertion, OpenRCX extraction per RC corner of the
# node's views, post-route timing.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "pro"
set NODE_NAME [expr {[info exists ::env(CBFLOW_NODE_NAME)] && $::env(CBFLOW_NODE_NAME) ne "" ? $::env(CBFLOW_NODE_NAME) : "pro1"}]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load {
    oss_load_stage [oss_upstream_node]
    set_propagated_clock [all_clocks]
}

flow_proc fill {
    filler_placement [oss_trk fillers]
    global_connect                    ;# UPF-derived rules are stored in the database
    check_placement
}

# One SPEF per RC corner; each view reads the SPEF of its rc_corner.
flow_proc extract {
    set _done {}
    define_process_corner -ext_model_index 0 X
    foreach _v [oss_node_views $::NODE_NAME] {
        set _rc [oss_view_attr $_v rc_corner]
        if {[lsearch -exact $_done $_rc] < 0} {
            extract_parasitics -ext_model_file [oss_get tech rcx,$_rc,openrcx]
            write_spef [oss_stage_out final_${_rc}.spef]
            lappend _done $_rc
        }
        read_spef -corner $_v [oss_stage_out final_${_rc}.spef]
    }
}

flow_proc report {
    write_db [oss_stage_out pro.odb]
    oss_write_qor pro
}

flow_exec_all
exit
