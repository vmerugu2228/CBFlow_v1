#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow M2_EXEC — compile (opensource / container tclsh -> verilator)
# The TB_SETUP testbench (input tb: the released tb.f) built by Verilator with
# coverage -> outputs/sim.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "M2_EXEC"
set STAGE_NAME "compile"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_flow_utils.tcl"

set design_name [oss_get flow design_name]
source "$::env(CBFLOW_DV_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dv_utils.tcl"

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"
flow_proc build {
    set _sim [dv_build m2_exec [oss_input tb] "$::WORK_DIR/build" "$::REPORTS_DIR/build.log"]
    file copy -force $_sim [oss_stage_out sim]
    handle_info "testbench built -> [oss_stage_out sim]"
}

oss_exec_all
exit
