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
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: previous stage's database + timing views + SDC, propagated clocks
flow_proc load_design {
    oss_load_stage [oss_upstream_node]
    set_propagated_clock [all_clocks]
}

# Filler insertion, supply connections of the new cells
flow_proc fill {
    filler_placement [oss_trk fillers]
    global_connect                    ;# UPF-derived rules are stored in the database
    check_placement
}

# Save the post-route database — before extraction: OpenRCX re-encodes the
# wires in the database (the detailed router then rejects them, DRT-1010, and
# check_drc reports false markers), so pro.odb / signoff's final.odb / the
# release keep the routed wiring as detailed route wrote it.
flow_proc save_design {
    write_db [oss_stage_out pro.odb]
}

# One SPEF per RC corner; each view reads the SPEF of its rc_corner. The
# SPEFs (outputs/final_<rc>.spef) are written here, not in save_design:
# read_spef loads them back for the post-route timing reports.
flow_proc extract {
    set _done {}
    define_process_corner -ext_model_index 0 X
    foreach _v [oss_node_views $::NODE_NAME] {
        set _rc [oss_view_attr $_v rc_corner]
        if {[lsearch -exact $_done $_rc] < 0} {
            oss_rcx_extract $_rc
            write_spef [oss_stage_out final_${_rc}.spef]
            oss_spef_check [oss_stage_out final_${_rc}.spef] $_rc
            lappend _done $_rc
        }
        read_spef -corner $_v [oss_stage_out final_${_rc}.spef]
    }
}

# Reports: post-route QoR, timing, area, checklist metrics, timing snapshot
flow_proc report {
    oss_write_qor pro
}

flow_exec_all
exit
