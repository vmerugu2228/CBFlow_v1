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
    oss_load_node $::NODE_NAME $blocks 0
}

# Constraints: SDC + OCV derate (project mmmc_config timing_derate_early / late)
flow_proc read_constraints {
    read_sdc [oss_sdc_file]
    oss_apply_derate
    oss_stage_clocks $::NODE_NAME
}

# Report: the checklist library reports of this stage
# (FP: the tag its export step reports under, "fp")
flow_proc report {
    oss_checks_run [expr {$::FLOW_TYPE eq "FP" ? "fp" : $::STAGE_NAME}]
}

flow_exec_all
exit
