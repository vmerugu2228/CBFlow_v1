#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — place (opensource / openroad)
# Global + detailed placement and design repair on the init_design floorplan.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "place"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"

set design_name [oss_get flow design_name]
set blocks      [hier_children $design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

# Load: previous stage's database + timing views + SDC
flow_proc load_design { oss_load_stage [oss_upstream_node] }

# Global + detailed placement, design repair
flow_proc global_detailed_place {
    global pnr
    oss_set_wire_rc
    global_placement -density [oss_get pnr oss,place,density] -routability_driven
    estimate_parasitics -placement
    repair_design
    detailed_placement
    check_placement -verbose
}

# Reports: QoR, timing, area, checklist metrics, timing snapshot
flow_proc report {
    oss_write_qor place
}

# Save the placed database
flow_proc save_design {
    write_db [oss_stage_out place.odb]
}

flow_exec_all
exit
