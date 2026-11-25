#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow M1_EXEC — cov_merge (opensource / container tclsh -> verilator_coverage)
# Coverage of the passing runs merged (verilator_coverage): code coverage of the
# DUT sources (rtl.f of the testbench), functional coverage (covergroup bins),
# vPlan closure up to M1 -> outputs/metrics.json, plan.csv, merged.dat,
# reports/coverage.rpt.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "M1_EXEC"
set STAGE_NAME "cov_merge"
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
flow_proc merge {
    dv_tool "$::REPORTS_DIR/covmerge.log" covmerge --results "[cbflow_node_dir [oss_chain_node regress]]/outputs/results.csv" \
        --dut-files {*}[dv_dut_files [oss_input tb]] --vplan [oss_input vplan] --milestone [oss_get m1_exec oss,milestone] \
        -o "$::WORK_DIR/cov" --report "$::REPORTS_DIR/coverage.rpt"
    foreach _f {metrics.json plan.csv merged.dat} { file copy -force "$::WORK_DIR/cov/$_f" [oss_stage_out $_f] }
    file copy -force [oss_stage_out plan.csv] "$::REPORTS_DIR/plan.csv"
    handle_info "code [oss_report_value $::REPORTS_DIR/coverage.rpt {Code coverage}], vPlan [oss_report_value $::REPORTS_DIR/coverage.rpt {vPlan coverage}]"
}

oss_exec_all
exit
