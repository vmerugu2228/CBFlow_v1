#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow M1_EXEC — regress (opensource / container tclsh -> testbench)
# Every vPlan test of the features up to M1 (cumulative) x m1_exec(oss,regress,seeds)
# seeds, m1_exec(oss,regress,jobs) in parallel -> outputs/results.csv,
# reports/regress.rpt; failing runs do not fail the stage (sign-off decides).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "M1_EXEC"
set STAGE_NAME "regress"
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
flow_proc regress {
    set _ms [oss_get m1_exec oss,milestone]
    dv_tool "$::REPORTS_DIR/tests.log" tests --vplan [oss_input vplan] --milestone $_ms -o "$::WORK_DIR/tests.txt"
    set _fh [open "$::WORK_DIR/tests.txt"]; set _tests [string trim [read $_fh]]; close $_fh
    dv_tool "$::REPORTS_DIR/regress.log" regress --sim "[cbflow_node_dir [oss_chain_node compile]]/outputs/sim" \
        --tests {*}$_tests --seeds [oss_get m1_exec oss,regress,seeds] --jobs [oss_get m1_exec oss,regress,jobs] \
        --timeout-s [oss_get m1_exec oss,sim,timeout_s] -o "$::WORK_DIR/regress"
    file copy -force "$::WORK_DIR/regress/results.csv" [oss_stage_out results.csv]
    dv_tool "$::REPORTS_DIR/runsum.log" runsum --results [oss_stage_out results.csv] \
        --title "$_ms regression — $::design_name" -o "$::REPORTS_DIR/regress.rpt"
    handle_info "[oss_report_value $::REPORTS_DIR/regress.rpt Runs]"
}

oss_exec_all
exit
