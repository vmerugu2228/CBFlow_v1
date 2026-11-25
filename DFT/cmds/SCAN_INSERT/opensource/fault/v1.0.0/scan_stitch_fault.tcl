#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow SCAN_INSERT — scan_stitch (opensource / container tclsh)
# The chains SYNTH stitched, traced through the netlist: scan-in port →
# (buffers / inverters) → scan flop scan-in pin → its Q / QN → … → scan-out
# (a scan_out port, or the functional output the inserter reused). Per chain:
# order, length, inversions, clock port + edge, scan-enable port; unscanned
# flops; DFT-rule violations. Writes the scandef + chain map (scan.json).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "SCAN_INSERT"
set STAGE_NAME "scan_stitch"
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
    set ::init "[cbflow_node_dir [oss_chain_node init_scan]]/outputs"
}

flow_proc trace_chains {
    global design_name
    dft_py "$::REPORTS_DIR/trace.log" trace --json "$::init/netlist.json" --top $design_name \
        --cells "$::init/cells.json" \
        --scan-in [oss_get project dft,scan_in_pattern] \
        --scan-out [oss_get project dft,scan_out_pattern] \
        --scan-enable [oss_get project dft,scan_enable_pattern] \
        --max-length [oss_get project dft,max_chain_length] \
        --clock-mixing [oss_get project dft,clock_mixing] \
        -o [oss_stage_out scan.json] --scandef [oss_stage_out scan.scandef] \
        --report "$::REPORTS_DIR/scan_chains.rpt"
}

# The SYNTH scandef (the inserter's view) must describe the traced chains:
# same chains, same flops, same scan-in -> scan-out order
flow_proc check_scandef {
    set _ref [dft_scandef_chains [dft_input scandef]]
    set _cur [dft_scandef_chains [oss_stage_out scan.scandef]]
    if {[lsort [concat {*}$_ref]] ne [lsort [concat {*}$_cur]]} {
        error "SYNTH scandef ([dft_input scandef]) and the netlist's chains have different scan flops"
    }
    if {$_ref ne $_cur} {
        error "SYNTH scandef ([dft_input scandef]) orders the chains differently from the netlist (scan-in -> scan-out)"
    }
    handle_info "SYNTH scandef matches the traced chains ([llength $_cur] chain(s))"
}

flow_proc report {
    set _r "$::REPORTS_DIR/scan_chains.rpt"
    handle_info "chains [dft_report_value $_r chains], scanned [dft_report_value $_r {scanned flops}] of\
                 [dft_report_value $_r {sequential cells}], violations [dft_report_value $_r Violations]"
}

dft_exec_all
exit
