#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow PNR — cts_opt (opensource / openroad)
# Post-CTS setup + hold repair across the node's MMMC corners.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "PNR"
set STAGE_NAME "cts_opt"
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
    oss_load_stage [oss_upstream_node] 0
    set_propagated_clock [all_clocks]
    estimate_parasitics -placement
}

# Constraints: SDC + OCV derate (project mmmc_config timing_derate_early / late)
flow_proc read_constraints {
    read_sdc [oss_sdc_file]
    oss_apply_derate
    oss_drv_limits                   ;# pnr(oss,drv,*) after the SDC
}

# Setup + hold repair, legalization
flow_proc repair {
    global pnr
    repair_timing -setup -setup_margin [oss_get pnr oss,repair,setup_margin]
    repair_timing -hold  -hold_margin  [oss_get pnr oss,repair,hold_margin]
    detailed_placement
    check_placement
    estimate_parasitics -placement
}

# Reports: QoR, timing, area, checklist metrics, timing snapshot
flow_proc report {
    oss_write_qor cts_opt
}

# Save the repaired database
flow_proc save_design {
    global_connect                    ;# supply pins of cells added in this stage (UPF rules in the db)
    write_db [oss_stage_out cts_opt.odb]
}

flow_exec_all
exit
