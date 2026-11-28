#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow ATPG — signoff (opensource / container tclsh)
# Pattern sign-off: test / fault coverage against project(dft,atpg,
# test_coverage_min|fault_coverage_min), zero-delay simulation 0 mismatches
# (and timing simulation when it ran); signoff.rpt + delivery manifest.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "ATPG"
set STAGE_NAME "signoff"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc signoff {
    global design_name
    set _cov "[cbflow_node_dir [oss_chain_node coverage_report]]/reports/coverage.rpt"
    set _tc [dft_report_value $_cov {Test coverage}]
    set _fc [dft_report_value $_cov {Fault coverage}]
    set _np [dft_report_value $_cov Patterns]
    set _tmin [oss_get project dft,atpg,test_coverage_min]
    set _fmin [oss_get project dft,atpg,fault_coverage_min]
    set _zd "[cbflow_node_dir [oss_chain_node zd_pattern_sim]]/outputs/zd_sim.status"
    set _fh [open $_zd]; set _zds [string trim [read $_fh]]; close $_fh
    set _fails {}
    if {$_tc < $_tmin} { lappend _fails "test coverage $_tc % < $_tmin %" }
    if {$_fc < $_fmin} { lappend _fails "fault coverage $_fc % < $_fmin %" }
    if {$_zds ne "PASS"} { lappend _fails "zero-delay pattern simulation $_zds" }
    set _st [expr {[llength $_fails] ? "FAIL" : "PASS"}]
    set _l [list "ATPG pattern sign-off — $design_name (pd_phase [oss_get atpg pd_phase])" \
                 "  Patterns          : $_np" \
                 "  Test coverage     : $_tc % (min $_tmin %)" \
                 "  Fault coverage    : $_fc % (min $_fmin %)" \
                 "  Zero-delay sim    : $_zds" \
                 "  Status            : $_st"]
    foreach _f $_fails { lappend _l "  FAIL: $_f" }
    dft_write "$::REPORTS_DIR/signoff.rpt" "[join $_l \n]\n"
    # delivery manifest: the pattern deliverables with sizes
    set _ex "[cbflow_node_dir [oss_chain_node export_patterns]]/outputs"
    set _items {}
    foreach _f {patterns.stil patterns.json scan_tb.v macro_stubs.v} {
        lappend _items "    \{\"file\": \"$_ex/$_f\", \"bytes\": [file size $_ex/$_f]\}"
    }
    dft_write [oss_stage_out delivery/MANIFEST.json] "\{\n  \"design\": \"$design_name\",\n  \"status\": \"$_st\",\n  \"patterns\": $_np,\n  \"test_coverage_pct\": $_tc,\n  \"fault_coverage_pct\": $_fc,\n  \"files\": \[\n[join $_items ,\n]\n  \]\n\}\n"
    dft_write [oss_stage_out signoff.status] "$_st\n"
    if {$_st ne "PASS"} { error "ATPG sign-off FAILED: [join $_fails {; }]" }
    handle_info "ATPG sign-off PASS: $_np patterns, test coverage $_tc %, fault coverage $_fc %"
}

dft_exec_all
exit
