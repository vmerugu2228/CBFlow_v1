#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — init_atpg (opensource / container tclsh)
# Read the netlist ATPG runs on (pd_phase pre: the SCAN_INSERT release; post:
# the PNR release): scan cells from the liberty, the netlist as Yosys JSON, a
# cell census, the scan chains traced on THIS netlist (same flops as the
# SCAN_INSERT scandef; a reorder is reported and followed), macro stubs
# (outputs held 0 — the ATPG model of memories / child blocks). Writes the
# pd_phase decision (outputs/decision_outcome.txt).
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
set STAGE_NAME "init_atpg"
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
    set ::netlist [dft_input netlist]
    set ::scandef_ref [dft_input scandef]
    set ::libs [dft_libs init_atpg]
    set ::pd_phase [oss_get atpg pd_phase]
    if {$::pd_phase ni {pre post}} { error "atpg(pd_phase) must be pre or post, got '$::pd_phase'" }
    handle_info "pd_phase $::pd_phase — netlist $::netlist"
}

flow_proc read_design {
    global design_name
    dft_py "$::REPORTS_DIR/cells.log" cells {*}[concat {*}[lmap _l $::libs {list --lib $_l}]] -o [oss_stage_out cells.json]
    dft_netlist_json $::netlist $design_name $::libs [oss_stage_out netlist.json] "$::REPORTS_DIR/netlist_json.log"
    dft_py "$::REPORTS_DIR/census.log" census --json [oss_stage_out netlist.json] --top $design_name \
        --cells [oss_stage_out cells.json] --scan-in [oss_get project dft,scan_in_pattern] \
        --scan-enable [oss_get project dft,scan_enable_pattern] -o "$::REPORTS_DIR/census.rpt"
    if {[dft_report_value "$::REPORTS_DIR/census.rpt" "Scan flops"] == 0} {
        error "$design_name netlist has no scan flops — ATPG needs a full-scan netlist (SYNTH with project(dft,enable))"
    }
}

flow_proc trace_chains {
    global design_name
    dft_py "$::REPORTS_DIR/trace.log" trace --json [oss_stage_out netlist.json] --top $design_name \
        --cells [oss_stage_out cells.json] \
        --scan-in [oss_get project dft,scan_in_pattern] --scan-out [oss_get project dft,scan_out_pattern] \
        --scan-enable [oss_get project dft,scan_enable_pattern] \
        --max-length [oss_get project dft,max_chain_length] --clock-mixing [oss_get project dft,clock_mixing] \
        -o [oss_stage_out scan.json] --scandef [oss_stage_out scan.scandef] --report "$::REPORTS_DIR/scan_chains.rpt"
    set _v [dft_report_value "$::REPORTS_DIR/scan_chains.rpt" Violations]
    if {$_v > 0} { error "$_v scan rule violation(s) on the ATPG netlist — $::REPORTS_DIR/scan_chains.rpt" }
    set _ref [dft_scandef_chains $::scandef_ref]
    set _cur [dft_scandef_chains [oss_stage_out scan.scandef]]
    if {[lsort [concat {*}$_ref]] ne [lsort [concat {*}$_cur]]} {
        error "scan flops of this netlist differ from the SCAN_INSERT scandef ($::scandef_ref)"
    } elseif {$_ref ne $_cur} {
        handle_warning "chain order differs from the SCAN_INSERT scandef (reordered after insertion) — patterns follow this netlist's chains"
    } else {
        handle_info "chains match the SCAN_INSERT scandef ([llength $_cur] chain(s))"
    }
    set ::scan_clock [dft_scan_clock "$::REPORTS_DIR/scan_chains.rpt"]
    dft_py "$::REPORTS_DIR/stubs.log" stubs --json [oss_stage_out netlist.json] --top $design_name \
        --cells [oss_stage_out cells.json] -o [oss_stage_out macro_stubs.v]
}

flow_proc decide {
    dft_write [oss_stage_out decision_outcome.txt] "$::pd_phase\n"
}

dft_exec_all
exit
