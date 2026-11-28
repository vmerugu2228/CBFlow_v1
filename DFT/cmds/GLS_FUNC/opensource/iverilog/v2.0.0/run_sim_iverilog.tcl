#!/usr/bin/env tclsh
# ═══════════════════════════════════════════════════════════════════════════════
# CBflow GLS_FUNC — run_sim (opensource / container tclsh → vvp)
# Run the simulation (vvp). Pass: gls_func(oss,pass_regex) in the log, no line
# matching gls_func(oss,fail_regex), $finish reached. Writes run_sim.status.
# ═══════════════════════════════════════════════════════════════════════════════

set run_dir $::env(CBFLOW_RUN_DIR)
source "$run_dir/.run.cbflow.tcl"
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/utils.tcl"

set FLOW_TYPE "GLS_FUNC"
set STAGE_NAME "run_sim"
set NODE_NAME [cbflow_node_name]

source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/config.tcl"
source "$run_dir/work/$FLOW_TYPE/$NODE_NAME/run/setup.tcl"
setup_dirs $run_dir $FLOW_TYPE $NODE_NAME
source "$::env(FLOW_DIR)/global/utils/utilities/$::env(UTILITIES_VERSION)/oss_utils.tcl"
source "$::env(CBFLOW_DFT_DIR)/utils/utilities/$::env(UTILITIES_VERSION)/oss_dft_utils.tcl"

set design_name [oss_get flow design_name]

if {![namespace exists ::flow]} { namespace eval ::flow { variable exec_mode "auto"; variable start_time [clock seconds]; variable flow_errors {} } }
set ::flow::exec_mode "auto"

flow_proc simulate {
    set _arr [oss_flow_arr]
    set _vvp "[cbflow_node_dir [oss_chain_node compile]]/outputs/sim.vvp"
    set _log "$::REPORTS_DIR/run_sim.log"
    set _rc [catch {dft_run $_log vvp -n $_vvp {*}[oss_get_opt $_arr oss,plusargs] +cbflow_vcd=[oss_stage_out sim.vcd]} _err]
    set _fh [open $_log]; set _t [read $_fh]; close $_fh
    set _fails {}
    if {$_rc} { lappend _fails "vvp exited with an error: [lindex [split $_err \n] 0]" }
    if {![regexp {\$finish called} $_t]} { lappend _fails "simulation did not reach \$finish" }
    if {![regexp -- [oss_get $_arr oss,pass_regex] $_t]} { lappend _fails "pass pattern '[oss_get $_arr oss,pass_regex]' not found" }
    set _bad [regexp -all -line -inline -- "^.*([oss_get $_arr oss,fail_regex]).*\$" $_t]
    if {[llength $_bad]} { lappend _fails "[expr {[llength $_bad] / 2}] line(s) match '[oss_get $_arr oss,fail_regex]', first: [string trim [lindex $_bad 0]]" }
    set _st [expr {[llength $_fails] ? "FAIL" : "PASS"}]
    set _l [list "Gate-level simulation — $::design_name ($::FLOW_TYPE)" "  Status : $_st"]
    foreach _x {Tests Errors Patterns Checks Mismatches} {
        if {[regexp -line "^$_x:\\s*(\\d+)" $_t -> _v]} { lappend _l [format "  %-7s: %s" $_x $_v] }
    }
    foreach _f $_fails { lappend _l "  FAIL: $_f" }
    dft_write "$::REPORTS_DIR/run_sim.rpt" "[join $_l \n]\n"
    dft_write [oss_stage_out run_sim.status] "$_st\n"
    if {$_st ne "PASS"} { error "gate-level simulation FAILED: [join $_fails {; }] — $_log" }
    handle_info "gate-level simulation PASS"
}

dft_exec_all
exit
