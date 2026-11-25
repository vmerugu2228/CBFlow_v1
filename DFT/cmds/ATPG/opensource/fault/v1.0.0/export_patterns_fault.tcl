#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — export_patterns (opensource / container tclsh)
# Patterns on the real chains: each Atalanta vector split into scan loads
# (pseudo inputs = flop states, in the traced chain order with the
# inversions between flops undone), primary-input values and expected primary
# outputs / unloads. Writes patterns.json, a STIL-style pattern file and a
# self-checking serial-scan testbench (shift / capture / unload over the top
# ports only — it runs on any netlist with the same chains).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
set STAGE_NAME "export_patterns"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc export {
    global design_name
    set _init "[cbflow_node_dir [oss_chain_node init_atpg]]/outputs"
    set _pg "[cbflow_node_dir [oss_chain_node pattern_gen]]/outputs"
    set _holds {}
    foreach _h [dft_holds atpg] { lappend _holds --hold $_h }
    dft_py "$::REPORTS_DIR/patterns.log" patterns --test "$_pg/atpg.test" --map "$_pg/bench_map.json" \
        --scan "$_init/scan.json" --top $design_name {*}$_holds -o [oss_stage_out patterns.json] \
        --stil [oss_stage_out patterns.stil] --tb [oss_stage_out scan_tb.v] --tb-name cbflow_scan_tb
    file copy -force "$_init/macro_stubs.v" [oss_stage_out macro_stubs.v]
}

dft_exec_all
exit
