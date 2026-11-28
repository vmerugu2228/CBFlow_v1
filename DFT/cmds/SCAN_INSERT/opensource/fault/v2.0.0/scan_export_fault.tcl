#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SCAN_INSERT — scan_export (opensource / tclsh)
# Scan deliverables under canonical names: scan.v (the checked scan netlist),
# scan.scandef + scan.json (chain order / clocks / enables), scan.sdc
# (scan-shift constraints from SYNTH).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SCAN_INSERT"
set STAGE_NAME "scan_export"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc load_design {
    set _chk "[cbflow_node_dir [oss_chain_node scan_check]]/outputs/scan_check.status"
    set _fh [open $_chk]; set _s [string trim [read $_fh]]; close $_fh
    if {$_s ne "PASS"} { error "scan_check status is '$_s' ($_chk) — nothing to export" }
    set ::stitch "[cbflow_node_dir [oss_chain_node scan_stitch]]/outputs"
}

flow_proc save_design {
    file copy -force [dft_input netlist] [oss_stage_out scan.v]
    file copy -force [dft_input sdc] [oss_stage_out scan.sdc]
    foreach _f {scan.scandef scan.json} { file copy -force "$::stitch/$_f" [oss_stage_out $_f] }
}

dft_exec_all
exit
