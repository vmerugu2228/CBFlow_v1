#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — coverage_report (opensource / container tclsh)
# Coverage report: Atalanta's collapsed-fault statistics (fault coverage, test
# coverage = detected / (faults - proven redundant), aborted), the logic the
# scan cut leaves outside ATPG, the undetected faults, and the independent
# pin-fault simulation.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
set STAGE_NAME "coverage_report"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc report {
    global design_name
    set _pg "[cbflow_node_dir [oss_chain_node pattern_gen]]"
    set _fs "[cbflow_node_dir [oss_chain_node fault_sim]]/outputs/fault_sim.json"
    dft_py "$::REPORTS_DIR/coverage.log" coverage --log "$_pg/reports/atalanta.log" --map "$_pg/outputs/bench_map.json" \
        --design $design_name --ufaults "$_pg/outputs/atpg.ufaults" --fsim $_fs \
        -o "$::REPORTS_DIR/coverage.rpt" --json [oss_stage_out coverage.json]
    handle_info "test coverage [dft_report_value $::REPORTS_DIR/coverage.rpt {Test coverage}] %,\
                 fault coverage [dft_report_value $::REPORTS_DIR/coverage.rpt {Fault coverage}] %"
}

dft_exec_all
exit
