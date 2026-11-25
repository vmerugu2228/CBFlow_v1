#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — timing_sim (opensource / container tclsh → iverilog)
# Timing-aware (SDF-annotated) pattern simulation — post-PD only. Not
# supported by the open-source flow yet: iverilog's SDF annotation of the
# sky130 cell models is partial, so this stage fails rather than claim a
# result. Bypass it explicitly (cbflow run bypass --stages timing_sim1) for a
# post-PD release without timing simulation; the ATPG_POSTPD_EXIT timing-sim
# check then stays open.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
set STAGE_NAME "timing_sim"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc simulate {
    dft_write "$::REPORTS_DIR/timing_sim.log" "TIMING SIMULATION NOT RUN: SDF-annotated pattern simulation is not supported by the open-source DFT flow\n"
    error "timing_sim: SDF-annotated pattern simulation is not supported by the open-source flow — bypass timing_sim1 explicitly (cbflow run bypass --stages timing_sim1)"
}

dft_exec_all
exit
