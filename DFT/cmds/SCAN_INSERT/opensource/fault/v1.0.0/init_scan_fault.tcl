#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SCAN_INSERT — init_scan (opensource / container tclsh)
# Read the scan netlist the SYNTH release staged: the scan cells of the
# library (liberty test_cell: scan in / enable / out pins), the netlist as
# Yosys JSON (library cells / macros blackboxed), and a cell census. A netlist
# without scan flops stops here — SYNTH ran with project(dft,enable) false.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SCAN_INSERT"
set STAGE_NAME "init_scan"
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
    global design_name
    set ::netlist [dft_input netlist]
    set ::libs [dft_libs $::STAGE_NAME]
    handle_info "Netlist: $::netlist"
    handle_info "Liberty: $::libs"
}

flow_proc read_cells {
    dft_py "$::REPORTS_DIR/cells.log" cells {*}[concat {*}[lmap _l $::libs {list --lib $_l}]] -o [oss_stage_out cells.json]
    dft_netlist_json $::netlist $::design_name $::libs [oss_stage_out netlist.json] "$::REPORTS_DIR/netlist_json.log"
}

flow_proc report {
    global design_name
    dft_py "$::REPORTS_DIR/census.log" census --json [oss_stage_out netlist.json] --top $design_name \
        --cells [oss_stage_out cells.json] --scan-in [oss_get project dft,scan_in_pattern] \
        --scan-enable [oss_get project dft,scan_enable_pattern] -o "$::REPORTS_DIR/census.rpt"
    set _scan [dft_report_value "$::REPORTS_DIR/census.rpt" "Scan flops"]
    set _seq  [dft_report_value "$::REPORTS_DIR/census.rpt" "Sequential cells"]
    handle_info "$design_name: $_scan scan flops of $_seq sequential cells"
    if {$_scan == 0} {
        error "$design_name has no scan flops — the SYNTH release was built with project(dft,enable) false (or no scan cells mapped); re-run SYNTH with DFT on"
    }
    if {[dft_report_value "$::REPORTS_DIR/census.rpt" "Scan-in ports"] == 0} {
        error "$design_name has no scan-in port matching project(dft,scan_in_pattern) '[oss_get project dft,scan_in_pattern]'"
    }
    # the scan-shift SDC SYNTH writes beside a scan netlist
    if {[catch {dft_input sdc} _e]} { error "scan SDC not staged — $_e (the SYNTH release carries sdc/${design_name}.scan.sdc when DFT is on)" }
}

dft_exec_all
exit
